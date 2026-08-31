#if os(macOS)
import Foundation

enum ProductUninstallValidationError: LocalizedError {
    case missingApplication
    case notApplication
    case wrongBundleIdentifier

    var errorDescription: String? {
        switch self {
        case .missingApplication:
            "This app could not be found on disk."
        case .notApplication:
            "This copy is not running from an application bundle."
        case .wrongBundleIdentifier:
            "This copy is not Finland Electricity Rates."
        }
    }
}

enum ProductUninstallValidator {
    static let bundleIdentifier = "personal.SpotPriceWidget"
    static let serviceName = "personal.SpotPriceWidget.Uninstaller"

    static func validatedRunningApp(
        _ runningAppURL: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let running = canonical(runningAppURL)

        guard running.pathExtension.lowercased() == "app" else {
            throw ProductUninstallValidationError.notApplication
        }
        guard fileManager.fileExists(atPath: running.path) else {
            throw ProductUninstallValidationError.missingApplication
        }
        guard Bundle(url: running)?.bundleIdentifier == bundleIdentifier else {
            throw ProductUninstallValidationError.wrongBundleIdentifier
        }

        return running
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

@objc(SpotPriceWidgetUninstalling)
protocol SpotPriceWidgetUninstalling {
    func moveContainingAppToTrash(
        withReply reply: @escaping (_ destinationPath: String?, _ errorMessage: String?) -> Void
    )

    func installUpdate(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String,
        withReply reply: @escaping (_ installedVersion: String?, _ errorMessage: String?) -> Void
    )
}

enum ProductUninstallerClientError: LocalizedError {
    case unavailable(String)
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            "The uninstall helper couldn’t move this app to the Trash: \(message)"
        case .invalidReply:
            "The uninstall helper returned an invalid result."
        }
    }
}

enum ProductUninstallerClient {
    static func moveContainingAppToTrash() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let request = ProductUninstallerRequest(continuation: continuation)
            request.start()
        }
    }
}

enum ProductUpdaterClientError: LocalizedError {
    case unavailable(String)
    case invalidReply

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            "The update could not be installed: \(message)"
        case .invalidReply:
            "The update helper returned an invalid result."
        }
    }
}

enum ProductUpdaterClient {
    static func install(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = ProductUpdateRequest(
                diskImageData: diskImageData,
                signatureText: signatureText,
                expectedVersion: expectedVersion,
                continuation: continuation
            )
            request.start()
        }
    }
}

private final class ProductUpdateRequest: @unchecked Sendable {
    private let diskImageData: Data
    private let signatureText: String
    private let expectedVersion: String
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var connection: NSXPCConnection?

    init(
        diskImageData: Data,
        signatureText: String,
        expectedVersion: String,
        continuation: CheckedContinuation<String, Error>
    ) {
        self.diskImageData = diskImageData
        self.signatureText = signatureText
        self.expectedVersion = expectedVersion
        self.continuation = continuation
    }

    func start() {
        let connection = NSXPCConnection(serviceName: ProductUninstallValidator.serviceName)
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: SpotPriceWidgetUninstalling.self)
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [self] error in
            finish(.failure(ProductUpdaterClientError.unavailable(error.localizedDescription)))
        }) as? SpotPriceWidgetUninstalling else {
            finish(.failure(ProductUpdaterClientError.unavailable("The helper connection could not be created.")))
            return
        }

        proxy.installUpdate(
            diskImageData: diskImageData,
            signatureText: signatureText,
            expectedVersion: expectedVersion
        ) { [self] installedVersion, errorMessage in
            if let errorMessage, !errorMessage.isEmpty {
                finish(.failure(ProductUpdaterClientError.unavailable(errorMessage)))
            } else if let installedVersion, !installedVersion.isEmpty {
                finish(.success(installedVersion))
            } else {
                finish(.failure(ProductUpdaterClientError.invalidReply))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()

        connection?.invalidate()
        continuation.resume(with: result)
    }
}

private final class ProductUninstallerRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var connection: NSXPCConnection?

    init(continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func start() {
        let connection = NSXPCConnection(serviceName: ProductUninstallValidator.serviceName)
        self.connection = connection
        connection.remoteObjectInterface = NSXPCInterface(with: SpotPriceWidgetUninstalling.self)
        connection.resume()

        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ [self] error in
            finish(.failure(ProductUninstallerClientError.unavailable(error.localizedDescription)))
        }) as? SpotPriceWidgetUninstalling else {
            finish(.failure(ProductUninstallerClientError.unavailable("The helper connection could not be created.")))
            return
        }

        proxy.moveContainingAppToTrash { [self] destinationPath, errorMessage in
            if let errorMessage, !errorMessage.isEmpty {
                finish(.failure(ProductUninstallerClientError.unavailable(errorMessage)))
            } else if let destinationPath, !destinationPath.isEmpty {
                finish(.success(URL(fileURLWithPath: destinationPath)))
            } else {
                finish(.failure(ProductUninstallerClientError.invalidReply))
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return
        }
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()

        connection?.invalidate()
        continuation.resume(with: result)
    }
}
#endif
