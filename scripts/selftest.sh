#!/bin/zsh
# Real-world test: AutoWriter types a tricky sample into a real app, reads it
# back (⌘A, ⌘C) and prints a report. Needs the Accessibility permission.
# Hands off the keyboard and mouse while it runs.
#   scripts/selftest.sh textedit [wpm]   types into a new TextEdit document
#   scripts/selftest.sh docs [wpm]       types at the end of the Google Doc open in your browser
#   scripts/selftest.sh search [wpm]     opens google.com in Chrome and types a search (no Return)
set -euo pipefail
TEST=${1:-textedit}
WPM=${2:-300}
APP=/Applications/AutoWriter.app
[ -d "$APP" ] || APP="$(cd "$(dirname "$0")/.." && pwd)/dist/AutoWriter.app"
REPORT="$(mktemp -t autowriter-selftest).json"

echo "AutoWriter self-test: $TEST at $WPM WPM. Hands off the keyboard and mouse until it's done..."
open -n -W "$APP" --args --selftest="$TEST" --wpm="$WPM" --report="$REPORT" --quit
cat "$REPORT"
echo
