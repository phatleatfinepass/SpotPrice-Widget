export const DATASET_ID = 396;
export const DATASET_UNIT = "gCO2/kWh";
export const FINGRID_EMISSION_FIELD = "Emission factor for electricity consumed in Finland - updated every 15 minutes";
export const SOURCE_NAME = "Fingrid Open Data";
export const SOURCE_URL = "https://data.fingrid.fi/en/datasets/396";
export const SOURCE_ATTRIBUTION = "Source Fingrid / data.fingrid.fi, license CC BY 4.0";
export const SOURCE_LICENSE_URL = "https://creativecommons.org/licenses/by/4.0/";
export const EMISSIONS_VALIDITY_MS = 30 * 60 * 1_000;
export const FUTURE_TOLERANCE_MS = 5 * 60 * 1_000;

export type GridEmissionsBand = "cleaner" | "typical" | "higher";

export interface GridEmissionsMeasurement {
  startTime: string;
  endTime: string;
  value: number;
}

export interface GridEmissionsBaseline {
  schemaVersion: 1;
  lowerThreshold: number;
  upperThreshold: number;
  baselineStart: string;
  baselineEnd: string;
  calculatedAt: string;
}

export interface GridEmissionsRelayPayload {
  schemaVersion: 1;
  datasetId: typeof DATASET_ID;
  value: number;
  unit: typeof DATASET_UNIT;
  measurementStart: string;
  measurementEnd: string;
  band: GridEmissionsBand;
  lowerThreshold: number;
  upperThreshold: number;
  baselineStart: string;
  baselineEnd: string;
  sourceFetchedAt: string;
  stale: boolean;
  source: typeof SOURCE_NAME;
  sourceUrl: typeof SOURCE_URL;
  attribution: typeof SOURCE_ATTRIBUTION;
  licenseUrl: typeof SOURCE_LICENSE_URL;
}

export function decodeFingridMeasurements(input: unknown): GridEmissionsMeasurement[] {
  const rows = rowsFromEnvelope(input);
  const decoded = rows.flatMap((row): GridEmissionsMeasurement[] => {
    if (!isRecord(row)) return [];

    const startTime = stringValue(row.startTime);
    const endTime = stringValue(row.endTime);
    const value = emissionValue(row);
    if (
      startTime === undefined
      || endTime === undefined
      || value === undefined
      || !validDate(startTime)
      || !validDate(endTime)
      || Date.parse(endTime) <= Date.parse(startTime)
      || value < 0
      || value > 10_000
    ) {
      return [];
    }

    return [{ startTime, endTime, value }];
  });

  return decoded.sort((left, right) => Date.parse(left.startTime) - Date.parse(right.startTime));
}

export function calculateBaseline(
  measurements: GridEmissionsMeasurement[],
  calculatedAt: Date,
): GridEmissionsBaseline {
  if (measurements.length === 0) throw new Error("no_measurements");

  const values = measurements.map((measurement) => measurement.value).sort((a, b) => a - b);
  const lowerThreshold = percentile(0.33, values);
  const upperThreshold = percentile(0.67, values);
  const first = measurements[0];
  const last = measurements[measurements.length - 1];
  if (first === undefined || last === undefined) throw new Error("no_measurements");

  return {
    schemaVersion: 1,
    lowerThreshold,
    upperThreshold,
    baselineStart: first.startTime,
    baselineEnd: last.endTime,
    calculatedAt: calculatedAt.toISOString(),
  };
}

export function makeRelayPayload(
  measurements: GridEmissionsMeasurement[],
  baseline: GridEmissionsBaseline,
  fetchedAt: Date,
): GridEmissionsRelayPayload {
  const latest = measurements.at(-1);
  if (latest === undefined) throw new Error("no_measurements");

  return {
    schemaVersion: 1,
    datasetId: DATASET_ID,
    value: latest.value,
    unit: DATASET_UNIT,
    measurementStart: latest.startTime,
    measurementEnd: latest.endTime,
    band: emissionsBand(latest.value, baseline.lowerThreshold, baseline.upperThreshold),
    lowerThreshold: baseline.lowerThreshold,
    upperThreshold: baseline.upperThreshold,
    baselineStart: baseline.baselineStart,
    baselineEnd: baseline.baselineEnd,
    sourceFetchedAt: fetchedAt.toISOString(),
    stale: measurementIsStale(latest.endTime, fetchedAt),
    source: SOURCE_NAME,
    sourceUrl: SOURCE_URL,
    attribution: SOURCE_ATTRIBUTION,
    licenseUrl: SOURCE_LICENSE_URL,
  };
}

