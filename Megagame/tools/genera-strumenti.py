#!/usr/bin/env python3
# ============================================================================
# genera-strumenti.py - genera l'arte dei tre strumenti del pannello:
#   grafica/schermo.raw     schermo centrale (neve + 5 immagini)
#   grafica/spia.raw        spia rotonda che si accende sfarfallando
#   grafica/quadrante.raw   quadrante grande con lancetta e sbuffo di vapore
#
# CONVENZIONE DELL'ARTE (uguale per tutti e tre)
#   2 piani, valori 0..3.  Il valore 0 e' TRASPARENTE: al montaggio si tiene
#   il pixel del pannello. Gli altri tre valori sono le tre tinte.
#   Il montaggio (che avvia il gioco) sovrappone l'arte allo sfondo del
#   pannello letto da grafica/Pannello.raw: cosi' il riquadro di ogni cella
#   puo' essere piu' grande del buco nero senza rovinare l'arte intorno, e
#   l'allineamento al byte smette di essere un vincolo sul disegno.
#
# I pixel accesi sono comunque tagliati sulla maschera del buco nero, letta
# qui da Pannello.raw: nessuna tinta finisce mai sopra la carrozzeria.
# ============================================================================
import os, random
from PIL import Image

W, H, PIANI_PAN = 320, 80, 4
ROWB_PAN, PSZ_PAN = W // 8, (W // 8) * H
NERO = 15

def leggi_pannello():
    d = open('grafica/Pannello.raw', 'rb').read()
    assert len(d) == PSZ_PAN * PIANI_PAN, len(d)
    return [[sum(((d[k*PSZ_PAN + y*ROWB_PAN + (x>>3)] >> (7-(x&7))) & 1) << k
                 for k in range(PIANI_PAN)) for x in range(W)] for y in range(H)]

PAN = leggi_pannello()
def nero(x, y):
    return 0 <= x < W and 0 <= y < H and PAN[y][x] == NERO

def salva_raw(celle, cw, ch, cols, rows, path):
    """celle[r][c] = matrice ch x cw di valori 0..3 -> raw a 2 piani."""
    sw, sh = cw*cols, ch*rows
    rowb = sw // 8
    assert sw % 8 == 0
    psz = rowb * sh
    d = bytearray(psz * 2)
    for r in range(rows):
        for c in range(cols):
            m = celle[r][c]
            for y in range(ch):
                for x in range(cw):
                    v = m[y][x]
                    if not v: continue
                    X, Y = c*cw + x, r*ch + y
                    for k in range(2):
                        if (v >> k) & 1:
                            d[k*psz + Y*rowb + (X>>3)] |= 1 << (7-(X&7))
    open(path, 'wb').write(bytes(d))
    return len(d), sw, sh, rowb, psz

def vuota(cw, ch): return [[0]*cw for _ in range(ch)]

# ============================================================================
# 1. SCHERMO CENTRALE - buco x141..184 y23..44 (44x22), tutto nero.
#    Cella 40x16 (come chiesto), montata a x144..183 y26..41: dentro il nero
#    con margine, e x144 e' multiplo di 8.
# ============================================================================
SCH_W, SCH_H = 40, 16
SCH_X, SCH_Y = 144, 26
SCH_NEVE, SCH_IMG = 8, 5
SCH_COLS, SCH_ROWS = 8, 2

def cifra_grande(n):
    F = {
     '1': ["..XX..","XXXX..","..XX..","..XX..","..XX..","..XX..","XXXXXX"],
     '2': ["XXXXX.","....XX","....XX",".XXXX.","XX....","XX....","XXXXXX"],
     '3': ["XXXXX.","....XX","....XX",".XXXX.","....XX","....XX","XXXXX."],
     '4': ["XX..XX","XX..XX","XX..XX","XXXXXX","....XX","....XX","....XX"],
     '5': ["XXXXXX","XX....","XX....","XXXXX.","....XX","....XX","XXXXX."],
    }
    return F[n]

