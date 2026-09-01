import SwiftUI

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
            await model.loadIfNeeded()
        }
    }
}
