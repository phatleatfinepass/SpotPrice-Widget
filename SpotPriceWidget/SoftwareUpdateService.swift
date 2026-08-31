#if os(macOS)
import AppKit
import Combine
import Foundation

struct ProductRelease: Equatable, Sendable {
    let version: ReleaseVersion
    let tagName: String
    let diskImageURL: URL
    let signatureURL: URL
    let releasePageURL: URL
}

@MainActor
final class SoftwareUpdateService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var availableRelease: ProductRelease?
    @Published private(set) var lastChecked: Date?

    let currentVersionText: String

    private static let repositoryOwner = "phatleatfinepass"
    private static let repositoryName = "SpotPrice-Widget"
    private static let diskImageName = "Finland-Electricity-Rates.dmg"
    private static let signatureName = "Finland-Electricity-Rates.dmg.sig"
    private let endpointPolicy: SoftwareUpdateEndpointPolicy

    init(
        bundle: Bundle = .main,
        endpointPolicy: SoftwareUpdateEndpointPolicy? = nil
    ) {
        currentVersionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
        self.endpointPolicy = endpointPolicy ?? .current(bundleURL: bundle.bundleURL)
    }

    var isBusy: Bool {
        phase == .checking || phase == .downloading || phase == .installing
    }

    var canCheckForUpdates: Bool { !isBusy }

    func checkForUpdates() async {
        guard !isBusy else { return }
        phase = .checking

        do {
            let release = try await fetchLatestRelease()
            lastChecked = Date()

            if let currentVersion = ReleaseVersion(currentVersionText), release.version <= currentVersion {
                availableRelease = nil
                phase = .upToDate
            } else {
                availableRelease = release
                phase = .updateAvailable
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func installAvailableUpdate() async {
        guard !isBusy, let release = availableRelease else { return }
        phase = .downloading

        do {
            async let signatureDownload = download(
                from: release.signatureURL,
                maximumSize: SoftwareUpdateTrust.maximumSignatureSize
            )
            async let diskImageDownload = download(
                from: release.diskImageURL,
                maximumSize: SoftwareUpdateTrust.maximumDiskImageSize
            )
            let (signatureData, diskImageData) = try await (signatureDownload, diskImageDownload)
            let signatureText = try SoftwareUpdateTrust.signatureText(from: signatureData)
            try SoftwareUpdateTrust.verify(diskImageData, signatureText: signatureText)

            phase = .installing
            _ = try await ProductUpdaterClient.install(
                diskImageData: diskImageData,
                signatureText: signatureText,
                expectedVersion: release.version.description
            )
            NSApplication.shared.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func openReleasePage() {
        let destination = availableRelease?.releasePageURL
            ?? URL(string: "https://github.com/phatleatfinepass/SpotPrice-Widget/releases/latest")!
        NSWorkspace.shared.open(destination)
    }

    private func fetchLatestRelease() async throws -> ProductRelease {
        var request = URLRequest(url: endpointPolicy.releaseAPIURL)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Finland-Electricity-Rates/\(currentVersionText)", forHTTPHeaderField: "User-Agent")

        let metadata = try await responseData(
            for: request,
            maximumSize: SoftwareUpdateTrust.maximumMetadataSize
        )
        let release = try JSONDecoder().decode(GitHubRelease.self, from: metadata)

        guard !release.draft, !release.prerelease,
              let version = ReleaseVersion(release.tagName),
              isTrustedReleasePage(release.htmlURL, tagName: release.tagName),
              let diskImage = release.assets.first(where: { $0.name == Self.diskImageName }),
              let signature = release.assets.first(where: { $0.name == Self.signatureName }),
              isTrustedAssetURL(diskImage.downloadURL, tagName: release.tagName, name: Self.diskImageName),
              isTrustedAssetURL(signature.downloadURL, tagName: release.tagName, name: Self.signatureName)
        else {
            throw SoftwareUpdateError.invalidRelease
        }

        return ProductRelease(
            version: version,
            tagName: release.tagName,
            diskImageURL: diskImage.downloadURL,
            signatureURL: signature.downloadURL,
            releasePageURL: release.htmlURL
        )
    }

    private func download(from url: URL, maximumSize: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Finland-Electricity-Rates", forHTTPHeaderField: "User-Agent")
        return try await responseData(for: request, maximumSize: maximumSize)
    }

    private func responseData(for request: URLRequest, maximumSize: Int) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url,
              endpointPolicy.allows(finalURL),
              data.count <= maximumSize
        else {
            throw SoftwareUpdateError.invalidResponse
        }
        return data
    }

    private func isTrustedReleasePage(_ url: URL, tagName: String) -> Bool {
        if endpointPolicy.loopbackOrigin != nil {
            return endpointPolicy.allows(url)
        }
        guard url.scheme == "https", url.host?.lowercased() == "github.com" else { return false }
        return url.pathComponents == [
            "/", Self.repositoryOwner, Self.repositoryName, "releases", "tag", tagName,
        ]
    }

    private func isTrustedAssetURL(_ url: URL, tagName: String, name: String) -> Bool {
        if endpointPolicy.loopbackOrigin != nil {
            return endpointPolicy.allows(url)
        }
        guard url.scheme == "https", url.host?.lowercased() == "github.com" else { return false }
        return url.pathComponents == [
            "/", Self.repositoryOwner, Self.repositoryName, "releases", "download", tagName, name,
        ]
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let downloadURL: URL

    enum CodingKeys: String, CodingKey {
        case name
        case downloadURL = "browser_download_url"
    }
}

private enum SoftwareUpdateError: LocalizedError {
    case invalidRelease
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRelease:
            "The latest release is missing its signed update files."
        case .invalidResponse:
            "The update server returned an invalid response."
        }
    }
}
#endif