def cella_neve(f):
    rnd = random.Random(1000 + f)
    m = vuota(SCH_W, SCH_H)
    banda = (f * 3) % SCH_H            # la banda chiara scorre verso il basso
    for y in range(SCH_H):
        vicino = min((y - banda) % SCH_H, (banda - y) % SCH_H)
        boost = 2 if vicino == 0 else (1 if vicino == 1 else 0)
        for x in range(SCH_W):
            r = rnd.random()
            if   r < 0.42 - 0.10*boost: v = 0
            elif r < 0.68 - 0.06*boost: v = 1
            elif r < 0.88 - 0.04*boost: v = 2
            else:                       v = 3
            m[y][x] = v
    return m

def cella_immagine(n):
    m = vuota(SCH_W, SCH_H)
    for x in range(SCH_W):
        m[0][x] = m[SCH_H-1][x] = 1
    for y in range(SCH_H):
        m[y][0] = m[y][SCH_W-1] = 1
    g = cifra_grande(str(n))
    ox, oy = (SCH_W - 6*3)//2, (SCH_H - 7*1)//2
    for y, riga in enumerate(g):
        for x, ch in enumerate(riga):
            if ch == 'X':
                for i in range(3):
                    m[oy+y][ox+x*3+i] = 3
    for i in range(3):                  # tacche laterali
        m[SCH_H//2-1+i][2] = m[SCH_H//2-1+i][SCH_W-3] = 2
    return m

sch = [[vuota(SCH_W, SCH_H) for _ in range(SCH_COLS)] for _ in range(SCH_ROWS)]
for f in range(SCH_NEVE):  sch[0][f] = cella_neve(f)
for i in range(SCH_IMG):   sch[1][i] = cella_immagine(i+1)
n, sw, sh, rowb, psz = salva_raw(sch, SCH_W, SCH_H, SCH_COLS, SCH_ROWS, 'grafica/schermo.raw')
print('schermo.raw    %5d byte  %dx%d  rowb %d  piano %d  cella %dx%d  a x%d y%d'
      % (n, sw, sh, rowb, psz, SCH_W, SCH_H, SCH_X, SCH_Y))

# ============================================================================
# 2. SPIE - quattro buchi rotondi in basso a destra. Nessuno contiene un
#    quadrato 8x8 allineato al byte (il massimo e' 4 righe): la cella e'
#    larga 2 byte e il montaggio ci mette dentro lo sfondo del pannello.
#    L'arte qui e' solo il disco da 8, con 0 = trasparente.
# ============================================================================
SPIA_D      = 8                  # diametro del disco
SPIA_CELL_W = 16                 # 2 byte: il disco non e' allineato al byte
SPIA_H      = 8
SPIA_FASI   = 8                  # colonne: l'accensione che sfarfalla
LIV = [0, 2, 0, 3, 1, 3, 2, 3]   # spenta, guizzi, poi accesa

# Quattro spie = quattro RIGHE della striscia. Non e' ridondanza: ognuna ha il
# disco a uno scostamento diverso dentro la cella da 2 byte, perche' nessuno dei
# quattro buchi ha il centro su un multiplo di 8. Lo scostamento lo fa QUI lo
# script, cosi' il montaggio al boot non deve spostare bit.
#          cella x, cella y, scostamento del disco dentro la cella
SPIE = [ (264, 40, 2), (280, 40, 4), (256, 49, 1), (272, 49, 3) ]

def disco(liv):
    m = vuota(SPIA_D, SPIA_D)
    if liv == 0: return m
    cx = cy = 3.5
    for y in range(SPIA_D):
        for x in range(SPIA_D):
            d = ((x-cx)**2 + (y-cy)**2) ** 0.5
            if d > 3.7: continue
            if liv == 1:   v = 1
            elif liv == 2: v = 2 if d > 1.6 else 3
            else:          v = 3 if d < 2.4 else 2
            m[y][x] = v
    return m

def cella_spia(liv, off):
    m = vuota(SPIA_CELL_W, SPIA_H)
    d = disco(liv)
    for y in range(SPIA_H):
        for x in range(SPIA_D):
            m[y][off + x] = d[y][x]
    return m

spia = [[cella_spia(LIV[f], SPIE[r][2]) for f in range(SPIA_FASI)]
        for r in range(len(SPIE))]
n, sw, sh, rowb, psz = salva_raw(spia, SPIA_CELL_W, SPIA_H, SPIA_FASI, len(SPIE),
                                 'grafica/spia.raw')
print('spia.raw       %5d byte  %dx%d  rowb %d  piano %d  cella %dx%d'
      % (n, sw, sh, rowb, psz, SPIA_CELL_W, SPIA_H))

# controllo: nessun pixel acceso fuori dal nero del buco, e la cella intera
# dentro il pannello
pieno = disco(3)
for r, (bx, by, off) in enumerate(SPIE):
    dx = bx + off
    bad = [(dx+x, by+y) for y in range(SPIA_D) for x in range(SPIA_D)
           if pieno[y][x] and not nero(dx+x, by+y)]
    print('   spia %d  cella x%d..%d y%d..%d  disco a x%d  accesi fuori dal nero: %d'
          % (r, bx, bx+SPIA_CELL_W-1, by, by+SPIA_H-1, dx, len(bad)))

# ----------------------------------------------------------------------------
# La QUINTA spia, quella rossa, sta nel cerchio sotto la lancetta. Stessa arte
# delle altre - gli stessi dischi, le stesse fasi - ma in un file suo, e il
# motivo non e' la grafica: e' la PALETTE. Sta sulle stesse righe raster delle
# due spie gialle in basso (y49..56), quindi non puo' usare le loro tre voci, e
# il foglio si monta con una mappa diversa (i grigi 4/5/6, che sotto y47 il
# copper porta al rosso). Mappa diversa = descrittore diverso = arte a parte.
#
# Qui lo scostamento e' 0: il disco cade a x224..231, che e' allineato al byte
# ed e' tutto nero. La cella resta larga 2 byte come le altre, e il montaggio
# ci rimette lo sfondo del pannello nella meta' destra.
ROSSA = (224, 49, 0)

rossa = [[cella_spia(LIV[f], ROSSA[2]) for f in range(SPIA_FASI)]]
n, sw, sh, rowb, psz = salva_raw(rossa, SPIA_CELL_W, SPIA_H, SPIA_FASI, 1,
                                 'grafica/spia_rossa.raw')
print('spia_rossa.raw %5d byte  %dx%d  rowb %d  piano %d  cella %dx%d'
      % (n, sw, sh, rowb, psz, SPIA_CELL_W, SPIA_H))
bx, by, off = ROSSA
dx = bx + off
bad = [(dx+x, by+y) for y in range(SPIA_D) for x in range(SPIA_D)
       if pieno[y][x] and not nero(dx+x, by+y)]
print('   spia rossa  cella x%d..%d y%d..%d  disco a x%d  accesi fuori dal nero: %d'
      % (bx, bx+SPIA_CELL_W-1, by, by+SPIA_H-1, dx, len(bad)))

# ============================================================================
# 3. QUADRANTE - buco x215..256 y10..46 (42x37). Il rettangolo tutto nero e
#    allineato al byte piu' grande e' 24x28: dentro un buco da 42 la lancetta
#    resterebbe un moncone. La cella e' quindi 40x37 a x216..255 y10..46, cioe'
#    il buco intero, e il montaggio ci rimette sotto lo sfondo del pannello.
#    Sedici angoli da 22.5 gradi. Quattro righe: 0 = lancetta pulita,
#    1..3 = le tre fasi dello sbuffo di vapore.
# ============================================================================
import math
QUA_X, QUA_Y = 216, 10
QUA_W, QUA_H = 40, 37
QUA_ANG  = 16
QUA_RIGHE = 4
CX, CY = 235.5 - QUA_X, 28.0 - QUA_Y      # 19.5, 18.0

# indice bussola: 0=N e si gira in senso orario -> angolo matematico
def dirz(i):
    a = math.radians(90 - i * 22.5)
    return math.cos(a), -math.sin(a)      # y cresce verso il basso

def q_nero(lx, ly):
    return nero(QUA_X + lx, QUA_Y + ly)

# raggio massimo utile: il pixel piu' lontano che resta nel nero, per ogni angolo
rmax = []
for i in range(QUA_ANG):
    dx, dy = dirz(i)
    r = 0.0
    while r < 30:
        x, y = int(round(CX + dx*(r+1))), int(round(CY + dy*(r+1)))
        if not q_nero(x, y): break
        r += 1
    rmax.append(r)
print()
print('quadrante: raggio nero per angolo:', [int(v) for v in rmax], ' minimo', int(min(rmax)))
R_LANC = int(min(rmax)) - 2
R_CONTRO = 5
R_TACCA_E, R_TACCA_I = int(min(rmax)) - 0, int(min(rmax)) - 3
print('quadrante: lancetta r=%d, tacche r=%d..%d' % (R_LANC, R_TACCA_I, R_TACCA_E))

def punta(m, x, y, v):
    xi, yi = int(round(x)), int(round(y))
    if 0 <= xi < QUA_W and 0 <= yi < QUA_H and q_nero(xi, yi):
        if v > m[yi][xi]: m[yi][xi] = v

def segmento(m, r0, r1, dx, dy, largo, v):
    passi = int((r1 - r0) * 4) + 1
    for s in range(passi + 1):
        r = r0 + (r1 - r0) * s / passi
        px, py = CX + dx*r, CY + dy*r
        nx, ny = -dy, dx
        w = largo(r) if callable(largo) else largo
        k = int(w * 2)
        for t in range(-k, k + 1):
            punta(m, px + nx*t*0.5, py + ny*t*0.5, v)

TACCHE = [12, 0, 4, 7]                     # ovest, nord, est, sud-sud-est

def cella_quadrante(i, fase):
    m = vuota(QUA_W, QUA_H)
    # tacche fisse alle quattro posizioni (stanno in ogni cella: costano zero)
    for t in TACCHE:
        dx, dy = dirz(t)
        segmento(m, R_TACCA_I, R_TACCA_E, dx, dy, 0.5, 1)
    dx, dy = dirz(i)
    # contrappeso
    segmento(m, 1, R_CONTRO, -dx, -dy, 1.0, 1)
    # corpo: si assottiglia verso la punta
    segmento(m, 1, R_LANC*0.62, dx, dy, lambda r: 1.4 - r/R_LANC*0.6, 2)
    segmento(m, R_LANC*0.55, R_LANC, dx, dy, lambda r: 1.0 - r/R_LANC*0.5, 3)
    # perno
    for y in range(QUA_H):
        for x in range(QUA_W):
            d = ((x-CX)**2 + (y-CY)**2) ** 0.5
            if d <= 1.2: punta(m, x, y, 3)
            elif d <= 2.2: punta(m, x, y, 2)
    if fase:
        rnd = random.Random(7000 + i*10 + fase)
        # sbuffo: esce dal perno e sale. Mai il valore 1: sul nero sparisce e
        # sembrerebbe sporco. Fase 1 piccolo e vivo, 2 aperto, 3 alto e rado.
        conf = {1: (4, 4.0, 1.3, 3, 1.0),
                2: (6, 8.0, 2.0, 2, 0.85),
                3: (6, 12.0, 2.4, 2, 0.45)}[fase]
        nb, dist0, rag0, v, dens = conf
        for b in range(nb):
            ang = math.radians(-90 + rnd.uniform(-38, 38))
            dist = dist0 + rnd.uniform(-1.8, 1.8) + b*0.6
            raggio = rag0 + rnd.uniform(-0.3, 0.5)
            bx, by = CX + math.cos(ang)*dist, CY + math.sin(ang)*dist
            for y in range(QUA_H):
                for x in range(QUA_W):
                    dd = (x-bx)**2 + (y-by)**2
                    if dd > raggio*raggio: continue
                    if (x-CX)**2 + (y-CY)**2 < 9: continue   # non sul perno
                    if dens < 1.0 and rnd.random() > dens: continue
                    punta(m, x, y, v)
            if fase == 2:
                punta(m, bx, by - raggio*0.6, 3)
    return m

qua = [[cella_quadrante(i, r) for i in range(QUA_ANG)] for r in range(QUA_RIGHE)]
n, sw, sh, rowb, psz = salva_raw(qua, QUA_W, QUA_H, QUA_ANG, QUA_RIGHE, 'grafica/quadrante.raw')
print('quadrante.raw  %5d byte  %dx%d  rowb %d  piano %d  cella %dx%d  a x%d y%d'
      % (n, sw, sh, rowb, psz, QUA_W, QUA_H, QUA_X, QUA_Y))
fuori = 0
for r in range(QUA_RIGHE):
    for i in range(QUA_ANG):
        for y in range(QUA_H):
            for x in range(QUA_W):
                if qua[r][i][y][x] and not q_nero(x, y): fuori += 1
print('   pixel accesi fuori dal nero del buco: %d' % fuori)
