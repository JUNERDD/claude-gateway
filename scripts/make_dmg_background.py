#!/usr/bin/env python3
from __future__ import annotations

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 760
HEIGHT = 430


def font(size: int, weight: str = "regular") -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = []
    if weight == "bold":
        candidates.extend(
            [
                "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
                "/System/Library/Fonts/Supplemental/Helvetica Bold.ttf",
            ]
        )
    candidates.extend(
        [
            "/System/Library/Fonts/Supplemental/Arial.ttf",
            "/System/Library/Fonts/Supplemental/Helvetica.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
        ]
    )

    for candidate in candidates:
        if Path(candidate).exists():
            try:
                return ImageFont.truetype(candidate, size)
            except OSError:
                pass
    return ImageFont.load_default()


def rounded_rect(draw: ImageDraw.ImageDraw, xy: tuple[int, int, int, int], radius: int, fill, outline=None, width=1):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: make_dmg_background.py <output.png>", file=sys.stderr)
        return 2

    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)

    img = Image.new("RGB", (WIDTH, HEIGHT), "#15171c")
    px = img.load()
    for y in range(HEIGHT):
        for x in range(WIDTH):
            t = y / max(HEIGHT - 1, 1)
            glow = math.exp(-(((x - 250) / 290) ** 2 + ((y - 72) / 170) ** 2))
            r = int(18 + 10 * (1 - t) + 18 * glow)
            g = int(20 + 12 * (1 - t) + 34 * glow)
            b = int(26 + 16 * (1 - t) + 76 * glow)
            px[x, y] = (r, g, b)

    draw = ImageDraw.Draw(img)

    for x in range(24, WIDTH, 28):
        draw.line((x, 0, x, HEIGHT), fill=(36, 43, 58), width=1)
    for y in range(22, HEIGHT, 28):
        draw.line((0, y, WIDTH, y), fill=(34, 40, 54), width=1)

    rounded_rect(draw, (28, 28, WIDTH - 28, HEIGHT - 28), 24, (24, 28, 38), (57, 68, 90), 1)

    title_font = font(28, "bold")
    body_font = font(14)
    hint_font = font(13)
    small_font = font(12)

    draw.text((54, 50), "Claude DeepSeek Gateway", font=title_font, fill=(246, 248, 252))
    draw.text((56, 88), "Drag the app into Applications to install", font=body_font, fill=(183, 195, 213))

    app_center = (210, 225)
    apps_center = (550, 225)
    arrow_y = 218

    draw.line((app_center[0] + 88, arrow_y, apps_center[0] - 88, arrow_y), fill=(104, 170, 255), width=5)
    draw.polygon(
        [
            (apps_center[0] - 88, arrow_y),
            (apps_center[0] - 112, arrow_y - 15),
            (apps_center[0] - 112, arrow_y + 15),
        ],
        fill=(104, 170, 255),
    )
    draw.text((330, 178), "Drag to install", font=hint_font, fill=(215, 225, 240))

    for center, label, accent in [
        (app_center, "App", (76, 137, 255)),
        (apps_center, "Applications", (78, 190, 144)),
    ]:
        x, y = center
        rounded_rect(draw, (x - 66, y - 78, x + 66, y + 84), 18, (12, 15, 22), (52, 63, 84), 1)
        draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill=accent)
        draw.text((x - draw.textlength(label, font=small_font) / 2, y + 56), label, font=small_font, fill=(192, 202, 219))

    draw.text((56, HEIGHT - 70), "After copying, open the app and paste your DeepSeek API key.", font=small_font, fill=(146, 157, 176))

    img.save(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
