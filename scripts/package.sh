#!/bin/zsh
set -eu
cd "${0:A:h:h}"
architecture=native
if [[ $# -gt 0 ]]; then
  [[ $# == 2 && "$1" == --arch ]] || { print -u2 'Usage: scripts/package.sh [--arch arm64|x86_64|universal]'; exit 2; }
  architecture="$2"
fi
[[ "$architecture" == native || "$architecture" == arm64 || "$architecture" == x86_64 || "$architecture" == universal ]] || exit 2
if [[ "$architecture" == native ]]; then
  scripts/swift.sh build --disable-sandbox -c release --product IDMMac
  scripts/swift.sh build --disable-sandbox -c release --product IDMBrowserHost
  binary_directory=.build/release
  app="$PWD/build/IDM Mac.app"
elif [[ "$architecture" == universal ]]; then
  scripts/package.sh --arch arm64
  scripts/package.sh --arch x86_64
  binary_directory=build/release-targets/universal
  mkdir -p "$binary_directory"
  for product in IDMMac IDMBrowserHost; do
    lipo -create "build/releases/arm64/IDM Mac.app/Contents/MacOS/$product" "build/releases/x86_64/IDM Mac.app/Contents/MacOS/$product" -output "$binary_directory/$product"
  done
  app="$PWD/build/releases/universal/IDM Mac.app"
else
  target_triple="$architecture-apple-macosx13.0"
  scratch_directory="build/release-targets/$architecture"
  scripts/swift.sh build --disable-sandbox -c release --triple "$target_triple" --scratch-path "$scratch_directory" --product IDMMac
  scripts/swift.sh build --disable-sandbox -c release --triple "$target_triple" --scratch-path "$scratch_directory" --product IDMBrowserHost
  binary_directory=$(scripts/swift.sh build -c release --triple "$target_triple" --scratch-path "$scratch_directory" --show-bin-path)
  app="$PWD/build/releases/$architecture/IDM Mac.app"
fi
python3 scripts/build_extensions.py --output build/extensions
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -rf "$app/Contents/Resources/BrowserIntegration"
cp -R build/extensions "$app/Contents/Resources/BrowserIntegration"
cp integrations/identity.json "$app/Contents/Resources/BrowserIntegration/identity.json"
cp version.json "$app/Contents/Resources/version.json"
cp "$binary_directory/IDMBrowserHost" "$app/Contents/MacOS/IDMBrowserHost"
cp "$binary_directory/IDMMac" "$app/Contents/MacOS/IDMMac"
python3 - "$app" <<'PY'
import json, plistlib, sys
from pathlib import Path
v=json.loads(Path('version.json').read_text())
p={'CFBundleExecutable':'IDMMac','CFBundleIdentifier':'local.haseebheaven.idmmac','CFBundleName':'IDM Mac','CFBundleDisplayName':'IDM Mac','CFBundlePackageType':'APPL','CFBundleShortVersionString':v['version'],'CFBundleVersion':v['build'],'LSMinimumSystemVersion':v['minimumMacOS'],'CFBundleURLTypes':[{'CFBundleURLName':'IDM Mac Browser Handoff','CFBundleURLSchemes':['idm-mac']}],'NSPrincipalClass':'NSApplication','NSHighResolutionCapable':True}
with (Path(sys.argv[1])/'Contents/Info.plist').open('wb') as f: plistlib.dump(p,f)
PY
# Sign outside Documents: FileProvider can reattach forbidden Finder metadata.
final_app="$app"
signing_directory=$(mktemp -d /private/tmp/idm-package-sign.XXXXXX)
trap 'rm -rf "$signing_directory"' EXIT
/usr/bin/ditto --norsrc --noextattr "$app" "$signing_directory/IDM Mac.app"
app="$signing_directory/IDM Mac.app"
xattr -cr "$app"
xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
codesign --force --sign - "$app/Contents/MacOS/IDMBrowserHost"
# Documents FileProvider can reattach Finder metadata while a bundle is written.
for signing_attempt in 1 2 3 4 5; do
  xattr -cr "$app"
  xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
  if codesign --force --sign - "$app"; then
    xattr -cr "$app"
    xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
    if codesign --verify --strict "$app"; then break; fi
  fi
  [[ "$signing_attempt" -lt 5 ]] || exit 1
done
codesign --verify --strict "$app/Contents/MacOS/IDMBrowserHost"
/usr/bin/ditto --norsrc --noextattr "$app" "$final_app"
xattr -cr "$final_app"
# Verify the returned bundle's bytes on a clean copy; Documents FileProvider may
# reattach FinderInfo between xattr and codesign even when all signed bytes match.
verification_app="$signing_directory/copied-back-verification.app"
/usr/bin/ditto --norsrc --noextattr "$final_app" "$verification_app"
xattr -cr "$verification_app"
codesign --verify --strict "$verification_app"
print "Built $final_app"
