# IDM 0.2.2

An unofficial native macOS port of Internet Download Manager, informed by recorded GhidraMCP and Radare2 MCP analysis of Windows IDM. This is a personal project, not an official Tonec release.

## Changes

- The browser extension is now named **IDM Extension** and ships in the release: `IDM-Extension-<version>-chromium.zip` works in Chrome, Edge, Brave and every other Chromium-based browser; `IDM-Extension-<version>-firefox.zip` works in Firefox. Safari and other browsers keep the HTTP bookmarklet handoff.
- Extension identity is unchanged (same Chrome ID, same Firefox ID, same native host name), so existing installs and native host registrations keep working.

## Downloads

Choose `arm64` for Apple Silicon, `x86_64` for Intel, or `universal` for either processor for the app, plus the matching `IDM-Extension` zips for your browsers. Verify every ZIP against `SHA256SUMS`, extract the app archive, then move **IDM.app** to Applications. The packages are ad hoc signed, without Developer ID notarization. If macOS blocks launching, approve the app in System Settings → Privacy & Security after checking its source and checksum.

Load the extracted extension folder with Load unpacked (Chromium) or Load Temporary Add-on (Firefox), register the native host from the app's Browser Integrations menu, then enable automatic capture in the extension popup. Firefox temporary installs disappear on browser restart; permanent distribution requires Mozilla signing.

## Credits

Internet Download Manager is made by the original IDM team at Tonec FZE — https://www.internetdownloadmanager.com/. This is an unofficial port with no affiliation or endorsement. If you use Windows, please buy the official IDM license to support the original team.

## Validation and limits

See the [compatibility report](https://github.com/haseeb-heaven/idm-mac-os/blob/develop/docs/macos-compatibility.md) and browser/test evidence for exact architectures, tested systems, checks and review outcomes.

A macOS 13 deployment target does not establish runtime verification of every macOS version. Individually branded Chromium browsers and native Safari extension packaging have not received complete acceptance runs. Full IDM feature parity and universal performance parity are not claimed. Expired Blob URLs, MediaSource streams and DRM cannot be imported from pasted URLs.
