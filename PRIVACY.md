# Privacy

Finland Electricity Rates is designed to work without an account, analytics, advertising, or a project-owned server.

## Data handled by the app

The app downloads public electricity-price and grid-condition data directly from the providers listed below. Normal network metadata, such as an IP address and request time, may be visible to those providers under their own privacy policies.

- [spot-hinta.fi](https://spot-hinta.fi/) for Finland spot prices
- [Energy-Charts](https://www.energy-charts.info/) for the renewable forecast signal
- [Fingrid Open Data](https://data.fingrid.fi/en/) for optional grid-emissions data

The app does not send personal data, widget usage, diagnostics, or analytics to the SpotPriceWidget project.

## On-device storage

Recent provider responses and presentation thresholds are cached in the app's local container so the widgets can continue showing the latest available information during a temporary outage. Removing the app and its container removes this cache.

The public release does not contain a Fingrid API credential. Developer builds may supply one locally through an unversioned build setting; the credential must never be committed to this repository.

## Tracking

The app does not track users across apps or websites and does not use advertising identifiers.

Questions can be submitted through the project's [support channel](SUPPORT.md).
