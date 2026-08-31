import Foundation

@main
struct SoftwareUpdateLogicTests {
    static func main() {
        testPinnedPublicKey()
        testBridgeVersionOrdering()
        testProductionEndpoint()
        testProofEndpointIsNarrowlyScoped()
        testOriginPolicy()
        testInvalidSignatureRejection()
        print("Software update trust tests passed.")
    }

    private static func testPinnedPublicKey() {
        let key = Data(base64Encoded: SoftwareUpdateTrust.publicKeyBase64)
        expect(key?.count == 32, "The pinned Ed25519 public key must contain exactly 32 bytes.")
    }

    private static func testBridgeVersionOrdering() {
        let installed = ReleaseVersion("1.2.1")
        let bridge = ReleaseVersion("v1.2.2")
        expect(installed != nil && bridge != nil, "Bridge versions must parse.")
        expect(installed! < bridge!, "An installed 1.2.1 app must discover the 1.2.2 bridge.")
        expect(bridge!.description == "1.2.2", "A tagged bridge version must normalize for installation.")
        expect(ReleaseVersion("1.2") == nil, "Incomplete versions must be rejected.")
    }

    private static func testProductionEndpoint() {
        let policy = SoftwareUpdateEndpointPolicy.production
        expect(
            policy.releaseAPIURL.absoluteString
                == "https://api.github.com/repos/phatleatfinepass/SpotPrice-Widget/releases/latest",
            "The production updater must use the fixed official repository."
        )
        expect(policy.loopbackOrigin == nil, "Production must never allow a loopback update origin.")
    }

    private static func testProofEndpointIsNarrowlyScoped() {
        let environment = ["SPOTPRICE_UPDATE_PROOF_API_URL": "http://127.0.0.1:8765/release.json"]
        let proofBundle = URL(fileURLWithPath: "/private/tmp/spotprice-update-proof.unit/App.app")
        let aliasedProofBundle = URL(fileURLWithPath: "/tmp/spotprice-update-proof.unit/App.app")
        let installedBundle = URL(fileURLWithPath: "/Users/test/Applications/App.app")

        let proofPolicy = SoftwareUpdateEndpointPolicy.current(
            environment: environment,
            bundleURL: proofBundle
        )
        expect(
            proofPolicy.releaseAPIURL.absoluteString == "http://127.0.0.1:8765/release.json",
            "A disposable proof bundle may use a loopback-only release endpoint."
        )
        expect(
            SoftwareUpdateEndpointPolicy.current(
                environment: environment,
                bundleURL: aliasedProofBundle
            ).releaseAPIURL == proofPolicy.releaseAPIURL,
            "The standard /tmp alias must preserve the disposable proof boundary."
        )

        let installedPolicy = SoftwareUpdateEndpointPolicy.current(
            environment: environment,
            bundleURL: installedBundle
        )
        expect(installedPolicy == .production, "A normal installation must ignore proof overrides.")
    }

    private static func testOriginPolicy() {
        let policy = SoftwareUpdateEndpointPolicy(
            releaseAPIURL: URL(string: "http://127.0.0.1:8765/release.json")!,
            loopbackOrigin: URL(string: "http://127.0.0.1:8765")!
        )
        expect(
            policy.allows(URL(string: "http://127.0.0.1:8765/update.dmg")!),
            "The proof policy must allow its exact loopback origin."
        )
        expect(
            !policy.allows(URL(string: "http://127.0.0.1:8766/update.dmg")!),
            "The proof policy must reject another loopback port."
        )
        expect(
            !policy.allows(URL(string: "http://example.com/update.dmg")!),
            "Plaintext remote update origins must be rejected."
        )
    }

    private static func testInvalidSignatureRejection() {
        expectThrows("Modified or unsigned update data must be rejected.") {
            try SoftwareUpdateTrust.verify(
                Data("modified update".utf8),
                signatureText: Data(repeating: 0, count: 64).base64EncodedString()
            )
        }
        expectThrows("Malformed signatures must be rejected.") {
            try SoftwareUpdateTrust.verify(Data(), signatureText: "not-base64")
        }
    }

    private static func expectThrows(_ message: String, operation: () throws -> Void) {
        do {
            try operation()
            expect(false, message)
        } catch { }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
    }
}
