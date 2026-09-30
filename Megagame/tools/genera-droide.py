#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-droide.py - il droide che fluttua sopra l'armatura nella schermata
#   del titolo. Cinque pose: due getti di reazione che pulsano e due luci
#   rosse che si accendono e si spengono.
#
# USO (dalla cartella Megagame):
#     python3 tools/genera-droide.py            scrive l'arte
#     python3 tools/genera-droide.py --mappa    stampa la mappa delle zone
#
# COSA SCRIVE
#   grafica/droide.raw        240x24, 8 piani, le 5 pose affiancate
#   grafica/droide_mask.raw   240x24, 1 piano, la maschera per il cookie cut
#   risorse/grafica/*.iff     le due anteprime da aprire in un editor
#
# PERCHE' 8 PIANI E NON UNO SPRITE
# Il titolo gira a 8 bitplane e **usa tutte e 256 le voci di palette** (contate
# sui pixel di title.raw, non sulla palette). Uno sprite attaccato pretende un
# blocco allineato di 16 voci tutto suo: per averlo bisognerebbe sovrascrivere
# 16 colori del titolo, cioe' guastare l'immagine. Un BOB invece si disegna
# dentro gli stessi piani e puo' usare i colori che il titolo ha GIA': costa
# zero voci. E' la stessa misura che ha deciso la questione, non una
# preferenza.
#
# I COLORI SI LEGGONO, NON SI RICOPIANO
# La palette e' quella vera del titolo, letta da grafica/title.pal - lo stesso
# file che LoadAGAPalette256 versa nei registri. Se un giorno il titolo cambia
# palette, questo script ridisegna il droide coi colori nuovi invece di
# aprirsi con colori che il gioco non ha.
#
# PERCHE' LA MASCHERA E' UN FILE E NON L'OR DEI PIANI
# BuildBobMask ricava la maschera dall'OR dei piani, e quel trucco impone che
# nessun pixel dell'arte valga 0. Qui la voce 0 di title.pal e' $f2f9fb, cioe'
# il BIANCO PIU' ACCESO che il titolo possiede: escluderla vorrebbe dire
# rinunciarci proprio sui riflessi della calotta e sul nucleo della fiamma.
# Con la maschera scritta a parte l'indice 0 torna disponibile e un buco per
# distrazione non puo' proprio capitare. Costa 720 byte in tutto.
#
# LA GEOMETRIA E' QUELLA DI DisegnaBOB, non una nuova
#   slot  = (larghezza/16 + 1) word   <- il +1 e' lo sconfinamento dello shift
#   pitch = pose * slot
#   piano = altezza * pitch
# Sono le stesse tre righe che DisegnaBOB calcola da bob_Larghezza e
# bob_Frames. Cosi' l'arte del droide ha la stessa forma di Omino32 e Nemico32
# e non serve una seconda convenzione da ricordare.
# ============================================================================
import os, sys
import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grafica

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORGENTE = os.path.join(RADICE, 'risorse', 'grafica', 'droide-sorgente.png')
PALETTE = os.path.join(RADICE, 'grafica', 'title.pal')
DEST_ARTE = os.path.join(RADICE, 'grafica', 'droide.raw')
DEST_MASK = os.path.join(RADICE, 'grafica', 'droide_mask.raw')

# ---------------------------------------------------------------- geometria
LARGH = 32                      # px del droide
ALT = 24                        # righe. Il rapporto del disegno e' 1,34:
                                # 32x32 lo schiaccerebbe in un altro robot.
POSE = 5
PIANI = 8                       # come il titolo
SLOT_W = LARGH // 16 + 1        # 3 word: due di arte piu' una per lo shift
CELLA = SLOT_W * 16             # 48 px per cella
W_TOT = CELLA * POSE            # 240 px: le cinque pose affiancate
PITCH = SLOT_W * 2 * POSE       # 30 byte
PIANO = PITCH * ALT             # 720 byte

