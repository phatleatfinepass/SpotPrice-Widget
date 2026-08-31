# Privacy

Finland Electricity Rates is designed to work without an account, analytics, or advertising. A minimal project-owned relay caches Finland grid-emissions data so a shared Fingrid credential never ships inside the public app.

## Data handled by the app

The app downloads public electricity-price and grid-condition data directly from the providers listed below. Normal network metadata, such as an IP address and request time, may be visible to those providers under their own privacy policies.

- [spot-hinta.fi](https://spot-hinta.fi/) for Finland spot prices
- [Energy-Charts](https://www.energy-charts.info/) for the renewable forecast signal
- [Fingrid Open Data](https://data.fingrid.fi/en/) for grid-emissions data, fetched on a schedule by the project relay

The app requests only the relay’s fixed current-emissions endpoint. It does not send an account identifier, location, widget settings, diagnostics, or analytics. Cloudflare may process normal connection metadata such as an IP address and request time to deliver the response under its own privacy terms. SpotPriceWidget disables persistent Worker observability and does not add application-level request logging.

## On-device storage

Recent provider responses and presentation thresholds are cached in the app's local container so the widgets can continue showing the latest available information during a temporary outage. Removing the app and its container removes this cache.

The public release does not contain a Fingrid API credential. The relay stores its credential as an encrypted provider secret and exposes only normalized dataset 396 data with source attribution. A local Debug bundle may contain a separately supplied developer credential in plaintext; it must never be distributed, backed up, or committed to this repository.

## Tracking

The app does not track users across apps or websites and does not use advertising identifiers.

Questions can be submitted through the project's [support channel](SUPPORT.md).
