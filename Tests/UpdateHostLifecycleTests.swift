import Foundation

@main
struct UpdateHostLifecycleTests {
    static func main() async {
        await testWaitsForTheExactProcessToExit()
        await testTimesOutWithoutReplacingWhileTheProcessLives()
        testPluginKitPathParsing()
        print("Update handoff tests passed.")
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
