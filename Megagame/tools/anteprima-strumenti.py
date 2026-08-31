#!/usr/bin/env python3
# Anteprime dei tre strumenti montati nel pannello vero. Non scrive niente in
# grafica/: serve solo a guardare. La palette e' quella di Pannello.cop, piu'
# la banda gialla che il copper mettera' sotto agli indicatori per le spie.
import re, math
from PIL import Image

W, H, PIANI = 320, 80, 4
ROWB, PSZ = W//8, (W//8)*H

def dec(d, w, h, p):
    rb, ps = w//8, (w//8)*h
    return [[sum(((d[k*ps + y*rb + (x>>3)] >> (7-(x&7))) & 1) << k
                 for k in range(p)) for x in range(w)] for y in range(h)]

PAN = dec(open('grafica/Pannello.raw','rb').read(), 320, 80, 4)
val = re.findall(r'\$([0-9a-fA-F]{4})', open('Pannello.cop', encoding='latin-1').read())
PAL = {}
for i in range(0, len(val)-1, 2):
    r = int(val[i], 16)
    if 0x180 <= r <= 0x1be: PAL[(r-0x180)//2] = int(val[i+1], 16)
GIALLO = {2: 0x631, 13: 0xea2, 14: 0xfe6}      # banda copper da y40 in giu'
def col(idx, y):
    v = GIALLO[idx] if (y >= 40 and idx in GIALLO) else PAL[idx]
    return (((v>>8)&15)*17, ((v>>4)&15)*17, (v&15)*17)

SCH = dec(open('grafica/schermo.raw','rb').read(), 320, 32, 2)
SPI = dec(open('grafica/spia.raw','rb').read(), 64, 8, 2)
QUA = dec(open('grafica/quadrante.raw','rb').read(), 640, 148, 2)

SCH_W, SCH_H, SCH_X, SCH_Y = 40, 16, 144, 26
SPIA_D = 8
SPIE = [(266,40), (284,40), (257,49), (275,49)]
QUA_W, QUA_H, QUA_X, QUA_Y = 40, 37, 216, 10

MAP_GRIGI  = {1:4, 2:5, 3:6}
MAP_GIALLI = {1:2, 2:13, 3:14}

def quadro(sch_f, spie_f, qua_i, qua_r):
    im = [[PAN[y][x] for x in range(W)] for y in range(H)]
    for y in range(SCH_H):
        for x in range(SCH_W):
            v = SCH[y][sch_f*SCH_W + x]
            if v: im[SCH_Y+y][SCH_X+x] = MAP_GRIGI[v]
    for y in range(QUA_H):
        for x in range(QUA_W):
            v = QUA[qua_r*QUA_H + y][qua_i*QUA_W + x]
            if v: im[QUA_Y+y][QUA_X+x] = MAP_GRIGI[v]
    for n, (sx, sy) in enumerate(SPIE):
        f = spie_f[n]
        for y in range(SPIA_D):
            for x in range(SPIA_D):
                v = SPI[y][f*SPIA_D + x]
                if v: im[sy+y][sx+x] = MAP_GIALLI[v]
    return im

def png(im, z, path, x0=0, x1=W-1, y0=0, y1=H-1):
    w, h = x1-x0+1, y1-y0+1
    g = Image.new('RGB', (w*z, h*z)); p = g.load()
    for y in range(h):
        for x in range(w):
            c = col(im[y0+y][x0+x], y0+y)
            for j in range(z):
                for i in range(z): p[x*z+i, y*z+j] = c
    g.save(path); return g

# --- tavola del quadrante: i 16 angoli, pulito e con lo sbuffo -------------
tav = Image.new('RGB', (16*QUA_W*3, 2*QUA_H*3), (0,0,0))
for r_i, r in enumerate((0, 2)):
    for i in range(16):
        cel = Image.new('RGB', (QUA_W*3, QUA_H*3))
        pp = cel.load()
        for y in range(QUA_H):
            for x in range(QUA_W):
                v = QUA[r*QUA_H + y][i*QUA_W + x]
                c = col(MAP_GRIGI[v], 0) if v else col(PAN[QUA_Y+y][QUA_X+x], QUA_Y+y)
                for jj in range(3):
                    for ii in range(3): pp[x*3+ii, y*3+jj] = c
        tav.paste(cel, (i*QUA_W*3, r_i*QUA_H*3))
tav.save('quadrante_tavola.png')

png(quadro(0, [7,7,7,7], 12, 0), 3, 'pannello_nuovi_fermo.png')
png(quadro(0, [7,7,7,7], 12, 0), 6, 'z_quadrante_fermo.png', 205, 300, 6, 62)

# --- gif: neve che scorre, lancetta W->N con sbuffo, spie che si accendono --
FR = []
seq_ang = [12]*6 + [13,13,13, 14,14,14, 15,15,15, 0,0,0] + [0]*10
seq_row = [0]*6  + [1,2,3, 1,2,3, 2,3,3, 3,3,2]           + [0]*10
acc = [[0,0,0,0]]
for n in range(len(seq_ang)-1):
    s = list(acc[-1])
    if n >= 4:
        k = min(3, (n-4)//4)
        s[k] = min(7, s[k] + 2)
    acc.append(s)
for n in range(len(seq_ang)):
    FR.append(png(quadro(n % 8, acc[n], seq_ang[n], seq_row[n]), 3, '/tmp/f.png'))
FR[0].save('pannello_nuovi.gif', save_all=True, append_images=FR[1:], duration=90, loop=0)
print('scritte: quadrante_tavola.png, pannello_nuovi_fermo.png, z_quadrante_fermo.png, pannello_nuovi.gif')
