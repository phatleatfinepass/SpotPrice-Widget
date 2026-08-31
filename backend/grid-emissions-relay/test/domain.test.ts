import { describe, expect, it } from "vitest";
import {
  calculateBaseline,
  decodeFingridMeasurements,
  FINGRID_EMISSION_FIELD,
  makeRelayPayload,
  payloadWithCurrentStaleness,
} from "../src/domain";

describe("grid emissions domain", () => {
  it("decodes Fingrid's envelope and orders measurements", () => {
    const measurements = decodeFingridMeasurements({
      data: [
        row("2026-08-31T10:15:00Z", "2026-08-31T10:30:00Z", "30"),
        row("2026-08-31T10:00:00Z", "2026-08-31T10:15:00Z", 10),
      ],
    });

    expect(measurements.map((measurement) => measurement.value)).toEqual([10, 30]);
  });

  it("decodes Fingrid's production one-row-per-period field", () => {
    const measurements = decodeFingridMeasurements([
      {
        startTime: "2026-08-31T10:00:00Z",
        endTime: "2026-08-31T10:15:00Z",
        [FINGRID_EMISSION_FIELD]: 14,
      },
    ]);

    expect(measurements).toEqual([
      {
        startTime: "2026-08-31T10:00:00Z",
        endTime: "2026-08-31T10:15:00Z",
        value: 14,
      },
    ]);
  });

  it("classifies the latest value against a 30-day distribution", () => {
    const measurements = [
      measurement("2026-08-31T10:00:00Z", 10),
      measurement("2026-08-31T10:15:00Z", 20),
      measurement("2026-08-31T10:30:00Z", 30),
      measurement("2026-08-31T10:45:00Z", 40),
    ];
    const fetchedAt = new Date("2026-08-31T11:01:00Z");
    const baseline = calculateBaseline(measurements, fetchedAt);
    const payload = makeRelayPayload(measurements, baseline, fetchedAt);

    expect(payload.band).toBe("higher");
    expect(payload.lowerThreshold).toBe(20);
    expect(payload.upperThreshold).toBe(30);
    expect(payload.stale).toBe(false);
  });

  it("keeps a flat distribution neutral", () => {
    const measurements = [
      measurement("2026-08-31T10:00:00Z", 14),
      measurement("2026-08-31T10:15:00Z", 14),
      measurement("2026-08-31T10:30:00Z", 14),
    ];
    const fetchedAt = new Date("2026-08-31T10:46:00Z");
    const payload = makeRelayPayload(
      measurements,
      calculateBaseline(measurements, fetchedAt),
      fetchedAt,
    );

    expect(payload.band).toBe("typical");
  });

  it("marks a cached response stale as time advances", () => {
    const measurements = [measurement("2026-08-31T10:00:00Z", 12)];
    const fetchedAt = new Date("2026-08-31T10:16:00Z");
    const payload = makeRelayPayload(
      measurements,
      calculateBaseline(measurements, fetchedAt),
      fetchedAt,
    );

    expect(payloadWithCurrentStaleness(payload, new Date("2026-08-31T10:44:59Z")).stale).toBe(false);
    expect(payloadWithCurrentStaleness(payload, new Date("2026-08-31T10:45:00Z")).stale).toBe(true);
  });
});

function row(startTime: string, endTime: string, value: string | number): Record<string, unknown> {
  return { startTime, endTime, "396": value };
}

function measurement(startTime: string, value: number) {
  const start = new Date(startTime);
  return {
    startTime: start.toISOString(),
    endTime: new Date(start.getTime() + 15 * 60 * 1_000).toISOString(),
    value,
  };
}
