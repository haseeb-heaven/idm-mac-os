# v0.2.0 verification

## Executed local checks

The final appearance-persistence source passed `scripts/test.sh` on Apple M2 / macOS 15.3.1: 19 Node tests, one completed-file helper regression, two fixture startup checks, 58 core checks, release packaging, real AppKit smoke/E2E checks and five native host acceptance groups.

AppKit smoke tests exercise Classic and Compact toolbars with Light and Dark appearances, release of the System override, the 900-point minimum width, all eleven toolbar items and queued startup URL delivery. An isolated UserDefaults suite saves both appearance preferences through actual menu handlers; a fresh controller verifies their restored values and applied window/toolbar appearance. These tests do not overwrite installed user preferences.

UI E2E checks download actual fixture bytes, verify SHA-256, pause/resume through toolbar handlers, check completed details, search and selection preservation, and exercise failed-job actions. These are deterministic local downloads, not a claim that all publisher servers accept standalone clients.

The final Intel binaries passed the same 58 core checks, smoke/E2E and five native host groups under Rosetta on the M2. Architecture, macOS 13 deployment target, strict signatures and extracted ZIP executable hashes were verified for ARM, Intel and Universal packages. See [compatibility evidence](test-results/v020-compatibility.json) and [browser evidence](test-results/v020-browser.json) for exact binary hashes and runtime scope.

## Review

OpenQodex 0.8.1 reviewed the v0.2.0 changes against `31f2b3e`. Initial change `517fdfc8622a` reported one minor maintainability finding: appearance persistence lacked coverage. The isolated suite and fresh-controller check described above correct that gap. Raw reviewer reports remain in ignored `build/`.

## CI fixture correction

The previous GitHub job spent about 35 seconds starting each HTTP fixture. Python HTTPServer called reverse DNS while binding localhost. Fixtures now bind directly and set deterministic server metadata; regression checks forbid reverse lookup and verify real HTTP content hashes. Keychain was passing and was not changed. CI runs bounded extension/core/package/UI/native/signature stages separately.

## Limits

Runtime verification is recorded per environment. Intel under Rosetta does not establish execution on a physical Intel Mac. A macOS 13 deployment target does not establish runtime testing on macOS 13 or 14. Safari native extensions, every branded Chromium browser, Firefox private/container recovery and Chrome cookie permission automation remain outside completed acceptance. Tests and coverage do not establish complete IDM parity or 100% code coverage.

Historical transfer-engine full 5 GiB and publisher URL checks remain in [verification](verification.md); transfer-engine source was unchanged in this release. Historical coverage values in that document refer to its earlier instrumented snapshot.