export function payloadWithCurrentStaleness(
  payload: GridEmissionsRelayPayload,
  date: Date,
): GridEmissionsRelayPayload {
  return {
    ...payload,
    stale: payload.stale || measurementIsStale(payload.measurementEnd, date),
  };
}

export function baselineIsCurrent(baseline: GridEmissionsBaseline, date: Date): boolean {
  if (!isBaseline(baseline)) return false;
  const age = date.getTime() - Date.parse(baseline.calculatedAt);
  return Number.isFinite(age) && age >= 0 && age < 24 * 60 * 60 * 1_000;
}

export function isBaseline(input: unknown): input is GridEmissionsBaseline {
  if (!isRecord(input)) return false;
  return input.schemaVersion === 1
    && finiteNumber(input.lowerThreshold)
    && finiteNumber(input.upperThreshold)
    && input.lowerThreshold <= input.upperThreshold
    && validDate(input.baselineStart)
    && validDate(input.baselineEnd)
    && Date.parse(input.baselineStart) < Date.parse(input.baselineEnd)
    && validDate(input.calculatedAt);
}

export function isRelayPayload(input: unknown): input is GridEmissionsRelayPayload {
  if (!isRecord(input)) return false;
  return input.schemaVersion === 1
    && input.datasetId === DATASET_ID
    && input.unit === DATASET_UNIT
    && finiteNumber(input.value)
    && input.value >= 0
    && input.value <= 10_000
    && validDate(input.measurementStart)
    && validDate(input.measurementEnd)
    && typeof input.band === "string"
    && ["cleaner", "typical", "higher"].includes(input.band)
    && finiteNumber(input.lowerThreshold)
    && finiteNumber(input.upperThreshold)
    && input.lowerThreshold <= input.upperThreshold
    && validDate(input.baselineStart)
    && validDate(input.baselineEnd)
    && validDate(input.sourceFetchedAt)
    && typeof input.stale === "boolean"
    && input.source === SOURCE_NAME
    && input.sourceUrl === SOURCE_URL
    && input.attribution === SOURCE_ATTRIBUTION
    && input.licenseUrl === SOURCE_LICENSE_URL;
}

function emissionsBand(value: number, lowerThreshold: number, upperThreshold: number): GridEmissionsBand {
  if (lowerThreshold >= upperThreshold) return "typical";
  if (value <= lowerThreshold) return "cleaner";
  if (value >= upperThreshold) return "higher";
  return "typical";
}

function measurementIsStale(measurementEnd: string, date: Date): boolean {
  const age = date.getTime() - Date.parse(measurementEnd);
  return !Number.isFinite(age) || age < -FUTURE_TOLERANCE_MS || age >= EMISSIONS_VALIDITY_MS;
}

function percentile(fraction: number, sortedValues: number[]): number {
  if (sortedValues.length === 0) throw new Error("no_measurements");
  const index = Math.round((sortedValues.length - 1) * fraction);
  const value = sortedValues[Math.min(Math.max(index, 0), sortedValues.length - 1)];
  if (value === undefined) throw new Error("no_measurements");
  return value;
}

function rowsFromEnvelope(input: unknown): unknown[] {
  if (Array.isArray(input)) return input;
  if (isRecord(input) && Array.isArray(input.data)) return input.data;
  throw new Error("invalid_fingrid_response");
}

function emissionValue(row: Record<string, unknown>): number | undefined {
  const direct = numberValue(row[FINGRID_EMISSION_FIELD])
    ?? numberValue(row[String(DATASET_ID)])
    ?? numberValue(row.value);
  if (direct !== undefined) return direct;

  if (Array.isArray(row.datasets)) {
    for (const item of row.datasets) {
      if (!isRecord(item)) continue;
      if (numberValue(item.datasetId) === DATASET_ID) return numberValue(item.value);
    }
  }

  return undefined;
}

function stringValue(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function numberValue(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }
  return undefined;
}

function finiteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function validDate(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
