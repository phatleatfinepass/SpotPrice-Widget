# Grid emissions relay

This Worker is the public, read-only cache for Fingrid dataset 396. It keeps the Fingrid credentials out of the app and limits upstream traffic to one scheduled refresh every five minutes.

The public surface is deliberately narrow:

- `GET /v1/finland/emissions/current` returns one normalized, attributed value.
- `GET /health` is a static liveness check and never reads KV.
- Requests cannot choose a dataset, time range, upstream URL, or header.
- A cache miss returns `503`; public traffic never triggers a Fingrid request.

The current response is cached at Cloudflare's edge before KV is read. The scheduled handler is the only path that contacts Fingrid, and credential-bearing requests reject redirects.

`FINGRID_API_KEY_PRIMARY` and `FINGRID_API_KEY_SECONDARY` are required encrypted Worker secrets. The secondary subscription key is used only when the primary is rejected with `401` or `403`; it is never used to bypass a `429` rate limit.

The KV namespace ID in the checked-in Wrangler configuration is a non-secret binding to the project’s production cache. Never put credentials in that file, `.dev.vars`, shell command arguments, documentation, or Git.

For local verification:

```bash
npm ci --ignore-scripts
npm run check
```

Maintainers create the production KV namespace, replace the placeholder namespace ID, and set both Fingrid keys through Wrangler's hidden interactive prompt. Provider setup and deployment follow the repository's project-scoped Cloudflare workflow. After deployment, verify both public routes and configure an account-level rate limit for abusive traffic.
