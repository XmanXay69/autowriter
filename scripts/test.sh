#!/bin/zsh
# Runs AutoWriter's unit tests (the typing loop, file loading, result
# checking...). They need no permissions and don't open the app.
# Usage: scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild test -project AutoWriter.xcodeproj -scheme AutoWriter -destination 'platform=macOS' \
    -derivedDataPath build 2>&1 | grep -v linkd | grep -E "✘|✔ Test run|Test run with|error:|failed|TEST (SUCCEEDED|FAILED)|Expectation failed|recorded an issue" || true
# The tests build a copy of the app; remove it so macOS's permission check
# only ever sees the one in Applications.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"$LSREGISTER" -u "$PWD/build/Build/Products/Debug/AutoWriter.app" 2>/dev/null || true
rm -rf build/Build/Products/Debug/AutoWriter.app
