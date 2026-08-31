#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Spritesheet dell'indicatore orizzontale a liquido - 40x8, 4 colori.

Indici:
  0 = trasparente (interno vuoto del tubo)
  1 = bordo del tubo   (colore fisso, non cambia mai)
  2 = corpo del liquido    -> rosso / arancione / giallo per fascia di livello
  3 = luce del liquido, menisco e bolle -> idem

Le tre fasce si ottengono riscrivendo i colori 2 e 3: il foglio e' uno solo.
1-3 rosso, 4-6 arancione, da 7 in su giallo.

Griglia: una riga per livello (0..10), 9 colonne
  col 0      = stato fermo
  col 1..3   = transizione in salita L -> L+1   (3 frame)
  col 4..8   = transizione in discesa L -> L-1  (5 frame)
Le celle senza senso (salita al livello 10, discesa al livello 0) sono vuote.
"""
import math
import struct
import numpy as np
from PIL import Image

W, H = 40, 8
LEVELS = 11              # 0..10
STEP = 4                 # px di liquido per livello (10*4 = 40)
UP, DOWN = 3, 5          # frame di transizione
COLS = 1 + UP + DOWN     # 9
ROW_TOP, ROW_BOT = 0, 7  # binari del tubo
IN_TOP, IN_BOT = 1, 6    # interno

PAL_ROSSO   = [(0, 0, 0), (56, 56, 74), (200, 32, 60), (255, 110, 130)]
PAL_ARANCIO = [(0, 0, 0), (56, 56, 74), (238, 106, 0), (255, 184, 112)]
PAL_GIALLO  = [(0, 0, 0), (56, 56, 74), (228, 168, 0), (255, 228, 120)]


def palette(level):
    """Fascia di colore: 1-3 rosso, 4-6 arancione, da 7 in su giallo.
    Il livello 0 non ha liquido, quindi il colore e' indifferente."""
    if level <= 3:
        return PAL_ROSSO
    if level <= 6:
        return PAL_ARANCIO
    return PAL_GIALLO
OUT = '/home/claude/out/'


def wave(r, amp, phase):
    """Curvatura del fronte del liquido riga per riga."""
    return int(round(amp * math.sin(2 * math.pi * (r - IN_TOP) / 6.0 + phase)))


def bubbles(seed, n, frames, front):
    """Bolle che salgono: una lista per frame di (x, y)."""
    rng = np.random.RandomState(seed)
    out = [[] for _ in range(frames)]
    if front < 6:
        return out
    for b in range(n):
        bx = int(rng.randint(2, max(3, front - 2)))
        start = int(rng.randint(0, max(1, frames - 1)))
        speed = 6.0 / max(frames, 1)
        for f in range(start, frames):
            y = IN_BOT - (f - start) * speed - rng.rand() * 0.3
            if y < IN_TOP + 1:
                break
            out[f].append((bx, int(round(y))))
    return out


def draw(front, amp=0.0, phase=0.0, bub=()):
    """Un frame 40x8. front = colonne di liquido (0..40)."""
    fr = np.zeros((H, W), dtype=np.uint8)
    fr[ROW_TOP, :] = 1
    fr[ROW_BOT, :] = 1
    if front <= 0:
        return fr
    for r in range(IN_TOP, IN_BOT + 1):
        f = front + (wave(r, amp, phase) if front < W else 0)
        f = max(0, min(W, f))
        if f == 0:
            continue
        if r == IN_BOT:
            fr[r, 0:f] = 1               # ombra sul fondo, stesso colore del tubo
        elif r == IN_TOP:
            fr[r, 0:f] = 3               # riflesso lungo il pelo superiore
        else:
            fr[r, 0:f] = 2
            fr[r, f - 1] = 3             # menisco: bordo d'attacco illuminato
    for bx, by in bub:
        if IN_TOP < by <= IN_BOT and 0 <= bx < W and fr[by, bx] == 2:
            fr[by, bx] = 3
    return fr


