#if os(macOS)
import AppKit
import Combine
import SwiftUI
import WidgetKit

struct ProductManagementSections: View {
    @StateObject private var updates = SoftwareUpdateService()
    @StateObject private var maintenance = ProductMaintenanceService()
    @State private var pendingDangerAction: DangerAction?

    let resetDisabled: Bool
    let onReset: () async -> Void

    var body: some View {
        VStack(spacing: 18) {
            softwareUpdateCard
            dangerZoneCard
        }
        .alert(item: $pendingDangerAction) { action in
            switch action {
            case .reset:
                Alert(
                    title: Text("Reset Widget Data?"),
                    message: Text(
                        "This clears this app’s saved prices and downloaded installers, "
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

    private var softwareUpdateCard: some View {
        ManagementCard(
            title: "Software Update",
            systemImage: "arrow.triangle.2.circlepath",
            tint: .blue
        ) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Finland Electricity Rates")
                        .font(.headline)
                    Text("Version \(updates.currentVersionText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    updateStatus
                        .padding(.top, 3)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    Button("Check for Updates") {
                        Task { await updates.checkForUpdates() }
                    }
                    .disabled(updates.isBusy)

                    if updates.availableRelease != nil {
                        Button("Install Update…") {
                            Task { await updates.installAvailableUpdate() }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updates.isBusy)

                        Button("Release Notes") {
                            updates.openReleasePage()
                        }
                        .buttonStyle(.link)
                        .disabled(updates.isBusy)
                    }
                }
                .controlSize(.regular)
            }
        }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updates.phase {
        case .idle:
            Label("Check GitHub Releases when you’re ready.", systemImage: "clock")
                .foregroundStyle(.secondary)
        case .checking:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…")
            }
            .foregroundStyle(.secondary)
        case .upToDate:
            Label("You’re up to date.", systemImage: "checkmark.circle.fill")
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
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Downloading and verifying the installer…")
            }
            .foregroundStyle(.secondary)
        case .installerOpened:
            Label(
                "Verified installer opened. Quit this app, then drag the new version to Applications.",
                systemImage: "checkmark.shield.fill"
            )
            .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var dangerZoneCard: some View {
        ManagementCard(
            title: "Danger Zone",
            systemImage: "exclamationmark.triangle.fill",
            tint: .red,
            showsDangerBorder: true
        ) {
            VStack(spacing: 0) {
                DangerActionRow(
                    title: "Reset Widget Data",
                    detail: "Clear app cache, then request fresh widget timelines.",
                    buttonTitle: "Reset…",
                    disabled: resetDisabled || maintenance.isWorking
                ) {
                    pendingDangerAction = .reset
                }

                Divider().padding(.vertical, 14)

                DangerActionRow(
                    title: "Uninstall",
                    detail: "Move this app to the Trash and close it.",
                    buttonTitle: "Uninstall…",
                    disabled: maintenance.isWorking
                ) {
                    pendingDangerAction = .uninstall
                }

                if let message = maintenance.message {
                    Label(message, systemImage: maintenance.messageIsError ? "exclamationmark.circle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(maintenance.messageIsError ? .red : .gray)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 14)
                }
            }
        }
    }
}

private struct ManagementCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let showsDangerBorder: Bool
    let content: () -> Content

    init(
        title: String,
        systemImage: String,
        tint: Color,
        showsDangerBorder: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.showsDangerBorder = showsDangerBorder
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: systemImage)
                .font(.title3.bold())
                .foregroundStyle(showsDangerBorder ? tint : .primary)
                .symbolRenderingMode(.hierarchical)

            content()
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            if showsDangerBorder {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(tint.opacity(0.28), lineWidth: 1)
            }
        }
    }
}

private struct DangerActionRow: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(buttonTitle, role: .destructive, action: action)
                .buttonStyle(.bordered)
                .disabled(disabled)
        }
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
        SoftwareUpdateService.clearDownloadedInstallers()
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
