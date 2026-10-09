# Verification record

Machine: Apple Silicon, macOS 15.3.1; Swift 6.0.3 Command Line Tools. Tests use the real release-mode engine.

## What the suite checks

- Deterministic functional checks: ranges; ignored-range fallback; weak ETag/Last-Modified fallback; single-stream transfers; retries during HEAD and GET; redirects; Basic authentication and rejection; HTTP proxy routing; Keychain CRUD; unknown lengths; empty files; malformed ranges; changed resources; HTTP errors; truncation; collision preservation; pause/resume; speed limiting; HTML page rejection; attached HTML files; browser-verification errors; SQLite recovery; URL validation; queue scheduling; safe batch filenames; missing validator fallback; empty-file HEAD fallback; HTML base URL resolution; inactive markup exclusion; chunk-stream backpressure; cancellation before response headers; same-origin credential redirects; and cross-origin credential removal.
- Real trusted HTTPS download matched against a separately fetched SHA256 reference.
- Full 5 GiB loopback download with matching full-file SHA-256 and a 1 GiB peak-RSS assertion (generated files removed afterward).
- Release `.app` built for all architectures with strict ad hoc signature verification.
- Native window smoke checks: visibility, columns, category rows, toolbar items, layout at 1100 and 900 pixel widths; scheduled jobs remain queued after termination.
- Node extension checks: validation, permissions, capture, browser recovery and guard behavior, plus an acceptance-helper regression.
- Packaged native host/app acceptance groups and AppKit end-to-end checks (actual download SHA-256, toolbar pause/resume, completed details, search, failed-job actions, startup URL delivery, minimum width).
- Real Chromium and Firefox runs against the packaged app, including live Blob imports and full-file fixture hashes. See [browser setup and precise limitations](browser-integrations.md).

## User-reported Testfile.org failure

`https://testfile.org/files-5GB` returned HTTP 403 for both HEAD and GET, with `cf-mitigated: challenge`, and a browser-verification page. The app reports browser verification clearly, supports GET fallback when HEAD alone is forbidden, and provides an Open Page action in Details. The specific external endpoint remains dependent on the site's access decision; the local 5 GiB test does not claim that this website was downloaded successfully.

## Limits

Checks establish the documented native behaviors. They do not establish universal throughput equivalence, every proxy/auth scheme, or long-duration production reliability. Safari destination approval and full transfer remain unverified, as do individual branded Chromium browsers and Firefox private/container recovery. The package is locally ad hoc signed for personal use, not notarized for public distribution.

## Follow-up download checks

See [real URL verification](real-url-verification.md) for public installer hashes. Reports are recorded separately to avoid duplicate linked core instrumentation.
