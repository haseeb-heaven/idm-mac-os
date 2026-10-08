# IDM macOS reverse engineering plan

## Objective and authorization

The owner reports a licensed IDM copy and requests a personal MacBook port. Reverse engineer the supplied binary first, then implement macOS equivalents of verified behavior. Aim for full feature and visual parity; track gaps explicitly and never claim unverified equivalence.

## Input

- Installer: `/Users/haseeb-mir/Downloads/idman643build15.exe`
- SHA-256: `a902e77169a3e4d8a88ee2ccaab11d3d43ab209483625a3602438ed4a22bbfd9`
- Original stays untouched. Extract analysis copies into ignored `samples/`.
- License keys remain local and must never enter source control or logs.

## Tools and evidence

Use GhidraMCP as the primary decompiler and Radare2 MCP for independent disassembly, imports, sections, references, and function checks. Discover actual exposed tools and local configuration before assuming endpoints or executable paths. Direct stdio MCP clients now reach both real servers; scripts/mcp_client.py handles JSON-RPC. Ghidra uses the project-local .venv and Homebrew Ghidra 12.1.2; r2mcp uses the executable discovered in the local MCP configuration. CLI `/opt/homebrew/bin/rabin2` and `/opt/homebrew/bin/r2` are available; installer triage used rabin2.

Follow the useful principles from `../open-igi/RE.md`: preserve provenance; do not invent addresses, prototypes, calling conventions, structures, or semantics. IGI functions and symbols do not describe IDM.

## Research sequence

1. Record file identity, hash, PE metadata, sections, imports, strings, and installer format.
2. Identify the installer container and extract without executing it. Inventory and hash every payload. Distinguish setup code from the actual download manager.
3. Import application binaries into a dedicated Ghidra project. Record tool versions, analysis settings, program IDs, and analysis completion.
4. Enumerate entry points, functions, strings, resources, imports, cross references, callers, and callees.
5. Trace HTTP requests, range negotiation, segmentation, connection scheduling, retry/backoff, redirects, authentication, proxy handling, pause/resume, persistence, file assembly, queues, scheduling, speed limits, and browser integration.
6. Independently inspect relevant instructions and references with Radare2 MCP. Preserve contradictory findings.
7. Record each finding with binary hash, RVA/VA, image base, tool output, interpretation, confidence, and unresolved questions. Decompiler output alone is a hypothesis.
8. Observe the licensed Windows application in an isolated compatible environment to document screens, state transitions, and download behavior. Never treat installer analysis as application behavior.
9. Build a feature parity matrix linking observed behavior to evidence and macOS implementation status.
10. Choose macOS architecture based on findings; implement the download engine, persistence, interface, incrementally; browser integration remains excluded. Mark Windows-specific behavior requiring a macOS equivalent.
11. Compare the resulting app with the licensed reference across documented scenarios before marking any feature equivalent.

## Deliverables

- `analysis/raw/`: reproducible static output.
- `docs/initial-analysis.md`: triage and limitations.
- `docs/findings/`: function and subsystem evidence.
- `docs/parity.md`: feature coverage.
- `scripts/`: repeatable analysis tooling.
- `Sources/`: macOS implementation once subsystem behavior is established.

## Agent handoff prompt

Continue this personal IDM macOS project. Read RE.md and recorded evidence first. Discover and use the owner's GhidraMCP and Radare2 MCP integrations. Extract and inventory the installer payload, then analyze actual application binaries with Ghidra and independently check findings with radare2. Document the download engine and UI behavior before implementing macOS equivalents. Maintain a complete parity matrix. Continue authorized work autonomously, preserve originals and private credentials, and report real blockers and uncertain findings. Never fabricate tool execution or call an incomplete port a 100% replica.

## Implementation progress

Application extracted, imported and analyzed using GhidraMCP; HTTP range functions decompiled and independently checked with Radare2 MCP. See docs/findings/http-engine.md. CrossOver reference application runs locally. The native implementation, checksum tests, native UI integration checks, and original-IDM speed comparisons are recorded in docs/native-port.md and docs/speed-comparison.md.
