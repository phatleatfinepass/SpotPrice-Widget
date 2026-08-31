import {
  baselineIsCurrent,
  calculateBaseline,
  DATASET_ID,
  decodeFingridMeasurements,
  GridEmissionsBaseline,
  GridEmissionsMeasurement,
  GridEmissionsRelayPayload,
  isRelayPayload,
  makeRelayPayload,
  payloadWithCurrentStaleness,
} from "./domain";

const CURRENT_CACHE_KEY = "grid-emissions:current:v1";
const BASELINE_CACHE_KEY = "grid-emissions:baseline:v1";
const CURRENT_PATH = "/v1/finland/emissions/current";
const HEALTH_PATH = "/health";
const CURRENT_LOOKBACK_MS = 2 * 60 * 60 * 1_000;
const BASELINE_LOOKBACK_MS = 30 * 24 * 60 * 60 * 1_000;
const MINIMUM_REFRESH_MS = 4 * 60 * 1_000;

export interface Env {
  GRID_CACHE: KVNamespace;
  FINGRID_API_KEY_PRIMARY: string;
  FINGRID_API_KEY_SECONDARY: string;
}

export interface PublicResponseCache {
  match(request: Request): Promise<Response | undefined>;
  put(request: Request, response: Response): Promise<void>;
}

export default {
  async fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    return handleRequest(request, env, new Date(), caches.default, context);
  },

  async scheduled(
    _controller: ScheduledController,
    env: Env,
    context: ExecutionContext,
  ): Promise<void> {
    context.waitUntil(refreshEmissions(env, new Date()));
  },
} satisfies ExportedHandler<Env>;

export async function handleRequest(
  request: Request,
  env: Env,
  date: Date,
  publicCache?: PublicResponseCache,
  context?: Pick<ExecutionContext, "waitUntil">,
): Promise<Response> {
  const url = new URL(request.url);
  if (url.search !== "") return jsonError(400, "query_parameters_not_supported");
  if (request.method !== "GET" && request.method !== "HEAD") {
    return jsonError(405, "method_not_allowed", { Allow: "GET, HEAD" });
  }

  if (url.pathname === CURRENT_PATH) {
    const cacheKey = new Request(new URL(CURRENT_PATH, url.origin), { method: "GET" });
    const cachedResponse = await publicCache?.match(cacheKey);
    if (cachedResponse !== undefined) {
      return request.method === "HEAD" ? responseWithoutBody(cachedResponse) : cachedResponse;
    }

    const payload = await readCurrentPayload(env.GRID_CACHE);
    if (payload === null) {
      return jsonError(503, "data_not_ready", { "Retry-After": "300" });
    }
    const responsePayload = payloadWithCurrentStaleness(payload, date);
    const response = jsonResponse(responsePayload, request.method === "HEAD", {
      "Cache-Control": "public, max-age=60, s-maxage=120",
    });
    if (publicCache !== undefined) {
      const cacheWrite = publicCache.put(
        cacheKey,
        jsonResponse(responsePayload, false, {
          "Cache-Control": "public, max-age=60, s-maxage=120",
        }),
      );
      if (context !== undefined) {
        context.waitUntil(cacheWrite);
      } else {
        await cacheWrite;
      }
    }
    return response;
  }

  if (url.pathname === HEALTH_PATH) {
    return jsonResponse(
      { ok: true, service: "finland-grid-emissions-relay" },
      request.method === "HEAD",
      { "Cache-Control": "public, max-age=300" },
    );
  }

  return jsonError(404, "not_found");
}

