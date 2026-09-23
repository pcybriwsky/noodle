#!/usr/bin/env python3
"""Builds character variants of the figures and app/figures.html, a preview with the SVGs inlined.

The hand-drawn figures in app/Resources/figures/*.svg are the sprout character. Other characters
are generated from them by swapping the tagged parts (body, head shape, topper, glow), so every
character shares the same motions. Variants land in app/Resources/figures/<character>/<id>.svg.
"""
import html
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parent.parent
res = root / "app" / "Resources"
figs = res / "figures"
exercises = json.loads((res / "exercises.json").read_text())

SPROUT_BODY = '<path data-part="body" d="M43 29 L53 29 A8 8 0 0 1 61 37 L61 49 A13 13 0 0 1 48 62 A13 13 0 0 1 35 49 L35 37 A8 8 0 0 1 43 29 Z" fill="#D97757" stroke="none"/>'
SPROUT_HEAD = '<circle cx="48" cy="29" r="13" fill="#D97757" stroke="none"/>'
TOPPER = re.compile(r'\s*<g data-part="topper">.*?</g>', re.S)

PASTA, HOLE, RIDGE = "#EDBB5F", "#B9852E", "#CF9640"
LIFT = 6  # rigatoni torso is taller: head and face sit this much higher than the sprout's


def ridges(y1: float, y2: float) -> str:
    return "".join(
        f'<path d="M{x} {y1} L{x} {y2}" stroke="{RIDGE}" stroke-width="1.3" opacity="0.8"/>'
        for x in (38.5, 43, 48, 53, 57.5)
    )


ZITI_BODY = (
    f'<path data-part="body" d="M40 {29 - LIFT} L56 {29 - LIFT} Q61 {29 - LIFT} 61 {34 - LIFT} L61 57 Q61 62 56 62 L40 62 Q35 62 35 57 L35 {34 - LIFT} Q35 {29 - LIFT} 40 {29 - LIFT} Z" fill="{PASTA}" stroke="none"/>'
    + ridges(25, 60)
)
ZITI_HEAD = (
    f'<rect x="35" y="{16 - LIFT}" width="26" height="27" rx="5" fill="{PASTA}" stroke="none"/>'
    + ridges(21.6 - LIFT, 43 - LIFT)
    + f'<ellipse cx="48" cy="{18.8 - LIFT}" rx="10.5" ry="2.6" fill="{HOLE}" stroke="none"/>'
)


def rigatoni(svg: str) -> str:
    assert svg.count(SPROUT_BODY) == 1 and svg.count(SPROUT_HEAD) == 1
    svg = TOPPER.sub("", svg)
    svg = svg.replace(SPROUT_BODY, ZITI_BODY).replace(SPROUT_HEAD, ZITI_HEAD)
    svg = svg.replace('<g data-part="face">', f'<g data-part="face" transform="translate(0 -{LIFT})">')
    # Yellow glow disappears on pasta, so rigatoni glows coral. Own id so both sets can share a page.
    svg = svg.replace('id="cp-glow"', 'id="cp-glow-rigatoni"').replace("url(#cp-glow)", "url(#cp-glow-rigatoni)")
    svg = svg.replace('stop-color="#FFC857"', 'stop-color="#FF7A59"')
    return svg.replace("<svg ", '<svg data-character="rigatoni" ', 1)


CHARACTERS = {"sprout": lambda s: s, "rigatoni": rigatoni}
EXTRAS = ["wave"]  # non-exercise figures (onboarding), generated for every character too

grids = {}
for name, make in CHARACTERS.items():
    cells = []
    for ex in exercises:
        base = figs / Path(ex["figure"]).name
        svg = make(base.read_text()) if base.exists() else '<div class="missing"></div>'
        if name != "sprout" and base.exists():
            out = figs / name / base.name
            out.parent.mkdir(exist_ok=True)
            out.write_text(svg)
        cells.append(f"""    <figure>
      <div class="tile">{svg}</div>
      <figcaption><b>{html.escape(ex["name"])}</b><span>{html.escape(ex["spec"])}</span></figcaption>
    </figure>""")
    for extra in EXTRAS:
        base = figs / f"{extra}.svg"
        if name != "sprout" and base.exists():
            (figs / name / base.name).write_text(make(base.read_text()))
    grids[name] = "\n".join(cells)

