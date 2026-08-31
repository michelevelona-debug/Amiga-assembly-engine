#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Ricostruzione dei 16 frame del falo' a 16x16 e riscrittura del foglio
con un quadrato vuoto 16x16 fra un frame e l'altro (e in coda).

NOTA SULLA SORGENTE: l'immagine di partenza non ha una griglia di pixel
reale. I blocchi misurano ~10,5 px, hanno i bordi sfumati e non sono
allineati fra un frame e l'altro; la fiamma piu' alta e' ~23 blocchi,
non 16. Quindi i frame non si possono ritagliare: vanno ricampionati.
Ancoraggi usati (misurati, non stimati):
  - la base della fiamma e' identica in tutti i frame: y=443 (riga 1),
    y=790 (riga 2);
  - il centro orizzontale di ogni frame e' il baricentro dei 34 px sopra
    la base, cioe' la parte che non si muove.
Scala: SY = 236/16 (la fiamma piu' alta riempie esattamente le 16 righe),
SX = 8,2 (la piu' larga occupa ~13 colonne su 16). Le due scale sono
diverse perche' il disegno sorgente e' piu' alto che largo rispetto a una
cella quadrata: a scala unica la fiamma verrebbe larga 7 px su 16.
"""
import numpy as np
from PIL import Image

SRC = '/root/.claude/uploads/ce940bb7-1a6d-54c0-a4a3-37c80d4110ed/4053a280-image.png'
PALETTE = [(0x00, 0x00, 0x00), (0xFF, 0xF7, 0xC2), (0xFF, 0xB3, 0x47),
           (0xB2, 0x3A, 0x1A), (0x3A, 0x1A, 0x0E)]
BANDS = [(200, 460, 443), (560, 800, 790)]      # y0, y1, baseline
SY = 236.0 / 16.0
SX = 8.2
FRAC = 0.70        # porzione centrale del blocco usata per il campionamento
OUT = '/home/claude/out/'


def frame_boxes(mask, y0, y1, gap=14):
    band = mask[y0:y1]
    xs = np.where(band.sum(0) > 0)[0]
    out = []
    s = p = xs[0]
    for x in xs[1:]:
        if x - p > gap:
            out.append((s, p))
            s = x
        p = x
    out.append((s, p))
    return out


def base_center(mask, x0, x1, base, h=34):
    sub = mask[base - h:base + 1, x0:x1 + 1]
    w = sub.sum(0).astype(float)
    if w.sum() == 0:
        w = mask[:, x0:x1 + 1].sum(0).astype(float)
    return x0 + (w * np.arange(len(w))).sum() / w.sum()


def resample(src, cx, base):
    pal = np.array(PALETTE, dtype=float)
    out = np.zeros((16, 16), dtype=np.uint8)
    for r in range(16):
        yc = base + 1 - (15.5 - r) * SY
        for c in range(16):
            xc = cx + (c - 7.5) * SX
            blk = src[int(round(yc - SY * FRAC / 2)):int(round(yc + SY * FRAC / 2)),
                      int(round(xc - SX * FRAC / 2)):int(round(xc + SX * FRAC / 2))]
            if blk.size:
                m = blk.reshape(-1, 3).mean(0)
                out[r, c] = int(np.argmin(((pal - m) ** 2).sum(1)))
    return out


def save_sheet(frames, palette, path, planes):
    sheet = np.zeros((16, 32 * len(frames)), dtype=np.uint8)
    for i, f in enumerate(frames):
        sheet[:, i * 32:i * 32 + 16] = f
    img = Image.fromarray(sheet, mode='P')
    pal = []
    for c in palette:
        pal.extend(c)
    img.putpalette(pal, rawmode='RGB')
    img.save(path + '.png', bits=4, optimize=False)

    pitch = sheet.shape[1] // 8
    raw = bytearray()
    for p in range(planes):
        for y in range(16):
            for bx in range(pitch):
                b = 0
                for k in range(8):
                    if (int(sheet[y, bx * 8 + k]) >> p) & 1:
                        b |= 0x80 >> k
                raw.append(b)
    open(path + '.raw', 'wb').write(bytes(raw))
    return sheet, len(raw)


def main():
    src = np.array(Image.open(SRC).convert('RGB')).astype(float)
    mask = src.max(2) > 60

    frames = []
    for y0, y1, base in BANDS:
        for x0, x1 in frame_boxes(mask, y0, y1):
            frames.append(resample(src, base_center(mask, x0, x1, base), base))
    assert len(frames) == 16

    sheet, n = save_sheet(frames, PALETTE, OUT + 'falo_16x16', 3)
    print('4 colori + trasparente -> 3 bitplane, foglio %dx%d, raw %d byte'
          % (sheet.shape[1], sheet.shape[0], n))

    # variante a 3 colori: il marrone scuro diventa trasparente
    # (entra in uno sprite hardware da 2 bitplane senza attached)
    f3 = [np.where(f == 4, 0, f) for f in frames]
    _, n3 = save_sheet(f3, PALETTE[:4], OUT + 'falo_16x16_3col', 2)
    print('3 colori + trasparente -> 2 bitplane, raw %d byte' % n3)

    np.save('/home/claude/frames.npy', np.array(frames))

    # ---------------------------------------------------------- anteprime
    def to_rgb(arr, palette):
        im = Image.fromarray(arr, mode='P')
        pal = []
        for c in palette:
            pal.extend(c)
        im.putpalette(pal, rawmode='RGB')
        return im.convert('RGB')

    Z, G = 14, 3
    board = Image.new('RGB', (8 * (16 * Z + G) + G, 2 * (16 * Z + G) + G), (70, 70, 70))
    for i, f in enumerate(frames):
        board.paste(to_rgb(f, PALETTE).resize((16 * Z, 16 * Z), Image.NEAREST),
                    (G + (i % 8) * (16 * Z + G), G + (i // 8) * (16 * Z + G)))
    board.save(OUT + 'falo_anteprima.png')

    strip = to_rgb(sheet, PALETTE).resize((sheet.shape[1] * 3, 48), Image.NEAREST)
    strip.save(OUT + 'falo_foglio_zoom.png')

    gif = [to_rgb(f, PALETTE).resize((160, 160), Image.NEAREST) for f in frames]
    gif[0].save(OUT + 'falo_anim.gif', save_all=True, append_images=gif[1:],
                duration=90, loop=0)


if __name__ == '__main__':
    main()
