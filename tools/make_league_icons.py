#!/usr/bin/env python3
"""Generate the left-panel icons for the league season.

One white, alpha-only glyph per panel destination, drawn at 4x and reduced, so
`draw_texture_rect(..., tint)` can colour it (gold when active, soft otherwise)
without a second asset. The shared style is a flat sports-broadcast glyph on a
96-unit grid with a 7-unit stroke: no emoji, no engine icon, no photograph.

Run from the repository root:

    python3 tools/make_league_icons.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 96
SS = 4  # supersampling factor
OUT = Path("assets/ui/league")
ICONS = ("fixtures", "table", "calendar", "europe", "interest", "stats", "system")
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


def _canvas() -> Image.Image:
    return Image.new("RGBA", (SIZE * SS, SIZE * SS), (255, 255, 255, 0))


def _draw_fixtures(d: ImageDraw.ImageDraw) -> None:
    """A football: ring, centre pentagon and five seams."""
    s = SS
    cx = cy = 48 * s
    d.ellipse([cx - 32 * s, cy - 32 * s, cx + 32 * s, cy + 32 * s], outline=WHITE, width=7 * s)
    pts = []
    for i in range(5):
        a = -90 + i * 72
        import math

        pts.append((cx + 13 * s * math.cos(math.radians(a)),
                    cy + 13 * s * math.sin(math.radians(a))))
    d.polygon(pts, fill=WHITE)
    for px, py in pts:
        vx, vy = px - cx, py - cy
        n = (vx * vx + vy * vy) ** 0.5 or 1.0
        d.line([px, py, cx + vx / n * 30 * s, cy + vy / n * 30 * s], fill=WHITE, width=5 * s)


def _draw_table(d: ImageDraw.ImageDraw) -> None:
    """A ranked table: three leading places and their rows."""
    s = SS
    d.line([16 * s, 13 * s, 80 * s, 13 * s], fill=WHITE, width=7 * s)
    for i, y in enumerate((30, 50, 70)):
        d.rectangle([16 * s, (y - 5) * s, 26 * s, (y + 5) * s], fill=WHITE)
        d.line([36 * s, y * s, (80 - i * 6) * s, y * s], fill=WHITE, width=7 * s)


def _draw_calendar(d: ImageDraw.ImageDraw) -> None:
    """A month page: frame, top band, two hangers and a dot grid."""
    s = SS
    d.rounded_rectangle([16 * s, 22 * s, 80 * s, 80 * s], radius=8 * s, outline=WHITE, width=7 * s)
    d.line([16 * s, 38 * s, 80 * s, 38 * s], fill=WHITE, width=7 * s)
    d.line([32 * s, 14 * s, 32 * s, 26 * s], fill=WHITE, width=7 * s)
    d.line([64 * s, 14 * s, 64 * s, 26 * s], fill=WHITE, width=7 * s)
    for row in range(2):
        for col in range(3):
            x, y = (32 + col * 16) * s, (52 + row * 16) * s
            d.rectangle([x - 3 * s, y - 3 * s, x + 3 * s, y + 3 * s], fill=WHITE)


def _draw_europe(d: ImageDraw.ImageDraw) -> None:
    """A globe: the ring, the equator and one meridian."""
    import math

    s = SS
    cx = cy = 48 * s
    d.ellipse([cx - 30 * s, cy - 30 * s, cx + 30 * s, cy + 30 * s], outline=WHITE, width=7 * s)
    d.line([cx - 30 * s, cy * 1.0, cx + 30 * s, cy * 1.0], fill=WHITE, width=7 * s)
    d.ellipse([cx - 13 * s, cy - 30 * s, cx + 13 * s, cy + 30 * s], outline=WHITE, width=6 * s)
    d.arc([cx - 21 * s, cy - 30 * s, cx + 21 * s, cy + 30 * s], 0, 360, fill=WHITE,
          width=int(2.5 * s))
    d.line([cx - 30 * s * math.cos(math.radians(30)), cy - 15 * s,
            cx + 30 * s * math.cos(math.radians(30)), cy - 15 * s], fill=WHITE,
           width=int(3.5 * s))
    d.line([cx - 30 * s * math.cos(math.radians(30)), cy + 15 * s,
            cx + 30 * s * math.cos(math.radians(30)), cy + 15 * s], fill=WHITE,
           width=int(3.5 * s))


def _draw_interest(d: ImageDraw.ImageDraw) -> None:
    """A star: the shortlist mark, matching the yellow names on the sheets."""
    import math

    s = SS
    cx = cy = 48 * s
    pts = []
    for i in range(10):
        a = math.radians(-90 + i * 36)
        r = (32 if i % 2 == 0 else 13) * s
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    d.polygon(pts, fill=WHITE)


def _draw_stats(d: ImageDraw.ImageDraw) -> None:
    """A rising bar chart on its axes."""
    s = SS
    d.line([18 * s, 16 * s, 18 * s, 80 * s], fill=WHITE, width=7 * s)
    d.line([18 * s, 80 * s, 82 * s, 80 * s], fill=WHITE, width=7 * s)
    for i, h in enumerate((18, 32, 46)):
        x = (28 + i * 18) * s
        d.rectangle([x, (78 - h) * s, x + 11 * s, 78 * s], fill=WHITE)


def _draw_system(d: ImageDraw.ImageDraw) -> None:
    """A gear: ring, eight teeth and the hole."""
    import math

    s = SS
    cx = cy = 48 * s
    for i in range(8):
        a = math.radians(i * 45)
        x, y = cx + 30 * s * math.cos(a), cy + 30 * s * math.sin(a)
        d.ellipse([x - 9 * s, y - 9 * s, x + 9 * s, y + 9 * s], fill=WHITE)
    d.ellipse([cx - 26 * s, cy - 26 * s, cx + 26 * s, cy + 26 * s], fill=WHITE)
    d.ellipse([cx - 11 * s, cy - 11 * s, cx + 11 * s, cy + 11 * s], fill=CLEAR)


def build(name: str) -> Image.Image:
    im = _canvas()
    d = ImageDraw.Draw(im)
    globals()[f"_draw_{name}"](d)
    return im.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in ICONS:
        path = OUT / f"{name}.png"
        build(name).save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
