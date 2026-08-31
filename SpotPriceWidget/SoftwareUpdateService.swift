#if os(macOS)
import AppKit
import Combine
import CryptoKit
import Foundation

struct ProductRelease: Equatable, Sendable {
    let version: ReleaseVersion
    let tagName: String
    let diskImageURL: URL
    let checksumURL: URL
    let releasePageURL: URL
}

struct ReleaseVersion: Comparable, Equatable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let normalized = rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue
        let components = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(components[0]),
              let minor = Int(components[1]),
              let patch = Int(components[2])
        else { return nil }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }
}

@MainActor
final class SoftwareUpdateService: ObservableObject {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable
        case downloading
        case installerOpened
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var availableRelease: ProductRelease?
    @Published private(set) var lastChecked: Date?

    let currentVersionText: String

    private static let repositoryOwner = "phatleatfinepass"
    private static let repositoryName = "SpotPrice-Widget"
    private static let diskImageName = "Finland-Electricity-Rates.dmg"
    private static let checksumName = "Finland-Electricity-Rates.dmg.sha256"
    private static let maximumMetadataSize = 1_000_000
    private static let maximumChecksumSize = 4_096
    private static let maximumDiskImageSize = 128 * 1_024 * 1_024

    init(bundle: Bundle = .main) {
        self.currentVersionText = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
    }

    var isBusy: Bool {
        phase == .checking || phase == .downloading
    }

    func checkForUpdates() async {
        guard !isBusy else { return }
        phase = .checking

        do {
            let release = try await Self.fetchLatestRelease(currentVersion: currentVersionText)
            lastChecked = Date()

            guard let currentVersion = ReleaseVersion(currentVersionText) else {
                availableRelease = release
                phase = .updateAvailable
                return
            }

            if release.version > currentVersion {
                availableRelease = release
                phase = .updateAvailable
            } else {
                availableRelease = nil
                phase = .upToDate
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func installAvailableUpdate() async {
        guard !isBusy, let release = availableRelease else { return }
        phase = .downloading

        do {
            async let checksumDownload = Self.download(
                from: release.checksumURL,
                maximumSize: Self.maximumChecksumSize
            )
            async let diskImageDownload = Self.download(
                from: release.diskImageURL,
                maximumSize: Self.maximumDiskImageSize
            )

            let (checksumData, diskImageData) = try await (checksumDownload, diskImageDownload)
            try Self.verify(
                diskImageData: diskImageData,
                checksumData: checksumData
            )

            let diskImage = try Self.saveInstaller(
                diskImageData,
                version: release.version.description
            )
            guard NSWorkspace.shared.open(diskImage) else {
                throw SoftwareUpdateError.couldNotOpenInstaller
            }

            phase = .installerOpened
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func openReleasePage() {
        let destination = availableRelease?.releasePageURL
            ?? URL(string: "https://github.com/phatleatfinepass/SpotPrice-Widget/releases/latest")!
        NSWorkspace.shared.open(destination)
    }

    static func clearDownloadedInstallers() {
        guard let updateDirectory = try? updateDirectory(create: false) else { return }
        try? FileManager.default.removeItem(at: updateDirectory)
    }

    private static func fetchLatestRelease(currentVersion: String) async throws -> ProductRelease {
        let endpoint = URL(
            string: "https://api.github.com/repos/phatleatfinepass/SpotPrice-Widget/releases/latest"
        )!
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(
            "Finland-Electricity-Rates/\(currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )

        let metadata = try await responseData(
            for: request,
            maximumSize: maximumMetadataSize
        )
        let release = try JSONDecoder().decode(GitHubRelease.self, from: metadata)

        guard !release.draft, !release.prerelease,
              let version = ReleaseVersion(release.tagName),
              isTrustedReleasePage(release.htmlURL, tagName: release.tagName),
              let diskImage = release.assets.first(where: { $0.name == diskImageName }),
              let checksum = release.assets.first(where: { $0.name == checksumName }),
              isTrustedAssetURL(diskImage.downloadURL, tagName: release.tagName, name: diskImageName),
              isTrustedAssetURL(checksum.downloadURL, tagName: release.tagName, name: checksumName)
        else {
            throw SoftwareUpdateError.invalidRelease
        }

        return ProductRelease(
            version: version,
            tagName: release.tagName,
            diskImageURL: diskImage.downloadURL,
            checksumURL: checksum.downloadURL,
            releasePageURL: release.htmlURL
        )
    }

    private static func download(from url: URL, maximumSize: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Finland-Electricity-Rates", forHTTPHeaderField: "User-Agent")
        return try await responseData(for: request, maximumSize: maximumSize)
    }

    private static func responseData(for request: URLRequest, maximumSize: Int) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let finalURL = httpResponse.url,
              isTrustedDownloadHost(finalURL),
              data.count <= maximumSize
        else {
            throw SoftwareUpdateError.invalidResponse
        }
        return data
    }

    static func verify(diskImageData: Data, checksumData: Data) throws {
        guard let checksumText = String(data: checksumData, encoding: .utf8),
              let firstLine = checksumText.split(whereSeparator: \.isNewline).first
        else {
            throw SoftwareUpdateError.invalidChecksum
        }

        let fields = firstLine.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 2 else { throw SoftwareUpdateError.invalidChecksum }

        let expected = String(fields[0]).lowercased()
        let publishedName = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        guard expected.count == 64,
              expected.allSatisfy(\.isHexDigit),
              publishedName == diskImageName
        else {
            throw SoftwareUpdateError.invalidChecksum
        }

        let actual = SHA256.hash(data: diskImageData)
            .map { String(format: "%02x", $0) }
            .joined()
        guard actual == expected else {
            throw SoftwareUpdateError.checksumMismatch
        }
    }

    private static func saveInstaller(_ data: Data, version: String) throws -> URL {
        let directory = try updateDirectory(create: true)
        let installer = directory.appendingPathComponent(
            "Finland-Electricity-Rates-\(version).dmg",
            isDirectory: false
        )
        try data.write(to: installer, options: .atomic)
        return installer
    }

    private static func updateDirectory(create: Bool) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: create
        )
        let directory = applicationSupport
            .appendingPathComponent("Finland Electricity Rates", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return directory
    }

    private static func isTrustedDownloadHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "api.github.com"
            || host == "github.com"
            || host == "objects.githubusercontent.com"
            || host == "release-assets.githubusercontent.com"
    }

    private static func isTrustedReleasePage(_ url: URL, tagName: String) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "github.com" else { return false }
        return url.pathComponents == [
            "/", repositoryOwner, repositoryName, "releases", "tag", tagName,
        ]
    }

    private static func isTrustedAssetURL(_ url: URL, tagName: String, name: String) -> Bool {
        guard url.scheme == "https", url.host?.lowercased() == "github.com" else { return false }
        return url.pathComponents == [
            "/", repositoryOwner, repositoryName, "releases", "download", tagName, name,
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
    case invalidChecksum
    case checksumMismatch
    case couldNotOpenInstaller

    var errorDescription: String? {
        switch self {
        case .invalidRelease:
            "The latest release is missing its verified installer files."
        case .invalidResponse:
            "The update server returned an invalid response."
        case .invalidChecksum:
            "The release checksum file is invalid."
        case .checksumMismatch:
            "The downloaded installer failed its integrity check."
        case .couldNotOpenInstaller:
            "The verified installer could not be opened."
        }
    }
}
#endif
