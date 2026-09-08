"""Pós-processa piriquito-silhueta.svg: estilo infantil (contorno, olho grande, bochecha,
bico sorridente, topete, penas) e compõe logo + ícone."""
import re, sys, os
B = os.path.dirname(os.path.abspath(__file__))
svg = open(os.path.join(B, 'piriquito-silhueta.svg')).read()

# 1) cores mais vivas
rep = {
    'id="corpo"': None,
}
svg = re.sub(r'(<linearGradient id="corpo"[^>]*>)\s*<stop[^/]*/><stop[^/]*/><stop[^/]*/>',
             r'\1<stop offset="0" stop-color="#2F8F1E"/><stop offset="0.5" stop-color="#5FC93C"/><stop offset="1" stop-color="#A9EA6C"/>', svg)
svg = re.sub(r'(<linearGradient id="amarelo"[^>]*>)\s*<stop[^/]*/><stop[^/]*/>',
             r'\1<stop offset="0" stop-color="#F7F46E"/><stop offset="1" stop-color="#BCDB12"/>', svg)
svg = re.sub(r'(<linearGradient id="azul"[^>]*>)\s*<stop[^/]*/><stop[^/]*/>',
             r'\1<stop offset="0" stop-color="#2A6FD6"/><stop offset="1" stop-color="#27B0C4"/>', svg)
svg = re.sub(r'(<linearGradient id="rosa"[^>]*>)\s*<stop[^/]*/><stop[^/]*/>',
             r'\1<stop offset="0" stop-color="#FAC9BE"/><stop offset="1" stop-color="#E0939A"/>', svg)

# 2) contorno grosso atrás do corpo (mesmo caminho, só traço)
m = re.search(r'  <g transform="([^"]+)" fill="url\(#corpo\)" >\n((?:    <path d="[^"]+"/>\n)+)  </g>', svg)
tr, body_paths = m.group(1), m.group(2)
outline = f'  <g transform="{tr}" fill="none" stroke="#1E6B1E" stroke-width="90" stroke-linejoin="round" stroke-linecap="round">\n{body_paths}  </g>\n'
svg = svg.replace(m.group(0), outline + m.group(0))

# 3) remover olho antigo
svg = re.sub(r'  <circle cx="[\d.]+" cy="[\d.]+" r="7.5" fill="#F4F4F4"/>\n  <circle[^\n]+\n  <circle[^\n]+\n', '', svg)

details = '''  <!-- detalhes (coordenadas da foto) -->
  <defs>
    <radialGradient id="blush"><stop offset="0" stop-color="#FF8FA3" stop-opacity="0.6"/><stop offset="1" stop-color="#FF8FA3" stop-opacity="0"/></radialGradient>
  </defs>
  <!-- penas da asa (dorso: x 150-330, entre topo e meio do corpo) -->
  <g fill="none" stroke="#1E6B1E" stroke-width="3.5" stroke-linecap="round" opacity="0.5">
    <path d="M170 272 q26 -18 54 -10"/><path d="M204 252 q26 -18 54 -10"/><path d="M240 232 q26 -18 54 -10"/>
    <path d="M186 292 q26 -16 52 -8"/><path d="M226 272 q26 -16 52 -8"/><path d="M266 252 q26 -16 52 -8"/>
    <!-- cauda -->
    <path d="M42 344 L140 306"/><path d="M52 352 L146 318"/>
    <!-- barriga -->
    <path d="M318 322 q11 10 22 0 q11 10 22 0 q11 10 22 0"/>
    <path d="M340 298 q11 10 22 0 q11 10 22 0"/>
  </g>
  <!-- topete -->
  <g fill="#6FD34A" stroke="#1E6B1E" stroke-width="4" stroke-linejoin="round">
    <path d="M404 86 C398 66 418 60 420 78 C424 62 446 64 438 84 Z"/>
  </g>
  <!-- bochecha -->
  <circle cx="452" cy="150" r="16" fill="url(#blush)"/>
  <!-- olho grande -->
  <circle cx="433" cy="120" r="15" fill="#FFFFFF" stroke="#1E6B1E" stroke-width="3"/>
  <circle cx="435" cy="121" r="10.5" fill="#3B2A1E"/>
  <circle cx="436" cy="122" r="6" fill="#111111"/>
  <circle cx="440" cy="116" r="3.6" fill="#FFFFFF"/>
  <circle cx="431" cy="126" r="1.8" fill="#FFFFFF"/>
  <!-- bico sorridente -->
  <path d="M469 166 L491 183 C488 190 478 189 473 183 C469 178 468 172 469 166 Z" fill="#D98E93" stroke="#1E6B1E" stroke-width="3" stroke-linejoin="round"/>
  <path d="M467 138 C486 128 504 140 502 158 C501 170 497 178 493 183 L470 165 C465 156 464 146 467 138 Z" fill="url(#rosa)" stroke="#1E6B1E" stroke-width="3" stroke-linejoin="round"/>
  <path d="M472 166 Q482 172 491 182" fill="none" stroke="#1E6B1E" stroke-width="3" stroke-linecap="round"/>
  <path d="M474 143 C482 138 492 142 496 150" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round" opacity="0.7"/>
'''
svg = svg.replace('</svg>', details + '</svg>')
open(os.path.join(B, 'piriquito-silhueta-kids.svg'), 'w').write(svg)

# 4) compor logo e ícone
vb = [float(v) for v in re.search(r'viewBox="([^"]+)"', svg).group(1).split()]
inner = svg[svg.index('<defs>'):svg.rindex('</svg>')]
sc = 440 / vb[2]; tx = 16 - vb[0] * sc; ty = 488 - (vb[1] + vb[3]) * sc
bubble = '''  <!-- balão de fala -->
  <path d="M322 36 H478 a28 28 0 0 1 28 28 V120 a28 28 0 0 1 -28 28 H430 L432 190 L392 148 H322 a28 28 0 0 1 -28 -28 V64 a28 28 0 0 1 28 -28 Z" fill="#1E6B1E"/>
  <path d="M400 76 c-10 -12 -28 -4 -26 10 c2 12 26 26 26 26 s24 -14 26 -26 c2 -14 -16 -22 -26 -10 z" fill="#FF7A90"/>
  <circle cx="352" cy="92" r="9" fill="#FFFFFF"/><circle cx="448" cy="92" r="9" fill="#FFFFFF"/>
  <!-- brilhinhos -->
  <g fill="#FFD54A">
    <path d="M292 176 l4 10 10 4 -10 4 -4 10 -4 -10 -10 -4 10 -4 z"/>
    <path d="M498 192 l3 8 8 3 -8 3 -3 8 -3 -8 -8 -3 8 -3 z"/>
    <path d="M60 300 l3 8 8 3 -8 3 -3 8 -3 -8 -8 -3 8 -3 z"/>
  </g>
'''
body = f'  <g transform="translate({tx:.2f} {ty:.2f}) scale({sc:.5f})">\n{inner}  </g>\n'
head = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">\n'
open(os.path.join(B, 'piriquito-logo.svg'), 'w').write(head + '  <!-- Piriquito: silhueta real do periquito em estilo infantil, falando -->\n' + body + bubble + '</svg>\n')
open(os.path.join(B, 'piriquito-icon.svg'), 'w').write(head + '  <rect width="512" height="512" rx="112" fill="#FFF6D6"/>\n  <g transform="translate(30 30) scale(0.883)">\n' + body + bubble + '  </g>\n</svg>\n')
print('ok')
