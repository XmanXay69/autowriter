#!/bin/zsh
# Runs AutoWriter's unit tests (the typing loop, file loading, result
# checking...). They need no permissions and don't open the app.
# Usage: scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild test -project AutoWriter.xcodeproj -scheme AutoWriter -destination 'platform=macOS' \
    -derivedDataPath build 2>&1 | grep -v linkd | grep -E "✘|✔ Test run|Test run with|error:|failed|TEST (SUCCEEDED|FAILED)|Expectation failed|recorded an issue" || true
