# Finland Electricity Rates 1.2.8

Version 1.2.8 completes the **App Management** layout with three equal-width horizontal actions. **Check for Updates**, **Reset**, and **Uninstall** now share the same height, corner geometry, and baseline, with concise descriptions directly beneath the maintenance controls.

The release also fixes widgets that appeared unchanged after several successful app updates. macOS could keep the old widget-extension process alive after replacing the application bundle, so WidgetKit continued executing pre-update code from memory. The updater now stops only the exact extension embedded in Finland Electricity Rates before replacement, re-registers the new extension, and reloads both timelines.

A delayed, retryable first-launch handoff allows this repair to work when upgrading from 1.2.7, whose older helper may still be finishing the update transaction. The process match uses the complete canonical executable path and does not stop Debug builds or unrelated app copies.

The release gate covers exact-process lifecycle tests, product metadata, maintenance safeguards, updater trust and handoff, widget registration, uninstall target resolution, relay validation, signed Debug compilation, and Universal macOS packaging.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. A first installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature used by the in-app updater.
