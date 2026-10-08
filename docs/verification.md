# Verification record

Machine: Apple Silicon, macOS 15.3.1; Swift 6.0.3 Command Line Tools. Tests use the real release-mode engine.

## Completed checks

- 38 deterministic functional checks passed: ranges; ignored-range fallback; weak ETag/Last-Modified fallback; single-stream transfers; retries during HEAD and GET; redirects; Basic authentication and rejection; HTTP proxy routing; Keychain CRUD; unknown lengths; empty files; malformed ranges; changed resources; HTTP errors; truncation; collision preservation; pause/resume; speed limiting; HTML page rejection; attached HTML files; browser-verification errors; SQLite recovery; URL validation; queue scheduling; safe batch filenames; missing validator fallback; and empty-file HEAD fallback; and HTML base URL resolution; and inactive markup exclusion.
- Real trusted HTTPS download matched a separately fetched SHA256 reference.
- Full 5 GiB loopback download: **5,368,709,120 bytes**, full-file SHA256 matched the independently generated pattern, **253 seconds**. Generated files were removed after the check. This run preceded the final response-header-only review fixes; affected fallback and HTML paths were rechecked separately.
- Release `.app` built and its ad hoc signature verified.
- Native window smoke check: visible, six download columns, eleven category rows, eleven toolbar items, layout checked at 1100 and 900 pixel widths; scheduled jobs remain queued after termination. Actual rendered views are captured under ignored `build/`.
- Python analysis/fixture scripts compile; shell scripts parse; `git diff --check` passes.

## OpenQodex

The initial review found missing HEAD retries and inflated retry progress. The next review found validator selection inconsistency and missing GET HTML rejection. Subsequent reviews found unsafe batch filenames, missing-validator fallback, queued-job termination, and empty-file HEAD fallback; and HTML base URL resolution; and inactive markup exclusion. These findings were fixed and regression-tested. The full delivery review (`d5c43bb70057`, against `1ebe3ec`) reported one minor grabber base URL issue, which was corrected and regression-tested. The correction review identified inactive markup handling, which was replaced with native HTML parsing and regression-tested. Final parser review (`c638826b19d6`, against `2d3fca1`) passed with **no findings on the changed lines**. Earlier full reviews and this final correction review together cover the implementation; the final review alone is not a new full audit. Raw review reports remain in ignored `build/`.

## User-reported Testfile.org failure

`https://testfile.org/files-5GB` returned HTTP 403 for both HEAD and GET, with `cf-mitigated: challenge`, and a browser-verification page. The original failed job recorded HTTP 403 with zero bytes. The app now reports browser verification clearly, supports GET fallback when HEAD alone is forbidden, and provides an Open Page action in Details. The specific external endpoint remains dependent on the site's access decision; the local 5 GiB test does not claim that this website was downloaded successfully.

## Limits

Checks establish the documented native behaviors. They do not establish full IDM parity, throughput equivalence, every proxy/auth scheme, or long-duration production reliability. The package is locally ad hoc signed for personal use, not notarized for public distribution.
