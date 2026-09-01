import AppKit
import Foundation

final class UninstallService: NSObject, SpotPriceWidgetUninstalling {
    private let containingAppURL: URL
    private let callerProcessIdentifier: pid_t

    init(containingAppURL: URL, callerProcessIdentifier: pid_t) {
        self.containingAppURL = containingAppURL
        self.callerProcessIdentifier = callerProcessIdentifier
    }

    func moveContainingAppToTrash(
        withReply reply: @escaping (String?, String?) -> Void
    ) {
        do {
            let appURL = try UninstallTarget.validatedAppURL(containingAppURL)
            NSWorkspace.shared.recycle([appURL]) { recycledURLs, error in
                if let error {
                    reply(nil, error.localizedDescription)
                } else if let destinationURL = recycledURLs[appURL] ?? recycledURLs.first?.value {
                    reply(destinationURL.path, nil)
                } else {
                    reply(nil, "macOS did not return the app’s Trash location.")
                }
            }
        } catch {
            reply(nil, error.localizedDescription)
        }
    }

    func installUpdate(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String,
        withReply reply: @escaping (String?, String?) -> Void
    ) {
        Task {
            let lease = UpdateTransactionLease()
            do {
                let preparedUpdate = try UpdateInstaller.prepare(
                    diskImageData: diskImageData,
                    signatureText: signatureText,
                    expectedVersion: expectedVersion,
                    containingAppURL: containingAppURL
                )
                reply(preparedUpdate.expectedVersion, nil)
                do {
                    _ = try await UpdateInstaller.commit(
                        preparedUpdate,
                        callerProcessIdentifier: callerProcessIdentifier
                    )
                } catch {
                    NSLog("Prepared update could not be committed: %@", error.localizedDescription)
                }
            } catch {
                reply(nil, error.localizedDescription)
            }
            lease.end()
        }
    }
}

private final class UpdateTransactionLease {
    private let reason = "Completing a verified Finland Electricity Rates update"
    private var isActive = true

    init() {
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.disableAutomaticTermination(reason)
    }

    func end() {
        guard isActive else { return }
        isActive = false
        ProcessInfo.processInfo.enableAutomaticTermination(reason)
        ProcessInfo.processInfo.enableSuddenTermination()
    }

    deinit {
        end()
    }
}

final class UninstallListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let containingAppURL: URL

    init(containingAppURL: URL) {
        self.containingAppURL = containingAppURL
    }

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        do {
            try UninstallSecurity.validate(
                connection: newConnection,
                containingAppURL: containingAppURL
            )
        } catch {
            NSLog("Rejected uninstall connection: %@", error.localizedDescription)
            return false
        }

        newConnection.exportedInterface = NSXPCInterface(with: SpotPriceWidgetUninstalling.self)
        newConnection.exportedObject = UninstallService(
            containingAppURL: containingAppURL,
            callerProcessIdentifier: newConnection.processIdentifier
        )
        newConnection.resume()
        return true
    }
}

do {
    let containingAppURL = try UninstallTarget.containingAppURL(
        serviceBundleURL: Bundle.main.bundleURL
    )
    let delegate = UninstallListenerDelegate(containingAppURL: containingAppURL)
    let listener = NSXPCListener.service()
    listener.delegate = delegate
    listener.resume()
    RunLoop.current.run()
} catch {
    NSLog("Uninstall helper could not start: %@", error.localizedDescription)
    exit(EXIT_FAILURE)
}
