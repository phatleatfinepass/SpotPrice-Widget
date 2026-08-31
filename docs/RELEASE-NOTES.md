# Finland Electricity Rates 1.2.0

This release adds native maintenance controls to the macOS host app. Software Update checks the fixed official GitHub repository, downloads the disk image and its published checksum, verifies SHA-256 integrity, and opens the verified installer without executing a remote shell script.

The new Danger Zone keeps destructive actions explicit. Reset Widget Data clears rebuildable host-app data and asks WidgetKit for fresh timelines. Uninstall now moves the exact running app to the Trash and closes it without a file picker or manual Finder step.

The app and widget remain sandboxed. A narrowly scoped embedded XPC service performs only the Trash operation. It accepts no filesystem path, derives the app from its own bundle location, and validates the caller’s user, signing identifier, and exact containing-app path before acting. The release gate launches a disposable signed copy and requires it to move itself to the current user’s Trash successfully.

Host and widget fallback caches remain isolated in their own sandboxes. The direct build no longer declares an App Group that ad-hoc signing cannot provide reliably. WidgetKit refreshes replace extension caches after a reset while retaining last-known data during an outage. The existing public Fingrid relay remains keyless for customers, and its credentials remain encrypted server-side rather than embedded in the app, installer, repository, logs, or public response.

The release includes the Electricity Rates and Grid Conditions widgets for macOS 26.5 or later. The Universal app supports Apple silicon and Intel Macs.

This is a free direct release. It is ad-hoc signed for bundle integrity but is not Apple-notarized and does not carry a paid Developer ID identity. On first launch, macOS may require approval in **System Settings → Privacy & Security → Open Anyway**. The app and installer never disable Gatekeeper or remove quarantine protection.

Download both release assets if you want to verify the disk image SHA-256 checksum before installation.
