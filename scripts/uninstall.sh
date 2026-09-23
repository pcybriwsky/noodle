#!/bin/bash
# Removes the two ClaudePosture hooks from ~/.claude/settings.json (with a backup, after showing
# you the diff), the login item, and the app. Leaves everything else in settings.json alone.
#   -y             answer yes to every prompt
#   SKIP_APP=1     only touch settings.json
#   APP_DIR=...    install location (default ~/Applications)
#   CLAUDE_SETTINGS=...  settings file (default ~/.claude/settings.json)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/_hooks.sh"
[[ "${1:-}" == "-y" ]] && ASSUME_YES=1
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/ClaudePosture.app"

if [[ -f "$SETTINGS" ]]; then
  apply_settings_filter "$JQ_UNMERGE" remove
else
  echo "No $SETTINGS, nothing to remove there."
fi

if [[ "${SKIP_APP:-0}" != 1 ]]; then
  if [[ -d "$APP" ]]; then
    open -g 'claudeposture://login-off' 2>/dev/null && sleep 1.5 || true   # the app unregisters its own login item
  fi
  pkill -x ClaudePosture 2>/dev/null || true
  if [[ -d "$APP" ]]; then
    "$LSREGISTER" -u "$APP" 2>/dev/null || true
    rm -rf "$APP"
    echo "Removed $APP"
  fi
  echo "Your config and log are still in ~/.claude-posture. Delete that folder if you don't want them."
fi
