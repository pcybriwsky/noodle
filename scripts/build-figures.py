#!/usr/bin/env python3
"""Builds character variants of the figures and app/figures.html, a preview with the SVGs inlined.

The hand-drawn figures in app/Resources/figures/*.svg are the sprout character. Other characters
are generated from them by swapping the tagged parts (body, head shape, topper, glow), so every
character shares the same motions. Variants land in app/Resources/figures/<character>/<id>.svg.
"""
import html
import json
import math
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


def bend_curve(x, top_y, angle, pivot=(48, 41), bottom_y=47, k=4.5):
    """A line that leaves the torso straight up at (x, bottom_y) and arrives at the head's line end
    (x, top_y), rotated `angle` degrees around the neck pivot, along the head's own axis."""
    th = math.radians(angle)
    px, py = pivot
    dx, dy = x - px, top_y - py
    tx, ty = px + dx * math.cos(th) - dy * math.sin(th), py + dx * math.sin(th) + dy * math.cos(th)
    ux, uy = math.sin(th), -math.cos(th)          # the head's "up" after tilting
    return (f"M{x:g} {bottom_y} C{x:g} {bottom_y - k:.2f} {tx - ux * k:.2f} {ty - uy * k:.2f} {tx:.2f} {ty:.2f}")


class Pasta:
    """One noodle's shapes. torso(top) draws the body from `top` down to the hips, decor(y1, y2)
    its texture between two heights. Head moves use joint() (tilts) and neck() (slides)."""
    lift = 6
    x1, x2 = 35, 61
    color = "#EDBB5F"

    def torso(self, top, decor_from=None): raise NotImplementedError
    def decor(self, y1, y2): return ""
    def head(self): raise NotImplementedError

    def joint(self, uid, angles, timing):
        r = (self.x2 - self.x1) / 2
        disc = f'<circle cx="48" cy="41" r="{r}" fill="{self.color}" stroke="none"/>'
        bent = self.bent_lines(angles, timing)
        if bent:
            return disc + bent
        return (f'<clipPath id="j{uid}"><circle cx="48" cy="41" r="{r}"/></clipPath>' + disc
                + f'<g clip-path="url(#j{uid})">{self.decor(41 - r, 41 + r)}</g>')

    def bent_lines(self, angles, timing):
        """Ridges or strands that curve from the upright torso into the tilted head, per frame."""
        xs = getattr(self, "xs", None)
        if not xs:
            return ""
        top_y = 43 - self.lift - 0.5            # where the head's lines end
        out = []
        for x in xs:
            frames = [bend_curve(x, top_y, a) for a in angles]
            out.append(f'<path d="{frames[0]}" stroke="{self.line_color}" stroke-width="{self.line_width}" opacity="0.8">'
                       f'<animate attributeName="d" values="{";".join(frames)}" {timing}/></path>')
        return "".join(out)

    def neck_path(self, dx):
        a, b = self.x1 + dx, self.x2 + dx
        return f"M{a:g} 37 C{a:g} 42 {self.x1} 42 {self.x1} 47 L{self.x2} 47 C{self.x2} 42 {b:g} 42 {b:g} 37 Z"

    def neck_decor(self, dxs, timing):
        xs = getattr(self, "xs", None)
        if not xs:
            return ""
        out = []
        for x in xs:
            frames = [f"M{x + dx:g} 37 C{x + dx:g} 42 {x} 42 {x} 47" for dx in dxs]
            out.append(f'<path d="{frames[0]}" stroke="{self.line_color}" stroke-width="{self.line_width}" opacity="0.8">'
                       f'<animate attributeName="d" values="{";".join(frames)}" {timing}/></path>')
        return "".join(out)


