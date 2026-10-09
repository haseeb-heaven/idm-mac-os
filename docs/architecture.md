# How this app is built

MacDownloadManager is an independent open-source macOS download manager. Its workflow is inspired by classic download managers such as Internet Download Manager (Tonec FZE) — no affiliation, no shared code, no reverse engineering. All native code is authored in Swift and AppKit.

## Native architecture

| Component | Responsibility |
| --- | --- |
| `DownloadEngine` | Range negotiation, validators, retries, partial files, integrity checks, assembly |
| `HTTPChunkStream` | Delegate-delivered data chunks, reusable URLSession connections, queue backpressure |
| `JobStore` | SQLite snapshots and recovery of interrupted jobs |
| `CredentialStore` | macOS Keychain storage and retrieval |
| `QueuePolicy` | Due-time and FIFO selection |
| AppKit controllers | Native windows, toolbar actions, details, and failure guidance |

The engine delivers data in chunks over reusable URLSession connections while retaining validation, throttling, and partial-file behavior. Per-block autorelease pools bound assembly/checksum temporaries, and the opt-in acceptance test asserts peak RSS below 1 GiB on the 5 GiB check.

## Tools used

- **Swift 6, AppKit, URLSession, SQLite, Security/Keychain:** implementation and native integration checks.
- **Python, curl, SHA-256, LLVM coverage tools:** fixtures, independent download references, integrity, and executable coverage.
- **Node.js:** WebExtension validation and permission/capture behavior checks.
- **OpenQodex with Codex reviewer:** code reviews whose findings and corrections are recorded in the repository.

## Scope and distribution

Browser integration is independently implemented with a Swift host and Chromium/Firefox WebExtensions; see [browser setup and actual test evidence](browser-integrations.md). Live ordinary `blob:` data can stream from its originating tab; arbitrary pasted or expired Blob identifiers remain unavailable. Browser challenges and expired signed URLs remain external access constraints. [Feature status](parity.md) records unsupported and unverified behavior. Third-party executables, license keys, cookies, and local runtime data remain outside Git. The application bundle is locally ad hoc signed for the owner's Mac.
