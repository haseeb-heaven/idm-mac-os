#!/bin/zsh
set -eu
cd "${0:A:h:h}"
scripts/package.sh
target_dir="${1:-/Applications}"
app_destination="$target_dir/MacDownloadManager.app"
mkdir -p "$target_dir"
pkill -f "$app_destination" 2>/dev/null || true
if [[ -e "$app_destination" ]]; then
  existing_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_destination/Contents/Info.plist" 2>/dev/null || true)
  [[ -z "$existing_identifier" || "$existing_identifier" == 'local.haseebheaven.macdownloadmanager' ]] || { print -u2 'An unrelated app exists at the installation destination.'; exit 1; }
  rm -rf "$app_destination"
fi
cp -R 'build/MacDownloadManager.app' "$app_destination"
xattr -cr "$app_destination"
codesign --verify --strict "$app_destination"
"$app_destination/Contents/MacOS/MacDownloadManager" --register-browsers || true
touch "$app_destination"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$app_destination" 2>/dev/null || true
print "Installed to $app_destination"
