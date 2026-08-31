import CryptoKit
import Foundation

@main
struct SoftwareUpdateLogicTests {
    @MainActor
    static func main() {
        testSemanticVersionOrdering()
        testChecksumVerification()
        print("Software update logic tests passed.")
    }

    private static func testSemanticVersionOrdering() {
        let version110 = ReleaseVersion("1.1.0")
        let version119 = ReleaseVersion("v1.1.9")
        let version120 = ReleaseVersion("1.2.0")
        let version121 = ReleaseVersion("v1.2.1")

        expect(version110 != nil, "A normal semantic version must parse.")
        expect(version119 != nil, "A v-prefixed semantic version must parse.")
        expect(version120 != nil, "The next minor version must parse.")
        expect(version121 != nil, "A v-prefixed patch update must parse.")
        expect(version110! < version119!, "Patch versions must sort numerically.")
        expect(version119! < version120!, "Minor versions must sort numerically.")
        expect(version120! < version121!, "A public patch update must sort above the installed version.")
        expect(ReleaseVersion("1.2") == nil, "Incomplete versions must be rejected.")
        expect(ReleaseVersion("1.2.0-beta") == nil, "Prerelease strings must be rejected.")
    }

    @MainActor
    private static func testChecksumVerification() {
        let diskImageData = Data("verified installer".utf8)
        let digest = SHA256.hash(data: diskImageData)
            .map { String(format: "%02x", $0) }
            .joined()
        let checksum = Data("\(digest)  Finland-Electricity-Rates.dmg\n".utf8)

        do {
            try SoftwareUpdateService.verify(
                diskImageData: diskImageData,
                checksumData: checksum
            )
        } catch {
            expect(false, "A matching installer checksum must pass: \(error)")
        }

        expectThrows("A modified installer must fail checksum verification.") {
            try SoftwareUpdateService.verify(
                diskImageData: Data("modified installer".utf8),
                checksumData: checksum
            )
        }
        expectThrows("A checksum for another filename must be rejected.") {
            let wrongName = Data("\(digest)  Another-App.dmg\n".utf8)
            try SoftwareUpdateService.verify(
                diskImageData: diskImageData,
                checksumData: wrongName
            )
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
