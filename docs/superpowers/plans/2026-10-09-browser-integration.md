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

- [ ] Add tests that reject oversize/truncated frames and injected headers:
```swift
try XCTAssertThrowsError(try NativeMessageFrame.encode(Data(count:1048577)))
try XCTAssertThrowsError(try BrowserLink(url:"https://example.com/x",headers:["Cookie":"a=1\r\nHost:evil"]).validate())
```
- [ ] Implement bounded Codable requests, safe URL/filename checks and framed messages.
- [ ] Add optional browserSourceURL to jobs without breaking old SQLite JSON decoding.
- [ ] Persist transport headers in a separate Keychain service; pass them into engine requests and clear sensitive headers on cross-origin redirects.
- [ ] Test streamed file ordering, declared lengths, collision preservation and abort cleanup.
- [ ] Run scripts/swift.sh run --disable-sandbox IDMCoreChecks; commit tested core changes.

## Task 2: Native app and browser host

Files: Sources/IDMBrowserHost/main.swift, Sources/IDMMac/BrowserBridgeServer.swift, BrowserIntegrationCoordinator.swift, App.swift, MainWindowController.swift; Package.swift; scripts/package.sh.

Interfaces: BrowserBridgeServer(handler: @MainActor (BrowserRequest) async -> BrowserResponse); MainWindowController.queueBrowserDownload and browser-import job updates; IDMBrowserHost stdio frames.

- [ ] Bind listener to 127.0.0.1 and write a 0600 random-token configuration.
- [ ] Implement host request validation, caller allowlist, app launch, bounded socket reads and response framing.
- [ ] Implement AppKit destination/batch review, native jobs and streamed-import lifecycle.
- [ ] Register idm-mac URL events; validate untrusted URL-scheme payloads and ignore credential fields.
- [ ] Package host executable and extension resources; expose Browser Integrations in the native menu.
- [ ] Test forged tokens, malformed messages, review cancellation and app startup; package and run native UI checks; commit.

## Task 3: Browser extensions and real QA

Files: integrations/shared/core.js, background.js, popup.html/js, Chromium/Firefox manifests; scripts/build_extensions.py, browser_integration_tests.py; browser test fixtures.

Interfaces: background nativeRequest(BrowserRequest) -> Promise<BrowserResponse>; runtime content messages bind blob sessions to the initiating tab; generated manifests share a checked extension identity.

- [ ] Build context-menu link, selection/batch and direct-media actions; permission-gated session context.
- [ ] Add opt-in downloads.onCreated capture with pause, successful native cancel, and failure resume.
- [ ] Stream actual Blob data from its owning tab through persistent native messaging in 128 KiB chunks.
- [ ] Add a toolbar popup with status, capture/session settings, current-link actions and visible errors.
- [ ] Generate universal bookmarklet handoff and browser installation resources.
- [ ] Run Node protocol/action tests and isolated real Chromium/Firefox/Safari-handoff checks with full file hashes. Record unsupported environments explicitly.
- [ ] Commit tested browser implementation.

## Task 4: SDLC and publication

Files: README.md, docs/browser-integration.md, docs/parity.md, docs/verification.md, AGENTS.md; measured reports.

- [ ] Run scripts/test.sh, scripts/coverage.sh, opt-in release 5 GiB/memory assertion and browser QA.
- [ ] Review the complete change using OpenQodex; fix findings and rerun affected checks.
- [ ] Update browser support, source/native provenance and test evidence without a 100% parity claim.
- [ ] Commit reports and push develop; verify remote commit and clean worktree; launch the packaged app.
