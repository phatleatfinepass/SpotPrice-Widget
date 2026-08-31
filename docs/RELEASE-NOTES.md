# Finland Electricity Rates 1.2.3

Version 1.2.3 is the first signed release intended to exercise the transactional in-app updater included in version 1.2.2. From the app, choose **Check for Updates**, then **Install Update…**. The app downloads the disk image and detached Ed25519 signature from the fixed official GitHub repository and verifies that project signature before installation begins.

The maintenance service independently verifies the signature, exact bundle identifier, newer semantic version, and complete nested code-signature tree. Version 1.2.3 is fully staged before the installed copy is moved aside. Version 1.2.2 remains available as a hidden rollback until 1.2.3 launches and stays open; a failed launch restores 1.2.2.

The updater never executes a downloaded shell script, disables Gatekeeper, removes quarantine, or accepts an arbitrary app or destination from the update request. Installations on 1.2.1 or earlier must install the 1.2.2 bridge manually before attempting this automatic upgrade.

There are no widget-design or data-source changes in this release. Electricity Rates, Grid Conditions, the public keyless Fingrid relay, reset, and uninstall behavior remain unchanged so the update test is isolated from product behavior.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. First installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature.