export async function refreshEmissions(env: Env, date: Date): Promise<void> {
  const existing = await readCurrentPayload(env.GRID_CACHE);
  if (
    existing !== null
    && date.getTime() - Date.parse(existing.sourceFetchedAt) >= 0
    && date.getTime() - Date.parse(existing.sourceFetchedAt) < MINIMUM_REFRESH_MS
  ) {
    return;
  }

  const storedBaseline = await env.GRID_CACHE.get<GridEmissionsBaseline>(BASELINE_CACHE_KEY, "json");
  const shouldRebuildBaseline = storedBaseline === null || !baselineIsCurrent(storedBaseline, date);
  const lookback = shouldRebuildBaseline ? BASELINE_LOOKBACK_MS : CURRENT_LOOKBACK_MS;
  const measurements = await fetchFingridMeasurements(
    date.getTime() - lookback,
    date.getTime(),
    env,
  );
  const baseline = shouldRebuildBaseline
    ? calculateBaseline(measurements, date)
    : storedBaseline;
  const payload = makeRelayPayload(measurements, baseline, date);

  if (shouldRebuildBaseline) {
    await env.GRID_CACHE.put(BASELINE_CACHE_KEY, JSON.stringify(baseline));
  }
  await env.GRID_CACHE.put(CURRENT_CACHE_KEY, JSON.stringify(payload));
}

export async function fetchFingridMeasurements(
  startMilliseconds: number,
  endMilliseconds: number,
  env: Pick<Env, "FINGRID_API_KEY_PRIMARY" | "FINGRID_API_KEY_SECONDARY">,
  fetcher: typeof fetch = fetch,
  wait: (milliseconds: number) => Promise<void> = delay,
): Promise<GridEmissionsMeasurement[]> {
  const primaryKey = env.FINGRID_API_KEY_PRIMARY.trim();
  const secondaryKey = env.FINGRID_API_KEY_SECONDARY.trim();
  if (primaryKey === "") throw new Error("missing_primary_credential");
  if (secondaryKey === "") throw new Error("missing_secondary_credential");

  const primary = await requestFingrid(startMilliseconds, endMilliseconds, primaryKey, fetcher);
  let response = primary;
  if (
    (primary.status === 401 || primary.status === 403)
    && secondaryKey !== ""
  ) {
    await wait(2_100);
    response = await requestFingrid(
      startMilliseconds,
      endMilliseconds,
      secondaryKey,
      fetcher,
    );
  }

  if (!response.ok) throw new Error(`fingrid_http_${response.status}`);
  const responseBody: unknown = await response.json();
  const measurements = decodeFingridMeasurements(responseBody);
  if (measurements.length === 0) throw new Error("no_measurements");
  return measurements;
}

async function requestFingrid(
  startMilliseconds: number,
  endMilliseconds: number,
  apiKey: string,
  fetcher: typeof fetch,
): Promise<Response> {
  const url = new URL("https://data.fingrid.fi/api/data");
  url.searchParams.set("datasets", String(DATASET_ID));
  url.searchParams.set("startTime", new Date(startMilliseconds).toISOString());
  url.searchParams.set("endTime", new Date(endMilliseconds).toISOString());
  url.searchParams.set("format", "json");
  url.searchParams.set("oneRowPerTimePeriod", "true");
  url.searchParams.set("locale", "en");
  url.searchParams.set("pageSize", "5000");
  url.searchParams.set("sortBy", "startTime");
  url.searchParams.set("sortOrder", "asc");

  return fetcher(url, {
    headers: {
      Accept: "application/json",
      "x-api-key": apiKey,
    },
    redirect: "manual",
    signal: AbortSignal.timeout(15_000),
  });
}

async function readCurrentPayload(cache: KVNamespace): Promise<GridEmissionsRelayPayload | null> {
  const value = await cache.get<unknown>(CURRENT_CACHE_KEY, "json");
  return isRelayPayload(value) ? value : null;
}

function jsonResponse(
  body: unknown,
  headOnly: boolean,
  extraHeaders: Record<string, string> = {},
): Response {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Content-Security-Policy": "default-src 'none'",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  });
  return new Response(headOnly ? null : JSON.stringify(body), { status: 200, headers });
}

function jsonError(status: number, code: string, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify({ error: code }), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Content-Security-Policy": "default-src 'none'",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      ...extraHeaders,
    },
  });
}

function responseWithoutBody(response: Response): Response {
  return new Response(null, {
    status: response.status,
    statusText: response.statusText,
    headers: response.headers,
  });
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