class Rigatoni(Pasta):
    lift, color, hole, ridge = 6, "#EDBB5F", "#B9852E", "#CF9640"
    line_width = 1.3

    @property
    def line_color(self): return self.ridge
    xs = (38.5, 43, 48, 53, 57.5)

    def decor(self, y1, y2): return lines(self.xs, y1, y2, self.ridge)

    def torso(self, top, decor_from=None):
        if top <= 29 - self.lift:   # standing: soft shoulders, hidden under the head anyway
            t = top
            shape = f"M40 {t} L56 {t} Q61 {t} 61 {t + 5} L61 57 Q61 62 56 62 L40 62 Q35 62 35 57 L35 {t + 5} Q35 {t} 40 {t} Z"
        else:
            shape = f"M35 {top} L61 {top} L61 57 Q61 62 56 62 L40 62 Q35 62 35 57 Z"
        return (f'<path data-part="body" d="{shape}" fill="{self.color}" stroke="none"/>'
                + self.decor(max(decor_from or top, 25), 60))

    def head(self):
        l = self.lift
        t, b = 16 - l, 43 - l   # rounded top, square bottom so it meets the neck and torso without a notch
        return (f'<path d="M35 {t + 5} Q35 {t} 40 {t} L56 {t} Q61 {t} 61 {t + 5} L61 {b} L35 {b} Z" fill="{self.color}" stroke="none"/>'
                + self.decor(21.6 - l, 43 - l)
                + f'<ellipse cx="48" cy="{18.8 - l}" rx="10.5" ry="2.6" fill="{self.hole}" stroke="none"/>')



class Spaghetti(Pasta):
    lift, color, strand = 4, "#F2D07E", "#D5A54A"
    line_width = 1.2

    @property
    def line_color(self): return self.strand
    xs = (39, 43.5, 48, 52.5, 57)

    def decor(self, y1, y2): return lines(self.xs, y1, y2, self.strand, 1.2, wave=1.1)

    def torso(self, top, decor_from=None):
        return (f'<path data-part="body" d="M35 {top} L61 {top} L61 57 Q61 62 56 62 L40 62 Q35 62 35 57 Z" fill="{self.color}" stroke="none"/>'
                + self.decor((decor_from or top) + 2, 60))

    def head(self):
        top = 29 - self.lift
        dome = lambda x: top - (13 ** 2 - (x - 48) ** 2) ** 0.5 + 2.5
        curl = f"M49 {17 - self.lift} C51 {8 - self.lift} 60 {7 - self.lift} 61 {12 - self.lift} C62 {17 - self.lift} 55 {18 - self.lift} 56 {13 - self.lift}"
        return (f'<path d="M35 {top} A13 13 0 0 1 61 {top} L61 {43 - self.lift} L35 {43 - self.lift} Z" fill="{self.color}" stroke="none"/>'
                + lines(self.xs, dome, 43 - self.lift, self.strand, 1.2, wave=1.1)
                + f'<path d="{curl}" stroke="{self.strand}" stroke-width="4"/><path d="{curl}" stroke="{self.color}" stroke-width="2.4"/>')


class Penne(Pasta):
    lift, color, hole, ridge = 6, "#EEBF62", "#B5812B", "#CC933D"
    line_width = 1.3

    @property
    def line_color(self): return self.ridge
    xs = (38.5, 43, 48, 53, 57.5)

    def slant_top(self, x): return (18 - self.lift) - 8 * (x - 35) / 26   # cut from low-left to high-right
    def slant_bottom(self, x): return 65 - 7 * (x - 35) / 26

    def decor(self, y1, y2): return lines(self.xs, y1, lambda x: min(y2, self.slant_bottom(x) - 2.5), self.ridge)

    def torso(self, top, decor_from=None):
        return (f'<path data-part="body" d="M35 {top} L61 {top} L61 58 L35 65 Z" fill="{self.color}" stroke="none"/>'
                + self.decor(decor_from or top, 70))

    def head(self):
        st = self.slant_top
        return (f'<path d="M35 {st(35)} L61 {st(61)} L61 {43 - self.lift} L35 {43 - self.lift} Z" fill="{self.color}" stroke="none"/>'
                + lines(self.xs, lambda x: st(x) + 4, 43 - self.lift, self.ridge)
                + f'<ellipse cx="48" cy="{st(48) + 0.5:.1f}" rx="11.5" ry="2.4" fill="{self.hole}" stroke="none" transform="rotate(-17 48 {st(48) + 0.5:.1f})"/>')



