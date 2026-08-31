import Foundation

enum UninstallTargetError: LocalizedError {
    case invalidServiceLocation
    case invalidApplication
    case missingApplication

    var errorDescription: String? {
        switch self {
        case .invalidServiceLocation:
            "The uninstall helper is not embedded in the expected application."
        case .invalidApplication:
            "The containing application could not be verified."
        case .missingApplication:
            "The containing application no longer exists on disk."
        }
    }
}

enum UninstallTarget {
    static let hostBundleIdentifier = "personal.SpotPriceWidget"
    static let serviceBundleIdentifier = "personal.SpotPriceWidget.Uninstaller"

    static func containingAppURL(
        serviceBundleURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let serviceURL = canonical(serviceBundleURL)
        guard serviceURL.pathExtension.lowercased() == "xpc",
              serviceURL.lastPathComponent == "SpotPriceWidgetUninstaller.xpc",
              serviceURL.deletingLastPathComponent().lastPathComponent == "XPCServices",
              serviceURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Contents"
        else {
            throw UninstallTargetError.invalidServiceLocation
        }

        let appURL = serviceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try validatedAppURL(appURL, fileManager: fileManager)
    }

    static func validatedAppURL(
        _ appURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let appURL = canonical(appURL)
        guard appURL.pathExtension.lowercased() == "app",
              Bundle(url: appURL)?.bundleIdentifier == hostBundleIdentifier
        else {
            throw UninstallTargetError.invalidApplication
        }
        guard fileManager.fileExists(atPath: appURL.path) else {
            throw UninstallTargetError.missingApplication
        }
        return appURL
    }

    static func enclosingApplicationURL(for codeURL: URL) -> URL? {
        var candidate = canonical(codeURL)
        while candidate.path != "/" {
            if candidate.pathExtension.lowercased() == "app" {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }
        return nil
    }

    static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}
