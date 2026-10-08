# IDM Mac

Personal native Apple Silicon macOS download manager for `haseeb-heaven`. Built with Swift 6 and AppKit, informed by analysis of the owner's licensed Windows IDM application.

## Run

```sh
scripts/package.sh
open "build/IDM Mac.app"
```

Requires macOS 15+, Apple Silicon, Python 3.12 for the fixtures, and Swift 6 Command Line Tools. No full Xcode installation or external Swift packages are needed. `scripts/swift.sh` handles the inconsistent private SwiftPM interfaces found on this Mac using a project-local copy of the public interfaces.

## Features

- Manual HTTP/HTTPS and batch URL downloads.
- Concurrent byte ranges, pause/resume, safe fallback when ranges are ignored, retries, redirects, and file assembly.
- SQLite job persistence and recovery after restart; Keychain Basic authentication credentials.
- Proxy configuration, speed limits, FIFO queue, and scheduled start times while the app is running.
- IDM-inspired light theme, colored toolbar with overflow handling, category icons, file grid, progress bars, and live details with full errors.
- Basic single-page file-link grabber with deduplication and a review step.

Browser integration is excluded. Complete IDM behavior parity is **not verified**: dynamic segmentation policy, advanced recurring schedules, named queues, recursive grabber workflows, FTP, and Windows-specific integrations are not implemented. See [feature coverage](docs/parity.md).

## Verify

```sh
scripts/test.sh
# Instrument core and native UI checks; generate line/region coverage and HTML reports:
scripts/coverage.sh
# Opt-in real installer downloads with independent curl checksum comparisons:
python3 scripts/real_download_checks.py
# Full-size acceptance test; generates and removes 5 GiB locally:
scripts/swift.sh run --disable-sandbox -c release IDMCoreChecks --large
# Independent HTTPS reference and native download comparison:
curl -fsSL https://raw.githubusercontent.com/github/gitignore/main/Swift.gitignore -o build/https-reference.txt
scripts/swift.sh run --disable-sandbox IDMCoreChecks --https
```

The integration executable is used because this machine's Command Line Tools do not contain XCTest. It exercises real URLSession requests, actual file IO, SQLite, Keychain, and a deterministic loopback server. Test failures return a nonzero exit code. Read [verification results](docs/verification.md) for recorded outcomes and limits.

## Download failures

Select a failed download and choose **Details**. The window shows the full error, lets you retry, and offers **Open Page**. Websites requiring browser verification may reject a standalone download manager. Copy the actual file URL from the browser once available. Ordinary HTML pages are rejected; explicitly attached HTML files are supported.

## Research

[RE.md](RE.md) documents the analysis workflow. [HTTP engine findings](docs/findings/http-engine.md) link original function addresses to GhidraMCP decompilation and independent Radare2 MCP evidence. Proprietary binaries and license keys stay outside Git. Local app data lives in `~/Library/Application Support/IDMMac/`.

[Real URL test results and measured coverage](docs/real-url-verification.md).
