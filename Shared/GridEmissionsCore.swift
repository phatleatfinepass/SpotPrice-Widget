import Foundation
import OSLog

private final class GridEmissionsNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = GridEmissionsNoRedirectDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum GridEmissionsBand: String, Codable, Sendable {
    case cleaner
    case typical
    case higher

    var title: String {
        switch self {
        case .cleaner: "Cleaner than usual"
        case .typical: "Typical emissions"
        case .higher: "Higher than usual"
        }
    }
}

struct GridEmissionsPresentation: Hashable, Sendable {
    let gramsCO2PerKWh: Double?
    let band: GridEmissionsBand?
    let measurementStart: Date?
    let measuredAt: Date?
    let isStale: Bool

    static func sample(
        gramsCO2PerKWh: Double = 34,
        band: GridEmissionsBand = .cleaner,
        at date: Date = Date()
    ) -> GridEmissionsPresentation {
        GridEmissionsPresentation(
            gramsCO2PerKWh: gramsCO2PerKWh,
            band: band,
            measurementStart: date.addingTimeInterval(-15 * 60),
            measuredAt: date,
            isStale: false
        )
    }

    static func unavailable() -> GridEmissionsPresentation {
        GridEmissionsPresentation(
            gramsCO2PerKWh: nil,
            band: nil,
            measurementStart: nil,
            measuredAt: nil,
            isStale: true
        )
    }

    var valueText: String {
        guard let gramsCO2PerKWh else { return "—" }
        return gramsCO2PerKWh.formatted(.number.precision(.fractionLength(0)))
    }

    var statusText: String {
        band?.title ?? "Emission data unavailable"
    }

    var accessibilitySummary: String {
        guard gramsCO2PerKWh != nil else {
            return "Current Finland grid emissions are unavailable."
        }
        let staleNote = isStale ? " Cached value." : ""
        return "Current grid emissions are \(valueText) grams of carbon dioxide per kilowatt-hour. \(statusText).\(staleNote)"
    }
}

struct GridEmissionsMeasurement: Codable, Hashable, Sendable {
    let startTime: Date
    let endTime: Date
    let value: Double
}

struct GridEmissionsLoadResult: Sendable {
    let presentation: GridEmissionsPresentation
    let lowerThreshold: Double?
    let upperThreshold: Double?
    let distributionFetchedAt: Date?
}

private actor GridEmissionsLoadCoordinator {
    static let shared = GridEmissionsLoadCoordinator()

    private var inFlight: Task<GridEmissionsPresentation, Never>?

    func load(
        operation: @escaping @Sendable () async -> GridEmissionsPresentation
    ) async -> GridEmissionsPresentation {
        if let inFlight {
            return await inFlight.value
        }

        let task = Task { await operation() }
        inFlight = task
        let presentation = await task.value
        inFlight = nil
        return presentation
    }
}

enum GridEmissionsAPIError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case noMeasurements

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Set the FINGRID_API_KEY build setting to load Finland grid emissions."
        case .invalidURL: "The Fingrid emissions URL is invalid."
        case .invalidResponse: "Fingrid returned an invalid emissions response."
        case let .httpStatus(status): "Fingrid returned HTTP \(status)."
        case .noMeasurements: "Fingrid returned no emissions measurements."
        }
    }
}

struct GridEmissionsAPIClient {
    private static let datasetID = 396
    private let session: URLSession
    private let apiKey: String?

    init(
        session: URLSession = .shared,
        apiKey: String? = GridEmissionsAPIClient.configuredAPIKey()
    ) {
        self.session = session
        self.apiKey = apiKey
    }

    var hasConfiguredAPIKey: Bool {
        apiKey?.isEmpty == false
    }

    func fetchMeasurements(from start: Date, through end: Date) async throws -> [GridEmissionsMeasurement] {
        guard let apiKey, !apiKey.isEmpty else { throw GridEmissionsAPIError.missingAPIKey }

        var components = URLComponents(string: "https://data.fingrid.fi/api/data")
        components?.queryItems = [
            URLQueryItem(name: "datasets", value: String(Self.datasetID)),
            URLQueryItem(name: "startTime", value: Self.apiDateFormatter.string(from: start)),
            URLQueryItem(name: "endTime", value: Self.apiDateFormatter.string(from: end)),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "oneRowPerTimePeriod", value: "true"),
            URLQueryItem(name: "locale", value: "en"),
            URLQueryItem(name: "pageSize", value: "5000"),
            URLQueryItem(name: "sortBy", value: "startTime"),
            URLQueryItem(name: "sortOrder", value: "asc")
        ]
        guard let url = components?.url else { throw GridEmissionsAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let (data, response) = try await session.data(
            for: request,
            delegate: GridEmissionsNoRedirectDelegate.shared
        )
        guard let response = response as? HTTPURLResponse else {
            throw GridEmissionsAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GridEmissionsAPIError.httpStatus(response.statusCode)
        }

        let measurements = try Self.decodeMeasurements(from: data)
        guard !measurements.isEmpty else { throw GridEmissionsAPIError.noMeasurements }
        return measurements.sorted { $0.startTime < $1.startTime }
    }

