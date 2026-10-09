# MacDownloadManager 0.3.0

A fresh start under a new, independent identity. MacDownloadManager is an open-source download manager for macOS whose workflow is inspired by classic download managers — no affiliation, no shared code, no reverse engineering.

## What changed

- **Complete rebrand**: the app is now **MacDownloadManager** (`MacDownloadManager.app`) with a project-owned icon drawn in code. All code, identifiers, extensions, docs, and scripts were renamed.
- **New identities**: bundle ID, URL scheme (`macdownloadmanager://`), native host name, Chrome/Firefox extension IDs, Keychain service, and app data directory all moved to the new identity.
- **Removed**: all reverse-engineering artifacts, binary analysis, benchmark tooling against third-party software, historical comparisons, and every previous release.
- The browser extension is now **MacDownloadManager Extension**, shipping in the release for Chromium browsers and Firefox as before.

## Fresh-install notes

- Delete any previous app copy, re-register browsers from the app's Browser Integrations menu, and re-enable capture in the extension popup.
- Downloads, Keychain items, and preferences from the old identity are not migrated. Remove the old app data directory if you want a fully clean slate.
- Verify every ZIP against `SHA256SUMS`. Packages are ad hoc signed, without Developer ID notarization.

## Credits

Workflow inspired by the original Internet Download Manager by Tonec FZE — https://www.internetdownloadmanager.com/. If you use Windows, please buy the official IDM license to support the original team. This project shares no code, artwork, or binaries with it.

## Validation and limits

See the [verification record](https://github.com/haseeb-heaven/mac-download-manager/blob/develop/docs/verification.md) for executed checks. A macOS 13 deployment target does not establish runtime verification of every macOS version. Full feature parity with any other product is not claimed. Expired Blob URLs, MediaSource streams and DRM cannot be imported from pasted URLs.
