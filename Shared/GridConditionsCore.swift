import Foundation

enum GridConditionVisualState: String, Hashable, Sendable {
    case clean
    case lessClean
}

struct GridConditionTimelineRun: Hashable, Identifiable, Sendable {
    let state: GridConditionVisualState
    let start: Date
    let end: Date

    var id: Date { start }
}

enum GridConditionsSignal {
    static let emissionsValidity: TimeInterval = 30 * 60

    private static let slotDuration: TimeInterval = 15 * 60
    private static let futureTimestampTolerance: TimeInterval = 5 * 60

    static func currentForecastPoint(
        in points: [GridForecastSignalPoint],
        at date: Date
    ) -> GridForecastSignalPoint? {
        points.last(where: {
            $0.dateTime <= date
                && date < $0.dateTime.addingTimeInterval(slotDuration)
        })
    }

    static func currentForecastSlotEnd(
        in points: [GridForecastSignalPoint],
        at date: Date
    ) -> Date? {
        currentForecastPoint(in: points, at: date)?
            .dateTime
            .addingTimeInterval(slotDuration)
    }

    static func emissionsAreFresh(
        band: GridEmissionsBand?,
        measuredAt: Date?,
        isStale: Bool,
        at date: Date
    ) -> Bool {
        freshEmissionsBand(
            band,
            measuredAt: measuredAt,
            isStale: isStale,
            at: date
        ) != nil
    }

    static func emissionsBandForCurrentForecastSlot(
        forecastPoints: [GridForecastSignalPoint],
        band: GridEmissionsBand?,
        measurementStart: Date?,
        measuredAt: Date?,
        isStale: Bool,
        at date: Date
    ) -> GridEmissionsBand? {
        guard
            let current = currentForecastPoint(in: forecastPoints, at: date),
            let measuredAt,
            let measurementStart,
            measurementStart < measuredAt,
            measurementStart < current.dateTime.addingTimeInterval(slotDuration),
            measuredAt > current.dateTime
        else { return nil }

        return freshEmissionsBand(
            band,
            measuredAt: measuredAt,
            isStale: isStale,
            at: date
        )
    }

    static func currentVisualState(
        renewableState: GridSignalState?,
        isForecastStale: Bool,
        emissionsBand: GridEmissionsBand?,
        measuredAt: Date?,
        isEmissionsStale: Bool,
        at date: Date
    ) -> GridConditionVisualState? {
        let emissionsBand = freshEmissionsBand(
            emissionsBand,
            measuredAt: measuredAt,
            isStale: isEmissionsStale,
            at: date
        )

        if emissionsBand == .higher {
            return .lessClean
        }
        guard !isForecastStale else { return nil }
        if renewableState == .low {
            return .lessClean
        }
        if renewableState == .high, emissionsBand == .cleaner {
            return .clean
        }
        return nil
    }

    static func timelineRuns(
        forecastPoints: [GridForecastSignalPoint],
        isForecastStale: Bool,
        timelineStart: Date,
        timelineEnd: Date
    ) -> [GridConditionTimelineRun] {
        guard !isForecastStale, timelineEnd > timelineStart else { return [] }

        var runs: [GridConditionTimelineRun] = []
        for point in forecastPoints {
            let slotStart = max(point.dateTime, timelineStart)
            let slotEnd = min(
                point.dateTime.addingTimeInterval(slotDuration),
                timelineEnd
            )
            guard slotEnd > slotStart else { continue }

            let visualState: GridConditionVisualState?
            switch point.state {
            case .high:
                visualState = .clean
            case .low:
                visualState = .lessClean
            case .average:
                visualState = nil
            }
            guard let visualState else { continue }

            append(
                GridConditionTimelineRun(
                    state: visualState,
                    start: slotStart,
                    end: slotEnd
                ),
                to: &runs
            )
        }
        return runs
    }

    static func statusSentence(
        renewableState: GridSignalState?,
        isForecastStale: Bool,
        isForecastUnavailable: Bool,
        emissionsBand: GridEmissionsBand?,
        measuredAt: Date?,
        isEmissionsStale: Bool,
        at date: Date
    ) -> String {
        guard !isForecastUnavailable else {
            return "Renewable forecast unavailable."
        }
        guard renewableState != nil else {
            return "Current grid signal unavailable."
        }

        switch currentVisualState(
            renewableState: renewableState,
            isForecastStale: isForecastStale,
            emissionsBand: emissionsBand,
            measuredAt: measuredAt,
            isEmissionsStale: isEmissionsStale,
            at: date
        ) {
        case .clean:
            return "Electricity is clean now."
        case .lessClean:
            return "Electricity is less clean now."
        case nil:
            return "Grid conditions are mixed now."
        }
    }

    private static func freshEmissionsBand(
        _ band: GridEmissionsBand?,
        measuredAt: Date?,
        isStale: Bool,
        at date: Date
    ) -> GridEmissionsBand? {
        guard !isStale, let band, let measuredAt else { return nil }
        let age = date.timeIntervalSince(measuredAt)
        guard
            age >= -futureTimestampTolerance,
            age < emissionsValidity
        else { return nil }
        return band
    }

    private static func append(
        _ run: GridConditionTimelineRun,
        to runs: inout [GridConditionTimelineRun]
    ) {
        if let previous = runs.last,
           previous.state == run.state,
           previous.end == run.start {
            runs[runs.count - 1] = GridConditionTimelineRun(
                state: previous.state,
                start: previous.start,
                end: run.end
            )
        } else {
            runs.append(run)
        }
    }
}
