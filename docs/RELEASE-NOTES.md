# Finland Electricity Rates 1.2.7

Version 1.2.7 redesigns **App Management** as one compact horizontal surface. **Software Update** and **App Controls** now share a balanced 50/50 layout that is easier to scan without adding another section to the dashboard.

**Reset Data** and **Uninstall** sit side by side inside App Controls with a single subtle divider. Their previous nested danger-zone shell has been removed, while the existing confirmation dialogs, local-data reset behavior, recoverable Trash uninstall, and signed automatic-update flow remain unchanged.

The section uses native SwiftUI material, SF Symbols, standard bordered controls, and the system destructive role for uninstall. Update, reset, and uninstall actions also disable one another while work is in progress, preventing overlapping maintenance operations.

The release gate covers product metadata, maintenance safeguards, updater trust and handoff, widget registration, uninstall target resolution, relay validation, and Universal macOS packaging.

The release supports macOS 26.5 or later on Apple silicon and Intel Macs. It is a free direct release: the bundles are ad-hoc signed for integrity but are not Apple-notarized and do not carry a paid Developer ID identity. A first installation can still require **System Settings → Privacy & Security → Open Anyway**.

The release contains the disk image, its SHA-256 checksum, and the detached project update signature used by the in-app updater.
