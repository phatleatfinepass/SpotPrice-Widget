import Foundation

@main
struct GridConditionsSignalTests {
    static func main() {
        testWidgetDataResetClearsOnlyRebuildableCaches()
        testCurrentStateMatrix()
        testStaleAndMissingEmissionsSuppressGreen()
        testStaleForecastSuppressesForecastColors()
        testTimelineStateMatrix()
        testFutureHighRendersWithoutLiveEmissions()
        testForecastRunsCoalesceAcrossFutureSlots()
        testPartialCurrentSlotUsesWallClockContainment()
        testGapDoesNotTreatFallbackAsCurrent()
        testMeasurementCannotColorSuccessiveForecastSlots()
        testLowRenewableWarningRemainsForecastable()
        testStatusCopyUsesCombinedState()
        testEmissionsFreshnessBoundary()
        testFreshEmissionsCacheSurvivesTransientRateLimit()
        testRelayResponseDecoding()
        testRelayRejectsWrongDataset()
        testMonthHourBaselineUsesHelsinkiTime()
        testRenewableClassifierUsesBothGates()
        testDescendingHighForecastDoesNotFillHorizon()
        testFlatWindowSuppressesRelativeColor()
        testProviderWarningSurvivesFlatWindow()
        testPresentationIncludesFinalAvailableSlot()
        testPresentationRejectsExpiredFutureAndGappedCoverage()
        testFinlandClockUsesHelsinkiTime()
        testShortTimelineTicksKeepQuarterHoursDistinct()
        testTimelineStartsAtTheActualClock()
        testCurrentStateStopsAtForecastGap()
        testTimelineTicksStayUniqueAcrossDaylightSavingChange()
        testSpotPriceRejectsExpiredFutureAndGappedCoverage()
        print("Grid conditions signal tests passed.")
    }

