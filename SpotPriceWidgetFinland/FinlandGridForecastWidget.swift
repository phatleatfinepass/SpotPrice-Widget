import SwiftUI
import WidgetKit

struct FinlandGridForecastEntry: TimelineEntry {
    let date: Date
    let presentation: GridForecastPresentation
    let emissions: GridEmissionsPresentation
}

struct FinlandGridForecastProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinlandGridForecastEntry {
        FinlandGridForecastEntry(
            date: Date(),
            presentation: .sample(),
            emissions: .sample()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (FinlandGridForecastEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        Task {
            completion(await loadEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinlandGridForecastEntry>) -> Void) {
        Task {
            let now = Date()
            async let emissionsLoad = GridEmissionsRepository().load()

            do {
                let result = try await GridForecastRepository().load()
                let emissions = await emissionsLoad
                let horizon = min(
                    now.addingTimeInterval(24 * 60 * 60),
                    result.availableThrough ?? now.addingTimeInterval(24 * 60 * 60)
                )
                var dates = [now]
                dates.append(contentsOf: result.points.map(\.dateTime).filter { $0 > now && $0 <= horizon })

                let entries = dates.compactMap { date -> FinlandGridForecastEntry? in
                    guard let presentation = GridForecastPresentation.make(
                        points: result.points,
                        at: date,
                        lastUpdated: result.fetchedAt,
                        availableThrough: result.availableThrough,
                        isStale: result.isStale
                    ) else { return nil }
                    return FinlandGridForecastEntry(
                        date: date,
                        presentation: presentation,
                        emissions: emissions
                    )
                }

                let fallback = FinlandGridForecastEntry(
                    date: now,
                    presentation: .unavailable(at: now),
                    emissions: emissions
                )
                completion(Timeline(
                    entries: entries.isEmpty ? [fallback] : entries,
                    policy: .after(now.addingTimeInterval(15 * 60))
                ))
            } catch {
                let emissions = await emissionsLoad
                completion(Timeline(
                    entries: [FinlandGridForecastEntry(
                        date: now,
                        presentation: .unavailable(at: now),
                        emissions: emissions
                    )],
                    policy: .after(now.addingTimeInterval(15 * 60))
                ))
            }
        }
    }

    private func loadEntry(at date: Date) async -> FinlandGridForecastEntry {
        async let emissionsLoad = GridEmissionsRepository().load()
        do {
            let result = try await GridForecastRepository().load()
            let emissions = await emissionsLoad
            if let presentation = GridForecastPresentation.make(
                points: result.points,
                at: date,
                lastUpdated: result.fetchedAt,
                availableThrough: result.availableThrough,
                isStale: result.isStale
            ) {
                return FinlandGridForecastEntry(
                    date: date,
                    presentation: presentation,
                    emissions: emissions
                )
            }
        } catch { }
        return FinlandGridForecastEntry(
            date: date,
            presentation: .unavailable(at: date),
            emissions: await emissionsLoad
        )
    }
}

struct FinlandGridForecastEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinlandGridForecastEntry
    var familyOverride: WidgetFamily?

    init(entry: FinlandGridForecastEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        GridConditionsWidgetView(
            presentation: entry.presentation,
            emissions: entry.emissions,
            compact: (familyOverride ?? family) == .systemSmall
        )
    }
}

private struct GridConditionsWidgetView: View {
    let presentation: GridForecastPresentation
    let emissions: GridEmissionsPresentation
    let compact: Bool

