import SwiftUI

@main
struct SpotPriceWidgetApp: App {
#if os(macOS)
    @StateObject private var updates = SoftwareUpdateService()
#endif

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
