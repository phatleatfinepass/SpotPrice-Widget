# Finland Electricity Rates 1.2.9

This update fixes a startup issue that could leave the desktop widgets blank after upgrading macOS. Opening Finland Electricity Rates now requests fresh widget content and preserves the registration macOS established for the app. Subsequent launches of the same build leave the running widget process alone.

A one-time process handoff keeps updates from older versions compatible without unregistering the app. The signed updater still replaces the complete app and retains rollback protection during an update.

On version 1.2.8, open **Finland Electricity Rates → Check for Updates…** and select **Install Update…**. Your existing widgets can stay on the desktop; there is no need to uninstall the app, remove the widgets, or reset their data.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. The Universal app and its embedded components are ad-hoc signed for integrity. The in-app updater verifies the project’s detached Ed25519 signature before installing the new version.
