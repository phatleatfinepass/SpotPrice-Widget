# Finland Electricity Rates 1.1.0

This release makes Grid Conditions work for every public installation without asking customers for a Fingrid API key. Current Finland grid emissions now come through a small read-only cache that refreshes from Fingrid every five minutes, preserves the latest valid measurement during short outages, and compares it with a rolling 30-day baseline.

The Fingrid credentials remain encrypted on the service and are never embedded in the app, installer, repository, logs, or public response. Release packaging rejects credential-bearing bundles and requires a fresh dataset 396 response before creating the disk image.

Grid Conditions also receives the normalized renewable outlook, correct Finland timestamps, and independent clean/high forecast periods. Current CO₂ readings no longer color future forecast slots. The installer retains the widget-gallery identity and product-icon cleanup introduced in 1.0.1.

The release includes the Electricity Rates and Grid Conditions widgets for macOS 26.5 or later. The Universal app supports Apple silicon and Intel Macs.

This is a free direct release. It is ad-hoc signed for bundle integrity but is not Apple-notarized and does not carry a paid Developer ID identity. On first launch, macOS may require approval in **System Settings → Privacy & Security → Open Anyway**. The app and installer never disable Gatekeeper or remove quarantine protection.

Download both release assets if you want to verify the disk image SHA-256 checksum before installation.
