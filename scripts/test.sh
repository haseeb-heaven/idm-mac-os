#!/bin/zsh
set -eu
cd "${0:A:h:h}"
scripts/swift.sh run --disable-sandbox IDMCoreChecks
scripts/package.sh
"build/IDM Mac.app/Contents/MacOS/IDMMac" --smoke-test "$PWD/build/ui-smoke.json"
cat build/ui-smoke.json

python3 scripts/ui_e2e.py
