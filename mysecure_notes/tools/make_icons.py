"""Рисует иконку ASRbox: тёмно-синий «squircle» с градиентом и белой коробкой."""
from PIL import Image, ImageDraw, ImageChops
import os, sys

S = 1024
out = sys.argv[1] if len(sys.argv) > 1 else 'assets/icon'
os.makedirs(out, exist_ok=True)


def squircle_mask(size, n=5.0):
    # суперэллипс |x|^n + |y|^n = 1 — форма иконок Apple
    big = size * 2
    m = Image.new('L', (big, big), 0)
    px = m.load()
    c = big / 2
    for y in range(big):
        for x in range(big):
            dx = abs(x - c) / c
            dy = abs(y - c) / c
            if dx ** n + dy ** n <= 1:
                px[x, y] = 255
    return m.resize((size, size), Image.LANCZOS)


def base():
    top, bot = (64, 156, 255), (10, 60, 200)
    g = Image.new('RGB', (S, S))
    d = ImageDraw.Draw(g)
    for y in range(S):
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)))
    img = g.convert('RGBA')
    img.putalpha(squircle_mask(S))

    # глиф: коробка — белый контур со скруглением, крышка-линия и точка-замок
    gl = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(gl)
    w = 58
    x0, y0, x1, y1 = 262, 300, 762, 740
    gd.rounded_rectangle([x0, y0, x1, y1], radius=84, outline=(255, 255, 255, 255), width=w)
    gd.rounded_rectangle([x0, y0, x1, y0 + 150], radius=84, fill=(255, 255, 255, 255))
    gd.rectangle([x0 + 30, y0 + 90, x1 - 30, y0 + 150], fill=(255, 255, 255, 255))
    gd.rounded_rectangle([452, 470, 572, 530], radius=30, fill=(255, 255, 255, 255))
    # лёгкая тень под глифом
    sh = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    sh.paste((0, 20, 90, 70), (0, 14), gl.split()[3])
    img = Image.alpha_composite(img, sh)
    return Image.alpha_composite(img, gl)


icon = base()
icon.save(os.path.join(out, 'icon_1024.png'))

for name, px in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    d = os.path.join(out, 'android', f'mipmap-{name}')
    os.makedirs(d, exist_ok=True)
    icon.resize((px, px), Image.LANCZOS).save(os.path.join(d, 'ic_launcher.png'))

icon.save(os.path.join(out, 'app_icon.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
icon.save(os.path.join(out, 'tray.ico'), sizes=[(16, 16), (24, 24), (32, 32), (48, 48)])
icon.resize((512, 512), Image.LANCZOS).save(os.path.join(out, 'icon_512.png'))
print('ok')
