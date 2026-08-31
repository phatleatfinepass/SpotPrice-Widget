import Charts
import Combine
import SwiftUI
import WidgetKit
#if DEBUG && os(macOS)
import AppKit
#endif

@MainActor
final class SpotPriceViewModel: ObservableObject {
    @Published private(set) var presentation: SpotPricePresentation?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository = SpotPriceRepository()

    func loadIfNeeded() async {
        guard presentation == nil else { return }
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let result = try await repository.load()
            guard let presentation = SpotPricePresentation.make(
                points: result.points,
                at: Date(),
                lastUpdated: result.fetchedAt,
                isStale: result.isStale
            ) else {
                throw SpotPriceAPIError.noPrices
            }
            self.presentation = presentation
            errorMessage = result.isStale
                ? "Live prices are unavailable. Showing the latest saved data."
                : nil
            WidgetCenter.shared.reloadTimelines(ofKind: "FinlandSpotElectricityRates")
            WidgetCenter.shared.reloadTimelines(ofKind: "FinlandGridForecast")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetWidgetData() async {
        guard !isLoading else { return }

        WidgetDataStore.resetCaches()
        presentation = nil
        errorMessage = nil
        WidgetCenter.shared.reloadAllTimelines()
        await refresh()
    }
}

struct ContentView: View {
    @StateObject private var model = SpotPriceViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let presentation = model.presentation {
                        if let errorMessage = model.errorMessage {
                            StalePriceBanner(message: errorMessage)
                        }

                        CurrentRateCard(presentation: presentation)
                        UpcomingPriceSection(presentation: presentation)
                    } else if let errorMessage = model.errorMessage {
                        ContentUnavailableView(
                            "Prices unavailable",
                            systemImage: "bolt.trianglebadge.exclamationmark",
                            description: Text(errorMessage)
                        )
                        .frame(maxWidth: .infinity, minHeight: 260)
                    } else {
                        ProgressView("Loading Finland prices…")
                            .frame(maxWidth: .infinity, minHeight: 260)
                    }

#if os(macOS)
                    ProductManagementSections(
                        resetDisabled: model.isLoading,
                        onReset: { await model.resetWidgetData() }
                    )
#endif
                }
                .frame(maxWidth: 760)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Electricity Rates")
            .toolbar {
                ToolbarItem {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        if model.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .task {
#if DEBUG && os(macOS)
            if await runUninstallIntegrationTestIfRequested() {
                return
            }
#endif
            await model.loadIfNeeded()
        }
    }

#if DEBUG && os(macOS)
    private func runUninstallIntegrationTestIfRequested() async -> Bool {
        guard ProcessInfo.processInfo.environment["SPOTPRICE_TEST_UNINSTALL"] == "1" else {
            return false
        }

        do {
            let destinationURL = try await ProductUninstallerClient.moveContainingAppToTrash()
            FileHandle.standardOutput.write(Data("UNINSTALL_DESTINATION=\(destinationURL.path)\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("UNINSTALL_ERROR=\(error.localizedDescription)\n".utf8))
        }
        NSApplication.shared.terminate(nil)
        return true
    }
#endif
}

private struct CurrentRateCard: View {
    let presentation: SpotPricePresentation

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Finland · Spot price", systemImage: "bolt.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(presentation.currentBand.title)
                    .font(.system(.title, design: .rounded, weight: .bold))

                if let bandEndsAt = presentation.bandEndsAt {
                    Text("Until \(FinlandTime.clock(bandEndsAt))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                Text("Includes VAT · updates every 15 minutes")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            RateGauge(
                priceCents: presentation.currentPriceCents,
                progress: presentation.currentRankProgress,
                band: presentation.currentBand,
                size: 128
            )
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Current Finland electricity price, \(presentation.currentPriceCents.formattedPrice) cents per kilowatt-hour, \(presentation.currentBand.title)"
        )
    }
}

private struct UpcomingPriceSection: View {
    let presentation: SpotPricePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today · 00:00–23:45")
                        .font(.title2.bold())
                    Text("Hourly averages from 15-minute market prices")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("c/kWh")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            PriceChart(
                hours: presentation.upcomingHours,
                currentTime: presentation.referenceDate
            )
                .frame(height: 230)

            StatisticsRow(statistics: presentation.statistics)

            Divider()

            LazyVStack(spacing: 0) {
                ForEach(presentation.upcomingHours) { hour in
                    HourlyPriceRow(hour: hour)
                    if hour.id != presentation.upcomingHours.last?.id {
                        Divider().padding(.leading, 48)
                    }
                }
            }

            HStack {
                Text("Updated \(FinlandTime.clock(presentation.lastUpdated))")
                Spacer()
                if let availableThrough = presentation.availableThrough {
                    Text("Available through \(FinlandTime.weekdayClock(availableThrough))")
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Link(destination: URL(string: "https://spot-hinta.fi/")!) {
                Label("Price data from spot-hinta.fi", systemImage: "link")
                    .font(.caption2)
            }

            Link(destination: URL(string: "https://www.energy-charts.info/")!) {
                Label("Grid forecast data from Energy-Charts.info", systemImage: "leaf.fill")
                    .font(.caption2)
            }

            Link(destination: URL(string: "https://data.fingrid.fi/en/datasets/396")!) {
                Label("Grid emissions data from Fingrid Open Data", systemImage: "leaf.fill")
                    .font(.caption2)
            }
        }
        .padding(22)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct PriceChart: View {
    let hours: [HourlySpotPrice]
    let currentTime: Date

    var body: some View {
        Chart {
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(.secondary.opacity(0.35))

            ForEach(hours) { hour in
                BarMark(
                    x: .value("Hour", hour.start),
                    y: .value("Price", hour.priceCents)
                )
                .foregroundStyle(hour.band.color.gradient)
                .cornerRadius(7, style: .continuous)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 4)) { _ in
                AxisGridLine().foregroundStyle(.clear)
                AxisTick().foregroundStyle(.secondary)
                AxisValueLabel(format: FinlandTime.hourStyle)
                    .font(.caption2)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { _ in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel()
                    .font(.caption2)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                if let currentHour,
                   let plotFrame = proxy.plotFrame,
                   let xPosition = proxy.position(forX: currentHour.start),
                   let yPosition = proxy.position(forY: max(currentHour.priceCents, 0)) {
                    AppCurrentBarIndicator()
                        .position(
                            x: geometry[plotFrame].minX + xPosition,
                            y: geometry[plotFrame].minY + yPosition - AppCurrentBarIndicator.height / 2 - 2
                        )
                }
            }
        }
        .accessibilityLabel("Electricity prices today from 00:00 through 23:45")
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
        return lowerBound...(upperBound + span * 0.15)
    }
}

private struct AppCurrentBarIndicator: View {
    static let height: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            Text("Now")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(.secondary)

            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.68))
        }
        .frame(width: 38, height: Self.height, alignment: .top)
        .accessibilityHidden(true)
    }
}

