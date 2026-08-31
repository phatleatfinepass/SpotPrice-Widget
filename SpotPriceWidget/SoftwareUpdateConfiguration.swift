#if os(macOS)
import CryptoKit
import Foundation

enum SoftwareUpdateTrust {
    static let publicKeyBase64 = "Xvx62h4TF8R1hPAQOriCMGuOFMMaspN/4YkNDdcTrFM="
    static let maximumMetadataSize = 1_000_000
    static let maximumSignatureSize = 512
    static let maximumDiskImageSize = 128 * 1_024 * 1_024

    static func verify(_ data: Data, signatureText: String) throws {
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
              publicKeyData.count == 32,
              let signatureData = Data(
                  base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              signatureData.count == 64
        else {
            throw SoftwareUpdateTrustError.invalidSignature
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signatureData, for: data) else {
            throw SoftwareUpdateTrustError.invalidSignature
        }
    }

    static func signatureText(from data: Data) throws -> String {
        guard data.count <= maximumSignatureSize,
              let text = String(data: data, encoding: .utf8),
              Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines))?.count == 64
        else {
            throw SoftwareUpdateTrustError.invalidSignature
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum SoftwareUpdateTrustError: LocalizedError, Equatable {
    case invalidSignature

    var errorDescription: String? {
        "The update does not have a valid project signature. Nothing was installed."
    }
}

struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

struct SoftwareUpdateEndpointPolicy: Equatable, Sendable {
    let releaseAPIURL: URL
    let loopbackOrigin: URL?

    static let production = Self(
        releaseAPIURL: URL(
            string: "https://api.github.com/repos/phatleatfinepass/SpotPrice-Widget/releases/latest"
        )!,
        loopbackOrigin: nil
    )

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleURL: URL = Bundle.main.bundleURL
    ) -> Self {
        let bundlePath = bundleURL.standardizedFileURL.path
        guard (bundlePath.hasPrefix("/private/tmp/spotprice-update-proof.")
                || bundlePath.hasPrefix("/tmp/spotprice-update-proof.")),
              let rawURL = environment["SPOTPRICE_UPDATE_PROOF_API_URL"],
              let url = URL(string: rawURL),
              isLoopbackHTTP(url)
        else {
            return .production
        }

        return Self(releaseAPIURL: url, loopbackOrigin: origin(of: url))
    }

    func allows(_ url: URL) -> Bool {
        if let loopbackOrigin, Self.origin(of: url) == loopbackOrigin {
            return true
        }

        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "api.github.com"
            || host == "github.com"
            || host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
    }

    private static func isLoopbackHTTP(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host?.lowercased() else {
            return false
        }
        return host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static func origin(of url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme.lowercased()
        components.host = host.lowercased()
        components.port = url.port
        return components.url
    }
}
#endif
