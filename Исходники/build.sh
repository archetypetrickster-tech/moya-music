#!/bin/zsh
set -eu
cd "$(dirname "$0")"
destination_app="../Моя музыка.app"
build_work="$(mktemp -d "${TMPDIR:-/tmp}/moyamusic-build.XXXXXX")"
cleanup() {
    if [[ -d "$build_work/previous.app" && ! -e "$destination_app" ]]; then
        mv "$build_work/previous.app" "$destination_app" || { print -u2 -- "Предыдущая сборка: $build_work/previous.app"; return 1; }
    fi
    rm -rf "$build_work"
}
trap cleanup EXIT
APP="$build_work/Моя музыка.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
for build_arch in arm64 x86_64; do
    xcrun swiftc main.swift QueueView.swift Diagnostics.swift WindowBehavior.swift SourceSwitch.swift -O -target "$build_arch-apple-macosx13.0" -framework AppKit -framework WebKit -o "$build_work/MoyaMusic-$build_arch"
    xcrun swiftc headphones.swift -O -target "$build_arch-apple-macosx13.0" -framework AppKit -framework CoreAudio -o "$build_work/Headphones-$build_arch"
done
xcrun lipo -create "$build_work/MoyaMusic-arm64" "$build_work/MoyaMusic-x86_64" -output "$APP/Contents/MacOS/MoyaMusic"
xcrun lipo -create "$build_work/Headphones-arm64" "$build_work/Headphones-x86_64" -output "$APP/Contents/Helpers/MoyaMusicHeadphones"
codesign --force --sign - "$APP/Contents/Helpers/MoyaMusicHeadphones"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp bridge.js "$APP/Contents/Resources/bridge.js"
cp queue-inspect.js "$APP/Contents/Resources/queue-inspect.js"
cp queue-engine.js "$APP/Contents/Resources/queue-engine.js"
mkdir -p "$APP/Contents/Resources/Icons"
cp Icons/*.png Icons/*.txt Icons/*.json "$APP/Contents/Resources/Icons/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MoyaMusic</string>
<key>CFBundleIdentifier</key><string>ru.ninesquares.moyamusic</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleName</key><string>Моя музыка</string>
<key>CFBundleDisplayName</key><string>Моя музыка</string>
<key>CFBundleVersion</key><string>710</string>
<key>CFBundleShortVersionString</key><string>0.7.10</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
if [[ -e "$destination_app" ]]; then mv "$destination_app" "$build_work/previous.app"; fi
mv "$APP" "$destination_app"
echo "Собрано: $destination_app"
