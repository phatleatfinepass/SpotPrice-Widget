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

    static func install(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String,
        containingAppURL: URL
    ) async throws -> String {
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

        try fileManager.copyItem(at: sourceApp, to: stagedApp)
        do {
            try validateApp(stagedApp, expectedVersion: expectedVersion)
            try fileManager.moveItem(at: currentApp, to: backupApp)
            try fileManager.moveItem(at: stagedApp, to: currentApp)
        } catch {
            try? fileManager.removeItem(at: stagedApp)
            if fileManager.fileExists(atPath: backupApp.path),
               !fileManager.fileExists(atPath: currentApp.path) {
                try? fileManager.moveItem(at: backupApp, to: currentApp)
            }
            throw error
        }

        do {
            let runningApplication = try await launchNewInstance(at: currentApp)
            try await Task.sleep(for: .seconds(3))
            guard !runningApplication.isTerminated,
                  runningApplication.bundleURL.map(UninstallTarget.canonical) == UninstallTarget.canonical(currentApp)
            else {
                throw UpdateInstallError.updatedApplicationDidNotLaunch
            }
            try fileManager.removeItem(at: backupApp)
            return expectedVersion
        } catch {
            if fileManager.fileExists(atPath: currentApp.path) {
                try? fileManager.moveItem(at: currentApp, to: failedApp)
            }
            if fileManager.fileExists(atPath: backupApp.path) {
                try? fileManager.moveItem(at: backupApp, to: currentApp)
            }
            try? fileManager.removeItem(at: failedApp)
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

    private static func launchNewInstance(at appURL: URL) async throws -> NSRunningApplication {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
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
