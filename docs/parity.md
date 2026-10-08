# Feature coverage

This is implementation coverage, not a claim of 100% IDM equivalence.

| Feature | Native behavior | Evidence / remaining comparison |
|---|---|---|
| HTTP ranges | Concurrent validated fixed-size segments | Original range construction decompiled and independently checked; dynamic IDM policy unverified |
| Pause/resume | Partial files retained; validators checked on resume | Cancellation/resume integration check passes |
| Retry/recovery | Exponential retries for inspection and transfer; rejects permanent errors | HEAD and transfer regression checks pass |
| Redirects / HTTPS | URLSession redirects and normal system TLS trust | Redirect fixture and real HTTPS checksum comparison pass |
| Authentication | Keychain-backed Basic credentials | Auth and Keychain integration checks pass; advanced auth unverified |
| Proxy | Configurable HTTP/HTTPS proxy dictionary | Actual HTTP proxy routing check passes; authenticated proxy unverified |
| Speed limits | Aggregate throttled byte processing | Timing assertion passes; IDM algorithm equivalence unverified |
| Queues | One FIFO queue, start/stop controls | Queue scheduling policy checks pass; multiple named queues absent |
| Scheduler | Persistent per-job start date, app must be running | Due-time policy and SQLite round-trip pass; recurring schedules absent |
| Storage | SQLite jobs and on-disk partial files | Restart recovery, collision, truncation, and storage failure checks pass |
| Large files | 64-bit sizes/ranges and bounded segment files | Complete 5 GiB download and full SHA256 passed |
| Interface | IDM-style native toolbar, category tree, list, live details | Original captured under CrossOver; native default/minimum-width smoke checks pass; exact visual parity unverified |
| Site grabber | File links from one public page, deduplication and manual review | Link extraction check passes; recursive crawling absent |
| Browser integration | Excluded | User-requested exclusion |
| FTP / Windows-specific features | Not implemented | No equivalence claim |

Windows IDM ran under CrossOver for layout observation. Paired full-file downloads and throughput comparisons against the original application are recorded in [speed comparison](speed-comparison.md). Full comparative testing of all features remains incomplete.
