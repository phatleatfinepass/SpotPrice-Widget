import Foundation

enum GridSignalState: Int, Codable, CaseIterable, Sendable {
    case low = 0
    case average = 1
    case high = 2

    var title: String {
        switch self {
        case .low: "Low"
        case .average: "Average"
        case .high: "High"
        }
    }
}

struct GridSignalThresholds: Hashable, Sendable {
    let lower: Double
    let upper: Double
}

struct GridForecastSignalPoint: Hashable, Identifiable, Sendable {
    let dateTime: Date
    let renewableShare: Double
    let smoothedRenewableShare: Double
    let state: GridSignalState

    var id: Date { dateTime }
}

enum FinlandRenewableSignal {
    private static let smoothingSlotCount = 4
    private static let hysteresis = 1.0

    // P33/P67 of Finland's hourly renewable share for each calendar month.
    // Every year is normalized to hourly grain before pooling, so the newer
    // 15-minute history is not weighted four times more than older data.
    // Source window: Energy-Charts public-power data, 2023–2025.
    private static let monthlyThresholds: [Int: GridSignalThresholds] = [
        1: .init(lower: 39.6, upper: 54.0),
        2: .init(lower: 39.3, upper: 52.7),
        3: .init(lower: 37.9, upper: 51.4),
        4: .init(lower: 41.7, upper: 51.8),
        5: .init(lower: 45.6, upper: 58.0),
        6: .init(lower: 42.9, upper: 53.0),
        7: .init(lower: 36.1, upper: 46.7),
        8: .init(lower: 39.7, upper: 48.9),
        9: .init(lower: 46.2, upper: 60.0),
        10: .init(lower: 45.6, upper: 61.5),
        11: .init(lower: 40.2, upper: 56.8),
        12: .init(lower: 40.0, upper: 56.8),
    ]

    static func thresholds(
        at date: Date,
        calendar: Calendar = .helsinki
    ) -> GridSignalThresholds {
        monthlyThresholds[calendar.component(.month, from: date)]
            ?? GridSignalThresholds(lower: 40, upper: 55)
    }

    static func classify(
        points: [GridForecastPoint],
        calendar: Calendar = .helsinki
    ) -> [GridForecastSignalPoint] {
        let sorted = points
            .filter { $0.renewableShare != nil }
            .sorted { $0.dateTime < $1.dateTime }
        guard !sorted.isEmpty else { return [] }

        var previousState: GridSignalState?
        return sorted.indices.compactMap { index in
            guard let share = sorted[index].renewableShare else { return nil }
            let windowEnd = min(index + smoothingSlotCount, sorted.count)
            let windowShares = sorted[index..<windowEnd].compactMap { point -> Double? in
                guard point.dateTime.timeIntervalSince(sorted[index].dateTime) < 60 * 60 else {
                    return nil
                }
                return point.renewableShare
            }
            let smoothedShare = windowShares.isEmpty
                ? share
                : windowShares.reduce(0, +) / Double(windowShares.count)
            let thresholds = thresholds(at: sorted[index].dateTime, calendar: calendar)

            let state: GridSignalState
            if sorted[index].signal == -1 {
                // Keep an explicit provider congestion warning conservative.
                state = .low
            } else {
                state = classifiedState(
                    for: smoothedShare,
                    thresholds: thresholds,
                    previousState: previousState
                )
            }
            previousState = state

            return GridForecastSignalPoint(
                dateTime: sorted[index].dateTime,
                renewableShare: share,
                smoothedRenewableShare: smoothedShare,
                state: state
            )
        }
    }

    private static func classifiedState(
        for share: Double,
        thresholds: GridSignalThresholds,
        previousState: GridSignalState?
    ) -> GridSignalState {
        guard let previousState else {
            if share < thresholds.lower { return .low }
            if share > thresholds.upper { return .high }
            return .average
        }

        switch previousState {
        case .low:
            if share > thresholds.upper + hysteresis { return .high }
            if share > thresholds.lower + hysteresis { return .average }
            return .low
        case .average:
            if share < thresholds.lower - hysteresis { return .low }
            if share > thresholds.upper + hysteresis { return .high }
            return .average
        case .high:
            if share < thresholds.lower - hysteresis { return .low }
            if share < thresholds.upper - hysteresis { return .average }
            return .high
        }
    }
}

struct GridForecastPoint: Codable, Hashable, Identifiable, Sendable {
    let dateTime: Date
    let renewableShare: Double?
    let signal: Int?

    var id: Date { dateTime }

    var providerState: GridSignalState? {
        switch signal {
        case 0: .low
        case 1: .average
        case 2: .high
        // Energy-Charts reserves -1 for grid congestion. Keep the three-level
        // timeline safe and conservative by displaying it on the Low level.
        case -1: .low
        default: nil
        }
    }
}

struct GridSignalRun: Hashable, Identifiable, Sendable {
    let state: GridSignalState
    let start: Date
    let end: Date

    var id: Date { start }
}

