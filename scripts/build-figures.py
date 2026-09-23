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

# ---- The pasta cast. Each one swaps the sprout's torso and head for its own shapes. ----

GLOW = "#FF7A59"  # the sprout's yellow glow disappears on pasta, so pasta glows coral


def lines(xs, y_top, y_bottom, color, width=1.3, wave=0.0):
    """Vertical ridges or strands. y_top/y_bottom can be numbers or functions of x."""
    out = []
    for x in xs:
        y1 = y_top(x) if callable(y_top) else y_top
        y2 = y_bottom(x) if callable(y_bottom) else y_bottom
        if wave:
            d, y, flip, step = f"M{x} {y1:.1f}", y1, 1, 4.0
            while y + step <= y2:
                d += f" Q{x + wave * flip:.1f} {y + step / 2:.1f} {x} {y + step:.1f}"
                y, flip = y + step, -flip
        else:
            d = f"M{x} {y1:.1f} L{x} {y2:.1f}"
        out.append(f'<path d="{d}" stroke="{color}" stroke-width="{width}" opacity="0.8"/>')
    return "".join(out)


def ruffled(x1, y1, x2, y2, fill, amp=1.8, step=4.5):
    """A lasagna sheet: straight top and bottom, wavy ruffled sides."""
    d = f"M{x1} {y1} L{x2} {y1}"
    y, n = y1, 0
    while y + step <= y2 + 0.01:
        d += f" Q{x2 + amp:.1f} {y + step / 2:.1f} {x2} {y + step:.1f}"
        y += step
    d += f" L{x1} {y:.1f}"
    while y - step >= y1 - 0.01:
        d += f" Q{x1 - amp:.1f} {y - step / 2:.1f} {x1} {y - step:.1f}"
        y -= step
    return f'<path d="{d} Z" fill="{fill}" stroke="none"/>'


def band(x1, x2, y, h, fill):
    """A wavy layer of sauce or cheese across the sheet."""
    d = f"M{x1} {y}"
    for i, x in enumerate(range(x1, x2, 4)):
        d += f" Q{x + 2} {y + (-1.2 if i % 2 else 1.2)} {x + 4} {y}"
    d += f" L{x2} {y + h}"
    for i, x in enumerate(range(x2, x1, -4)):
        d += f" Q{x - 2} {y + h + (1.2 if i % 2 else -1.2)} {x - 4} {y + h}"
    return f'<path d="{d} Z" fill="{fill}" stroke="none"/>'


def rigatoni_parts():
    lift, pasta, hole, ridge = 6, "#EDBB5F", "#B9852E", "#CF9640"
    xs = (38.5, 43, 48, 53, 57.5)
    body = (f'<path data-part="body" d="M40 {29 - lift} L56 {29 - lift} Q61 {29 - lift} 61 {34 - lift} L61 57 Q61 62 56 62 L40 62 Q35 62 35 57 L35 {34 - lift} Q35 {29 - lift} 40 {29 - lift} Z" fill="{pasta}" stroke="none"/>'
            + lines(xs, 25, 60, ridge))
    head = (f'<rect x="35" y="{16 - lift}" width="26" height="27" rx="5" fill="{pasta}" stroke="none"/>'
            + lines(xs, 21.6 - lift, 43 - lift, ridge)
            + f'<ellipse cx="48" cy="{18.8 - lift}" rx="10.5" ry="2.6" fill="{hole}" stroke="none"/>')
    return body, head, lift


def spaghetti_parts():
    lift, pasta, strand = 4, "#F2D07E", "#D5A54A"
    xs = (39, 43.5, 48, 52.5, 57)
    top = 29 - lift
    body = (f'<path data-part="body" d="M35 {top} L61 {top} L61 57 Q61 62 56 62 L40 62 Q35 62 35 57 Z" fill="{pasta}" stroke="none"/>'
            + lines(xs, top + 2, 60, strand, 1.2, wave=1.1))
    dome = lambda x: top - (13 ** 2 - (x - 48) ** 2) ** 0.5 + 2.5
    curl = f"M49 {17 - lift} C51 {8 - lift} 60 {7 - lift} 61 {12 - lift} C62 {17 - lift} 55 {18 - lift} 56 {13 - lift}"
    head = (f'<path d="M35 {top} A13 13 0 0 1 61 {top} L61 {43 - lift} L35 {43 - lift} Z" fill="{pasta}" stroke="none"/>'
            + lines(xs, dome, 43 - lift, strand, 1.2, wave=1.1)
            + f'<path d="{curl}" stroke="{strand}" stroke-width="4"/><path d="{curl}" stroke="{pasta}" stroke-width="2.4"/>')
    return body, head, lift


