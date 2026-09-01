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
                    .padding(.vertical, 20)

                resetPanel
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(22)

                Divider()
                    .padding(.vertical, 20)

                uninstallPanel
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
        VStack(alignment: .leading, spacing: 15) {
            HStack(alignment: .top, spacing: 14) {
                ManagementSymbol(
                    systemImage: "arrow.triangle.2.circlepath",
                    tint: Color(nsColor: .secondaryLabelColor)
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("Software Update")
                        .font(.title3.bold())
                    Text("Version \(updates.currentVersionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 42, alignment: .topLeading)

            updateActions
                .frame(maxWidth: .infinity, alignment: .trailing)

            if showsUpdateStatus {
                updateStatus
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    }

    private var showsUpdateStatus: Bool {
        if case .idle = updates.phase {
            return false
        }
        return true
    }

    @ViewBuilder
    private var updateActions: some View {
        if updates.availableRelease != nil {
            VStack(alignment: .trailing, spacing: 7) {
                Button("Install Update…") {
                    Task { await updates.installAvailableUpdate() }
                }
                .buttonStyle(ManagementPrimaryButtonStyle())
                .disabled(updates.isBusy || maintenance.isWorking)

                Button("Release Notes") {
                    updates.openReleasePage()
                }
                .buttonStyle(.link)
                .disabled(updates.isBusy || maintenance.isWorking)
            }
        } else {
            Button("Check for Updates") {
                Task { await updates.checkForUpdates() }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(ManagementPrimaryButtonStyle())
            .disabled(updates.isBusy || maintenance.isWorking)
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.phase {
        case .idle:
            EmptyView()
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

    private var resetPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("App Controls")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: 42, alignment: .topLeading)

            ManagementActionCell(
                detail: "Refresh cached widget values",
                systemImage: "arrow.counterclockwise",
                buttonTitle: "Reset",
                isDestructive: false,
                disabled: resetDisabled || maintenance.isWorking || updates.isBusy
            ) {
                pendingDangerAction = .reset
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
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    }

    private var uninstallPanel: some View {
        VStack(alignment: .leading, spacing: 15) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .accessibilityHidden(true)

            ManagementActionCell(
                detail: "Remove app and local data",
                systemImage: "trash",
                buttonTitle: "Uninstall",
                isDestructive: true,
                disabled: maintenance.isWorking || updates.isBusy
            ) {
                pendingDangerAction = .uninstall
            }
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .topLeading)
    }
}

private struct ManagementSymbol: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 30, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .accessibilityHidden(true)
    }
}

private struct ManagementPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.82 : 1))
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct ManagementActionCell: View {
    let detail: String
    let systemImage: String
    let buttonTitle: String
    let isDestructive: Bool
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button(action: action) {
                Label(buttonTitle, systemImage: systemImage)
                    .font(.body)
                    .foregroundStyle(isDestructive ? Color.red : Color(nsColor: .labelColor))
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 34)
                    .background(.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isDestructive
                                    ? Color.red.opacity(0.82)
                                    : Color(nsColor: .separatorColor).opacity(0.9),
                                lineWidth: 1
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .opacity(disabled ? 0.45 : 1)
            .disabled(disabled)
            .accessibilityHint(detail)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
