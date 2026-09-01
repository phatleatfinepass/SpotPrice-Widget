# Finland Electricity Rates 1.2.6

Version 1.2.6 fixes intermittent **Data unavailable** states in the Grid Conditions widget when a renewable-forecast slot changed before a still-current Fingrid CO₂ measurement expired.

The WidgetKit timeline now treats renewable-forecast transitions and live-emissions expiry as independent events. A forecast boundary can update the clean-energy outlook without discarding the valid emissions reading; the CO₂ value becomes stale only at its actual expiry time.

If the widget has an expired cached CO₂ measurement, it now labels it **Last reading**. **Data unavailable** is reserved for cases where no numeric emissions measurement exists.

This release also adds the project’s app, widget, icon, packaging, and transactional-update engineering playbook. It documents the verified direct-distribution architecture and the update handoff adopted in version 1.2.5.

Electricity-price presentation, forecast normalization, reset, uninstall, and automatic-update behavior are otherwise unchanged.

The release gate includes a regression that reproduces a forecast boundary occurring before emissions expiry, along with the existing product, updater, widget-registration, uninstall, relay, and Universal macOS packaging checks.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. A first installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature.