page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Posture figures</title>
<style>
  :root {{
    --bg: #FFFFFF; --tile: #FBF4EF; --fg: #2B2420; --muted: #8A817B; --line: #EDE6E1; --accent: #B85A3A;
    color-scheme: light;
  }}
  :root[data-theme="dark"] {{
    --bg: #161312; --tile: #221D1B; --fg: #F6F1EE; --muted: #A39A94; --line: #2E2825; --accent: #EE9A7A;
    color-scheme: dark;
  }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      --bg: #161312; --tile: #221D1B; --fg: #F6F1EE; --muted: #A39A94; --line: #2E2825; --accent: #EE9A7A;
      color-scheme: dark;
    }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--bg); color: var(--fg); font: 14px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, sans-serif; }}
  main {{ max-width: 960px; margin: 0 auto; padding: 48px 16px 64px; }}
  .eyebrow {{ font-size: 11px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: var(--accent); }}
  h1 {{ font-size: 32px; letter-spacing: -.02em; margin: 6px 0 4px; }}
  p.lede {{ color: var(--muted); margin: 0 0 24px; max-width: 560px; }}
  .controls {{ display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 28px; align-items: center; }}
  .seg {{ display: inline-flex; padding: 3px; gap: 2px; background: var(--tile); border: 1px solid var(--line); border-radius: 10px; margin-right: 8px; }}
  .seg button {{ border: 0; background: transparent; }}
  button {{ font: inherit; font-size: 13px; font-weight: 500; color: var(--fg); background: var(--tile); border: 1px solid var(--line); border-radius: 8px; padding: 6px 12px; cursor: pointer; }}
  button[aria-pressed="true"] {{ background: var(--fg); color: var(--bg); border-color: var(--fg); }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 24px 20px; }}
  .grid[hidden] {{ display: none; }}
  figure {{ margin: 0; }}
  .tile {{ background: var(--tile); border-radius: 16px; height: 150px; display: grid; place-items: center; color: var(--fg); }}
  .tile svg {{ width: 96px; height: 96px; transition: transform .2s; }}
  body.zoom .tile {{ height: 260px; }}
  body.zoom .tile svg {{ transform: scale(2.2); }}
  figcaption {{ display: flex; flex-direction: column; margin-top: 10px; }}
  figcaption span {{ color: var(--muted); font-size: 13px; }}
  .missing {{ width: 72px; height: 72px; border-radius: 50%; border: 1.5px dashed var(--line); }}
</style>
</head>
<body>
<main>
  <div class="eyebrow">claude-posture</div>
  <h1>Toni the Rigatoni</h1>
  <p class="lede">All eight moves at 96px, looping. Arrows show which way to move, the glow shows what should feel the stretch. Peak pose freezes each one at the moment that matters.</p>
  <div class="controls">
    <div class="seg" role="group" aria-label="Character">
      <button data-character="rigatoni" aria-pressed="true">Toni the Rigatoni</button>
      <button data-character="sprout" aria-pressed="false">Sprout</button>
    </div>
    <button id="theme" aria-pressed="false">Dark mode</button>
    <button id="zoom" aria-pressed="false">Zoom</button>
    <button id="pause" aria-pressed="false">Pause</button>
    <button id="peak" aria-pressed="false">Peak pose</button>
  </div>
  <div class="grid" data-grid="rigatoni">
{grids["rigatoni"]}
  </div>
  <div class="grid" data-grid="sprout" hidden>
{grids["sprout"]}
  </div>
</main>
<script>
  const root = document.documentElement, body = document.body;
  const svgs = () => document.querySelectorAll(".tile svg");
  const toggle = (id, fn) => {{
    const b = document.getElementById(id);
    b.addEventListener("click", () => {{ const on = b.getAttribute("aria-pressed") !== "true"; b.setAttribute("aria-pressed", on); fn(on); }});
  }};
  const darkNow = matchMedia("(prefers-color-scheme: dark)").matches;
  document.getElementById("theme").setAttribute("aria-pressed", darkNow);
  toggle("theme", (on) => root.dataset.theme = on ? "dark" : "light");
  toggle("zoom", (on) => body.classList.toggle("zoom", on));
  toggle("pause", (on) => svgs().forEach((s) => on ? s.pauseAnimations() : s.unpauseAnimations()));
  const peaks = {{ "chin-tuck": 1.2, "doorway": 1.8, "scap": 1.3, "walk": 0.3, "t-ext": 1.5, "hip-flexor": 1.8, "neck-side": 1.2, "calf-raise": 0.9 }};
  toggle("peak", (on) => svgs().forEach((s) => {{
    if (on) {{ s.pauseAnimations(); s.setCurrentTime(peaks[s.dataset.figure] || 1); }} else {{ s.setCurrentTime(0); s.unpauseAnimations(); }}
  }}));
  const pick = (name) => {{
    document.querySelectorAll(".seg button").forEach((b) => b.setAttribute("aria-pressed", b.dataset.character === name));
    document.querySelectorAll("[data-grid]").forEach((g) => g.hidden = g.dataset.grid !== name);
    try {{ localStorage.setItem("character", name); }} catch (e) {{}}
  }};
  document.querySelectorAll(".seg button").forEach((b) => b.addEventListener("click", () => pick(b.dataset.character)));
  try {{ const saved = localStorage.getItem("character"); if (saved && document.querySelector(`[data-grid="${{saved}}"]`)) pick(saved); }} catch (e) {{}}
</script>
</body>
</html>
"""

out = root / "app" / "figures.html"
out.write_text(page)
print(out)
