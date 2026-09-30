#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# anteprima-mappa.py - guarda la mappa invece di immaginarla.
#
# USO (dalla cartella Megagame):
#     python3 tools/anteprima-mappa.py
#
# PRODUCE in risorse/grafica/:
#     mappa-arte.png        la mappa di oggi montata con le TILE VERE
#     mappa-indici.png      la stessa mappa a 1 PIXEL PER TILE, ingrandita:
#                           e' l'aspetto che avrebbe la superficie di EDITING
#                           se la mappa si disegnasse come immagine indicizzata
#     tavola-tile.png       le tile del foglio numerate, per sapere chi e' chi
#
# COME LEGGE I COLORI: dai blocchi copper GamePalHi/GamePalLo di Gioco.s,
# ricomponendo i 24 bit come fa InitPalette8BPL (nibble alti << 4 | bassi).
# Non c'e' una palette ricopiata qui dentro: sarebbe una seconda copia che
# diverge alla prima modifica.
#
# LA MAPPA la legge dal blocco `MAPPA:` del sorgente. Quando la mappa diventera'
# un file, qui si cambia UNA funzione.
# ============================================================================
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valori

from PIL import Image

RADICE = valori.RADICE
TILE = 16
FOGLIO_COLS = 20          # tile per riga in Tiles.raw (lo dice la DIVU #20 di
                          # DisegnaSfondo, non un commento)
FOGLIO_PITCH = 40         # byte per riga del foglio
FOGLIO_RIGHE = 256
PIANI = 5


def _rami_vivi(righe, tab):
    """Le righe che l'assemblatore vede davvero, valutando i condizionali."""
    pila = [True]
    fuori = []
    for l in righe:
        c = l.split(';')[0].rstrip()
        m = re.match(r'^\s+IF(NE|EQ|GE|GT|LE|LT)\s+(.+)$', c, re.I)
        if m:
            try:
                v = valori._numero(m.group(2).strip(), tab)
                vivo = valori._CONDIZIONI[m.group(1).upper()](v)
            except Exception:
                vivo = True
            pila.append(pila[-1] and vivo)
            continue
        if re.match(r'^\s+ENDC\b', c, re.I):
            if len(pila) > 1:
                pila.pop()
            continue
        if pila[-1]:
            fuori.append(c)
    return fuori


