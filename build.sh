#!/bin/sh
# Builds Lightdown.app into ./build. Pass --install to copy it to /Applications.
set -e
cd "$(dirname "$0")"

swift build -c release --product Lightdown
BIN="$(swift build -c release --show-bin-path)/Lightdown"

APP=build/Lightdown.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Lightdown"
cp Info.plist "$APP/Contents/Info.plist"
# Stamp the build so About shows which commit it came from.
COMMIT="$(git rev-parse --short HEAD)"
git diff --quiet HEAD || COMMIT="$COMMIT-dirty"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" \
    -c "Add :LightdownCommit string $COMMIT" "$APP/Contents/Info.plist"
cp Resources/* "$APP/Contents/Resources/"
cp LICENSE NOTICE "$APP/Contents/Resources/"
# macOS ties privacy grants (such as Documents or Downloads folder access) to the
# signature. An ad-hoc signature changes with every build, so each rebuild is a new app
# to macOS. A self-signed code signing certificate named "ak-dev" keeps the signature
# stable (README, Signing). Set LOCAL_SIGN_NAME to use a certificate with another name.
LOCAL_SIGN_NAME=${LOCAL_SIGN_NAME:-ak-dev}
LOCAL_ID=$(security find-identity -p codesigning 2>/dev/null \
    | awk -v name="\"$LOCAL_SIGN_NAME\"" 'index($0, name) { print $2; exit }' || true)
if [ -n "$LOCAL_ID" ]; then
    codesign --force --sign "$LOCAL_ID" "$APP"
    echo "Signed with \"$LOCAL_SIGN_NAME\""
else
    codesign --force --sign - "$APP"
    echo "Ad-hoc signed: no \"$LOCAL_SIGN_NAME\" certificate, so folder access prompts return after every rebuild"
fi
echo "Built $APP"

if [ "$1" = "--install" ]; then
    rm -rf /Applications/Lightdown.app
    cp -R "$APP" /Applications/
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Lightdown.app
    echo "Installed to /Applications/Lightdown.app"
fi
