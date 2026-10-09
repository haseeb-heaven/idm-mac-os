# Browser integration design

The user authorizes browser integrations, develop-based implementation, builds, executed tests, review, commits and pushes. This supersedes the former browser-integration exclusion. Existing main remains the release branch.

## Scope

A Swift/AppKit native app and Swift native-messaging executable provide reviewed HTTP/HTTPS download handoff, batch links, optional session-cookie/referrer context, direct media selection, and streaming browser-local Blob imports. Independently authored Chromium MV3 and Firefox WebExtensions provide context menus, toolbar actions and opt-in interception. A universal bookmarklet hands HTTP/HTTPS links to the native URL handler in Safari and other browsers. Safari-native extension packaging requires full Xcode; this machine only has Command Line Tools. No native Safari-extension test or universal browser parity claim is made without execution.

## Boundary and workflow

Native messaging uses four-byte little-endian lengths and bounded JSON frames. A loopback-only native app listener authenticates the host using a random token in a user-only config file. The host launches the app when necessary. HTTP jobs are acknowledged only after user destination approval and persistence. Capture pauses a browser download first, cancels it only after native acceptance, and resumes it on failure or cancellation.

Session transfer is opt-in, requires browser cookie/site permission, and applies only to the requested URL. Headers enter Keychain, never SQLite or logs. Cookie and Authorization headers are removed across origin changes. Browser-local Blob files stream from the original tab in bounded chunks; ordering, declared lengths and collision checks precede final assembly. Expired blobs, MediaSource/DRM streams and unsupported web pages produce explicit errors rather than pretending to be downloadable files.

A URL-scheme handoff is untrusted and always requires native destination review. It accepts HTTP/HTTPS links only and cannot import cookies or arbitrary local paths. Browser extensions are JavaScript because browsers require WebExtensions; the macOS app, bridge and downloader remain native Swift.

## Validation

Core tests cover frame limits/truncation, request validation, header injection/origin boundaries, Keychain session storage, blob ordering/size/cleanup/collisions and backward-compatible jobs. JavaScript tests exercise link extraction, capture fallback and native responses. Actual isolated browser tests verify extension-to-host-to-app file checksums, batch links, blob streaming, auth and failure fallback. Existing core, UI, packaging, large-file and measured coverage checks remain required. OpenQodex reviews changed code before push. Public docs distinguish executed browser tests from compatibility targets and external packaging requirements.
