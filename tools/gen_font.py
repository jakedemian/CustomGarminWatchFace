"""Render a BMFont text-format font (.fnt + .png) for Connect IQ from a variable TTF.

Glyph metrics are normalized so text width == ink width and the line box == digit
height. That lets the watch face center the time exactly (by ink, not advance) and
use TEXT_JUSTIFY_VCENTER without descender space skewing it.

Usage: python -I gen_font.py <ttf> <weight> <px_size> <chars> <out_basename> [tracking] [thin]

thin: thins strokes below the font's lightest weight. Glyphs are rendered at 4x, eroded
by <thin> supersampled pixels per side, then downsampled; each step removes ~0.5px of
stroke width at final size.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

PAD = 2  # atlas gap between glyphs
SS = 4  # supersampling factor when thinning


def main():
    ttf, weight, size, chars, out = sys.argv[1:6]
    tracking = int(sys.argv[6]) if len(sys.argv) > 6 else 0
    thin = int(sys.argv[7]) if len(sys.argv) > 7 else 0
    weight, size = int(weight), int(size)

    scale = SS if thin else 1
    font = ImageFont.truetype(ttf, size * scale)
    axes = font.get_variation_axes()
    font.set_variation_by_axes([weight if a["name"] == b"Weight" else a["maximum"] for a in axes])

    # Render each glyph on an oversized canvas with the baseline at y=size*2 and crop
    # to the actual ink (Pillow's getbbox reports advance width, not ink, for some glyphs).
    canvas, base = (size * 3 * scale, size * 3 * scale), size * 2 * scale
    inked = {}
    for c in chars:
        img = Image.new("L", canvas, 0)
        ImageDraw.Draw(img).text((size * scale // 2, base), c, fill=255, font=font, anchor="ls")
        for _ in range(thin):
            img = img.filter(ImageFilter.MinFilter(3))
        if scale > 1:
            img = img.resize((size * 3, size * 3), Image.BOX)
        bbox = img.getbbox()
        inked[c] = (img.crop(bbox), bbox[1])
    top = min(t for _, t in inked.values())
    bottom = max(t + img.height for img, t in inked.values())
    line_h = bottom - top

    glyphs = [(c, img, t - top) for c, (img, t) in inked.items()]

    atlas_w = sum(g[1].width + PAD for g in glyphs) + PAD
    # Coverage goes in RGB brightness on opaque black. The Connect IQ font compiler
    # (GarminFontObject.convertToNBit) ignores alpha and quantizes HSB brightness, so
    # white-with-alpha glyphs come out fully aliased.
    atlas = Image.new("RGB", (atlas_w, line_h + 2 * PAD), (0, 0, 0))
    lines, x = [], PAD
    for c, img, yoff in glyphs:
        atlas.paste(img.convert("RGB"), (x, PAD))
        lines.append(
            f"char id={ord(c)} x={x} y={PAD} width={img.width} height={img.height} "
            f"xoffset=0 yoffset={yoff} xadvance={img.width + tracking} page=0 chnl=15"
        )
        x += img.width + PAD

    out = Path(out)
    atlas.save(out.with_suffix(".png"))
    header = [
        f'info face="{Path(ttf).stem}-w{weight}-t{thin}" size={size} bold=0 italic=0 charset="" '
        f"unicode=1 stretchH=100 smooth=1 aa=1 padding=0,0,0,0 spacing=1,1 outline=0",
        f"common lineHeight={line_h} base={line_h} scaleW={atlas.width} scaleH={atlas.height} "
        f"pages=1 packed=0 alphaChnl=4 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="{out.with_suffix(".png").name}"',
        f"chars count={len(lines)}",
    ]
    out.with_suffix(".fnt").write_text("\n".join(header + lines) + "\n", encoding="utf-8")
    print(f"{out.name}: line_h={line_h} atlas={atlas.size}")


if __name__ == "__main__":
    main()
