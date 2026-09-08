#!/usr/bin/env python3
"""Draw the Cheppu lockup: the mark, the wordmark, and the name in Telugu.

The lockup's text is outlined rather than set. An SVG that GitHub renders as
an <img> never fetches a font, and neither Space Grotesk nor Noto Sans Telugu
is on a reader's machine by default — set as text, the wordmark would arrive
in whatever the browser had lying around, and చెప్పు in nothing at all. So
this script shapes both runs with HarfBuzz (Telugu's conjunct is a shaping
result, not a sequence of glyphs) and writes the curves into the file.

That leaves the shape of the words with no source but the file it produced,
which is why this script exists: the lockup is regenerated from here, never
edited by hand. The mark inside it is the same five rectangles stated in the
README and in MenuBarIcon.swift, on the same 24-unit grid.

    Scripts/draw-the-lockup.py

Writes docs/brand/cheppu-lockup.svg and docs/brand/cheppu-lockup-dark.svg.
Needs fonttools and uharfbuzz, and fetches the two fonts from Google Fonts
on first run (both are SIL Open Font License 1.1; outlines drawn from them
may be embedded and redistributed).
"""

import sys
import urllib.request
from pathlib import Path

try:
    import uharfbuzz as hb
    from fontTools.ttLib import TTFont
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.boundsPen import BoundsPen
    from fontTools.pens.transformPen import TransformPen
    from fontTools.misc.transform import Identity
except ImportError:
    sys.exit("needs fonttools and uharfbuzz: pip install fonttools uharfbuzz")

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "docs" / "brand"
CACHE = ROOT / ".build" / "fonts"

FONTS = {
    # Google Fonts serves one static TTF per weight from these URLs.
    "SpaceGrotesk-Medium.ttf":
        "https://fonts.gstatic.com/s/spacegrotesk/v22/"
        "V8mQoQDjQSkFtoMM3T6r8E7mF71Q-gOoraIAEj7aUUsj.ttf",
    "NotoSansTelugu-Medium.ttf":
        "https://fonts.gstatic.com/s/notosanstelugu/v30/"
        "0FlxVOGZlE2Rrtr-HmgkMWJNjJ5_RyT8o8c7fHkeg-esVC5dzHkHIJQqrEntSTbqQQ.ttf",
}

# The mark on its 24-unit grid: rails 14 × 2.4 with a 1.2 radius at y 2 and
# 19.6; three bars 2.4 wide, centred on x 8.5 / 12 / 15.5, of heights 8 / 13 /
# 8, each centred on y 12. Ink spans x 5..19 and y 2..22 — 14 × 20.
MARK = [(5, 2, 14, 2.4), (5, 19.6, 14, 2.4),
        (7.3, 8, 2.4, 8), (10.8, 5.5, 2.4, 13), (14.3, 8, 2.4, 8)]
MIDDLE_BAR = 3

WORDMARK = "Cheppu"          # Space Grotesk Medium
NAME = "చెప్పు"                # Noto Sans Telugu Medium — Telugu for "tell me"
WORD_SIZE = 46
WORD_TRACKING = -0.03        # em
CAP_HEIGHT = 0.700           # em, Space Grotesk
NAME_SIZE = 19
LEADING = 7                  # px of white between the two runs' ink
CLEAR = 6                    # units from the mark to the wordmark; the rule is 4
PAD = 1                      # a hair of air, so nothing clips when it is scaled


def font(name):
    """The TTF at `name`, fetched into .build/fonts the first time it is asked for."""
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"fetching {name}")
        urllib.request.urlretrieve(FONTS[name], path)
    return path


def outline(ttf, text, size, tracking=0.0):
    """Shape `text` and outline it, baseline at y 0 and the pen starting at x 0.

    Returns the path data and the run's ink bounds, both in SVG coordinates.
    """
    tt = TTFont(ttf)
    upm = tt["head"].unitsPerEm
    scale = size / upm
    glyphs = tt.getGlyphSet()

    shaper = hb.Font(hb.Face(ttf.read_bytes()))
    shaper.scale = (upm, upm)
    buf = hb.Buffer()
    buf.add_str(text)
    buf.guess_segment_properties()
    hb.shape(shaper, buf)

    path = SVGPathPen(glyphs, ntos=lambda v: number(v))
    bounds = BoundsPen(glyphs)
    pen_x = 0.0
    for info, pos in zip(buf.glyph_infos, buf.glyph_positions):
        placed = (Identity
                  .translate((pen_x + pos.x_offset) * scale, -pos.y_offset * scale)
                  .scale(scale, -scale))
        for target in (path, bounds):
            glyphs[tt.getGlyphName(info.codepoint)].draw(TransformPen(target, placed))
        pen_x += pos.x_advance + tracking / scale
    return path.getCommands(), bounds.bounds


def number(value):
    return f"{round(value, 2):g}"


def draw(path, ink, terracotta, muted):
    word, (wx0, wy0, wx1, wy1) = outline(
        font("SpaceGrotesk-Medium.ttf"), WORDMARK, WORD_SIZE,
        WORD_TRACKING * WORD_SIZE)
    name, (nx0, ny0, nx1, ny1) = outline(
        font("NotoSansTelugu-Medium.ttf"), NAME, NAME_SIZE)

    # The two baselines are set apart by the white between the ink, not by a
    # nominal leading: what would otherwise collide is the wordmark's
    # descenders and the vowel sign above చె.
    cap = CAP_HEIGHT * WORD_SIZE
    word_baseline = PAD + cap
    name_baseline = word_baseline + wy1 + LEADING - ny0

    # The mark stands the height of the text beside it — cap line to the
    # Telugu baseline — and that fixes the unit the whole grid is drawn in.
    unit = (name_baseline - (word_baseline - cap)) / 20
    text_x = PAD + 14 * unit + CLEAR * unit

    width = text_x + max(wx1 - wx0, nx1 - nx0) + PAD
    height = max(PAD + 20 * unit, name_baseline + ny1) + PAD

    rects = "\n".join(
        '  <rect x="{}" y="{}" width="{}" height="{}" rx="{}" fill="{}"/>'.format(
            number(PAD + (x - 5) * unit), number(PAD + (y - 2) * unit),
            number(w * unit), number(h * unit), number(1.2 * unit),
            terracotta if i == MIDDLE_BAR else ink)
        for i, (x, y, w, h) in enumerate(MARK))

    label = "Cheppu — చెప్పు"
    path.write_text(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {number(width)} '
        f'{number(height)}" width="{number(width)}" height="{number(height)}" '
        f'role="img" aria-label="{label}, Telugu for “tell me”">\n'
        f"  <title>{label}</title>\n"
        f"{rects}\n"
        f'  <path transform="translate({number(text_x - wx0)} {number(word_baseline)})"'
        f' fill="{ink}" d="{word}"/>\n'
        f'  <path transform="translate({number(text_x - nx0)} {number(name_baseline)})"'
        f' fill="{muted}" d="{name}"/>\n'
        f"</svg>\n")
    print(f"{path.relative_to(ROOT)} — {number(width)} × {number(height)}")


draw(BRAND / "cheppu-lockup.svg", "#211F1C", "#C2551F", "#6B655D")
draw(BRAND / "cheppu-lockup-dark.svg", "#F2EEE7", "#D9702F", "#A79E92")
