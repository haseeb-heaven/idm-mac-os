# Passed: no findings

Change 6c7ff9e08f66 against 9aa16c7, 11 files, +462 -42

Blast radius: risk medium \(5 symbols touched, 4 callers in 2 files\)

Counts: no findings, 23 scanner candidates dropped

## Findings \(0\)

No findings on the changed lines.

## Dropped scanner candidates \(23\)

### c1 at scripts/compare\_idm\_speed.py:8: The benchmark imports subprocess to launch fixed local executables without a shell. \(see scripts/compare\_idm\_speed.py:23\)

- **Source:** bandit:B404

### c2 at scripts/compare\_idm\_speed.py:23: The benchmark passes fixed commands and internally selected URLs as separate arguments without a shell. \(see scripts/compare\_idm\_speed.py:23\)

- **Source:** bandit:B603

### c3 at scripts/compare\_idm\_speed.py:35: The benchmark launches a fixed local executable with an internally selected URL without a shell. \(see scripts/compare\_idm\_speed.py:35\)

- **Source:** bandit:B603

### c4 at scripts/compare\_idm\_speed.py:8: The combined imports cause no behavioral problem and match the surrounding script style. \(see scripts/compare\_idm\_speed.py:8\)

- **Source:** ruff:E401

### c5 at scripts/compare\_idm\_speed.py:19: The inline guard correctly rejects an existing benchmark destination. \(see scripts/compare\_idm\_speed.py:19\)

- **Source:** ruff:E701

### c6 at scripts/compare\_idm\_speed.py:25: The inline guard correctly raises an error when the download exceeds its deadline. \(see scripts/compare\_idm\_speed.py:25\)

- **Source:** ruff:E701

### c7 at scripts/compare\_idm\_speed.py:27: The inline context manager correctly hashes the file before closing it. \(see scripts/compare\_idm\_speed.py:27\)

- **Source:** ruff:E701

### c8 at scripts/compare\_idm\_speed.py:30: The inline condition correctly waits only after the launcher exits. \(see scripts/compare\_idm\_speed.py:30\)

- **Source:** ruff:E701

### c9 at scripts/compare\_idm\_speed.py:38: The inline guard correctly rejects failed native downloads or missing success output. \(see scripts/compare\_idm\_speed.py:38\)

- **Source:** ruff:E701

### c10 at scripts/compare\_idm\_speed.py:39: The inline guard correctly rejects downloads whose size differs from the expected size. \(see scripts/compare\_idm\_speed.py:39\)

- **Source:** ruff:E701

### c11 at scripts/compare\_idm\_speed.py:42: The parser statements execute in the required order and cause no behavioral problem. \(see scripts/compare\_idm\_speed.py:42\)

- **Source:** ruff:E702

### c12 at scripts/compare\_idm\_speed.py:43: The inline guard correctly rejects nonpositive trial counts and deadlines. \(see scripts/compare\_idm\_speed.py:43\)

- **Source:** ruff:E701

### c13 at scripts/compare\_idm\_speed.py:44: The statements construct the report directory before creating it. \(see scripts/compare\_idm\_speed.py:44\)

- **Source:** ruff:E702

### c14 at scripts/compare\_idm\_speed.py:49: The inline condition correctly skips cases outside the selected case. \(see scripts/compare\_idm\_speed.py:49\)

- **Source:** ruff:E701

### c15 at scripts/compare\_idm\_speed.py:56: The statements record and save each completed run before printing it. \(see scripts/compare\_idm\_speed.py:56\)

- **Source:** ruff:E702

### c16 at scripts/compare\_idm\_speed.py:57: The inline guard correctly rejects pairs with different checksums. \(see scripts/compare\_idm\_speed.py:57\)

- **Source:** ruff:E701

### c17 at scripts/compare\_idm\_speed.py:58: The inline loop marks both records only after their checksums match. \(see scripts/compare\_idm\_speed.py:58\)

- **Source:** ruff:E701

### c18 at scripts/compare\_idm\_speed.py:61: The statements save the error before propagating the exception. \(see scripts/compare\_idm\_speed.py:61\)

- **Source:** ruff:E702

### c19 at scripts/compare\_idm\_speed.py:63: The inline entry guard correctly invokes main only during direct execution. \(see scripts/compare\_idm\_speed.py:63\)

- **Source:** ruff:E701

### c20 at scripts/http\_fixture.py:15: The statements complete the redirect response before returning. \(see scripts/http\_fixture.py:15\)

- **Source:** ruff:E702

### c21 at scripts/http\_fixture.py:17: The statements reject leaked credentials and stop response processing. \(see scripts/http\_fixture.py:17\)

- **Source:** ruff:E702

### c22 at scripts/http\_fixture.py:59: The inline condition intentionally delays GET headers for the cancellation check. \(see scripts/http\_fixture.py:59\)

- **Source:** ruff:E701

### c23 at scripts/http\_fixture.py:62: The inline condition intentionally expands the bulk payload for the backpressure check. \(see scripts/http\_fixture.py:62\)

- **Source:** ruff:E701

## Coverage

- **Files read:** not recorded by Codex
- **Reads outside the snapshot:** not recorded by Codex
- **Changed ranges given to the reviewer:** 40 of 40
Scanners: 4 scanners ran, 9 had nothing to check

Reviewer: codex 0.160.1, 62 s, 1 turn, 141,459 tokens in, 1,942 out

Made by Qodex: review on every pull request at https://qodex.ai