    static func configuredAPIKey(bundle: Bundle = .main) -> String? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "FingridAPIKey") as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }

    static func decodeMeasurements(from data: Data) throws -> [GridEmissionsMeasurement] {
        let object = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]

        if let root = object as? [String: Any],
           let envelopeRows = root["data"] as? [[String: Any]] {
            rows = envelopeRows
        } else if let directRows = object as? [[String: Any]] {
            rows = directRows
        } else {
            throw GridEmissionsAPIError.invalidResponse
        }

        return rows.compactMap { row in
            guard
                let startString = row["startTime"] as? String,
                let endString = row["endTime"] as? String,
                let startTime = parseDate(startString),
                let endTime = parseDate(endString),
                let value = emissionValue(in: row)
            else { return nil }

            return GridEmissionsMeasurement(
                startTime: startTime,
                endTime: endTime,
                value: value
            )
        }
    }

    private static func emissionValue(in row: [String: Any]) -> Double? {
        if let value = number(row[String(datasetID)]) ?? number(row["value"]) {
            return value
        }

        if
            let datasets = row["datasets"] as? [[String: Any]],
            let match = datasets.first(where: {
                number($0["datasetId"]).map(Int.init) == datasetID
            })
        {
            return number(match["value"])
        }

        let metadataKeys: Set<String> = [
            "datasetId", "startTime", "endTime", "modifiedAt", "modifiedAtUTC"
        ]
        for (key, rawValue) in row where !metadataKeys.contains(key) {
            if let value = number(rawValue) { return value }
        }

        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static let apiDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

enum GridEmissionsRelayError: LocalizedError {
    case missingURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingURL: "The grid-emissions relay is not configured."
        case .invalidResponse: "The grid-emissions relay returned invalid data."
        case let .httpStatus(status): "The grid-emissions relay returned HTTP \(status)."
        }
    }
}

struct GridEmissionsRelayClient {
    private static let datasetID = 396
    private static let unit = "gCO2/kWh"
    private static let source = "Fingrid Open Data"
    private static let sourceURL = "https://data.fingrid.fi/en/datasets/396"
    private static let attribution = "Source Fingrid / data.fingrid.fi, license CC BY 4.0"
    private static let licenseURL = "https://creativecommons.org/licenses/by/4.0/"

    private let session: URLSession
    private let endpoint: URL?

    init(
        session: URLSession = .shared,
        endpoint: URL? = GridEmissionsRelayClient.configuredURL()
    ) {
        self.session = session
        self.endpoint = endpoint
    }

    var isConfigured: Bool { endpoint != nil }

    func fetchCurrent() async throws -> GridEmissionsLoadResult {
        guard let endpoint else { throw GridEmissionsRelayError.missingURL }

        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(
            for: request,
            delegate: GridEmissionsNoRedirectDelegate.shared
        )
        guard let response = response as? HTTPURLResponse else {
            throw GridEmissionsRelayError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GridEmissionsRelayError.httpStatus(response.statusCode)
        }
        return try Self.decodeCurrent(from: data)
    }

    static func configuredURL(bundle: Bundle = .main) -> URL? {
        guard let rawValue = bundle.object(forInfoDictionaryKey: "GridEmissionsRelayURL") as? String else {
            return nil
        }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !value.isEmpty,
            !value.hasPrefix("$("),
            let url = URL(string: value),
            url.scheme == "https",
            url.host != nil,
            url.port == nil,
            url.user == nil,
            url.password == nil,
            url.path == "/v1/finland/emissions/current",
            url.query == nil,
            url.fragment == nil
        else { return nil }
        return url
    }

