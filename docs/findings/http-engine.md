# Original IDM HTTP engine evidence

Analyzed file: extracted `IDMan.exe`, SHA-256 `e3fc655a335e17a6fdd09a9b315291d0c8863180f0d801e5dd7433c9e56afbd8`, version 6.43 build 15.2. Ghidra 12.1.2 / pyghidra 3.1.0, x86 32-bit Windows compiler specification, image base `0x00400000`.

## Findings

| Address | Observation | Evidence |
|---|---|---|
| `0x006cfa00` | Bounded byte-range request format | Ghidra string and radare2 MCP cross references |
| `0x005ae8e0` | Function constructs bounded and open-ended range request headers using 64-bit offsets | Ghidra decompilation; radare2 verifies instruction sequence at `0x005af215` |
| `0x00581c80` | Case-insensitive response header checks include ETag and Content-Range; locates `bytes ` prefix | Ghidra decompilation |
| `0x00582780` | Parses Content-Length using a 64-bit format and processes Content-Range | Ghidra decompilation; radare2 verifies header comparison at `0x0058289d` |
| `0x0058c7f0` | Large response-processing function references ETag and Last-Modified | Ghidra decompilation and cross references |

These observations support implementing byte-range downloading and response validation. Function prototypes, complete object layouts, segmentation policy, and scheduler behavior remain unverified. The Mac implementation uses native equivalents; it is not a direct binary translation.

## Reproduction

1. Run `.venv/bin/python scripts/extract_installer.py /Users/haseeb-mir/Downloads/idman643build15.exe`.
2. Run `.venv/bin/python scripts/analyze_mcp.py` for initial import.
3. Run `.venv/bin/python scripts/inspect_protocol.py` to persist analysis and export actual callers and decompilation.
4. Inspect `analysis/raw/r2mcp-range-xrefs.json`, `r2mcp-range-call.json`, and `r2mcp-content-range-call.json` for independent instruction evidence.

## Windows reference

Official CrossOver 26.3.0 trial archive hash was checked against Homebrew cask metadata. IDM was installed in the project-local `IDM-Reference` bottle. The running reference main window was captured in ignored `build/idm-reference.png`. It shows Add URL, Resume, Stop, Stop All, Delete, Options, Scheduler, Start Queue, Stop Queue, category tree, and download table. A Tip of the Day dialog was visible. This confirms reference execution and layout observation, not functional parity.
