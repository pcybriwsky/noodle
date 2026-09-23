#!/bin/bash
# Tests the settings.json merge/unmerge in install.sh / uninstall.sh against temp files only.
# Usage: scripts/test-hooks.sh [settings.json to copy as an extra round-trip fixture]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "${TMPDIR:-/tmp}/posture-hooks.XXXXXX")"
pass=0; fail=0
ok()   { echo "  ok   $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; fail=$((fail+1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }
run()  { CLAUDE_SETTINGS="$1" SKIP_APP=1 "$ROOT/scripts/$2" -y >"$T/out" 2>&1; }
count() { jq --arg c "$2" '[.. | objects | select(.command? == $c)] | length' "$1"; }
P="open -g 'claudeposture://prompt' >/dev/null 2>&1 &"
S="open -g 'claudeposture://stop' >/dev/null 2>&1 &"
nbak() { ls "$1".bak-* 2>/dev/null | wc -l | tr -d ' '; }

echo "missing file"
F="$T/missing/settings.json"
run "$F" install.sh
check "created with both hooks" '[[ $(count "$F" "$P") == 1 && $(count "$F" "$S") == 1 ]]'
check "no backup for a new file" '[[ $(nbak "$F") == 0 ]]'
run "$F" uninstall.sh
check "uninstall leaves {}" '[[ $(jq -c . "$F") == "{}" ]]'

echo "other hooks and settings"
F="$T/other/settings.json"; mkdir -p "$T/other"
cat > "$F" <<'JSON'
{
  "model": "opus",
  "permissions": {
    "allow": [
      "Bash(git status)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "echo hi"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "./guard.sh"
          }
        ]
      }
    ]
  }
}
JSON
cp "$F" "$T/orig.json"
run "$F" install.sh
check "ours added once each" '[[ $(count "$F" "$P") == 1 && $(count "$F" "$S") == 1 ]]'
check "other hooks kept" '[[ $(count "$F" "echo hi") == 1 && $(count "$F" "./guard.sh") == 1 && $(count "$F" "afplay /System/Library/Sounds/Glass.aiff") == 1 ]]'
check "other settings kept" '[[ "$(jq -c "del(.hooks)" "$F")" == "$(jq -c "del(.hooks)" "$T/orig.json")" ]]'
check "backup created and equals original" '[[ $(nbak "$F") == 1 ]] && cmp -s "$(ls "$F".bak-*)" "$T/orig.json"'
cp "$F" "$T/once.json"
sleep 1; run "$F" install.sh
check "second install changes nothing" 'cmp -s "$F" "$T/once.json"'
check "second install says nothing to add" 'grep -q "nothing to add" "$T/out"'
check "second install makes no backup" '[[ $(nbak "$F") == 1 ]]'
run "$F" uninstall.sh
check "round trip is byte-identical" 'cmp -s "$F" "$T/orig.json"'
run "$F" uninstall.sh
check "second uninstall is a no-op" 'cmp -s "$F" "$T/orig.json" && grep -q "nothing to remove" "$T/out"'

echo "our command already inside someone else's group"
F="$T/shared.json"
jq --arg p "$P" '{hooks:{UserPromptSubmit:[{hooks:[{type:"command",command:"echo a"},{type:"command",command:$p}]}]}}' -n > "$F"
cp "$F" "$T/shared-orig.json"
run "$F" install.sh
check "no duplicate prompt hook" '[[ $(count "$F" "$P") == 1 && $(count "$F" "$S") == 1 ]]'
run "$F" uninstall.sh
check "uninstall removes only ours, keeps their group" '[[ $(count "$F" "$P") == 0 && $(count "$F" "echo a") == 1 && $(jq ".hooks.UserPromptSubmit|length" "$F") == 1 ]]'

echo "invalid JSON"
F="$T/bad.json"; echo '{ nope' > "$F"
run "$F" install.sh; rc=$?
check "refuses, nonzero exit, file untouched" '[[ $rc != 0 && $(cat "$F") == "{ nope" && $(nbak "$F") == 0 ]]'

echo "symlinked settings.json"
mkdir -p "$T/link"; echo '{"model":"opus"}' | jq . > "$T/link/real.json"; ln -s "$T/link/real.json" "$T/link/settings.json"
run "$T/link/settings.json" install.sh
check "still a symlink, target updated" '[[ -L "$T/link/settings.json" && $(count "$T/link/real.json" "$P") == 1 ]]'

echo "declining the prompt"
F="$T/decline.json"; echo '{}' > "$F"
echo n | CLAUDE_SETTINGS="$F" SKIP_APP=1 ASSUME_YES=0 script -q /dev/null "$ROOT/scripts/install.sh" >"$T/out" 2>&1 </dev/null || true
check "file unchanged when not confirmed" '[[ $(cat "$F") == "{}" ]]'

if [[ -n "${1:-}" ]]; then
  echo "round trip on a copy of $1"
  SRC="$1"; F="$T/real/settings.json"; mkdir -p "$T/real"; cp "$SRC" "$F"
  run "$F" install.sh; run "$F" install.sh; run "$F" uninstall.sh
  check "byte-identical after install x2 + uninstall" 'cmp -s "$F" "$SRC"'
fi

echo "$pass passed, $fail failed  (temp files in $T)"
[[ $fail == 0 ]]
