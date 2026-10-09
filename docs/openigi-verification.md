# OpenIGI Grabber and download verification

Executed 2026-10-09 on this Apple Silicon Mac with the real Swift engine. Native files were independently verified against complete, byte-ordered curl HTTP/1.1 range responses. No downloaded program or installation script was executed.

| Endpoint | Bytes | SHA-256 |
| --- | ---: | --- |
| `https://api.openigi.com/download/win-x64` | 44,723,616 | `e7d517df4cde1d5f0e350e2486d42af4e668b9e5df9e6649510a2ac3ed471609` |
| `https://api.openigi.com/download/linux-x64` | 45,382,292 | `c44fc18db8e154cdeab0246ad5297b0cd9fa2e1d7a8c72860ee739ff30183df0` |
| `https://api.openigi.com/download/osx-arm64` | 41,496,743 | `5c5e226d6c58fdfee35354333f8f1ffd14271ac604729b5933140c9a7d82879f` |

[Full results](test-results/openigi-downloads.json) record the native and reference hashes, bytes, timings and transfer options. Windows was freshly downloaded in 307.4 seconds using four connections and 1 MiB chunks. Earlier Linux/macOS native results were reused for fresh independent verification. macOS took 377.7 seconds and required a second engine attempt after a timeout; Linux took 305.6 seconds, but its earlier evidence did not record segment options. Reference curl used eight connections and 1 MiB ranges, with no transport errors in the final verification run.

## Discovery

The native single-page Grabber now recognizes explicit HTML download attributes and anchor paths containing `/download/`, including extensionless OS endpoints. Extension filtering remains in place for ordinary page assets. The regression fixture verifies this behavior, deduplication and credential rejection.

Earlier actual native discovery on [OpenIGI](https://openigi.com/) returned three OS anchors. The live page changed during the test session: the current HTML contains only the Windows download anchor, and Linux/macOS installation instructions point to a shell script. The recorded endpoints remained downloadable. [Current-page evidence and HTML hash](test-results/page-change.json) distinguish the two observations. The script was not executed.

## Limits and failures

[An earlier four-MiB segment attempt stalled](test-results/initial-segment-attempt.json), and [a Windows transfer timed out](test-results/segmented-attempt-failures.json). Earlier whole-stream curl probes also reset or failed HTTP/2 framing. Those failures are retained; the passing one-MiB range runs do not prove reliability with the application's default eight-MiB chunks, universal network reliability or speed parity with original IDM.

Reproduce the bounded test with `python3 scripts/openigi_download_checks.py --os win-x64 --output build/openigi-recheck`; first build `IDMCoreChecks` using `scripts/swift.sh build --disable-sandbox --product IDMCoreChecks`. With the current page, new native discovery tests can run Windows; Linux/macOS earlier native evidence can be independently rechecked using `--reuse-native` with their saved evidence files. The opt-in runner downloads real publisher files and removes its owned payload directories afterward, retaining evidence JSON.
