import Foundation
import OSLog

struct AirTrafficRegion: Hashable, Sendable {
    let centerLatitude: Double
    let centerLongitude: Double
    let radiusKm: Double

    nonisolated static let helsinki = AirTrafficRegion(
        centerLatitude: 60.3172,
        centerLongitude: 24.9633,
        radiusKm: 80
    )

    var minimumLatitude: Double {
        centerLatitude - radiusKm / 111.32
    }

    var maximumLatitude: Double {
        centerLatitude + radiusKm / 111.32
    }

    var minimumLongitude: Double {
        centerLongitude - radiusKm / longitudeKilometersPerDegree
    }

    var maximumLongitude: Double {
        centerLongitude + radiusKm / longitudeKilometersPerDegree
    }

    func distanceKm(latitude: Double, longitude: Double) -> Double {
        let earthRadiusKm = 6_371.0
        let latitudeDelta = (latitude - centerLatitude).degreesToRadians
        let longitudeDelta = (longitude - centerLongitude).degreesToRadians
        let originLatitude = centerLatitude.degreesToRadians
        let destinationLatitude = latitude.degreesToRadians
        let haversine = pow(sin(latitudeDelta / 2), 2)
            + cos(originLatitude) * cos(destinationLatitude) * pow(sin(longitudeDelta / 2), 2)
        return earthRadiusKm * 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
    }

    func normalizedPosition(latitude: Double, longitude: Double) -> AirTrafficVector {
        let eastKm = (longitude - centerLongitude) * longitudeKilometersPerDegree
        let northKm = (latitude - centerLatitude) * 111.32
        return AirTrafficVector(
            x: eastKm / radiusKm,
            y: northKm / radiusKm
        )
    }

    func bearingDegrees(latitude: Double, longitude: Double) -> Double {
        let originLatitude = centerLatitude.degreesToRadians
        let destinationLatitude = latitude.degreesToRadians
        let longitudeDelta = (longitude - centerLongitude).degreesToRadians
        let y = sin(longitudeDelta) * cos(destinationLatitude)
        let x = cos(originLatitude) * sin(destinationLatitude)
            - sin(originLatitude) * cos(destinationLatitude) * cos(longitudeDelta)
        return atan2(y, x).radiansToDegrees.normalizedBearing
    }

    private var longitudeKilometersPerDegree: Double {
        111.32 * cos(centerLatitude.degreesToRadians)
    }
}

struct AirTrafficVector: Hashable, Sendable {
    let x: Double
    let y: Double
}

enum AirTrafficMovement: String, Codable, Hashable, Sendable {
    case inbound
    case outbound
    case cruise
    case crossing

    var code: String {
        switch self {
        case .inbound: "IN"
        case .outbound: "OUT"
        case .cruise: "CRZ"
        case .crossing: "XING"
        }
    }

    var title: String {
        switch self {
        case .inbound: "Inbound"
        case .outbound: "Outbound"
        case .cruise: "Cruising"
        case .crossing: "Crossing"
        }
    }
}

struct AirTrafficContact: Codable, Hashable, Identifiable, Sendable {
    let icao24: String
    let callsign: String
    let originCountry: String
    let latitude: Double
    let longitude: Double
    let altitudeMeters: Double?
    let velocityMetersPerSecond: Double?
    let trackDegrees: Double?
    let verticalRateMetersPerSecond: Double?
    let lastPosition: Date
    let distanceKm: Double

    var id: String { icao24 }

    var altitudeFeet: Int? {
        altitudeMeters.map { Int(($0 * 3.28084).rounded()) }
    }

    var altitudeLabel: String {
        guard let altitudeFeet else { return "ALT —" }
        if altitudeFeet >= 10_000 {
            return "FL\(Int((Double(altitudeFeet) / 100).rounded()))"
        }
        return "\(altitudeFeet.formatted(.number.grouping(.never))) FT"
    }

    var speedKnots: Int? {
        velocityMetersPerSecond.map { Int(($0 * 1.94384).rounded()) }
    }

