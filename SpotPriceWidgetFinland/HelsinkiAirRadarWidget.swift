import MapKit
import SwiftUI
import WidgetKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct HelsinkiAirRadarEntry: TimelineEntry {
    let date: Date
    let snapshot: AirTrafficSnapshot
    let mapImageData: Data?
}

struct HelsinkiAirRadarProvider: TimelineProvider {
    func placeholder(in context: Context) -> HelsinkiAirRadarEntry {
        HelsinkiAirRadarEntry(
            date: Date(),
            snapshot: .sample(),
            mapImageData: AirRadarMapCache().load()
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (HelsinkiAirRadarEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        Task {
            let now = Date()
            async let snapshot = AirTrafficRepository().load()
            async let mapImageData = AirRadarMapRepository().load()
            completion(HelsinkiAirRadarEntry(
                date: now,
                snapshot: await snapshot,
                mapImageData: await mapImageData
            ))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HelsinkiAirRadarEntry>) -> Void) {
        Task {
            let now = Date()
            async let snapshot = AirTrafficRepository().load()
            async let mapImageData = AirRadarMapRepository().load()
            let entry = HelsinkiAirRadarEntry(
                date: now,
                snapshot: await snapshot,
                mapImageData: await mapImageData
            )
            completion(Timeline(
                entries: [entry],
                policy: .after(now.addingTimeInterval(15 * 60))
            ))
        }
    }
}

struct HelsinkiAirRadarEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HelsinkiAirRadarEntry
    var familyOverride: WidgetFamily?

    init(entry: HelsinkiAirRadarEntry, familyOverride: WidgetFamily? = nil) {
        self.entry = entry
        self.familyOverride = familyOverride
    }

    var body: some View {
        Group {
            if entry.snapshot.isUnavailable {
                AirRadarUnavailableView(date: entry.date)
            } else {
                switch familyOverride ?? family {
                case .systemMedium:
                    MediumAirRadarView(entry: entry)
                default:
                    SmallAirRadarView(entry: entry)
                }
            }
        }
        .foregroundStyle(RadarPalette.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        if entry.snapshot.isUnavailable {
            return "Helsinki air traffic snapshot is unavailable. Retrying on the next scan."
        }

        let count = entry.snapshot.contacts.count
        let cacheNote = entry.snapshot.isStale ? " Showing a cached snapshot." : ""
        let grouped = Dictionary(grouping: entry.snapshot.contacts, by: \.movement)
        let movements = [
            AirTrafficMovement.inbound,
            .outbound,
            .cruise,
            .crossing,
        ]
        .compactMap { movement -> String? in
            guard let movementCount = grouped[movement]?.count, movementCount > 0 else { return nil }
            return "\(movementCount) \(movement.title.lowercased())"
        }
        .joined(separator: ", ")
        let movementNote = movements.isEmpty ? "" : " Estimated movement: \(movements)."
        return "Helsinki airspace radar detected \(count) airborne aircraft within 80 kilometers of Helsinki Airport.\(movementNote)\(cacheNote)"
    }
}

private struct SmallAirRadarView: View {
    let entry: HelsinkiAirRadarEntry

    var body: some View {
        ZStack {
            RadarPlot(
                contacts: entry.snapshot.contacts,
                scanDate: entry.date,
                maxContacts: 10,
                showsLocationLabels: false,
                mapImageData: entry.mapImageData
            )
            .padding(13)

            VStack(spacing: 0) {
                AirRadarHeader(contactCount: entry.snapshot.contacts.count, compact: true)

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    RadarScanStatus(snapshot: entry.snapshot)
                    Spacer(minLength: 4)
                    Text("80 KM")
                }
                .font(RadarType.micro)
                .foregroundStyle(RadarPalette.secondary)
            }
            .padding(10)

            if entry.snapshot.contacts.isEmpty {
                RadarEmptyLabel()
            }
        }
    }
}

private struct MediumAirRadarView: View {
    let entry: HelsinkiAirRadarEntry

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RadarPlot(
                    contacts: entry.snapshot.contacts,
                    scanDate: entry.date,
                    maxContacts: 14,
                    showsLocationLabels: entry.mapImageData == nil,
                    mapImageData: entry.mapImageData
                )

                if entry.snapshot.contacts.isEmpty {
                    RadarEmptyLabel()
                }
            }
            .aspectRatio(1, contentMode: .fit)

            Rectangle()
                .fill(RadarPalette.grid.opacity(0.55))
                .frame(width: 0.5)

