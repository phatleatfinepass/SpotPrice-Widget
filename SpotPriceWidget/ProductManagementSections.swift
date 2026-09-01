#if os(macOS)
import AppKit
import Combine
import SwiftUI
import WidgetKit

struct ProductManagementSections: View {
    @EnvironmentObject private var updates: SoftwareUpdateService
    @StateObject private var maintenance = ProductMaintenanceService()
    @State private var pendingDangerAction: DangerAction?

    let resetDisabled: Bool
    let onReset: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Management")
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 0) {
                softwareUpdatePanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)

                Divider()
                    .padding(.vertical, 22)

                appControlsPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .alert(item: $pendingDangerAction) { action in
            switch action {
            case .reset:
                Alert(
                    title: Text("Reset Widget Data?"),
                    message: Text(
                        "This clears this app’s saved prices, "
                        + "then asks WidgetKit to reload both widgets. WidgetKit controls when the refresh runs."
                    ),
                    primaryButton: .destructive(Text("Reset")) {
                        Task { await maintenance.reset(using: onReset) }
                    },
                    secondaryButton: .cancel()
                )
            case .uninstall:
                Alert(
                    title: Text("Uninstall Finland Electricity Rates?"),
                    message: Text(
                        "Finland Electricity Rates will move itself to the Trash, clear its local widget data, "
                        + "and close. You can restore the app from the Trash until it is emptied."
                    ),
                    primaryButton: .destructive(Text("Move to Trash")) {
                        Task { await maintenance.uninstall() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    private var softwareUpdatePanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                ManagementIcon(
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: Color(nsColor: .labelColor).opacity(0.82)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Software Update")
                        .font(.title3.bold())
                    Text("Version \(updates.currentVersionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    updateStatus
                        .padding(.top, 5)
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                if updates.availableRelease != nil {
                    Button("Release Notes") {
                        updates.openReleasePage()
                    }
                    .buttonStyle(.link)
                    .disabled(updates.isBusy || maintenance.isWorking)

                    Button("Install Update…") {
                        Task { await updates.installAvailableUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(updates.isBusy || maintenance.isWorking)
                } else {
                    Button("Check for Updates") {
                        Task { await updates.checkForUpdates() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(updates.isBusy || maintenance.isWorking)
                }
            }
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.phase {
        case .idle:
            Label("Signed automatic updates", systemImage: "checkmark.shield")
                .foregroundStyle(.secondary)
        case .checking:
            progressStatus("Checking for updates…")
        case .upToDate:
            Label("Up to date", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updateAvailable:
            if let release = updates.availableRelease {
                Label(
                    "Version \(release.version.description) is available.",
                    systemImage: "arrow.down.circle.fill"
                )
                .foregroundStyle(.blue)
            }
        case .downloading:
            progressStatus("Downloading and verifying the signed update…")
        case .installing:
            progressStatus("Installing the new version and checking that it opens…")
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private func progressStatus(_ text: String) -> some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }

    private var appControlsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("App Controls")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 0) {
                ManagementActionCell(
                    title: "Reset Data",
                    detail: "Refresh cached widget values",
                    systemImage: "arrow.counterclockwise",
                    tint: Color(nsColor: .labelColor).opacity(0.82),
                    buttonTitle: "Reset…",
                    isDestructive: false,
                    disabled: resetDisabled || maintenance.isWorking || updates.isBusy
                ) {
                    pendingDangerAction = .reset
                }

                Divider()
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)

                ManagementActionCell(
                    title: "Uninstall",
                    detail: "Remove app and local data",
                    systemImage: "trash",
                    tint: .red,
                    buttonTitle: "Uninstall…",
                    isDestructive: true,
                    disabled: maintenance.isWorking || updates.isBusy
                ) {
                    pendingDangerAction = .uninstall
                }
            }

            if let message = maintenance.message {
                Label(message, systemImage: maintenance.messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(
                        maintenance.messageIsError ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary)
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 196, alignment: .topLeading)
    }
}

private struct ManagementIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 25, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 48, height: 48)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

private struct ManagementActionCell: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let buttonTitle: String
    let isDestructive: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                ManagementIcon(systemImage: systemImage, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button(buttonTitle, role: isDestructive ? .destructive : nil, action: action)
                .buttonStyle(.bordered)
                .disabled(disabled)
        }
        .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
    }
}

@MainActor
private final class ProductMaintenanceService: ObservableObject {
    @Published private(set) var isWorking = false
    @Published private(set) var message: String?
    @Published private(set) var messageIsError = false

    func reset(using operation: () async -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }

        await operation()
        messageIsError = false
        message = "App data was reset and a widget reload was requested."
    }

    func uninstall() async {
        guard !isWorking else { return }
        isWorking = true
        message = nil
        defer { isWorking = false }

        let appURL: URL
        do {
            appURL = try ProductUninstallValidator.validatedRunningApp(Bundle.main.bundleURL)
        } catch {
            messageIsError = true
            message = error.localizedDescription
            return
        }

        WidgetDataStore.resetCaches()
        WidgetCenter.shared.reloadAllTimelines()

        do {
            _ = try await ProductUninstallerClient.moveContainingAppToTrash()
            NSApplication.shared.terminate(nil)
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
            messageIsError = true
            message = error.localizedDescription
        }
    }
}

private enum DangerAction: String, Identifiable {
    case reset
    case uninstall

    var id: String { rawValue }
}
#endif
