"""The Codex icon set (my-website src/data/icons.ts), read and flattened for native drawing.

Each icon is drawn on a 24-unit grid as parts: a heavy `stroke`, a fine `hair`, or a solid `fill`;
parts marked `detail` are left out of the small (caption) cut. Native code gets every path as
absolute move / line / cubic / close commands (arcs and quadratics turned into cubics here), so
SwiftUI needs no SVG parser. Kotlin keeps the original path data, which Compose parses itself.
"""
import math
import re
from pathlib import Path

ICON_RE = re.compile(r"^  (\w+): \{\n    title: '((?:[^'\\]|\\.)*)',\n    why: '((?:[^'\\]|\\.)*)',\n    parts: \[\n(.*?)\n    \],\n  \},", re.M | re.S)
PART_RE = re.compile(r"([shf])\('([^']*)'(, true)?\)")
WEIGHT = {"s": "stroke", "h": "hair", "f": "fill"}


def read_icons(path: Path):
    text = path.read_text()
    icons = []
    for m in ICON_RE.finditer(text):
        name, title, why, body = m.groups()
        parts = [{"w": WEIGHT[w], "d": d, "detail": bool(detail)} for w, d, detail in PART_RE.findall(body)]
        icons.append({"name": name, "title": title.replace("\\'", "'"), "why": why.replace("\\'", "'"), "parts": parts})
    declared = re.findall(r"^  (\w+): \{$", text, re.M)
    if [i["name"] for i in icons] != declared:
        raise SystemExit(f"icons.ts changed shape: read {len(icons)} of {len(declared)} icons")
    return icons


TOKEN = re.compile(r"[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?")
ARGS = {"M": 2, "L": 2, "H": 1, "V": 1, "C": 6, "S": 4, "Q": 4, "T": 2, "A": 7, "Z": 0}


def _arc(x1, y1, rx, ry, phi, large, sweep, x2, y2):
    """SVG arc to cubic segments (SVG 1.1 implementation notes F.6)."""
    if rx == 0 or ry == 0:
        return [("L", x2, y2)]
    rx, ry = abs(rx), abs(ry)
    p = math.radians(phi)
    cp, sp = math.cos(p), math.sin(p)
    dx, dy = (x1 - x2) / 2, (y1 - y2) / 2
    x1p, y1p = cp * dx + sp * dy, -sp * dx + cp * dy
    lam = x1p**2 / rx**2 + y1p**2 / ry**2
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx**2 * ry**2 - rx**2 * y1p**2 - ry**2 * x1p**2
    den = rx**2 * y1p**2 + ry**2 * x1p**2
    co = math.sqrt(max(0.0, num / den)) * (-1 if large == sweep else 1)
    cxp, cyp = co * rx * y1p / ry, -co * ry * x1p / rx
    cx, cy = cp * cxp - sp * cyp + (x1 + x2) / 2, sp * cxp + cp * cyp + (y1 + y2) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
    dt = ang((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(1, math.ceil(abs(dt) / (math.pi / 2) - 1e-9))
    step = dt / n
    k = 4 / 3 * math.tan(step / 4)
    out = []
    for i in range(n):
        a1, a2 = t1 + i * step, t1 + (i + 1) * step
        c1, s1, c2, s2 = math.cos(a1), math.sin(a1), math.cos(a2), math.sin(a2)
        pts = [(c1 - k * s1, s1 + k * c1), (c2 + k * s2, s2 - k * c2), (c2, s2)]
        seg = []
        for ex, ey in pts:
            ex, ey = ex * rx, ey * ry
            seg += [cp * ex - sp * ey + cx, sp * ex + cp * ey + cy]
        out.append(("C", *seg))
    return out


def flatten(d: str):
    """SVG path data -> [('M',x,y) | ('L',x,y) | ('C',x1,y1,x2,y2,x,y) | ('Z',)], absolute."""
    toks = TOKEN.findall(d)
    out, i = [], 0
    x = y = sx = sy = 0.0
    lastc = lastq = None  # reflected control points
    cmd = None
    while i < len(toks):
        if re.fullmatch(r"[A-Za-z]", toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in "Zz":
                out.append(("Z",))
                x, y = sx, sy
                lastc = lastq = None
                continue
        up, rel = cmd.upper(), cmd.islower()
        n = ARGS[up]
        a = [float(v) for v in toks[i:i + n]]
        i += n
        if up == "A":
            ex, ey = a[5] + (x if rel else 0), a[6] + (y if rel else 0)
            out += _arc(x, y, a[0], a[1], a[2], int(a[3]), int(a[4]), ex, ey)
            x, y = ex, ey
            lastc = lastq = None
            continue
        ox, oy = (x, y) if rel else (0.0, 0.0)
        if up == "M":
            x, y = a[0] + ox, a[1] + oy
            sx, sy = x, y
            out.append(("M", x, y))
            cmd = "l" if rel else "L"  # later pairs are lines
            lastc = lastq = None
        elif up in "LHV":
            if up == "L":
                x, y = a[0] + ox, a[1] + oy
            elif up == "H":
                x = a[0] + (x if rel else 0)
            else:
                y = a[0] + (y if rel else 0)
            out.append(("L", x, y))
            lastc = lastq = None
        elif up in "CS":
            if up == "C":
                c1 = (a[0] + ox, a[1] + oy)
                c2, e = (a[2] + ox, a[3] + oy), (a[4] + ox, a[5] + oy)
            else:
                c1 = (2 * x - lastc[0], 2 * y - lastc[1]) if lastc else (x, y)
                c2, e = (a[0] + ox, a[1] + oy), (a[2] + ox, a[3] + oy)
            out.append(("C", *c1, *c2, *e))
            lastc, lastq = c2, None
            x, y = e
        else:  # Q, T
            if up == "Q":
                q, e = (a[0] + ox, a[1] + oy), (a[2] + ox, a[3] + oy)
            else:
                q = (2 * x - lastq[0], 2 * y - lastq[1]) if lastq else (x, y)
                e = (a[0] + ox, a[1] + oy)
            c1 = (x + 2 / 3 * (q[0] - x), y + 2 / 3 * (q[1] - y))
            c2 = (e[0] + 2 / 3 * (q[0] - e[0]), e[1] + 2 / 3 * (q[1] - e[1]))
            out.append(("C", *c1, *c2, *e))
            lastq, lastc = q, None
            x, y = e
    return out


def to_svg(cmds):
    """Flattened commands back to path data, for the contact sheet and tests."""
    f = lambda v: f"{v:.4f}".rstrip("0").rstrip(".")
    return " ".join(c[0] + " ".join(f(v) for v in c[1:]) for c in cmds)
