import Foundation

enum SpotPriceBand: String, Codable, CaseIterable, Sendable {
    case low
    case typical
    case high

    var title: String {
        switch self {
        case .low: "Low price"
        case .typical: "Typical price"
        case .high: "High price"
        }
    }

    static func from(priceCents: Double) -> SpotPriceBand {
        if priceCents < 4.99 { return .low }
        if priceCents <= 8.99 { return .typical }
        return .high
    }
}

struct SpotPricePoint: Codable, Hashable, Identifiable, Sendable {
    let rank: Int?
    let dateTime: Date
    let priceNoTax: Double?
    let priceWithTax: Double

    var id: Date { dateTime }
    var centsWithTax: Double { priceWithTax * 100 }
    var band: SpotPriceBand { SpotPriceBand.from(priceCents: centsWithTax) }

    enum CodingKeys: String, CodingKey {
        case rank = "Rank"
        case dateTime = "DateTime"
        case priceNoTax = "PriceNoTax"
        case priceWithTax = "PriceWithTax"
    }
}

struct HourlySpotPrice: Hashable, Identifiable, Sendable {
    let start: Date
    let priceCents: Double
    let averageRank: Double?

    var id: Date { start }
    var band: SpotPriceBand { SpotPriceBand.from(priceCents: priceCents) }
}

struct SpotPriceStatistics: Hashable, Sendable {
    let minimum: Double
    let average: Double
    let maximum: Double

    static let empty = SpotPriceStatistics(minimum: 0, average: 0, maximum: 0)
}

struct SpotPricePresentation: Hashable, Sendable {
    let referenceDate: Date
    let currentPriceCents: Double
    let currentBand: SpotPriceBand
    let currentRankProgress: Double
    let bandEndsAt: Date?
    let upcomingHours: [HourlySpotPrice]
    let statistics: SpotPriceStatistics
    let lastUpdated: Date
    let availableThrough: Date?
    let isStale: Bool
    let isUnavailable: Bool

    static func make(
        points: [SpotPricePoint],
        at now: Date,
        lastUpdated: Date,
        isStale: Bool,
        calendar: Calendar = .helsinki
    ) -> SpotPricePresentation? {
        let sortedPoints = points.sorted { $0.dateTime < $1.dateTime }
        guard !sortedPoints.isEmpty else { return nil }

        let slotDuration: TimeInterval = 15 * 60
        guard let current = sortedPoints.last(where: {
            $0.dateTime <= now && now < $0.dateTime.addingTimeInterval(slotDuration)
        }) else {
            // Never label an expired cache entry or a future-only slot as the
            // current rate. A missing current interval is unavailable data.
            return nil
        }

        let currentBand = current.band
        var bandEndsAt = current.dateTime.addingTimeInterval(slotDuration)
        var previous = current
        for point in sortedPoints where point.dateTime > current.dateTime {
            let expectedStart = previous.dateTime.addingTimeInterval(slotDuration)
            guard abs(point.dateTime.timeIntervalSince(expectedStart)) <= 2 else { break }
            guard point.band == currentBand else {
                bandEndsAt = point.dateTime
                break
            }
            bandEndsAt = point.dateTime.addingTimeInterval(slotDuration)
            previous = point
        }

        let rankProgress: Double
        if let rank = current.rank {
            rankProgress = min(max((Double(rank) - 1) / 95, 0), 1)
        } else {
            rankProgress = 0.5
        }

        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(24 * 60 * 60)
        let hourlySource = sortedPoints.filter {
            $0.dateTime >= dayStart && $0.dateTime < dayEnd
        }

        let grouped = Dictionary(grouping: hourlySource) {
            calendar.dateInterval(of: .hour, for: $0.dateTime)?.start ?? $0.dateTime
        }

        let upcomingHours = grouped.keys.sorted().prefix(24).compactMap { start -> HourlySpotPrice? in
            guard let values = grouped[start], !values.isEmpty else { return nil }
            let price = values.map(\.centsWithTax).reduce(0, +) / Double(values.count)
            let ranks = values.compactMap(\.rank).map(Double.init)
            let averageRank = ranks.isEmpty ? nil : ranks.reduce(0, +) / Double(ranks.count)
            return HourlySpotPrice(start: start, priceCents: price, averageRank: averageRank)
        }

        let statistics: SpotPriceStatistics
        if upcomingHours.isEmpty {
            statistics = .empty
        } else {
            let prices = upcomingHours.map(\.priceCents)
            statistics = SpotPriceStatistics(
                minimum: prices.min() ?? 0,
                average: prices.reduce(0, +) / Double(prices.count),
                maximum: prices.max() ?? 0
            )
        }

        return SpotPricePresentation(
            referenceDate: now,
            currentPriceCents: current.centsWithTax,
            currentBand: currentBand,
            currentRankProgress: rankProgress,
            bandEndsAt: bandEndsAt,
            upcomingHours: upcomingHours,
            statistics: statistics,
            lastUpdated: lastUpdated,
            availableThrough: sortedPoints.last?.dateTime.addingTimeInterval(slotDuration),
            isStale: isStale,
            isUnavailable: false
        )
    }

