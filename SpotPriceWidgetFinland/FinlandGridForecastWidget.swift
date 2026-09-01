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
                let entry = makeEntry(at: now, result: result, emissions: emissions)
                let entries = timelineEntries(
                    startingWith: entry,
                    result: result,
                    now: now
                )
                completion(Timeline(
                    entries: entries,
                    policy: .after(refreshDate(for: entries, now: now))
                ))
            } catch {
                let emissions = await emissionsLoad
                let entry = FinlandGridForecastEntry(
                    date: now,
                    presentation: .unavailable(at: now),
                    emissions: emissions
                )
                let entries = timelineEntries(
                    startingWith: entry,
                    result: nil,
                    now: now
                )
                completion(Timeline(
                    entries: entries,
                    policy: .after(refreshDate(for: entries, now: now))
                ))
            }
        }
    }

    private func loadEntry(at date: Date) async -> FinlandGridForecastEntry {
        async let emissionsLoad = GridEmissionsRepository().load()
        do {
            let result = try await GridForecastRepository().load()
            let emissions = await emissionsLoad
            return makeEntry(at: date, result: result, emissions: emissions)
        } catch { }
        return FinlandGridForecastEntry(
            date: date,
            presentation: .unavailable(at: date),
            emissions: await emissionsLoad
        )
    }

    private func makeEntry(
        at date: Date,
        result: GridForecastLoadResult,
        emissions: GridEmissionsPresentation
    ) -> FinlandGridForecastEntry {
        FinlandGridForecastEntry(
            date: date,
            presentation: GridForecastPresentation.make(
                points: result.points,
                at: date,
                lastUpdated: result.fetchedAt,
                availableThrough: result.availableThrough,
                isStale: result.isStale
            ) ?? .unavailable(at: date),
            emissions: emissions
        )
    }

    private func timelineEntries(
        startingWith entry: FinlandGridForecastEntry,
        result: GridForecastLoadResult?,
        now: Date
    ) -> [FinlandGridForecastEntry] {
        let emissionsAreFresh = GridConditionsSignal.emissionsAreFresh(
            band: entry.emissions.band,
            measuredAt: entry.emissions.measuredAt,
            isStale: entry.emissions.isStale,
            at: now
        )
        let initialEntry = FinlandGridForecastEntry(
            date: entry.date,
            presentation: entry.presentation,
            emissions: emissionsAreFresh ? entry.emissions : entry.emissions.markingStale()
        )

        let transitionEntries = GridConditionsSignal.timelineTransitions(
            forecastPoints: entry.presentation.forecastPoints,
            emissionsBand: entry.emissions.band,
            emissionsMeasuredAt: entry.emissions.measuredAt,
            emissionsAreStale: entry.emissions.isStale,
            after: now
        ).map { transition in
            let presentation = result.map {
                GridForecastPresentation.make(
                    points: $0.points,
                    at: transition.date,
                    lastUpdated: $0.fetchedAt,
                    availableThrough: $0.availableThrough,
                    isStale: $0.isStale
                ) ?? .unavailable(at: transition.date)
            } ?? .unavailable(at: transition.date)
            return FinlandGridForecastEntry(
                date: transition.date,
                presentation: presentation,
                emissions: transition.hasFreshEmissions
                    ? entry.emissions
                    : entry.emissions.markingStale()
            )
        }

        return [initialEntry] + transitionEntries
    }

    private func refreshDate(
        for entries: [FinlandGridForecastEntry],
        now: Date
    ) -> Date {
        let regularRefresh = now.addingTimeInterval(15 * 60)
        guard let safetyRefresh = entries.dropFirst().first?.date else {
            return regularRefresh
        }
        return min(safetyRefresh, regularRefresh)
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
        return "Finland grid conditions. \(emissions.accessibilitySummary) \(gridConditionsStatusSentence(presentation: presentation, emissions: emissions)) \(renewableAccessibilitySummary(presentation))"
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

            GridEmissionsStatus(
                emissions: emissions,
                referenceDate: presentation.referenceDate,
                compact: true
            )
                .padding(.top, 1)

            Spacer(minLength: 5)

            Text(presentation.outlookSentence)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            if presentation.isUnavailable {
                GridForecastUnavailableTimeline()
                    .frame(height: 43)
                    .padding(.top, 1)
            } else {
                GridForecastTimeline(
                    presentation: presentation,
                    compact: true
                )
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
                Text("Grid Conditions")
                    .font(.system(size: 13, weight: .semibold))

                Spacer(minLength: 8)

                Text("Finland")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 12) {
                GridEmissionsValue(emissions: emissions, compact: false)

                Spacer(minLength: 4)

                GridEmissionsStatus(
                    emissions: emissions,
                    referenceDate: presentation.referenceDate,
                    compact: false
                )
            }
            .padding(.top, 2)

            Spacer(minLength: 4)

            Text(presentation.outlookSentence)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            if presentation.isUnavailable {
                GridForecastUnavailableTimeline()
                    .frame(height: 45)
                    .padding(.top, 1)
            } else {
                GridForecastTimeline(
                    presentation: presentation,
                    compact: false
                )
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
    let referenceDate: Date
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: compact ? 10 : 12, weight: .semibold))
            }

            Text(statusText)
                .font(.system(size: compact ? 11 : 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(GridConditionsPalette.color(
            for: emissions.band,
            isStale: !GridConditionsSignal.emissionsAreFresh(
                band: emissions.band,
                measuredAt: emissions.measuredAt,
                isStale: emissions.isStale,
                at: referenceDate
            )
        ))
    }

    private var isFresh: Bool {
        GridConditionsSignal.emissionsAreFresh(
            band: emissions.band,
            measuredAt: emissions.measuredAt,
            isStale: emissions.isStale,
            at: referenceDate
        )
    }

    private var symbolName: String? {
        guard isFresh else { return "carbon.dioxide.cloud" }
        return switch emissions.band {
        case .cleaner: "leaf.fill"
        case .higher: "carbon.dioxide.cloud.fill"
        case .typical, nil: nil
        }
    }

    private var statusText: String {
        guard isFresh else {
            return emissions.gramsCO2PerKWh == nil ? "Data unavailable" : "Last reading"
        }
        return switch emissions.band {
        case .cleaner: "Cleaner now"
        case .typical: "Usual range"
        case .higher: "Higher emissions"
        case nil: "Data unavailable"
        }
    }
}