    var body: some View {
        Group {
            if compact {
                SmallGridConditionsView(presentation: presentation, emissions: emissions)
            } else {
                MediumGridConditionsView(presentation: presentation, emissions: emissions)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if presentation.isUnavailable {
            return "Finland grid conditions. \(emissions.accessibilitySummary) Renewable forecast is unavailable."
        }
        return "Finland grid conditions. \(emissions.accessibilitySummary) \(presentation.accessibilitySummary)"
    }
}

private struct SmallGridConditionsView: View {
    let presentation: GridForecastPresentation
    let emissions: GridEmissionsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Finland")
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)

            GridEmissionsValue(emissions: emissions, compact: true)
                .padding(.top, 2)

            GridEmissionsStatus(emissions: emissions, compact: true)
                .padding(.top, 1)

            Spacer(minLength: 5)

            Text(presentation.statusSentence)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            if presentation.isUnavailable {
                GridForecastUnavailableTimeline()
                    .frame(height: 43)
                    .padding(.top, 1)
            } else {
                GridForecastTimeline(presentation: presentation, compact: true)
                    .frame(height: 43)
                    .padding(.top, 1)
            }
        }
    }
}

private struct MediumGridConditionsView: View {
    let presentation: GridForecastPresentation
    let emissions: GridEmissionsPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                HStack(spacing: 5) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("Grid Conditions")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer(minLength: 8)

                Text("Finland")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                GridEmissionsValue(emissions: emissions, compact: false)

                Spacer(minLength: 4)

                GridEmissionsStatus(emissions: emissions, compact: false)
            }
            .padding(.top, 2)

            Spacer(minLength: 4)

            Text(presentation.statusSentence)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if presentation.isUnavailable {
                GridForecastUnavailableTimeline()
                    .frame(height: 45)
                    .padding(.top, 1)
            } else {
                GridForecastTimeline(presentation: presentation, compact: false)
                    .frame(height: 45)
                    .padding(.top, 1)
            }
        }
    }

}

private struct GridEmissionsValue: View {
    let emissions: GridEmissionsPresentation
    let compact: Bool

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: compact ? 4 : 6) {
            Text(emissions.valueText)
                .font(.system(size: compact ? 34 : 40, weight: .bold, design: .rounded))
                .tracking(compact ? -1.2 : -1.5)
                .monospacedDigit()
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text("gCO₂/kWh")
                .font(.system(size: compact ? 9.5 : 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, compact ? 4 : 5)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}

private struct GridEmissionsStatus: View {
    let emissions: GridEmissionsPresentation
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Image(systemName: "leaf.fill")
                .font(.system(size: compact ? 10 : 12, weight: .semibold))

            Text(emissions.statusText)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(GridConditionsPalette.color(for: emissions.band))
    }
}

