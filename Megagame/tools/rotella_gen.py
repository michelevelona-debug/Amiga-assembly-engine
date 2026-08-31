#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Spritesheet delle rotelle del punteggio - stile contatore elettromeccanico.
Celle 8x8, 4 colori (2 bitplane), indice 0 opaco.

Riga 1 : 10 cifre x (1 frame a riposo + 3 frame di transizione) = 40 frame = 320 px
Riga 2 : 4 frame di rotazione veloce (motion blur)

Modello del tamburo
-------------------
La strip di texture ha PITCH=8 righe per cifra (glifo 6 righe + 2 di stacco).
La finestra visibile copre 10 righe di texture su 8 righe di schermo:
le 6 righe centrali sono 1:1 (cifre nitide, nessun filtraggio), mentre la
prima e l'ultima riga comprimono 2 righe di texture in 1 -> e' li' che il
cilindro "gira via", ed e' anche dove l'ombreggiatura e' piu' scura, quindi
la compressione non si legge come sfocatura ma come curvatura.
Lo scorrimento e' di 2 righe di texture per frame: 4 frame = una cifra.
"""
import math
import numpy as np
from PIL import Image

# ---------------------------------------------------------------- parametri
SS     = 16         # sub-campioni verticali per riga di texture
CELL   = 8
PITCH  = 8          # righe di texture per cifra
NDIG   = 10
TEX_H  = PITCH * NDIG          # 80 righe = giro completo del tamburo
STEPS  = 4                     # frame per cifra

# intervallo di texture coperto da ogni riga di schermo (relativo al centro)
ROWS_T = [(-5.0, -3.0), (-3.0, -2.0), (-2.0, -1.0), (-1.0, 0.0),
          (0.0, 1.0), (1.0, 2.0), (2.0, 3.0), (3.0, 5.0)]

R_CYL  = 4.42       # raggio del cilindro in righe di texture (R*sin(5/R)=4)
GAIN   = 1.35       # durezza della caduta di luce ai bordi
LIGHT  = 0.05       # luce spostata verso l'alto

FACE   = 0.34       # luminanza della faccia del tamburo
INK    = 1.00       # luminanza della cifra
THR    = (0.18, 0.47, 0.78)    # soglie di quantizzazione a 4 livelli

PALETTE = [(0, 0, 0), (56, 56, 68), (150, 150, 166), (244, 244, 252)]

# ------------------------------------------------------------- glifi 6w x 6h
GLYPHS = [
    ".####."
    "#....#"
    "#....#"
    "#....#"
    "#....#"
    ".####.",   # 0

    "..#..."
    ".##..."
    "..#..."
    "..#..."
    "..#..."
    ".####.",   # 1

    ".####."
    "#....#"
    "....#."
    "..##.."
    ".#...."
    "######",   # 2

    ".####."
    ".....#"
    "..###."
    ".....#"
    "#....#"
    ".####.",   # 3

    "#...#."
    "#...#."
    "#...#."
    "######"
    "....#."
    "....#.",   # 4

    "######"
    "#....."
    "#####."
    ".....#"
    "#....#"
    ".####.",   # 5

    ".####."
    "#....."
    "#####."
    "#....#"
    "#....#"
    ".####.",   # 6

    "######"
    ".....#"
    "....#."
    "...#.."
    "..#..."
    "..#...",   # 7

    ".####."
    "#....#"
    ".####."
    "#....#"
    "#....#"
    ".####.",   # 8

    ".####."
    "#....#"
    "#....#"
    ".#####"
    ".....#"
    ".####.",   # 9
]
GW, GH = 6, 6
GX = 1              # colonna iniziale del glifo nella cella (margine 1 e 1)
GY = 1              # riga iniziale del glifo nella cella (stacco 1 sopra, 1 sotto)


def build_texture():
    """Strip verticale: TEX_H righe x CELL colonne, 1.0 = inchiostro."""
    tex = np.zeros((TEX_H, CELL), dtype=np.float32)
    for d, g in enumerate(GLYPHS):
        for r in range(GH):
            for c in range(GW):
                if g[r * GW + c] == '#':
                    tex[d * PITCH + GY + r, GX + c] = 1.0
    return tex


def shade(tc):
    """Luce sul cilindro alla posizione di texture tc (relativa al centro)."""
    th = tc / R_CYL + LIGHT
    return max(0.0, math.cos(th * GAIN))


def sample(tex, t0, t1, phase):
    """Media della texture sull'intervallo [t0,t1) traslato di phase."""
    acc = np.zeros(CELL, dtype=np.float64)
    n = max(1, int(round((t1 - t0) * SS)))
    for i in range(n):
        t = phase + t0 + (i + 0.5) * (t1 - t0) / n
        acc += tex[int(math.floor(t)) % TEX_H]
    return acc / n


def render(tex, phases):
    """Cella 8x8 in luminanza, mediando su una lista di fasi (>1 = motion blur)."""
    out = np.zeros((CELL, CELL), dtype=np.float64)
    for y, (t0, t1) in enumerate(ROWS_T):
        sh = shade((t0 + t1) / 2.0)
        ink = np.zeros(CELL, dtype=np.float64)
        for ph in phases:
            ink += sample(tex, t0, t1, ph)
        ink /= len(phases)
        out[y] = (FACE + ink * (INK - FACE)) * sh
    return out


