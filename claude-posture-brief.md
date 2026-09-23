# claude-posture build brief

Build a small macOS tool that shows a desk exercise card while Claude Code is working. Claude Code hooks trigger it, and a tiny native helper app renders it as a floating card above whatever app I'm in.

Read this whole brief first, then start with Phase 0.

## Why it's built this way

- Hooks in `~/.claude/settings.json` are shared across the Claude Code CLI, the VS Code / Cursor extension, and the Claude Desktop Code tab. So one hook config covers every surface.
- Only use `UserPromptSubmit` and `Stop`. They fire reliably everywhere. Do NOT rely on the `Notification` hook, there are reports of it never firing in the VS Code extension.
- Hook stdout for `UserPromptSubmit` gets injected into Claude's context. The hook must print nothing, ever. Redirect all output to /dev/null and background it.
- The visual can't live in the terminal or IDE, since hook output is either swallowed or goes to the model. It has to be an OS-level window. That's also what makes it look identical everywhere.
- Cowork doesn't fire hooks. Out of scope.

## Architecture

```
Claude Code (any surface)
  └─ hook: open -g "claudeposture://prompt"   (UserPromptSubmit)
  └─ hook: open -g "claudeposture://stop"     (Stop)
        │
        ▼
ClaudePosture.app  (Swift, menu bar only, no dock icon)
  ├─ owns all logic (delay, cooldown, rotation, logging)
  └─ NSPanel, non-activating, floating, all Spaces
        └─ WKWebView rendering card.html (HTML + inline SVG + CSS animation)
```

Key decisions, keep these unless something actually blocks you.

- **Hooks stay one-liners.** They just fire a URL scheme with `open -g` (the `-g` keeps focus where it is). If the app isn't running, `open` launches it. No server, no sockets.
- **The app owns the logic**, not a bash script. That way multiple concurrent Claude Code sessions don't race on state files.
- **Non-activating panel.** The card must never steal keyboard focus from my terminal or editor. Use `NSPanel` with `.nonactivatingPanel`, level `.floating`, `collectionBehavior` including `.canJoinAllSpaces` and `.fullScreenAuxiliary`. Buttons must still be clickable.
- **Card UI is HTML/SVG in a WKWebView** so the design is easy to iterate on without recompiling Swift. Bundle `card.html` and the SVGs as resources. Pass exercise data in via `evaluateJavaScript`. JS talks back (Done / Snooze) via `WKScriptMessageHandler`.

## Behavior

- On `prompt` event, start a **delay timer** (default 15s). If a `stop` event arrives before it fires, cancel. This means quick prompts never nag me, only real waits do.
- When the delay fires, show the card only if the **cooldown** has passed since the last card (default 20 min).
- Exercises **rotate in order**, persisted across launches.
- On `stop` while a card is showing, don't dismiss it. Swap the subtitle to something like "Claude's done, finish your set" so I know I can go back.
- Card auto-dismisses after the exercise duration + 30s if ignored (logged as `ignored`).
- **Done** logs `done` and dismisses. **Snooze** logs `snoozed`, dismisses, and pushes the cooldown out 10 min.
- Quiet hours and a global pause toggle in the menu bar menu.

## Config and state

All in `~/.claude-posture/`.

- `config.json` with delay seconds, cooldown minutes, snooze minutes, position (default top-right), inset, quiet hours, enabled exercise ids. Create with defaults on first launch.
- `state.json` with rotation index and last shown timestamp.
- `log.jsonl` with one line per card `{ts, exercise, outcome}`.

Menu bar item shows a small line icon plus today's done count. Menu has Pause for 1 hour, Pause until tomorrow, Show one now, Open config, Quit.

## The card

