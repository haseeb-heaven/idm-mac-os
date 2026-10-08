# Original IDM versus the native macOS engine

This report records actual downloads by Windows IDM and the native release on the same Mac. It establishes the measured cases; it does not certify universal performance or complete IDM parity.

## Environment and method

- Apple M2 / Mac14,7, 8 GiB RAM, macOS 15.3.1 build 24D70.
- Original `IDMan.exe` 6.43 build 15.2 under CrossOver 26.3 in the isolated `IDM-Reference` bottle. Installed executable SHA-256 matches the analyzed binary.
- The reference installation is in trial mode. Its normal registration reminder is declined through the No button; activation logic is unchanged.
- Native executable is an optimized Swift release build with sixteen connections, 8 MiB segments, and no rate limit. Original connection settings remain at installation defaults; an equal connection count has not been established.
- Each valid pair requests the same public publisher URL and produces matching complete-file SHA-256 hashes. Output filenames are unique, destinations are absent before dispatch, and files are removed after hashing.
- Alternating order: original/native, native/original, original/native. Three pairs per installer are collected for the performance campaign; one additional pair per installer validates the subsequent memory-corrected release.
- Elapsed time includes any automatic network retries during a completed transfer and is measured with Python's monotonic performance clock from command dispatch through full-file completion and SHA-256 verification. Original file completion is polled at 100 ms intervals; native completion is observed through its executable exit. Native temporary-file cleanup occurs before that exit; the original benchmark file is removed after its timer stops.
- Rates use decimal MB/s (`bytes / seconds / 1,000,000`). IDM's live UI can display binary units; live peak values are not substituted for these full-file rates.
- The original application is already running, whereas the native checker is launched for each run. Wine launch overhead is included. This is a comparison of these concrete Mac workflows, not a bare-Windows or equal-process-lifecycle experiment.
- Public CDN behavior, bandwidth, background activity, TLS negotiation, redirects, and caching outside this Mac are uncontrolled. Some development work occurred while collecting exploratory measurements. Medians summarize observations and are not statistical proof of equivalence.

## Sources

