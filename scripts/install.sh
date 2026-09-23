#!/bin/bash
# Builds Noodle.app, copies it to ~/Applications, and adds the two hooks to
# ~/.claude/settings.json (with a backup, after showing you the diff).
#   -y             answer yes to every prompt
#   SKIP_APP=1     only touch settings.json
#   APP_DIR=...    install location (default ~/Applications)
#   CLAUDE_SETTINGS=...  settings file (default ~/.claude/settings.json)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/_hooks.sh"
[[ "${1:-}" == "-y" ]] && ASSUME_YES=1
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Noodle.app"
# Before the rename the app was ClaudePosture.app. Clear it out so only one copy owns the URL scheme.
LEGACY="$APP_DIR/ClaudePosture.app"


if [[ "${SKIP_APP:-0}" != 1 ]]; then
  echo "Building..."
  BUILT="$("$ROOT/scripts/build-app.sh" | tail -1)"
  pkill -x ClaudePosture 2>/dev/null || true
  mkdir -p "$APP_DIR"
  if [[ -d "$LEGACY" ]]; then "$LSREGISTER" -u "$LEGACY" 2>/dev/null || true; rm -rf "$LEGACY"; fi
  rm -rf "$APP"
  ditto "$BUILT" "$APP"
  "$LSREGISTER" -u "$BUILT" 2>/dev/null || true   # so the URL scheme resolves to the installed copy
  "$LSREGISTER" -f "$APP"
  echo "Installed $APP"
fi

apply_settings_filter "$JQ_MERGE" add

if [[ "${SKIP_APP:-0}" != 1 ]]; then
  open -g "$APP"
  if ask "Open Noodle at login?"; then
    sleep 1
    open -g 'claudeposture://login-on'   # the app registers itself, no Automation prompt needed
    echo "Added login item. Toggle it anytime under Settings in the menu bar."
  fi
  echo "Running. Look for the little figure in your menu bar."
fi