def palette24(tab):
    """I 32 colori come long $00RRGGBB, ricostruiti da GamePalHi/GamePalLo."""
    testo = valori._espandi(valori.SORGENTE)
    inizio_hi = next(i for i, l in enumerate(testo) if l.startswith('GamePalHi:'))
    inizio_lo = next(i for i, l in enumerate(testo) if l.startswith('GamePalLo:'))
    fine_lo = next(i for i, l in enumerate(testo[inizio_lo:], inizio_lo)
                   if 'Ripristino BPLCON3' in l)

    def coppie(blocco):
        fuori = {}
        for c in _rami_vivi(blocco, tab):
            m = re.search(r'\bdc\.w\s+(.+)$', c, re.I)
            if not m:
                continue
            voci = [v.strip() for v in m.group(1).split(',')]
            for i in range(0, len(voci) - 1, 2):
                try:
                    reg = valori._numero(voci[i], tab)
                    val = valori._numero(voci[i + 1], tab)
                except Exception:
                    continue
                if 0x180 <= reg <= 0x1be and (reg & 1) == 0:
                    fuori[(reg - 0x180) // 2] = val
        return fuori

    hi = coppie(testo[inizio_hi:inizio_lo])
    lo = coppie(testo[inizio_lo:fine_lo])
    pal = []
    for i in range(32):
        h = hi.get(i, 0)
        b = lo.get(i, 0)
        r = ((h >> 8) & 15) << 4 | ((b >> 8) & 15)
        g = ((h >> 4) & 15) << 4 | ((b >> 4) & 15)
        bl = (h & 15) << 4 | (b & 15)
        pal.append((r, g, bl))
    return pal


def foglio_tile():
    """Ogni tile del foglio come lista di 16x16 INDICI (0..31)."""
    dati = open(os.path.join(RADICE, 'grafica', 'Tiles.raw'), 'rb').read()
    piano = FOGLIO_PITCH * FOGLIO_RIGHE
    righe_tile = FOGLIO_RIGHE // TILE
    fuori = []
    for tr in range(righe_tile):
        for tc in range(FOGLIO_COLS):
            cella = []
            for y in range(TILE):
                riga = tr * TILE + y
                px = []
                for x in range(TILE):
                    bx = tc * 2 + (x >> 3)
                    bit = 7 - (x & 7)
                    v = 0
                    for p in range(PIANI):
                        b = dati[p * piano + riga * FOGLIO_PITCH + bx]
                        v |= ((b >> bit) & 1) << p
                    px.append(v)
                cella.append(px)
            fuori.append(cella)
    return fuori


def mappa_dal_sorgente(tab):
    """Le righe di MAPPA: come liste di numeri di tile."""
    testo = valori._espandi(valori.SORGENTE)
    i = next(k for k, l in enumerate(testo) if l.startswith('MAPPA:'))
    fuori = []
    for l in testo[i + 1:]:
        c = l.split(';')[0].rstrip()
        m = re.search(r'\bdc\.w\s+(.+)$', c, re.I)
        if not m:
            if fuori and c.strip():
                break
            continue
        fuori.append([int(v.strip()) for v in m.group(1).split(',')])
        if len(fuori) == tab['MAPPA_ROWS']:
            break
    return fuori


def main():
    tab = valori.leggi()
    pal = palette24(tab)
    tile = foglio_tile()
    mappa = mappa_dal_sorgente(tab)
    cols, rows = tab['MAPPA_COLS'], tab['MAPPA_ROWS']
    print('mappa letta: %d righe x %d colonne' % (len(mappa), len(mappa[0])))
    assert len(mappa) == rows and all(len(r) == cols for r in mappa)

    # quante tile del foglio sono davvero disegnate
    vuote = [i for i, c in enumerate(tile) if all(v == 0 for riga in c for v in riga)]
    usate = sorted({t for r in mappa for t in r})
    print('slot nel foglio: %d   non vuote: %d   usate dalla mappa: %d (max %d)'
          % (len(tile), len(tile) - len(vuote), len(usate), max(usate)))

    fuori = os.path.join(RADICE, 'risorse', 'grafica')
    os.makedirs(fuori, exist_ok=True)

    # 1) la mappa montata con le tile vere
    arte = Image.new('RGB', (cols * TILE, rows * TILE))
    pix = arte.load()
    for ty, riga in enumerate(mappa):
        for tx, n in enumerate(riga):
            c = tile[n]
            for y in range(TILE):
                for x in range(TILE):
                    pix[tx * TILE + x, ty * TILE + y] = pal[c[y][x]]
    arte.save(os.path.join(fuori, 'mappa-arte.png'))

    # 2) la superficie di editing: 1 px = 1 tile, colore = media della tile
    medie = []
    for c in tile:
        n = TILE * TILE
        r = sum(pal[v][0] for riga in c for v in riga) // n
        g = sum(pal[v][1] for riga in c for v in riga) // n
        b = sum(pal[v][2] for riga in c for v in riga) // n
        medie.append((r, g, b))
    mini = Image.new('RGB', (cols, rows))
    mp = mini.load()
    for ty, riga in enumerate(mappa):
        for tx, n in enumerate(riga):
            mp[tx, ty] = medie[n]
    mini.resize((cols * 14, rows * 14), Image.NEAREST).save(
        os.path.join(fuori, 'mappa-indici.png'))

    # 3) la tavola delle tile non vuote, numerata
    from PIL import ImageDraw
    vive = [i for i in range(len(tile)) if i not in vuote]
    per_riga = 16
    righe_t = (len(vive) + per_riga - 1) // per_riga
    cell = TILE * 2
    tav = Image.new('RGB', (per_riga * (cell + 10), righe_t * (cell + 14)), (20, 20, 28))
    dr = ImageDraw.Draw(tav)
    for k, n in enumerate(vive):
        cx = (k % per_riga) * (cell + 10) + 5
        cy = (k // per_riga) * (cell + 14) + 12
        c = tile[n]
        im = Image.new('RGB', (TILE, TILE))
        ip = im.load()
        for y in range(TILE):
            for x in range(TILE):
                ip[x, y] = pal[c[y][x]]
        tav.paste(im.resize((cell, cell), Image.NEAREST), (cx, cy))
        dr.text((cx, cy - 11), str(n), fill=(200, 200, 210))
    tav.save(os.path.join(fuori, 'tavola-tile.png'))

    print('scritti: risorse/grafica/mappa-arte.png, mappa-indici.png, tavola-tile.png')
    return 0


if __name__ == '__main__':
    sys.exit(main())
