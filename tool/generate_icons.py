#!/usr/bin/env python3
"""Generate every RetroBeat icon asset from one drawing routine.

The mark is a vinyl record: a dark disc, a play triangle on its label, and a
label gradient that runs from the app's default accent (blue) into the Retro
mode glow (teal) — the two identities the app actually has, in one shape.

Regenerate whenever the mark or palette changes:

    pip install pillow
    python3 tool/generate_icons.py

Writes:
    assets/icon/icon.png                         (528x512 master, standalone)
    android/app/src/main/res/mipmap-*/ic_launcher.png             (legacy)
    android/app/src/main/res/mipmap-*/ic_launcher_foreground.png  (adaptive)
    web/icons/Icon-*.png, web/icons/Icon-maskable-*.png, web/favicon.png
    store/icon-512.png                            (Play listing icon)
    store/feature-graphic-1024x500.png             (Play listing banner)

Android is the only shipped target (see the platform table in README.md); the
web/ output exists only because `flutter create` scaffolds it, and it was
still carrying the unmodified Flutter template logo before this script existed.
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
STORE = os.path.join(ROOT, "store")
ASSET_ICON = os.path.join(ROOT, "assets", "icon")
WEB_ICONS = os.path.join(ROOT, "web", "icons")

# The app's default accent (AppColors.accent) and the Retro-mode glow
# (AppColors.retroGlow) — the disc label gradient runs between the two.
ACCENT = (52, 121, 246)
RETRO_GLOW = (61, 224, 176)
BG_TOP = (16, 20, 28)
BG_BOT = (6, 8, 12)
DISC = (24, 27, 32)
DISC_RIM = (46, 51, 59)

LEGACY_DENSITIES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ADAPTIVE_DENSITIES = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}


def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def rounded_mask(size, radius):
    m = Image.new("L", (size, size), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return m


def vertical_gradient(size, top, bot):
    img = Image.new("RGB", size)
    d = ImageDraw.Draw(img)
    w, h = size
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=lerp(top, bot, t))
    return img


def radial_fill(draw, cx, cy, r, outer, inner, steps=28):
    """Paint a radial gradient by drawing shrinking filled circles, largest
    first — Pillow has no native radial-gradient brush, so each smaller circle
    simply overpaints the middle of the last one."""
    for i in range(steps, 0, -1):
        t = i / steps
        rad = r * t
        draw.ellipse(
            [cx - rad, cy - rad, cx + rad, cy + rad],
            fill=lerp(outer, inner, 1 - t),
        )


def draw_vinyl(canvas: Image.Image, cx: float, cy: float, r: float, glow: bool = False):
    """The mark itself: disc, grooves, gradient label, play triangle, spindle."""
    draw = ImageDraw.Draw(canvas, "RGBA")

    if glow:
        # A soft halo behind the disc, painted on its own layer and blurred —
        # gives the standalone icon some depth without adding a hard shadow.
        halo = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        hd = ImageDraw.Draw(halo)
        hd.ellipse([cx - r * 1.28, cy - r * 1.28, cx + r * 1.28, cy + r * 1.28],
                   fill=(*ACCENT, 70))
        halo = halo.filter(ImageFilter.GaussianBlur(r * 0.30))
        canvas.alpha_composite(halo)
        draw = ImageDraw.Draw(canvas, "RGBA")

    # The disc, with a faint lighter rim so it doesn't read as a flat circle.
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(*DISC, 255))
    draw.ellipse(
        [cx - r, cy - r, cx + r, cy + r],
        outline=(*DISC_RIM, 255),
        width=max(1, round(r * 0.02)),
    )

    # Grooves: thin concentric rings, barely-there.
    for frac in (0.58, 0.74, 0.90):
        gr = r * frac
        draw.ellipse(
            [cx - gr, cy - gr, cx + gr, cy + gr],
            outline=(255, 255, 255, 18),
            width=max(1, round(r * 0.012)),
        )

    # Label: gradient from the app's accent to the Retro glow — the two looks
    # this app actually has, in one shape.
    label_r = r * 0.40
    radial_fill(draw, cx, cy, label_r, ACCENT, RETRO_GLOW, steps=28)
    draw.ellipse(
        [cx - label_r, cy - label_r, cx + label_r, cy + label_r],
        outline=(0, 0, 0, 40),
        width=max(1, round(r * 0.01)),
    )

    # Play triangle. Optically centred means shifted right of true centre —
    # a symmetric triangle at dead centre reads as left-heavy.
    tri_h = label_r * 1.05
    tri_w = tri_h * 0.86
    shift = tri_w * 0.12
    apex = (cx + tri_w * 0.62 + shift, cy)
    top = (cx - tri_w * 0.38 + shift, cy - tri_h / 2)
    bot = (cx - tri_w * 0.38 + shift, cy + tri_h / 2)
    draw.polygon([top, apex, bot], fill=(250, 251, 253, 255))

    # Spindle hole.
    sr = r * 0.055
    draw.ellipse([cx - sr, cy - sr, cx + sr, cy + sr], fill=(*DISC, 255))


def app_icon_square(size: int) -> Image.Image:
    """Full standalone icon: background + mark, rounded corners."""
    img = vertical_gradient((size, size), BG_TOP, BG_BOT).convert("RGBA")
    draw_vinyl(img, size / 2, size / 2, size * 0.34, glow=True)
    img.putalpha(rounded_mask(size, round(size * 0.22)))
    return img


def adaptive_foreground(size: int) -> Image.Image:
    """Mark only, transparent, sized to stay inside the launcher's safe zone
    (the centre ~66% of an adaptive icon survives every mask shape)."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_vinyl(img, size / 2, size / 2, size * 0.30)
    return img


