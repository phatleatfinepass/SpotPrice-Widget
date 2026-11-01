import Darwin
import Foundation

enum WidgetExtensionLifecycleError: LocalizedError {
    case processDidNotExit
    case unknownProcessIdentity

    var errorDescription: String? {
        switch self {
        case .processDidNotExit:
            "The previous widget extension could not be stopped safely."
        case .unknownProcessIdentity:
            "The widget process could not be identified safely."
        }
    }
}

enum WidgetExtensionLifecycle {
    private static let extensionExecutableRelativePath =
        "Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex/Contents/MacOS/SpotPriceWidgetFinlandExtension"

    static func terminateRunningExtension(
        in appURL: URL,
        predatingHost hostPID: pid_t? = nil,
        timeout: TimeInterval = 3,
        pollInterval: TimeInterval = 0.05
    ) async throws {
        let executableURL = expectedExecutableURL(in: appURL)
        // During an incoming legacy update, a process started with or after the
        // authenticated new host is already current. Preserve it, including
        // replacements WidgetKit spawns while an earlier process is exiting.
        let cutoff = try hostPID.map { pid -> UInt64 in
            guard let info = processInfo(pid), info.pbi_uid == geteuid() else {
                throw WidgetExtensionLifecycleError.unknownProcessIdentity
            }
            return startTime(info)
        }
        var processIdentifiers = try runningProcessIdentifiers(matching: executableURL, before: cutoff)
        guard !processIdentifiers.isEmpty else { return }

        try signal(processIdentifiers, with: SIGTERM, matching: executableURL, before: cutoff)
        processIdentifiers = try await waitForExit(
            matching: executableURL,
            before: cutoff,
            timeout: timeout,
            pollInterval: pollInterval
        )
        guard !processIdentifiers.isEmpty else { return }

        // Widget extensions are disposable system-managed processes. Escalate
        // only for the exact executable embedded in the validated app bundle.
        try signal(processIdentifiers, with: SIGKILL, matching: executableURL, before: cutoff)
        processIdentifiers = try await waitForExit(
            matching: executableURL,
            before: cutoff,
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
        before cutoff: UInt64?,
        timeout: TimeInterval,
        pollInterval: TimeInterval
    ) async throws -> [pid_t] {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))

        while clock.now < deadline {
            let remaining = try runningProcessIdentifiers(matching: executableURL, before: cutoff)
            if remaining.isEmpty { return [] }
            let nanoseconds = UInt64(max(pollInterval, 0.01) * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        return try runningProcessIdentifiers(matching: executableURL, before: cutoff)
    }

    private static func signal(
        _ pids: [pid_t], with value: Int32, matching executableURL: URL, before cutoff: UInt64?
    ) throws {
        for pid in pids where pid > 1 {
            // Recheck at signal time: a selected PID may have exited or been reused.
            guard try eligible(pid, executableURL: executableURL, before: cutoff) else { continue }
            _ = kill(pid, value)
        }
    }

    private static func runningProcessIdentifiers(matching executableURL: URL, before cutoff: UInt64?) throws -> [pid_t] {
        try allProcessIdentifiers().filter { try eligible($0, executableURL: executableURL, before: cutoff) }
    }

    private static func eligible(_ pid: pid_t, executableURL: URL, before cutoff: UInt64?) throws -> Bool {
        guard let path = executablePath(for: pid),
              matches(processExecutablePath: path, expectedExecutableURL: executableURL) else { return false }
        guard let info = processInfo(pid) else {
            if kill(pid, 0) != 0 && errno == ESRCH { return false }
            throw WidgetExtensionLifecycleError.unknownProcessIdentity
        }
        guard info.pbi_uid == geteuid() else { return false }
        return cutoff.map { startTime(info) < $0 } ?? true
    }

    private static func processInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    private static func startTime(_ info: proc_bsdinfo) -> UInt64 {
        info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec
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
