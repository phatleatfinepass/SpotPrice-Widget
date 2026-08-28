import Foundation
import OSLog

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
            measuredAt: date,
            isStale: false
        )
    }

    static func unavailable() -> GridEmissionsPresentation {
        GridEmissionsPresentation(
            gramsCO2PerKWh: nil,
            band: nil,
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

        let (data, response) = try await session.data(for: request)
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

    private static func configuredAPIKey(bundle: Bundle = .main) -> String? {
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

struct GridEmissionsRepository {
    private static let logger = Logger(
        subsystem: "personal.SpotPriceWidget",
        category: "GridEmissions"
    )

    private let client: GridEmissionsAPIClient
    private let cache: GridEmissionsCache
    private let now: () -> Date

    init(
        client: GridEmissionsAPIClient = GridEmissionsAPIClient(),
        cache: GridEmissionsCache = GridEmissionsCache(),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.cache = cache
        self.now = now
    }

    func load() async -> GridEmissionsPresentation {
        let currentDate = now()
        let cached = cache.load()

        do {
            let needsDistribution = cached?.distributionFetchedAt
                .map { currentDate.timeIntervalSince($0) >= 24 * 60 * 60 }
                ?? true
            let lookback = needsDistribution ? 30 * 24 * 60 * 60 : 2 * 60 * 60
            let measurements = try await client.fetchMeasurements(
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
            let presentation = GridEmissionsPresentation(
                gramsCO2PerKWh: latest.value,
                band: band,
                measuredAt: latest.endTime,
                isStale: false
            )
            cache.save(GridEmissionsCache.Payload(
                presentationValue: latest.value,
                presentationBand: band,
                measuredAt: latest.endTime,
                lowerThreshold: lowerThreshold,
                upperThreshold: upperThreshold,
                distributionFetchedAt: distributionFetchedAt,
                cachedAt: currentDate
            ))
            return presentation
        } catch {
            Self.logger.error("Live emissions load failed: \(error.localizedDescription, privacy: .public)")
            guard let cached else { return .unavailable() }
            return GridEmissionsPresentation(
                gramsCO2PerKWh: cached.presentationValue,
                band: cached.presentationBand,
                measuredAt: cached.measuredAt,
                isStale: true
            )
        }
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
        guard let lowerThreshold, let upperThreshold else { return nil }
        if value <= lowerThreshold { return .cleaner }
        if value >= upperThreshold { return .higher }
        return .typical
    }
}

struct GridEmissionsCache {
    private let defaults: UserDefaults
    private let key = "finland-grid-emissions-cache-v1"

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
        let measuredAt: Date
        let lowerThreshold: Double?
        let upperThreshold: Double?
        let distributionFetchedAt: Date?
        let cachedAt: Date
    }
}
