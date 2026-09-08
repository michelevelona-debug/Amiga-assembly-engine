#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-parallasse.py - l'arte della parallasse: una foresta di conifere su
#   tre piani di profondita'.
#
# USO (dalla cartella Megagame):  python3 tools/genera-parallasse.py
#
# GEOMETRIA, presa da Gioco.s e non scelta qui:
#   640x256, 2 piani separati (10240 byte l'uno), 40960 byte in tutto.
#   Di 256 righe se ne vedono 176: dalla PARALLAX_SRC_ROW0 (11) alla 186.
#   Quello che sta fuori non arriva mai a schermo (BuildParallaxStrip copia
#   solo PARALLAX_STRIP_ROWS righe a partire da ROW0), ma si disegna lo stesso:
#   costa zero e se un domani ROW0 cambia non compaiono buchi.
#
# I TRE VALORI SONO PROFONDITA', non ombreggiatura. Le tinte in Gioco.s sono
#   1 = $182838  la piu' scura  -> gli alberi VICINI
#   2 = $2a3a52  mezzatinta     -> quelli di mezzo
#   3 = $46608c  la piu' chiara -> quelli lontani
# Il valore 0 e' TRASPARENTE: ci si vede il cielo.
# I piani si disegnano da dietro in avanti, cosi' il vicino copre il lontano.
#
# TILEABILE a 640: tutto si disegna in modulo 640, quindi un albero che esce a
# destra rientra a sinistra. La parallasse scorre a meta' della velocita' della
# camera e gira in continuo: una cucitura visibile si vedrebbe passare.
#
# LA COPERTURA E' UN VINCOLO DI GIOCO, non di gusto. Questa arte sta in PRIMO
# PIANO, sopra il player: l'arte precedente (alberi secchi) copriva il 32% dei
# pixel visibili. Una parete di conifere piena renderebbe illeggibile il gioco.
# Lo script la MISURA e la stampa: se cresce troppo si diradano le file.
# ============================================================================
import math, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grafica

W, H = 640, 256
ROW0, VIS = 11, 176          # la finestra che finisce a schermo
PIANI = 2

buf = [[0]*W for _ in range(H)]

def punta(x, y, v):
    if 0 <= y < H:
        buf[y][x % W] = v

def disco(cx, cy, r, v):
    ri = int(r) + 1
    for dy in range(-ri, ri+1):
        for dx in range(-ri, ri+1):
            if dx*dx + dy*dy <= r*r:
                punta(cx+dx, cy+dy, v)

def ramo(cx, cy, lato, lung, cala, spess, v, rnd):
    """Un ramo: esce dal tronco, scende un po', e finisce in un ciuffo. Il
    ciuffo e' quello che toglie l'aria da scheletro di pesce."""
    passi = max(2, int(lung))
    for i in range(passi + 1):
        u = i / passi
        x = cx + lato * lung * u
        y = cy + cala * u * u
        t = spess * (1 - 0.55*u)
        for dy in range(int(-t/2), int(t/2) + 1):
            punta(int(round(x)), int(round(y)) + dy, v)
    # ciuffi lungo il ramo e in punta
    for u in (0.55, 0.8, 1.0):
        rr = spess * rnd.uniform(0.55, 0.95) * (1.25 - 0.5*u)
        if rr >= 0.9:
            disco(int(round(cx + lato*lung*u)), int(round(cy + cala*u*u)), rr, v)

