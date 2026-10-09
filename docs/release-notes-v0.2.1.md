# IDM 0.2.1

An unofficial native macOS port of Internet Download Manager, informed by recorded GhidraMCP and Radare2 MCP analysis of Windows IDM. This is a personal project, not an official Tonec release.

## Changes

- The app is now named **IDM** (`IDM.app`) instead of “IDM Mac” — window title, menus, About panel, installer, packages and docs.
- About panel and docs now credit the original IDM team and link the official site.
- Optional local app-icon override in packaging (`build/local-icon/IDMMac.icns`, extracted from the owner's licensed installer); vendor artwork is never committed.
- Firefox media-selector hardening: activate the tab and wait for a nonzero viewport before checking choices.

## Downloads

Choose `arm64` for Apple Silicon, `x86_64` for Intel, or `universal` for either processor. Verify the ZIP against `SHA256SUMS`, extract it, then move **IDM.app** to Applications. The packages are ad hoc signed, without Developer ID notarization. If macOS blocks launching, approve the app in System Settings → Privacy & Security after checking its source and checksum.

Browser extensions require loading and native host registration using the packaged setup instructions. Safari supports HTTP bookmarklet handoff; a packaged native Safari extension is not included.

## Credits

Internet Download Manager is made by the original IDM team at Tonec FZE — https://www.internetdownloadmanager.com/. This is an unofficial port with no affiliation or endorsement. If you use Windows, please buy the official IDM license to support the original team.

## Validation and limits

See the [compatibility report](https://github.com/haseeb-heaven/idm-mac-os/blob/develop/docs/macos-compatibility.md) and browser/test evidence for exact architectures, tested systems, checks and review outcomes.

A macOS 13 deployment target does not establish runtime verification of every macOS version. Physical Intel execution, Rosetta execution and cross-compilation are recorded separately. Full IDM feature parity and universal performance parity are not claimed. Expired Blob URLs, MediaSource streams and DRM cannot be imported from pasted URLs.
