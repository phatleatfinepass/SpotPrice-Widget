# Finland Electricity Rates 1.2.1

This is a minimal public patch release created to exercise Software Update from version 1.2.0. The app checks the fixed official GitHub repository, recognizes 1.2.1 as newer, downloads the disk image and its published checksum, verifies SHA-256 integrity, and opens the verified installer without executing a remote shell script.

There are no widget-design or data-source changes in this patch. The maintenance controls introduced in 1.2.0 are unchanged. Uninstall moves the exact running app bundle to the Trash and closes it, which is the standard removal model for a standalone macOS app.

The app and widget remain sandboxed. The narrowly scoped embedded XPC service accepts no filesystem path, derives the app from its own bundle location, and validates the caller’s user, signing identifier, and exact containing-app path before performing the Trash operation. The public Fingrid relay remains keyless for customers, and its credentials remain encrypted server-side rather than embedded in the app, installer, repository, logs, or public response.

The release includes the Electricity Rates and Grid Conditions widgets for macOS 26.5 or later. The Universal app supports Apple silicon and Intel Macs.

This is a free direct release. It is ad-hoc signed for bundle integrity but is not Apple-notarized and does not carry a paid Developer ID identity. On first launch, macOS may require approval in **System Settings → Privacy & Security → Open Anyway**. The app and installer never disable Gatekeeper or remove quarantine protection.

Download both release assets if you want to verify the disk image SHA-256 checksum before installation.