            VStack(alignment: .leading, spacing: 6) {
                AirRadarHeader(contactCount: entry.snapshot.contacts.count, compact: false)

                Rectangle()
                    .fill(RadarPalette.grid.opacity(0.55))
                    .frame(height: 0.5)

                if entry.snapshot.contacts.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("NO CONTACTS")
                            .font(RadarType.label)
                        Text("No airborne ADS-B positions detected in range")
                            .font(RadarType.micro)
                            .foregroundStyle(RadarPalette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                } else {
                    VStack(spacing: 4) {
                        ForEach(entry.snapshot.contacts.prefix(4)) { contact in
                            RadarContactRow(contact: contact)
                        }
                    }
                    Spacer(minLength: 0)
                }

                HStack {
                    RadarScanStatus(snapshot: entry.snapshot)
                    Spacer(minLength: 4)
                    Text("OPENSKY")
                }
                .font(RadarType.micro)
                .foregroundStyle(RadarPalette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
    }
}

private struct AirRadarHeader: View {
    let contactCount: Int
    let compact: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Circle()
                .fill(RadarPalette.primary)
                .frame(width: 5, height: 5)
                .shadow(color: RadarPalette.glow, radius: 3)

            Text(compact ? "HEL RADAR" : "HEL AIRSPACE")
                .font(compact ? RadarType.compactTitle : RadarType.title)
                .tracking(compact ? 0.8 : 1.1)

            Spacer(minLength: 3)

            Text("\(contactCount) ACFT")
                .font(RadarType.label)
                .monospacedDigit()
                .foregroundStyle(RadarPalette.secondary)
        }
        .lineLimit(1)
    }
}

private struct RadarScanStatus: View {
    let snapshot: AirTrafficSnapshot

    var body: some View {
        HStack(spacing: 3) {
            Text(snapshot.isStale ? "CACHED" : "SCAN")
                .foregroundStyle(snapshot.isStale ? RadarPalette.warning : RadarPalette.secondary)
            Text(snapshot.fetchedAt, format: .dateTime.hour().minute())
                .monospacedDigit()
        }
    }
}

private struct RadarContactRow: View {
    let contact: AirTrafficContact

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "airplane")
                .font(.system(size: 8, weight: .semibold))
                .rotationEffect(.degrees((contact.trackDegrees ?? 90) - 90))
                .frame(width: 13, height: 13)
                .foregroundStyle(RadarPalette.color(for: contact.movement))

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(contact.callsign)
                        .font(RadarType.label)
                        .lineLimit(1)
                    RadarMovementBadge(movement: contact.movement)
                }
                Text(contact.compactDetail)
                    .font(RadarType.micro)
                    .foregroundStyle(RadarPalette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RadarPlot: View {
    let contacts: [AirTrafficContact]
    let scanDate: Date
    let maxContacts: Int
    let showsLocationLabels: Bool
    let mapImageData: Data?

    private let region = AirTrafficRegion.helsinki

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let radius = max(0, min(size.width, size.height) / 2 - 3)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            ZStack {
                if let mapImageData {
                    RadarMapLayer(imageData: mapImageData)
                        .frame(width: radius * 2, height: radius * 2)
                        .clipShape(Circle())
                        .position(center)
                }

                Canvas { context, canvasSize in
                    drawRadarGrid(context: &context, size: canvasSize)
                    drawSweep(context: &context, center: center, radius: radius)
                }

                if showsLocationLabels {
                    ForEach(RadarReferencePoint.helsinkiArea) { point in
                        RadarLocationMarker(label: point.label)
                            .position(position(
                                latitude: point.latitude,
                                longitude: point.longitude,
                                center: center,
                                radius: radius
                            ))
                    }
                }

                ForEach(Array(contacts.prefix(maxContacts)).indices, id: \.self) { index in
                    let contact = contacts[index]
                    RadarContactBlip(
                        contact: contact,
                        showsCallsign: index < (showsLocationLabels ? 8 : 5)
                    )
                    .position(position(
                        latitude: contact.latitude,
                        longitude: contact.longitude,
                        center: center,
                        radius: radius
                    ))
                }

                Circle()
                    .fill(RadarPalette.primary)
                    .frame(width: 3, height: 3)
                    .shadow(color: RadarPalette.glow, radius: 3)
                    .position(center)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var sweepBearing: Double {
        scanDate.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: 120) / 120 * 360
    }

    private func drawRadarGrid(context: inout GraphicsContext, size: CGSize) {
        let radius = max(0, min(size.width, size.height) / 2 - 3)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let gridStyle = StrokeStyle(lineWidth: 0.55)

        for fraction in [0.25, 0.5, 0.75, 1.0] {
            let ringRadius = radius * fraction
            let rect = CGRect(
                x: center.x - ringRadius,
                y: center.y - ringRadius,
                width: ringRadius * 2,
                height: ringRadius * 2
            )
            context.stroke(
                Path(ellipseIn: rect),
                with: .color(RadarPalette.grid.opacity(fraction == 1 ? 0.8 : 0.42)),
                style: gridStyle
            )
        }

        for bearing in stride(from: 0.0, to: 360.0, by: 45.0) {
            let radians = (bearing - 90) * .pi / 180
            var line = Path()
            line.move(to: center)
            line.addLine(to: CGPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            ))
            context.stroke(
                line,
                with: .color(RadarPalette.grid.opacity(bearing.truncatingRemainder(dividingBy: 90) == 0 ? 0.48 : 0.24)),
                style: gridStyle
            )
        }

        let north = context.resolve(
            Text("N")
                .font(RadarType.micro)
                .foregroundStyle(RadarPalette.secondary)
        )
        context.draw(north, at: CGPoint(x: center.x, y: center.y - radius + 6))
    }

    private func drawSweep(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let endAngle = Angle(degrees: sweepBearing - 90)
        let startAngle = Angle(degrees: sweepBearing - 124)
        var wedge = Path()
        wedge.move(to: center)
        wedge.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        wedge.closeSubpath()
        context.fill(
            wedge,
            with: .radialGradient(
                Gradient(colors: [RadarPalette.primary.opacity(0.03), RadarPalette.primary.opacity(0.14)]),
                center: center,
                startRadius: 0,
                endRadius: radius
            )
        )

        let radians = (sweepBearing - 90) * .pi / 180
        var sweepLine = Path()
        sweepLine.move(to: center)
        sweepLine.addLine(to: CGPoint(
            x: center.x + cos(radians) * radius,
            y: center.y + sin(radians) * radius
        ))
        context.stroke(
            sweepLine,
            with: .color(RadarPalette.primary.opacity(0.9)),
            style: StrokeStyle(lineWidth: 1)
        )
    }

    private func position(
        latitude: Double,
        longitude: Double,
        center: CGPoint,
        radius: CGFloat
    ) -> CGPoint {
        let vector = region.normalizedPosition(latitude: latitude, longitude: longitude)
        return CGPoint(
            x: center.x + CGFloat(vector.x) * radius,
            y: center.y - CGFloat(vector.y) * radius
        )
    }
}

