#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-fette-parallasse.py - taglia grafica/parallasse.raw in FETTE da 64 px
#   gia' impaginate come DATI SPRITE a 64 bit, pronte da incbinnare.
#
# USO (dalla cartella Megagame):  python3 tools/genera-fette-parallasse.py
#
# PERCHE' ESISTE
# La parallasse smette di essere due bitplane disegnati dal blitter e diventa
# sei sprite larghi 64 px che si spostano. L'arte non si ridisegna: uno sprite
# Amiga ha 2 bit per pixel (0 trasparente, 1/2/3 tre colori) e la parallasse ha
# 2 bitplane e tre tinte di profondita'. E' la stessa struttura vista da due
# parti, quindi questo script e' una RI-IMPAGINAZIONE, non una conversione.
#
# IL FORMATO, che e' l'unica parte delicata
# Con FMODE a 64 bit ogni accesso DMA sprite preleva 64 bit, e SPRPOS e SPRCTL
# sono la PRIMA word di DUE accessi distinti. Quindi:
#   byte  0..1   SPRPOS          \
#   byte  2..7   riempimento      | blocco di controllo: 16 byte, non 8
#   byte  8..9   SPRCTL           |
#   byte 10..15  riempimento     /
#   byte 16..    una riga: 8 byte di piano A (DATA, bit 0 del colore)
#                          8 byte di piano B (DATB, bit 1)
#   in coda      16 byte a zero: fine dello sprite
# Il 5 settembre un blocco di controllo da 8 byte ha ucciso tre canali su
# cinque, e il conto tornava solo cosi'. Vedi claude/convenzioni.md.
#
# Una fetta di 64 px riempie ESATTAMENTE un prelievo a 64 bit: nessun byte
# sprecato, e la larghezza della fetta non e' una scelta ma una conseguenza.
#
# QUELLO CHE NON DECIDE QUESTO SCRIPT
# Geometria e righe si LEGGONO da Gioco.s (CUT_BOTTOM_ROWS, PARALLAX_SRC_ROW0,
# DIW_H_START) e i tre colori pure (SKYLINE_C*_RGB). Il numero di fette esce
# dalla larghezza dell'arte diviso 64. In Gioco.s una guardia confronta la
# lunghezza del file incbinnato con FETTA_SZ*FETTE_N: se questo script e il
# sorgente divergono, l'assemblaggio si ferma invece di mostrare spazzatura.
# ============================================================================
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grafica

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORG = os.path.join(RADICE, 'grafica', 'parallasse.raw')
DEST = os.path.join(RADICE, 'grafica', 'fette_parallasse.raw')

SRC_W, SRC_H, PIANI = 640, 256, 2
FETTA_W = 64                                    # = un prelievo sprite a 64 bit
CTRL_B, RIGA_B, FINE_B = 16, 16, 16

# --- i numeri che vengono da Gioco.s, non da qui -------------------------
ROW0 = grafica.equ('PARALLAX_SRC_ROW0')
VIS = 256 - grafica.equ('CUT_BOTTOM_ROWS')      # = BG_VIS_ROWS
DIW_H_START = grafica.equ('DIW_H_START')
VSTART = 0x2C                                   # prima riga della finestra
VSTOP = VSTART + VIS                            # = PANNELLO_TOP_RASTER

FETTE_N = SRC_W // FETTA_W
FETTA_SZ = CTRL_B + VIS*RIGA_B + FINE_B


