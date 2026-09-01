import AppKit
import Foundation
import Security

enum UpdateInstallError: LocalizedError {
    case invalidVersion
    case versionMismatch
    case downgradeRejected
    case invalidSignature
    case invalidDiskImage
    case missingApplication
    case invalidApplication
    case invalidCodeSignature(OSStatus)
    case destinationUnavailable
    case replacementFailed
    case widgetRegistrationFailed
    case updatedApplicationDidNotLaunch

    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            "The update version is invalid."
        case .versionMismatch:
            "The signed update does not contain the expected version."
        case .downgradeRejected:
            "The update is not newer than the installed version."
        case .invalidSignature:
            "The update does not have a valid project signature."
        case .invalidDiskImage:
            "The signed update disk image could not be mounted safely."
        case .missingApplication:
            "The signed update does not contain Finland Electricity Rates."
        case .invalidApplication:
            "The signed update contains an invalid application bundle."
        case .invalidCodeSignature(let status):
            "The updated app failed its complete code-signature check (\(status))."
        case .destinationUnavailable:
            "The current installation folder is not writable."
        case .replacementFailed:
            "The current app could not be replaced; the previous version was restored."
        case .widgetRegistrationFailed:
            "The updated app’s widget could not be registered; the previous version was restored."
        case .updatedApplicationDidNotLaunch:
            "The updated app did not stay open; the previous version was restored."
        }
    }
}

struct UpdateVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

enum UpdateInstaller {
    private static let appName = "Finland Electricity Rates.app"

    struct PreparedUpdate {
        let expectedVersion: String
        let currentApp: URL
        let stagedApp: URL
        let backupApp: URL
        let failedApp: URL
    }

    static func prepare(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String,
        containingAppURL: URL
    ) throws -> PreparedUpdate {
        try UpdateTrust.verify(diskImageData, signatureText: signatureText)

        guard let expected = UpdateVersion(expectedVersion) else {
            throw UpdateInstallError.invalidVersion
        }
        let currentApp = try UninstallTarget.validatedAppURL(containingAppURL)
        guard let currentVersionText = Bundle(url: currentApp)?
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let currentVersion = UpdateVersion(currentVersionText),
              expected > currentVersion
        else {
            throw UpdateInstallError.downgradeRejected
        }

        let fileManager = FileManager.default
        let workRoot = fileManager.temporaryDirectory
            .appendingPathComponent("finland-electricity-update-\(UUID().uuidString)", isDirectory: true)
        let diskImageURL = workRoot.appendingPathComponent("update.dmg")
        let mountURL = workRoot.appendingPathComponent("mount", isDirectory: true)
        try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workRoot) }
        try diskImageData.write(to: diskImageURL, options: [.atomic, .completeFileProtection])

        try runHdiutil(["attach", diskImageURL.path, "-nobrowse", "-readonly", "-mountpoint", mountURL.path, "-quiet"])
        defer { try? runHdiutil(["detach", mountURL.path, "-quiet"]) }

        let sourceApp = mountURL.appendingPathComponent(appName, isDirectory: true)
        guard fileManager.fileExists(atPath: sourceApp.path) else {
            throw UpdateInstallError.missingApplication
        }
        try validateApp(sourceApp, expectedVersion: expectedVersion)

        let parent = currentApp.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.destinationUnavailable
        }

        let transactionID = UUID().uuidString
        let stagedApp = parent.appendingPathComponent(".Finland Electricity Rates.update-\(transactionID).app")
        let backupApp = parent.appendingPathComponent(".Finland Electricity Rates.backup-\(transactionID).app")
        let failedApp = parent.appendingPathComponent(".Finland Electricity Rates.failed-\(transactionID).app")

        do {
            try fileManager.copyItem(at: sourceApp, to: stagedApp)
            try validateApp(stagedApp, expectedVersion: expectedVersion)
        } catch {
            try? fileManager.removeItem(at: stagedApp)
            throw error
        }

        return PreparedUpdate(
            expectedVersion: expectedVersion,
            currentApp: currentApp,
            stagedApp: stagedApp,
            backupApp: backupApp,
            failedApp: failedApp
        )
    }

    static func commit(
        _ prepared: PreparedUpdate,
        callerProcessIdentifier: pid_t
    ) async throws -> String {
        let fileManager = FileManager.default

        do {
            try await UpdateHostLifecycle.waitForExit(processIdentifier: callerProcessIdentifier)
        } catch {
            try? fileManager.removeItem(at: prepared.stagedApp)
            throw error
        }

        do {
            try? UpdateRegistration.unregister(appURL: prepared.currentApp)
            try fileManager.moveItem(at: prepared.currentApp, to: prepared.backupApp)
            try fileManager.moveItem(at: prepared.stagedApp, to: prepared.currentApp)
        } catch {
            try? fileManager.removeItem(at: prepared.stagedApp)
            if fileManager.fileExists(atPath: prepared.backupApp.path),
               !fileManager.fileExists(atPath: prepared.currentApp.path) {
                try? fileManager.moveItem(at: prepared.backupApp, to: prepared.currentApp)
                try? UpdateRegistration.register(appURL: prepared.currentApp)
            }
            throw UpdateInstallError.replacementFailed
        }

        do {
            try UpdateRegistration.register(appURL: prepared.currentApp)
            let runningApplication = try await launchApplication(at: prepared.currentApp)
            try await Task.sleep(for: .seconds(3))
            guard !runningApplication.isTerminated,
                  runningApplication.bundleURL.map(UninstallTarget.canonical)
                    == UninstallTarget.canonical(prepared.currentApp)
            else {
                throw UpdateInstallError.updatedApplicationDidNotLaunch
            }
            try UpdateRegistration.verify(appURL: prepared.currentApp)
            try fileManager.removeItem(at: prepared.backupApp)
            return prepared.expectedVersion
        } catch {
            try? UpdateRegistration.unregister(appURL: prepared.currentApp)
            if fileManager.fileExists(atPath: prepared.currentApp.path) {
                try? fileManager.moveItem(at: prepared.currentApp, to: prepared.failedApp)
            }
            if fileManager.fileExists(atPath: prepared.backupApp.path) {
                try? fileManager.moveItem(at: prepared.backupApp, to: prepared.currentApp)
                try? UpdateRegistration.register(appURL: prepared.currentApp)
                _ = try? await launchApplication(at: prepared.currentApp)
            }
            try? fileManager.removeItem(at: prepared.failedApp)
            throw error
        }
    }

    private static func validateApp(_ appURL: URL, expectedVersion: String) throws {
        guard appURL.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == UninstallTarget.hostBundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion
        else {
            throw UpdateInstallError.versionMismatch
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(appURL as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw UpdateInstallError.invalidCodeSignature(createStatus)
        }
        let rawFlags = kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
        let status = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: rawFlags), nil)
        guard status == errSecSuccess else {
            throw UpdateInstallError.invalidCodeSignature(status)
        }
    }

    private static func runHdiutil(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw UpdateInstallError.invalidDiskImage
        }
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.invalidDiskImage
        }
    }

    private static func launchApplication(at appURL: URL) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = false
        configuration.activates = true

        return try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { app, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: UpdateInstallError.updatedApplicationDidNotLaunch)
                }
            }
        }
    }
}

