# Noodle

Stretching while Claude is noodling.

![Toni the Rigatoni sliding in with a stretch](docs/demo.gif)
<!-- GIF placeholder: record a card popping up and drop it at docs/demo.gif -->

While Claude Code is busy on a long prompt, a card slides in from the edge of your screen with a quick desk stretch and a little noodle sticker to show you how. Hit Start and your noodle times the set. Pick your pasta: Toni the Rigatoni, Sammy the Spaghetti, Patty the Penne, or Lenny the Lasagna. Quick prompts never trigger a card, and it never steals focus from your terminal or editor.

Works everywhere Claude Code runs hooks: the CLI, the VS Code and Cursor extensions, and the Code tab in Claude Desktop. macOS only.

## Install

```bash
scripts/install.sh
```

It builds `Noodle.app`, copies it to `~/Applications`, and adds two hooks to `~/.claude/settings.json`. You'll see the exact diff and get asked before anything is written, and your old file gets backed up to `settings.json.bak-<timestamp>`. Running it again is safe, it won't add the hooks twice.

It also asks whether to open the app at login (you can flip that later in Settings). First launch, your noodle says hi and walks you through a quick desk setup check.

Needs Xcode command line tools (`swift`) and `jq`.

## How it works

- You send a prompt. If Claude is still working 15 seconds later, a card slides in from the corner, like a notification. Want more of a show? Settings > Entrance > Drop in on a noodle, and your noodle rides a strand of spaghetti down from the menu bar first.
- At most one card every 20 minutes.
- No cards while you're on a call. If any app is using your mic or camera, Toni waits. You can also have him skip busy calendar events.
- Working late? No quiet hours by default, so you still get nudged.
- **Start** runs the timer while your noodle demos the move. When time's up (or you hit Done early) it logs the set, celebrates a little, and gets out of your way. **Snooze** pushes the next one back 10 minutes.
- Ignoring it is fine too. After 20 seconds your noodle peeks over the top of the card once, and after a minute the card drifts off on its own. It stays put while your pointer is on it.
- **How to** opens beginner steps for the move, plus the most common mistake to avoid.
- If Claude finishes while a card is up, it says so, and you can finish your set.
- The menu bar icon shows today's count and has Pause, Show one now, Say hi to Toni, and Settings.
- With Reduce motion on, cards fade in and out instead of sliding, and your noodle skips the peek.

## Settings

Everything lives under **Settings** in the menu bar: focus, character, entrance, how long before a card shows, how often, snooze length, corner, which exercises, holding during calls or calendar events, quiet hours, always show steps, and open at login.

**Focus** picks the rotation: *Tech neck* leans on chin tucks, neck, and upper back. *Tight hips* (anterior pelvic tilt) leans on hip flexors and legs. *General stiffness* is all eight. The intro asks, and you can switch anytime.

Under the hood it's `~/.claude-posture/config.json` (Settings > Edit config file…). Changes apply on the next card, no restart needed.

| key | default | what it does |
|---|---|---|
| `delaySeconds` | `15` | how long a prompt has to run before a card shows |
| `cooldownMinutes` | `20` | minimum gap between cards |
| `snoozeMinutes` | `10` | extra wait after Snooze |
| `position` | `top-right` | `top-right`, `top-left`, `bottom-right`, `bottom-left` |
| `inset` | `16` | distance from the screen edge |
| `quietHours` | off, `22:00` to `07:00` | no cards in this window when `enabled` is true |
| `enabledExercises` | all | ids from `exercises.json`, in the order you want them |
| `character` | `rigatoni` | `rigatoni` (Toni), `spaghetti` (Sammy), `penne` (Patty), `lasagna` (Lenny), or `sprout` |
| `entrance` | `card` | `card` slides in from the screen edge, `noodle` drops in from the menu bar first (top corners, skipped with Reduce motion) |
| `expandSteps` | `false` | open How to on every card, handy while the moves are new |
| `focus` | `all` | `neck`, `hips`, `all`, or `custom` after picking exercises by hand |
| `holdDuringCalls` | `true` | skip cards while any app is using the mic or camera |
| `holdDuringCalendarEvents` | `false` | skip cards during busy calendar events (asks for calendar access) |

State lives next to it in `state.json`, and every card gets a line in `log.jsonl`.

## Add an exercise

1. Add an entry to `app/Resources/exercises.json` with an `id`, `name`, short `instruction`, `spec`, `durationSeconds`, beginner `steps`, and a `tip`.
2. Draw `app/Resources/figures/<id>.svg`. Copy an existing figure and keep the tagged parts (`body`, `head`, `face`, `topper`, `legs`) so every character can be generated from it. Animate with SMIL (`<animate>`, `<animateTransform>`), and use `currentColor` for limbs so dark mode works.
3. Run `scripts/dev.sh show`.

`scripts/build-figures.py` makes the Toni versions from the base drawings and rebuilds `app/figures.html`, a preview page with every move, dark mode, and a peak pose toggle.

## Working on it

```bash
scripts/dev.sh          # rebuild and restart the installed app
scripts/dev.sh show     # ...and show a card
scripts/dev.sh intro    # ...and replay the intro
```

`app/Resources/card.html` opens in a browser as a demo with every move, the peek, the noodle drop, dark mode, Reduce motion, and the intro. Serve `app/` locally so it can load the figures, e.g. `python3 -m http.server -d app`.

## Uninstall

```bash
scripts/uninstall.sh
```

Removes the app and takes out only the two hooks it added, leaving the rest of `settings.json` alone. `~/.claude-posture` stays unless you delete it.

## License

MIT, see [LICENSE](LICENSE).
