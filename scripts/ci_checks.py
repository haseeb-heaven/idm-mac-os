#!/usr/bin/env python3
"""Run existing verification stages with bounded process groups and visible logs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'build/IDM.app'


def execute(command, timeout):
    print('+ ' + ' '.join(map(str, command)), flush=True)
    process = subprocess.Popen(command, cwd=ROOT, start_new_session=True)
    try:
        code = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        print(f'ERROR: stage command exceeded {timeout} seconds; terminating its process group', flush=True)
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        raise SystemExit(124)
    if code:
        raise SystemExit(code)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stage', choices=['extensions', 'core', 'package', 'ui', 'native', 'proof'])
    stage = parser.parse_args().stage
    print(f'BEGIN {stage}: {platform.machine()} / {platform.mac_ver()[0]}', flush=True)
    started = time.monotonic()
    if stage == 'extensions':
        execute(['node', '--test', 'Tests/BrowserIntegration/core.test.js'], 90)
        execute([sys.executable, 'scripts/browser_test_helpers_checks.py'], 90)
        execute([sys.executable, 'scripts/fixture_startup_checks.py'], 30)
        execute([sys.executable, 'scripts/ci_runner_checks.py'], 30)
    elif stage == 'core':
        execute(['scripts/swift.sh', 'run', '--disable-sandbox', 'IDMCoreChecks'], 360)
    elif stage == 'package':
        execute(['scripts/package.sh'], 600)
    elif stage == 'ui':
        execute([str(APP / 'Contents/MacOS/IDMMac'), '--smoke-test', str(ROOT / 'build/ui-smoke.json')], 60)
        print((ROOT / 'build/ui-smoke.json').read_text(), flush=True)
        execute([sys.executable, 'scripts/ui_e2e.py'], 90)
    elif stage == 'native':
        with tempfile.TemporaryDirectory(prefix='native-browser-checks.', dir=ROOT / 'build') as directory:
            execute([sys.executable, 'scripts/native_browser_checks.py', '--app', str(APP), '--directory', directory], 120)
            report = json.loads((Path(directory) / 'report.json').read_text())
            (ROOT / 'build/native-browser-report.json').write_text(json.dumps(report, indent=2) + '\n')
    else:
        binaries = [APP / 'Contents/MacOS' / name for name in ['IDMMac', 'IDMBrowserHost']]
        for target in [APP, *binaries]:
            execute(['codesign', '--verify', '--strict', str(target)], 30)
        proof = {'runner': os.environ.get('RUNNER_NAME'), 'architecture': platform.machine(),
                 'macOS': platform.mac_ver()[0], 'commit': os.environ.get('GITHUB_SHA'),
                 'version': json.loads((ROOT / 'version.json').read_text()), 'binaries': []}
        for binary in binaries:
            arch = subprocess.check_output(['lipo', '-archs', str(binary)], text=True, timeout=10).strip()
            proof['binaries'].append({'name': binary.name, 'architectures': arch,
                                      'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()})
        (ROOT / 'build/ci-proof.json').write_text(json.dumps(proof, indent=2) + '\n')
        execute(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(APP), 'build/IDM-tested.zip'], 60)
    print(f'PASS {stage}: {time.monotonic() - started:.1f} seconds', flush=True)


if __name__ == '__main__':
    main()
