import SwiftUI

struct DashboardView: View {
    @ObservedObject var model: DashboardViewModel
    @State private var selectedDay: DashboardDay = .tomorrow

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ForEach(Array(model.notices.enumerated()), id: \.offset) { _, notice in
                    DashboardNotice(message: notice)
                }

                if let price = model.pricePresentation {
                    LiveOverviewCard(
                        price: price,
                        emissions: model.emissionsPresentation,
                        bestWindow: model.bestWindow
                    )

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) {
                            PriceDashboardCard(
                                days: model.priceDays,
                                selectedDay: $selectedDay
                            )
                            .frame(minWidth: 520, maxWidth: .infinity)

                            GridDashboardCard(
                                series: model.gridSeries,
                                emissions: model.emissionsPresentation,
                                forecast: model.forecastPresentation
                            )
                            .frame(minWidth: 520, maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)

                        VStack(spacing: 18) {
                            PriceDashboardCard(
                                days: model.priceDays,
                                selectedDay: $selectedDay
                            )
                            GridDashboardCard(
                                series: model.gridSeries,
                                emissions: model.emissionsPresentation,
                                forecast: model.forecastPresentation
                            )
                        }
                    }

                    if let day = resolvedPriceDay {
                        HourlyPricesCard(day: day, forecast: model.forecastPresentation)
                    }

                    DashboardSourceFooter(
                        priceUpdated: price.lastUpdated,
                        forecastUpdated: model.forecastPresentation?.lastUpdated,
                        emissionsUpdated: model.emissionsPresentation.measuredAt
                    )
                } else if model.isLoading {
                    ProgressView("Loading Finland energy data…")
                        .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ContentUnavailableView(
                        "Energy data unavailable",
                        systemImage: "bolt.trianglebadge.exclamationmark",
                        description: Text(model.notices.first ?? "Try refreshing the data.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                }

#if os(macOS)
                ProductManagementSections(
                    resetDisabled: model.isLoading,
                    onReset: { await model.resetWidgetData() }
                )
#endif
            }
            .frame(maxWidth: 1420)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await model.refresh() }
        .onChange(of: model.priceDays.count) { _, _ in
            if model.priceDays[selectedDay] == nil {
                selectedDay = model.priceDays[.tomorrow] != nil ? .tomorrow : .today
            }
        }
    }

    private var resolvedPriceDay: DashboardPriceDay? {
        model.priceDays[selectedDay]
    }
}

private struct LiveOverviewCard: View {
    let price: SpotPricePresentation
    let emissions: GridEmissionsPresentation
    let bestWindow: DashboardBestWindow?

    var body: some View {
        HStack(spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(price.currentBand.dashboardColor)
                    .frame(width: 52)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("LIVE")
                            .foregroundStyle(price.currentBand.dashboardColor)
                        Text("· \(price.currentBand.title)")
                    }
                    .font(.caption.weight(.semibold))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(price.currentPriceCents.formattedPrice)
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("c/kWh")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(price.bandEndsAt.map { "This price band ends at \(FinlandTime.clock($0))" } ?? "Live 15-minute price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 11) {
                PriceRangeGauge(
                    price: price.currentPriceCents,
                    minimum: price.statistics.minimum,
                    maximum: price.statistics.maximum
                )

                Label(
                    bestWindow.map { "Best combined window · \(FinlandTime.clock($0.start))–\(FinlandTime.clock($0.end))" }
                        ?? "Best combined window is waiting for overlapping data",
                    systemImage: "calendar.badge.clock"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(bestWindow == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
            }
            .frame(maxWidth: .infinity)

            Divider().padding(.vertical, 4)

            HStack(spacing: 14) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(emissions.band?.dashboardColor ?? .secondary)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text("LIVE")
                            .foregroundStyle(emissions.band?.dashboardColor ?? .secondary)
                        Text("· Grid emissions")
                    }
                    .font(.caption.weight(.semibold))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(emissions.valueText)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text("gCO₂/kWh")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text(emissions.band?.title ?? "Data unavailable")
                        .font(.headline)
                        .foregroundStyle(emissions.band?.dashboardColor ?? .secondary)
                }
            }
            .frame(minWidth: 300, alignment: .leading)
        }
        .padding(22)
        .dashboardCard()
    }
}

private struct PriceRangeGauge: View {
    let price: Double
    let minimum: Double
    let maximum: Double

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let lowStop = position(for: 4.99)
                let typicalStop = position(for: 8.99)

