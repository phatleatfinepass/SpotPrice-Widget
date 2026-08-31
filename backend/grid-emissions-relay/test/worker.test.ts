import { describe, expect, it, vi } from "vitest";
import {
  calculateBaseline,
  FINGRID_EMISSION_FIELD,
  makeRelayPayload,
} from "../src/domain";
import {
  Env,
  fetchFingridMeasurements,
  handleRequest,
  PublicResponseCache,
  refreshEmissions,
} from "../src/index";

describe("grid emissions relay", () => {
  it("serves only the fixed endpoint without query parameters", async () => {
    const cache = new MemoryKV();
    await seedCurrent(cache);
    const env = environment(cache);

    expect((await handleRequest(request("/v1/finland/emissions/current"), env, now())).status).toBe(200);
    expect((await handleRequest(request("/v1/finland/emissions/current?dataset=1"), env, now())).status).toBe(400);
    expect((await handleRequest(request("/v1/finland/emissions/history"), env, now())).status).toBe(404);
    expect((await handleRequest(request("/v1/finland/emissions/current", "POST"), env, now())).status).toBe(405);
  });

  it("returns 503 without triggering an upstream fetch on a cache miss", async () => {
    const response = await handleRequest(
      request("/v1/finland/emissions/current"),
      environment(new MemoryKV()),
      now(),
    );

    expect(response.status).toBe(503);
    expect(response.headers.get("Retry-After")).toBe("300");
  });

  it("serves a cached public response without another KV read", async () => {
    const kv = new MemoryKV();
    const edge = new MemoryResponseCache();
    await seedCurrent(kv);
    const env = environment(kv);

    const first = await handleRequest(request("/v1/finland/emissions/current"), env, now(), edge);
    expect(first.status).toBe(200);
    expect(kv.readCount).toBe(1);

    const second = await handleRequest(request("/v1/finland/emissions/current"), env, now(), edge);
    expect(second.status).toBe(200);
    expect(kv.readCount).toBe(1);
  });

  it("serves static health without reading KV", async () => {
    const kv = new MemoryKV();
    const response = await handleRequest(request("/health"), environment(kv), now());

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      ok: true,
      service: "finland-grid-emissions-relay",
    });
    expect(kv.readCount).toBe(0);
  });

  it("refreshes the baseline and current payload with one upstream request", async () => {
    const cache = new MemoryKV();
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(new Headers(init?.headers).get("x-api-key")).toBe("primary-test-key");
      return Response.json({
        data: [
          apiRow("2026-08-31T10:00:00Z", 12),
          apiRow("2026-08-31T10:15:00Z", 24),
          apiRow("2026-08-31T10:30:00Z", 36),
        ],
      });
    });
    vi.stubGlobal("fetch", fetchMock);

    await refreshEmissions(environment(cache), now());

    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(await cache.get("grid-emissions:baseline:v1", "json")).not.toBeNull();
    expect(await cache.get("grid-emissions:current:v1", "json")).toMatchObject({ value: 36 });
    vi.unstubAllGlobals();
  });

  it("uses the secondary credential only when the primary is unauthorized", async () => {
    const headers: string[] = [];
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      const apiKey = new Headers(init?.headers).get("x-api-key") ?? "";
      headers.push(apiKey);
      if (apiKey === "primary-test-key") return new Response(null, { status: 401 });
      return Response.json({ data: [apiRow("2026-08-31T10:30:00Z", 18)] });
    });

    const measurements = await fetchFingridMeasurements(
      now().getTime() - 60 * 60 * 1_000,
      now().getTime(),
      environment(new MemoryKV()),
      fetchMock as typeof fetch,
      async () => undefined,
    );

    expect(headers).toEqual(["primary-test-key", "secondary-test-key"]);
    expect(measurements.at(-1)?.value).toBe(18);
  });

  it("does not use the secondary credential to bypass rate limiting", async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 429 }));

    await expect(fetchFingridMeasurements(
      now().getTime() - 60 * 60 * 1_000,
      now().getTime(),
      environment(new MemoryKV()),
      fetchMock as typeof fetch,
      async () => undefined,
    )).rejects.toThrow("fingrid_http_429");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it("refuses redirects without forwarding the credential to another request", async () => {
    const fetchMock = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      expect(init?.redirect).toBe("manual");
      return new Response(null, {
        status: 302,
        headers: { Location: "https://attacker.example/collect" },
      });
    });

    await expect(fetchFingridMeasurements(
      now().getTime() - 60 * 60 * 1_000,
      now().getTime(),
      environment(new MemoryKV()),
      fetchMock as typeof fetch,
      async () => undefined,
    )).rejects.toThrow("fingrid_http_302");
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});

class MemoryKV {
  private readonly values = new Map<string, string>();
  readCount = 0;

  async get<T = string>(key: string, type?: "json"): Promise<T | string | null> {
    this.readCount += 1;
    const value = this.values.get(key);
    if (value === undefined) return null;
    return type === "json" ? JSON.parse(value) as T : value;
  }

  async put(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }
}

class MemoryResponseCache implements PublicResponseCache {
  private readonly values = new Map<string, Response>();

  async match(request: Request): Promise<Response | undefined> {
    return this.values.get(request.url)?.clone();
  }

  async put(request: Request, response: Response): Promise<void> {
    this.values.set(request.url, response.clone());
  }
}

function environment(cache: MemoryKV): Env {
  return {
    GRID_CACHE: cache as unknown as KVNamespace,
    FINGRID_API_KEY_PRIMARY: "primary-test-key",
    FINGRID_API_KEY_SECONDARY: "secondary-test-key",
  };
}

function request(path: string, method = "GET"): Request {
  return new Request(`https://relay.example${path}`, { method });
}

function now(): Date {
  return new Date("2026-08-31T10:46:00Z");
}

function apiRow(startTime: string, value: number): Record<string, unknown> {
  const start = new Date(startTime);
  return {
    startTime: start.toISOString(),
    endTime: new Date(start.getTime() + 15 * 60 * 1_000).toISOString(),
    [FINGRID_EMISSION_FIELD]: value,
  };
}

async function seedCurrent(cache: MemoryKV): Promise<void> {
  const measurements = [
    {
      startTime: "2026-08-31T10:30:00.000Z",
      endTime: "2026-08-31T10:45:00.000Z",
      value: 18,
    },
  ];
  const payload = makeRelayPayload(measurements, calculateBaseline(measurements, now()), now());
  await cache.put("grid-emissions:current:v1", JSON.stringify(payload));
}
