#!/bin/zsh
set -eu
cd "${0:A:h:h}"
scripts/package.sh
app_destination="$HOME/Applications/IDM Mac.app"
mkdir -p "$HOME/Applications"
if [[ -e "$app_destination" ]]; then
  existing_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_destination/Contents/Info.plist" 2>/dev/null || true)
  [[ "$existing_identifier" == 'local.haseebheaven.idmmac' ]] || { print -u2 'An unrelated app exists at the installation destination.'; exit 1; }
  backup_destination="$HOME/Applications/IDM Mac.previous-$(date +%Y%m%d-%H%M%S).app"
  mv "$app_destination" "$backup_destination"
  print "Previous app preserved: $backup_destination"
fi
cp -R 'build/IDM Mac.app' "$app_destination"
xattr -cr "$app_destination"
codesign --verify --strict "$app_destination"
"$app_destination/Contents/MacOS/IDMMac" --register-browsers
print "Installed $app_destination"
