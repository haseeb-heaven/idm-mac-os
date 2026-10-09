# Feature status

What MacDownloadManager implements today, and what it does not. No equivalence with any other product is claimed.

| Feature | Status | Evidence |
|---|---|---|
| HTTP ranges | Concurrent validated fixed-size segments | Fixture and integration checks pass |
| Pause/resume | Partial files retained; validators checked on resume | Cancellation/resume integration check passes |
| Retry/recovery | Exponential retries for inspection and transfer; rejects permanent errors | HEAD and transfer regression checks pass |
| Redirects / HTTPS | URLSession redirects and normal system TLS trust | Redirect fixture and real HTTPS checksum comparison pass |
| Authentication | Keychain-backed Basic credentials | Auth and Keychain integration checks pass; advanced auth unverified |
| Proxy | Configurable HTTP/HTTPS proxy dictionary | Actual HTTP proxy routing check passes; authenticated proxy unverified |
| Speed limits | Aggregate throttled byte processing | Timing assertion passes |
| Queues | One FIFO queue, start/stop controls | Queue scheduling policy checks pass; multiple named queues absent |
| Scheduler | Persistent per-job start date, app must be running | Due-time policy and SQLite round-trip pass; recurring schedules absent |
| Storage | SQLite jobs and on-disk partial files | Restart recovery, collision, truncation, and storage failure checks pass |
| Large files | 64-bit sizes/ranges and bounded segment files | Complete 5 GiB download and full SHA256 passed |
| Interface | Colored/labeled AppKit toolbar, optional compact layout, light/dark/system appearance, sidebar, searchable list and live details | Appearance/layout combinations, preference restoration and minimum-width checks pass |
| Site grabber | File links from one public page, deduplication and manual review | Extension and explicit/extensionless download-link extraction checks pass; recursive crawling absent |
| Browser integration | Swift native messaging host, Chromium/Firefox extensions, link/batch/media selection, optional capture and cookies, Blob streaming | See [browser compatibility and executed tests](browser-integrations.md) |
| FTP | Not implemented | No claim |

The workflow is inspired by classic download managers such as Internet Download Manager (Tonec FZE) — no affiliation, no shared code.