def feature_graphic() -> Image.Image:
    """1024x500 Play listing banner: the mark over a drifting wake, echoing the
    Ambience visualisation. Play overlays the app name and rating itself, so no
    text is baked in here."""
    w, h = 1024, 500
    img = vertical_gradient((w, h), (14, 18, 26), (5, 7, 11)).convert("RGBA")

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for k in range(6):
        pts = []
        for i in range(0, w + 1, 6):
            t = i / w
            y = (
                h * 0.5
                + math.sin(t * 3.1 * math.pi + k * 0.9) * h * 0.20
                + math.sin(t * 7.3 * math.pi - k * 1.4) * h * 0.08
                + (k - 2.5) * 18
            )
            pts.append((i, y))
        color = ACCENT if k % 2 == 0 else RETRO_GLOW
        gd.line(pts, fill=(*color, 55 + k * 6), width=32)
    glow = glow.filter(ImageFilter.GaussianBlur(26))
    img.alpha_composite(glow)

    vign = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vign).ellipse([-w * 0.15, -h * 0.55, w * 1.15, h * 1.55], fill=90)
    vign = vign.filter(ImageFilter.GaussianBlur(120))
    img = Image.composite(img, Image.new("RGBA", (w, h), (5, 7, 11, 255)), vign.point(lambda v: 255 - v))

    draw_vinyl(img, w / 2, h / 2, h * 0.34, glow=True)
    return img


def maskable_web_icon(size: int) -> Image.Image:
    """Web's maskable purpose needs the same safe-zone padding as Android
    adaptive icons: background fills the canvas, the mark stays inset."""
    img = vertical_gradient((size, size), BG_TOP, BG_BOT).convert("RGBA")
    draw_vinyl(img, size / 2, size / 2, size * 0.27)
    return img


if __name__ == "__main__":
    os.makedirs(ASSET_ICON, exist_ok=True)
    os.makedirs(STORE, exist_ok=True)
    os.makedirs(WEB_ICONS, exist_ok=True)

    master = app_icon_square(512)
    master.save(os.path.join(ASSET_ICON, "icon.png"))
    master.save(os.path.join(STORE, "icon-512.png"))

    for density, px in LEGACY_DENSITIES.items():
        out_dir = os.path.join(RES, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        app_icon_square(px).save(os.path.join(out_dir, "ic_launcher.png"))

    for density, px in ADAPTIVE_DENSITIES.items():
        out_dir = os.path.join(RES, f"mipmap-{density}")
        os.makedirs(out_dir, exist_ok=True)
        adaptive_foreground(px).save(os.path.join(out_dir, "ic_launcher_foreground.png"))

    for size in (192, 512):
        app_icon_square(size).save(os.path.join(WEB_ICONS, f"Icon-{size}.png"))
        maskable_web_icon(size).save(os.path.join(WEB_ICONS, f"Icon-maskable-{size}.png"))
    app_icon_square(48).save(os.path.join(ROOT, "web", "favicon.png"))

    feature_graphic().convert("RGB").save(
        os.path.join(STORE, "feature-graphic-1024x500.png")
    )

    print("wrote assets/icon/icon.png")
    print("wrote android launcher icons (legacy + adaptive, 5 densities)")
    print("wrote web/icons/* and web/favicon.png")
    print("wrote store/icon-512.png and store/feature-graphic-1024x500.png")
    print("screenshots: capture from a device; Play needs at least 2")
