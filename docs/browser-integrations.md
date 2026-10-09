# Browser integrations

The download manager, app bridge and native messaging host are native Swift. Browser extensions use browser-required JavaScript WebExtensions. This is an independently implemented macOS application informed by the recorded Windows IDM analysis, with no Tonec affiliation. It is not an official release or a verified 100% feature replica.

## Install

1. Run `scripts/install.sh` and open `~/Applications/IDM.app`. This packages and registers the native host; putting the app outside Documents avoids browser privacy restrictions on that folder.
2. Choose **File → Browser Integrations → Open Setup**. If you move the app, choose **Register Browsers** again.
3. Chromium browsers: open the browser's extensions page, enable developer mode, choose **Load unpacked**, and select the setup page's `chromium` directory.
4. Firefox: use `about:debugging#/runtime/this-firefox` → **Load Temporary Add-on** → the included `firefox/manifest.json`. Temporary add-ons must be reloaded after restarting Firefox. Persistent release installation requires Mozilla signing.
5. In Safari or another browser, copy the provided bookmarklet into a bookmark URL. It hands HTTP/HTTPS links to the app for destination approval.

The setup resources are packaged in `IDM.app/Contents/Resources/BrowserIntegration` and generated in `build/extensions`. Native hosts are registered per user. No browser profile is modified by the extension build.

## Functions

- Download a link, selected links, or a batch through the native engine.
- Select ordinary direct HTTP video/audio sources from the current page.
- Import a live Blob from its originating HTTP/HTTPS tab in bounded 128 KiB chunks with ordered acknowledgements and SHA-256 verification.
- Enable automatic capture explicitly: the extension pauses the original browser download, cancels it after native acceptance, and resumes it if the app rejects or cannot receive it.
- Enable session transfer explicitly, then grant cookie/site permission. Only target-site cookies from the initiating tab’s cookie store are sent. They are kept in Keychain, never job JSON. Cookie and Authorization headers are stripped across origin changes.

If Firefox cannot resume a paused transfer after failed handoff, the extension starts a replacement browser GET download and cancels the original only after that replacement is accepted. It preserves private/container context and avoids recapturing its own replacement. This recovery cannot reconstruct POST bodies or original request headers unavailable in the downloads API. Non-default containers are left with the browser if required cookie permission is missing.

Session sharing requires a known initiating tab. Automatic capture without tab context resumes the browser download instead of guessing a cookie store.

The app reviews destinations before accepting a normal browser download. Browser URL-scheme requests cannot carry session headers. Blob imports cannot resume after their source tab/stream disappears; reimport from the live tab. MediaSource, DRM, expired Blob identifiers and arbitrary pasted browser-local URLs are unsupported.

## Compatibility

| Browser family | Integration | Verification |
| --- | --- | --- |
| Chromium: Chrome, Edge, Brave, Vivaldi, Opera, Arc | MV3 extension and native messaging; registration targets included | Actual Chromium test results recorded below; individual branded browsers require their own acceptance runs |
| Firefox | MV2 WebExtension and native messaging | Actual Firefox test results recorded below |
| Safari | HTTP/HTTPS bookmarklet and native URL handler | Native Safari extension packaging requires full Xcode, which is unavailable on this development Mac |
| Other browsers supporting bookmarks/custom URL schemes | HTTP/HTTPS bookmarklet | Compatibility target; no universal execution claim |

Context-menu/browser integration behavior was researched against [IDM's browser integration documentation](https://www.internetdownloadmanager.com/support/right_click_IE.html). Protocols follow [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) and [Mozilla native messaging](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_messaging). Safari packaging requirements are documented by [Apple](https://developer.apple.com/documentation/safariservices/safari-web-extensions).

## Test commands

```sh
node --test Tests/BrowserIntegration/core.test.js
scripts/test.sh  # includes Node, native host/app acceptance and UI checks
python3 scripts/build_extensions.py --output build/qa-extensions --host-name local.haseebheaven.idmmac.test
python3 scripts/browser_integration_tests.py --help
```

The browser runner uses official testing binaries, temporary profiles, separate app storage and a unique test native host. It verifies resulting files against the deterministic fixture SHA-256. The production extension identity is stable; its public key is tracked, while signing secrets/build output are ignored.

## Executed acceptance: 2026-10-09

[Machine-readable results and binary hashes](test-results/browser-current.json) record actual browser execution against the packaged release app:

| Suite | Result | Scope |
| --- | --- | --- |
| Node extension checks | 19 passed | Validation, permissions, capture, browser recovery and guard behavior |
| Acceptance-helper regression | Passed | Staging/unfinished/missing/prior files rejected; completed final destination required |
| Native core | 58 passed | Protocol, Keychain, streamed Blob lifecycle, engine and Grabber regressions |
| Packaged native host/app | 5 groups passed | Private configuration, native ping, collision-safe batch checksums, ordered Blob cleanup, caller rejection |
| Chrome for Testing 155.0.8059.39 | 12 passed | Real native messaging, HTTP/batch checksums, mixed-link filtering, live/expired Blob handling, direct media discovery/selected HTTP and Blob transfer, capture and missing-host fallback |
| Firefox 157.0.1 | 11 passed | Real native messaging, granted cookie-protected transfer, HTTP/batch/Blob checksums, selected media HTTP/Blob transfer, capture and non-range missing-host replacement recovery |
| AppKit | Passed | Actual pause/resume and SHA-256, search match/no-match states, details, failed-job actions and minimum-width layout |
| Safari | Partial / unverified transfer | Real URL-scheme navigation attempted; save-dialog approval unavailable through automation. Bookmarklet execution blocked by existing JavaScript-from-Apple-Events setting |

Chrome cookie permission UI did not complete the automation path; actual cookie transfer is verified in Firefox, with shared validation covered by Node/core checks. Individually branded Chromium browsers, Firefox private/container recovery and native Safari extension packaging have not received complete acceptance runs. No user browser privacy setting was changed to make these tests pass.

The browser QA runner requires Python `websocket-client`, official Chrome for Testing, Firefox and geckodriver. Firefox UI automation uses geckodriver's `--allow-system-access` flag only in the owned temporary test profile. Diagnostic extension pages are staged privately by the runner; production resources do not contain them.

OpenQodex supplies code review; it does not execute these browser tests. Current measured coverage and review results are recorded in [verification](verification.md).
