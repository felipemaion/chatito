import cv2, numpy as np, subprocess, re, sys, os
from PIL import Image
S = os.path.dirname(os.path.abspath(__file__))
src = '/Users/maion/.claude/image-cache/b7b96c85-bb94-47b3-b6d0-2bd63509845a/5.png'
im = np.array(Image.open(src).convert('RGBA'))
H, W = im.shape[:2]
rgb = im[:, :, :3].astype(np.int32)
alpha = im[:, :, 3]
# máscara: não-branco (e alfa > 0)
white = (rgb.min(axis=2) > 235)
mask = ((~white) & (alpha > 10)).astype(np.uint8) * 255
k = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, k)
mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
n, lab, stats, _ = cv2.connectedComponentsWithStats(mask)
big = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
mask = (lab == big).astype(np.uint8) * 255
# preencher buracos
cnts, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
mask = np.zeros_like(mask); cv2.drawContours(mask, cnts, -1, 255, -1)
print('bbox', cv2.boundingRect(max(cnts, key=cv2.contourArea)), file=sys.stderr)

def potrace(m, name, turd=30, alphamax=1.0):
    p = os.path.join(S, name + '.pbm')
    Image.fromarray(255 - m).convert("1").save(p)
    svg = subprocess.run(['potrace', '-s', '-t', str(turd), '-a', str(alphamax), '-O', '0.4', '-o', '-', p],
                         capture_output=True, text=True).stdout
    tr = re.search(r'<g transform="([^"]+)"', svg).group(1)
    paths = re.findall(r'<path d="([^"]+)"', svg)
    return tr, paths

# regiões de cor dentro da máscara
hsv = cv2.cvtColor(im[:, :, :3], cv2.COLOR_RGB2HSV)
h, s, v = hsv[:, :, 0].astype(int), hsv[:, :, 1].astype(int), hsv[:, :, 2].astype(int)
inside = mask > 0
r, g, b = rgb[:, :, 0], rgb[:, :, 1], rgb[:, :, 2]
yellow = inside & (h >= 22) & (h <= 38) & (s > 90) & (v > 120)
blue = inside & (h >= 85) & (h <= 130) & (s > 60) & (v > 60)
pink = inside & (((h <= 12) | (h >= 160)) & (s > 40) & (v > 120))
dark = inside & (v < 55)
def clean(m, o=3, c=7, minarea=80):
    m = m.astype(np.uint8) * 255
    m = cv2.morphologyEx(m, cv2.MORPH_OPEN, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (o, o)))
    m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (c, c)))
    n, lab, st, _ = cv2.connectedComponentsWithStats(m)
    out = np.zeros_like(m)
    for i in range(1, n):
        if st[i, cv2.CC_STAT_AREA] >= minarea: out[lab == i] = 255
    return out
yellow_m, blue_m, pink_m = clean(yellow, 3, 9, 150), clean(blue, 3, 9, 120), clean(pink, 3, 7, 60)
_n,_lab,_st,_=cv2.connectedComponentsWithStats(yellow_m); _big=1+np.argmax(_st[1:,cv2.CC_STAT_AREA]); yellow_m=((_lab==_big).astype(np.uint8))*255
# olho: pixels escuros na cabeça (quadrante superior direito)
eye = dark.copy(); eye[:, :int(W * 0.58)] = False; eye[:, int(W * 0.70):] = False; eye[int(H * 0.34):, :] = False
eye_m = clean(eye, 3, 5, 15)
ys, xs = np.where(eye_m > 0)
eye_c = (float(xs.mean()), float(ys.mean())) if len(xs) else None
print('eye', eye_c, 'areas', yellow_m.sum()//255, blue_m.sum()//255, pink_m.sum()//255, file=sys.stderr)

def med(m):
    px = rgb[m]
    return '#%02X%02X%02X' % tuple(int(x) for x in np.median(px, axis=0)) if len(px) else None
def pct(m, q):
    px = rgb[m]; return '#%02X%02X%02X' % tuple(int(x) for x in np.percentile(px, q, axis=0))
green = inside & ~(yellow | blue | pink | dark)
print('green med', med(green), 'dark', pct(green, 15), 'light', pct(green, 85), 'yellow', med(yellow_m > 0), 'blue', med(blue_m > 0), 'pink', med(pink_m > 0), file=sys.stderr)

tr, body = potrace(mask, 'body', 40, 1.2)
_, yp = potrace(yellow_m, 'yellow', 20, 1.2)
_, bp = potrace(blue_m, 'blue', 20, 1.2)
_, pp = potrace(pink_m, 'pink', 10, 1.0)
x, y, w, hh = cv2.boundingRect(max(cnts, key=cv2.contourArea))
out = []
out.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x-8} {y-8} {w+16} {hh+16}">')
out.append('''  <defs>
    <linearGradient id="corpo" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="%s"/><stop offset="0.5" stop-color="%s"/><stop offset="1" stop-color="%s"/>
    </linearGradient>
    <radialGradient id="brilho" cx="0.62" cy="0.6" r="0.42">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.28"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="face" cx="0.9" cy="0.18" r="0.16">
      <stop offset="0" stop-color="#D8E86A" stop-opacity="0.75"/><stop offset="1" stop-color="#D8E86A" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="amarelo" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#EEF25C"/><stop offset="1" stop-color="%s"/>
    </linearGradient>
    <linearGradient id="azul" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#1E63B0"/><stop offset="1" stop-color="#1C8C9C"/>
    </linearGradient>
    <linearGradient id="rosa" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#F3B7AC"/><stop offset="1" stop-color="%s"/>
    </linearGradient>
  </defs>''' % (pct(green, 8), med(green), pct(green, 92), med(yellow_m > 0), med(pink_m > 0)))
def grp(paths, fill, extra=''):
    return f'  <g transform="{tr}" fill="{fill}" {extra}>\n' + '\n'.join(f'    <path d="{d}"/>' for d in paths) + '\n  </g>'
out.append(grp(body, 'url(#corpo)'))
out.append(grp(body, 'url(#brilho)'))
out.append(grp(body, 'url(#face)'))
out.append(grp(yp, 'url(#amarelo)'))
out.append(grp(bp, 'url(#azul)'))
out.append(grp(pp, 'url(#rosa)'))
if eye_c:
    ex, ey = eye_c
    out.append(f'  <circle cx="{ex:.1f}" cy="{ey:.1f}" r="7.5" fill="#F4F4F4"/>')
    out.append(f'  <circle cx="{ex+0.5:.1f}" cy="{ey+0.5:.1f}" r="5.2" fill="#1E1E1E"/>')
    out.append(f'  <circle cx="{ex+2.2:.1f}" cy="{ey-1.8:.1f}" r="1.8" fill="#FFFFFF"/>')
out.append('</svg>')
open(os.path.join(S, 'silhueta.svg'), 'w').write('\n'.join(out))
print('written', file=sys.stderr)
