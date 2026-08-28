import Charts
import WidgetKit
import SwiftUI

struct FinlandSpotPriceEntry: TimelineEntry {
    let date: Date
    let presentation: SpotPricePresentation
}

struct FinlandSpotPriceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FinlandSpotPriceEntry {
        FinlandSpotPriceEntry(date: Date(), presentation: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (FinlandSpotPriceEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        Task {
            completion(await loadEntry(at: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinlandSpotPriceEntry>) -> Void) {
        Task {
            let now = Date()
            do {
                let result = try await SpotPriceRepository().load()
                let horizon = now.addingTimeInterval(12 * 60 * 60)
                var dates = [now]
                dates.append(contentsOf: result.points.map(\.dateTime).filter { $0 > now && $0 <= horizon })

                let entries = dates.compactMap { date -> FinlandSpotPriceEntry? in
                    guard let presentation = SpotPricePresentation.make(
                        points: result.points,
                        at: date,
                        lastUpdated: result.fetchedAt,
                        isStale: result.isStale
                    ) else { return nil }
                    return FinlandSpotPriceEntry(date: date, presentation: presentation)
                }

                let fallback = FinlandSpotPriceEntry(date: now, presentation: .unavailable(at: now))
                let safeEntries = entries.isEmpty ? [fallback] : entries
                let reloadDate = (safeEntries.last?.date ?? now).addingTimeInterval(15 * 60)
                completion(Timeline(entries: safeEntries, policy: .after(reloadDate)))
            } catch {
                let retryDate = now.addingTimeInterval(15 * 60)
                completion(Timeline(
                    entries: [FinlandSpotPriceEntry(date: now, presentation: .unavailable(at: now))],
                    policy: .after(retryDate)
                ))
            }
        }
    }

    private func loadEntry(at date: Date) async -> FinlandSpotPriceEntry {
        do {
            let result = try await SpotPriceRepository().load()
            if let presentation = SpotPricePresentation.make(
                points: result.points,
                at: date,
                lastUpdated: result.fetchedAt,
                isStale: result.isStale
            ) {
                return FinlandSpotPriceEntry(date: date, presentation: presentation)
            }
        } catch { }
        return FinlandSpotPriceEntry(date: date, presentation: .unavailable(at: date))
    }
}

struct FinlandSpotPriceEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FinlandSpotPriceEntry
    var familyOverride: WidgetFamily?

    init(entry: FinlandSpotPriceEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    @ViewBuilder
    var body: some View {
        if entry.presentation.isUnavailable {
            WidgetUnavailableView()
        } else {
            familyContent
        }
    }

    @ViewBuilder
    private var familyContent: some View {
        switch familyOverride ?? family {
#if os(iOS)
        case .accessoryCircular:
            AccessoryCircularRateView(presentation: entry.presentation)
        case .accessoryRectangular:
            AccessoryRateView(presentation: entry.presentation)
        case .accessoryInline:
            AccessoryInlineRateView(presentation: entry.presentation)
#endif
        case .systemMedium:
            MediumRateView(presentation: entry.presentation)
        case .systemLarge:
            LargeRateView(presentation: entry.presentation)
        case .systemExtraLarge:
            ExtraLargeRateView(presentation: entry.presentation)
        default:
            SmallRateView(presentation: entry.presentation)
        }
    }
}

struct WidgetUnavailableView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: "bolt.trianglebadge.exclamationmark")
                .font(.title2)
                .widgetAccentable()
            Text("Electricity Rates")
                .font(.headline)
            Text("Prices unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Retrying shortly")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct SmallRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HomeWidgetHeader()

            HStack(alignment: .center, spacing: 2) {
                CompactRateStatusView(presentation: presentation, style: .small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)

                WeatherRateRange(presentation: presentation, size: 70)
                    .offset(x: 3)
            }
            .frame(height: 67)

            CompactWidgetPriceChart(
                hours: presentation.upcomingHours,
                currentTime: presentation.referenceDate,
                currentPriceCents: presentation.currentPriceCents,
                currentBand: presentation.currentBand,
                showsExtrema: false,
                showsTimeLabels: false,
                compact: true
            )
            .frame(height: 37)
            .accessibilityLabel(presentation.chartAccessibilityLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}

struct MediumRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HomeWidgetHeader()
                    CompactRateStatusView(presentation: presentation, style: .medium)
                }

                Spacer(minLength: 0)