- About 340 × 132 pt, top-right, 16pt inset, rounded 14pt, subtle shadow.
- Follows system light/dark mode.
- Left, a 96 × 96 animated line figure. Right, the exercise name, the instruction line, and the rep/time spec.
- A thin progress bar or ring showing time left in the set.
- Two buttons, Done and Snooze.
- Small counter like "3 of 8" or today's done count, low emphasis.
- Enter animation is a quick fade + 8pt slide. No bounce, nothing cute.
- No emoji anywhere.

## The figures

Draw these myself as SVG, don't pull from exercise databases (licensing on the popular open ones is murky and they barely cover desk stretches anyway).

- Single-weight line figures, round caps, `stroke="currentColor"` so they theme automatically.
- Each is 2 or 3 keyframe poses, looped with CSS animation at about 1.6s, eased. Animate transforms on limb groups rather than morphing paths where possible.
- Consistent proportions across all eight so they read as one set.
- Readable at 96px. Keep detail minimal, a circle head and simple limbs is plenty.

| id | name | view | motion | spec |
|---|---|---|---|---|
| chin-tuck | Chin tucks | side | head slides straight back and returns | 10 slow reps |
| doorway | Doorway chest stretch | side | forearms on frame, body leans through | 30 sec |
| scap | Scap squeezes | back | shoulder blades pinch together | 15 reps, 2 sec hold |
| walk | Walkaround | side | walking cycle | 2 min |
| t-ext | Thoracic extension | side, seated | hands behind head, upper back arches over chair | 10 reps |
| hip-flexor | Hip flexor stretch | side | split stance, hips push forward | 30 sec each side |
| neck-side | Neck side stretch | front | ear tilts toward shoulder, alternating | 20 sec each side |
| calf-raise | Calf raises | side | heels rise and lower | 20 reps |

## Phases

### Phase 0, mockup in Paper

Use the Paper MCP to mock up the card before writing any app code. Make a frame with the card in light and dark, plus two or three of the figures at 96px, and a variant showing the post-stop "Claude's done" state. Show me and wait for my OK before Phase 1. If the Paper MCP isn't connected, tell me and stop.

### Phase 1, the app

- Swift package or Xcode project under `app/`, buildable from the command line (`xcodebuild` or `swift build`, whichever is simpler for a menu bar app with a URL scheme and bundled resources).
- Register the `claudeposture://` URL scheme in Info.plist. `LSUIElement` true.
- Implement the panel, the webview card, and all behavior above.
- Build the figures in `app/Resources/figures/` and preview them all on one `figures.html` page I can open in a browser.

### Phase 2, install

- `scripts/install.sh` builds the app, copies it to `~/Applications`, and merges the two hooks into `~/.claude/settings.json`.
- The merge must use `jq`, back up the existing file first to `settings.json.bak-<timestamp>`, and never clobber other hooks or settings. Idempotent, running it twice doesn't duplicate entries.
- Show me the diff of settings.json and ask before writing it.
- `scripts/uninstall.sh` reverses it cleanly.
- Optional, offer to add the app as a Login Item.

Hook entries to merge in:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "open -g 'claudeposture://prompt' >/dev/null 2>&1 &" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "open -g 'claudeposture://stop' >/dev/null 2>&1 &" } ] }
    ]
  }
}
```

### Phase 3, README

Short. What it is, install, config options, how to add an exercise, uninstall. A GIF placeholder at the top.

## Done means

- [ ] Sending a prompt that runs longer than the delay shows the card, a quick one doesn't
- [ ] Card never steals focus from the terminal, VS Code, or Cursor
- [ ] Card shows on the active Space, including over a full-screen app
- [ ] Works from CLI, VS Code extension, Cursor, and the Claude Desktop Code tab
- [ ] Two Claude sessions at once don't produce two cards
- [ ] Nothing the hook does ever appears in Claude's context
- [ ] Done, Snooze, and ignored all log correctly
- [ ] Light and dark mode both look right
- [ ] install.sh is idempotent and uninstall.sh leaves settings.json as it was

## Style notes for anything you write me (README, UI copy)

Casual and concise. No em-dashes.
