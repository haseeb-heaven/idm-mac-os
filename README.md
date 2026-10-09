# IDM

**A personal, native macOS port of Internet Download Manager, informed by reverse engineering of Windows IDM.**

Swift 6 · AppKit · URLSession · SQLite · Keychain · macOS 13+ · Apple Silicon / Intel / Universal

This is an independent project for `haseeb-heaven`, with no affiliation or endorsement from Tonec. It is not an official “IDM for Mac” release. The owner's Windows copy supplies the analysis and execution reference.

## Credits

Internet Download Manager is made by the original IDM team at Tonec FZE — https://www.internetdownloadmanager.com/. This repository is an unofficial macOS port, not the official software. If you use Windows, please buy an official IDM license to support the original team so tools like this can keep existing on other platforms.

![Native macOS interface during an actual integration test](docs/screenshots/idm-classic-downloads-v020.png)

## Start here

| Topic | Evidence |
| --- | --- |
| How the macOS implementation was built | [Native port, provenance, architecture, and tools](docs/native-port.md) |
| Original executable analysis | [GhidraMCP and Radare2 MCP findings](docs/findings/http-engine.md) |
| Download correctness | [Real URLs, file sizes, and SHA-256 results](docs/real-url-verification.md) |
| OpenIGI site grabbing and OS downloads | [Discovery, full-file checksums and network limits](docs/openigi-verification.md) |
| Original IDM speed comparison | [Paired download methodology and results](docs/speed-comparison.md) |
| Feature status and limitations | [Coverage matrix](docs/parity.md) |
| Browser setup and compatibility | [Native messaging, extensions and browser test evidence](docs/browser-integrations.md) |
| Regression checks and review | [Verification record](docs/verification.md) |

## Download v0.2.1

[Get the latest release](https://github.com/haseeb-heaven/idm-mac-os/releases/latest): choose Apple Silicon (`arm64`), Intel (`x86_64`), or Universal. Extract the ZIP and move **IDM.app** to Applications. Packages are ad hoc signed and are not notarized; macOS may require approval in System Settings → Privacy & Security. Check the included `SHA256SUMS` before installation.

See [macOS compatibility and executed architecture checks](docs/macos-compatibility.md), [classic toolbar design and AgentReach research](docs/design/idm-classic-v020.md), and [release notes](docs/release-notes-v0.2.0.md).

## Build and run

```sh
git clone git@github.com:haseeb-heaven/idm-mac-os.git
cd idm-mac-os
scripts/package.sh
open "build/IDM.app"
```

Requirements: Apple Silicon or Intel Mac, macOS 13+, Swift 6 Command Line Tools, and Python 3.12 for fixtures/build resources, and Node.js 22 for extension checks. The Swift package has no external dependencies. A full Xcode installation is unnecessary. `scripts/swift.sh` handles the inconsistent SwiftPM interfaces on the development Mac using a project-local public-interface copy.

For personal installation and native host registration, run `scripts/install.sh`; it installs to `~/Applications/IDM.app`. Browser extensions must then be loaded using the included setup instructions.

The release bundle is locally ad hoc signed. App data is stored in `~/Library/Application Support/IDMMac/`; credentials are stored in Keychain.

## Features

- Manual HTTP/HTTPS and batch downloads with validated concurrent byte ranges.
- Partial-file pause/resume, response validators, retries, redirects, and safe final assembly.
- SQLite persistence and recovery after restart; Keychain Basic authentication.
- Proxy settings, aggregate rate limits, FIFO queue, and per-job scheduled start times.
- Classic IDM-style colored toolbar and labeled actions; optional compact Mac toolbar, light/dark/system appearance, searchable downloads and live details.
- Single-page file-link grabber with deduplication and review before downloading.
- Chromium and Firefox extensions: link/context-menu handoff, batches, direct media selection, optional cookies and automatic capture.
- Streaming imports from live browser Blob URLs; Safari/other-browser HTTP bookmarklet handoff.

Dynamic IDM segmentation, advanced recurring schedules, multiple named queues, recursive grabbing, FTP, and Windows-specific integrations remain unsupported or unverified. Speed measurements apply to the recorded environment and files; universal performance parity is not established.

## Verify

```sh
# Core checks, release packaging, and actual native toolbar/queue end-to-end checks:
scripts/test.sh

# Instrumented core/UI coverage and browsable uncovered lines:
scripts/coverage.sh

# Opt-in complete downloads with independent curl SHA-256 references:
python3 scripts/real_download_checks.py

# Opt-in 5 GiB acceptance test; removes the generated file afterward:
scripts/swift.sh run --disable-sandbox -c release IDMCoreChecks --large
```

The executable test runner is used because this Mac's Command Line Tools do not provide XCTest. It exercises real HTTP requests, file IO, SQLite, Keychain, restart behavior, and AppKit controls. Test failures return nonzero exit status. Measured coverage and its gaps are published with the results.

**Previous release checks:** 47 core checks, native AppKit pause/resume and checksum checks, complete 5 GiB acceptance with an asserted 1 GiB memory ceiling, and real paired installer downloads. That release measured **96.90% core** and **81.44% UI** line coverage; see the verification record for current integration results.

## Compare with Windows IDM

Original IDM runs in a project-local CrossOver bottle. The benchmark invokes its supported command-line interface, waits for complete files, verifies SHA-256 hashes, alternates run order, and records elapsed time and decimal MB/s.

```sh
scripts/swift.sh build --disable-sandbox -c release --product IDMCoreChecks
python3 scripts/compare_idm_speed.py --trials 3
```

CrossOver, the owner's IDM installer, the reference bottle, and optional MinGW-built dialog observer are local prerequisites. See the [methodology](docs/speed-comparison.md) for setup, excluded trials, units, and comparison limits. Proprietary binaries and credentials are excluded from Git.

## Troubleshooting

Select a failed job for the full error and retry controls. Browser-verification pages can reject standalone clients. Signed download URLs can expire; use a stable publisher/release URL to obtain a fresh redirect. A `blob:` URL identifies data in its originating browser environment: use the included extension in that live tab to import an ordinary Blob, or supply an HTTP/HTTPS source URL. Expired Blob URLs, MediaSource streams and DRM cannot be recovered from a pasted URL.

## Repository layout

```text
Sources/IDMCore/       Native transfer, persistence, credentials, queue, and grabber
Sources/IDMMac/        AppKit application, bridge and interface
Sources/IDMBrowserHost/ Swift native-messaging executable
integrations/         Independently authored browser extensions and bookmarklet
Tests/IDMCoreTests/   Executable functional/integration checks
scripts/              Analysis, build, test, coverage, and benchmark tooling
analysis/raw/         Original binary identity and actual MCP output
docs/                 Findings, coverage, comparisons, screenshots, and limits
```

[RE.md](RE.md) records the reverse-engineering workflow. [AGENTS.md](AGENTS.md) defines the development, testing, review, and publication rules. Original installers, extracted executables, activation keys, and build products remain local.