def penne_parts():
    lift, pasta, hole, ridge = 6, "#EEBF62", "#B5812B", "#CC933D"
    xs = (38.5, 43, 48, 53, 57.5)
    slant_top = lambda x: (18 - lift) - 8 * (x - 35) / 26          # cut from low-left to high-right
    slant_bottom = lambda x: 65 - 7 * (x - 35) / 26
    body = (f'<path data-part="body" d="M35 {29 - lift} L61 {29 - lift} L61 58 L35 65 Z" fill="{pasta}" stroke="none"/>'
            + lines(xs, 29 - lift, lambda x: slant_bottom(x) - 2.5, ridge))
    head = (f'<path d="M35 {slant_top(35)} L61 {slant_top(61)} L61 {43 - lift} L35 {43 - lift} Z" fill="{pasta}" stroke="none"/>'
            + lines(xs, lambda x: slant_top(x) + 4, 43 - lift, ridge)
            + f'<ellipse cx="48" cy="{slant_top(48) + 0.5:.1f}" rx="11.5" ry="2.4" fill="{hole}" stroke="none" transform="rotate(-17 48 {slant_top(48) + 0.5:.1f})"/>')
    return body, head, lift


def lasagna_parts():
    lift, pasta, sauce, cheese = 4, "#EDC36B", "#C9492F", "#F7EAD0"
    top = 29 - lift
    body = (ruffled(32, top, 64, 62, pasta).replace("<path ", '<path data-part="body" ', 1)
            + band(32, 64, 36, 3.5, sauce) + band(32, 64, 45, 3, cheese) + band(32, 64, 53, 3.5, sauce))
    head = (ruffled(32, 16 - lift, 64, 43 - lift, pasta)
            + band(32, 64, 16 - lift, 3.2, sauce) + band(32, 64, 16 - lift + 3.2, 1.8, cheese))
    return body, head, lift


def pasta(name, parts):
    body, head, lift = parts()

    def make(svg: str) -> str:
        assert svg.count(SPROUT_BODY) == 1 and svg.count(SPROUT_HEAD) == 1
        svg = TOPPER.sub("", svg)
        svg = svg.replace(SPROUT_BODY, body).replace(SPROUT_HEAD, head)
        svg = svg.replace('<g data-part="face">', f'<g data-part="face" transform="translate(0 -{lift})">')
        svg = svg.replace('id="cp-glow"', f'id="cp-glow-{name}"').replace("url(#cp-glow)", f"url(#cp-glow-{name})")
        svg = svg.replace('stop-color="#FFC857"', f'stop-color="{GLOW}"')
        return svg.replace("<svg ", f'<svg data-character="{name}" ', 1)
    return make


# id -> (label, generator). The sprout is the hand-drawn base and stays as is.
CHARACTERS = {
    "rigatoni": ("Toni the Rigatoni", pasta("rigatoni", rigatoni_parts)),
    "spaghetti": ("Sammy the Spaghetti", pasta("spaghetti", spaghetti_parts)),
    "penne": ("Patty the Penne", pasta("penne", penne_parts)),
    "lasagna": ("Lenny the Lasagna", pasta("lasagna", lasagna_parts)),
    "sprout": ("Sprout", lambda s: s),
}
EXTRAS = [("wave", "Wave (intro)"), ("hang", "Hang (entrance)")]  # generated for every character too

grids = {}
for name, (label, make) in CHARACTERS.items():
    cells = []
    items = [(Path(ex["figure"]).name, ex["name"], ex["spec"]) for ex in exercises]
    items += [(f"{extra}.svg", title, "") for extra, title in EXTRAS]
    for file, title, spec in items:
        base = figs / file
        svg = make(base.read_text()) if base.exists() else '<div class="missing"></div>'
        if name != "sprout" and base.exists():
            out = figs / name / file
            out.parent.mkdir(exist_ok=True)
            out.write_text(svg)
        cells.append(f"""    <figure>
      <div class="tile">{svg}</div>
      <figcaption><b>{html.escape(title)}</b><span>{html.escape(spec)}</span></figcaption>
    </figure>""")
    grids[name] = "\n".join(cells)

first = next(iter(CHARACTERS))
seg = "\n".join(
    f'      <button data-character="{n}" aria-pressed="{str(n == first).lower()}">{html.escape(l)}</button>'
    for n, (l, _) in CHARACTERS.items())
grid_html = "\n".join(
    f'  <div class="grid" data-grid="{n}"{"" if n == first else " hidden"}>\n{g}\n  </div>' for n, g in grids.items())

page = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Noodle figures</title>
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
  <div class="eyebrow">Noodle</div>
  <h1>The Noodle cast</h1>
  <p class="lede">All eight moves at 96px, looping. Arrows show which way to move, the glow shows what should feel the stretch. Peak pose freezes each one at the moment that matters.</p>
  <div class="controls">
    <div class="seg" role="group" aria-label="Character">
{seg}
    </div>
    <button id="theme" aria-pressed="false">Dark mode</button>
    <button id="zoom" aria-pressed="false">Zoom</button>
    <button id="pause" aria-pressed="false">Pause</button>
    <button id="peak" aria-pressed="false">Peak pose</button>
  </div>
{grid_html}
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
