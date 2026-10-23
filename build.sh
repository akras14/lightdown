#!/bin/sh
# Builds Lightdown.app into ./build. Pass --install to copy it to /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Lightdown"

APP=build/Lightdown.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lightdown"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$1" = "--install" ]; then
    rm -rf /Applications/Lightdown.app
    cp -R "$APP" /Applications/
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Lightdown.app
    echo "Installed to /Applications/Lightdown.app"
fi