struct GridForecastPresentation: Hashable, Sendable {
    let referenceDate: Date
    let locationName: String
    let currentState: GridSignalState
    let currentRenewableShare: Double?
    let stateEndsAt: Date?
    let signalRuns: [GridSignalRun]
    let forecastPoints: [GridForecastSignalPoint]
    let signalThresholds: GridSignalThresholds
    let timelineStart: Date
    let timelineEnd: Date
    let lastUpdated: Date
    let availableThrough: Date?
    let isStale: Bool
    let isUnavailable: Bool

    static func make(
        points: [GridForecastPoint],
        at now: Date,
        lastUpdated: Date,
        availableThrough: Date?,
        isStale: Bool,
        locationName: String = "Finland"
    ) -> GridForecastPresentation? {
        let classified = FinlandRenewableSignal.classify(points: points)
        guard !classified.isEmpty else { return nil }

        let slotDuration: TimeInterval = 15 * 60
        let current = classified.last(where: {
            $0.dateTime <= now && now < $0.dateTime.addingTimeInterval(slotDuration)
        }) ?? classified.first(where: { $0.dateTime > now }) ?? classified.last!

        let start = current.dateTime
        let state = current.state
        let future = classified.filter { $0.dateTime >= current.dateTime }
        let stateEndsAt = future.first(where: { $0.state != state })?.dateTime

        let requestedEnd = start.addingTimeInterval(24 * 60 * 60)
        let dataEnd = availableThrough
            ?? classified.last!.dateTime.addingTimeInterval(slotDuration)
        let end = min(requestedEnd, dataEnd)
        guard end > start else { return nil }

        let visiblePoints = classified.filter {
            $0.dateTime < end && $0.dateTime.addingTimeInterval(slotDuration) > start
        }

        var runs: [GridSignalRun] = []
        var openState: GridSignalState?
        var openStart: Date?
        var openEnd: Date?

        for point in visiblePoints {
            let pointState = point.state
            let slotStart = max(point.dateTime, start)
            let slotEnd = min(point.dateTime.addingTimeInterval(slotDuration), end)

            if openState == pointState, openEnd == slotStart {
                openEnd = slotEnd
            } else {
                if let openState, let openStart, let openEnd {
                    runs.append(GridSignalRun(state: openState, start: openStart, end: openEnd))
                }
                openState = pointState
                openStart = slotStart
                openEnd = slotEnd
            }
        }

        if let openState, let openStart, let openEnd {
            runs.append(GridSignalRun(state: openState, start: openStart, end: openEnd))
        }

        return GridForecastPresentation(
            referenceDate: now,
            locationName: locationName,
            currentState: state,
            currentRenewableShare: current.renewableShare,
            stateEndsAt: stateEndsAt,
            signalRuns: runs,
            forecastPoints: visiblePoints,
            signalThresholds: FinlandRenewableSignal.thresholds(at: start),
            timelineStart: start,
            timelineEnd: end,
            lastUpdated: lastUpdated,
            availableThrough: availableThrough,
            isStale: isStale,
            isUnavailable: false
        )
    }

    static func sample(at now: Date = Date(), calendar: Calendar = .helsinki) -> GridForecastPresentation {
        let start = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let roundedStart = calendar.date(
            bySetting: .minute,
            value: (calendar.component(.minute, from: start) / 15) * 15,
            of: start
        ) ?? start

        let points = (0..<96).map { index -> GridForecastPoint in
            let date = roundedStart.addingTimeInterval(Double(index) * 15 * 60)
            let thresholds = FinlandRenewableSignal.thresholds(at: date, calendar: calendar)
            let renewableShare: Double
            switch index {
            case 10..<24, 64..<72:
                renewableShare = thresholds.upper + 5
            case 40..<48:
                renewableShare = thresholds.lower - 5
            default:
                renewableShare = (thresholds.lower + thresholds.upper) / 2
            }
            return GridForecastPoint(
                dateTime: date,
                renewableShare: renewableShare,
                signal: 1
            )
        }

        return make(
            points: points,
            at: now,
            lastUpdated: now,
            availableThrough: roundedStart.addingTimeInterval(24 * 60 * 60),
            isStale: false
        ) ?? unavailable(at: now)
    }

    static func unavailable(at now: Date = Date()) -> GridForecastPresentation {
        GridForecastPresentation(
            referenceDate: now,
            locationName: "Finland",
            currentState: .average,
            currentRenewableShare: nil,
            stateEndsAt: nil,
            signalRuns: [],
            forecastPoints: [],
            signalThresholds: FinlandRenewableSignal.thresholds(at: now),
            timelineStart: now,
            timelineEnd: now.addingTimeInterval(24 * 60 * 60),
            lastUpdated: now,
            availableThrough: nil,
            isStale: true,
            isUnavailable: true
        )
    }

