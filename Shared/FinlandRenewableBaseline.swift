import Foundation

/// Finland renewable-share reference bands used by the forward grid signal.
///
/// The baseline is built from Energy-Charts `renewable_share_of_load`, using
/// the three latest complete years (2023–2025). Quarter-hour observations are
/// normalized to hourly means before pooling. Each cell is the P33/P67 band
/// for the matching Helsinki calendar month and local hour.
enum FinlandRenewableBaseline {
    static let completedYears = 2023...2025

    static func thresholds(
        at date: Date,
        calendar: Calendar = .helsinki
    ) -> GridSignalThresholds {
        let month = calendar.component(.month, from: date)
        let hour = calendar.component(.hour, from: date)

        if let hours = monthHourThresholds[month], hours.indices.contains(hour) {
            return hours[hour]
        }
        if let monthly = monthlyThresholds[month] {
            return monthly
        }
        return seasonalThresholds[seasonIndex(for: month)]
            ?? GridSignalThresholds(lower: 40, upper: 55)
    }

    private static func seasonIndex(for month: Int) -> Int {
        switch month {
        case 3...5: 1
        case 6...8: 2
        case 9...11: 3
        default: 0
        }
    }

    private static let seasonalThresholds: [Int: GridSignalThresholds] = [
        0: .init(lower: 39.7, upper: 54.1),
        1: .init(lower: 42.1, upper: 53.9),
        2: .init(lower: 39.5, upper: 49.4),
        3: .init(lower: 44.1, upper: 59.4),
    ]

    private static let monthlyThresholds: [Int: GridSignalThresholds] = [
        1: .init(lower: 39.6, upper: 53.9),
        2: .init(lower: 39.4, upper: 52.6),
        3: .init(lower: 38.0, upper: 51.2),
        4: .init(lower: 41.8, upper: 51.6),
        5: .init(lower: 45.7, upper: 57.9),
        6: .init(lower: 43.0, upper: 52.9),
        7: .init(lower: 36.1, upper: 46.5),
        8: .init(lower: 39.8, upper: 48.8),
        9: .init(lower: 46.3, upper: 59.8),
        10: .init(lower: 45.7, upper: 61.4),
        11: .init(lower: 40.3, upper: 56.6),
        12: .init(lower: 40.1, upper: 56.6),
    ]

