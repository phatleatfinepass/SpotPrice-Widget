import Foundation

@main
struct UninstallerTargetTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("spotprice-uninstaller-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = try makeApp(under: root)
        let serviceURL = appURL
            .appendingPathComponent("Contents/XPCServices/SpotPriceWidgetUninstaller.xpc", isDirectory: true)
        try fileManager.createDirectory(at: serviceURL, withIntermediateDirectories: true)

        let resolved = try UninstallTarget.containingAppURL(
            serviceBundleURL: serviceURL,
            fileManager: fileManager
        )
        expect(resolved == appURL.standardizedFileURL, "The helper must resolve only its containing app.")

        let unexpectedServiceURL = appURL
            .appendingPathComponent("Contents/Helpers/SpotPriceWidgetUninstaller.xpc", isDirectory: true)
        try fileManager.createDirectory(at: unexpectedServiceURL, withIntermediateDirectories: true)
        expectThrows("A helper outside Contents/XPCServices must be rejected.") {
            _ = try UninstallTarget.containingAppURL(
                serviceBundleURL: unexpectedServiceURL,
                fileManager: fileManager
            )
        }

        let executableURL = appURL.appendingPathComponent("Contents/MacOS/SpotPriceWidget")
        expect(
            UninstallTarget.enclosingApplicationURL(for: executableURL) == appURL.standardizedFileURL,
            "The caller executable must resolve to its application bundle."
        )

        print("Uninstaller target tests passed.")
    }

    private static func makeApp(under root: URL) throws -> URL {
        let appURL = root.appendingPathComponent("Finland Electricity Rates.app", isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": UninstallTarget.hostBundleIdentifier,
            "CFBundleName": "Finland Electricity Rates",
            "CFBundlePackageType": "APPL",
            "CFBundleVersion": "1",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return appURL.standardizedFileURL
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fail(message) }
    }

    private static func expectThrows(_ message: String, operation: () throws -> Void) {
        do {
            try operation()
            fail(message)
        } catch { }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}
