# macOS compatibility

MacDownloadManager 0.2.0 targets macOS 13 Ventura and newer. The native application and native browser messaging host are available in three packages:

| Package | Processor | Deployment target |
| --- | --- | --- |
| `arm64` | Apple Silicon | macOS 13.0 |
| `x86_64` | Intel | macOS 13.0 |
| `universal` | Apple Silicon or Intel | macOS 13.0 |

Use the universal package when unsure. This is an independently authored application; the packages are ad hoc signed, without Apple Developer ID notarization. A deployment target records which operating system the binaries permit; it does not establish that every macOS version has been tested.

## Reproduce release packages

A Mac with Swift 6 Command Line Tools, Python 3, and Node.js is required. No full Xcode installation is needed to build the application or the native messaging host.

```sh
scripts/package.sh --arch arm64
scripts/package.sh --arch x86_64
scripts/package.sh --arch universal
python3 scripts/release_artifacts.py
```

Default `scripts/package.sh` still produces `build/MacDownloadManager.app` for the build machine's architecture. Architecture packages appear in `build/releases/<architecture>/MacDownloadManager.app`. The release script verifies both executable architectures, their `LC_BUILD_VERSION` macOS deployment targets, version metadata, and strict code signatures. It writes three ZIP archives, `SHA256SUMS`, and `release-manifest.json` containing hashes for each archive and executable.

Version metadata has one source: `version.json`. Browser extension compatibility depends on the browser as well as the operating system; see [browser integrations](browser-integrations.md). Safari's packaged native extension is not included.

## Executed validation

On October 9, 2026, the application and native host compiled for both `arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`; `lipo` created universal binaries. All six binary outputs passed architecture, macOS 13 deployment target, and strict code signature checks. Each release ZIP was extracted and verified again, with matching executable SHA-256 hashes.

The Intel application ran through already installed Rosetta on an Apple M2 Mac running macOS 15.3.1. Native window smoke checks passed for classic and compact toolbars, each in light and dark appearance, including minimum window width, release of the system appearance override, actual menu-driven appearance persistence restored in a fresh controller, and browser URL delivery. Real download UI tests passed file checksum, toolbar pause/resume, search filtering, selection preservation, completed details, and failure actions. The Intel native messaging host passed five acceptance groups: private bridge configuration and ping, HTTP batch filename collisions and checksums, live Blob completion and duplicate-session handling, sequence-error cleanup, and unrecognized extension rejection.

The Intel core regression executable also passed all 58 checks through Rosetta, including HTTP range behavior, restart/resume, streaming checksum verification, storage, and browser protocol assertions.

These tests use isolated storage and deterministic local HTTP fixtures. Intel cross-compilation and an Intel executable running through Rosetta are separate from testing on a physical Intel Mac. macOS 13, 14, and other untested releases need testing on those operating systems before version-specific runtime compatibility can be claimed. The minimum target does not support macOS 12 or earlier.

Local reproducible evidence: `build/release-arm64.log`, `build/release-x86_64.log`, `build/release-artifacts.log`, `build/release-intel-smoke.json`, `build/release-intel-e2e.log`, `build/release-intel-native.log`, and `build/release-intel-core.log`. Release hashes are recorded in the attached `release-manifest.json` and `SHA256SUMS` rather than duplicating hashes of an intermediate build here.

Architecture hashes and Intel execution results for each release are recorded in [the compatibility report](test-results/compatibility.json). Reports are regenerated after UI and packaging changes. The ARM UI and browser runtime reports are tracked separately.
