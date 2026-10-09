# Browser integration review record

OpenQodex 0.8.1 with the Codex reviewer reviewed actual source snapshots. It performs code review, not runtime browser testing. Runtime checks and their recorded file hashes are linked from [verification](verification.md).

| Review | Scope | Findings and correction |
| --- | --- | --- |
| `0c58babae340` | Complete integration against `98876cf`, 128 changed ranges supplied | Startup URL handoff could be discarded; media context menu bypassed selection. Added bounded queued URL delivery and original-tab media selector with chosen HTTP/Blob transfer tests. |
| `182abc2215d9` | Follow-up against `3de3a4b`, 92 changed ranges supplied | Search could change the selected download through a stale row index. Selection now stores the download UUID independently; the actual AppKit regression tests shifted-row retention and hidden-row deselection. |
| `520e444aa236` | Corrected acceptance helper snapshot, 50 changed ranges supplied | No code defect found in the helper correction; the snapshot still contained old staging-file evidence. Replaced it with fresh final-destination/completed-job results after the review snapshot was taken. |
| `35bae5dbf929` | Final UI/acceptance snapshot, 75 changed ranges supplied | Browser helper could treat a Blob staging file as completed. Acceptance now excludes staging and requires completed native jobs with final destination files; browser checks are repeated after this correction. |

Earlier integration reviews also found batch filtering/collisions, permission patterns and user-gesture timing, the ordinary Blob-anchor route, and approval deadline/durable completion issues. Those were corrected before the acceptance runs.

Raw reports remain in ignored `build/`; proprietary original binaries, signing secrets, browser credentials and bridge tokens are excluded from publication. Reviewer file-read coverage was not recorded by Codex, so supplied changed ranges are not represented as proof that every file was read.

The final published evidence supersedes the earlier staged-file reports. The helper regression rejects staging, unfinished final bytes, missing destinations and prior files; completed final files are accepted. It runs in `scripts/test.sh` without optional browser dependencies. Code-review warnings are recorded as found and corrected, rather than relabeled as a clean full audit.
