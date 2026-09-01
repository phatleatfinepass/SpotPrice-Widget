# Finland Electricity Rates 1.2.5

Version 1.2.5 fixes the automatic-update handoff and restores the WidgetKit provider when macOS retains an older or competing registration.

The updater now verifies and stages the complete signed replacement before asking the running app to quit. Its authenticated maintenance helper waits for that exact host process to exit, replaces the bundle transactionally, refreshes Launch Services and WidgetKit, launches one new app instance, and verifies both the new process and the installed widget path before removing the rollback copy. If replacement, registration, or launch fails, the previous app and widget registration are restored together.

The app also asks its narrowly scoped helper to refresh the exact containing app’s widget registration at launch. This lets 1.2.5 repair the widget gallery after an update initiated by the older 1.2.4 helper, without accepting an arbitrary app or filesystem path.

Because updater behavior executes from the version already installed, the one-time 1.2.4 → 1.2.5 bridge may still display the earlier close-and-relaunch sequence. Once 1.2.5 is installed, later signed updates use the corrected quit-before-replace flow.

Dashboard presentation, electricity-price thresholds, Fingrid emissions, renewable forecasts, reset, and uninstall behavior are unchanged.

The release gate now tests host-exit ordering and timeout behavior, PluginKit path parsing, launch-time registration repair through the real signed XPC boundary, the existing uninstall integration, and the complete macOS product build.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. A first installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature.