private struct GridForecastTimeline: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let presentation: GridForecastPresentation
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let trackHeight: CGFloat = compact ? 27 : 31
            let labelY: CGFloat = compact ? 37 : 42
            let labelWidth: CGFloat = usesMinuteLabels ? 40 : 24

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

                    let shape = RoundedRectangle(
                        cornerRadius: min(compact ? 7 : 8, runWidth / 2),
                        style: .continuous
                    )

                    ZStack {
                        if renderingMode == .accented, run.state == .lessClean {
                            shape
                                .fill(.secondary.opacity(0.1))
                                .overlay {
                                    shape.strokeBorder(.secondary, lineWidth: 2)
                                }
                        } else {
                            shape.fill(GridConditionsPalette.color(for: run.state))
                        }

                        if runWidth >= (compact ? 20 : 24) {
                            Image(systemName: symbolName(for: run.state))
                                .font(.system(size: compact ? 9 : 10.5, weight: .bold))
                                .foregroundStyle(symbolColor(for: run.state))
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
                    Text(labelText(for: date, index: index))
                        .font(.system(size: compact ? 10 : 10.5, weight: index == 0 ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: labelWidth)
                        .position(
                            x: min(
                                max(xPosition(for: date, width: width), labelWidth / 2),
                                width - labelWidth / 2
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

    private var highlightedRuns: [GridConditionTimelineRun] {
        GridConditionsSignal.timelineRuns(
            forecastPoints: presentation.forecastPoints,
            isForecastStale: presentation.isStale,
            timelineStart: presentation.timelineStart,
            timelineEnd: displayEnd
        )
    }

    private var gridDates: [Date] {
        FinlandTime.timelineTicks(
            from: presentation.timelineStart,
            through: displayEnd,
            maximumCount: 13
        )
        .dropFirst()
        .filter { $0 < displayEnd }
    }

    private var labelDates: [Date] {
        FinlandTime.timelineTicks(
            from: presentation.timelineStart,
            through: displayEnd,
            maximumCount: compact ? 3 : 5
        )
    }

    private func xPosition(for date: Date, width: CGFloat) -> CGFloat {
        let duration = max(displayEnd.timeIntervalSince(presentation.timelineStart), 1)
        let progress = date.timeIntervalSince(presentation.timelineStart) / duration
        return width * CGFloat(min(max(progress, 0), 1))
    }

    private func symbolName(for state: GridConditionVisualState) -> String {
        switch state {
        case .clean: "leaf.fill"
        case .lessClean: "carbon.dioxide.cloud.fill"
        }
    }

    private func symbolColor(for state: GridConditionVisualState) -> Color {
        if renderingMode == .accented { return .primary }
        return state == .clean ? .black.opacity(0.78) : .white.opacity(0.94)
    }

    private func labelText(for date: Date, index: Int) -> String {
        if index == 0 { return "Now" }
        return usesMinuteLabels ? FinlandTime.clock(date) : FinlandTime.hour(date)
    }

    private var usesMinuteLabels: Bool {
        displayEnd.timeIntervalSince(presentation.timelineStart) < 3 * 60 * 60
            || labelDates.dropFirst().contains {
                Calendar.helsinki.component(.minute, from: $0) != 0
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
    static func color(for state: GridConditionVisualState) -> Color {
        switch state {
        case .clean: .green
        case .lessClean: .red
        }
    }

    static func color(for band: GridEmissionsBand?, isStale: Bool) -> Color {
        guard !isStale else { return .secondary }
        return switch band {
        case .cleaner: .green
        case .typical: .secondary
        case .higher: .red
        case nil: .secondary
        }
    }
}

private func gridConditionsStatusSentence(
    presentation: GridForecastPresentation,
    emissions: GridEmissionsPresentation
) -> String {
    let currentEmissionsBand = GridConditionsSignal.emissionsBandForCurrentForecastSlot(
        forecastPoints: presentation.forecastPoints,
        band: emissions.band,
        measurementStart: emissions.measurementStart,
        measuredAt: emissions.measuredAt,
        isStale: emissions.isStale,
        at: presentation.referenceDate
    )
    return GridConditionsSignal.statusSentence(
        renewableState: GridConditionsSignal.currentForecastPoint(
            in: presentation.forecastPoints,
            at: presentation.referenceDate
        )?.state,
        isForecastStale: presentation.isStale,
        isForecastUnavailable: presentation.isUnavailable,
        emissionsBand: currentEmissionsBand,
        measuredAt: emissions.measuredAt,
        isEmissionsStale: currentEmissionsBand == nil,
        at: presentation.referenceDate
    )
}

private func renewableAccessibilitySummary(
    _ presentation: GridForecastPresentation
) -> String {
    guard !presentation.isUnavailable else { return "" }
    guard let current = GridConditionsSignal.currentForecastPoint(
        in: presentation.forecastPoints,
        at: presentation.referenceDate
    ) else {
        return "The renewable forecast does not cover the current time."
    }
    let share = "Renewable share is \(current.renewableShare.formatted(.number.precision(.fractionLength(0)))) percent and \(current.state.title.lowercased())."
    let end = presentation.stateEndsAt ?? presentation.availableThrough
    guard let end else { return share }
    return "\(share.dropLast()) through \(FinlandTime.clock(end))."
}

private extension GridEmissionsPresentation {
    func markingStale() -> GridEmissionsPresentation {
        GridEmissionsPresentation(
            gramsCO2PerKWh: gramsCO2PerKWh,
            band: band,
            measurementStart: measurementStart,
            measuredAt: measuredAt,
            isStale: true
        )
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
