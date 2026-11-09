#!/bin/zsh
# Real-world test: AutoWriter types a tricky sample into a real app, reads it
# back (⌘A, ⌘C) and prints a report. Needs the Accessibility permission.
# Hands off the keyboard and mouse while it runs.
#   scripts/selftest.sh textedit [wpm]   types into a new TextEdit document
#   scripts/selftest.sh docs [wpm]       types into the Google Doc open in your browser, where you click
#   scripts/selftest.sh search [wpm]     opens google.com in Chrome; click the search box; types a search (no Return)
set -euo pipefail
TEST=${1:-textedit}
WPM=${2:-300}
APP=/Applications/AutoWriter.app
[ -d "$APP" ] || APP="$(cd "$(dirname "$0")/.." && pwd)/dist/AutoWriter.app"
REPORT="$(mktemp -t autowriter-selftest).json"

echo "AutoWriter self-test: $TEST at $WPM WPM."
if [ "$TEST" != "textedit" ]; then
    echo "During the 8-second countdown, click where it should type: at the end of your"
    echo "Google Doc's text (in the page itself, not a side panel), or into the search box."
fi
echo "Then hands off the keyboard and mouse until it's done. Clicking away stops the test."
open -n -W "$APP" --args --selftest="$TEST" --wpm="$WPM" --report="$REPORT" --quit
echo "--- steps"
cat "$REPORT.log" 2>/dev/null
echo "--- report"
cat "$REPORT"
echo
