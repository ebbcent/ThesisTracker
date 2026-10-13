#!/usr/bin/env python3
"""
Generate a premium sage-green abstract macOS app icon for ThesisTracker.
Design: flat sage-green background + three diagonal white pill bars + soft shadows.
"""

from PIL import Image, ImageDraw, ImageFilter
import math, os

BG_COLOR = (122, 158, 128, 255)   # #7A9E80  sage green

ANGLE_DEG = 22

# (width_fraction, cy_fraction, opacity)
BARS = [
    (0.72, 0.295, 0.92),
    (0.56, 0.510, 0.68),
    (0.38, 0.720, 0.44),
]
BAR_H_F = 0.115         # bar height as fraction of icon size
SHADOW_ALPHA   = 65
SHADOW_BLUR_F  = 0.028
SHADOW_OFF_F   = 0.020


def draw_pill(draw, x0, y0, x1, y1, fill):
    """Draw a horizontal pill (rounded rectangle) with given bounding box."""
    w = x1 - x0
    h = y1 - y0
    r = h // 2
    draw.rectangle([x0 + r, y0, x1 - r, y1], fill=fill)
    draw.ellipse([x0, y0, x0 + h, y1], fill=fill)
    draw.ellipse([x1 - h, y0, x1, y1], fill=fill)


def make_bar_image(size, bar_w, bar_h, alpha_val):
    """Create a white pill on transparent background, centered."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx, cy = size // 2, size // 2
    x0 = cx - bar_w // 2
    x1 = cx + bar_w // 2
    y0 = cy - bar_h // 2
    y1 = cy + bar_h // 2
    draw_pill(draw, x0, y0, x1, y1, fill=(255, 255, 255, alpha_val))
    return img


def make_icon(size: int) -> Image.Image:
    s = size

    # Background
    img = Image.new('RGBA', (s, s), BG_COLOR)

    bar_h = int(s * BAR_H_F)
    blur_r = max(2, int(s * SHADOW_BLUR_F))
    ox = int(s * SHADOW_OFF_F)
    oy = int(s * SHADOW_OFF_F * 1.4)

    for w_f, cy_f, opacity in BARS:
        bar_w = int(s * w_f)
        alpha_val = int(255 * opacity)
        cy_target = int(s * cy_f)
        shift = cy_target - s // 2

        # ── Shadow ──────────────────────────────────────────────────────────
        shadow_img = Image.new('RGBA', (s, s), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow_img)
        cx = s // 2
        x0 = cx - bar_w // 2 + ox
        x1 = cx + bar_w // 2 + ox
        y0 = s // 2 - bar_h // 2 + oy
        y1 = s // 2 + bar_h // 2 + oy
        draw_pill(sdraw, x0, y0, x1, y1, fill=(0, 25, 8, SHADOW_ALPHA))
        # Rotate & translate shadow
        shadow_img = shadow_img.rotate(-ANGLE_DEG, resample=Image.BICUBIC, expand=False)
        # Translate vertically: shift after rotation
        shadow_img = shadow_img.transform(
            (s, s), Image.AFFINE, (1, 0, 0, 0, 1, -shift), resample=Image.BICUBIC
        )
        shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(radius=blur_r))
        img = Image.alpha_composite(img, shadow_img)

        # ── Bar ─────────────────────────────────────────────────────────────
        bar_img = make_bar_image(s, bar_w, bar_h, alpha_val)
        bar_img = bar_img.rotate(-ANGLE_DEG, resample=Image.BICUBIC, expand=False)
        bar_img = bar_img.transform(
            (s, s), Image.AFFINE, (1, 0, 0, 0, 1, -shift), resample=Image.BICUBIC
        )
        img = Image.alpha_composite(img, bar_img)

    return img


SIZES = {
    "icon_16x16.png":      16,
    "icon_16x16@2x.png":   32,
    "icon_32x32.png":      32,
    "icon_32x32@2x.png":   64,
    "icon_128x128.png":    128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png":    256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png":    512,
    "icon_512x512@2x.png": 1024,
}

OUT_DIR = os.path.join(
    os.path.dirname(__file__),
    "ThesisTracker/Assets.xcassets/AppIcon.appiconset"
)

if __name__ == "__main__":
    master = make_icon(1024)
    print("Master icon generated (1024×1024)")

    for filename, size in SIZES.items():
        path = os.path.join(OUT_DIR, filename)
        icon = master.resize((size, size), Image.LANCZOS)
        icon.save(path, "PNG")
        print(f"  ✓ {filename} ({size}×{size})")

    print(f"\nAll icons saved to:\n  {OUT_DIR}")