                WeatherRateRange(presentation: presentation, size: 84)
                    .offset(y: -3)
            }
            .frame(height: 82, alignment: .top)

            CompactWidgetPriceChart(
                hours: presentation.upcomingHours,
                currentTime: presentation.referenceDate,
                currentPriceCents: presentation.currentPriceCents,
                currentBand: presentation.currentBand,
                showsExtrema: true,
                showsTimeLabels: true,
                compact: false
            )
            .frame(height: 60)
            .padding(.top, 4)
            .accessibilityLabel(presentation.chartAccessibilityLabel)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}

struct LargeRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 16) {
                    HomeWidgetHeader(showsUpdatedTime: true, presentation: presentation)
                    RateStatusView(presentation: presentation)
                }

                Spacer(minLength: 0)

                WeatherRateRange(presentation: presentation, size: 104)
            }

            Divider()

            HStack {
                Text("Rate schedule")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(presentation.chartAvailabilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            WidgetPriceChart(
                hours: presentation.upcomingHours,
                currentTime: presentation.referenceDate,
                labelStride: 6
            )
            .frame(maxHeight: .infinity)

            if let cheapest = presentation.cheapestHour {
                PriceTimeInsight(
                    systemImage: "clock.arrow.circlepath",
                    title: "Lowest around \(cheapest.start.formatted(.dateTime.hour().minute()))",
                    detail: "From \(cheapest.priceCents.widgetPrice) c/kWh"
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}

struct ExtraLargeRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        HStack(spacing: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HomeWidgetHeader()
                RateStatusView(presentation: presentation)
                WeatherRateRange(presentation: presentation, size: 122)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
            .frame(width: 170, alignment: .leading)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Rate schedule")
                        .font(.headline)
                    Spacer()
                    Text(presentation.extraLargeChartAvailabilityLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                WidgetPriceChart(
                    hours: presentation.upcomingHours,
                    currentTime: presentation.referenceDate,
                    labelStride: 6
                )
                .frame(maxHeight: .infinity)

                HStack(spacing: 24) {
                    if let cheapest = presentation.cheapestHour {
                        PriceTimeInsight(
                            systemImage: "arrow.down",
                            title: "Cheapest around \(cheapest.start.formatted(.dateTime.hour().minute()))",
                            detail: "From \(cheapest.priceCents.widgetPrice) c/kWh"
                        )
                    }

                    if let priciest = presentation.priciestHour {
                        PriceTimeInsight(
                            systemImage: "arrow.up",
                            title: "Peak around \(priciest.start.formatted(.dateTime.hour().minute()))",
                            detail: "Up to \(priciest.priceCents.widgetPrice) c/kWh"
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}

#if os(iOS)
struct AccessoryInlineRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        if let bandEndsAt = presentation.bandEndsAt {
            Text("⚡ Electricity Rates · \(presentation.currentBand.homeTitle) until \(bandEndsAt, format: .dateTime.hour().minute())")
        } else {
            Text("⚡ Electricity Rates · \(presentation.currentPriceCents.widgetPrice) c/kWh")
        }
    }
}

struct AccessoryCircularRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        WeatherRateRange(presentation: presentation, size: 68, accessory: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.accessibilitySummary)
    }
}

struct AccessoryRateView: View {
    let presentation: SpotPricePresentation

    var body: some View {
        HStack(spacing: 7) {
            WeatherRateRange(presentation: presentation, size: 58, accessory: true)

            VStack(alignment: .leading, spacing: 0) {
                Text("Electricity Rates")
                    .font(.caption2.weight(.semibold))
                Text(presentation.currentBand.homeTitle)
                    .font(.headline)
                    .lineLimit(1)
                if let bandEndsAt = presentation.bandEndsAt {
                    Text("Until \(bandEndsAt, format: .dateTime.hour().minute())")
                        .font(.caption2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(presentation.accessibilitySummary)
    }
}
#endif

struct HomeWidgetHeader: View {
    var showsUpdatedTime = false
    var presentation: SpotPricePresentation?

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.orange, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 0) {
                Text("Electricity Rates")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                if showsUpdatedTime, let presentation {
                    Text("Finland · \(presentation.lastUpdated, format: .dateTime.hour().minute())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Finland")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct RateStatusView: View {
    let presentation: SpotPricePresentation
    var compact = false
    var concise = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(presentation.currentBand.homeTitle)
                .font(compact ? .headline : .title2)
                .fontWeight(.bold)
                .foregroundStyle(presentation.currentBand.color)
                .lineLimit(1)

            if let bandEndsAt = presentation.bandEndsAt {
                Text(concise
                    ? "Until \(bandEndsAt.formatted(.dateTime.hour().minute()))"
                    : "\(presentation.currentBand.homeSentence) until \(bandEndsAt.formatted(.dateTime.hour().minute()))"
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(presentation.currentBand.homeSentence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum CompactRateStatusStyle {
    case small
    case medium

    var titleSize: CGFloat {
        switch self {
        case .small: 18
        case .medium: 24
        }
    }

    var detailSize: CGFloat {
        switch self {
        case .small: 10.5
        case .medium: 13
        }
    }
}

private struct CompactRateStatusView: View {
    let presentation: SpotPricePresentation
    let style: CompactRateStatusStyle

    var body: some View {
        VStack(alignment: .leading, spacing: style == .small ? 2 : 3) {
            Text(presentation.currentBand.homeTitle)
                .font(.system(size: style.titleSize, weight: .bold, design: .rounded))
                .foregroundStyle(presentation.currentBand.color)
                .lineLimit(1)
                .minimumScaleFactor(style == .small ? 0.76 : 0.9)

            Text(detail)
                .font(.system(size: style.detailSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(style == .small ? 0.68 : 0.86)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var detail: String {
        guard let bandEndsAt = presentation.bandEndsAt else {
            return presentation.currentBand.homeSentence
        }
        return "\(presentation.currentBand.compactSentence) until \(bandEndsAt.formatted(.dateTime.hour().minute()))"
    }
}

struct WeatherRateRange: View {
    let presentation: SpotPricePresentation
    let size: CGFloat
    var accessory = false

    var body: some View {
        GeometryReader { proxy in
            let marker = WeatherArcGeometry.markerPoint(
                progress: presentation.currentRangeProgress,
                size: proxy.size
            )

            ZStack {
                WeatherRangeArcShape()
                    .stroke(
                        .secondary.opacity(accessory ? 0.55 : 0.62),
                        style: StrokeStyle(lineWidth: size * 0.105, lineCap: .round)
                    )

                Circle()
                    .fill(.primary)
                    .frame(width: size * 0.12, height: size * 0.12)
                    .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                    .position(marker)
                    .widgetAccentable()

                Text(presentation.currentPriceCents.widgetPrice)
                    .font(.system(size: size * 0.22, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .frame(width: proxy.size.width * 0.66)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.44)

                if !accessory || size >= 58 {
                    Text("c/kWh")
                        .font(.system(size: accessory ? 9 : max(11, size * 0.08), weight: .medium))
                        .foregroundStyle(.secondary)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.68)
                }

                Text(presentation.rangeMinimum.widgetPrice)
                    .font(.system(size: accessory ? size * 0.115 : max(11, size * 0.115), weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .position(x: proxy.size.width * 0.21, y: proxy.size.height * 0.87)

                Text(presentation.rangeMaximum.widgetPrice)
                    .font(.system(size: accessory ? size * 0.115 : max(11, size * 0.115), weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .position(x: proxy.size.width * 0.79, y: proxy.size.height * 0.87)
            }
        }
        .frame(width: size, height: size * 0.92)
    }
}

struct WeatherRangeArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        let metrics = WeatherArcGeometry.metrics(in: rect.size)
        var path = Path()
        path.addArc(
            center: metrics.center,
            radius: metrics.radius,
            startAngle: .degrees(WeatherArcGeometry.startDegrees),
            endAngle: .degrees(WeatherArcGeometry.endDegrees),
            clockwise: false
        )
        return path
    }
}

private enum WeatherArcGeometry {
    struct Metrics {
        let center: CGPoint
        let radius: CGFloat
    }

    static let startDegrees = 145.0
    static let endDegrees = 395.0

    static func metrics(in size: CGSize) -> Metrics {
        Metrics(
            center: CGPoint(x: size.width * 0.5, y: size.height * 0.49),
            radius: min(size.width * 0.37, size.height * 0.44)
        )
    }

    static func markerPoint(progress: Double, size: CGSize) -> CGPoint {
        let metrics = metrics(in: size)
        let progress = CGFloat(min(max(progress, 0), 1))
        let degrees = startDegrees + (endDegrees - startDegrees) * Double(progress)
        let radians = CGFloat(degrees * .pi / 180)
        return CGPoint(
            x: metrics.center.x + metrics.radius * cos(radians),
            y: metrics.center.y + metrics.radius * sin(radians)
        )
    }
}

private struct CompactWidgetPriceChart: View {
    private static let hourCount = 24

    let hours: [HourlySpotPrice]
    let currentTime: Date
    let currentPriceCents: Double
    let currentBand: SpotPriceBand
    let showsExtrema: Bool
    let showsTimeLabels: Bool
    let compact: Bool

    var body: some View {
        GeometryReader { proxy in
            let metrics = ChartMetrics(
                size: proxy.size,
                compact: compact,
                showsTimeLabels: showsTimeLabels
            )

            ZStack(alignment: .topLeading) {
                if minimumPrice < 0 {
                    Rectangle()
                        .fill(.secondary.opacity(0.22))
                        .frame(width: metrics.size.width, height: 0.5)
                        .position(
                            x: metrics.size.width / 2,
                            y: zeroBaselineY(metrics: metrics)
                        )
                }

                ForEach(0..<Self.hourCount, id: \.self) { index in
                    let value = price(at: index)
                    let height = barHeight(for: value, metrics: metrics)
                    let isNegative = (value ?? 0) < 0

                    UnevenRoundedRectangle(
                        cornerRadii: RectangleCornerRadii(
                            topLeading: isNegative ? 0 : metrics.cornerRadius,
                            bottomLeading: isNegative ? metrics.cornerRadius : 0,
                            bottomTrailing: isNegative ? metrics.cornerRadius : 0,
                            topTrailing: isNegative ? 0 : metrics.cornerRadius
                        ),
                        style: .continuous
                    )
                    .fill(barColor(at: index))
                    .frame(width: metrics.barWidth, height: height)
                    .position(
                        x: metrics.xPosition(for: index),
                        y: zeroBaselineY(metrics: metrics) + (isNegative ? height / 2 : -height / 2)
                    )
                }

                if showsExtrema, !allPricesEqual {
                    if !currentIsMinimum, let minimumIndex {
                        PriceBarAnnotation(text: minimumPrice.widgetPrice, compact: compact)
                            .position(annotationPosition(for: minimumIndex, metrics: metrics))
                    }

                    if !currentIsMaximum, let maximumIndex {
                        PriceBarAnnotation(text: maximumPrice.widgetPrice, compact: compact)
                            .position(annotationPosition(for: maximumIndex, metrics: metrics))
                    }
                }

                if let currentIndex {
                    CurrentPriceBarAnnotation(
                        title: currentAnnotationTitle,
                        price: currentExtremePrice,
                        compact: compact
                    )
                    .position(annotationPosition(for: currentIndex, metrics: metrics))
                }

                if showsTimeLabels {
                    ForEach([0, 6, 12, 18], id: \.self) { hour in
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 7, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .position(
                                x: metrics.xPosition(for: hour),
                                y: metrics.axisLabelY
                            )
                    }
                }
            }
        }
    }

    private var hourByIndex: [Int: HourlySpotPrice] {
        Dictionary(uniqueKeysWithValues: hours.prefix(Self.hourCount).map {
            (Calendar.helsinki.component(.hour, from: $0.start), $0)
        })
    }

    private var currentIndex: Int? {
        let index = Calendar.helsinki.component(.hour, from: currentTime)
        return (0..<Self.hourCount).contains(index) ? index : nil
    }

    private func price(at index: Int) -> Double? {
        if let hour = hourByIndex[index] {
            return hour.priceCents
        }
        return index == currentIndex ? currentPriceCents : nil
    }

    private var publishedPrices: [Double] {
        (0..<Self.hourCount).compactMap(price(at:))
    }

    private var minimumPrice: Double {
        publishedPrices.min() ?? currentPriceCents
    }

    private var maximumPrice: Double {
        publishedPrices.max() ?? currentPriceCents
    }

    private var allPricesEqual: Bool {
        abs(maximumPrice - minimumPrice) < 0.000_001
    }

    private var minimumIndex: Int? {
        (0..<Self.hourCount).first { index in
            guard let value = price(at: index) else { return false }
            return abs(value - minimumPrice) < 0.000_001
        }
    }

    private var maximumIndex: Int? {
        (0..<Self.hourCount).first { index in
            guard let value = price(at: index) else { return false }
            return abs(value - maximumPrice) < 0.000_001
        }
    }

    private var currentPriceInChart: Double? {
        guard let currentIndex else { return nil }
        return price(at: currentIndex)
    }

    private var currentIsMinimum: Bool {
        guard !allPricesEqual, let currentPriceInChart else { return false }
        return abs(currentPriceInChart - minimumPrice) < 0.000_001
    }

    private var currentIsMaximum: Bool {
        guard !allPricesEqual, let currentPriceInChart else { return false }
        return abs(currentPriceInChart - maximumPrice) < 0.000_001
    }

    private var currentAnnotationTitle: String {
        if currentIsMinimum { return "Lowest Now" }
        if currentIsMaximum { return "Highest Now" }
        return "Now"
    }

    private var currentExtremePrice: String? {
        guard showsExtrema, currentIsMinimum || currentIsMaximum else { return nil }
        return currentPriceInChart?.widgetPrice
    }

    private func barHeight(for value: Double?, metrics: ChartMetrics) -> CGFloat {
        guard let value else { return metrics.placeholderHeight }
        let baselineY = zeroBaselineY(metrics: metrics)
        let availableHeight = value < 0
            ? metrics.plotBottomY - baselineY
            : baselineY - metrics.plotTopY

        guard availableHeight > 0 else { return metrics.zeroBarHeight }
        guard abs(value) > 0.000_001 else { return metrics.zeroBarHeight }
        guard !allPricesEqual else {
            return min(
                availableHeight,
                max(metrics.minimumBarHeight, availableHeight * 0.55)
            )
        }

        let sideMaximum = value < 0
            ? max(abs(min(minimumPrice, 0)), 0.000_001)
            : max(maximumPrice, 0.000_001)
        let progress = min(max(abs(value) / sideMaximum, 0), 1)
        return min(
            availableHeight,
            max(metrics.minimumBarHeight, availableHeight * CGFloat(progress))
        )
    }

    private func barColor(at index: Int) -> Color {
        guard let hour = hourByIndex[index] else {
            if index == currentIndex {
                return currentBand.chartColor
            }
            return .secondary.opacity(compact ? 0.16 : 0.14)
        }
        let band = index == currentIndex ? currentBand : hour.band
        return band.chartColor.opacity(index == currentIndex ? 1 : 0.88)
    }

    private func annotationPosition(for index: Int, metrics: ChartMetrics) -> CGPoint {
        let value = price(at: index)
        let baselineY = zeroBaselineY(metrics: metrics)
        let height = barHeight(for: value, metrics: metrics)
        let desiredY = (value ?? 0) < 0
            ? baselineY - metrics.annotationHeight / 2 - 1
            : baselineY - height - metrics.annotationHeight / 2 - 1
        return CGPoint(
            x: metrics.xPosition(for: index),
            y: max(metrics.annotationHeight / 2, desiredY)
        )
    }

    private func zeroBaselineY(metrics: ChartMetrics) -> CGFloat {
        let positiveMagnitude = max(maximumPrice, 0)
        let negativeMagnitude = abs(min(minimumPrice, 0))

        if negativeMagnitude < 0.000_001 { return metrics.plotBottomY }
        if positiveMagnitude < 0.000_001 { return metrics.plotTopY }

        let positiveShare = positiveMagnitude / (positiveMagnitude + negativeMagnitude)
        return metrics.plotTopY + metrics.plotHeight * CGFloat(positiveShare)
    }

    private struct ChartMetrics {
        let size: CGSize
        let compact: Bool
        let showsTimeLabels: Bool

        var gap: CGFloat { compact ? 1.5 : 2.5 }
        var axisHeight: CGFloat { showsTimeLabels ? 10 : 0 }
        var annotationHeight: CGFloat { compact ? 10 : 15 }
        var plotTopY: CGFloat { annotationHeight + 1 }
        var plotBottomY: CGFloat { size.height - axisHeight }
        var plotHeight: CGFloat { max(8, plotBottomY - plotTopY) }
        var minimumBarHeight: CGFloat { max(compact ? 3 : 5, plotHeight * 0.12) }
        var zeroBarHeight: CGFloat { max(1.5, minimumBarHeight * 0.4) }
        var placeholderHeight: CGFloat { max(2, minimumBarHeight * 0.55) }
        var barWidth: CGFloat {
            max(2, (size.width - gap * CGFloat(CompactWidgetPriceChart.hourCount - 1))
                / CGFloat(CompactWidgetPriceChart.hourCount))
        }
        var cornerRadius: CGFloat {
            compact ? min(barWidth / 2, 2.5) : barWidth / 2
        }
        var axisLabelY: CGFloat { size.height - axisHeight / 2 }

        func xPosition(for index: Int) -> CGFloat {
            barWidth / 2 + CGFloat(index) * (barWidth + gap)
        }
    }
}

private struct PriceBarAnnotation: View {
    let text: String
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text(text)
                .font(.system(size: compact ? 6.5 : 7.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: compact ? 4 : 5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.62))
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

private struct CurrentPriceBarAnnotation: View {
    let title: String
    let price: String?
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let price {
                Text(price)
                    .font(.system(size: compact ? 6 : 7, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text(title)
                .font(.system(size: compact ? 6.5 : 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: compact ? 4 : 5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.68))
        }
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct WidgetPriceChart: View {
    let hours: [HourlySpotPrice]
    let currentTime: Date
    let labelStride: Int
    var compact = false

    var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.22))

            ForEach(unpublishedHours, id: \.self) { start in
                BarMark(
                    x: .value("Hour", start),
                    y: .value("Awaiting publication", placeholderHeight)
                )
                .foregroundStyle(.secondary.opacity(compact ? 0.16 : 0.14))
                .cornerRadius(compact ? 5 : 8, style: .continuous)
                .accessibilityLabel(start.formatted(.dateTime.hour()))
                .accessibilityValue("Price not published yet")
            }

            ForEach(hours) { hour in
                BarMark(
                    x: .value("Hour", hour.start),
                    y: .value("Price", hour.priceCents)
                )
                .foregroundStyle(
                    hour.band.chartColor.opacity(hour.start == hours.first?.start ? 1 : (compact ? 0.82 : 0.88))
                )
                .cornerRadius(compact ? 5 : 8, style: .continuous)
                .accessibilityLabel(hour.start.formatted(.dateTime.hour()))
                .accessibilityValue(
                    "\(hour.priceCents.widgetPrice) cents per kilowatt-hour, \(hour.band.homeTitle)"
                )
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: axisDates) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisValueLabel(format: .dateTime.hour())
                    .font(.caption2)
            }
        }
        .chartXAxis(compact ? .hidden : .visible)
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let currentHour,
                   let plotFrame = proxy.plotFrame,
                   let xPosition = proxy.position(forX: currentHour.start),
                   let yPosition = proxy.position(forY: max(currentHour.priceCents, 0)) {
                    CurrentBarIndicator(compact: compact)
                        .position(
                            x: geometry[plotFrame].minX + xPosition,
                            y: geometry[plotFrame].minY + yPosition
                                - (compact ? CurrentBarIndicator.compactHeight / 2 + 1 : CurrentBarIndicator.regularHeight / 2 + 2)
                        )
                }
            }
        }
    }

    private var chartStart: Date {
        Calendar.helsinki.startOfDay(for: currentTime)
    }

    private var axisDates: [Date] {
        Swift.stride(from: 0, to: 24, by: labelStride).compactMap {
            Calendar.helsinki.date(byAdding: .hour, value: $0, to: chartStart)
        }
    }

    private var currentHour: HourlySpotPrice? {
        guard let currentHourStart = Calendar.helsinki.dateInterval(of: .hour, for: currentTime)?.start else {
            return nil
        }
        return hours.first { $0.start == currentHourStart }
    }

    private var yDomain: ClosedRange<Double> {
        let prices = hours.map(\.priceCents)
        let lowerBound = min(prices.min() ?? 0, 0)
        let upperBound = max(prices.max() ?? 1, 0)
        let span = max(upperBound - lowerBound, 1)
        return lowerBound...(upperBound + span * (compact ? 0.24 : 0.18))
    }

    private var unpublishedHours: [Date] {
        let published = Set(hours.map(\.start))
        return (0..<24).compactMap {
            Calendar.helsinki.date(byAdding: .hour, value: $0, to: chartStart)
        }
        .filter { !published.contains($0) }
    }

    private var placeholderHeight: Double {
        max((hours.map { abs($0.priceCents) }.max() ?? 1) * 0.06, 0.5)
    }
}

private struct CurrentBarIndicator: View {
    static let compactHeight: CGFloat = 14
    static let regularHeight: CGFloat = 18

    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            Text("Now")
                .font(.system(size: compact ? 7 : 9, weight: .semibold, design: .rounded))
                .tracking(compact ? 0.25 : 0.45)
                .foregroundStyle(.secondary)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: compact ? 5 : 7, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.68))
        }
        .frame(
            width: compact ? 28 : 34,
            height: compact ? Self.compactHeight : Self.regularHeight,
            alignment: .top
        )
        .accessibilityHidden(true)
    }
}

struct PriceTimeInsight: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SpotPriceWidgetFinland: Widget {
    let kind = "FinlandSpotElectricityRates"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinlandSpotPriceProvider()) { entry in
            FinlandSpotPriceEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Finland Electricity Rates")
        .description("Shows the current Finland spot price and today's hourly prices, including VAT.")
        .supportedFamilies(supportedFamilies)
    }

    private var supportedFamilies: [WidgetFamily] {
#if os(iOS)
        [
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .systemExtraLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ]
#else
        [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
#endif
    }
}

#if DEBUG
struct SpotPriceWidgetFinland_Previews: PreviewProvider {
    private static let entry = FinlandSpotPriceEntry(
        date: Date(),
        presentation: .sample()
    )

    static var previews: some View {
        Group {
            FinlandSpotPriceEntryView(entry: entry, familyOverride: .systemSmall)
                .containerBackground(.fill.tertiary, for: .widget)
                .previewContext(WidgetPreviewContext(family: .systemSmall))
                .previewDisplayName("Electricity Rates · Small")

            FinlandSpotPriceEntryView(entry: entry, familyOverride: .systemMedium)
                .containerBackground(.fill.tertiary, for: .widget)
                .previewContext(WidgetPreviewContext(family: .systemMedium))
                .previewDisplayName("Electricity Rates · Medium")
        }
    }
}
#endif

private extension SpotPriceBand {
    var chartColor: Color {
        switch self {
        case .low: .green
        case .typical: .orange
        case .high: .red
        }
    }

    var color: Color {
        switch self {
        case .low: Color(red: 0.20, green: 0.68, blue: 0.36)
        case .typical: Color(red: 0.94, green: 0.65, blue: 0.12)
        case .high: Color(red: 0.90, green: 0.26, blue: 0.22)
        }
    }

    var homeTitle: String {
        switch self {
        case .low: "Off-Peak"
        case .typical: "Standard"
        case .high: "Peak"
        }
    }

    var homeSentence: String {
        switch self {
        case .low: "Priced lower"
        case .typical: "Typical price"
        case .high: "Priced higher"
        }
    }

    var compactSentence: String {
        switch self {
        case .low: "Lower"
        case .typical: "Typical"
        case .high: "Higher"
        }
    }
}

private extension Double {
    var widgetPrice: String {
        formatted(.number.precision(.fractionLength(abs(self) < 10 ? 2 : 1)))
    }
}

private extension SpotPricePresentation {
    var publishedHourCount: Int {
        min(upcomingHours.count, 24)
    }

    var chartAvailabilityLabel: String {
        "Today · 00:00–23:45 · c/kWh"
    }

    var extraLargeChartAvailabilityLabel: String {
        "Today · 00:00–23:45 · hourly average · incl. VAT"
    }

    var chartAccessibilityLabel: String {
        "Today's electricity prices from 00:00 through 23:45, \(publishedHourCount) hourly averages published"
    }

    var rangeMinimum: Double {
        min(upcomingHours.map(\.priceCents).min() ?? currentPriceCents, currentPriceCents)
    }

    var rangeMaximum: Double {
        max(upcomingHours.map(\.priceCents).max() ?? currentPriceCents, currentPriceCents)
    }

    var currentRangeProgress: Double {
        let span = rangeMaximum - rangeMinimum
        guard span > 0.000_001 else { return 0.5 }
        return min(max((currentPriceCents - rangeMinimum) / span, 0), 1)
    }

    var cheapestHour: HourlySpotPrice? {
        upcomingHours.min { $0.priceCents < $1.priceCents }
    }

    var priciestHour: HourlySpotPrice? {
        upcomingHours.max { $0.priceCents < $1.priceCents }
    }

    var accessibilitySummary: String {
        "Finland electricity rate, \(currentPriceCents.widgetPrice) cents per kilowatt-hour, \(currentBand.homeTitle), today's range \(rangeMinimum.widgetPrice) to \(rangeMaximum.widgetPrice) cents"
    }
}
