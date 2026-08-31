# Finland Electricity Rates 1.2.4

Version 1.2.4 introduces the full native macOS dashboard while preserving the glanceable Electricity Rates and Grid Conditions widgets.

The app now opens with a live overview of the current VAT-inclusive spot price and Fingrid emissions value, a proportional daily price-range gauge, and the best upcoming window that balances low price with renewable availability. The Electricity Prices card provides a working Today/Tomorrow selector, fully rounded hourly bars, negative-price support, and visible daily extrema. The hourly table adds renewable share and a concise recommendation for each available hour.

Grid Conditions now presents two distinct Apple Charts views instead of combining unrelated units on one normalized plot. **Forecast** shows renewable share for the next 24 hours as a percentage area-and-line chart. **History** shows measured grid emissions for the past 24 hours as gCO₂/kWh bars when direct historical data is available. Both views keep a fixed footprint so the dashboard does not jump or resize when data or selection changes.

The host app also resolves the public grid-emissions relay bundled with the widget, so the current Fingrid value remains available without exposing an API credential. Release builds do not fabricate emissions history when only the current public measurement is available.

The signed transactional updater remains unchanged. It verifies the detached Ed25519 signature, exact bundle identifier, newer version, and complete nested code-signature tree before replacing the installed app, with rollback retained until the new process remains alive.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. A first installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature.
