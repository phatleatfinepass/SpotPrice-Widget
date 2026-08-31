import Darwin
import Foundation
import Security

enum UninstallSecurityError: LocalizedError {
    case wrongUser
    case invalidProcess
    case unsignedCaller(OSStatus)
    case invalidCaller(OSStatus)
    case missingStaticCode(OSStatus)
    case missingSigningInformation(OSStatus)
    case wrongSigningIdentifier
    case missingCodePath(OSStatus)
    case wrongCodePath

    var errorDescription: String? {
        switch self {
        case .wrongUser:
            "The uninstall request came from another user."
        case .invalidProcess:
            "The uninstall request did not identify a valid process."
        case .unsignedCaller(let status):
            "The uninstall caller could not be inspected (\(status))."
        case .invalidCaller(let status):
            "The uninstall caller failed code-signing validation (\(status))."
        case .missingStaticCode(let status):
            "The uninstall caller’s static code could not be inspected (\(status))."
        case .missingSigningInformation(let status):
            "The uninstall caller’s signing identity could not be read (\(status))."
        case .wrongSigningIdentifier:
            "The uninstall caller is not Finland Electricity Rates."
        case .missingCodePath(let status):
            "The uninstall caller’s application path could not be read (\(status))."
        case .wrongCodePath:
            "The uninstall caller is not the copy that contains this helper."
        }
    }
}

enum UninstallSecurity {
    static func validate(connection: NSXPCConnection, containingAppURL: URL) throws {
        guard connection.effectiveUserIdentifier == geteuid() else {
            throw UninstallSecurityError.wrongUser
        }
        guard connection.processIdentifier > 0 else {
            throw UninstallSecurityError.invalidProcess
        }

        var guestCode: SecCode?
        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: connection.processIdentifier),
        ] as CFDictionary
        let guestStatus = SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            SecCSFlags(),
            &guestCode
        )
        guard guestStatus == errSecSuccess, let guestCode else {
            throw UninstallSecurityError.unsignedCaller(guestStatus)
        }

        let validityStatus = SecCodeCheckValidity(guestCode, SecCSFlags(), nil)
        guard validityStatus == errSecSuccess else {
            throw UninstallSecurityError.invalidCaller(validityStatus)
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(guestCode, SecCSFlags(), &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw UninstallSecurityError.missingStaticCode(staticStatus)
        }

        var signingInformation: CFDictionary?
        let signingStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(),
            &signingInformation
        )
        guard signingStatus == errSecSuccess,
              let signingInformation = signingInformation as? [String: Any]
        else {
            throw UninstallSecurityError.missingSigningInformation(signingStatus)
        }
        guard signingInformation[kSecCodeInfoIdentifier as String] as? String == UninstallTarget.hostBundleIdentifier else {
            throw UninstallSecurityError.wrongSigningIdentifier
        }

        var codePath: CFURL?
        let pathStatus = SecCodeCopyPath(staticCode, SecCSFlags(), &codePath)
        guard pathStatus == errSecSuccess, let codePath else {
            throw UninstallSecurityError.missingCodePath(pathStatus)
        }
        let callerURL = codePath as URL
        guard let callerAppURL = UninstallTarget.enclosingApplicationURL(for: callerURL),
              UninstallTarget.canonical(callerAppURL) == UninstallTarget.canonical(containingAppURL)
        else {
            throw UninstallSecurityError.wrongCodePath
        }
    }
}