                ZStack(alignment: .topLeading) {
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(SpotPriceBand.low.dashboardColor)
                            .frame(width: width * lowStop)
                        Rectangle()
                            .fill(SpotPriceBand.typical.dashboardColor)
                            .frame(width: width * max(typicalStop - lowStop, 0))
                        Rectangle()
                            .fill(SpotPriceBand.high.dashboardColor)
                            .frame(width: width * max(1 - typicalStop, 0))
                    }
                    .frame(width: width, height: 10)
                    .clipShape(Capsule())
                    .offset(y: 22)

                    VStack(spacing: 1) {
                        Text(price.formattedPrice)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: "arrowtriangle.down.fill")
                            .font(.system(size: 7))
                    }
                    .frame(width: 48)
                    .offset(x: max(0, min(width - 48, width * position(for: price) - 24)))

                    if domain.lowerBound < 4.99, domain.upperBound > 4.99 {
                        GaugeThresholdLabel(value: "5")
                            .position(x: width * lowStop, y: 42)
                    }
                    if domain.lowerBound < 8.99, domain.upperBound > 8.99 {
                        GaugeThresholdLabel(value: "9")
                            .position(x: width * typicalStop, y: 42)
                    }
                }
            }
            .frame(height: 50)

            HStack {
                Text("Lowest \(domain.lowerBound.formattedPrice)")
                Spacer()
                Text("Highest \(domain.upperBound.formattedPrice)")
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Current price \(price.formattedPrice) cents per kilowatt-hour. "
            + "Daily range from \(domain.lowerBound.formattedPrice) to \(domain.upperBound.formattedPrice). "
            + "Low prices end at 4.99 and typical prices end at 8.99."
        )
    }

    private var domain: ClosedRange<Double> {
        let lower = min(minimum, price)
        let upper = max(maximum, price)
        return lower...(upper > lower ? upper : lower + 1)
    }

    private func position(for value: Double) -> Double {
        min(max((value - domain.lowerBound) / (domain.upperBound - domain.lowerBound), 0), 1)
    }
}

private struct GaugeThresholdLabel: View {
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Rectangle()
                .fill(.secondary.opacity(0.55))
                .frame(width: 1, height: 5)
            Text(value)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

private struct PriceDashboardCard: View {
    let days: [DashboardDay: DashboardPriceDay]
    @Binding var selectedDay: DashboardDay

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardCardHeader(
                title: "Electricity prices",
                subtitle: priceSubtitle,
                trailing: "c/kWh"
            )

