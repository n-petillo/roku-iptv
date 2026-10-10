# Generates the app's image assets (run: PYTHONPATH=<pillow> python3 tools/make_images.py).
# `python3 tools/make_images.py android` instead writes only the Android TV banner and
# launcher icons under android/app/src/main/res/ (images/ is left untouched).
# White shapes are tinted at runtime with Poster.blendColor; *.9.png are Roku 9-patches.
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

OUT = "images"
INK = (12, 12, 12)
S = 4  # supersampling for smooth edges

def aa(img, size):
    return img.resize(size, Image.LANCZOS)

def rounded(w, h, r, stroke=0, color=(255, 255, 255, 255)):
    big = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    box = [0, 0, w * S - 1, h * S - 1]
    if stroke:
        d.rounded_rectangle(box, radius=r * S, outline=color, width=stroke * S)
    else:
        d.rounded_rectangle(box, radius=r * S, fill=color)
    return aa(big, (w, h))

def ninepatch(name, shape, r):
    """Wrap shape in a 1px border marking the middle as stretchable."""
    w, h = shape.size
    img = Image.new("RGBA", (w + 2, h + 2), (0, 0, 0, 0))
    img.paste(shape, (1, 1))
    px = img.load()
    for x in range(1 + r, 1 + w - r):
        px[x, 0] = (0, 0, 0, 255)
        px[x, h + 1] = (0, 0, 0, 255)
    for y in range(1 + r, 1 + h - r):
        px[0, y] = (0, 0, 0, 255)
        px[w + 1, y] = (0, 0, 0, 255)
    img.save(os.path.join(OUT, name + ".9.png"))

def shapes():
    for r in (4, 8, 12):
        ninepatch("r%d" % r, rounded(r * 2 + 4, r * 2 + 4, r), r)
    ninepatch("pill", rounded(76, 76, 36), 36)
    ninepatch("pill_s", rounded(36, 36, 16), 16)
    ninepatch("pill44", rounded(44, 44, 21), 21)
    ninepatch("r6_line", rounded(16, 16, 6, stroke=1), 6)
    ninepatch("r8_line", rounded(20, 20, 8, stroke=1), 8)
    ninepatch("pill_line", rounded(76, 76, 36, stroke=1), 36)
    ninepatch("ring", rounded(32, 32, 12, stroke=3), 12)
    # ink outside an r8 rounded rect, clear inside: rounds the corners of the video preview
    w = h = 20
    big = Image.new("RGBA", (w * S, h * S), INK + (255,))
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * S - 1, h * S - 1], radius=8 * S, fill=(0, 0, 0, 0))
    ninepatch("mask_r8", aa(big, (w, h)), 8)

def icons():
    big = Image.new("RGBA", (20 * S, 20 * S), (0, 0, 0, 0))
    ImageDraw.Draw(big).ellipse([0, 0, 20 * S - 1, 20 * S - 1], fill=(255, 255, 255, 255))
    aa(big, (20, 20)).save(os.path.join(OUT, "dot.png"))

    # filled star with rounded joins (lucide-style)
    import math
    n = 52 * S
    big = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    cx, cy, R, ri = n / 2, n * 0.54, n * 0.46, n * 0.19
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        rad = R if i % 2 == 0 else ri
        pts.append((cx + rad * math.cos(a), cy + rad * math.sin(a)))
    d = ImageDraw.Draw(big)
    d.polygon(pts, fill=(255, 255, 255, 255))
    d.line(pts + [pts[0]], fill=(255, 255, 255, 255), width=int(n * 0.06), joint="curve")
    aa(big, (52, 52)).save(os.path.join(OUT, "star.png"))

    n = 48 * S
    big = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(big).line([(n * .19, n * .53), (n * .38, n * .72), (n * .81, n * .28)], fill=(255, 255, 255, 255), width=int(n * .09), joint="curve")
    aa(big, (48, 48)).save(os.path.join(OUT, "check.png"))

    # play/pause glyph for key caps
    w, h = 36 * S, 20 * S
    big = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    d.polygon([(0, 0), (15 * S, h / 2), (0, h)], fill=(255, 255, 255, 255))
    d.rectangle([22 * S, 0, 25 * S, h], fill=(255, 255, 255, 255))
    d.rectangle([31 * S, 0, 34 * S, h], fill=(255, 255, 255, 255))
    aa(big, (36, 20)).save(os.path.join(OUT, "playpause.png"))

