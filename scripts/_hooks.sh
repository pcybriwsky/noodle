# Shared by install.sh and uninstall.sh. Source it, don't run it.
# Env: CLAUDE_SETTINGS overrides the settings path (handy for testing on a copy).

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
PROMPT_CMD="open -g 'claudeposture://prompt' >/dev/null 2>&1 &"
STOP_CMD="open -g 'claudeposture://stop' >/dev/null 2>&1 &"
BUNDLE_ID="com.ngenart.claudeposture"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Adds one {hooks:[{type,command}]} group per event, unless that command is already there anywhere.
JQ_MERGE='
def add($ev; $cmd):
  if any(.hooks[$ev][]?; any(.hooks[]?; (.command? // null) == $cmd)) then .
  else .hooks[$ev] = ((.hooks[$ev] // []) + [{hooks: [{type: "command", command: $cmd}]}]) end;
add("UserPromptSubmit"; $p) | add("Stop"; $s)'

# Removes exactly our command. Drops a group/event array/hooks object only if removing ours emptied it.
JQ_UNMERGE='
def rm($ev; $cmd):
  def ours: (.hooks | type) == "array" and any(.hooks[]; (.command? // null) == $cmd);
  if (.hooks | type) == "object" and (.hooks[$ev] | type) == "array" and any(.hooks[$ev][]; ours) then
    .hooks[$ev] |= map(if ours then (.hooks |= map(select((.command? // null) != $cmd))) | select(.hooks | length > 0) else . end)
    | if (.hooks[$ev] | length) == 0 then del(.hooks[$ev]) else . end
    | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end;
rm("UserPromptSubmit"; $p) | rm("Stop"; $s)'

ask() {  # ask "Question?" -> 0 on yes. ASSUME_YES=1 or -y answers yes.
  [[ "${ASSUME_YES:-0}" == 1 ]] && return 0
  local ans=""
  read -r -p "$1 [y/N] " ans </dev/tty || true
  [[ "$ans" =~ ^[Yy] ]]
}

# apply_settings_filter <jq filter> <verb>: shows a diff, asks, backs up, writes.
apply_settings_filter() {
  local filter="$1" verb="$2" cur="" src new
  command -v jq >/dev/null || { echo "jq is required (brew install jq)."; return 1; }
  [[ -f "$SETTINGS" ]] && cur="$(cat "$SETTINGS")"
  src="$cur"; [[ -z "$(tr -d '[:space:]' <<<"$cur" | head -c 1)" ]] && src='{}'
  if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$src"; then
    echo "$SETTINGS isn't a JSON object, leaving it alone."; return 1
  fi
  new="$(jq --arg p "$PROMPT_CMD" --arg s "$STOP_CMD" "$filter" <<<"$src")" || return 1
  if [[ "$new" == "$(jq . <<<"$src")" ]]; then
    echo "settings.json: nothing to $verb."; return 0
  fi
  echo "Changes to $SETTINGS:"
  diff -u --label "settings.json" --label "settings.json (new)" <(printf '%s' "$cur${cur:+$'\n'}") <(printf '%s\n' "$new") || true
  if ! ask "Write these changes?"; then echo "Skipped settings.json."; return 0; fi
  if [[ -f "$SETTINGS" ]]; then
    local bak="$SETTINGS.bak-$(date +%Y%m%d-%H%M%S)" n=1
    while [[ -e "$bak" ]]; do bak="${bak%-[0-9]}-$n"; n=$((n+1)); done   # never overwrite a backup
    cp -p "$SETTINGS" "$bak" && echo "Backed up to $bak"
  else
    mkdir -p "$(dirname "$SETTINGS")"
  fi
  printf '%s\n' "$new" > "$SETTINGS"   # write through, so a symlinked settings.json stays a symlink
  echo "Updated $SETTINGS"
}