private struct StatisticsRow: View {
    let statistics: SpotPriceStatistics

    var body: some View {
        HStack(spacing: 10) {
            StatisticCell(title: "Lowest", value: statistics.minimum, color: SpotPriceBand.low.color)
            StatisticCell(title: "Average", value: statistics.average, color: SpotPriceBand.typical.color)
            StatisticCell(title: "Highest", value: statistics.maximum, color: SpotPriceBand.high.color)
        }
    }
}

private struct StatisticCell: View {
    let title: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value.formattedPrice)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Capsule()
                .fill(color)
                .frame(width: 28, height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HourlyPriceRow: View {
    let hour: HourlySpotPrice

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(hour.band.color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)

            Text(FinlandTime.clock(hour.start))
                .font(.body.monospacedDigit())
                .frame(width: 54, alignment: .leading)

            Text(hour.band.title)
                .foregroundStyle(.secondary)

            Spacer()

            Text("\(hour.priceCents.formattedPrice) c/kWh")
                .font(.body.weight(.semibold).monospacedDigit())
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }
}

private struct StalePriceBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct RateGauge: View {
    let priceCents: Double
    let progress: Double
    let band: SpotPriceBand
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0.1, to: 0.9)
                .stroke(.secondary.opacity(0.16), style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))

            Circle()
                .trim(from: 0.1, to: 0.1 + 0.8 * min(max(progress, 0), 1))
                .stroke(band.color.gradient, style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
        }
        .rotationEffect(.degrees(90))
        .overlay {
            VStack(spacing: -1) {
                Text(priceCents.formattedPrice)
                    .font(.system(size: size * 0.23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                Text("c/kWh")
                    .font(.system(size: size * 0.09, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(size * 0.15)
        }
        .frame(width: size, height: size)
    }
}

private extension SpotPriceBand {
    var color: Color {
        switch self {
        case .low: Color(red: 0.20, green: 0.68, blue: 0.36)
        case .typical: Color(red: 0.94, green: 0.65, blue: 0.12)
        case .high: Color(red: 0.90, green: 0.26, blue: 0.22)
        }
    }
}

private extension Double {
    var formattedPrice: String {
        formatted(.number.precision(.fractionLength(abs(self) < 10 ? 2 : 1)))
    }
}
