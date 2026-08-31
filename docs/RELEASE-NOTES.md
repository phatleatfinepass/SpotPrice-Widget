# Finland Electricity Rates 1.2.2

Version 1.2.2 is the bridge to signed, transactional in-app updates. The app checks the fixed official GitHub repository, downloads the disk image and detached Ed25519 signature, and verifies that project signature before any installation work begins. A narrowly scoped maintenance service independently verifies the same signature, exact bundle identifier, newer version, and complete nested code-signature tree.

The new app is fully staged before the installed copy is moved aside. The previous version remains available as a rollback until 1.2.2 launches and stays open; a failed launch restores the previous version. The app never executes a downloaded shell script, disables Gatekeeper, removes quarantine, or accepts an arbitrary app or destination from the update request.

Installations on 1.2.1 or earlier still contain the previous installer-opening updater, so installing this bridge release requires the existing manual disk-image step once. After 1.2.2 is installed, later signed releases can use the automatic in-place flow.

There are no widget-design or data-source changes in this bridge. Electricity Rates, Grid Conditions, the public keyless Fingrid relay, reset, and uninstall behavior remain unchanged.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. First installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature.
