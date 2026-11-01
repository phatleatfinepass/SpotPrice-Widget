import Foundation

@main
struct UpdateHostLifecycleTests {
    static func main() async {
        if CommandLine.arguments.dropFirst() == ["--widget-process-fixture"] {
            // Copy a locally built executable, not an Apple platform binary:
            // macOS can kill a relocated /bin/sleep for a launch-constraint violation.
            FileHandle.standardOutput.write(Data([1]))
            try? await Task.sleep(for: .seconds(30))
            return
        }
        await testWaitsForTheExactProcessToExit()
        await testTimesOutWithoutReplacingWhileTheProcessLives()
        await testStopsOnlyTheExactWidgetExecutable()
        testPluginKitPathParsing()
        print("Update handoff tests passed.")
    }

    private static func testStopsOnlyTheExactWidgetExecutable() async {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("spotprice-widget-process-\(UUID().uuidString)", isDirectory: true)
        let appURL = root.appendingPathComponent("Finland Electricity Rates.app", isDirectory: true)
        let executableURL = WidgetExtensionLifecycle.expectedExecutableURL(in: appURL)
        let competingURL = root
            .appendingPathComponent("Debug", isDirectory: true)
            .appendingPathComponent("SpotPriceWidgetFinlandExtension")

        do {
            try fileManager.createDirectory(
                at: executableURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: competingURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let fixture = URL(fileURLWithPath: CommandLine.arguments[0])
            try fileManager.copyItem(at: fixture, to: executableURL)
            try fileManager.copyItem(at: fixture, to: competingURL)

            let widgetProcess = Process()
            widgetProcess.executableURL = executableURL
            widgetProcess.arguments = ["--widget-process-fixture"]
            let widgetReady = Pipe()
            widgetProcess.standardOutput = widgetReady
            let competingProcess = Process()
            competingProcess.executableURL = competingURL
            competingProcess.arguments = ["--widget-process-fixture"]
            let competingReady = Pipe()
            competingProcess.standardOutput = competingReady
            try widgetProcess.run()
            try competingProcess.run()
            defer {
                if widgetProcess.isRunning { widgetProcess.terminate() }
                if competingProcess.isRunning { competingProcess.terminate() }
                try? fileManager.removeItem(at: root)
            }

            // Prove both fixtures actually started before inspecting process identity.
            guard try widgetReady.fileHandleForReading.read(upToCount: 1) == Data([1]),
                  try competingReady.fileHandleForReading.read(upToCount: 1) == Data([1])
            else { fail("Both widget process fixtures must start.") }

            // Start the host between two instances at the *same* canonical
            // widget path: only the pre-host instance may be a legacy resident.
            let host = try startReadyFixture(at: fixture)
            defer { if host.isRunning { host.terminate() } }
            let freshWidget = try startReadyFixture(at: executableURL)
            defer { if freshWidget.isRunning { freshWidget.terminate() } }
            try await WidgetExtensionLifecycle.terminateRunningExtension(
                in: appURL, predatingHost: host.processIdentifier, timeout: 1, pollInterval: 0.02
            )
            widgetProcess.waitUntilExit()
            expect(
                widgetProcess.terminationReason == .uncaughtSignal
                    && (widgetProcess.terminationStatus == SIGTERM || widgetProcess.terminationStatus == SIGKILL),
                "Build preparation must stop the widget that predates the new host."
            )
            expect(freshWidget.isRunning, "The newly launched widget must survive build preparation.")
            expect(competingProcess.isRunning, "An unrelated copy must survive build preparation.")

            try await WidgetExtensionLifecycle.terminateRunningExtension(in: appURL, timeout: 1, pollInterval: 0.02)
            freshWidget.waitUntilExit()
            expect(freshWidget.terminationReason == .uncaughtSignal, "Actual replacement must still stop the exact widget.")
            expect(competingProcess.isRunning, "Actual replacement must preserve the unrelated copy.")
            expect(
                !WidgetExtensionLifecycle.matches(
                    processExecutablePath: competingURL.path,
                    expectedExecutableURL: executableURL
                ),
                "Widget process matching must use the complete canonical executable path."
            )
        } catch {
            try? fileManager.removeItem(at: root)
            fail("The widget process handoff failed: \(error.localizedDescription)")
        }
    }

    private static func startReadyFixture(at url: URL) throws -> Process {
        let process = Process()
        let ready = Pipe()
        process.executableURL = url
        process.arguments = ["--widget-process-fixture"]
        process.standardOutput = ready
        try process.run()
        guard try ready.fileHandleForReading.read(upToCount: 1) == Data([1]) else {
            fail("The process fixture must start.")
        }
        return process
    }

    private static func testWaitsForTheExactProcessToExit() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["0.30"]

        do {
            try process.run()
            let started = Date()
            try await UpdateHostLifecycle.waitForExit(
                processIdentifier: process.processIdentifier,
                timeout: 2,
                pollInterval: 0.02
            )
            expect(
                Date().timeIntervalSince(started) >= 0.20,
                "The update must not continue while the authenticated host process is alive."
            )
        } catch {
            fail("Waiting for a normally exiting host failed: \(error.localizedDescription)")
        }
    }

    private static func testTimesOutWithoutReplacingWhileTheProcessLives() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["2"]

        do {
            try process.run()
            defer {
                if process.isRunning {
                    process.terminate()
                }
            }

            do {
                try await UpdateHostLifecycle.waitForExit(
                    processIdentifier: process.processIdentifier,
                    timeout: 0.10,
                    pollInterval: 0.02
                )
                fail("A live host must prevent the replacement phase.")
            } catch UpdateHostLifecycleError.hostDidNotExit {
                // Expected.
            } catch {
                fail("The live-host timeout returned the wrong error: \(error.localizedDescription)")
            }
        } catch {
            fail("The timeout fixture could not start: \(error.localizedDescription)")
        }
    }

    private static func testPluginKitPathParsing() {
        let installed = "/Applications/Finland Electricity Rates.app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
        let debug = "/Users/test/DerivedData/Debug/Finland Electricity Rates.app/Contents/PlugIns/SpotPriceWidgetFinlandExtension.appex"
        let output = """
        !    personal.SpotPriceWidget.SpotPriceWidgetFinland(1.2.4)\tUUID-1\tdate\t\(installed)
        +    personal.SpotPriceWidget.SpotPriceWidgetFinland(1.2.3)\tUUID-2\tdate\t\(debug)
         (2 plug-ins)
        """

        expect(
            WidgetRegistrationPaths.extensionPaths(from: output) == [installed, debug],
            "PluginKit registration parsing must preserve only exact absolute extension paths."
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}