def build():
    cells = {}
    for L in range(LEVELS):
        cells[(L, 0)] = draw(L * STEP)
        if L < LEVELS - 1:               # salita L -> L+1
            bl = bubbles(100 + L, 3, UP, L * STEP)
            for k in range(1, UP + 1):
                cells[(L, k)] = draw(L * STEP + k, 1.0, 1.1 * k, bl[k - 1])
        if L > 0:                        # discesa L -> L-1
            bl = bubbles(200 + L, 4, DOWN, L * STEP)
            for k in range(1, DOWN + 1):
                off = [1, 1, 2, 3, 3][k - 1]
                cells[(L, UP + k)] = draw(L * STEP - off, 1.0, 0.9 * k + 2.0,
                                          bl[k - 1])
    return cells


def compose(cells, pitch_x, pitch_y):
    sheet = np.zeros((LEVELS * pitch_y, COLS * pitch_x), dtype=np.uint8)
    for (L, c), fr in cells.items():
        sheet[L * pitch_y:L * pitch_y + H, c * pitch_x:c * pitch_x + W] = fr
    return sheet


def planar(sheet, planes=2):
    h, w = sheet.shape
    pitch = w // 8
    out = bytearray()
    for p in range(planes):
        for y in range(h):
            for bx in range(pitch):
                b = 0
                for k in range(8):
                    if (int(sheet[y, bx * 8 + k]) >> p) & 1:
                        b |= 0x80 >> k
                out.append(b)
    return bytes(out)


def chunk(cid, data):
    if len(data) & 1:
        data += b'\x00'
    return cid + struct.pack('>I', len(data)) + data


def write_ilbm(path, sheet, palette):
    h, w = sheet.shape
    planes = 2
    row = ((w + 15) // 16) * 2
    bmhd = struct.pack('>HHhhBBBBHBBhh', w, h, 0, 0, planes, 0, 0, 0, 0, 10, 11, w, h)
    cmap = b''.join(bytes(c) for c in palette)
    body = bytearray()
    for y in range(h):
        for p in range(planes):
            for bx in range(row):
                b = 0
                for k in range(8):
                    x = bx * 8 + k
                    if x < w and (int(sheet[y, x]) >> p) & 1:
                        b |= 0x80 >> k
                body.append(b)
    payload = (b'ILBM' + chunk(b'BMHD', bmhd) + chunk(b'CMAP', cmap)
               + chunk(b'CAMG', struct.pack('>I', 0)) + chunk(b'BODY', bytes(body)))
    open(path, 'wb').write(b'FORM' + struct.pack('>I', len(payload)) + payload)


def to_img(sheet, palette):
    im = Image.fromarray(sheet, mode='P')
    p = []
    for c in palette:
        p.extend(c)
    im.putpalette(p, rawmode='RGB')
    return im


def main():
    cells = build()

    for name, px, py in (('indicatore_sep', 2 * W, 2 * H),   # 720x176
                         ('indicatore', W + 8, H)):          # 432x88, compatto
        sheet = compose(cells, px, py)
        img = to_img(sheet, PAL_ROSSO)
        img.save(OUT + name + '.png', bits=2, optimize=False)
        raw = planar(sheet)
        open(OUT + name + '.raw', 'wb').write(raw)
        write_ilbm(OUT + name + '.iff', sheet, PAL_ROSSO)
        print('%-14s %3dx%-3d  pitch riga %3d byte  cella %2d byte  raw %6d byte'
              % (name, sheet.shape[1], sheet.shape[0], sheet.shape[1] // 8,
                 px // 8, len(raw)))
        np.save('/home/claude/%s.npy' % name, sheet)

    # ---------------------------------------------------------- verifiche
    sep = np.load('/home/claude/indicatore_sep.npy')
    ok = True
    for L in range(LEVELS):
        for c in range(COLS):
            blk = sep[L * 2 * H:L * 2 * H + H, c * 2 * W:c * 2 * W + W]
            ref = cells.get((L, c))
            if ref is None:
                ok &= not blk.any()
            else:
                ok &= bool((blk == ref).all())
            ok &= not sep[L * 2 * H:(L + 1) * 2 * H, c * 2 * W + W:(c + 1) * 2 * W].any()
        ok &= not sep[L * 2 * H + H:(L + 1) * 2 * H].any()
    print('celle al posto giusto e separatori a zero:', ok)
    print('celle vuote attese:', sum(1 for L in range(LEVELS) for c in range(COLS)
                                     if (L, c) not in cells))
    print('frame disegnati:', len(cells))
    print('livelli, fronte del liquido:', [L * STEP for L in range(LEVELS)])


if __name__ == '__main__':
    main()