# --------------------------------------------------------- le zone animate
# Colonne e righe misurate sulla griglia 32x24 (python3 tools/genera-droide.py
# --mappa le ristampa). NON sono stimate a occhio: vengono dalla mappa dei
# pixel rosso-dominanti stampata da --mappa.
GETTI = (6, 27)                 # colonna centrale dei due ugelli
Y_UGELLO = 20                   # prima riga di fiamma
LUCI = ((8, 13, 15, 19),        # x0, x1, y0, y1 della luce sinistra
        (18, 23, 15, 19))       # e della destra

# Profilo della fiamma, dall'ugello in giu': (mezza larghezza, colore).
# Azzurro all'ugello e rosso in punta, non il contrario: il getto e' piu'
# caldo dove esce.
FIAMMA = [(1, (170, 225, 255)),
          (1, (255, 255, 235)),
          (1, (255, 150,  60)),
          (0, (200,  40,  25))]

LUCE_ACCESA = (255,  58,  40)
LUCE_SPENTA = ( 58,  14,  16)
LUCE_NUCLEO = (255, 205, 190)   # il puntino caldo al centro, solo al massimo

# Le cinque pose: (quanto sono accese le luci, righe di fiamma).
# Le luci fanno acceso-acceso-spento-spento-fioco e la fiamma pulsa su un
# ritmo diverso, cosi' il giro non batte tutto insieme.
POSA = [(1.00, 3), (1.00, 4), (0.00, 2), (0.00, 3), (0.45, 4)]
SBANDA = [0, 1, 0, -1, 0]       # la punta della fiamma non sta ferma


def leggi_palette():
    """Le 256 voci del titolo, da grafica/title.pal ($00RRGGBB big endian)."""
    p = np.fromfile(PALETTE, dtype='>u4')
    if p.size != 256:
        raise SystemExit('title.pal ha %d voci invece di 256' % p.size)
    return np.stack([(p >> 16) & 255, (p >> 8) & 255, p & 255], axis=1).astype(int)


def base():
    """Il droide fermo: RGB LARGHxALT piu' la maschera dell'opacita'.
    Il fondo del PNG e' nero e la soglia e' bassa perche' il sorgente e' un
    rendering con del rumore, non pixel art pulita."""
    im = Image.open(SORGENTE).convert('RGB')
    a = np.asarray(im).astype(int)
    piena = a.sum(axis=2) > 24
    ys, xs = np.where(piena)
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    crop = im.crop((x0, y0, x1 + 1, y1 + 1))
    rgb = np.asarray(crop.resize((LARGH, ALT), Image.LANCZOS)).astype(float)
    mk = Image.fromarray((piena[y0:y1 + 1, x0:x1 + 1] * 255).astype(np.uint8))
    op = np.asarray(mk.resize((LARGH, ALT), Image.LANCZOS)).astype(float) > 110
    return rgb, op


def pixel_luce(rgb, op, box):
    """I pixel rosso-dominanti dentro un riquadro: sono la lente della luce.
    Il resto della struttura (la calotta bianca, il blu attorno) resta fermo -
    si accende e si spegne solo la lente, come farebbe una lampada vera."""
    x0, x1, y0, y1 = box
    out = []
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            r, g, b = rgb[y, x]
            if op[y, x] and r > 90 and r > g + 40 and r > b + 30:
                out.append((x, y))
    return out


def componi(rgb0, op0, luci, posa):
    """Una posa: RGB piu' opacita'."""
    acceso, lung = POSA[posa]
    rgb = rgb0.copy()
    op = op0.copy()

    for gruppo in luci:
        for (x, y) in gruppo:
            rgb[y, x] = (np.array(LUCE_SPENTA, float) * (1 - acceso)
                         + np.array(LUCE_ACCESA, float) * acceso)
    if acceso > 0.8:
        for gruppo in luci:
            if gruppo:
                xm = sum(p[0] for p in gruppo) / len(gruppo)
                ym = sum(p[1] for p in gruppo) / len(gruppo)
                px = min(gruppo, key=lambda p: (p[0] - xm) ** 2 + (p[1] - ym) ** 2)
                rgb[px[1], px[0]] = LUCE_NUCLEO

    # la fiamma si RIDISEGNA, non si ritocca: cosi' la sua lunghezza e' un
    # numero di questo file e non una proprieta' nascosta del PNG
    for cx in GETTI:
        for dy in range(len(FIAMMA)):
            for x in range(cx - 1, cx + 2):
                if 0 <= x < LARGH and Y_UGELLO + dy < ALT:
                    op[Y_UGELLO + dy, x] = False
        for dy in range(lung):
            mez, col = FIAMMA[dy]
            xc = cx + (SBANDA[posa] if dy >= 2 else 0)
            y = Y_UGELLO + dy
            if y >= ALT:
                break
            for x in range(xc - mez, xc + mez + 1):
                if 0 <= x < LARGH:
                    rgb[y, x] = col
                    op[y, x] = True
    return rgb, op


