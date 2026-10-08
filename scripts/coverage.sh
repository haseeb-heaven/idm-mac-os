#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build/coverage/profiles
rm -f build/coverage/profiles/*.profraw(N)
scripts/swift.sh build --disable-sandbox --scratch-path build/coverage --enable-code-coverage
export LLVM_PROFILE_FILE="$PWD/build/coverage/profiles/%p-%m.profraw"
build/coverage/debug/IDMCoreChecks
build/coverage/debug/IDMMac --smoke-test "$PWD/build/coverage/ui-smoke.json"
python3 scripts/ui_e2e.py "$PWD/build/coverage/debug/IDMMac"
xcrun llvm-profdata merge -sparse build/coverage/profiles/*.profraw -o build/coverage/combined.profdata
xcrun llvm-cov report build/coverage/debug/IDMCoreChecks -instr-profile build/coverage/combined.profdata -ignore-filename-regex 'Tests/|\.build/|build/' | tee build/coverage/core-report.txt
xcrun llvm-cov report build/coverage/debug/IDMMac -instr-profile build/coverage/combined.profdata -ignore-filename-regex 'Sources/IDMCore/|Tests/|\.build/|build/' | tee build/coverage/ui-report.txt
xcrun llvm-cov show build/coverage/debug/IDMCoreChecks -instr-profile build/coverage/combined.profdata -ignore-filename-regex 'Tests/' -format=html -output-dir build/coverage/html/core
xcrun llvm-cov show build/coverage/debug/IDMMac -instr-profile build/coverage/combined.profdata -ignore-filename-regex 'Sources/IDMCore/' -format=html -output-dir build/coverage/html/ui
