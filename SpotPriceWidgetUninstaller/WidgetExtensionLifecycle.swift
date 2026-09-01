import Darwin
import Foundation

enum WidgetExtensionLifecycleError: LocalizedError {
    case processDidNotExit

    var errorDescription: String? {
        switch self {
        case .processDidNotExit:
            "The previous widget extension could not be stopped safely."
        }
    }
}

enum WidgetExtensionLifecycle {
    private static let extensionExecutableRelativePath =
        "Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex/Contents/MacOS/SpotPriceWidgetFinlandExtension"

    static func terminateRunningExtension(
        in appURL: URL,
        timeout: TimeInterval = 3,
        pollInterval: TimeInterval = 0.05
    ) async throws {
        let executableURL = expectedExecutableURL(in: appURL)
        var processIdentifiers = runningProcessIdentifiers(matching: executableURL)
        guard !processIdentifiers.isEmpty else { return }

        signal(processIdentifiers, with: SIGTERM)
        processIdentifiers = try await waitForExit(
            matching: executableURL,
            timeout: timeout,
            pollInterval: pollInterval
        )
        guard !processIdentifiers.isEmpty else { return }

        // Widget extensions are disposable system-managed processes. Escalate
        // only for the exact executable embedded in the validated app bundle.
        signal(processIdentifiers, with: SIGKILL)
        processIdentifiers = try await waitForExit(
            matching: executableURL,
            timeout: 1,
            pollInterval: pollInterval
        )
        guard processIdentifiers.isEmpty else {
            throw WidgetExtensionLifecycleError.processDidNotExit
        }
    }

    static func expectedExecutableURL(in appURL: URL) -> URL {
        canonical(appURL.appendingPathComponent(extensionExecutableRelativePath))
    }

    static func matches(
        processExecutablePath: String,
        expectedExecutableURL: URL
    ) -> Bool {
        canonical(URL(fileURLWithPath: processExecutablePath)) == canonical(expectedExecutableURL)
    }

    private static func waitForExit(
        matching executableURL: URL,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async throws -> [pid_t] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))

        while clock.now < deadline {
            let remaining = runningProcessIdentifiers(matching: executableURL)
            if remaining.isEmpty { return [] }
            let nanoseconds = UInt64(max(pollInterval, 0.01) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        return runningProcessIdentifiers(matching: executableURL)
    }

    private static func signal(_ processIdentifiers: [pid_t], with value: Int32) {
        for processIdentifier in processIdentifiers where processIdentifier > 1 {
            if kill(processIdentifier, value) != 0, errno != ESRCH {
                continue
            }
        }
    }

    private static func runningProcessIdentifiers(matching executableURL: URL) -> [pid_t] {
        allProcessIdentifiers().filter { processIdentifier in
            guard let path = executablePath(for: processIdentifier) else { return false }
            return matches(
                processExecutablePath: path,
                expectedExecutableURL: executableURL
            )
        }
    }

    private static func allProcessIdentifiers() -> [pid_t] {
        let estimatedCount = proc_listallpids(nil, 0)
        guard estimatedCount > 0 else { return [] }

        var processIdentifiers = [pid_t](
            repeating: 0,
            count: Int(estimatedCount) + 32
        )
        let actualCount = processIdentifiers.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard actualCount > 0 else { return [] }
        return Array(processIdentifiers.prefix(Int(actualCount))).filter { $0 > 1 }
    }

    private static func executablePath(for processIdentifier: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = buffer.withUnsafeMutableBufferPointer { pointer in
            proc_pidpath(processIdentifier, pointer.baseAddress, UInt32(pointer.count))
        }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