def quantizza(rgb, op, pal):
    """L'indice del titolo piu' vicino, per ogni pixel. Tutte e 256 le voci
    sono candidate, zero compreso: la maschera e' un file a parte, quindi un
    pixel di valore 0 non e' piu' un buco."""
    d = ((rgb.reshape(-1, 1, 3) - pal.reshape(1, -1, 3)) ** 2).sum(axis=2)
    q = d.argmin(axis=1).reshape(ALT, LARGH)
    q[~op] = 0
    return q


def main():
    pal = leggi_palette()
    rgb0, op0 = base()
    luci = [pixel_luce(rgb0, op0, b) for b in LUCI]

    if '--mappa' in sys.argv:
        r, g, b = rgb0[:, :, 0], rgb0[:, :, 1], rgb0[:, :, 2]
        ros = op0 & (r > 90) & (r > g + 40) & (r > b + 30)
        print('    ' + ''.join(str(x % 10) for x in range(LARGH)))
        for y in range(ALT):
            print('%2d  %s' % (y, ''.join(
                '.' if not op0[y, x] else ('R' if ros[y, x] else '#')
                for x in range(LARGH))))
        print('\n. vuoto   R rosso (candidato luce)   # corpo')
        print('getti alle colonne %s, ugello alla riga %d' % (str(GETTI), Y_UGELLO))
        for i, gr in enumerate(luci):
            print('luce %d: %d pixel' % (i, len(gr)))
        return 0

    # una cella per posa dentro un'unica immagine 240x24
    celle = [[0] * W_TOT for _ in range(ALT)]
    mcelle = [[0] * W_TOT for _ in range(ALT)]
    for p in range(POSE):
        rgb, op = componi(rgb0, op0, luci, p)
        q = quantizza(rgb, op, pal)
        for y in range(ALT):
            for x in range(LARGH):
                celle[y][p * CELLA + x] = int(q[y, x])
                mcelle[y][p * CELLA + x] = 1 if op[y, x] else 0

    tav = [tuple(c) for c in pal]
    n, n_iff, p_iff = grafica.salva(DEST_ARTE, celle, W_TOT, ALT, PIANI, tav)
    nm, nm_iff, pm_iff = grafica.salva(DEST_MASK, mcelle, W_TOT, ALT, 1,
                                       [(0, 0, 0), (255, 255, 255)])

    print('droide.raw       %5d byte   %dx%d, %d piani, %d pose'
          % (n, W_TOT, ALT, PIANI, POSE))
    print('droide_mask.raw  %5d byte   %dx%d, 1 piano' % (nm, W_TOT, ALT))
    print('anteprime        %s' % os.path.relpath(p_iff, RADICE))
    print('                 %s' % os.path.relpath(pm_iff, RADICE))
    print()
    print('Le EQU da tenere in pari con questi file (Gioco.s):')
    print('  DROIDE_LARGH        %d' % LARGH)
    print('  DROIDE_ALT          %d' % ALT)
    print('  DROIDE_POSE         %d' % POSE)
    print('  DROIDE_PIANI        %d' % PIANI)
    print('  DROIDE_SLOT_W       %d   (word per cella, shift compreso)' % SLOT_W)
    print('  DROIDE_PITCH        %d   byte per riga dello sheet' % PITCH)
    print('  DROIDE_PIANO        %d   byte per piano' % PIANO)
    print('  DROIDE_LEN_ATTESA   %d   guardia sulla lunghezza del file' % n)
    print('  DROIDE_MASK_LEN     %d' % nm)
    return 0


if __name__ == '__main__':
    sys.exit(main())
