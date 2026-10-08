# Project workflow

Personal native macOS IDM project. Browser integration is excluded.

- Work on feature branches in small commits; push reviewed changes to the private repository.
- Analyze real IDM application binaries using GhidraMCP; independently cross-check with Radare2 MCP. Record hashes, addresses, output, and uncertainty in RE.md and docs. Never use fake backend evidence.
- Keep original installers untouched. Ignore extracted proprietary binaries, keys, credentials, build products, and local analyzer projects.
- Use Swift 6, AppKit, URLSession, SQLite, and Keychain. Target macOS 15 Apple Silicon.
- Run scripts/test.sh for affected changes. Command Line Tools lack XCTest; the executable IDMCoreChecks supplies deterministic assertions and integration tests. Use scripts/swift.sh build for builds. Test downloads against deterministic HTTP fixtures; verify file hashes and restart behavior.
- Package and launch the release app before claiming delivery. Review changes with OpenQodex before pushing. Record incomplete reviews and test limitations honestly.
- Track every feature in docs/parity.md. A feature is equivalent only after reference comparison. Never claim full parity from static analysis alone.