    var movement: AirTrafficMovement {
        let region = AirTrafficRegion.helsinki
        let verticalRate = verticalRateMetersPerSecond ?? 0
        let isClimbing = verticalRate >= 1
        let isDescending = verticalRate <= -1
        let isHighAndLevel = (altitudeFeet ?? 0) >= 18_000 && abs(verticalRate) < 2.5
        let isTerminalAltitude = (altitudeFeet ?? 0) < 18_000

        guard let trackDegrees else {
            if isHighAndLevel { return .cruise }
            if isTerminalAltitude && isDescending { return .inbound }
            if isTerminalAltitude && isClimbing { return .outbound }
            return .crossing
        }

        let outwardBearing = region.bearingDegrees(latitude: latitude, longitude: longitude)
        let inwardBearing = (outwardBearing + 180).normalizedBearing
        let outwardAlignment = trackDegrees.angularDistance(to: outwardBearing)
        let inwardAlignment = trackDegrees.angularDistance(to: inwardBearing)
        let isRadiallyOutbound = outwardAlignment <= 55
        let isRadiallyInbound = inwardAlignment <= 55

        if isTerminalAltitude && distanceKm <= 60 {
            if isRadiallyInbound || isDescending { return .inbound }
            if isRadiallyOutbound || isClimbing { return .outbound }
        }
        if isHighAndLevel { return .cruise }
        if isRadiallyInbound { return .inbound }
        if isRadiallyOutbound { return .outbound }
        return .crossing
    }

    var compactDetail: String {
        let distance = "\(Int(distanceKm.rounded())) KM"
        guard let speedKnots else { return "\(altitudeLabel) · \(distance)" }
        return "\(altitudeLabel) · \(speedKnots) KT · \(distance)"
    }
}

struct AirTrafficSnapshot: Codable, Hashable, Sendable {
    let contacts: [AirTrafficContact]
    let fetchedAt: Date
    let isStale: Bool
    let isUnavailable: Bool

    static func sample(at date: Date = Date()) -> AirTrafficSnapshot {
        let samples = [
            ("FIN7LP", "461f9a", 60.52, 24.72, 2_950.0, 145.0, 136.0, -4.2),
            ("SAS732", "4ac9e2", 60.17, 25.22, 1_620.0, 118.0, 314.0, -3.1),
            ("RYR6NV", "4ca923", 60.73, 25.04, 7_840.0, 226.0, 192.0, -1.0),
            ("FIN3AF", "461e17", 60.34, 24.18, 4_580.0, 174.0, 258.0, 4.0),
            ("NAX2PC", "47875b", 59.94, 24.61, 9_120.0, 241.0, 42.0, 0.1),
            ("DLH4YH", "3c66a8", 60.10, 25.74, 10_360.0, 251.0, 286.0, -0.4),
            ("KLM71V", "4841aa", 60.84, 24.35, 8_430.0, 238.0, 165.0, -2.0),
        ]

        let region = AirTrafficRegion.helsinki
        let contacts = samples.map { sample in
            AirTrafficContact(
                icao24: sample.1,
                callsign: sample.0,
                originCountry: "",
                latitude: sample.2,
                longitude: sample.3,
                altitudeMeters: sample.4,
                velocityMetersPerSecond: sample.5,
                trackDegrees: sample.6,
                verticalRateMetersPerSecond: sample.7,
                lastPosition: date,
                distanceKm: region.distanceKm(latitude: sample.2, longitude: sample.3)
            )
        }
        .sorted { $0.distanceKm < $1.distanceKm }

        return AirTrafficSnapshot(
            contacts: contacts,
            fetchedAt: date,
            isStale: false,
            isUnavailable: false
        )
    }

    static func unavailable(at date: Date = Date()) -> AirTrafficSnapshot {
        AirTrafficSnapshot(
            contacts: [],
            fetchedAt: date,
            isStale: true,
            isUnavailable: true
        )
    }
}

enum OpenSkyAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "The OpenSky air-traffic URL is invalid."
        case .invalidResponse: "OpenSky returned an invalid air-traffic response."
        case let .httpStatus(status): "OpenSky returned HTTP \(status)."
        }
    }
}