private struct RadarMapLayer: View {
    let imageData: Data

    var body: some View {
        Group {
#if os(iOS)
            if let image = UIImage(data: imageData) {
                styledMap(Image(uiImage: image))
            }
#elseif os(macOS)
            if let image = NSImage(data: imageData) {
                styledMap(Image(nsImage: image))
            }
#endif
        }
    }

    private func styledMap(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .saturation(0.16)
            .contrast(1.35)
            .brightness(-0.3)
            .overlay(RadarPalette.background.opacity(0.42))
            .clipped()
    }
}

private struct AirRadarMapRepository {
    private let cache = AirRadarMapCache()

    func load() async -> Data? {
        if let cached = cache.load() { return cached }
        guard let imageData = await AirRadarMapSnapshotter().makeImageData() else { return nil }
        cache.save(imageData)
        return imageData
    }
}

private struct AirRadarMapCache {
    private var fileURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("hel-air-radar-map-v1.png")
    }

    func load() -> Data? {
        guard let fileURL else { return nil }
        return try? Data(contentsOf: fileURL)
    }

    func save(_ imageData: Data) {
        guard let fileURL else { return }
        try? imageData.write(to: fileURL, options: .atomic)
    }
}

@MainActor
private struct AirRadarMapSnapshotter {
    func makeImageData() async -> Data? {
        let region = AirTrafficRegion.helsinki
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: region.centerLatitude,
                longitude: region.centerLongitude
            ),
            latitudinalMeters: region.radiusKm * 2_000,
            longitudinalMeters: region.radiusKm * 2_000
        )
        options.size = CGSize(width: 320, height: 320)

        options.mapType = .mutedStandard

#if os(iOS)
        options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
#elseif os(macOS)
        options.appearance = NSAppearance(named: .darkAqua)
#endif

        do {
            let snapshot = try await MKMapSnapshotter(options: options).start()
#if os(iOS)
            return snapshot.image.pngData()
#elseif os(macOS)
            guard
                let tiffData = snapshot.image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData)
            else { return nil }
            return bitmap.representation(using: .png, properties: [:])
#endif
        } catch {
            return nil
        }
    }
}

private struct RadarContactBlip: View {
    let contact: AirTrafficContact
    let showsCallsign: Bool

