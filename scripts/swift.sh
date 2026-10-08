#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p build
# Some CLT installations contain stale private SwiftPM interfaces. Use current public
# interfaces in a project-local copy; never modify the system installation.
if [[ ! -d build/swiftpm-libs/ManifestAPI ]]; then
    python3 - <<'PY'
from pathlib import Path
import shutil
source=Path('/Library/Developer/CommandLineTools/usr/lib/swift/pm')
for name in ['ManifestAPI','PluginAPI']:
 if (source/name).exists():shutil.copytree(source/name,Path('build/swiftpm-libs')/name,dirs_exist_ok=True,ignore=shutil.ignore_patterns('*.private.swiftinterface'))
PY
fi
export SWIFTPM_CUSTOM_LIBS_DIR="$PWD/build/swiftpm-libs"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/swiftpm-clean-cache"
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
export SDKROOT="$(xcrun --show-sdk-path)"
exec swift "$@"
