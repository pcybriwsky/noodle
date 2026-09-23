#!/bin/bash
# Dev loop: regenerate figures, rebuild, swap the new build into the installed app, restart it.
# Never touches settings.json (run install.sh once for that).
#   scripts/dev.sh          rebuild and restart
#   scripts/dev.sh show     ...then show a card
#   scripts/dev.sh intro    ...then replay Toni's intro
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Noodle.app"
LEGACY="$APP_DIR/ClaudePosture.app"   # pre-rename install
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

python3 "$ROOT/scripts/build-figures.py" >/dev/null
BUILT="$("$ROOT/scripts/build-app.sh" | tail -1)"
pkill -x ClaudePosture 2>/dev/null || true

if [[ -d "$LEGACY" ]]; then "$LSREGISTER" -u "$LEGACY" 2>/dev/null || true; rm -rf "$LEGACY"; mkdir -p "$APP"; fi
if [[ -d "$APP" ]]; then
  rm -rf "$APP"
  ditto "$BUILT" "$APP"
  "$LSREGISTER" -u "$BUILT" 2>/dev/null || true
  "$LSREGISTER" -f "$APP"
else
  echo "Not installed yet, running the build copy. Run scripts/install.sh to install for real."
  APP="$BUILT"
fi

open -g "$APP"
sleep 1.5
case "${1:-}" in
  show)  open -g 'claudeposture://show' ;;
  intro) open -g 'claudeposture://intro' ;;
esac
echo "Running $APP"