    var body: some View {
        VStack(spacing: -1) {
            Image(systemName: "airplane")
                .font(.system(size: 8, weight: .bold))
                .rotationEffect(.degrees((contact.trackDegrees ?? 90) - 90))
                .shadow(color: RadarPalette.glow, radius: 2)

            if showsCallsign {
                Text("\(contact.callsign) \(contact.movement.code)")
                    .font(.system(size: 5.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .padding(.horizontal, 1)
                    .background(RadarPalette.background.opacity(0.72))
            }
        }
        .foregroundStyle(RadarPalette.color(for: contact.movement))
    }
}

private struct RadarMovementBadge: View {
    let movement: AirTrafficMovement

    var body: some View {
        Text(movement.code)
            .font(.system(size: 5.5, weight: .bold, design: .monospaced))
            .foregroundStyle(RadarPalette.color(for: movement))
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(RadarPalette.color(for: movement).opacity(0.1))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(RadarPalette.color(for: movement).opacity(0.6), lineWidth: 0.5)
            }
    }
}

private struct RadarLocationMarker: View {
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .stroke(RadarPalette.secondary, lineWidth: 0.6)
                .frame(width: 4, height: 4)
            Text(label)
                .font(.system(size: 5, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(RadarPalette.secondary)
    }
}

private struct RadarEmptyLabel: View {
    var body: some View {
        Text("NO CONTACTS")
            .font(RadarType.micro)
            .tracking(0.8)
            .foregroundStyle(RadarPalette.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(RadarPalette.background.opacity(0.82))
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(RadarPalette.grid.opacity(0.7), lineWidth: 0.5)
            }
    }
}

private struct AirRadarUnavailableView: View {
    let date: Date

    var body: some View {
        ZStack {
            RadarPlot(
                contacts: [],
                scanDate: date,
                maxContacts: 0,
                showsLocationLabels: false,
                mapImageData: nil
            )
            .padding(13)
            .opacity(0.55)

            VStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.title3)
                Text("RADAR OFFLINE")
                    .font(RadarType.label)
                    .tracking(0.8)
                Text("Retrying next scan")
                    .font(RadarType.micro)
                    .foregroundStyle(RadarPalette.secondary)
            }
            .padding(8)
            .background(RadarPalette.background.opacity(0.86))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(RadarPalette.grid, lineWidth: 0.6)
            }
        }
        .padding(10)
    }
}

private struct RadarReferencePoint: Identifiable {
    let id: String
    let label: String
    let latitude: Double
    let longitude: Double

    static let helsinkiArea = [
        RadarReferencePoint(id: "efhk", label: "HEL", latitude: 60.3172, longitude: 24.9633),
        RadarReferencePoint(id: "helsinki", label: "HKI", latitude: 60.1699, longitude: 24.9384),
        RadarReferencePoint(id: "espoo", label: "ESP", latitude: 60.2055, longitude: 24.6559),
    ]
}

private enum RadarPalette {
    static let background = Color(red: 0.012, green: 0.045, blue: 0.034)
    static let primary = Color(red: 0.36, green: 1.0, blue: 0.63)
    static let secondary = Color(red: 0.31, green: 0.68, blue: 0.47)
    static let grid = Color(red: 0.18, green: 0.58, blue: 0.38)
    static let warning = Color(red: 1.0, green: 0.73, blue: 0.25)
    static let outbound = Color(red: 0.35, green: 0.86, blue: 1.0)
    static let cruise = Color(red: 1.0, green: 0.79, blue: 0.32)
    static let crossing = Color(red: 0.75, green: 0.56, blue: 1.0)
    static let glow = Color(red: 0.26, green: 1.0, blue: 0.58).opacity(0.7)

    static func color(for movement: AirTrafficMovement) -> Color {
        switch movement {
        case .inbound: primary
        case .outbound: outbound
        case .cruise: cruise
        case .crossing: crossing
        }
    }
}

private enum RadarType {
    static let compactTitle = Font.system(size: 9, weight: .bold, design: .monospaced)
    static let title = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let label = Font.system(size: 8, weight: .semibold, design: .monospaced)
    static let micro = Font.system(size: 6.5, weight: .medium, design: .monospaced)
}

private struct RadarWidgetBackground: View {
    var body: some View {
        ZStack {
            RadarPalette.background
            RadialGradient(
                colors: [RadarPalette.grid.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 150
            )
        }
    }
}

struct HelsinkiAirRadarWidget: Widget {
    let kind = "HelsinkiAirRadar"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HelsinkiAirRadarProvider()) { entry in
            HelsinkiAirRadarEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    RadarWidgetBackground()
                }
        }
        .configurationDisplayName("HEL Airspace Radar")
        .description("Shows a snapshot of airborne aircraft detected within 80 km of Helsinki Airport.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