private enum UpdateRegistration {
    private static let widgetBundleIdentifier =
        "personal.SpotPriceWidget.SpotPriceWidgetFinland"
    private static let extensionRelativePath =
        "Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
    private static let launchServicesTool = URL(
        fileURLWithPath:
            "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    )
    private static let pluginKitTool = URL(fileURLWithPath: "/usr/bin/pluginkit")

    static func unregister(appURL: URL) throws {
        let extensionURL = appURL.appendingPathComponent(extensionRelativePath, isDirectory: true)
        _ = try? run(pluginKitTool, arguments: ["-r", extensionURL.path])
        _ = try? run(launchServicesTool, arguments: ["-u", appURL.path])
    }

    static func register(appURL: URL) throws {
        let extensionURL = appURL.appendingPathComponent(extensionRelativePath, isDirectory: true)
        guard let extensionBundle = Bundle(url: extensionURL),
              extensionBundle.bundleIdentifier == widgetBundleIdentifier
        else {
            throw UpdateInstallError.widgetRegistrationFailed
        }

        let canonicalExtension = UninstallTarget.canonical(extensionURL)
        let registeredPaths = try registeredExtensionPaths()
        for registeredPath in registeredPaths {
            let registeredURL = UninstallTarget.canonical(URL(fileURLWithPath: registeredPath))
            guard registeredURL != canonicalExtension else { continue }
            _ = try? run(pluginKitTool, arguments: ["-r", registeredURL.path])

            let competingApp = registeredURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if Bundle(url: competingApp)?.bundleIdentifier == UninstallTarget.hostBundleIdentifier {
                _ = try? run(launchServicesTool, arguments: ["-u", competingApp.path])
            }
        }

        _ = try run(launchServicesTool, arguments: ["-f", "-R", appURL.path])
        _ = try run(pluginKitTool, arguments: ["-a", extensionURL.path])
        try verify(appURL: appURL)
    }

    static func verify(appURL: URL) throws {
        let expected = UninstallTarget.canonical(
            appURL.appendingPathComponent(extensionRelativePath, isDirectory: true)
        )

        for _ in 0..<12 {
            let registered = try registeredExtensionPaths()
                .map { UninstallTarget.canonical(URL(fileURLWithPath: $0)) }
            if registered.contains(expected) {
                return
            }
            Thread.sleep(forTimeInterval: 0.15)
        }
        throw UpdateInstallError.widgetRegistrationFailed
    }

    private static func registeredExtensionPaths() throws -> [String] {
        let output = try run(
            pluginKitTool,
            arguments: ["-m", "-A", "-D", "-v", "-i", widgetBundleIdentifier],
            captureOutput: true
        )
        return WidgetRegistrationPaths.extensionPaths(from: output)
    }

    @discardableResult
    private static func run(
        _ executableURL: URL,
        arguments: [String],
        captureOutput: Bool = false
    ) throws -> String {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = captureOutput ? outputPipe : FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw UpdateInstallError.widgetRegistrationFailed
        }
        guard process.terminationStatus == 0 else {
            throw UpdateInstallError.widgetRegistrationFailed
        }
        guard captureOutput else { return "" }
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
