# Passed: no findings

Change cb8e8baaf94b against 993b45d, 20 files, +388 -18

Blast radius: risk medium \(1 symbol touched, 2 callers in 1 file\)

Counts: no findings, 15 scanner candidates dropped

## Findings \(0\)

No findings on the changed lines.

## Dropped scanner candidates \(15\)

### c1 at scripts/coverage.sh:1: The script intentionally uses zsh, including zsh path modifiers and glob qualifiers. \(see scripts/coverage.sh:1\)

- **Source:** shellcheck:SC1071

### c2 at scripts/real\_download\_checks.py:3: The script uses subprocess for explicit download verification commands without shell evaluation. \(see scripts/real\_download\_checks.py:14\)

- **Source:** bandit:B404

### c3 at scripts/real\_download\_checks.py:14: The local verification script intentionally resolves curl through the user's executable search path. \(see scripts/real\_download\_checks.py:14\)

- **Source:** bandit:B607

### c4 at scripts/real\_download\_checks.py:14: The command uses fixed arguments and hardcoded URLs without shell evaluation. \(see scripts/real\_download\_checks.py:14\)

- **Source:** bandit:B603

### c5 at scripts/real\_download\_checks.py:19: The command invokes the local check executable with hardcoded URLs and a computed checksum. \(see scripts/real\_download\_checks.py:15\)

- **Source:** bandit:B603

### c6 at scripts/ui\_e2e.py:3: The script uses subprocess to launch the local fixture and native verification executable. \(see scripts/ui\_e2e.py:5\)

- **Source:** bandit:B404

### c7 at scripts/ui\_e2e.py:5: The command invokes the current Python interpreter with a fixed local fixture path. \(see scripts/ui\_e2e.py:5\)

- **Source:** bandit:B603

### c8 at scripts/ui\_e2e.py:9: The local test runner intentionally accepts an executable path and passes arguments without shell evaluation. \(see scripts/ui\_e2e.py:9\)

- **Source:** bandit:B603

### c9 at scripts/http\_fixture.py:49: The compact conditional follows existing fixture formatting and correctly creates the oversized payload. \(see scripts/http\_fixture.py:49\)

- **Source:** ruff:E701

### c10 at scripts/http\_fixture.py:50: The compact conditional follows existing fixture formatting and correctly creates 510 links. \(see scripts/http\_fixture.py:50\)

- **Source:** ruff:E701

### c11 at scripts/real\_download\_checks.py:3: The combined imports affect formatting only and match existing script conventions. \(see scripts/real\_download\_checks.py:3\)

- **Source:** ruff:E401

### c12 at scripts/real\_download\_checks.py:17: The single-line context manager computes the checksum and closes the reference file correctly. \(see scripts/real\_download\_checks.py:17\)

- **Source:** ruff:E701

### c13 at scripts/real\_download\_checks.py:21: The statements intentionally record and print each result sequentially. \(see scripts/real\_download\_checks.py:21\)

- **Source:** ruff:E702

### c14 at scripts/real\_download\_checks.py:22: The compact conditional correctly removes the reference file only when it exists. \(see scripts/real\_download\_checks.py:22\)

- **Source:** ruff:E701

### c15 at scripts/ui\_e2e.py:3: The combined imports affect formatting only and match existing script conventions. \(see scripts/ui\_e2e.py:3\)

- **Source:** ruff:E401

## Coverage

- **Files read:** not recorded by Codex
- **Reads outside the snapshot:** not recorded by Codex
- **Changed ranges given to the reviewer:** 44 of 44
Scanners: 5 scanners ran, 8 had nothing to check

Reviewer: codex 0.160.1, 47 s, 1 turn, 158,969 tokens in, 1,374 out

Made by Qodex: review on every pull request at https://qodex.ai
