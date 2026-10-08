#!/bin/zsh
set -eu
cd "${0:A:h:h}"
scripts/swift.sh build --disable-sandbox -c release --product IDMMac
app="$PWD/build/IDM Mac.app"
mkdir -p "$app/Contents/MacOS"
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
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
print "Built $app"