class Lasagna(Pasta):
    lift, x1, x2, color, sauce, cheese = 4, 32, 64, "#EDC36B", "#C9492F", "#F7EAD0"
    layers = ((36, 3.5, "sauce"), (45, 3, "cheese"), (53, 3.5, "sauce"))

    def decor(self, y1, y2):
        return "".join(band(32, 64, y, h, getattr(self, c)) for y, h, c in self.layers if y1 <= y and y + h <= y2)

    def torso(self, top, decor_from=None):
        return ruffled(32, top, 64, 62, self.color).replace("<path ", '<path data-part="body" ', 1) + self.decor(decor_from or top, 62)

    def head(self):
        t = 16 - self.lift
        return (ruffled(32, t, 64, 43 - self.lift, self.color)
                + band(32, 64, t, 3.2, self.sauce) + band(32, 64, t + 3.2, 1.8, self.cheese))


NECK_JOINT = re.compile(r'<path data-part="body" data-neck="joint"[^>]*/>\s*<circle data-part="joint"[^>]*/>')
NECK_BRIDGE = re.compile(r'<path data-part="body" data-neck="bridge" d="M35 (\d+) [^"]*"[^>]*/>\s*'
                         r'<path data-part="neck" d="[^"]*" fill="[^"]*" stroke="none">\s*<animate attributeName="d" values="([^"]*)" ([^/]*)/>\s*</path>')
HEAD_TILT = re.compile(r'<g data-part="head">\s*<animateTransform attributeName="transform" type="rotate" values="([^"]*)" ([^/]*)/>')
_uid = [0]


def pasta(name, p):
    def make(svg: str) -> str:
        _uid[0] += 1
        uid = f"{name}{_uid[0]}"
        svg = TOPPER.sub("", svg)
        if NECK_JOINT.search(svg):                       # neck stretch: tilt bends at a round joint
            tilt = HEAD_TILT.search(svg)
            angles = [float(v.split()[0]) for v in tilt.group(1).split(";")]
            svg = NECK_JOINT.sub(lambda m: p.torso(41, decor_from=47 if p.bent_lines([0], '') else None) + p.joint(uid, angles, tilt.group(2)), svg)
        elif (m := NECK_BRIDGE.search(svg)):              # chin tuck: the neck curves as the head slides
            top, values, timing = int(m.group(1)), m.group(2), m.group(3)
            dxs = [float(v.split()[0][1:]) - 35 for v in values.split(";")]
            frames = ";".join(p.neck_path(dx) for dx in dxs)
            neck = (f'<path data-part="neck" d="{p.neck_path(dxs[0])}" fill="{p.color}" stroke="none">'
                    f'<animate attributeName="d" values="{frames}" {timing}/></path>')
            svg = svg.replace(m.group(0), p.torso(top) + neck + p.neck_decor(dxs, timing))
        else:
            assert svg.count(SPROUT_BODY) == 1
            svg = svg.replace(SPROUT_BODY, p.torso(29 - p.lift))
        assert svg.count(SPROUT_HEAD) == 1
        svg = svg.replace(SPROUT_HEAD, p.head())
        svg = svg.replace('<g data-part="face">', f'<g data-part="face" transform="translate(0 -{p.lift})">')
        svg = svg.replace('id="cp-glow"', f'id="cp-glow-{uid}"').replace("url(#cp-glow)", f"url(#cp-glow-{uid})")
        svg = svg.replace('stop-color="#FFC857"', f'stop-color="{GLOW}"')
        return svg.replace("<svg ", f'<svg data-character="{name}" ', 1)
    return make


# id -> (label, generator). The sprout is the hand-drawn base and stays as is.
CHARACTERS = {
    "rigatoni": ("Toni the Rigatoni", pasta("rigatoni", Rigatoni())),
    "spaghetti": ("Sammy the Spaghetti", pasta("spaghetti", Spaghetti())),
    "penne": ("Patty the Penne", pasta("penne", Penne())),
    "lasagna": ("Lenny the Lasagna", pasta("lasagna", Lasagna())),
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
