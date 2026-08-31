import Charts
import SwiftUI

struct DashboardPriceChart: View {
    let day: DashboardPriceDay

    var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1))

            ForEach(day.hours) { hour in
                BarMark(
                    x: .value("Hour", hour.start),
                    y: .value("Price", hour.priceCents),
                    width: .fixed(14)
                )
                .foregroundStyle(hour.band.dashboardColor.gradient)
                .cornerRadius(7, style: .continuous)
                .annotation(position: hour.priceCents < 0 ? .bottom : .top, spacing: 4) {
                    if hour.id == minimumHour?.id || hour.id == maximumHour?.id {
                        Text(hour.priceCents.formattedPrice)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(range: .plotDimension(startPadding: 10, endPadding: 44))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.secondary.opacity(0.7))
                AxisValueLabel(format: FinlandTime.hourStyle).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.14))
                AxisValueLabel().font(.caption2)
            }
        }
        .accessibilityLabel("\(day.day.rawValue) hourly electricity prices")
    }

    private var minimumHour: HourlySpotPrice? {
        day.hours.min(by: { $0.priceCents < $1.priceCents })
    }

    private var maximumHour: HourlySpotPrice? {
        day.hours.max(by: { $0.priceCents < $1.priceCents })
    }

    private var yDomain: ClosedRange<Double> {
        let values = day.hours.map(\.priceCents)
        let minimum = min(values.min() ?? 0, 0)
        let maximum = max(values.max() ?? 1, 0)
        let span = max(maximum - minimum, 1)
        return (minimum - span * 0.12)...(maximum + span * 0.18)
    }
}

struct DashboardRenewableForecastChart: View {
    let points: [GridForecastSignalPoint]
    @Binding var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(sortedPoints) { point in
                AreaMark(
                    x: .value("Time", point.dateTime),
                    y: .value("Renewable share", point.renewableShare)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.32), .green.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("Time", point.dateTime),
                    y: .value("Renewable share", point.renewableShare)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected time", selectedPoint.dateTime))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                PointMark(
                    x: .value("Selected time", selectedPoint.dateTime),
                    y: .value("Renewable share", selectedPoint.renewableShare)
                )
                .foregroundStyle(.green)
                .symbolSize(62)
                .annotation(position: .top, spacing: 8) {
                    ChartValueAnnotation(
                        time: selectedPoint.dateTime,
                        value: "\(selectedPoint.renewableShare.formatted(.number.precision(.fractionLength(0))))%",
                        detail: "Renewable share",
                        color: .green
                    )
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 38))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                AxisTick().foregroundStyle(.secondary.opacity(0.65))
                AxisValueLabel(format: FinlandTime.hourStyle).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                if let percentage = value.as(Int.self) {
                    AxisValueLabel {
                        Text("\(percentage)%")
                            .font(.caption2)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Renewable share forecast for the next 24 hours, shown as a percentage.")
    }

    private var sortedPoints: [GridForecastSignalPoint] {
        points.sorted { $0.dateTime < $1.dateTime }
    }

    private var selectedPoint: GridForecastSignalPoint? {
        guard let selectedDate else { return nil }
        return sortedPoints.min {
            abs($0.dateTime.timeIntervalSince(selectedDate))
                < abs($1.dateTime.timeIntervalSince(selectedDate))
        }
    }
}

struct DashboardEmissionsHistoryChart: View {
    let points: [DashboardEmissionsPoint]
    @Binding var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(sortedPoints) { point in
                BarMark(
                    x: .value("Time", point.date),
                    y: .value("Grid emissions", point.gramsCO2PerKWh),
                    width: .fixed(12)
                )
                .foregroundStyle(Color.cyan.opacity(0.72).gradient)
                .cornerRadius(5, style: .continuous)
            }

            if let selectedPoint {
                RuleMark(x: .value("Selected time", selectedPoint.date))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 8) {
                        ChartValueAnnotation(
                            time: selectedPoint.date,
                            value: selectedPoint.gramsCO2PerKWh.formatted(
                                .number.precision(.fractionLength(0))
                            ),
                            detail: "gCO₂/kWh",
                            color: .cyan
                        )
                    }
            }
        }
        .chartYScale(domain: 0...yMaximum)
        .chartXScale(range: .plotDimension(startPadding: 8, endPadding: 38))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.10))
                AxisTick().foregroundStyle(.secondary.opacity(0.65))
                AxisValueLabel(format: FinlandTime.hourStyle).font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                if let grams = value.as(Double.self) {
                    AxisValueLabel {
                        Text(grams.formatted(.number.precision(.fractionLength(0))))
                            .font(.caption2)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("Grid emissions during the past 24 hours in grams of carbon dioxide per kilowatt-hour.")
    }

    private var sortedPoints: [DashboardEmissionsPoint] {
        points.sorted { $0.date < $1.date }
    }

    private var selectedPoint: DashboardEmissionsPoint? {
        guard let selectedDate else { return nil }
        return sortedPoints.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var yMaximum: Double {
        max((points.map(\.gramsCO2PerKWh).max() ?? 1) * 1.18, 1)
    }
}

private struct ChartValueAnnotation: View {
    let time: Date
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(FinlandTime.clock(time))
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

struct DashboardStatisticsRow: View {
    let statistics: SpotPriceStatistics

    var body: some View {
        HStack(spacing: 10) {
            StatisticCell(title: "Lowest", value: statistics.minimum, color: SpotPriceBand.low.dashboardColor)
            StatisticCell(title: "Average", value: statistics.average, color: SpotPriceBand.typical.dashboardColor)
            StatisticCell(title: "Highest", value: statistics.maximum, color: SpotPriceBand.high.dashboardColor)
        }
    }
}

private struct StatisticCell: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.formattedPrice)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Capsule().fill(color).frame(width: 28, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
