import AppKit
import Foundation

final class UninstallService: NSObject, SpotPriceWidgetUninstalling {
    private let containingAppURL: URL

    init(containingAppURL: URL) {
        self.containingAppURL = containingAppURL
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
            do {
                let installedVersion = try await UpdateInstaller.install(
                    diskImageData: diskImageData,
                    signatureText: signatureText,
                    expectedVersion: expectedVersion,
                    containingAppURL: containingAppURL
                )
                reply(installedVersion, nil)
            } catch {
                reply(nil, error.localizedDescription)
            }
        }
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
        newConnection.exportedObject = UninstallService(containingAppURL: containingAppURL)
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