- [VS Code stable Apple Silicon DMG](https://code.visualstudio.com/sha/download?build=stable&os=darwin-arm64-dmg): 295,206,425 bytes.
- [Cursor 3.23 Apple Silicon DMG](https://api2.cursor.sh/updates/download/golden/darwin-arm64/cursor/3.23): 294,097,415 bytes.
- [Antigravity 2.21.1 Apple Silicon DMG](https://storage.googleapis.com/antigravity-public/antigravity-hub/2.21.1-5614635819335680/darwin-arm/Antigravity.dmg): 206,573,240 bytes.

Publisher stable links can change over time. The recorded byte counts are pinned acceptance criteria for this experiment; refresh the expected sizes after independently identifying a new asset before rerunning. A changed byte count or checksum invalidates a pair. Incomplete attempts are preserved separately with their exclusion reason.

Raw exploratory records: [per-byte incomplete attempt](benchmarks/exploratory-per-byte-incomplete.json), [chunk engine with four connections](benchmarks/chunk-four-connections.json), [eight connections with 2 MiB segments](benchmarks/chunk-eight-connections-2MiB.json), [eight connections with 8 MiB segments, interrupted](benchmarks/eight-connections-8MiB-incomplete.json). These describe earlier binaries and are not mixed with final-release medians. Exploratory stages include development builds identified by binary SHA-256 where recorded; the performance-campaign source is commit `6cb8302`, with checker SHA-256 `a1f753e8ba64dc1ae2de01138dace1a8738d13345350de9c93e837b391393324`. [Original progress controls](benchmarks/original-progress-controls.txt) show actual IDM downloading under CrossOver. The 32 connection-table rows are UI capacity evidence; they do not establish 32 active connections or the default maximum.

## Three-pair performance campaign

All campaign native measurements use sixteen connections and 8 MiB segments. Each recorded complete pair has the same complete-file SHA-256. Individual timings remain in the linked JSON records; completed slow transfers are retained.

| Installer | Original IDM median MB/s | Native median MB/s | Original range MB/s | Native range MB/s | Valid pairs |
| --- | ---: | ---: | ---: | ---: | ---: |
| VS Code | 11.00 | 11.42 | 9.73–11.16 | 11.38–11.71 | 3 |
| Cursor | 7.59 | 9.78 | 6.80–8.84 | 8.33–10.08 | 3 |
| Antigravity | 2.83 | 9.08 | 1.57–9.40 | 8.64–9.29 | 3 |

[Campaign VS Code records](benchmarks/performance-campaign-vscode.json), [campaign Cursor records](benchmarks/performance-campaign-cursor.json), [campaign Antigravity records](benchmarks/performance-campaign-antigravity.json). Antigravity’s original trials took 72.96, 21.97, and 131.84 seconds; native trials took 23.91, 22.23, and 22.76 seconds. The slow original transfers completed automatically without manual intervention and are retained. Their large variation means the median ratio must not be presented as a general acceleration factor. Original IDM under CrossOver is a concrete reference workflow, not a substitute for a stable bare-Windows benchmark.

## Excluded attempts and implementation changes

One exploratory Cursor run was delayed by the reference application's registration reminder and did not produce a final file. It supplies no valid speed measurement. Original IDM subsequently reported connection timeouts; restarting only the reference bottle's Wine runtime restored a checksum-verified warm-up download. These interrupted attempts are excluded. A subsequent eight-connection/8-MiB Antigravity attempt also stalled at zero bytes in original IDM on its third trial; its two completed pairs remain exploratory and the incomplete trial is excluded. A fresh isolated-runtime restart and checksum-verified warm-up precede the final sixteen-connection comparison.

The initial native implementation consumed asynchronous bytes individually. Delegate-based chunks remove that application-level loop and apply per-task high/low watermarks to reduce queued data pressure. A second change reuses the final URL resolved during inspection so every segment does not repeat the publisher redirect. Authorization is preserved only for the original origin; separate same-origin and cross-origin tests cover this behavior.

The optimized chunk engine's complete 5 GiB fixture download passed SHA-256 verification in 111 seconds. The earlier per-byte implementation completed the same acceptance check in 253 seconds. These separate runs indicate improvement, but they were not a controlled simultaneous benchmark.

## Reproduce

Install CrossOver and the owner's IDM copy in the local paths used by the benchmark. The project's original local setup uses `build/tools/CrossOver.app`, `build/bottles/IDM-Reference`, and the installed `C:\Program Files\Internet Download Manager\IDMan.exe`. These proprietary runtime files are ignored by Git.

```sh
# Optional normal-dialog observer/guard; requires MinGW on the host.
mkdir -p build/speed-comparison
i686-w64-mingw32-gcc -O2 -static scripts/windows_idm_probe.c \
  -o build/speed-comparison/idm_probe.exe -luser32 -lgdi32

# Regression check: synthetic Edit text must not be read; Static text is reported.
LC_ALL=C LANG=C CX_BOTTLE_PATH="$PWD/build/bottles" \
  build/tools/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine \
  --bottle IDM-Reference build/speed-comparison/idm_probe.exe --self-test

# Start this only in the reference bottle; create guard-stop to finish it.
rm -f build/speed-comparison/guard-stop
LC_ALL=C LANG=C CX_BOTTLE_PATH="$PWD/build/bottles" \
  build/tools/CrossOver.app/Contents/SharedSupport/CrossOver/bin/wine \
  --bottle IDM-Reference build/speed-comparison/idm_probe.exe \
  --guard "Z:\\Users\\haseeb-mir\\Documents\\Code\\idm-mac-os\\build\\speed-comparison\\guard-stop"
```

Run the guard in a separate tracked terminal if needed, verify a warm-up file completes, then:

```sh
scripts/swift.sh build --disable-sandbox -c release --product IDMCoreChecks
python3 scripts/compare_idm_speed.py --trials 3 --timeout 600
# Keep stdout or redirect it to an ignored build log for long runs.
touch build/speed-comparison/guard-stop
```

The guard acknowledges standard trial/administrator reminders and closes completed-download dialogs through normal controls. It reads no edit fields and modifies no licensing settings. A run interrupted by a prompt requiring manual intervention, runtime recovery, incomplete file, or mismatch must be excluded. Slow complete transfers with matching checksums are retained; automatic retries remain part of their elapsed time. The script fails on timeout or checksum mismatch and preserves completed records under `build/speed-comparison/run-*/results.json`.

The original command-line switches are documented by [IDM's publisher](https://www.internetdownloadmanager.com/support/command_line.html). The probe and harness source, raw timing records, binary identities, and hashes provide the reproduction trail.

## Other supplied links

The fresh convt release completed in the earlier native-versus-curl checksum checks. The supplied old GitHub signed asset had expired and returned HTTP 618; Testfile returned a browser challenge (HTTP 403). Browser-local `blob:` addresses cannot provide standalone HTTP download-speed samples. These links are recorded in [real URL verification](real-url-verification.md); no paired original-IDM speed result is claimed for them.

## Large-file memory correction

After the three-pair campaign, the final 5 GiB check exposed temporary Foundation object retention in synchronous assembly and checksum-read loops. A read-only stack sample identified `NSFileHandle.read` and an 8.1 GiB process footprint; the incomplete check was stopped and only its generated file was removed. Explicit per-block autorelease pools address these paths. The memory-corrected run completed the full checksum check in **86 seconds**, with **465,879,040 bytes** peak resident memory (about **444 MiB**), and removed its generated files. The opt-in large-file test now asserts peak RSS below **1 GiB**. [Darwin defines the measurement in bytes](https://github.com/apple/darwin-xnu/blob/main/bsd/man/man2/getrusage.2).

The campaign table above identifies the earlier `6cb8302` binary; it is not silently relabeled as a measurement of the corrected release. Follow-up pairs and the final memory-assertion run are recorded separately.

The assertion-enabled final acceptance passed in **90 seconds** with **462,143,488 bytes** peak RSS (about **441 MiB**). [Full-file and memory assertion log](large-file-test-results.txt), [OS resource record](large-file-memory-resources.txt). Native source: `878bdf8`. Generated files were removed. The 86- and 90-second runs are acceptance checks, not controlled throughput-equivalence experiments.

## Corrected release follow-up pairs

After the memory correction and successful assertion-enabled 5 GiB run, original IDM was restarted in its isolated bottle and warmed with a curl-matched file. One fresh original/native pair per installer validates the exact corrected release. These single-pair rates are observations, not medians or statistical proof of equality. They are separate from the earlier campaign.

| Installer | Original IDM MB/s | Native MB/s | Full SHA-256 matched |
| --- | ---: | ---: | --- |
| VS Code | 10.42 | 10.82 | Yes |
| Cursor | 8.72 | 10.06 | Yes |
| Antigravity | 9.10 | 8.85 | Yes |

[Raw corrected-release records](benchmarks/memory-corrected-release.json). Native source commit: `878bdf8`; checker SHA-256: `0e14c70c594af63bbfc3dd26cd76e8a7897e0cdb7334ae06923d45a1163afc6c`. Settings: sixteen connections, 8 MiB segments, no rate limit. All six complete downloads matched their paired hashes and the earlier independently verified publisher-file identities. The reference guard was stopped after the runs.