private struct GridForecastTimeline: View {
    let presentation: GridForecastPresentation
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackHeight: CGFloat = compact ? 28 : 30
            let labelY: CGFloat = compact ? 37 : 41

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous)
                    .fill(.secondary.opacity(0.08))
                    .frame(width: width, height: trackHeight)

                ForEach(gridDates, id: \.self) { date in
                    Rectangle()
                        .fill(.secondary.opacity(0.17))
                        .frame(width: 1, height: trackHeight)
                        .offset(x: xPosition(for: date, width: width))
                }

                ForEach(highlightedRuns) { run in
                    let startX = xPosition(for: run.start, width: width)
                    let endX = xPosition(for: run.end, width: width)
                    let runWidth = max(endX - startX, compact ? 3 : 4)
                    let inset: CGFloat = compact ? 1.5 : 2

                    ZStack {
                        RoundedRectangle(
                            cornerRadius: min(compact ? 7 : 8, runWidth / 2),
                            style: .continuous
                        )
                        .fill(GridConditionsPalette.color(for: run.state))

                        if runWidth >= (compact ? 20 : 24) {
                            Image(systemName: symbolName(for: run.state))
                                .font(.system(size: compact ? 9 : 10.5, weight: .bold))
                                .foregroundStyle(.black.opacity(0.78))
                        }
                    }
                    .frame(
                        width: max(runWidth - inset, 2),
                        height: trackHeight - 4
                    )
                    .position(
                        x: startX + runWidth / 2,
                        y: trackHeight / 2
                    )
                    .widgetAccentable()
                }

                ForEach(Array(labelDates.enumerated()), id: \.offset) { index, date in
                    Text(date.formatted(.dateTime.hour()))
                        .font(.system(size: compact ? 6.2 : 7.5, weight: .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: 24)
                        .position(
                            x: min(
                                max(labelPosition(index: index, width: width), 10),
                                width - 10
                            ),
                            y: labelY
                        )
                }
            }
        }
        .accessibilityHidden(true)
    }

    private var displayEnd: Date {
        let familyDuration: TimeInterval = (compact ? 12 : 24) * 60 * 60
        return min(presentation.timelineEnd, presentation.timelineStart.addingTimeInterval(familyDuration))
    }

    private var scheduleRuns: [GridSignalRun] {
        presentation.signalRuns.compactMap { run in
            let start = max(run.start, presentation.timelineStart)
            let end = min(run.end, displayEnd)
            guard end > start else { return nil }
            return GridSignalRun(state: run.state, start: start, end: end)
        }
    }

    private var highlightedRuns: [GridSignalRun] {
        scheduleRuns.filter { $0.state != .average }
    }

    private var gridDates: [Date] {
        let step = Double(compact ? 1 : 2) * 60 * 60
        let duration = displayEnd.timeIntervalSince(presentation.timelineStart)
        let count = max(Int(floor(duration / step)), 1)
        guard count > 1 else { return [] }
        return (1..<count).map {
            presentation.timelineStart.addingTimeInterval(Double($0) * step)
        }
    }

    private var labelDates: [Date] {
        let count = compact ? 4 : 5
        let duration = displayEnd.timeIntervalSince(presentation.timelineStart)
        let step = duration / Double(max(count - 1, 1))
        return (0..<count).map {
            presentation.timelineStart.addingTimeInterval(Double($0) * step)
        }
    }

    private func labelPosition(index: Int, width: CGFloat) -> CGFloat {
        let denominator = CGFloat(max(labelDates.count - 1, 1))
        return width * CGFloat(index) / denominator
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let duration = max(displayEnd.timeIntervalSince(presentation.timelineStart), 1)
        let progress = date.timeIntervalSince(presentation.timelineStart) / duration
        return width * CGFloat(min(max(progress, 0), 1))
    }

    private func symbolName(for state: GridSignalState) -> String {
        switch state {
        case .high: "leaf.fill"
        case .low: "carbon.dioxide.cloud.fill"
        case .average: ""
        }
    }
}

private struct GridForecastUnavailableTimeline: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.xyaxis.line")
                .font(.caption2)
            Text("Forecast unavailable · retrying shortly")
                .font(.caption2)
                .lineLimit(1)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private enum GridConditionsPalette {
    static func color(for state: GridSignalState) -> Color {
        switch state {
        case .low: .red
        case .average: .clear
        case .high: .green
        }
    }

    static func color(for band: GridEmissionsBand?) -> Color {
        switch band {
        case .cleaner: .green
        case .typical: .orange
        case .higher: .red
        case nil: .secondary
        }
    }
}

struct FinlandGridForecastWidget: Widget {
    let kind = "FinlandGridForecast"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinlandGridForecastProvider()) { entry in
            FinlandGridForecastEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Finland Grid Conditions")
        .description("See Finland’s current grid emissions and upcoming renewable-energy forecast.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#if DEBUG
struct FinlandGridForecastWidget_Previews: PreviewProvider {
    static let entry = FinlandGridForecastEntry(
        date: Date(),
        presentation: .sample(),
        emissions: .sample()
    )

    static var previews: some View {
        Group {
            FinlandGridForecastEntryView(entry: entry, familyOverride: .systemSmall)
                .containerBackground(.fill.tertiary, for: .widget)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Grid Conditions · Small")

            FinlandGridForecastEntryView(entry: entry, familyOverride: .systemMedium)
                .containerBackground(.fill.tertiary, for: .widget)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Grid Conditions · Medium")
        }
    }
}
#endif
