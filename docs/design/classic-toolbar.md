# Classic toolbar

## Research and design decision

The default layout follows familiar download-manager conventions: a labeled action toolbar, categories on the left, compact file rows and a status bar.

The icons are project-owned: authored vector shapes and system symbols. Add URL uses an authored paper stack and plus badge; resume, stop, delete, options, scheduler, queue and grabber use standard action metaphors. No third-party artwork is used.

## Appearance behavior

View offers Classic/Compact and Light/Dark/Follow System. Preferences persist for the normal installed app; isolated smoke/acceptance instances do not change them. Layer surfaces update when effective system appearance changes. Details follow the selected application appearance.

Actual AppKit smoke checks exercise both toolbar layouts, light/dark appearance, release of the system override, minimum window width and all eleven commands. End-to-end checks download a fixture, verify SHA-256, pause/resume through real toolbar handlers and check search selection and failed-job actions. Screenshots depict the actual app.

## Release scope

Current releases target macOS 13 or later and package Apple Silicon (`arm64`), Intel (`x86_64`) and Universal binaries. Deployment checks and executed runtime environments are recorded in [macOS compatibility](../macos-compatibility.md). Older macOS and 32-bit/PowerPC Macs are unsupported. Build targets do not establish tests on every Mac model or every macOS release.

CI separates bounded extension, fixture, core, package, UI, native-host and signature/proof stages on ARM/Intel macOS runners. The previous job's repeated fixture delays were caused by unnecessary reverse DNS in HTTPServer startup; fixtures now bind without reverse lookup, and a regression verifies real HTTP checks with DNS unavailable. Keychain was already passing and was not changed.

## Actual app screenshots

Screenshots depict the actual app running fixture transfers:

![Toolbar during verified downloads](../screenshots/app-downloads.png)