    private static func testWidgetDataResetClearsOnlyRebuildableCaches() {
        let suite = "personal.SpotPriceWidget.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            expect(false, "Could not create isolated UserDefaults suites.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suite)
        }

        let cacheKeys = [
            WidgetDataStore.spotPriceCacheKey,
            WidgetDataStore.gridForecastCacheKey,
            WidgetDataStore.gridEmissionsCacheKey,
        ]
        for cacheKey in cacheKeys {
            defaults.set(Data([0x1]), forKey: cacheKey)
        }
        defaults.set("keep", forKey: "unrelated-preference")

        WidgetDataStore.resetCaches(defaults: defaults)

        for cacheKey in cacheKeys {
            expect(defaults.object(forKey: cacheKey) == nil, "Cache was not reset: \(cacheKey)")
        }
        expect(
            defaults.string(forKey: "unrelated-preference") == "keep",
            "Reset must not clear unrelated preferences."
        )
    }

    private static func testCurrentStateMatrix() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(GridSignalState, GridEmissionsBand, GridConditionVisualState?)] = [
            (.low, .cleaner, .lessClean),
            (.low, .typical, .lessClean),
            (.low, .higher, .lessClean),
            (.average, .cleaner, nil),
            (.average, .typical, nil),
            (.average, .higher, .lessClean),
            (.high, .cleaner, .clean),
            (.high, .typical, nil),
            (.high, .higher, .lessClean),
        ]

        for (renewable, emissions, expected) in cases {
            let actual = GridConditionsSignal.currentVisualState(
                renewableState: renewable,
                isForecastStale: false,
                emissionsBand: emissions,
                measuredAt: now,
                isEmissionsStale: false,
                at: now
            )
            expect(
                actual == expected,
                "Unexpected state for renewable=\(renewable), emissions=\(emissions): \(String(describing: actual))"
            )
        }
    }

    private static func testStaleAndMissingEmissionsSuppressGreen() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let stale = GridConditionsSignal.currentVisualState(
            renewableState: .high,
            isForecastStale: false,
            emissionsBand: .cleaner,
            measuredAt: now,
            isEmissionsStale: true,
            at: now
        )
        expect(stale == nil, "A stale Cleaner reading must not produce green.")

        let missing = GridConditionsSignal.currentVisualState(
            renewableState: .high,
            isForecastStale: false,
            emissionsBand: nil,
            measuredAt: nil,
            isEmissionsStale: true,
            at: now
        )
        expect(missing == nil, "Missing emissions must not produce green.")

        let expired = GridConditionsSignal.currentVisualState(
            renewableState: .high,
            isForecastStale: false,
            emissionsBand: .cleaner,
            measuredAt: now.addingTimeInterval(-31 * 60),
            isEmissionsStale: false,
            at: now
        )
        expect(expired == nil, "An expired Cleaner reading must not produce green.")
    }

    private static func testStaleForecastSuppressesForecastColors() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let current = GridConditionsSignal.currentVisualState(
            renewableState: .high,
            isForecastStale: true,
            emissionsBand: .cleaner,
            measuredAt: now,
            isEmissionsStale: false,
            at: now
        )
        expect(current == nil, "A stale High forecast must not produce green.")

        let runs = GridConditionsSignal.timelineRuns(
            forecastPoints: [point(at: now, state: .high)],
            isForecastStale: true,
            timelineStart: now,
            timelineEnd: now.addingTimeInterval(15 * 60)
        )
        expect(runs.isEmpty, "A stale renewable forecast must not render green runs.")

        let staleLowRuns = GridConditionsSignal.timelineRuns(
            forecastPoints: [point(at: now, state: .low)],
            isForecastStale: true,
            timelineStart: now,
            timelineEnd: now.addingTimeInterval(15 * 60)
        )
        expect(staleLowRuns.isEmpty, "A stale Low forecast must not render an outdated warning.")
    }

    private static func testTimelineStateMatrix() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let cases: [(GridSignalState, GridConditionVisualState?)] = [
            (.low, .lessClean),
            (.average, nil),
            (.high, .clean),
        ]

        for (renewable, expected) in cases {
            let runs = GridConditionsSignal.timelineRuns(
                forecastPoints: [point(at: start, state: renewable)],
                isForecastStale: false,
                timelineStart: start,
                timelineEnd: start.addingTimeInterval(15 * 60)
            )
            expect(
                runs.first?.state == expected,
                "Unexpected timeline state for renewable=\(renewable): \(String(describing: runs.first?.state))"
            )
            expect(
                runs.count == (expected == nil ? 0 : 1),
                "The timeline matrix must emit at most one current-slot run."
            )
        }
    }

    private static func testFutureHighRendersWithoutLiveEmissions() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let points = (0..<4).map { index in
            point(at: start.addingTimeInterval(Double(index) * 15 * 60), state: .high)
        }
        let runs = GridConditionsSignal.timelineRuns(
            forecastPoints: points,
            isForecastStale: false,
            timelineStart: start,
            timelineEnd: start.addingTimeInterval(60 * 60)
        )
        expect(runs.count == 1, "A decisive renewable opportunity should render without live emissions.")
        expect(runs.first?.state == .clean, "A High renewable forecast must render green.")
        expect(
            runs.first?.end == start.addingTimeInterval(60 * 60),
            "The renewable forecast should cover the full qualifying future run."
        )
    }

    private static func testForecastRunsCoalesceAcrossFutureSlots() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let points = (0..<4).map { index in
            point(at: start.addingTimeInterval(Double(index) * 15 * 60), state: .high)
        }
        let end = start.addingTimeInterval(60 * 60)

        let runs = GridConditionsSignal.timelineRuns(
            forecastPoints: points,
            isForecastStale: false,
            timelineStart: start,
            timelineEnd: end
        )
        expect(runs.count == 1, "Adjacent forecast slots should merge into one run.")
        expect(runs.first?.state == .clean, "A High renewable run must render green.")
        expect(
            runs.first?.end == end,
            "The timeline must preserve the complete qualifying forecast window."
        )
    }

    private static func testLowRenewableWarningRemainsForecastable() {
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let lowStart = start.addingTimeInterval(45 * 60)
        let runs = GridConditionsSignal.timelineRuns(
            forecastPoints: [point(at: lowStart, state: .low)],
            isForecastStale: false,
            timelineStart: start,
            timelineEnd: start.addingTimeInterval(60 * 60)
        )
        expect(runs.count == 1, "A Low renewable warning should remain visible without emissions data.")
        expect(runs.first?.state == .lessClean, "A Low renewable warning must render red.")
        expect(runs.first?.start == lowStart, "The warning must preserve its forecast start.")
    }

    private static func testPartialCurrentSlotUsesWallClockContainment() {
        let slotStart = Date(timeIntervalSince1970: 2_000_000_000)
        let now = slotStart.addingTimeInterval(13 * 60)
        let runs = GridConditionsSignal.timelineRuns(
            forecastPoints: [point(at: slotStart, state: .high)],
            isForecastStale: false,
            timelineStart: slotStart,
            timelineEnd: slotStart.addingTimeInterval(15 * 60)
        )
        expect(runs.first?.state == .clean, "A point containing the wall clock must be the current slot.")
        expect(
            GridConditionsSignal.currentForecastSlotEnd(
                in: [point(at: slotStart, state: .high)],
                at: now
            ) == slotStart.addingTimeInterval(15 * 60),
            "The safety boundary must be the containing slot's end."
        )
    }

    private static func testGapDoesNotTreatFallbackAsCurrent() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let past = point(at: now.addingTimeInterval(-30 * 60), state: .high)
        let future = point(at: now.addingTimeInterval(30 * 60), state: .high)

        for fallback in [past, future] {
            expect(
                GridConditionsSignal.currentForecastPoint(in: [fallback], at: now) == nil,
                "A past or future fallback must not be reported as current."
            )
        }

        let sentence = GridConditionsSignal.statusSentence(
            renewableState: nil,
            isForecastStale: false,
            isForecastUnavailable: false,
            emissionsBand: .cleaner,
            measuredAt: now,
            isEmissionsStale: false,
            at: now
        )
        expect(sentence == "Current grid signal unavailable.", "Missing current coverage must not claim a current combined state.")
    }

    private static func testEmissionsFreshnessBoundary() {
        let measuredAt = Date(timeIntervalSince1970: 2_000_000_000)
        expect(
            GridConditionsSignal.emissionsAreFresh(
                band: .cleaner,
                measuredAt: measuredAt,
                isStale: false,
                at: measuredAt.addingTimeInterval(30 * 60 - 1)
            ),
            "An emissions reading remains fresh immediately before its validity boundary."
        )
        expect(
            !GridConditionsSignal.emissionsAreFresh(
                band: .cleaner,
                measuredAt: measuredAt,
                isStale: false,
                at: measuredAt.addingTimeInterval(30 * 60)
            ),
            "An emissions reading must become visually stale at its expiry boundary."
        )
    }

    private static func testFreshEmissionsCacheSurvivesTransientRateLimit() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let payload = GridEmissionsCache.Payload(
            presentationValue: 10.5,
            presentationBand: .cleaner,
            measurementStart: now.addingTimeInterval(-30 * 60),
            measuredAt: now.addingTimeInterval(-15 * 60),
            lowerThreshold: 15,
            upperThreshold: 30,
            distributionFetchedAt: now.addingTimeInterval(-60 * 60),
            wasStaleWhenCached: false,
            cachedAt: now.addingTimeInterval(-60)
        )

        expect(
            GridEmissionsRepository.shouldUseCached(payload, at: now),
            "A recently cached, current Fingrid measurement should suppress a duplicate API call."
        )
        expect(
            !GridEmissionsRepository.presentation(from: payload, at: now).isStale,
            "A transient refresh failure must not hide a still-current cached measurement."
        )

        let expiredDate = now.addingTimeInterval(GridConditionsSignal.emissionsValidity)
        expect(
            !GridEmissionsRepository.shouldUseCached(payload, at: expiredDate),
            "An expired Fingrid measurement must trigger a refresh instead of remaining current."
        )
        expect(
            GridEmissionsRepository.presentation(from: payload, at: expiredDate).isStale,
            "An expired cached measurement must remain visually unavailable."
        )
    }

    private static func testRelayResponseDecoding() {
        let data = Data("""
        {
          "schemaVersion": 1,
          "datasetId": 396,
          "value": 14,
          "unit": "gCO2/kWh",
          "measurementStart": "2033-05-18T03:18:00.000Z",
          "measurementEnd": "2033-05-18T03:33:00.000Z",
          "band": "cleaner",
          "lowerThreshold": 20,
          "upperThreshold": 40,
          "baselineStart": "2033-04-18T03:18:00.000Z",
          "baselineEnd": "2033-05-18T03:33:00.000Z",
          "sourceFetchedAt": "2033-05-18T03:34:00.000Z",
          "stale": false,
          "source": "Fingrid Open Data",
          "sourceUrl": "https://data.fingrid.fi/en/datasets/396",
          "attribution": "Source Fingrid / data.fingrid.fi, license CC BY 4.0",
          "licenseUrl": "https://creativecommons.org/licenses/by/4.0/"
        }
        """.utf8)

        let result = try? GridEmissionsRelayClient.decodeCurrent(from: data)
        expect(result?.presentation.gramsCO2PerKWh == 14, "The public relay value must decode.")
        expect(result?.presentation.band == .cleaner, "The public relay band must decode.")
        expect(result?.presentation.isStale == false, "A fresh relay response must remain fresh.")
        expect(result?.lowerThreshold == 20, "The relay's baseline threshold must be retained.")
    }

    private static func testRelayRejectsWrongDataset() {
        let data = Data("""
        {
          "schemaVersion": 1,
          "datasetId": 1,
          "value": 14,
          "unit": "gCO2/kWh",
          "measurementStart": "2033-05-18T03:18:00Z",
          "measurementEnd": "2033-05-18T03:33:00Z",
          "band": "cleaner",
          "lowerThreshold": 20,
          "upperThreshold": 40,
          "baselineStart": "2033-04-18T03:18:00Z",
          "baselineEnd": "2033-05-18T03:33:00Z",
          "sourceFetchedAt": "2033-05-18T03:34:00Z",
          "stale": false,
          "source": "Fingrid Open Data",
          "sourceUrl": "https://data.fingrid.fi/en/datasets/396",
          "attribution": "Source Fingrid / data.fingrid.fi, license CC BY 4.0",
          "licenseUrl": "https://creativecommons.org/licenses/by/4.0/"
        }
        """.utf8)

        expect(
            (try? GridEmissionsRelayClient.decodeCurrent(from: data)) == nil,
            "The app must reject a relay response for any other dataset."
        )
    }

    private static func testMeasurementCannotColorSuccessiveForecastSlots() {
        let firstSlot = Date(timeIntervalSince1970: 2_000_000_000)
        let secondSlot = firstSlot.addingTimeInterval(15 * 60)
        let unchangedMeasurementStart = firstSlot
        let unchangedMeasurementEnd = secondSlot

        let secondGenerationBand = GridConditionsSignal.emissionsBandForCurrentForecastSlot(
            forecastPoints: [point(at: secondSlot, state: .high)],
            band: .cleaner,
            measurementStart: unchangedMeasurementStart,
            measuredAt: unchangedMeasurementEnd,
            isStale: false,
            at: secondSlot
        )
        expect(
            secondGenerationBand == nil,
            "The combined status must reject a measurement from the prior slot."
        )
        let secondGenerationSentence = GridConditionsSignal.statusSentence(
            renewableState: .high,
            isForecastStale: false,
            isForecastUnavailable: false,
            emissionsBand: secondGenerationBand,
            measuredAt: unchangedMeasurementEnd,
            isEmissionsStale: secondGenerationBand == nil,
            at: secondSlot
        )
        expect(
            secondGenerationSentence == "Grid conditions are mixed now.",
            "The following slot's status must not reuse the old measurement to claim clean electricity."
        )
    }

    private static func testStatusCopyUsesCombinedState() {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let typical = GridConditionsSignal.statusSentence(
            renewableState: .high,
            isForecastStale: false,
            isForecastUnavailable: false,
            emissionsBand: .typical,
            measuredAt: now,
            isEmissionsStale: false,
            at: now
        )
        expect(!typical.lowercased().contains("clean"), "Typical emissions must not claim clean electricity.")

        let higher = GridConditionsSignal.statusSentence(
            renewableState: .high,
            isForecastStale: false,
            isForecastUnavailable: false,
            emissionsBand: .higher,
            measuredAt: now,
            isEmissionsStale: false,
            at: now
        )
        expect(higher == "Electricity is less clean now.", "Higher emissions must use less-clean copy.")
    }

    private static func testMonthHourBaselineUsesHelsinkiTime() {
        let midnight = helsinkiDate(month: 8, day: 29, hour: 0)
        let afternoon = helsinkiDate(month: 8, day: 29, hour: 15)
        let midnightBand = FinlandRenewableSignal.thresholds(at: midnight)
        let afternoonBand = FinlandRenewableSignal.thresholds(at: afternoon)

        expect(midnightBand == GridSignalThresholds(lower: 42.4, upper: 50.0), "August midnight must use its month × hour band.")
        expect(afternoonBand == GridSignalThresholds(lower: 37.5, upper: 47.1), "August afternoon must use its month × hour band.")
    }

    private static func testRenewableClassifierUsesBothGates() {
        let start = helsinkiDate(month: 8, day: 29, hour: 0)
        let shares = Array(repeating: 20.0, count: 8)
            + Array(repeating: 48.0, count: 16)
            + Array(repeating: 90.0, count: 8)
        let classified = FinlandRenewableSignal.classify(
            points: forecastPoints(startingAt: start, shares: shares)
        )

        expect(classified.prefix(4).allSatisfy { $0.state == .low }, "Historically low values in the window's bottom quartile must form a red run.")
        expect(classified[24..<28].allSatisfy { $0.state == .high }, "Historically high values in the window's top quartile must form a green run.")
        expect(classified[10..<20].allSatisfy { $0.state == .average }, "Values without both gates must remain neutral.")

        var runLength = 0
        var runState = GridSignalState.average
        for point in classified + [signalPoint(at: classified.last!.dateTime.addingTimeInterval(15 * 60), state: .average)] {
            if point.state == runState {
                runLength += 1
            } else {
                if runState != .average {
                    expect(runLength >= 4, "Every renewable color run must persist for at least one hour.")
                }
                runState = point.state
                runLength = 1
            }
        }
    }

    private static func testDescendingHighForecastDoesNotFillHorizon() {
        let start = helsinkiDate(month: 8, day: 29, hour: 6)
        let pointCount = 73
        let shares = (0..<pointCount).map { index in
            84.2 - (33.2 * Double(index) / Double(pointCount - 1))
        }
        let points = forecastPoints(startingAt: start, shares: shares)
        expect(
            points.allSatisfy { point in
                point.renewableShare! > FinlandRenewableSignal.thresholds(at: point.dateTime).upper
            },
            "The live-like descending fixture must remain above every historical upper band."
        )

        let classified = FinlandRenewableSignal.classify(points: points)
        expect(classified.first?.state == .high, "The strongest opening values should form a green run.")
        expect(
            classified.dropLast(3).contains { $0.state == .average },
            "The relative-window gate must end green before the forecast horizon."
        )
    }

    private static func testFlatWindowSuppressesRelativeColor() {
        let start = helsinkiDate(month: 8, day: 29, hour: 0)
        let classified = FinlandRenewableSignal.classify(
            points: forecastPoints(
                startingAt: start,
                shares: Array(repeating: 80, count: 16)
            )
        )
        expect(classified.allSatisfy { $0.state == .average }, "A forecast window with IQR below 3 percentage points must stay blank.")
    }

    private static func testProviderWarningSurvivesFlatWindow() {
        let start = helsinkiDate(month: 8, day: 29, hour: 0)
        var points = forecastPoints(
            startingAt: start,
            shares: Array(repeating: 80, count: 16)
        )
        points[5] = GridForecastPoint(
            dateTime: points[5].dateTime,
            renewableShare: 80,
            signal: -1
        )
        let classified = FinlandRenewableSignal.classify(points: points)
        expect(classified[5].state == .low, "A provider congestion warning must remain red even in a flat window.")
        expect(classified.enumerated().allSatisfy { index, point in index == 5 || point.state == .average }, "Congestion must not color unrelated slots.")
    }

    private static func testPresentationIncludesFinalAvailableSlot() {
        let start = helsinkiDate(month: 8, day: 29, hour: 0)
        let points = forecastPoints(
            startingAt: start,
            shares: Array(repeating: 50, count: 8)
        )
        let presentation = GridForecastPresentation.make(
            points: points,
            at: start.addingTimeInterval(60),
            lastUpdated: start,
            // Legacy caches stored Energy-Charts' last-record start here.
            availableThrough: points.last!.dateTime,
            isStale: false
        )
        expect(presentation?.forecastPoints.count == points.count, "The final 15-minute record must not be dropped.")
        expect(
            presentation?.timelineEnd == points.last!.dateTime.addingTimeInterval(15 * 60),
            "The presentation coverage end must be exclusive of the final slot."
        )
    }

    private static func testPresentationRejectsExpiredFutureAndGappedCoverage() {
        let now = helsinkiDate(month: 8, day: 29, hour: 12)
        let expired = forecastPoints(
            startingAt: now.addingTimeInterval(-60 * 60),
            shares: Array(repeating: 50, count: 4)
        )
        let future = forecastPoints(
            startingAt: now.addingTimeInterval(15 * 60),
            shares: Array(repeating: 50, count: 4)
        )
        let gapped = [
            GridForecastPoint(
                dateTime: now.addingTimeInterval(-30 * 60),
                renewableShare: 50,
                signal: 1
            ),
            GridForecastPoint(
                dateTime: now.addingTimeInterval(30 * 60),
                renewableShare: 50,
                signal: 1
            ),
        ]

        for points in [expired, future, gapped] {
            let presentation = GridForecastPresentation.make(
                points: points,
                at: now,
                lastUpdated: now,
                availableThrough: points.last!.dateTime.addingTimeInterval(15 * 60),
                isStale: false
            )
            expect(presentation == nil, "Coverage that does not contain the wall clock must be unavailable.")
        }
    }

    private static func testFinlandClockUsesHelsinkiTime() {
        let apiTimestamp = ISO8601DateFormatter().date(
            from: "2026-08-30T00:45:00+03:00"
        )!
        expect(
            FinlandTime.clock(apiTimestamp) == "00:45",
            "A Finland API timestamp must remain on the Helsinki clock."
        )
    }

    private static func testShortTimelineTicksKeepQuarterHoursDistinct() {
        let start = helsinkiDate(month: 8, day: 30, hour: 0)
        let end = start.addingTimeInterval(60 * 60)
        let small = FinlandTime.timelineTicks(
            from: start,
            through: end,
            maximumCount: 3
        )
        let medium = FinlandTime.timelineTicks(
            from: start,
            through: end,
            maximumCount: 5
        )

        expect(
            small.dropFirst().map(FinlandTime.clock) == ["00:30", "01:00"],
            "A short small timeline must preserve its half-hour labels."
        )
        expect(
            medium.dropFirst().map(FinlandTime.clock)
                == ["00:15", "00:30", "00:45", "01:00"],
            "A short medium timeline must preserve all quarter-hour labels."
        )
    }

    private static func testTimelineStartsAtTheActualClock() {
        let slotStart = helsinkiDate(month: 8, day: 30, hour: 0)
        let now = slotStart.addingTimeInterval(7 * 60)
        let points = forecastPoints(
            startingAt: slotStart,
            shares: [45, 50, 55, 60, 65, 70, 75, 80]
        )
        let presentation = GridForecastPresentation.make(
            points: points,
            at: now,
            lastUpdated: now,
            availableThrough: points.last!.dateTime.addingTimeInterval(15 * 60),
            isStale: false
        )

        expect(
            presentation?.timelineStart == now,
            "The label Now must begin at the actual entry time, not the slot start."
        )
    }

    private static func testCurrentStateStopsAtForecastGap() {
        let slotStart = helsinkiDate(month: 8, day: 30, hour: 0)
        let now = slotStart.addingTimeInterval(5 * 60)
        let continuousPrefix = forecastPoints(
            startingAt: slotStart,
            shares: [45, 45, 45, 45]
        )
        let afterGap = forecastPoints(
            startingAt: slotStart.addingTimeInterval(2 * 60 * 60),
            shares: [45, 45, 45, 45]
        )
        let points = continuousPrefix + afterGap
        let presentation = GridForecastPresentation.make(
            points: points,
            at: now,
            lastUpdated: now,
            availableThrough: points.last!.dateTime.addingTimeInterval(15 * 60),
            isStale: false
        )

        expect(
            presentation?.stateEndsAt == slotStart.addingTimeInterval(60 * 60),
            "The current state must stop at a data gap even when the later state matches."
        )
    }

    private static func testTimelineTicksStayUniqueAcrossDaylightSavingChange() {
        let start = Calendar.helsinki.date(from: DateComponents(
            timeZone: FinlandTime.timeZone,
            year: 2026,
            month: 10,
            day: 25,
            hour: 0,
            minute: 30
        ))!
        let ticks = FinlandTime.timelineTicks(
            from: start,
            through: start.addingTimeInterval(4 * 60 * 60),
            maximumCount: 5
        )
        let labels = ticks.dropFirst().map(FinlandTime.clock)

        expect(
            Set(labels).count == labels.count,
            "The repeated autumn clock hour must not create duplicate axis labels."
        )
        expect(
            zip(ticks, ticks.dropFirst()).allSatisfy { pair in
                pair.0 < pair.1
            },
            "Timeline ticks must remain strictly ordered across a daylight-saving change."
        )
    }

    private static func testSpotPriceRejectsExpiredFutureAndGappedCoverage() {
        let now = helsinkiDate(month: 8, day: 30, hour: 12)
        let expired = spotPricePoints(
            startingAt: now.addingTimeInterval(-60 * 60),
            count: 4
        )
        let future = spotPricePoints(
            startingAt: now.addingTimeInterval(15 * 60),
            count: 4
        )
        let gapped = [
            SpotPricePoint(
                rank: 1,
                dateTime: now.addingTimeInterval(-30 * 60),
                priceNoTax: nil,
                priceWithTax: 0.01
            ),
            SpotPricePoint(
                rank: 2,
                dateTime: now.addingTimeInterval(30 * 60),
                priceNoTax: nil,
                priceWithTax: 0.02
            ),
        ]

        for points in [expired, future, gapped] {
            expect(
                SpotPricePresentation.make(
                    points: points,
                    at: now,
                    lastUpdated: now,
                    isStale: false
                ) == nil,
                "A rate schedule without the current slot must be unavailable."
            )
        }

        let currentAndGap = spotPricePoints(
            startingAt: now.addingTimeInterval(-5 * 60),
            count: 1
        ) + spotPricePoints(
            startingAt: now.addingTimeInterval(25 * 60),
            count: 1
        )
        let presentation = SpotPricePresentation.make(
            points: currentAndGap,
            at: now,
            lastUpdated: now,
            isStale: false
        )
        expect(
            presentation?.bandEndsAt == now.addingTimeInterval(10 * 60),
            "The current rate must stop at the end of its slot when the schedule has a gap."
        )
    }

    private static func point(
        at date: Date,
        state: GridSignalState
    ) -> GridForecastSignalPoint {
        signalPoint(at: date, state: state)
    }

    private static func signalPoint(
        at date: Date,
        state: GridSignalState
    ) -> GridForecastSignalPoint {
        GridForecastSignalPoint(
            dateTime: date,
            renewableShare: 50,
            smoothedRenewableShare: 50,
            state: state
        )
    }

    private static func forecastPoints(
        startingAt start: Date,
        shares: [Double]
    ) -> [GridForecastPoint] {
        shares.enumerated().map { index, share in
            GridForecastPoint(
                dateTime: start.addingTimeInterval(Double(index) * 15 * 60),
                renewableShare: share,
                signal: 1
            )
        }
    }

    private static func spotPricePoints(
        startingAt start: Date,
        count: Int
    ) -> [SpotPricePoint] {
        (0..<count).map { index in
            SpotPricePoint(
                rank: index + 1,
                dateTime: start.addingTimeInterval(Double(index) * 15 * 60),
                priceNoTax: nil,
                priceWithTax: 0.01
            )
        }
    }

    private static func helsinkiDate(month: Int, day: Int, hour: Int) -> Date {
        Calendar.helsinki.date(from: DateComponents(
            timeZone: TimeZone(identifier: "Europe/Helsinki"),
            year: 2026,
            month: month,
            day: day,
            hour: hour
        ))!
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else { fatalError(message) }
    }
}