    static func decodeCurrent(from data: Data) throws -> GridEmissionsLoadResult {
        let response: ResponsePayload
        do {
            response = try JSONDecoder().decode(ResponsePayload.self, from: data)
        } catch {
            throw GridEmissionsRelayError.invalidResponse
        }

        guard
            response.schemaVersion == 1,
            response.datasetId == datasetID,
            response.unit == unit,
            response.source == source,
            response.sourceUrl == sourceURL,
            response.attribution == attribution,
            response.licenseUrl == licenseURL,
            response.value.isFinite,
            (0...10_000).contains(response.value),
            response.lowerThreshold.isFinite,
            response.upperThreshold.isFinite,
            response.lowerThreshold <= response.upperThreshold,
            let measurementStart = parseDate(response.measurementStart),
            let measurementEnd = parseDate(response.measurementEnd),
            measurementStart < measurementEnd,
            let baselineStart = parseDate(response.baselineStart),
            let baselineEnd = parseDate(response.baselineEnd),
            baselineStart < baselineEnd,
            parseDate(response.sourceFetchedAt) != nil
        else { throw GridEmissionsRelayError.invalidResponse }

        return GridEmissionsLoadResult(
            presentation: GridEmissionsPresentation(
                gramsCO2PerKWh: response.value,
                band: response.band,
                measurementStart: measurementStart,
                measuredAt: measurementEnd,
                isStale: response.stale
            ),
            lowerThreshold: response.lowerThreshold,
            upperThreshold: response.upperThreshold,
            distributionFetchedAt: baselineEnd
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct ResponsePayload: Decodable {
        let schemaVersion: Int
        let datasetId: Int
        let value: Double
        let unit: String
        let measurementStart: String
        let measurementEnd: String
        let band: GridEmissionsBand
        let lowerThreshold: Double
        let upperThreshold: Double
        let baselineStart: String
        let baselineEnd: String
        let sourceFetchedAt: String
        let stale: Bool
        let source: String
        let sourceUrl: String
        let attribution: String
        let licenseUrl: String
    }
}

struct GridEmissionsRepository {
    private static let logger = Logger(
        subsystem: "personal.SpotPriceWidget",
        category: "GridEmissions"
    )

    private let directClient: GridEmissionsAPIClient
    private let relayClient: GridEmissionsRelayClient
    private let cache: GridEmissionsCache
    private let now: () -> Date

    private static let refreshInterval: TimeInterval = 10 * 60

    init(
        client: GridEmissionsAPIClient = GridEmissionsAPIClient(),
        relayClient: GridEmissionsRelayClient = GridEmissionsRelayClient(),
        cache: GridEmissionsCache = GridEmissionsCache(),
        now: @escaping () -> Date = Date.init
    ) {
        self.directClient = client
        self.relayClient = relayClient
        self.cache = cache
        self.now = now
    }

    func load() async -> GridEmissionsPresentation {
        await GridEmissionsLoadCoordinator.shared.load {
            await loadUncoordinated()
        }
    }

    private func loadUncoordinated() async -> GridEmissionsPresentation {
        let currentDate = now()
        let cached = cache.load()

        if let cached, Self.shouldUseCached(cached, at: currentDate) {
            return Self.presentation(from: cached, at: currentDate)
        }

        do {
            let result = try await loadLive(at: currentDate, cached: cached)
            let presentation = result.presentation
            guard
                let value = presentation.gramsCO2PerKWh,
                let measuredAt = presentation.measuredAt
            else { throw GridEmissionsRelayError.invalidResponse }
            cache.save(GridEmissionsCache.Payload(
                presentationValue: value,
                presentationBand: presentation.band,
                measurementStart: presentation.measurementStart,
                measuredAt: measuredAt,
                lowerThreshold: result.lowerThreshold,
                upperThreshold: result.upperThreshold,
                distributionFetchedAt: result.distributionFetchedAt,
                wasStaleWhenCached: presentation.isStale,
                cachedAt: currentDate
            ))
            return presentation
        } catch {
            Self.logger.error("Live emissions load failed: \(error.localizedDescription, privacy: .public)")
            // Another WidgetKit request may have completed while this one was
            // in flight. Reload before declaring the value unavailable.
            guard let fallback = cache.load() ?? cached else { return .unavailable() }
            return Self.presentation(from: fallback, at: currentDate)
        }
    }

    private func loadLive(
        at currentDate: Date,
        cached: GridEmissionsCache.Payload?
    ) async throws -> GridEmissionsLoadResult {
#if DEBUG
        if directClient.hasConfiguredAPIKey {
            do {
                return try await loadDirect(at: currentDate, cached: cached)
            } catch {
                guard relayClient.isConfigured else { throw error }
                return try await relayClient.fetchCurrent()
            }
        }
#endif
        return try await relayClient.fetchCurrent()
    }

    private func loadDirect(
        at currentDate: Date,
        cached: GridEmissionsCache.Payload?
    ) async throws -> GridEmissionsLoadResult {
        let needsDistribution = cached?.distributionFetchedAt
            .map { currentDate.timeIntervalSince($0) >= 24 * 60 * 60 }
            ?? true
        let lookback = needsDistribution ? 30 * 24 * 60 * 60 : 2 * 60 * 60
        let measurements = try await directClient.fetchMeasurements(
            from: currentDate.addingTimeInterval(-Double(lookback)),
            through: currentDate
        )
        guard let latest = measurements.last else { throw GridEmissionsAPIError.noMeasurements }

        let lowerThreshold: Double?
        let upperThreshold: Double?
        let distributionFetchedAt: Date?
        if needsDistribution {
            let values = measurements.map(\.value).sorted()
            lowerThreshold = Self.percentile(0.33, in: values)
            upperThreshold = Self.percentile(0.67, in: values)
            distributionFetchedAt = currentDate
        } else {
            lowerThreshold = cached?.lowerThreshold
            upperThreshold = cached?.upperThreshold
            distributionFetchedAt = cached?.distributionFetchedAt
        }

        let band = Self.band(
            for: latest.value,
            lowerThreshold: lowerThreshold,
            upperThreshold: upperThreshold
        )
        return GridEmissionsLoadResult(
            presentation: GridEmissionsPresentation(
                gramsCO2PerKWh: latest.value,
                band: band,
                measurementStart: latest.startTime,
                measuredAt: latest.endTime,
                isStale: false
            ),
            lowerThreshold: lowerThreshold,
            upperThreshold: upperThreshold,
            distributionFetchedAt: distributionFetchedAt
        )
    }

    static func shouldUseCached(
        _ payload: GridEmissionsCache.Payload,
        at date: Date
    ) -> Bool {
        let cacheAge = date.timeIntervalSince(payload.cachedAt)
        return cacheAge >= 0
            && cacheAge < refreshInterval
            && !(payload.wasStaleWhenCached ?? false)
            && measurementIsCurrent(payload.measuredAt, at: date)
    }

    static func presentation(
        from payload: GridEmissionsCache.Payload,
        at date: Date
    ) -> GridEmissionsPresentation {
        GridEmissionsPresentation(
            gramsCO2PerKWh: payload.presentationValue,
            band: payload.presentationBand,
            measurementStart: payload.measurementStart
                ?? payload.measuredAt.addingTimeInterval(-15 * 60),
            measuredAt: payload.measuredAt,
            isStale: (payload.wasStaleWhenCached ?? false)
                || !measurementIsCurrent(payload.measuredAt, at: date)
        )
    }

    private static func measurementIsCurrent(_ measuredAt: Date, at date: Date) -> Bool {
        let age = date.timeIntervalSince(measuredAt)
        return age >= -5 * 60 && age < GridConditionsSignal.emissionsValidity
    }

    private static func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double? {
        guard !sortedValues.isEmpty else { return nil }
        let index = Int((Double(sortedValues.count - 1) * percentile).rounded())
        return sortedValues[min(max(index, 0), sortedValues.count - 1)]
    }

    private static func band(
        for value: Double,
        lowerThreshold: Double?,
        upperThreshold: Double?
    ) -> GridEmissionsBand? {
        guard
            let lowerThreshold,
            let upperThreshold,
            lowerThreshold < upperThreshold
        else { return .typical }
        if value <= lowerThreshold { return .cleaner }
        if value >= upperThreshold { return .higher }
        return .typical
    }
}

struct GridEmissionsCache {
    private let defaults: UserDefaults
    private let key = "finland-grid-emissions-cache-v2"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ payload: Payload) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(payload) {
            defaults.set(data, forKey: key)
        }
    }

    func load() -> Payload? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Payload.self, from: data)
    }

    struct Payload: Codable, Sendable {
        let presentationValue: Double
        let presentationBand: GridEmissionsBand?
        let measurementStart: Date?
        let measuredAt: Date
        let lowerThreshold: Double?
        let upperThreshold: Double?
        let distributionFetchedAt: Date?
        let wasStaleWhenCached: Bool?
        let cachedAt: Date
    }
}
