#!/bin/zsh
set -eu
cd "${0:A:h:h}"
node --test Tests/BrowserIntegration/core.test.js
python3 scripts/browser_test_helpers_checks.py
python3 scripts/fixture_startup_checks.py
python3 scripts/ci_runner_checks.py
scripts/swift.sh run --disable-sandbox DownloadCoreChecks
scripts/package.sh
"build/MacDownloadManager.app/Contents/MacOS/MacDownloadManager" --smoke-test "$PWD/build/ui-smoke.json"
cat build/ui-smoke.json

python3 scripts/ui_e2e.py

qa_directory=$(mktemp -d "$PWD/build/native-browser-checks.XXXXXX")
trap 'rm -rf "$qa_directory"' EXIT
python3 scripts/native_browser_checks.py --app "$PWD/build/MacDownloadManager.app" --directory "$qa_directory"
