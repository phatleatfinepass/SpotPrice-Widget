import Combine
import Foundation
import WidgetKit

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var pricePresentation: SpotPricePresentation?
    @Published private(set) var priceDays: [DashboardDay: DashboardPriceDay] = [:]
    @Published private(set) var forecastPresentation: GridForecastPresentation?
    @Published private(set) var emissionsPresentation: GridEmissionsPresentation = .unavailable()
    @Published private(set) var gridSeries: DashboardGridSeries = .empty
    @Published private(set) var bestWindow: DashboardBestWindow?
    @Published private(set) var isLoading = false
    @Published private(set) var notices: [String] = []

    private let priceRepository = SpotPriceRepository()
    private let forecastRepository = GridForecastRepository()
    private let emissionsRepository = GridEmissionsRepository()
    private let directEmissionsClient = GridEmissionsAPIClient()

    func loadIfNeeded() async {
        guard pricePresentation == nil else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        notices = []
        defer { isLoading = false }

        let now = Date()
        await loadPrices(at: now)
        await loadForecast(at: now)
        emissionsPresentation = await emissionsRepository.load()

        let history = await loadEmissionsHistory(through: now)
        gridSeries = makeGridSeries(
            measurements: history.measurements,
            forecast: forecastPresentation,
            now: now,
            usesPreview: history.usesPreview
        )
        bestWindow = makeBestWindow(now: now)

        WidgetCenter.shared.reloadTimelines(ofKind: "FinlandSpotElectricityRates")
        WidgetCenter.shared.reloadTimelines(ofKind: "FinlandGridForecast")
    }

    func resetWidgetData() async {
        guard !isLoading else { return }
        WidgetDataStore.resetCaches()
        pricePresentation = nil
        priceDays = [:]
        forecastPresentation = nil
        emissionsPresentation = .unavailable()
        gridSeries = .empty
        bestWindow = nil
        notices = []
        WidgetCenter.shared.reloadAllTimelines()
        await refresh()
    }

    private func loadPrices(at now: Date) async {
        do {
            let result = try await priceRepository.load()
            guard let presentation = SpotPricePresentation.make(
                points: result.points,
                at: now,
                lastUpdated: result.fetchedAt,
                isStale: result.isStale
            ) else { throw SpotPriceAPIError.noPrices }
            pricePresentation = presentation
            priceDays = Dictionary(uniqueKeysWithValues: DashboardDay.allCases.compactMap { day in
                DashboardPriceDay.make(day: day, from: result.points, now: now).map { (day, $0) }
            })
            if result.isStale {
                notices.append("Live prices are unavailable. Showing the latest saved data.")
            }
        } catch {
            notices.append(error.localizedDescription)
        }
    }

    private func loadForecast(at now: Date) async {
        do {
            let result = try await forecastRepository.load()
            forecastPresentation = GridForecastPresentation.make(
                points: result.points,
                at: now,
                lastUpdated: result.fetchedAt,
                availableThrough: result.availableThrough,
                isStale: result.isStale
            )
            if result.isStale {
                notices.append("The renewable forecast is using saved or substituted data.")
            }
        } catch {
            forecastPresentation = .unavailable(at: now)
            notices.append(error.localizedDescription)
        }
    }

    private func loadEmissionsHistory(through now: Date) async -> (
        measurements: [GridEmissionsMeasurement],
        usesPreview: Bool
    ) {
#if DEBUG
        if directEmissionsClient.hasConfiguredAPIKey {
            do {
                let measurements = try await directEmissionsClient.fetchMeasurements(
                    from: now.addingTimeInterval(-30 * 24 * 60 * 60),
                    through: now
                )
                return (measurements, false)
            } catch {
                notices.append("Live emissions history could not be loaded; the chart uses a labeled preview profile.")
            }
        }
        return (Self.previewEmissionsHistory(through: now, current: emissionsPresentation.gramsCO2PerKWh), true)
#else
        return ([], false)
#endif
    }

    private func makeGridSeries(
        measurements: [GridEmissionsMeasurement],
        forecast: GridForecastPresentation?,
        now: Date,
        usesPreview: Bool
    ) -> DashboardGridSeries {
        let calendar = Calendar.helsinki
        let historyStart = now.addingTimeInterval(-24 * 60 * 60)
        let recent = measurements.filter { $0.endTime > historyStart && $0.startTime <= now }
        let groupedHistory = Dictionary(grouping: recent) {
            calendar.dateInterval(of: .hour, for: $0.startTime)?.start ?? $0.startTime
        }
        let valuesByHour = Dictionary(grouping: measurements) {
            calendar.component(.hour, from: $0.startTime)
        }.mapValues { $0.map(\.value).sorted() }

        let emissions = groupedHistory.keys.sorted().suffix(24).compactMap {
            hour -> DashboardEmissionsPoint? in
            guard let values = groupedHistory[hour], !values.isEmpty else { return nil }
            let average = values.map(\.value).reduce(0, +) / Double(values.count)
            let comparison = valuesByHour[calendar.component(.hour, from: hour)] ?? []
            let percentile = Self.midrankPercentile(of: average, in: comparison)
            return DashboardEmissionsPoint(
                hourOffset: calendar.component(.hour, from: hour),
                date: hour,
                gramsCO2PerKWh: average,
                cleanlinessScore: min(max((1 - percentile) * 100, 0), 100)
            )
        }

        let groupedRenewables = Dictionary(grouping: forecast?.forecastPoints ?? []) {
            calendar.dateInterval(of: .hour, for: $0.dateTime)?.start ?? $0.dateTime
        }
        let renewables = groupedRenewables.keys.sorted().prefix(24).compactMap {
            hour -> DashboardRenewablePoint? in
            guard let values = groupedRenewables[hour], !values.isEmpty else { return nil }
            let share = values.map(\.smoothedRenewableShare).reduce(0, +) / Double(values.count)
            let thresholds = FinlandRenewableSignal.thresholds(at: hour, calendar: calendar)
            return DashboardRenewablePoint(
                hourOffset: calendar.component(.hour, from: hour),
                date: hour,
                renewableShare: share,
                cleanlinessScore: Self.renewableCleanlinessScore(share, thresholds: thresholds)
            )
        }

        return DashboardGridSeries(
            emissions: emissions,
            renewables: renewables,
            usesPreviewEmissionsHistory: usesPreview
        )
    }

    private func makeBestWindow(now: Date) -> DashboardBestWindow? {
        let calendar = Calendar.helsinki
        let currentHour = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let futurePrices = priceDays.values.flatMap(\.hours).filter { $0.start >= currentHour }
        guard !futurePrices.isEmpty, !gridSeries.renewables.isEmpty else { return nil }

        let minPrice = futurePrices.map(\.priceCents).min() ?? 0
        let maxPrice = futurePrices.map(\.priceCents).max() ?? 1
        let span = max(maxPrice - minPrice, 1)
        let candidates = futurePrices.compactMap { price -> (HourlySpotPrice, DashboardRenewablePoint, Double)? in
            guard let renewable = gridSeries.renewables.min(by: {
                abs($0.date.timeIntervalSince(price.start)) < abs($1.date.timeIntervalSince(price.start))
            }), abs(renewable.date.timeIntervalSince(price.start)) < 75 * 60 else { return nil }
            let priceScore = 100 * (1 - ((price.priceCents - minPrice) / span))
            return (price, renewable, priceScore * 0.6 + renewable.cleanlinessScore * 0.4)
        }
        guard let best = candidates.max(by: { $0.2 < $1.2 }) else { return nil }
        return DashboardBestWindow(
            start: best.0.start,
            end: best.0.start.addingTimeInterval(60 * 60),
            priceCents: best.0.priceCents,
            renewableShare: best.1.renewableShare
        )
    }

    private static func midrankPercentile(of value: Double, in values: [Double]) -> Double {
        guard !values.isEmpty else { return 0.5 }
        let below = values.lazy.filter { $0 < value }.count
        let equal = values.lazy.filter { abs($0 - value) < 0.000_001 }.count
        return (Double(below) + Double(equal) / 2) / Double(values.count)
    }

    private static func renewableCleanlinessScore(
        _ share: Double,
        thresholds: GridSignalThresholds
    ) -> Double {
        let clamped = min(max(share, 0), 100)
        if clamped <= thresholds.lower {
            return thresholds.lower > 0 ? 33 * clamped / thresholds.lower : 0
        }
        if clamped <= thresholds.upper {
            return 33 + 34 * (clamped - thresholds.lower) / max(thresholds.upper - thresholds.lower, 1)
        }
        return min(100, 67 + 33 * (clamped - thresholds.upper) / max(100 - thresholds.upper, 1))
    }

#if DEBUG
    private static func previewEmissionsHistory(
        through now: Date,
        current: Double?
    ) -> [GridEmissionsMeasurement] {
        let calendar = Calendar.helsinki
        let anchor = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        let currentValue = current ?? 42
        let profile = (0..<(30 * 24)).map { index -> GridEmissionsMeasurement in
            let hoursAgo = (30 * 24) - index
            let start = calendar.date(byAdding: .hour, value: -hoursAgo, to: anchor) ?? anchor
            let hour = Double(calendar.component(.hour, from: start))
            let daily = 13 * sin((hour - 5) / 24 * .pi * 2)
            let weekly = 7 * sin(Double(index) / (24 * 7) * .pi * 2)
            return GridEmissionsMeasurement(
                startTime: start,
                endTime: start.addingTimeInterval(60 * 60),
                value: max(5, currentValue + daily + weekly)
            )
        }
        return profile + [GridEmissionsMeasurement(
            startTime: anchor,
            endTime: min(now, anchor.addingTimeInterval(60 * 60)),
            value: currentValue
        )]
    }
#endif
}