def leggi_sorgente():
    d = open(SORG, 'rb').read()
    psz = (SRC_W // 8) * SRC_H
    if len(d) != psz * PIANI:
        sys.exit('parallasse.raw: %d byte, attesi %d' % (len(d), psz*PIANI))
    return d, psz


def valore(d, psz, x, y):
    """Il valore 0..3 del pixel (x,y) dell'arte sorgente."""
    rowb = SRC_W // 8
    i = y*rowb + (x >> 3)
    m = 1 << (7 - (x & 7))
    v = 1 if d[i] & m else 0
    if d[psz + i] & m:
        v |= 2
    return v


def costruisci():
    d, psz = leggi_sorgente()
    out = bytearray()
    coperti = 0
    for k in range(FETTE_N):
        x0 = k * FETTA_W
        # --- blocco di controllo, 16 byte ---
        sprpos = ((VSTART & 0xFF) << 8) | ((DIW_H_START >> 1) & 0xFF)
        sprctl = (((VSTOP & 0xFF) << 8)
                  | (((VSTART >> 8) & 1) << 2)
                  | (((VSTOP >> 8) & 1) << 1)
                  | (DIW_H_START & 1))
        out += sprpos.to_bytes(2, 'big') + b'\0'*6
        out += sprctl.to_bytes(2, 'big') + b'\0'*6
        # --- le righe ---
        for r in range(VIS):
            y = ROW0 + r
            a = bytearray(8)                    # piano A: bit 0 del colore
            b = bytearray(8)                    # piano B: bit 1
            for i in range(FETTA_W):
                v = valore(d, psz, x0 + i, y)
                if not v:
                    continue
                coperti += 1
                bit = 1 << (7 - (i & 7))
                if v & 1: a[i >> 3] |= bit
                if v & 2: b[i >> 3] |= bit
            out += bytes(a) + bytes(b)
        # --- terminatore ---
        out += b'\0' * FINE_B
    return bytes(out), coperti


def decodifica(dati):
    """Dalle fette alla bitmap planare 640 x VIS a 2 piani, per l'anteprima.
    E' l'inverso esatto di costruisci(): l'.iff nasce da qui, quindi se
    l'impaginazione sbaglia si vede nell'anteprima invece di restare nascosta
    fino a WinUAE."""
    rowb = SRC_W // 8
    psz = rowb * VIS
    p = bytearray(psz * PIANI)
    for k in range(FETTE_N):
        base = k*FETTA_SZ + CTRL_B
        for r in range(VIS):
            o = base + r*RIGA_B
            for j in range(8):                  # 8 byte = 64 px della fetta
                dst = r*rowb + k*(FETTA_W//8) + j
                p[dst] = dati[o + j]
                p[psz + dst] = dati[o + 8 + j]
    return bytes(p)


def main():
    dati, coperti = costruisci()
    atteso = FETTA_SZ * FETTE_N
    if len(dati) != atteso:
        sys.exit('taglia sbagliata: %d invece di %d' % (len(dati), atteso))

    # I colori si LEGGONO da Gioco.s: aprire l'IFF e vedere tinte che il gioco
    # non ha vorrebbe dire ritoccare l'arte guardando una bugia. Anche il
    # colore 0: nello sprite e' trasparente e ci si vede il cielo, quindi la
    # voce 0 dell'anteprima e' CIELO_FISSO_RGB, non un azzurro deciso qui.
    palette = [grafica.rgb24(grafica.equ('CIELO_FISSO_RGB')),
               grafica.rgb24(grafica.equ('SKYLINE_C1_RGB')),
               grafica.rgb24(grafica.equ('SKYLINE_C2_RGB')),
               grafica.rgb24(grafica.equ('SKYLINE_C3_RGB'))]
    n, n_iff, p_iff = grafica.salva_sprite(DEST, dati, decodifica,
                                           SRC_W, VIS, PIANI, palette)

    print('fette_parallasse.raw  %d byte' % n)
    print('  %d fette da %d px, %d byte l\'una' % (FETTE_N, FETTA_W, FETTA_SZ))
    print('  righe %d..%d dell\'arte (%d righe), VSTART %d VSTOP %d'
          % (ROW0, ROW0+VIS-1, VIS, VSTART, VSTOP))
    print('  anteprima: %s (%d byte)' % (os.path.relpath(p_iff, RADICE), n_iff))
    print('  copertura: %.1f%% dei pixel visibili'
          % (100.0*coperti/(SRC_W*VIS)))
    print()
    print('  Le EQU che Gioco.s deve avere, e la guardia le confronta:')
    print('    FETTE_N        = %d' % FETTE_N)
    print('    FETTA_SZ       = %d' % FETTA_SZ)
    print('    lunghezza file = %d' % atteso)

    # --- CONTROLLO: il giro completo deve tornare pixel per pixel ---------
    d, psz = leggi_sorgente()
    ricost = decodifica(open(DEST, 'rb').read())
    rowb = SRC_W // 8
    diversi = 0
    for r in range(VIS):
        for j in range(rowb):
            a0 = d[(ROW0+r)*rowb + j]
            b0 = d[psz + (ROW0+r)*rowb + j]
            if ricost[r*rowb + j] != a0: diversi += 1
            if ricost[rowb*VIS + r*rowb + j] != b0: diversi += 1
    print()
    print('  CONTROLLO andata e ritorno: %s (%d byte diversi su %d)'
          % ('IDENTICO' if diversi == 0 else 'DIVERSO', diversi, rowb*VIS*2))
    return 0 if diversi == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