def wash(w, h):
    """Soft teal -> sage -> cream band fading up into ink (approximates the design's wash)."""
    stops = [(0.0, (57, 100, 100)), (0.25, (65, 126, 124)), (0.5, (139, 167, 158)), (0.75, (200, 206, 193)), (1.0, (179, 140, 110))]
    def col(t):
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t <= t1:
                k = (t - t0) / (t1 - t0)
                return tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3))
        return stops[-1][1]
    small = Image.new("RGB", (64, 16))
    px = small.load()
    for y in range(16):
        fade = (y / 15.0) ** 1.6 * 0.55          # ink at the top, 55% wash at the bottom
        for x in range(64):
            c = col(x / 63.0)
            px[x, y] = tuple(int(INK[i] + (c[i] - INK[i]) * fade) for i in range(3))
    return small.resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(24))

def brand(w, h, title_px, with_wash, name, out_dir=OUT):
    img = Image.new("RGB", (w, h), INK)
    if with_wash:
        band = wash(w, int(h * 0.39))
        img.paste(band, (0, h - band.size[1]))
    f = ImageFont.truetype("fonts/ABCNormal-Normal.otf", title_px)
    d = ImageDraw.Draw(img)
    text = "FedSmokerTV"
    bb = d.textbbox((0, 0), text, font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    x, y = (w - tw) / 2 - bb[0], (h - th) / 2 - bb[1]
    d.text((x, y), text, font=f, fill=(255, 255, 255))
    # ember live dot, top-right of the wordmark
    r = max(4, title_px // 9)
    d.ellipse([x + tw + r, y - r * 0.2, x + tw + 3 * r, y + 1.8 * r], fill=(179, 90, 69))
    img.save(os.path.join(out_dir, name))

ANDROID_RES = "android/app/src/main/res"

def launcher(n, round_=False):
    """Short mark for small sizes: white "F" + ember dot on an ink tile with a soft wash."""
    N = n * S
    tile = Image.new("RGB", (N, N), INK)
    band = wash(N, int(N * 0.45))
    tile.paste(band, (0, N - band.size[1]))
    f = ImageFont.truetype("fonts/ABCNormal-Regular.otf", int(N * 0.62))
    d = ImageDraw.Draw(tile)
    bb = d.textbbox((0, 0), "F", font=f)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    r = N * 0.055
    gap = r * 0.9
    # centre the letter + dot group horizontally, the letter vertically
    x = (N - (tw + gap + 2 * r)) / 2 - bb[0]
    y = (N - th) / 2 - bb[1]
    d.text((x, y), "F", font=f, fill=(255, 255, 255))
    dx, dy = x + bb[0] + tw + gap, y + bb[1] - r * 0.3
    d.ellipse([dx, dy, dx + 2 * r, dy + 2 * r], fill=(179, 90, 69))
    mask = Image.new("L", (N, N), 0)
    md = ImageDraw.Draw(mask)
    if round_:
        md.ellipse([0, 0, N - 1, N - 1], fill=255)
    else:
        md.rounded_rectangle([0, 0, N - 1, N - 1], radius=N * 0.22, fill=255)
    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out.paste(tile, (0, 0), mask)
    return aa(out, (n, n))

def android():
    d = os.path.join(ANDROID_RES, "drawable-xhdpi")
    os.makedirs(d, exist_ok=True)
    brand(320, 180, 44, True, "banner.png", out_dir=d)
    for dpi, n in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        d = os.path.join(ANDROID_RES, "mipmap-" + dpi)
        os.makedirs(d, exist_ok=True)
        launcher(n).save(os.path.join(d, "ic_launcher.png"))
        launcher(n, round_=True).save(os.path.join(d, "ic_launcher_round.png"))

if __name__ == "__main__" and sys.argv[1:] == ["android"]:
    android()
elif __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    shapes()
    icons()
    wash(1920, 420).save(os.path.join(OUT, "wash_bottom.png"))
    brand(290, 218, 40, True, "icon_hd.png")
    brand(540, 405, 74, True, "icon_fhd.png")
    brand(1920, 1080, 120, True, "splash_fhd.png")
