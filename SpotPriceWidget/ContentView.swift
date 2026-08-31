import SwiftUI
#if DEBUG && os(macOS)
import AppKit
#endif

struct ContentView: View {
    @StateObject private var model = DashboardViewModel()

    var body: some View {
        NavigationStack {
            DashboardView(model: model)
                .navigationTitle("Electricity Rates")
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task { await model.refresh() }
                        } label: {
                            if model.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Refresh", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(model.isLoading)
                    }
                }
        }
        .task {
#if DEBUG && os(macOS)
            if await runUninstallIntegrationTestIfRequested() { return }
#endif
            await model.loadIfNeeded()
        }
    }

#if DEBUG && os(macOS)
    private func runUninstallIntegrationTestIfRequested() async -> Bool {
        guard ProcessInfo.processInfo.environment["SPOTPRICE_TEST_UNINSTALL"] == "1" else {
            return false
        }
        do {
            let destinationURL = try await ProductUninstallerClient.moveContainingAppToTrash()
            FileHandle.standardOutput.write(Data("UNINSTALL_DESTINATION=\(destinationURL.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("UNINSTALL_ERROR=\(error.localizedDescription)\n".utf8))
        }
        NSApplication.shared.terminate(nil)
        return true
    }
#endif
}
