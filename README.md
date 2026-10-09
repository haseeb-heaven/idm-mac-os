# MacDownloadManager

**An independent, open-source download manager for macOS.** Inspired by the classic Internet Download Manager workflow (segmented downloads, queue, scheduler, browser handoff) — no affiliation with Tonec, and no reverse-engineered code.

Swift 6 · AppKit · URLSession · SQLite · Keychain · macOS 13+ · Apple Silicon / Intel / Universal

## Credits

Workflow inspired by the original Internet Download Manager by Tonec FZE — https://www.internetdownloadmanager.com/. If you use Windows, please buy the official IDM license to support the original team. This project shares no code, artwork, or binaries with it.

## Download v0.3.0

[Get the latest release](https://github.com/haseeb-heaven/mac-download-manager/releases/latest): choose Apple Silicon (`arm64`), Intel (`x86_64`), or Universal for the app, plus `MDM-Extension` zips for Chromium browsers (Chrome, Edge, Brave) and Firefox. Extract the app ZIP and move **MacDownloadManager.app** to Applications. Packages are ad hoc signed and are not notarized; macOS may require approval in System Settings → Privacy & Security. Check the included `SHA256SUMS` before installation.

If you used a previous release under the old name, delete the old app, re-register browsers from the new app's Browser Integrations menu, and re-enable capture in the extension popup. Downloads, Keychain items, and extension IDs from the old identity are not migrated.

![MacDownloadManager downloads](docs/screenshots/app-downloads.png)

See [architecture](docs/architecture.md), [macOS compatibility](docs/macos-compatibility.md), and [release notes](docs/release-notes-v0.3.0.md).

## Build and run

```sh
git clone git@github.com:haseeb-heaven/mac-download-manager.git
cd mac-download-manager
scripts/package.sh
open "build/MacDownloadManager.app"
```

Requirements: Apple Silicon or Intel Mac, macOS 13+, Swift 6 Command Line Tools, and Python 3.12 for fixtures/build resources, and Node.js 22 for extension checks. The Swift package has no external dependencies. A full Xcode installation is unnecessary. `scripts/swift.sh` handles the inconsistent SwiftPM interfaces on the development Mac using a project-local public-interface copy.

For personal installation and native host registration, run `scripts/install.sh`; it installs to `~/Applications/MacDownloadManager.app`. Browser extensions must then be loaded using the included setup instructions.

The release bundle is locally ad hoc signed. App data is stored in `~/Library/Application Support/MacDownloadManager/`; credentials are stored in Keychain.

## Features

- Manual HTTP/HTTPS and batch downloads with validated concurrent byte ranges.
- Partial-file pause/resume, response validators, retries, redirects, and safe final assembly.
- SQLite persistence and recovery after restart; Keychain Basic authentication.
- Proxy settings, aggregate rate limits, FIFO queue, and per-job scheduled start times.
- 5 selectable themes with **Classic IDM enabled by default**, plus Modern Light, Modern Dark, Midnight Blue, Nordic Emerald, and Follow System.
- Colored toolbar with labeled actions; optional compact layout, searchable downloads and live details.
- Single-page file-link grabber with deduplication and review before downloading.
- Chromium and Firefox extensions: link/context-menu handoff, batches, direct media selection, optional cookies and automatic capture.
- Streaming imports from live browser Blob URLs; Safari/other-browser HTTP bookmarklet handoff.

Dynamic segmentation, advanced recurring schedules, multiple named queues, recursive grabbing, FTP, and OS-specific browser integrations beyond Chromium/Firefox remain unsupported or unverified. Speed measurements apply to the recorded environment and files only.

## Verify

```sh
# Core checks, release packaging, and actual native toolbar/queue end-to-end checks:
scripts/test.sh

# Instrumented core/UI coverage and browsable uncovered lines:
scripts/coverage.sh

# Opt-in complete downloads with independent curl SHA-256 references:
python3 scripts/real_download_checks.py

# Opt-in 5 GiB acceptance test; removes the generated file afterward:
scripts/swift.sh run --disable-sandbox -c release DownloadCoreChecks --large
```

The executable test runner is used because this Mac's Command Line Tools do not provide XCTest. It exercises real HTTP requests, file IO, SQLite, Keychain, restart behavior, and AppKit controls. Test failures return nonzero exit status. Measured coverage and its gaps are published with the results.

## Troubleshooting

Select a failed job for the full error and retry controls. Browser-verification pages can reject standalone clients. Signed download URLs can expire; use a stable publisher/release URL to obtain a fresh redirect. A `blob:` URL identifies data in its originating browser environment: use the included extension in that live tab to import an ordinary Blob, or supply an HTTP/HTTPS source URL. Expired Blob URLs, MediaSource streams and DRM cannot be recovered from a pasted URL.

## Repository layout

```text
Sources/DownloadCore/       Native transfer, persistence, credentials, queue, and grabber
Sources/MacDownloadManager/ AppKit application, bridge and interface
Sources/MacDownloadManagerHost/ Swift native-messaging executable
resources/                  Project-owned icon generator output
integrations/               Independently authored browser extensions and bookmarklet
Tests/DownloadCoreTests/    Executable functional/integration checks
scripts/                    Build, test, coverage, and release tooling
docs/                       Architecture, coverage, screenshots, and limits
```

[AGENTS.md](AGENTS.md) defines the development, testing, review, and publication rules. Only independently authored code and the project-owned icon are published — never third-party binaries, artwork, keys, or credentials.

## Author & License

- **Author**: Haseeb Mir ([@haseeb-heaven](https://github.com/haseeb-heaven))
- **License**: [MIT License](LICENSE) — Free and Open Source.
- **Inspiration**: Workflow inspired by classic Internet Download Manager (Tonec FZE). No affiliation, no shared code, no reverse-engineered binaries.
