# IDM Mac 0.2.0

An independent native macOS download manager, informed by recorded GhidraMCP and Radare2 MCP analysis of Windows IDM. This is a personal project, not an official Tonec release.

## Changes

- Classic IDM-style toolbar with independently authored colored icons and labeled actions.
- Optional compact Mac toolbar; light, dark and system appearance, with saved preferences.
- Native Apple Silicon, Intel and Universal packages targeting macOS 13 Ventura and newer.
- Chromium/Firefox native messaging, link and batch handoff, direct media selection, live Blob imports, opt-in cookies and automatic capture.
- Faster deterministic HTTP fixture startup and bounded, visible CI stages.

## Downloads

Choose `arm64` for Apple Silicon, `x86_64` for Intel, or `universal` for either processor. Verify the ZIP against `SHA256SUMS`, extract it, then move **IDM Mac.app** to Applications. The packages are ad hoc signed, without Developer ID notarization. If macOS blocks launching, approve the app in System Settings → Privacy & Security after checking its source and checksum.

Browser extensions require loading and native host registration using the packaged setup instructions. Safari supports HTTP bookmarklet handoff; a packaged native Safari extension is not included.

## Validation and limits

See the [compatibility report](https://github.com/haseeb-heaven/idm-mac-os/blob/develop/docs/macos-compatibility.md), [browser acceptance evidence](https://github.com/haseeb-heaven/idm-mac-os/blob/develop/docs/test-results/v020-browser.json), and [release verification](https://github.com/haseeb-heaven/idm-mac-os/blob/develop/docs/verification-v0.2.0.md) for exact architectures, tested systems, checks and review outcomes.

A macOS 13 deployment target does not establish runtime verification of every macOS version. Physical Intel execution, Rosetta execution and cross-compilation are recorded separately. Full IDM feature parity and universal performance parity are not claimed. Expired Blob URLs, MediaSource streams and DRM cannot be imported from pasted URLs.
