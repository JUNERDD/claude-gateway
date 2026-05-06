#!/usr/bin/env python3
"""生成 Claude DeepSeek Gateway 的 AppIcon.icns（依赖 Pillow）。"""

from __future__ import annotations

import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


ROOT = Path(__file__).resolve().parent.parent
ICONSET_DIR = ROOT / "Resources" / "AppIcon.iconset"
OUT_ICNS = ROOT / "Resources" / "AppIcon.icns"

# Apple 模板所需 PNG 列表
PNG_SPECS = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]


def _blend(c1: tuple[int, ...], c2: tuple[int, ...], t: float) -> tuple[int, int, int, int]:
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_master(size: int = 1024) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    top = (18, 28, 64, 255)
    bottom = (40, 98, 220, 255)
    bands = max(48, size // 20)
    for i in range(bands):
        y0 = i * size // bands
        y1 = (i + 1) * size // bands
        t = i / (bands - 1) if bands > 1 else 0
        draw.rectangle([0, y0, size, y1], fill=_blend(top, bottom, t))

    img = img.filter(ImageFilter.GaussianBlur(radius=max(1, size // 384)))

    # 内高光描边圆角矩形
    border = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bd = ImageDraw.Draw(border)
    inset = round(size * 0.089)
    rrect = inset * 1.85
    bd.rounded_rectangle(
        [inset, inset, size - inset, size - inset],
        radius=rrect,
        outline=(255, 255, 255, 70),
        width=max(2, size // 180),
    )
    img = Image.alpha_composite(img, border.filter(ImageFilter.GaussianBlur(radius=max(1, size // 256))))

    sx = size / 1024

    # 连接线（代理链路）
    link = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ld = ImageDraw.Draw(link)
    y_mid = round(512 * sx)
    x0, x1 = round(336 * sx), round(688 * sx)
    w = max(round(42 * sx), 8)
    # 轻微弧线：用线段近似
    points = []
    steps = 32
    for i in range(steps + 1):
        tt = i / steps
        x = x0 + (x1 - x0) * tt
        bend = math.sin(tt * math.pi) * (48 * sx)
        points.append((x, y_mid - bend))
    ld.line(points, fill=(235, 250, 255, 235), width=w, joint="curve")
    link = link.filter(ImageFilter.GaussianBlur(radius=w * 0.14))
    img = Image.alpha_composite(img, link)

    glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)

    def node(cx: int, cy: int, accent: tuple[int, int, int, int]):
        rr = round(108 * sx)
        for shrink, alpha in [(1.42, 45), (1.08, 100), (0.94, 200)]:
            r = round(rr * shrink)
            box = [cx - r, cy - r, cx + r, cy + r]
            gd.ellipse(box, fill=(accent[0], accent[1], accent[2], alpha))

    node(round(392 * sx), y_mid, (120, 240, 255, 255))
    node(round(632 * sx), y_mid, (160, 255, 215, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(radius=max(4, round(26 * sx))))
    img = Image.alpha_composite(img, glow)

    # 实心节点核
    core = ImageDraw.Draw(img)
    r_core = round(72 * sx)
    core.ellipse(
        [round(392 * sx) - r_core, y_mid - r_core, round(392 * sx) + r_core, y_mid + r_core],
        fill=(248, 255, 255, 255),
    )
    core.ellipse(
        [round(632 * sx) - r_core, y_mid - r_core, round(632 * sx) + r_core, y_mid + r_core],
        fill=(248, 255, 255, 255),
    )
    return img


def build_iconset() -> None:
    master = draw_master(1024)
    ICONSET_DIR.mkdir(parents=True, exist_ok=True)
    for name, dim in PNG_SPECS:
        out = ICONSET_DIR / name
        master.resize((dim, dim), Image.Resampling.LANCZOS).save(out)
    if OUT_ICNS.exists():
        OUT_ICNS.unlink()
    subprocess.run(
        ["iconutil", "-c", "icns", str(ICONSET_DIR), "-o", str(OUT_ICNS)],
        check=True,
    )


def main() -> None:
    build_iconset()
    print(str(OUT_ICNS))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001
        print(exc, file=sys.stderr)
        sys.exit(1)
