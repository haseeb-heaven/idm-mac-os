#!/bin/zsh
set -eu
cd "${0:A:h:h}"
scripts/swift.sh build --disable-sandbox -c release --product IDMMac
scripts/swift.sh build --disable-sandbox -c release --product IDMBrowserHost
python3 scripts/build_extensions.py --output build/extensions
app="$PWD/build/IDM Mac.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
rm -rf "$app/Contents/Resources/BrowserIntegration"
cp -R build/extensions "$app/Contents/Resources/BrowserIntegration"
cp integrations/identity.json "$app/Contents/Resources/BrowserIntegration/identity.json"
cp .build/release/IDMBrowserHost "$app/Contents/MacOS/IDMBrowserHost"
cp .build/release/IDMMac "$app/Contents/MacOS/IDMMac"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>IDMMac</string>
<key>CFBundleIdentifier</key><string>local.haseebheaven.idmmac</string>
<key>CFBundleName</key><string>IDM Mac</string>
<key>CFBundleDisplayName</key><string>IDM Mac</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLName</key><string>IDM Mac Browser Handoff</string><key>CFBundleURLSchemes</key><array><string>idm-mac</string></array></dict></array>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
xattr -d com.apple.FinderInfo "$app" 2>/dev/null || true
codesign --force --sign - "$app/Contents/MacOS/IDMBrowserHost"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
print "Built $app"
