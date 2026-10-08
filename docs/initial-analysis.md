# Initial installer analysis

Source: local downloaded installer. Static analysis performed with rabin2; raw JSON is in `analysis/raw/`.

- SHA-256: `a902e77169a3e4d8a88ee2ccaab11d3d43ab209483625a3602438ed4a22bbfd9`.
- Windows GUI PE32, x86, little endian.
- Preferred image base: `0x00400000`.
- rabin2 reports an overlay and a signature. Signature authenticity has not been verified.
- Metadata is installer evidence; it does not establish IDM download engine behavior.

Next: identify and extract the installer container, inventory application payloads, connect GhidraMCP and Radare2 MCP, and start application analysis.