    static func sample(at now: Date = Date(), calendar: Calendar = .helsinki) -> SpotPricePresentation {
        let dayStart = calendar.startOfDay(for: now)
        let prices = [8.4, 7.6, 6.2, 4.8, 3.9, 5.1, 7.4, 10.2, 13.8, 16.4, 14.1, 11.7,
                      9.6, 8.8, 7.9, 9.2, 12.4, 15.8, 18.1, 14.7, 11.3, 9.1, 7.2, 6.5]
        let upcoming = prices.enumerated().map { index, price in
            HourlySpotPrice(
                start: calendar.date(byAdding: .hour, value: index, to: dayStart) ?? dayStart,
                priceCents: price,
                averageRank: Double(index * 4 + 1)
            )
        }
        return SpotPricePresentation(
            referenceDate: now,
            currentPriceCents: 8.42,
            currentBand: SpotPriceBand.from(priceCents: 8.42),
            currentRankProgress: 0.23,
            bandEndsAt: calendar.date(byAdding: .minute, value: 45, to: now),
            upcomingHours: upcoming,
            statistics: SpotPriceStatistics(minimum: 3.9, average: 10.4, maximum: 18.1),
            lastUpdated: now,
            availableThrough: calendar.date(byAdding: .day, value: 1, to: dayStart),
            isStale: false,
            isUnavailable: false
        )
    }

    static func unavailable(at now: Date = Date()) -> SpotPricePresentation {
        SpotPricePresentation(
            referenceDate: now,
            currentPriceCents: 0,
            currentBand: .typical,
            currentRankProgress: 0,
            bandEndsAt: nil,
            upcomingHours: [],
            statistics: .empty,
            lastUpdated: now,
            availableThrough: nil,
            isStale: true,
            isUnavailable: true
        )
    }
}

struct SpotPriceLoadResult: Sendable {
    let points: [SpotPricePoint]
    let fetchedAt: Date
    let isStale: Bool
}

enum SpotPriceAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case noPrices

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The electricity-price URL is invalid."
        case .invalidResponse: "The price service returned an invalid response."
        case let .httpStatus(status): "The price service returned HTTP \(status)."
        case .noPrices: "No Finland electricity prices are currently available."
        }
    }
}

struct SpotPriceAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchPrices() async throws -> [SpotPricePoint] {
        var components = URLComponents(string: "https://api.spot-hinta.fi/TodayAndDayForward")
        components?.queryItems = [
            URLQueryItem(name: "region", value: "FI"),
            URLQueryItem(name: "priceResolution", value: "15")
        ]
        guard let url = components?.url else { throw SpotPriceAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SpotPriceAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw SpotPriceAPIError.httpStatus(response.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let points = try decoder.decode([SpotPricePoint].self, from: data)
            .sorted { $0.dateTime < $1.dateTime }
        guard !points.isEmpty else { throw SpotPriceAPIError.noPrices }
        return points
    }
}

struct SpotPriceRepository {
    private let client: SpotPriceAPIClient
    private let cache: SpotPriceCache

    init(client: SpotPriceAPIClient = SpotPriceAPIClient(), cache: SpotPriceCache = SpotPriceCache()) {
        self.client = client
        self.cache = cache
    }

    func load() async throws -> SpotPriceLoadResult {
        do {
            let points = try await client.fetchPrices()
            let fetchedAt = Date()
            cache.save(points: points, fetchedAt: fetchedAt)
            return SpotPriceLoadResult(points: points, fetchedAt: fetchedAt, isStale: false)
        } catch {
            if let cached = cache.load() {
                return SpotPriceLoadResult(
                    points: cached.points,
                    fetchedAt: cached.fetchedAt,
                    isStale: true
                )
            }
            throw error
        }
    }
}

struct SpotPriceCache {
    private let defaults: UserDefaults
    private let key = WidgetDataStore.spotPriceCacheKey

    init() {
        self.defaults = WidgetDataStore.defaults(preparing: WidgetDataStore.spotPriceCacheKey)
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func save(points: [SpotPricePoint], fetchedAt: Date) {
        let payload = Payload(fetchedAt: fetchedAt, points: points)
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
        let fetchedAt: Date
        let points: [SpotPricePoint]
    }
}

extension Calendar {
    static var helsinki: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "fi_FI")
        calendar.timeZone = TimeZone(identifier: "Europe/Helsinki") ?? .current
        return calendar
    }
}
