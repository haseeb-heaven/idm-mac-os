# Browser Integration Implementation Plan

> Execute inline using executing-plans, with task checkpoints and reviewed small commits.

**Goal:** Add safe, independently authored browser handoff and browser-local imports to the native macOS download manager.

**Architecture:** WebExtensions communicate through a framed Swift native host and authenticated loopback app bridge. AppKit reviews destinations and persists jobs. A custom URL scheme provides a universal HTTP handoff.

**Tech Stack:** Swift 6, AppKit, Network, Security/Keychain, WebExtensions MV3/MV2, Node test runner, Python browser fixtures.

## Global constraints

- macOS 15 Apple Silicon; existing Swift package has no external runtime dependencies.
- Work on develop; preserve user profiles, jobs and credentials; use isolated browser QA profiles.
- Maximum JSON frame 1 MiB; maximum Blob chunk 128 KiB; maximum batch 200 links.
- Only HTTP/HTTPS network URLs; no CR/LF header values, arbitrary local destinations or cross-origin credential forwarding.
- Native approval precedes browser cancellation; rejected/failed handoff resumes browser downloads.
- Public docs record executed tests, coverage and external Safari packaging limitations.

## Task 1: Protocol and transfer context

Files: Sources/IDMCore/BrowserIntegration.swift, BrowserBlobStore.swift, Credentials.swift, DownloadEngine.swift, HTTPChunkStream.swift, Models.swift; Tests/IDMCoreTests/BrowserTests.swift.

Interfaces: BrowserRequest.validate() throws; NativeMessageFrame.encode(Data) throws -> Data; NativeMessageFrame.extract(inout Data) throws -> Data?; BrowserBlobStore.begin/append/finish/abort; CredentialStore.saveHeaders/headers/deleteHeaders.

- [x] Add tests that reject oversize/truncated frames and injected headers:
```swift
try XCTAssertThrowsError(try NativeMessageFrame.encode(Data(count:1048577)))
try XCTAssertThrowsError(try BrowserLink(url:"https://example.com/x",headers:["Cookie":"a=1\r\nHost:evil"]).validate())
```
- [x] Implement bounded Codable requests, safe URL/filename checks and framed messages.
- [x] Add optional browserSourceURL to jobs without breaking old SQLite JSON decoding.
- [x] Persist transport headers in a separate Keychain service; pass them into engine requests and clear sensitive headers on cross-origin redirects.
- [x] Test streamed file ordering, declared lengths, collision preservation and abort cleanup.
- [x] Run scripts/swift.sh run --disable-sandbox IDMCoreChecks; commit tested core changes.

## Task 2: Native app and browser host

Files: Sources/IDMBrowserHost/main.swift, Sources/IDMMac/BrowserBridgeServer.swift, BrowserIntegrationCoordinator.swift, App.swift, MainWindowController.swift; Package.swift; scripts/package.sh.

Interfaces: BrowserBridgeServer(handler: @MainActor (BrowserRequest) async -> BrowserResponse); MainWindowController.queueBrowserDownload and browser-import job updates; IDMBrowserHost stdio frames.

- [x] Bind listener to 127.0.0.1 and write a 0600 random-token configuration.
- [x] Implement host request validation, caller allowlist, app launch, bounded socket reads and response framing.
- [x] Implement AppKit destination/batch review, native jobs and streamed-import lifecycle.
- [x] Register idm-mac URL events; validate untrusted URL-scheme payloads and ignore credential fields.
- [x] Package host executable and extension resources; expose Browser Integrations in the native menu.
- [x] Test forged tokens, malformed messages, review cancellation and app startup; package and run native UI checks; commit.

## Task 3: Browser extensions and real QA

Files: integrations/shared/core.js, background.js, popup.html/js, Chromium/Firefox manifests; scripts/build_extensions.py, browser_integration_tests.py; browser test fixtures.

Interfaces: background nativeRequest(BrowserRequest) -> Promise<BrowserResponse>; runtime content messages bind blob sessions to the initiating tab; generated manifests share a checked extension identity.

- [x] Build context-menu link, selection/batch and direct-media actions; permission-gated session context.
- [x] Add opt-in downloads.onCreated capture with pause, successful native cancel, and failure resume.
- [x] Stream actual Blob data from its owning tab through persistent native messaging in 128 KiB chunks.
- [x] Add a toolbar popup with status, capture/session settings, current-link actions and visible errors.
- [x] Generate universal bookmarklet handoff and browser installation resources.
- [x] Run Node protocol/action tests and isolated real Chromium/Firefox checks with full file hashes. Safari execution limits are recorded in the verification report.
- [x] Commit tested browser implementation.

## Task 4: SDLC and publication

Files: README.md, docs/browser-integration.md, docs/parity.md, docs/verification.md, AGENTS.md; measured reports.

- [x] Run scripts/test.sh, scripts/coverage.sh, opt-in release 5 GiB/memory assertion and browser QA.
- [x] Review the complete change using OpenQodex; fix findings and rerun affected checks.
- [x] Update browser support, source/native provenance and test evidence without a 100% parity claim.
- [x] Commit reports and push develop; verify remote commit and clean worktree; launch the packaged app.

## User-requested follow-ups

- Refine the AppKit interface into a compact professional desktop layout: monochrome native toolbar, search, restrained sidebar, readable rows and details. Verify actual pause/resume, checksum, search filtering, failed-job actions and minimum window width.
- Extend single-page grabbing to explicit download attributes and extensionless `/download/` endpoints. Verify OpenIGI links against actual current HTML and test the three previously discovered OS endpoints, preserving network failures and exact transfer settings.
- Safari bookmarklet execution, individually branded Chromium browsers and full original-IDM parity remain explicitly unverified where acceptance is unavailable.