def albero(cx, base, altezza, largh, val, rnd, chioma_da):
    """chioma_da = da che frazione dell'altezza comincia la chioma scendendo:
    0.35 e' un abete (rami quasi fino a terra), 0.62 un pino (fusto nudo)."""
    cima = base - altezza
    fine_chioma = cima + altezza * chioma_da
    # tronco: si assottiglia salendo, e sotto la chioma resta nudo
    for y in range(int(cima + altezza*0.06), base + 1):
        u = (y - cima) / altezza
        tw = max(1, int(round(1 + (largh/11) * u)))
        for dx in range(-(tw//2), tw - tw//2):
            punta(cx + dx, y, val)
    # rami: fitti, cosi' vicino al tronco si saldano in una MASSA e restano
    # frastagliati solo sul bordo. Con i rami radi veniva uno scheletro di
    # pesce: e' la densita' che fa la chioma, non il numero di file.
    n = max(6, int(altezza * 0.24))
    pende = rnd.uniform(-0.18, 0.18)           # l'albero pende un po' da un lato
    for i in range(n):
        t = (i + 1) / n
        y = cima + altezza*0.08 + (fine_chioma - cima - altezza*0.08) * (t ** 0.92)
        base_l = largh * (t ** 0.62)
        cala = 1.0 + 4.0 * t
        spess = 1.3 + 2.6 * t
        for lato in (-1, 1):
            if rnd.random() < 0.13 and t < 0.75:
                continue                      # qualche ramo manca: intacca il bordo
            # la lunghezza varia MOLTO: e' quello che frastaglia la sagoma
            lung = base_l * rnd.uniform(0.55, 1.30) * (1 + lato*pende)
            if lung < 1.5: lung = 1.5
            ramo(cx, int(round(y)), lato, lung, cala, spess, val, rnd)
    # cima: un affusolamento, non una pallina. Con il disco veniva un pomello.
    for k in range(int(altezza*0.10)):
        u = k / max(1, int(altezza*0.10))
        w = max(0, int(round(largh*0.16*u)))
        for dx in range(-w, w+1):
            punta(cx+dx, int(cima + altezza*0.045) + k, val)

def fila(gruppi, per_gruppo, val, seme, h, w, base, chioma):
    """Alberi a GRUPPI, non a passo regolare: e' quello che fa sembrare un
    bosco invece di un filare."""
    rnd = random.Random(seme)
    passo = W / gruppi
    for g in range(gruppi):
        gx = g * passo + rnd.uniform(-passo*0.18, passo*0.18)
        for k in range(rnd.randint(*per_gruppo)):
            cx = int(gx + rnd.gauss(0, passo*0.26)) % W
            altezza = rnd.randint(*h)
            largh = rnd.randint(*w)
            b = ROW0 + rnd.randint(*base)
            albero(cx, b, altezza, largh, val, rnd, rnd.uniform(*chioma))

# --- da dietro in avanti: il vicino copre il lontano ---------------------
# LONTANI (tinta 3, la piu' chiara): tanti, bassi, chiome fitte. Riempiono i
# vuoti fra i tronchi dei vicini, che e' dove si devono vedere.
fila(10, (2, 3), 3, 101, h=(78, 124), w=(11, 20), base=(VIS+2, VIS+10), chioma=(0.34, 0.54))
# DI MEZZO (tinta 2)
fila(7, (1, 2), 2, 202, h=(112, 156), w=(17, 29), base=(VIS+4, VIS+14), chioma=(0.42, 0.62))
# VICINI (tinta 1, la piu' scura): pochi, alti, fusto nudo per meta' altezza.
# E' li' che si gioca: sotto la chioma restano solo i tronchi.
fila(4, (1, 2), 1, 303, h=(148, 182), w=(28, 44), base=(VIS+8, VIS+20), chioma=(0.56, 0.72))

# ============================================================ CONTROLLI
# La palette dell'IFF non e' scelta qui: le tre tinte si LEGGONO da Gioco.s,
# cosi' aprendo il file si vedono i colori che avra' davvero a schermo. Il
# colore 0 e' trasparente (ci si vede il cielo) e nell'IFF e' dichiarato tale:
# il celeste serve solo a guardarlo, il chipset non lo usa.
PALETTE = [grafica.rgb24(grafica.equ('CIELO_FISSO_RGB')),
           grafica.rgb24(grafica.equ('SKYLINE_C1_RGB')),
           grafica.rgb24(grafica.equ('SKYLINE_C2_RGB')),
           grafica.rgb24(grafica.equ('SKYLINE_C3_RGB'))]

n, n_iff, p_iff = grafica.salva('grafica/parallasse.raw', buf, W, H, PIANI, PALETTE)
vis = [(x, y) for y in range(ROW0, ROW0+VIS) for x in range(W)]
acc = sum(1 for x, y in vis if buf[y][x])
print('parallasse.raw  %d byte  %dx%d a %d piani' % (n, W, H, PIANI))
print('%-15s %d byte' % (os.path.basename(p_iff), n_iff))
print('copertura nelle 176 righe visibili: %d px su %d = %.1f%%'
      % (acc, len(vis), 100*acc/len(vis)))
for v in (1, 2, 3):
    print('   valore %d: %6d px' % (v, sum(1 for x, y in vis if buf[y][x] == v)))
# cucitura: la colonna 639 e la 0 devono stare su alberi diversi, non essere
# uguali; quello che conta e' che non ci sia un salto, cioe' che gli alberi a
# cavallo del bordo siano continui. Si controlla ricucendo e cercando colonne
# vuote isolate al bordo.
sx = sum(1 for y in range(ROW0, ROW0+VIS) if buf[y][0])
dx = sum(1 for y in range(ROW0, ROW0+VIS) if buf[y][W-1])
print('colonna 0: %d px accesi   colonna 639: %d px accesi' % (sx, dx))
righe_vuote = [y for y in range(ROW0, ROW0+VIS)
               if not any(buf[y][x] for x in range(W))]
print('righe visibili completamente vuote: %d' % len(righe_vuote))
