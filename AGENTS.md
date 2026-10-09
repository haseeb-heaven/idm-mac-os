# Project workflow

Independent open-source macOS download manager. No reverse engineering of third-party software: no disassembly, no decompilation, no execution of proprietary binaries, no bundled third-party artwork. Browser integration is authorized. Track actual browser support and executed tests explicitly.

- Work on feature branches in small commits; push reviewed changes to the public repository on develop; publish only independently authored code and project-owned assets, never third-party binaries, artwork, or credentials.
- Use Swift 6, AppKit, URLSession, SQLite, and Keychain. Target macOS 13+ on Apple Silicon and Intel; publish architecture-specific and Universal packages. Record runtime testing separately from deployment targets.
- Run scripts/test.sh for affected changes. Command Line Tools lack XCTest; the executable DownloadCoreChecks supplies deterministic assertions and integration tests. Use scripts/swift.sh build for builds. Test downloads against deterministic HTTP fixtures; verify file hashes and restart behavior.
- Package and launch the release app before claiming delivery. Review changes with OpenQodex before pushing. Record incomplete reviews and test limitations honestly.
- Track feature status in docs/parity.md. Never claim equivalence with any other product.
