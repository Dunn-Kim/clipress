#!/bin/sh
# Clipress.app을 만든다. SwiftUI 매크로 플러그인이 CLT에 없어 Xcode 툴체인으로 빌드한다(xcode-select 설정은 건드리지 않음).
set -eu
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift build -c release --product Clipress

app=Clipress.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Clipress" "$app/Contents/MacOS/"
# 아이콘을 바꾸려면 scripts/make-icon.swift를 고치고 `swift scripts/make-icon.swift`로 다시 만든다.
cp assets/AppIcon.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Clipress</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.clipress</string>
    <key>CFBundleName</key><string>Clipress</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
echo "$app"