    var statusSentence: String {
        guard !isUnavailable else { return "Electricity forecast unavailable." }

        switch currentState {
        case .high:
            if let nextRun {
                return "Electricity is clean until \(formattedTime(nextRun.start))."
            } else {
                return "Electricity stays clean for the next 24 hours."
            }
        case .average:
            if let nextRun {
                switch nextRun.state {
                case .high:
                    return "Electricity will be cleaner from \(formattedTime(nextRun.start))."
                case .low:
                    return "Electricity will be less clean from \(formattedTime(nextRun.start))."
                case .average:
                    break
                }
            }
            return "Grid conditions stay steady."
        case .low:
            if let nextRun {
                return "Electricity is less clean until \(formattedTime(nextRun.start))."
            } else {
                return "Electricity stays less clean for the next 24 hours."
            }
        }
    }

    var conciseStatusSentence: String {
        guard !isUnavailable else { return "Renewable forecast unavailable" }
        return "\(conciseLevelText) · \(conciseTimingText.lowercased())"
    }

    var conciseLevelText: String {
        guard !isUnavailable else { return "Renewable forecast" }
        return "Renewable share \(currentState.title.lowercased())"
    }

    var conciseTimingText: String {
        guard !isUnavailable else { return "Renewable forecast unavailable" }

        switch currentState {
        case .high:
            if let nextRun {
                return "Until \(formattedTime(nextRun.start))"
            }
            return "Next 24 hours"
        case .average:
            if let highRun = signalRuns.first(where: { $0.state == .high && $0.start > timelineStart }) {
                return "Higher from \(formattedTime(highRun.start))"
            }
            return "Next 24 hours"
        case .low:
            if let nextRun {
                return "Improves from \(formattedTime(nextRun.start))"
            }
            return "Next 24 hours"
        }
    }

    private var nextRun: GridSignalRun? {
        signalRuns.dropFirst().first
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    var accessibilitySummary: String {
        let share = currentRenewableShare.map {
            " Current renewable share \($0.formatted(.number.precision(.fractionLength(0)))) percent."
        } ?? ""
        return "\(locationName) renewable forecast.\(share) \(statusSentence)"
    }
}

struct GridForecastLoadResult: Sendable {
    let points: [GridForecastPoint]
    let fetchedAt: Date
    let availableThrough: Date?
    let isStale: Bool
}

enum GridForecastAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case noForecast

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The grid-forecast URL is invalid."
        case .invalidResponse: "The grid-forecast service returned an invalid response."
        case let .httpStatus(status): "The grid-forecast service returned HTTP \(status)."
        case .noForecast: "No Finland grid forecast is currently available."
        }
    }
}

struct GridForecastAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchForecast() async throws -> GridForecastLoadResult {
        var components = URLComponents(string: "https://api.energy-charts.info/v2/signal")
        components?.queryItems = [URLQueryItem(name: "country", value: "fi")]
        guard let url = components?.url else { throw GridForecastAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw GridForecastAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GridForecastAPIError.httpStatus(response.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(GridSignalEnvelope.self, from: data)
        let points = envelope.data.compactMap { datum -> GridForecastPoint? in
            guard let share = datum.values.share else { return nil }
            return GridForecastPoint(
                dateTime: datum.timestamp,
                renewableShare: share,
                signal: datum.values.signal
            )
        }
        .sorted { $0.dateTime < $1.dateTime }

        guard !points.isEmpty else { throw GridForecastAPIError.noForecast }
        return GridForecastLoadResult(
            points: points,
            fetchedAt: envelope.generatedAt,
            availableThrough: envelope.availableUntil,
            isStale: false
        )
    }
}

struct GridForecastRepository {
    private let client: GridForecastAPIClient
    private let cache: GridForecastCache

    init(
        client: GridForecastAPIClient = GridForecastAPIClient(),
        cache: GridForecastCache = GridForecastCache()
    ) {
        self.client = client
        self.cache = cache
    }

    func load() async throws -> GridForecastLoadResult {
        do {
            let result = try await client.fetchForecast()
            cache.save(result)
            return result
        } catch {
            if let cached = cache.load() {
                return GridForecastLoadResult(
                    points: cached.points,
                    fetchedAt: cached.fetchedAt,
                    availableThrough: cached.availableThrough,
                    isStale: true
                )
            }
            throw error
        }
    }
}

struct GridForecastCache {
    private let defaults: UserDefaults
    private let key = "finland-grid-forecast-cache-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ result: GridForecastLoadResult) {
        let payload = Payload(
            fetchedAt: result.fetchedAt,
            availableThrough: result.availableThrough,
            points: result.points
        )
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
        let availableThrough: Date?
        let points: [GridForecastPoint]
    }
}

private struct GridSignalEnvelope: Decodable {
    let generatedAt: Date
    let availableUntil: Date?
    let data: [GridSignalDatum]

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case availableUntil = "available_until"
        case data
    }
}

private struct GridSignalDatum: Decodable {
    let timestamp: Date
    let values: GridSignalValues
}

private struct GridSignalValues: Decodable {
    let share: Double?
    let signal: Int?
}