    private static let monthHourThresholds: [Int: [GridSignalThresholds]] = [
        1: [.init(lower: 40.1, upper: 53.2), .init(lower: 39.2, upper: 53.7), .init(lower: 38.3, upper: 54), .init(lower: 38.8, upper: 53.6), .init(lower: 36.9, upper: 52.2), .init(lower: 37.6, upper: 52.6), .init(lower: 37, upper: 52.5), .init(lower: 39.2, upper: 51.7), .init(lower: 39.5, upper: 52.5), .init(lower: 40.1, upper: 53.7), .init(lower: 41, upper: 54.7), .init(lower: 41, upper: 54), .init(lower: 39, upper: 52.8), .init(lower: 38.8, upper: 52.7), .init(lower: 39.3, upper: 52.7), .init(lower: 39.4, upper: 53.3), .init(lower: 40.7, upper: 54.4), .init(lower: 41.6, upper: 55.6), .init(lower: 41.7, upper: 56.2), .init(lower: 41.4, upper: 55.6), .init(lower: 41.9, upper: 55.7), .init(lower: 41.5, upper: 56.1), .init(lower: 41.4, upper: 53.4), .init(lower: 41.5, upper: 53.8)],
        2: [.init(lower: 38.8, upper: 50.1), .init(lower: 38.3, upper: 50.7), .init(lower: 36.4, upper: 50.6), .init(lower: 36, upper: 50.8), .init(lower: 35.2, upper: 51), .init(lower: 36.2, upper: 51.2), .init(lower: 37, upper: 51), .init(lower: 37.7, upper: 52.6), .init(lower: 40.1, upper: 52.9), .init(lower: 40.8, upper: 52.5), .init(lower: 40.7, upper: 51.3), .init(lower: 39.7, upper: 50.1), .init(lower: 38, upper: 47.7), .init(lower: 37.9, upper: 48.7), .init(lower: 39.2, upper: 49.8), .init(lower: 38.4, upper: 52.6), .init(lower: 39.2, upper: 54.5), .init(lower: 41.9, upper: 56), .init(lower: 43.6, upper: 56.7), .init(lower: 44.4, upper: 56.1), .init(lower: 44.9, upper: 55.7), .init(lower: 43.1, upper: 54.9), .init(lower: 41.4, upper: 53.4), .init(lower: 40.3, upper: 52.5)],
        3: [.init(lower: 39.4, upper: 54.7), .init(lower: 38.3, upper: 56), .init(lower: 37.6, upper: 56), .init(lower: 37.2, upper: 55.3), .init(lower: 36.3, upper: 54.2), .init(lower: 36.3, upper: 55.7), .init(lower: 37, upper: 53.5), .init(lower: 39.2, upper: 54.1), .init(lower: 41, upper: 51.9), .init(lower: 40, upper: 48.5), .init(lower: 38.1, upper: 46.2), .init(lower: 38, upper: 46), .init(lower: 37.1, upper: 45.9), .init(lower: 36.5, upper: 46.4), .init(lower: 36.3, upper: 45.8), .init(lower: 35.9, upper: 46.6), .init(lower: 35.9, upper: 47.5), .init(lower: 36.6, upper: 48.3), .init(lower: 38.8, upper: 51.4), .init(lower: 40.7, upper: 53), .init(lower: 41.8, upper: 55.2), .init(lower: 42.7, upper: 53.8), .init(lower: 41.5, upper: 53.7), .init(lower: 40, upper: 54.3)],
        4: [.init(lower: 45.1, upper: 55), .init(lower: 45.1, upper: 56.7), .init(lower: 44.5, upper: 56.3), .init(lower: 44.2, upper: 55.5), .init(lower: 43.9, upper: 55), .init(lower: 44.4, upper: 55.6), .init(lower: 43.6, upper: 52.9), .init(lower: 43.3, upper: 52.8), .init(lower: 42.9, upper: 50.6), .init(lower: 41, upper: 48.6), .init(lower: 39.1, upper: 47.7), .init(lower: 39.9, upper: 48.7), .init(lower: 40.2, upper: 48.3), .init(lower: 39.7, upper: 48.4), .init(lower: 39.7, upper: 48.4), .init(lower: 39.3, upper: 49.2), .init(lower: 37.9, upper: 48.8), .init(lower: 38.4, upper: 48.9), .init(lower: 39.2, upper: 50), .init(lower: 40.3, upper: 49.9), .init(lower: 41.8, upper: 50.5), .init(lower: 43.9, upper: 53.4), .init(lower: 44.5, upper: 53.1), .init(lower: 45.2, upper: 55)],
        5: [.init(lower: 46.7, upper: 62.2), .init(lower: 49, upper: 64.4), .init(lower: 49, upper: 64.2), .init(lower: 47.6, upper: 63.4), .init(lower: 48.8, upper: 62.6), .init(lower: 49.4, upper: 62), .init(lower: 47, upper: 58.9), .init(lower: 44.9, upper: 53.5), .init(lower: 44.1, upper: 51.9), .init(lower: 44, upper: 52.6), .init(lower: 44.1, upper: 53.6), .init(lower: 44.9, upper: 55.1), .init(lower: 45.1, upper: 56.3), .init(lower: 45.5, upper: 56.8), .init(lower: 45.9, upper: 58.3), .init(lower: 46.4, upper: 57.4), .init(lower: 45.8, upper: 58.6), .init(lower: 46, upper: 59.3), .init(lower: 44.6, upper: 57.3), .init(lower: 43.6, upper: 55.4), .init(lower: 43.4, upper: 54.3), .init(lower: 44.2, upper: 55.2), .init(lower: 44.6, upper: 56.9), .init(lower: 46.3, upper: 59.4)],
        6: [.init(lower: 42.3, upper: 56.5), .init(lower: 45, upper: 57.2), .init(lower: 46, upper: 56.8), .init(lower: 45, upper: 56.4), .init(lower: 44.7, upper: 56.9), .init(lower: 45.1, upper: 55.1), .init(lower: 43.9, upper: 52.2), .init(lower: 42.4, upper: 49.2), .init(lower: 41.7, upper: 48.9), .init(lower: 42, upper: 49), .init(lower: 43.1, upper: 49.4), .init(lower: 43, upper: 49.7), .init(lower: 43.8, upper: 49.8), .init(lower: 43.9, upper: 50.8), .init(lower: 43.6, upper: 51.2), .init(lower: 43.7, upper: 50.7), .init(lower: 43, upper: 50.8), .init(lower: 43, upper: 52.7), .init(lower: 42.7, upper: 52.8), .init(lower: 42, upper: 52.4), .init(lower: 42.3, upper: 50.2), .init(lower: 42.3, upper: 50.6), .init(lower: 41.7, upper: 52.8), .init(lower: 42.2, upper: 55.2)],
        7: [.init(lower: 36.2, upper: 51.6), .init(lower: 37.5, upper: 52.8), .init(lower: 36.8, upper: 51.8), .init(lower: 37.3, upper: 51.5), .init(lower: 36.2, upper: 50.9), .init(lower: 36.2, upper: 51.1), .init(lower: 35.9, upper: 47.7), .init(lower: 34.6, upper: 44.4), .init(lower: 34.8, upper: 43.2), .init(lower: 35.9, upper: 44.1), .init(lower: 37.4, upper: 45.5), .init(lower: 36.2, upper: 46.4), .init(lower: 37.3, upper: 45.1), .init(lower: 35.9, upper: 44.5), .init(lower: 35, upper: 44.2), .init(lower: 35.8, upper: 44.3), .init(lower: 35.7, upper: 45.2), .init(lower: 36.4, upper: 45.1), .init(lower: 37.4, upper: 45.2), .init(lower: 36.7, upper: 46.7), .init(lower: 36, upper: 45), .init(lower: 35.8, upper: 46.3), .init(lower: 35.8, upper: 47.9), .init(lower: 35.8, upper: 49.5)],
        8: [.init(lower: 42.4, upper: 50), .init(lower: 42.4, upper: 51.9), .init(lower: 41.3, upper: 50.7), .init(lower: 41.1, upper: 50.3), .init(lower: 40.4, upper: 50.3), .init(lower: 40.7, upper: 50.3), .init(lower: 40.9, upper: 49.2), .init(lower: 40, upper: 49.7), .init(lower: 39.2, upper: 47.3), .init(lower: 39.4, upper: 45.6), .init(lower: 38.9, upper: 45.8), .init(lower: 38.9, upper: 46.8), .init(lower: 39.2, upper: 47.2), .init(lower: 39, upper: 47.3), .init(lower: 38, upper: 47.9), .init(lower: 37.5, upper: 47.1), .init(lower: 37.6, upper: 46.5), .init(lower: 38.9, upper: 48.1), .init(lower: 39.1, upper: 47.6), .init(lower: 39.4, upper: 46.6), .init(lower: 40.1, upper: 47.8), .init(lower: 41.5, upper: 49.5), .init(lower: 42.3, upper: 51.3), .init(lower: 43.3, upper: 50.4)],
        9: [.init(lower: 48.5, upper: 62.8), .init(lower: 46.9, upper: 63.1), .init(lower: 48.2, upper: 60.9), .init(lower: 47.2, upper: 60.5), .init(lower: 46.9, upper: 60.4), .init(lower: 47.6, upper: 60.1), .init(lower: 47.7, upper: 60), .init(lower: 49.4, upper: 63), .init(lower: 49.4, upper: 63.1), .init(lower: 47.2, upper: 60.8), .init(lower: 45, upper: 56.6), .init(lower: 43.7, upper: 55.7), .init(lower: 42.2, upper: 55.1), .init(lower: 41.1, upper: 55.2), .init(lower: 40.7, upper: 53.2), .init(lower: 41.5, upper: 54.3), .init(lower: 42.1, upper: 55.3), .init(lower: 42.8, upper: 56.1), .init(lower: 44.3, upper: 58.2), .init(lower: 47.3, upper: 59.6), .init(lower: 50, upper: 63.2), .init(lower: 51.4, upper: 63.7), .init(lower: 51, upper: 64.6), .init(lower: 49.8, upper: 63.6)],
        10: [.init(lower: 45.6, upper: 61.6), .init(lower: 46.2, upper: 60.3), .init(lower: 46.9, upper: 59.2), .init(lower: 46.2, upper: 58.9), .init(lower: 46.3, upper: 58.7), .init(lower: 46, upper: 58.9), .init(lower: 46.1, upper: 59.6), .init(lower: 46.6, upper: 61.1), .init(lower: 46.9, upper: 63.1), .init(lower: 47.7, upper: 62.7), .init(lower: 47, upper: 61.7), .init(lower: 44.4, upper: 60.5), .init(lower: 42, upper: 58.6), .init(lower: 41.3, upper: 57.6), .init(lower: 40.6, upper: 58.1), .init(lower: 41.9, upper: 59.2), .init(lower: 43.5, upper: 59.2), .init(lower: 44.8, upper: 60.1), .init(lower: 47.7, upper: 64.3), .init(lower: 49.3, upper: 65), .init(lower: 49, upper: 64.6), .init(lower: 49, upper: 64.6), .init(lower: 47.7, upper: 63.6), .init(lower: 45, upper: 62.3)],
        11: [.init(lower: 39.1, upper: 56.6), .init(lower: 38.7, upper: 56.2), .init(lower: 38.2, upper: 56.6), .init(lower: 37.6, upper: 57.8), .init(lower: 38.6, upper: 57), .init(lower: 38.4, upper: 57), .init(lower: 38.5, upper: 57.4), .init(lower: 40.3, upper: 56.3), .init(lower: 42.1, upper: 57.5), .init(lower: 41.6, upper: 57.8), .init(lower: 41.7, upper: 58), .init(lower: 41.2, upper: 56.9), .init(lower: 40.6, upper: 55.1), .init(lower: 39.2, upper: 54.4), .init(lower: 39.6, upper: 55.5), .init(lower: 39.9, upper: 56.3), .init(lower: 41.6, upper: 57), .init(lower: 42.3, upper: 57.6), .init(lower: 43, upper: 58), .init(lower: 42.8, upper: 56.4), .init(lower: 42, upper: 56.2), .init(lower: 41.7, upper: 56.9), .init(lower: 40.6, upper: 55.9), .init(lower: 40, upper: 55.7)],
        12: [.init(lower: 39.4, upper: 55.9), .init(lower: 38.9, upper: 55.2), .init(lower: 39, upper: 55.1), .init(lower: 38.7, upper: 56.3), .init(lower: 38.4, upper: 55.8), .init(lower: 37.4, upper: 54.2), .init(lower: 38.4, upper: 54.9), .init(lower: 39.4, upper: 56.1), .init(lower: 40.2, upper: 55.7), .init(lower: 40.1, upper: 54.4), .init(lower: 41.3, upper: 54.9), .init(lower: 40.7, upper: 55.1), .init(lower: 40.6, upper: 55.5), .init(lower: 40, upper: 56.4), .init(lower: 40.9, upper: 57.4), .init(lower: 42.1, upper: 58), .init(lower: 42.6, upper: 58.6), .init(lower: 43.7, upper: 58.5), .init(lower: 44.1, upper: 57), .init(lower: 43.8, upper: 57.1), .init(lower: 43.8, upper: 57.9), .init(lower: 42.7, upper: 58.4), .init(lower: 40.7, upper: 57.5), .init(lower: 38.9, upper: 55.2)],
    ]
}
