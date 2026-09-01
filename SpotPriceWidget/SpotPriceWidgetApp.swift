import SwiftUI
#if os(macOS)
import AppKit
import WidgetKit
#endif

@main
struct SpotPriceWidgetApp: App {
#if os(macOS)
    @StateObject private var updates = SoftwareUpdateService()
#endif

    init() {
#if os(macOS)
        ProductStartupMaintenance.start()
#endif
    }

    var body: some Scene {
        WindowGroup {
#if os(macOS)
            ContentView()
                .environmentObject(updates)
#else
            ContentView()
#endif
        }
#if os(macOS)
        .defaultSize(width: 1440, height: 960)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Task { await updates.checkForUpdates() }
                }
                .disabled(updates.isBusy)

                if updates.availableRelease != nil {
                    Button("Install Available Update…") {
                        Task { await updates.installAvailableUpdate() }
                    }
                    .disabled(updates.isBusy)
                }
            }
        }
#endif
    }
}

#if os(macOS)
private enum ProductStartupMaintenance {
    static func start() {
        Task {
#if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["SPOTPRICE_TEST_UNINSTALL"] == "1" {
                await runUninstallIntegrationTest()
                return
            }
            if environment["SPOTPRICE_TEST_WIDGET_REGISTRATION"] == "1" {
                await runWidgetRegistrationIntegrationTest()
                return
            }
#endif
            // During the bridge update, the previous helper can remain alive
            // briefly while it verifies the newly launched app. Waiting before
            // using the new restart selector guarantees this request reaches
            // the replacement helper rather than the pre-1.2.8 implementation.
            try? await Task.sleep(for: .seconds(5))

            for attempt in 0..<3 {
                do {
                    try await ProductWidgetRegistrationClient.repair()
                    WidgetCenter.shared.reloadAllTimelines()
                    return
                } catch {
                    guard attempt < 2 else { return }
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        }
    }

#if DEBUG
    private static func runUninstallIntegrationTest() async {
        do {
            let destinationURL = try await ProductUninstallerClient.moveContainingAppToTrash()
            FileHandle.standardOutput.write(Data("UNINSTALL_DESTINATION=\(destinationURL.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("UNINSTALL_ERROR=\(error.localizedDescription)\n".utf8))
        }
        NSApplication.shared.terminate(nil)
    }

    private static func runWidgetRegistrationIntegrationTest() async {
        do {
            try await ProductWidgetRegistrationClient.repair()
            FileHandle.standardOutput.write(Data("WIDGET_REGISTRATION_REPAIRED=1\n".utf8))
        } catch {
            FileHandle.standardError.write(Data(
                "WIDGET_REGISTRATION_ERROR=\(error.localizedDescription)\n".utf8
            ))
        }
        NSApplication.shared.terminate(nil)
    }
#endif
}
#endif
