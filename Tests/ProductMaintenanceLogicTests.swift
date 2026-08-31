import Foundation

@main
struct ProductMaintenanceLogicTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("spotprice-maintenance-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let appURL = try makeApp(
            named: "Finland Electricity Rates.app",
            bundleIdentifier: ProductUninstallValidator.bundleIdentifier,
            under: root
        )

        expectNoThrow("The running app must be accepted.") {
            _ = try ProductUninstallValidator.validatedRunningApp(
                appURL,
                fileManager: fileManager
            )
        }

        let aliasURL = root.appendingPathComponent("Selected App.app")
        try fileManager.createSymbolicLink(at: aliasURL, withDestinationURL: appURL)
        expectNoThrow("A symlink resolving to the running app must be accepted.") {
            _ = try ProductUninstallValidator.validatedRunningApp(
                aliasURL,
                fileManager: fileManager
            )
        }

        let wrongBundle = try makeApp(
            named: "Wrong Bundle.app",
            bundleIdentifier: "example.invalid",
            under: root
        )
        expectThrows("An unrelated app must be rejected.") {
            _ = try ProductUninstallValidator.validatedRunningApp(
                wrongBundle,
                fileManager: fileManager
            )
        }

        let missingApp = root.appendingPathComponent("Missing.app")
        expectThrows("A missing app must be rejected.") {
            _ = try ProductUninstallValidator.validatedRunningApp(
                missingApp,
                fileManager: fileManager
            )
        }

        guard ProductUninstallValidator.serviceName == "personal.SpotPriceWidget.Uninstaller" else {
            fail("The client must connect only to the fixed embedded helper service.")
        }

        print("Product maintenance logic tests passed.")
    }

    private static func makeApp(
        named name: String,
        bundleIdentifier: String,
        under root: URL
    ) throws -> URL {
        let appURL = root.appendingPathComponent(name, isDirectory: true)
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
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
        return appURL
    }

    private static func expectNoThrow(_ message: String, operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            fail("\(message) Error: \(error)")
        }
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
