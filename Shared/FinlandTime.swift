import Foundation

/// Clock formatting and axis tick generation for Finland energy data.
///
/// API timestamps are absolute instants, but the product always describes the
/// Finnish market. Keeping the display zone explicit prevents WidgetKit or a
/// device in another region from silently shifting the visible clock.
enum FinlandTime {
    static let timeZone = TimeZone(identifier: "Europe/Helsinki")
        ?? TimeZone(secondsFromGMT: 0)!

    private static let numericClockLocale = Locale(identifier: "en_GB")
    private static let niceTickMinutes = [15, 30, 60, 120, 180, 240, 360, 720, 1_440]

    static var clockStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        style.locale = numericClockLocale
        style.timeZone = timeZone
        return style
    }

    static var hourStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
            .hour(.twoDigits(amPM: .omitted))
        style.locale = numericClockLocale
        style.timeZone = timeZone
        return style
    }

    static var weekdayClockStyle: Date.FormatStyle {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated)
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)
        style.locale = numericClockLocale
        style.timeZone = timeZone
        return style
    }

    static func clock(_ date: Date) -> String {
        date.formatted(clockStyle)
    }

    static func hour(_ date: Date) -> String {
        date.formatted(hourStyle)
    }

    static func weekdayClock(_ date: Date) -> String {
        date.formatted(weekdayClockStyle)
    }

    /// Produces human-readable, wall-clock-aligned ticks without repeated
    /// hour labels on short forecast windows. The first item is always the
    /// exact timeline start and is rendered as “Now” by the widget.
    static func timelineTicks(
        from start: Date,
        through end: Date,
        maximumCount: Int,
        calendar: Calendar = .helsinki
    ) -> [Date] {
        guard maximumCount > 1, end > start else { return [start] }

        let idealStepMinutes = end.timeIntervalSince(start)
            / 60
            / Double(maximumCount - 1)
        let stepMinutes = niceTickMinutes.first {
            Double($0) >= idealStepMinutes - 0.000_001
        } ?? niceTickMinutes.last!

        var ticks = [start]
        var visibleClockLabels = Set<String>()
        var candidate = calendar.startOfDay(for: start)
        var iterationCount = 0

        while candidate <= start, iterationCount < 200 {
            guard let next = calendar.date(
                byAdding: .minute,
                value: stepMinutes,
                to: candidate
            ) else { break }
            candidate = next
            iterationCount += 1
        }

        while candidate <= end,
              ticks.count < maximumCount,
              iterationCount < 400 {
            let clockLabel = clock(candidate)
            if visibleClockLabels.insert(clockLabel).inserted {
                ticks.append(candidate)
            }
            guard let next = calendar.date(
                byAdding: .minute,
                value: stepMinutes,
                to: candidate
            ) else { break }
            candidate = next
            iterationCount += 1
        }

        if ticks.count == 1 {
            ticks.append(end)
        }
        return ticks
    }
}