            Picker("Price day", selection: $selectedDay) {
                ForEach(DashboardDay.allCases) { dayChoice in
                    Text(dayChoice.rawValue)
                        .tag(dayChoice)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .accessibilityHint("Choose a day. Unpublished prices show their expected publication time.")

            if let day {
                DashboardPriceChart(day: day)
                    .frame(height: 260)
                DashboardStatisticsRow(statistics: day.statistics)
            } else {
                ContentUnavailableView(
                    selectedDay == .tomorrow ? "Tomorrow isn’t published yet" : "Today’s prices are unavailable",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text(
                        selectedDay == .tomorrow
                            ? "Tomorrow’s Finland prices are normally published after 14:00 Helsinki time."
                            : "Refresh to try loading the latest Finland prices."
                    )
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(22)
        .dashboardCard()
    }

    private var day: DashboardPriceDay? {
        days[selectedDay]
    }

    private var priceSubtitle: String {
        if let day {
            return "\(day.date.formatted(DashboardFormatting.day)) · hourly averages"
        }
        return selectedDay == .tomorrow
            ? "Expected after 14:00 Helsinki time"
            : "Live data unavailable"
    }
}

private struct GridDashboardCard: View {
    private enum Detail: String, CaseIterable, Identifiable {
        case forecast = "Forecast"
        case history = "History"

        var id: Self { self }
    }

    let series: DashboardGridSeries
    let emissions: GridEmissionsPresentation
    let forecast: GridForecastPresentation?
    @State private var detail: Detail = .forecast
    @State private var selectedForecastDate: Date?
    @State private var selectedEmissionsDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DashboardCardHeader(
                title: "Grid conditions",
                subtitle: "Current emissions and renewable outlook",
                trailing: headerStatus
            )

            GridCurrentSummary(emissions: emissions, forecast: forecast)

            Picker("Grid detail", selection: $detail) {
                ForEach(Detail.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            switch detail {
            case .forecast:
                forecastContent
            case .history:
                historyContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(22)
        .dashboardCard()
    }

    @ViewBuilder
    private var forecastContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GridSectionHeader(
                title: "Renewable outlook",
                subtitle: "Forecast share of electricity demand · next 24 hours",
                unit: "%"
            )

            if let forecast, !forecast.isUnavailable, !forecast.forecastPoints.isEmpty {
                DashboardRenewableForecastChart(
                    points: forecast.forecastPoints,
                    selectedDate: $selectedForecastDate
                )
                .frame(height: 250)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(cleanerWindowText(for: forecast), systemImage: "leaf.fill")
                        .foregroundStyle(.green)
                    Spacer(minLength: 12)
                    Text(peakText(for: forecast))
                        .foregroundStyle(.secondary)
                }
                .font(.caption.weight(.semibold))
            } else {
                ContentUnavailableView(
                    "Renewable forecast unavailable",
                    systemImage: "leaf",
                    description: Text("Refresh to load the next 24 hours from Energy-Charts.")
                )
                .frame(maxWidth: .infinity, minHeight: 282)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 390, maxHeight: 390, alignment: .topLeading)
    }

    @ViewBuilder
    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            GridSectionHeader(
                title: "Grid emissions",
                subtitle: "Measured carbon intensity · past 24 hours",
                unit: "gCO₂/kWh"
            )

            if series.emissions.isEmpty {
                ContentUnavailableView(
                    "Past emissions unavailable",
                    systemImage: "chart.bar.xaxis",
                    description: Text("The current Fingrid measurement is still shown above.")
                )
                .frame(maxWidth: .infinity, minHeight: 282)
            } else {
                DashboardEmissionsHistoryChart(
                    points: series.emissions,
                    selectedDate: $selectedEmissionsDate
                )
                .frame(height: 250)

                GridEmissionsStatisticsRow(points: series.emissions)

                if series.usesPreviewEmissionsHistory {
                    Label("Preview history · live historical measurements unavailable", systemImage: "eye")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 390, maxHeight: 390, alignment: .topLeading)
    }

    private var headerStatus: String {
        if emissions.gramsCO2PerKWh == nil { return "Live value unavailable" }
        return emissions.isStale ? "Cached value" : "Live"
    }

    private func cleanerWindowText(for forecast: GridForecastPresentation) -> String {
        guard let run = forecast.signalRuns.first(where: {
            $0.state == .high && $0.end > forecast.timelineStart
        }) else {
            return "No stronger window forecast"
        }

        if run.start <= forecast.referenceDate.addingTimeInterval(15 * 60) {
            return "Cleaner period now–\(FinlandTime.clock(run.end))"
        }
        return "Cleaner window \(FinlandTime.clock(run.start))–\(FinlandTime.clock(run.end))"
    }

    private func peakText(for forecast: GridForecastPresentation) -> String {
        guard let peak = forecast.forecastPoints.max(by: {
            $0.renewableShare < $1.renewableShare
        }) else { return "Peak unavailable" }
        let share = peak.renewableShare.formatted(.number.precision(.fractionLength(0)))
        let time = Calendar.helsinki.isDate(peak.dateTime, inSameDayAs: forecast.referenceDate)
            ? FinlandTime.clock(peak.dateTime)
            : FinlandTime.weekdayClock(peak.dateTime)
        return "Peak \(share)% at \(time)"
    }
}

private struct GridCurrentSummary: View {
    let emissions: GridEmissionsPresentation
    let forecast: GridForecastPresentation?

    var body: some View {
        HStack(spacing: 20) {
            metric(
                eyebrow: "EMISSIONS NOW",
                value: emissions.valueText,
                unit: "gCO₂/kWh",
                detail: emissions.band?.title ?? "Data unavailable",
                color: emissions.band?.dashboardColor ?? .secondary,
                icon: "carbon.dioxide.cloud.fill"
            )

            Divider()

            metric(
                eyebrow: "RENEWABLE NOW",
                value: renewableValue,
                unit: "%",
                detail: forecast?.outlookSentence ?? "Forecast unavailable",
                color: .green,
                icon: "leaf.fill"
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.48), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var renewableValue: String {
        forecast?.currentRenewableShare?.formatted(
            .number.precision(.fractionLength(0))
        ) ?? "—"
    }

    private func metric(
        eyebrow: String,
        value: String,
        unit: String,
        detail: String,
        color: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct GridSectionHeader: View {
    let title: String
    let subtitle: String
    let unit: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(unit)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

private struct GridEmissionsStatisticsRow: View {
    let points: [DashboardEmissionsPoint]

    var body: some View {
        HStack(spacing: 8) {
            statistic("Lowest", values.min())
            statistic("Average", values.isEmpty ? nil : values.reduce(0, +) / Double(values.count))
            statistic("Highest", values.max())
        }
    }

    private var values: [Double] { points.map(\.gramsCO2PerKWh) }

    private func statistic(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value?.formatted(.number.precision(.fractionLength(0))) ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("gCO₂/kWh")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct HourlyPricesCard: View {
    let day: DashboardPriceDay
    let forecast: GridForecastPresentation?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DashboardCardHeader(
                title: "Hourly prices",
                subtitle: day.date.formatted(DashboardFormatting.day),
                trailing: "\(day.hours.count) hours"
            )

            Table(day.hours) {
                TableColumn("Time") { hour in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(hour.band.dashboardColor)
                            .frame(width: 8, height: 8)
                        Text(FinlandTime.clock(hour.start)).monospacedDigit()
                    }
                }
                .width(min: 100, ideal: 125)

                TableColumn("Condition") { hour in
                    Text(hour.band.title).foregroundStyle(.secondary)
                }

                TableColumn("Renewable forecast") { hour in
                    if let point = forecastPoint(for: hour) {
                        Text("\(point.renewableShare.formatted(.number.precision(.fractionLength(0))))%")
                            .monospacedDigit()
                    } else {
                        Text("—").foregroundStyle(.tertiary)
                    }
                }

                TableColumn("Recommendation") { hour in
                    Text(recommendation(for: hour))
                        .foregroundStyle(recommendationColor(for: hour))
                }

                TableColumn("Price") { hour in
                    Text("\(hour.priceCents.formattedPrice) c/kWh")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }
                .width(min: 120, ideal: 150)
            }
            .frame(height: 330)
        }
        .padding(22)
        .dashboardCard()
    }

    private func forecastPoint(for hour: HourlySpotPrice) -> GridForecastSignalPoint? {
        let hourEnd = hour.start.addingTimeInterval(60 * 60)
        let points = forecast?.forecastPoints.filter { $0.dateTime >= hour.start && $0.dateTime < hourEnd } ?? []
        guard !points.isEmpty else { return nil }
        return points.min(by: {
            abs($0.dateTime.timeIntervalSince(hour.start)) < abs($1.dateTime.timeIntervalSince(hour.start))
        })
    }

    private func recommendation(for hour: HourlySpotPrice) -> String {
        let gridState = forecastPoint(for: hour)?.state
        if hour.band == .low, gridState == .high { return "Run appliances" }
        if hour.band == .high { return "Avoid if flexible" }
        if gridState == .high { return "Cleaner window" }
        return "Flexible"
    }

    private func recommendationColor(for hour: HourlySpotPrice) -> Color {
        switch recommendation(for: hour) {
        case "Run appliances", "Cleaner window": .green
        case "Avoid if flexible": .red
        default: .secondary
        }
    }
}

private struct DashboardSourceFooter: View {
    let priceUpdated: Date
    let forecastUpdated: Date?
    let emissionsUpdated: Date?

    var body: some View {
        HStack(spacing: 20) {
            SourceLink(
                title: "spot-hinta.fi",
                updated: priceUpdated,
                url: "https://spot-hinta.fi/",
                icon: "bolt.fill"
            )
            SourceLink(
                title: "Energy-Charts.info",
                updated: forecastUpdated,
                url: "https://www.energy-charts.info/",
                icon: "leaf.fill"
            )
            SourceLink(
                title: "Fingrid Open Data",
                updated: emissionsUpdated,
                url: "https://data.fingrid.fi/en/datasets/396",
                icon: "carbon.dioxide.cloud.fill"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}

private struct SourceLink: View {
    let title: String
    let updated: Date?
    let url: String
    let icon: String

    var body: some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: icon)
                Text(updated.map { "Updated \(FinlandTime.clock($0))" } ?? "Update unavailable")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }
}

private struct DashboardCardHeader: View {
    let title: String
    let subtitle: String
    let trailing: String

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(trailing).font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

private struct ChartLegendItem: View {
    let title: String
    let subtitle: String
    let color: Color
    let symbol: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DashboardNotice: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private extension View {
    func dashboardCard() -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
