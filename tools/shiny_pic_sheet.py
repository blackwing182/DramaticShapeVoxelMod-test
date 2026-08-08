#!/usr/bin/env python3
"""Every battle pic, baked normal beside baked shiny, as one HTML page.

    luajit mods/DramaticShapeVoxelMod/tools/shiny_pic_dump.lua > /tmp/pics.tsv
    python mods/DramaticShapeVoxelMod/tools/shiny_pic_sheet.py /tmp/pics.tsv

Run from the PROJECT ROOT. Writes
mods/DramaticShapeVoxelMod/.claude/shiny_update/sprites.html, self-contained
(every pic is a data: URI), so it can be opened or sent on its own.

------- the bake is the engine's, exactly

src/battle/BattleState.lua:147 getImage() is the only place a battle pic gets
its colour, and it does it ONCE at load with mapPixel:

    col = r > 0.83 and c[1] or r > 0.5 and c[2] or r > 0.17 and c[3] or c[4]

Four-shade DMG art, keyed on the RED channel alone, snapped to the species
palette. That line is reproduced below rather than approximated, because the
whole question this sheet answers is what the player will actually see -- an
approximation of the bake would be answering a different one.

The colours come from tools/shiny_pic_dump.lua, which runs the real
ShinyPics wrap over the real PaletteFX, so nothing here re-derives them.
"""

import base64
import io
import os
import sys

from PIL import Image

ROOT = os.getcwd()
MOD = "mods/DramaticShapeVoxelMod"
OUT = os.path.join(MOD, ".claude/shiny_update/sprites.html")
SCALE = 3  # nearest-neighbour, so the pixels stay pixels


def parse_color(s):
    r, g, b = (int(v) for v in s.split(","))
    return (r, g, b)


def bake(img, pal):
    """getImage's mapPixel: red channel picks the shade, alpha is kept."""
    img = img.convert("RGBA")
    px = img.load()
    w, h = img.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            f = r / 255.0
            if f > 0.83:
                c = pal[0]
            elif f > 0.5:
                c = pal[1]
            elif f > 0.17:
                c = pal[2]
            else:
                c = pal[3]
            px[x, y] = (c[0], c[1], c[2], a)
    return img


def data_uri(img):
    img = img.resize((img.width * SCALE, img.height * SCALE), Image.NEAREST)
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "-"
    stream = sys.stdin if src == "-" else open(src, encoding="utf-8")
    rows = []
    with stream:
        for line in stream:
            line = line.rstrip("\n")
            if not line:
                continue
            f = line.split("\t")
            rows.append({
                "dex": int(f[0]),
                "name": f[1],
                "path": f[2],
                "kind": f[3],
                "normal": [parse_color(c) for c in f[4:8]],
                "shiny": [parse_color(c) for c in f[8:12]],
            })

    cards, missing = [], 0
    for row in rows:
        path = os.path.join(ROOT, row["path"])
        if not os.path.exists(path):
            missing += 1
            continue
        art = Image.open(path)
        n = data_uri(bake(art.copy(), row["normal"]))
        s = data_uri(bake(art.copy(), row["shiny"]))
        cards.append(
            '<figure class="k-{kind}">'
            '<div class="pair"><img src="{n}" alt="{name} normal">'
            '<img src="{s}" alt="{name} shiny"></div>'
            '<figcaption>{dex:03d} {name}<span>{kind}</span></figcaption>'
            "</figure>".format(kind=row["kind"], n=n, s=s,
                               name=row["name"], dex=row["dex"])
        )

    html = """<!doctype html>
<html><head><meta charset="utf-8"><title>Shiny battle pics</title>
<style>
  body { font: 13px/1.5 ui-monospace, Menlo, Consolas, monospace;
         margin: 24px; background: #14151a; color: #e6e6ea; }
  h1 { font-size: 18px; margin: 0 0 4px; }
  p.lede { color: #9aa0aa; max-width: 64em; margin: 0 0 20px; }
  .grid { display: flex; flex-wrap: wrap; gap: 14px; }
  figure { margin: 0; background: #1c1e26; border: 1px solid #2a2c34;
           border-radius: 6px; padding: 8px; }
  .k-table { border-color: #7a5a1e; }
  .pair { display: flex; gap: 6px; background: #fff; border-radius: 3px;
          padding: 2px; }
  img { display: block; image-rendering: pixelated; }
  figcaption { margin-top: 6px; color: #9aa0aa; display: flex;
               justify-content: space-between; gap: 10px; }
  figcaption span { color: #6f757f; }
  .k-table figcaption span { color: #ffc46b; }
</style></head><body>
<h1>Shiny battle pics &mdash; normal on the left, shiny on the right</h1>
<p class="lede">Each pair is the same four-shade art baked twice, through the
palette the game itself would use: <code>getImage</code> keys on the red
channel alone and snaps to the species palette, once, at load. The colours
come from the live <code>ShinyPics</code> wrap, so this is what the flat
battle screen draws &mdash; not a preview of it. Bordered cards are the five
species Stadium gives a real alternate texture, whose slide is measured back
out of that texture rather than declared.</p>
<p class="lede">%d species%s</p>
<div class="grid">%s</div>
</body></html>
""" % (len(cards),
       "" if not missing else " &middot; %d with no art on disk" % missing,
       "\n".join(cards))

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(html)
    size = os.path.getsize(OUT) / 1024.0
    print("%s -- %d pairs, %d missing, %.0f KB" % (OUT, len(cards), missing,
                                                   size))


if __name__ == "__main__":
    main()