struct OpenSkyAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchContacts(
        in region: AirTrafficRegion = .helsinki,
        at currentDate: Date = Date()
    ) async throws -> AirTrafficSnapshot {
        var components = URLComponents(string: "https://opensky-network.org/api/states/all")
        components?.queryItems = [
            URLQueryItem(name: "lamin", value: String(region.minimumLatitude)),
            URLQueryItem(name: "lomin", value: String(region.minimumLongitude)),
            URLQueryItem(name: "lamax", value: String(region.maximumLatitude)),
            URLQueryItem(name: "lomax", value: String(region.maximumLongitude)),
            URLQueryItem(name: "extended", value: "1"),
        ]
        guard let url = components?.url else { throw OpenSkyAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SpotPriceWidget/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw OpenSkyAPIError.invalidResponse
        }
        guard (200..<300).contains(response.statusCode) else {
            throw OpenSkyAPIError.httpStatus(response.statusCode)
        }

        return try Self.decodeSnapshot(from: data, region: region, currentDate: currentDate)
    }

    static func decodeSnapshot(
        from data: Data,
        region: AirTrafficRegion = .helsinki,
        currentDate: Date = Date()
    ) throws -> AirTrafficSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw OpenSkyAPIError.invalidResponse
        }

        let rawStates: [[Any]]
        if let states = root["states"] as? [[Any]] {
            rawStates = states
        } else if root["states"] is NSNull {
            rawStates = []
        } else {
            throw OpenSkyAPIError.invalidResponse
        }

        let responseDate = number(root["time"])
            .map { Date(timeIntervalSince1970: $0) }
            ?? currentDate
        let freshnessCutoff = currentDate.addingTimeInterval(-2 * 60)

        let contacts = rawStates.compactMap { state -> AirTrafficContact? in
            guard
                let icao24 = string(state, at: 0),
                let longitude = number(state, at: 5),
                let latitude = number(state, at: 6),
                boolean(state, at: 8) != true
            else { return nil }

            let lastPosition = number(state, at: 3)
                .map { Date(timeIntervalSince1970: $0) }
                ?? responseDate
            guard lastPosition >= freshnessCutoff else { return nil }

            let distanceKm = region.distanceKm(latitude: latitude, longitude: longitude)
            guard distanceKm <= region.radiusKm else { return nil }

            let rawCallsign = string(state, at: 1)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let callsign = rawCallsign.flatMap { $0.isEmpty ? nil : $0 }
                ?? icao24.uppercased()

            return AirTrafficContact(
                icao24: icao24,
                callsign: callsign,
                originCountry: string(state, at: 2) ?? "",
                latitude: latitude,
                longitude: longitude,
                altitudeMeters: number(state, at: 13) ?? number(state, at: 7),
                velocityMetersPerSecond: number(state, at: 9),
                trackDegrees: number(state, at: 10),
                verticalRateMetersPerSecond: number(state, at: 11),
                lastPosition: lastPosition,
                distanceKm: distanceKm
            )
        }
        .sorted { lhs, rhs in
            if lhs.distanceKm == rhs.distanceKm { return lhs.callsign < rhs.callsign }
            return lhs.distanceKm < rhs.distanceKm
        }

        return AirTrafficSnapshot(
            contacts: contacts,
            fetchedAt: responseDate,
            isStale: false,
            isUnavailable: false
        )
    }

    private static func value(_ state: [Any], at index: Int) -> Any? {
        guard state.indices.contains(index), !(state[index] is NSNull) else { return nil }
        return state[index]
    }

    private static func string(_ state: [Any], at index: Int) -> String? {
        value(state, at: index) as? String
    }

    private static func number(_ state: [Any], at index: Int) -> Double? {
        number(value(state, at: index))
    }

    private static func boolean(_ state: [Any], at index: Int) -> Bool? {
        value(state, at: index) as? Bool
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

struct AirTrafficRepository {
    private static let logger = Logger(
        subsystem: "personal.SpotPriceWidget",
        category: "AirTraffic"
    )

    private let client: OpenSkyAPIClient
    private let cache: AirTrafficCache
    private let now: () -> Date

    init(
        client: OpenSkyAPIClient = OpenSkyAPIClient(),
        cache: AirTrafficCache = AirTrafficCache(),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.cache = cache
        self.now = now
    }

    func load() async -> AirTrafficSnapshot {
        let currentDate = now()

        do {
            let snapshot = try await client.fetchContacts(at: currentDate)
            cache.save(snapshot)
            return snapshot
        } catch {
            Self.logger.error("Air-traffic refresh failed: \(error.localizedDescription, privacy: .public)")
            if let cached = cache.load(), currentDate.timeIntervalSince(cached.fetchedAt) <= 2 * 60 * 60 {
                return AirTrafficSnapshot(
                    contacts: cached.contacts,
                    fetchedAt: cached.fetchedAt,
                    isStale: true,
                    isUnavailable: false
                )
            }
            return .unavailable(at: currentDate)
        }
    }
}

struct AirTrafficCache {
    private let defaults: UserDefaults
    private let key = "helsinki-air-traffic-cache-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AirTrafficSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(AirTrafficSnapshot.self, from: data)
    }

    func save(_ snapshot: AirTrafficSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }
}

private extension Double {
    var degreesToRadians: Double { self * .pi / 180 }
    var radiansToDegrees: Double { self * 180 / .pi }

    var normalizedBearing: Double {
        let value = truncatingRemainder(dividingBy: 360)
        return value >= 0 ? value : value + 360
    }

    func angularDistance(to other: Double) -> Double {
        let difference = abs(normalizedBearing - other.normalizedBearing)
        return min(difference, 360 - difference)
    }
}
