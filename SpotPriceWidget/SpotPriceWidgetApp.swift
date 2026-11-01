import SwiftUI
#if os(macOS)
import AppKit
import WidgetKit
import OSLog
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
@MainActor
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
            let logger = Logger(subsystem: "personal.SpotPriceWidget", category: "WidgetStartup")
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
            do {
                try await ProductWidgetStartup.refresh(
                    build: build,
                    preparedBuild: UserDefaults.standard.string(forKey: ProductWidgetStartup.preparedBuildKey),
                    markPrepared: { UserDefaults.standard.set($0, forKey: ProductWidgetStartup.preparedBuildKey) }
                ) {
                    // A missing marker is also a first installation. This one-time
                    // process handoff covers skipped-version updater bridges.
                    // It must never remove Launch Services registration.
                    try await Task.sleep(for: .seconds(5))
                    for attempt in 0..<3 {
                        do {
                            try await ProductWidgetRegistrationClient.prepareCurrentBuild()
                            logger.info("Prepared widget process for build \(build, privacy: .public); registration preserved")
                            return
                        } catch {
                            guard attempt < 2 else { throw error }
                            try await Task.sleep(for: .seconds(1))
                        }
                    }
                } reload: {
                    WidgetCenter.shared.reloadAllTimelines()
                    logger.info("Requested widget timelines; registration preserved")
                }
            } catch {
                logger.error("Widget build preparation failed; reload requested and will retry next launch: \(error.localizedDescription, privacy: .public)")
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
            try await ProductWidgetRegistrationClient.repairForIntegrationTest()
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