def spin_profile(tex, blur=3.0, boost=1.6):
    """Profilo di riga della strip, spalmato: e' cio' che resta visibile quando
    il tamburo gira troppo veloce per leggere la cifra. Periodo 8 righe."""
    rowavg = tex.mean(axis=1)
    n = int(blur * SS)
    fine = np.zeros(TEX_H * SS)
    for i in range(TEX_H * SS):
        acc = 0.0
        for j in range(n):
            t = (i + j - n / 2.0) / SS
            acc += rowavg[int(math.floor(t)) % TEX_H]
        fine[i] = acc / n
    m = fine.mean()
    return 1.0 + boost * (fine / m - 1.0)      # modulazione centrata su 1


def render_spin(tex, fine, phase):
    """Cella 8x8: smear verticale con la banda di luce che sale."""
    colavg = tex.mean(axis=0)
    flat = np.where(colavg > 0, colavg[colavg > 0].mean(), 0.0)
    colavg = 0.5 * colavg + 0.5 * flat        # smear piu' pulito in orizzontale
    out = np.zeros((CELL, CELL), dtype=np.float64)
    for y, (t0, t1) in enumerate(ROWS_T):
        sh = shade((t0 + t1) / 2.0)
        n = max(1, int(round((t1 - t0) * SS)))
        mod = 0.0
        for i in range(n):
            t = phase + t0 + (i + 0.5) * (t1 - t0) / n
            mod += fine[int(math.floor(t * SS)) % (TEX_H * SS)]
        mod /= n
        ink = np.clip(colavg * mod, 0.0, 1.0)
        out[y] = (FACE + ink * (INK - FACE)) * sh
    return out


def quantize(lum):
    q = np.zeros(lum.shape, dtype=np.uint8)
    for i, t in enumerate(THR):
        q[lum >= t] = i + 1
    return q


def main():
    tex = build_texture()
    sheet = np.zeros((16, 320), dtype=np.uint8)

    # --- riga 1: cifra a riposo + 3 frame di transizione
    for d in range(NDIG):
        for k in range(STEPS):
            phase = d * PITCH + GY + GH / 2.0 + k * (PITCH / STEPS)
            col = (d * STEPS + k) * CELL
            sheet[0:8, col:col + 8] = quantize(render(tex, [phase]))

    # --- riga 2: rotazione veloce (4 frame in ciclo continuo, passo 2 righe)
    fine = spin_profile(tex, blur=3.0, boost=1.7)
    for i, ph in enumerate((0.0, 2.0, 4.0, 6.0)):
        sheet[8:16, i * CELL:i * CELL + 8] = quantize(render_spin(tex, fine, ph))

    img = Image.fromarray(sheet, mode='P')
    pal = []
    for c in PALETTE:
        pal.extend(c)
    img.putpalette(pal, rawmode='RGB')
    img.save('/home/claude/out/rotella_punteggio.png', bits=2, optimize=False)

    # --- raw planare 2 bitplane, piani sequenziali (piano0 = bit basso)
    pitch = sheet.shape[1] // 8
    raw = bytearray()
    for p in range(2):
        for y in range(sheet.shape[0]):
            for bx in range(pitch):
                b = 0
                for k in range(8):
                    if (sheet[y, bx * 8 + k] >> p) & 1:
                        b |= 0x80 >> k
                raw.append(b)
    open('/home/claude/out/rotella_punteggio.raw', 'wb').write(bytes(raw))

    # ------------------------------------------------------------- preview
    rgb = img.convert('RGB')
    Z = 10
    big = rgb.resize((320 * Z, 16 * Z), Image.NEAREST)
    px = big.load()
    for fx in range(41):
        x = min(fx * CELL * Z, big.width - 1)
        for y in range(big.height):
            px[x, y] = (200, 0, 0)
    for y in (0, 8 * Z, 16 * Z - 1):
        for x in range(big.width):
            px[x, y] = (200, 0, 0)
    big.save('/home/claude/out/preview_full.png')

    det = rgb.crop((0, 0, 96, 16)).resize((96 * 22, 16 * 22), Image.NEAREST)
    det.save('/home/claude/out/preview_detail.png')

    # tutte le cifre a riposo affiancate, come si vedrebbero in un punteggio
    rest = Image.new('RGB', (80, 8))
    for d in range(NDIG):
        rest.paste(rgb.crop((d * STEPS * 8, 0, d * STEPS * 8 + 8, 8)), (d * 8, 0))
    rest.resize((80 * 16, 8 * 16), Image.NEAREST).save('/home/claude/out/preview_rest.png')

    # ------------------------------------------------------------- animazioni
    frames = [rgb.crop((f * 8, 0, f * 8 + 8, 8)).resize((192, 192), Image.NEAREST)
              for f in range(40)]
    frames[0].save('/home/claude/out/rotella_rullo.gif', save_all=True,
                   append_images=frames[1:], duration=90, loop=0)
    spin = [rgb.crop((f * 8, 8, f * 8 + 8, 16)).resize((192, 192), Image.NEAREST)
            for f in range(4)]
    spin[0].save('/home/claude/out/rotella_veloce.gif', save_all=True,
                 append_images=spin[1:], duration=60, loop=0)

    # ------------------------------------------------------------- dump ascii
    ch = ' -+#'
    for f in range(6):
        print('--- frame %d' % f)
        for y in range(8):
            print('   ' + ''.join(ch[sheet[y, f * 8 + x]] for x in range(8)))
    print('--- spin')
    for y in range(8):
        print('   ' + '  '.join(''.join(ch[sheet[8 + y, i * 8 + x]] for x in range(8))
                                for i in range(4)))
    print('istogramma colori:', np.bincount(sheet.ravel(), minlength=4))


if __name__ == '__main__':
    main()
