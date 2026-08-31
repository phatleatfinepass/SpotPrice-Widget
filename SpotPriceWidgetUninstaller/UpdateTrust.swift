import CryptoKit
import Foundation

enum UpdateTrust {
    static let publicKeyBase64 = "Xvx62h4TF8R1hPAQOriCMGuOFMMaspN/4YkNDdcTrFM="
    static let maximumDiskImageSize = 128 * 1_024 * 1_024

    static func verify(_ data: Data, signatureText: String) throws {
        guard data.count <= maximumDiskImageSize,
              let publicKeyData = Data(base64Encoded: publicKeyBase64),
              publicKeyData.count == 32,
              let signatureData = Data(
                  base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)
              ),
              signatureData.count == 64
        else {
            throw UpdateInstallError.invalidSignature
        }

        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signatureData, for: data) else {
            throw UpdateInstallError.invalidSignature
        }
    }
}
