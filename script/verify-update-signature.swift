import CryptoKit
import Foundation

private let publicKeyBase64 = "Xvx62h4TF8R1hPAQOriCMGuOFMMaspN/4YkNDdcTrFM="

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(Data("Usage: verify-update-signature <artifact> <signature>\n".utf8))
    exit(2)
}

let artifactURL = URL(fileURLWithPath: CommandLine.arguments[1])
let signatureURL = URL(fileURLWithPath: CommandLine.arguments[2])
let artifactData = try Data(contentsOf: artifactURL, options: .mappedIfSafe)
let signatureText = try String(contentsOf: signatureURL, encoding: .utf8)

guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
      let signatureData = Data(
          base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      signatureData.count == 64
else {
    FileHandle.standardError.write(Data("Invalid Ed25519 update signature format.\n".utf8))
    exit(1)
}

let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
guard publicKey.isValidSignature(signatureData, for: artifactData) else {
    FileHandle.standardError.write(Data("Ed25519 update signature verification failed.\n".utf8))
    exit(1)
}

print("Ed25519 update signature verified.")
