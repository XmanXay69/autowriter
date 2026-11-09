#!/bin/zsh
# Builds AutoWriter.app. Run from anywhere:
#   scripts/build.sh            builds dist/AutoWriter.app
#   scripts/build.sh --install  installs it in /Applications, signed with your
#                               Apple Development certificate so the
#                               Accessibility permission survives updates
#   scripts/build.sh --dmg      makes dist/AutoWriter.dmg to share
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)"/\1/p' project.yml)
APP="dist/AutoWriter.app"

# XcodeGen makes the Xcode project from project.yml; xcodebuild compiles it.
xcodegen generate --quiet
mkdir -p build
if ! xcodebuild -project AutoWriter.xcodeproj -scheme AutoWriter -configuration Release \
        -derivedDataPath build -destination 'platform=macOS' build > build/build.log 2>&1; then
    grep -E "error:" build/build.log | sort -u || tail -30 build/build.log
    echo "Build failed (full log: build/build.log)"
    exit 1
fi
grep -E "warning:" build/build.log | grep -v "appintents" | sort -u || true
rm -rf dist
mkdir -p dist
ditto build/Build/Products/Release/AutoWriter.app "$APP"

# Sign the app. macOS remembers the Accessibility permission by signature.
if [ "${1:-}" = "--install" ]; then
    # Your free "Apple Development" certificate (from signing into Xcode)
    # gives every build the same identity, so you only grant the permission
    # once. Its name contains your Apple ID email, so these builds stay on
    # your Mac and never go on GitHub.
    IDENTITY=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}' || true)
    if [ -n "$IDENTITY" ]; then
        codesign --force --deep --sign "$IDENTITY" "$APP"
    else
        echo "No Apple Development certificate found, so signing ad hoc."
        echo "You'll need to turn Accessibility on again after each update."
        codesign --force --deep --sign - "$APP"
    fi
    codesign --verify --deep --strict "$APP"
    # Close the running copy (if there is one), then replace it.
    if pgrep -qf "AutoWriter.app/Contents/MacOS/AutoWriter"; then
        osascript -e 'quit app "AutoWriter"' 2>/dev/null || true
        sleep 1
        pkill -f "AutoWriter.app/Contents/MacOS/AutoWriter" 2>/dev/null || true
    fi
    rm -rf /Applications/AutoWriter.app
    ditto "$APP" /Applications/AutoWriter.app
    echo "Installed /Applications/AutoWriter.app ($VERSION)"
    exit 0
fi

# For sharing: "ad hoc" signing needs no certificate and holds no personal info.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

if [ "${1:-}" = "--dmg" ]; then
    STAGE=$(mktemp -d)
    ditto "$APP" "$STAGE/AutoWriter.app"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "AutoWriter $VERSION" -srcfolder "$STAGE" -ov -format UDZO dist/AutoWriter.dmg > /dev/null
    rm -rf "$STAGE"
    echo "Built dist/AutoWriter.dmg ($VERSION)"
else
    echo "Built $APP ($VERSION)"
fi
