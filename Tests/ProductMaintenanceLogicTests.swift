import Foundation

@main
struct ProductMaintenanceLogicTests {
    @MainActor
    static func main() async throws {
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

        try await testWidgetStartup()
        print("Product maintenance logic tests passed.")
    }

    @MainActor
    private static func testWidgetStartup() async throws {
        var preparedBuild: String?
        let markPrepared = { preparedBuild = $0 }
        var preparations = 0
        var reloads = 0
        let prepare = { preparations += 1 }
        let reload = { reloads += 1 }

        try await ProductWidgetStartup.refresh(build: "129", preparedBuild: preparedBuild, markPrepared: markPrepared, prepare: prepare, reload: reload)
        guard preparations == 1, reloads == 1 else { fail("First build launch must prepare once and reload.") }
        // A host relaunched after an OS upgrade sees the same persisted build.
        try await ProductWidgetStartup.refresh(build: "129", preparedBuild: preparedBuild, markPrepared: markPrepared, prepare: prepare, reload: reload)
        guard preparations == 1, reloads == 2 else { fail("Same-build relaunch must not restart the widget.") }
        try await ProductWidgetStartup.refresh(build: "130", preparedBuild: preparedBuild, markPrepared: markPrepared, prepare: prepare, reload: reload)
        guard preparations == 2, reloads == 3 else { fail("An updated build must prepare exactly once.") }

        enum PreparationFailure: Error { case unavailable }
        do {
            try await ProductWidgetStartup.refresh(build: "131", preparedBuild: preparedBuild, markPrepared: markPrepared, prepare: {
                throw PreparationFailure.unavailable
            }, reload: reload)
            fail("A helper failure must be reported.")
        } catch PreparationFailure.unavailable { }
        guard preparedBuild == "130", reloads == 4 else {
            fail("Failure must preserve the old marker and still reload healthy timelines.")
        }
        try await ProductWidgetStartup.refresh(build: "131", preparedBuild: preparedBuild, markPrepared: markPrepared, prepare: prepare, reload: reload)
        try await ProductWidgetStartup.refresh(build: "131", preparedBuild: preparedBuild, markPrepared: markPrepared, prepare: prepare, reload: reload)
        guard preparations == 3, reloads == 6 else { fail("Retry must complete once; subsequent launches only reload.") }
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
