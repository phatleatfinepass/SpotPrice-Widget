import Foundation
import SwiftUI

enum DashboardDay: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"

    var id: Self { self }
}

struct DashboardPriceDay: Hashable {
    let day: DashboardDay
    let date: Date
    let hours: [HourlySpotPrice]
    let statistics: SpotPriceStatistics

    static func make(
        day: DashboardDay,
        from points: [SpotPricePoint],
        now: Date,
        calendar: Calendar = .helsinki
    ) -> DashboardPriceDay? {
        let todayStart = calendar.startOfDay(for: now)
        let offset = day == .today ? 0 : 1
        guard let start = calendar.date(byAdding: .day, value: offset, to: todayStart) else {
            return nil
        }
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 60 * 60)
        let source = points.filter { $0.dateTime >= start && $0.dateTime < end }
        guard !source.isEmpty else { return nil }

        let grouped = Dictionary(grouping: source) {
            calendar.dateInterval(of: .hour, for: $0.dateTime)?.start ?? $0.dateTime
        }
        let hours = grouped.keys.sorted().compactMap { hourStart -> HourlySpotPrice? in
            guard let values = grouped[hourStart], !values.isEmpty else { return nil }
            let prices = values.map(\.centsWithTax)
            let ranks = values.compactMap(\.rank).map(Double.init)
            return HourlySpotPrice(
                start: hourStart,
                priceCents: prices.reduce(0, +) / Double(prices.count),
                averageRank: ranks.isEmpty ? nil : ranks.reduce(0, +) / Double(ranks.count)
            )
        }
        guard !hours.isEmpty else { return nil }
        let prices = hours.map(\.priceCents)
        return DashboardPriceDay(
            day: day,
            date: start,
            hours: hours,
            statistics: SpotPriceStatistics(
                minimum: prices.min() ?? 0,
                average: prices.reduce(0, +) / Double(prices.count),
                maximum: prices.max() ?? 0
            )
        )
    }
}

struct DashboardEmissionsPoint: Hashable, Identifiable {
    let hourOffset: Int
    let date: Date
    let gramsCO2PerKWh: Double
    let cleanlinessScore: Double
    var id: Int { hourOffset }
}

struct DashboardRenewablePoint: Hashable, Identifiable {
    let hourOffset: Int
    let date: Date
    let renewableShare: Double
    let cleanlinessScore: Double
    var id: Int { hourOffset }
}

struct DashboardBestWindow: Hashable {
    let start: Date
    let end: Date
    let priceCents: Double
    let renewableShare: Double
}

struct DashboardGridSeries: Hashable {
    let emissions: [DashboardEmissionsPoint]
    let renewables: [DashboardRenewablePoint]
    let usesPreviewEmissionsHistory: Bool

    static let empty = DashboardGridSeries(
        emissions: [],
        renewables: [],
        usesPreviewEmissionsHistory: false
    )
}

extension SpotPriceBand {
    var dashboardColor: Color {
        switch self {
        case .low: Color(red: 0.20, green: 0.72, blue: 0.38)
        case .typical: Color(red: 1.00, green: 0.64, blue: 0.10)
        case .high: Color(red: 1.00, green: 0.29, blue: 0.26)
        }
    }
}

extension GridEmissionsBand {
    var dashboardColor: Color {
        switch self {
        case .cleaner: .green
        case .typical: .orange
        case .higher: .red
        }
    }
}

extension Double {
    var formattedPrice: String {
        formatted(.number.precision(.fractionLength(abs(self) < 10 ? 2 : 1)))
    }
}

enum DashboardFormatting {
    static let day = Date.FormatStyle()
        .weekday(.wide)
        .day()
        .month(.abbreviated)
        .locale(Locale(identifier: "en_FI"))
}
