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
    private static let expectedSlotDuration: TimeInterval = 15 * 60
    private static let smoothingDuration: TimeInterval = 60 * 60
    private static let minimumSignalDuration: TimeInterval = 60 * 60
    private static let timestampTolerance: TimeInterval = 2
    private static let minimumWindowPointCount = 4
    private static let minimumWindowIQR = 3.0
    private static let highEntryPercentile = 0.75
    private static let highExitPercentile = 0.65
    private static let lowEntryPercentile = 0.25
    private static let lowExitPercentile = 0.35

    static func thresholds(
        at date: Date,
        calendar: Calendar = .helsinki
    ) -> GridSignalThresholds {
        FinlandRenewableBaseline.thresholds(at: date, calendar: calendar)
    }

    static func classify(
        points: [GridForecastPoint],
        calendar: Calendar = .helsinki
    ) -> [GridForecastSignalPoint] {
        let sorted = points
            .filter { point in
                guard let share = point.renewableShare else { return false }
                return (0...100).contains(share)
            }
            .sorted { $0.dateTime < $1.dateTime }
        guard !sorted.isEmpty else { return [] }

        let cadence = inferredCadence(in: sorted)
        let cadenceIsSupported = abs(cadence - expectedSlotDuration) <= timestampTolerance
        let smoothed = sorted.indices.map { index in
            forwardMean(at: index, in: sorted, cadence: cadence)
        }
        let windowValues = smoothed.compactMap { $0 }
        let windowIsDecisive: Bool = {
            guard
                cadenceIsSupported,
                windowValues.count >= minimumWindowPointCount,
                let lowerQuartile = quantile(0.25, in: windowValues),
                let upperQuartile = quantile(0.75, in: windowValues)
            else { return false }
            return upperQuartile - lowerQuartile >= minimumWindowIQR
        }()

        var drafts: [ClassifiedDraft] = []
        var previousState = GridSignalState.average
        var previousDate: Date?

        for index in sorted.indices {
            guard let share = sorted[index].renewableShare else { continue }
            let providerWarning = sorted[index].signal == -1
            let isContiguous = previousDate.map {
                abs(sorted[index].dateTime.timeIntervalSince($0) - cadence) <= timestampTolerance
            } ?? true
            if !isContiguous {
                previousState = .average
            }

            let state: GridSignalState
            if providerWarning {
                // Energy-Charts reserves -1 for grid congestion. It remains an
                // immediate warning even when the renewable signal is neutral.
                state = .low
            } else if windowIsDecisive,
                      let smoothedShare = smoothed[index] {
                let percentile = midrankPercentile(of: smoothedShare, in: windowValues)
                state = classifiedState(
                    for: smoothedShare,
                    windowPercentile: percentile,
                    thresholds: thresholds(at: sorted[index].dateTime, calendar: calendar),
                    previousState: previousState
                )
            } else {
                state = .average
            }

            drafts.append(ClassifiedDraft(
                dateTime: sorted[index].dateTime,
                renewableShare: share,
                smoothedRenewableShare: smoothed[index] ?? share,
                state: state,
                providerWarning: providerWarning
            ))
            previousState = state
            previousDate = sorted[index].dateTime
        }

        enforceMinimumRunDuration(in: &drafts, cadence: cadence)
        return drafts.map {
            GridForecastSignalPoint(
                dateTime: $0.dateTime,
                renewableShare: $0.renewableShare,
                smoothedRenewableShare: $0.smoothedRenewableShare,
                state: $0.state
            )
        }
    }

    private static func classifiedState(
        for share: Double,
        windowPercentile: Double,
        thresholds: GridSignalThresholds,
        previousState: GridSignalState
    ) -> GridSignalState {
        let historicalHigh = share >= thresholds.upper
        let historicalLow = share <= thresholds.lower
        let entersHigh = historicalHigh && windowPercentile >= highEntryPercentile
        let entersLow = historicalLow && windowPercentile <= lowEntryPercentile

        switch previousState {
        case .low:
            if entersHigh { return .high }
            if historicalLow, windowPercentile <= lowExitPercentile { return .low }
            return .average
        case .average:
            if entersLow { return .low }
            if entersHigh { return .high }
            return .average
        case .high:
            if entersLow { return .low }
            if historicalHigh, windowPercentile >= highExitPercentile { return .high }
            return .average
        }
    }

    private static func forwardMean(
        at index: Int,
        in points: [GridForecastPoint],
        cadence: TimeInterval
    ) -> Double? {
        guard abs(cadence - expectedSlotDuration) <= timestampTolerance else { return nil }
        let requiredCount = Int((smoothingDuration / cadence).rounded())
        guard requiredCount > 0, index + requiredCount <= points.count else { return nil }

        let start = points[index].dateTime
        var values: [Double] = []
        for offset in 0..<requiredCount {
            let point = points[index + offset]
            let expectedDate = start.addingTimeInterval(Double(offset) * cadence)
            guard
                abs(point.dateTime.timeIntervalSince(expectedDate)) <= timestampTolerance,
                let share = point.renewableShare,
                (0...100).contains(share)
            else { return nil }
            values.append(share)
        }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func inferredCadence(in points: [GridForecastPoint]) -> TimeInterval {
        let differences = zip(points, points.dropFirst())
            .map { $1.dateTime.timeIntervalSince($0.dateTime) }
            .filter { $0 > 0 && $0 <= smoothingDuration }
            .sorted()
        guard !differences.isEmpty else { return expectedSlotDuration }
        return differences[differences.count / 2]
    }

    private static func midrankPercentile(of value: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.5 }
        let below = values.lazy.filter { $0 < value }.count
        let equal = values.lazy.filter { abs($0 - value) < 0.000_001 }.count
        return (Double(below) + Double(equal) / 2) / Double(values.count)
    }

    private static func quantile(_ probability: Double, in values: [Double]) -> Double? {
        let sorted = values.sorted()
        guard let first = sorted.first else { return nil }
        guard sorted.count > 1 else { return first }
        let position = probability * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
    }

    private static func enforceMinimumRunDuration(
        in drafts: inout [ClassifiedDraft],
        cadence: TimeInterval
    ) {
        guard cadence > 0 else { return }
        var index = 0
        while index < drafts.count {
            let state = drafts[index].state
            guard state != .average else {
                index += 1
                continue
            }

            var end = index + 1
            while end < drafts.count,
                  drafts[end].state == state,
                  abs(drafts[end].dateTime.timeIntervalSince(drafts[end - 1].dateTime) - cadence)
                    <= timestampTolerance {
                end += 1
            }

            let duration = Double(end - index) * cadence
            if duration < minimumSignalDuration {
                for runIndex in index..<end where !drafts[runIndex].providerWarning {
                    drafts[runIndex].state = .average
                }
            }
            index = end
        }
    }

    private struct ClassifiedDraft {
        let dateTime: Date
        let renewableShare: Double
        let smoothedRenewableShare: Double
        var state: GridSignalState
        let providerWarning: Bool
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
        let slotDuration: TimeInterval = 15 * 60
        let sorted = points
            .filter { point in
                guard let share = point.renewableShare else { return false }
                return (0...100).contains(share)
            }
            .sorted { $0.dateTime < $1.dateTime }
        guard !sorted.isEmpty else { return nil }

        guard let currentRaw = sorted.last(where: {
            $0.dateTime <= now && now < $0.dateTime.addingTimeInterval(slotDuration)
        }) else {
            // A forecast must actually contain the wall clock. Do not present
            // an expired point, a future-only point, or a gap as "current."
            return nil
        }

        let coverageStart = currentRaw.dateTime
        let timelineStart = now
        let requestedEnd = timelineStart.addingTimeInterval(24 * 60 * 60)
        // `available_until` is documented and observed as the last record's
        // start. Repositories now normalize it to an exclusive coverage end;
        // maxing with the final record also repairs older cached payloads.
        let finalRecordEnd = sorted.last!.dateTime.addingTimeInterval(slotDuration)
        let dataEnd = max(availableThrough ?? finalRecordEnd, finalRecordEnd)
        let end = min(requestedEnd, dataEnd)
        guard end > timelineStart else { return nil }

        let visibleRawPoints = sorted.filter {
            $0.dateTime < end
                && $0.dateTime.addingTimeInterval(slotDuration) > timelineStart
        }
        let classified = FinlandRenewableSignal.classify(points: visibleRawPoints)
        guard !classified.isEmpty else { return nil }

        guard let current = classified.last(where: {
            $0.dateTime <= now && now < $0.dateTime.addingTimeInterval(slotDuration)
        }) else { return nil }
        let state = current.state
        let visiblePoints = classified

        var runs: [GridSignalRun] = []
        var openState: GridSignalState?
        var openStart: Date?
        var openEnd: Date?

        for point in visiblePoints {
            let pointState = point.state
            let slotStart = max(point.dateTime, timelineStart)
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
        let stateEndsAt = runs.first?.end

        return GridForecastPresentation(
            referenceDate: now,
            locationName: locationName,
            currentState: state,
            currentRenewableShare: current.renewableShare,
            stateEndsAt: stateEndsAt,
            signalRuns: runs,
            forecastPoints: visiblePoints,
            signalThresholds: FinlandRenewableSignal.thresholds(at: coverageStart),
            timelineStart: timelineStart,
            timelineEnd: end,
            lastUpdated: lastUpdated,
            availableThrough: dataEnd,
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
            if let end = currentStateDisplayEnd {
                return "Electricity is clean until \(formattedTime(end))."
            }
            return "Electricity stays clean for the next 24 hours."
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
            if let end = currentStateDisplayEnd {
                return "Electricity is less clean until \(formattedTime(end))."
            }
            return "Electricity stays less clean for the next 24 hours."
        }
    }

    var conciseStatusSentence: String {
        guard !isUnavailable else { return "Renewable forecast unavailable" }
        return "\(conciseLevelText) · \(conciseTimingText.lowercased())"
    }

    /// Short, decision-oriented copy for the supporting renewable timeline.
    /// Neutral is intentionally described as a lack of strong signal instead
    /// of an all-day "average" condition.
    var outlookSentence: String {
        guard !isUnavailable, !isStale else { return "Renewable outlook unavailable" }

        if currentState == .high {
            if let end = currentStateDisplayEnd {
                return "Cleaner until \(formattedTime(end))"
            }
            return "Cleaner period now"
        }
        if currentState == .low {
            if let end = currentStateDisplayEnd {
                return "Less clean until \(formattedTime(end))"
            }
            return "Less-clean period now"
        }

        guard let next = signalRuns.first(where: {
            $0.start > timelineStart && $0.state != .average
        }) else {
            return "No strong signal soon"
        }
        switch next.state {
        case .high:
            return "Cleaner from \(formattedTime(next.start))"
        case .low:
            return "Less clean from \(formattedTime(next.start))"
        case .average:
            return "No strong signal soon"
        }
    }

    var conciseLevelText: String {
        guard !isUnavailable else { return "Renewable forecast" }
        return "Renewable share \(currentState.title.lowercased())"
    }

    var conciseTimingText: String {
        guard !isUnavailable else { return "Renewable forecast unavailable" }

        switch currentState {
        case .high:
            if let end = currentStateDisplayEnd {
                return "Until \(formattedTime(end))"
            }
            return "Next 24 hours"
        case .average:
            if let highRun = signalRuns.first(where: { $0.state == .high && $0.start > timelineStart }) {
                return "Higher from \(formattedTime(highRun.start))"
            }
            return "Next 24 hours"
        case .low:
            if let end = currentStateDisplayEnd {
                return "Improves from \(formattedTime(end))"
            }
            return "Next 24 hours"
        }
    }

    private var nextRun: GridSignalRun? {
        signalRuns.dropFirst().first
    }

    private var currentStateDisplayEnd: Date? {
        guard let stateEndsAt else { return nil }
        let hasFullDayCoverage = timelineEnd.timeIntervalSince(timelineStart) >= 24 * 60 * 60 - 1
        return stateEndsAt < timelineEnd || !hasFullDayCoverage ? stateEndsAt : nil
    }

    private func formattedTime(_ date: Date) -> String {
        FinlandTime.clock(date)
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
        guard
            envelope.schemaVersion == "2.0",
            envelope.endpoint == "signal",
            envelope.country?.lowercased() == "fi",
            envelope.timezone == "Europe/Helsinki",
            envelope.resolution == "PT15M",
            envelope.intervalMinutes == 15,
            !envelope.deprecated
        else { throw GridForecastAPIError.invalidResponse }

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
        let slotDuration: TimeInterval = 15 * 60
        let finalRecordEnd = points.last!.dateTime.addingTimeInterval(slotDuration)
        let declaredEnd = envelope.availableUntil?.addingTimeInterval(slotDuration)
        let coverageEnd = max(declaredEnd ?? finalRecordEnd, finalRecordEnd)
        return GridForecastLoadResult(
            points: points,
            fetchedAt: envelope.generatedAt,
            availableThrough: coverageEnd,
            // Substituted or metadata-ambiguous forecasts remain visible but
            // deliberately lose green/red confidence coloring.
            isStale: envelope.substituteFlag != false
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
    private let key = WidgetDataStore.gridForecastCacheKey

    init() {
        self.defaults = WidgetDataStore.defaults(preparing: WidgetDataStore.gridForecastCacheKey)
    }

    init(defaults: UserDefaults) {
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
    let schemaVersion: String
    let endpoint: String
    let country: String?
    let timezone: String
    let resolution: String?
    let intervalMinutes: Int?
    let generatedAt: Date
    let availableFrom: Date?
    let availableUntil: Date?
    let attributes: [String: String]?
    let deprecated: Bool
    let data: [GridSignalDatum]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case endpoint
        case country
        case timezone
        case resolution
        case intervalMinutes = "interval_minutes"
        case generatedAt = "generated_at"
        case availableFrom = "available_from"
        case availableUntil = "available_until"
        case attributes
        case deprecated
        case data
    }

    var substituteFlag: Bool? {
        guard let raw = attributes?["substitute"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        else { return nil }
        return switch raw {
        case "true": true
        case "false": false
        default: nil
        }
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
