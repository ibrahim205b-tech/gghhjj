#!/usr/bin/env python3
"""Draws the HHKKLL launcher icon (gold monogram on a stadium-lit black
disc) at every Android density.   python3 tools/make_icon.py"""
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(__file__), "..", "app")
FONT = os.path.join(ROOT, "assets", "fonts", "NotoSans-Bold.ttf")
S = 1024


def master():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # Background: charcoal radial gradient in a rounded square.
    bg = Image.new("RGBA", (S, S))
    px = bg.load()
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - S * .5, y - S * .38) / (S * .75)
            c = max(0.0, 1 - d)
            px[x, y] = (int(8 + 30 * c), int(9 + 28 * c), int(13 + 30 * c), 255)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * .22), fill=255)
    img.paste(bg, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # Gold ring.
    ring = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ring).ellipse([S * .14, S * .12, S * .86, S * .84], outline=(247, 201, 72, 255), width=int(S * .03))
    img.alpha_composite(ring.filter(ImageFilter.GaussianBlur(S * .02)))
    img.alpha_composite(ring)
    # Monogram "HK" with glow.
    font = ImageFont.truetype(FONT, int(S * .36))
    txt = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    td = ImageDraw.Draw(txt)
    box = td.textbbox((0, 0), "HK", font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    td.text(((S - w) / 2 - box[0], S * .48 - h / 2 - box[1]), "HK", font=font, fill=(247, 201, 72, 255))
    img.alpha_composite(txt.filter(ImageFilter.GaussianBlur(S * .025)))
    # Vertical gold→white gradient fill for the letters.
    grad = Image.new("RGBA", (S, S))
    gp = grad.load()
    for y in range(S):
        t = y / S
        gp_row = (int(255 - 40 * t), int(236 - 70 * t), int(170 - 140 * t), 255)
        for x in range(S):
            gp[x, y] = gp_row
    img.paste(grad, (0, 0), txt)
    return img


m = master()
for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    m.resize((px, px), Image.LANCZOS).save(os.path.join(ROOT, "android", "app", "src", "main", "res", f"mipmap-{name}", "ic_launcher.png"))
m.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, "assets", "icon_512.png"))
print("icons written")
