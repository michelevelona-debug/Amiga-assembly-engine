#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# simula-strumenti.py - esegue in Python le routine del pannello con
#   l'aritmetica del 68000, sugli stessi byte che legge il codice vero.
#
# USO (dalla cartella Megagame):  python3 tools/simula-strumenti.py
#
# NON e' un modello scritto a parte: le EQU le legge DA Gioco.s e DA Testo.i, e
# ComponiSheet, CopiaCellaPannello, DisegnaLettera, ImpostaScritta e
# DisegnaScritta sono trascritte istruzione per istruzione. Un modello a parte
# dimostra che il modello funziona; solo l'aritmetica vera dimostra che
# funziona il codice.
#
# Cosa controlla, e sono le cose che a occhio non si vedono:
#   1. spie spente (rossa compresa) -> zero byte diversi dal pannello. E'
#      l'invariante che dice se la composizione con lo sfondo e' giusta: una
#      cella "vuota" deve lasciare il buco esattamente com'era.
#   2. la spia rossa accesa non tocca un pixel fuori dalla sua cella, e usa le
#      voci dei grigi (che sotto y47 il copper porta al rosso).
#   3. la lettera: 42 pixel per la A, tutti dentro il buco, tutti della tinta
#      giusta; e lo SPAZIO non cambia un byte.
#   4. la scritta scorrevole tocca solo i due piani in cui la tinta ha il bit a
#      zero, e solo dentro la finestra.
#   5. il giro della scritta si richiude: dopo ScrittaFine px si torna
#      identici, quindi non c'e' cucitura.
#
# Scrive sim2_partenza.png, sim2_acceso.png, z2_destra.png, z2_scritta.png e
# sim2_pannello.gif.
# ============================================================================
import io, re, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valori
from PIL import Image
src = '\n'.join(valori._espandi('Gioco.s'))
EQU={}
def val(e):
    e=e.strip()
    e=re.sub(r'\$([0-9a-fA-F]+)',lambda m:str(int(m.group(1),16)),e)
    e=e.replace('&',' & ').replace('|',' | ').replace('/','//')
    return eval(e,{},dict(EQU))
for _giro in range(3):
    for r in src.split('\n'):
        t=r.split(';')[0]
        m=re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+EQU\s+(.+)$',t)
        if m and m.group(1) not in EQU:
            try: EQU[m.group(1)]=val(m.group(2))
            except Exception: pass
G=lambda n:EQU[n]
for n in ('SPIA_GIALLE','SPIE_TOT','ROSSA_PLANE_SZ','ROSSA_RASTER','ROSSA_X','ROSSA_Y',
          'LETTERA_X','LETTERA_Y','LETTERA_OFS','LETTERA_TINTA',
          'SCRITTA_X','SCRITTA_Y','SCRITTA_BYTE_W','SCRITTA_H','SCRITTA_TINTA',
          'SCRITTA_ROWB','SCRITTA_CODA','SCRITTA_MAX_CAR','SCRITTA_PIANI_N','SCRITTA_RASTER',
          'FONT_H','FONT_GLYPH','FONT_FIRST','FONT_CHARS'):
    print('%-20s %d'%(n,G(n)))

PBR,PPS,PIANI=G('PANNELLO_BYTES_PER_ROW'),G('PANNELLO_PLANE_SIZE'),G('PANNELLO_BITPLANES')
PBP,PBPL=G('PANNELLO_BUF_PITCH'),G('PANNELLO_BUF_PLANE')
pannello=bytearray(open('grafica/Pannello.raw','rb').read())
font=open('grafica/Metal.fnt','rb').read()

def mappa(i1,i2,i3):
    return [(-((i>>k)&1))&0xFFFFFFFF for k in range(4) for i in (i1,i2,i3)]
MG=mappa(G('STRUM_TINTA1'),G('STRUM_TINTA2'),G('STRUM_TINTA3'))
MY=mappa(G('SPIA_TINTA1'),G('SPIA_TINTA2'),G('SPIA_TINTA3'))
MR=mappa(G('ROSSA_TINTA1'),G('ROSSA_TINTA2'),G('ROSSA_TINTA3'))

SpieTab=[[264//8,40,1],[280//8,40,2],[256//8,49,4],[272//8,49,8],[G('ROSSA_X')//8,G('ROSSA_Y'),16]]
STRUM=[
 dict(nome='schermo',file='grafica/schermo.raw',mappa=MG,pos=[[G('SCHERMO_X')//8,G('SCHERMO_Y')]],passo=0,
      cellb=G('SCHERMO_BYTE_W'),cellh=G('SCHERMO_H'),colonne=G('SCHERMO_COLONNE'),righe=G('SCHERMO_RIGHE')),
 dict(nome='spia',file='grafica/spia.raw',mappa=MY,pos=[r[:2] for r in SpieTab[:4]],passo=1,
      cellb=G('SPIA_BYTE_W'),cellh=G('SPIA_H'),colonne=G('SPIA_FASI'),righe=G('SPIA_GIALLE')),
 dict(nome='spia_rossa',file='grafica/spia_rossa.raw',mappa=MR,pos=[SpieTab[4][:2]],passo=0,
      cellb=G('SPIA_BYTE_W'),cellh=G('SPIA_H'),colonne=G('SPIA_FASI'),righe=G('ROSSA_RIGHE')),
 dict(nome='quadrante',file='grafica/quadrante.raw',mappa=MG,pos=[[G('QUAD_X')//8,G('QUAD_Y')]],passo=0,
      cellb=G('QUAD_BYTE_W'),cellh=G('QUAD_H'),colonne=G('QUAD_ANGOLI'),righe=G('QUAD_RIGHE')),
]
def componi(st):
    arte=bytearray(open(st['file'],'rb').read())
    D6=st['colonne']*st['cellb']; D7=(st['cellh']*st['righe'])*D6; D3=st['cellh']*D6
    assert len(arte)==D7*2,(st['nome'],len(arte),D7*2)
    sh=bytearray(D7*PIANI); A1=0;A3=0
    for _ in range(PIANI):
        A5=0
        for _ in range(D7//4):
            D0=int.from_bytes(arte[A5:A5+4],'big'); D1=int.from_bytes(arte[A5+D7:A5+D7+4],'big')
            D2=D0&D1; D0^=D2; D1^=D2
            D0&=st['mappa'][A3+0]; D1&=st['mappa'][A3+1]; D2&=st['mappa'][A3+2]
            D0|=D1|D2
            sh[A1:A1+4]=D0.to_bytes(4,'big'); A1+=4; A5+=4
        A3+=3
    for D5 in range(st['righe']):
        px,py=st['pos'][D5 if st['passo'] else 0]
        A2=py*PBR+px; off=D5*D3; A5=off; A1=off
        for _ in range(PIANI):
            A0=A2
            for _ in range(st['cellh']):
                for _ in range(st['colonne']):
                    A3=A0
                    for _ in range(st['cellb']):
                        v=arte[A5]|arte[A5+D7]; A5+=1
                        sh[A1]|=((~v)&0xFF)&pannello[A3]; A3+=1; A1+=1
                A0+=PBR
            A5-=D3; A1+=D7-D3; A2+=PPS
    return sh
FOGLI={st['nome']:componi(st) for st in STRUM}
print('fogli:',{k:len(v) for k,v in FOGLI.items()})

pulito=bytearray(PBPL*PIANI)
for k in range(PIANI):
    for y in range(80):
        pulito[k*PBPL+y*PBP:k*PBPL+y*PBP+PBR]=pannello[k*PPS+y*PBR:k*PPS+(y+1)*PBR]
buf=bytearray(pulito)

def copia(A0,A1,D0,D1,D2,D3,sheet):
    D5=D2-D0; D6=PBP-D0
    for _ in range(PIANI):
        A2,A3=A0,A1
        for _ in range(D1):
            for _ in range(D0):
                buf[A3]=sheet[A2]; A2+=1; A3+=1
            A2+=D5; A3+=D6
        A0+=D3; A1+=PBPL

def disegna_spia(n,fase):
    if n<4: sheet=FOGLI['spia']; cella=n*G('SPIA_H')*G('SPIA_ROWB'); psz=G('SPIA_PLANE_SZ')
    else:   sheet=FOGLI['spia_rossa']; cella=0; psz=G('ROSSA_PLANE_SZ')
    A0=cella+fase*G('SPIA_BYTE_W')
    A1=SpieTab[n][1]*PBP+SpieTab[n][0]
    copia(A0,A1,G('SPIA_BYTE_W'),G('SPIA_H'),G('SPIA_ROWB'),psz,sheet)
def disegna_schermo(r,c):
    copia(r*G('SCHERMO_H')*G('SCHERMO_ROWB')+c*G('SCHERMO_BYTE_W'),
          G('SCHERMO_Y')*PBP+G('SCHERMO_X')//8,G('SCHERMO_BYTE_W'),G('SCHERMO_H'),
          G('SCHERMO_ROWB'),G('SCHERMO_PLANE_SZ'),FOGLI['schermo'])
def disegna_quad(r,a):
    copia(r*G('QUAD_H')*G('QUAD_ROWB')+a*G('QUAD_BYTE_W'),
          G('QUAD_Y')*PBP+G('QUAD_X')//8,G('QUAD_BYTE_W'),G('QUAD_H'),
          G('QUAD_ROWB'),G('QUAD_PLANE_SZ'),FOGLI['quadrante'])

def disegna_lettera(ch):
    D0=ord(ch)-G('FONT_FIRST')
    if D0<0 or D0>=G('FONT_CHARS'): D0=0
    A0=D0*G('FONT_GLYPH')
    A1=G('LETTERA_Y')*PBR+G('LETTERA_X')//8
    A2=G('LETTERA_Y')*PBP+G('LETTERA_X')//8
    for _ in range(G('FONT_H')):
        D1=(font[A0]<<(8-G('LETTERA_OFS')))&0xFFFF; A0+=1
        D1=((D1<<8)|(D1>>8))&0xFFFF            # ROL.W #8
        A3,A4=A1,A2; D3=G('LETTERA_TINTA')
        for _ in range(PIANI):
            D6=D1; bit=D3&1; D3>>=1
            if not bit: D6=(~D6)&0xFFFF
            op=(lambda a,b:a|b) if bit else (lambda a,b:a&b)
            buf[A4]=op(pannello[A3],D6&0xFF)&0xFF
            D6=((D6<<8)|(D6>>8))&0xFFFF
            buf[A4+1]=op(pannello[A3+1],D6&0xFF)&0xFF
            A3+=PPS; A4+=PBPL
        A1+=PBR; A2+=PBP

SB=bytearray(G('SCRITTA_BUF_SZ')); ST={'car':0,'fine':0,'off':0}
def imposta_scritta(msg):
    n=0
    for ch in msg:
        if n>=G('SCRITTA_MAX_CAR'): break
        c=ord(ch)-G('FONT_FIRST')
        if c<0 or c>=G('FONT_CHARS'): c=0
        for r in range(G('SCRITTA_H')):
            SB[r*G('SCRITTA_ROWB')+n]=(~font[c*G('FONT_GLYPH')+r])&0xFF
        n+=1
    ST['car']=n; ST['fine']=n*8; ST['off']=0
    if n:
        for r in range(G('SCRITTA_H')):
            b=r*G('SCRITTA_ROWB')
            for i in range(G('SCRITTA_CODA')): SB[b+n+i]=SB[b+i%n]
def disegna_scritta():
    if not ST['car']: return
    o=ST['off']+G('SCRITTA_VELOCITA')
    if o>=ST['fine']: o-=ST['fine']
    ST['off']=o
    D2=o&15; A0=(o>>4)*2
    A1=G('SCRITTA_Y')*PBP+G('SCRITTA_X')//8
    for pi in range(SCRITTA_PIANI):
        A2=A0; A3=A1+pi_off[pi]
        for _ in range(G('SCRITTA_H')):
            for _ in range(G('SCRITTA_BYTE_W')//2):
                D1=int.from_bytes(SB[A2:A2+4],'big'); A2+=2
                D1=(D1<<D2)&0xFFFFFFFF
                w=(D1>>16)&0xFFFF
                buf[A3]=(w>>8)&0xFF; buf[A3+1]=w&0xFF; A3+=2
            if G('SCRITTA_BYTE_W')&1:
                D1=int.from_bytes(SB[A2:A2+4],'big')
                D1=(D1<<D2)&0xFFFFFFFF
                buf[A3]=(D1>>24)&0xFF; A3+=1
            A2+=G('SCRITTA_ROWB')-(G('SCRITTA_BYTE_W')//2)*2
            A3+=PBP-G('SCRITTA_BYTE_W')
pi_off=[k*PBPL for k in range(4) if not ((G('SCRITTA_TINTA')>>k)&1)]
SCRITTA_PIANI=len(pi_off)
assert SCRITTA_PIANI==G('SCRITTA_PIANI_N'), (SCRITTA_PIANI, G('SCRITTA_PIANI_N'))
print('piani riscritti dalla scritta:',pi_off)

# --------------------------------------------------------------- palette
v=re.findall(r'\$([0-9a-fA-F]{4})',io.open('Pannello.cop',encoding='latin-1').read())
PAL={}
for i in range(0,len(v)-1,2):
    r=int(v[i],16)
    if 0x180<=r<=0x1be: PAL[(r-0x180)//2]=int(v[i+1],16)
def colore(idx,y):
    c=PAL[idx]
    if y>=G('SPIA_Y0') and idx in (G('SPIA_TINTA1'),G('SPIA_TINTA2'),G('SPIA_TINTA3')):
        c={G('SPIA_TINTA1'):G('SPIA_COL1'),G('SPIA_TINTA2'):G('SPIA_COL2'),G('SPIA_TINTA3'):G('SPIA_COL3')}[idx]
    if y>=G('ROSSA_Y0') and idx in (G('ROSSA_TINTA1'),G('ROSSA_TINTA2'),G('ROSSA_TINTA3')):
        c={G('ROSSA_TINTA1'):G('ROSSA_COL1'),G('ROSSA_TINTA2'):G('ROSSA_COL2'),G('ROSSA_TINTA3'):G('ROSSA_COL3')}[idx]
    if y>=G('SCRITTA_Y0') and idx==G('SCRITTA_TINTA'): c=G('SCRITTA_COL')
    return (((c>>8)&15)*17,((c>>4)&15)*17,(c&15)*17)
def px(b,x,y): return sum(((b[k*PBPL+y*PBP+(x>>3)]>>(7-(x&7)))&1)<<k for k in range(PIANI))
def rendi(path,z=3,box=None):
    x0,x1,y0,y1=box if box else (0,319,0,79)
    w,h=x1-x0+1,y1-y0+1
    im=Image.new('RGB',(w*z,h*z)); p=im.load()
    for y in range(h):
        for x in range(w):
            c=colore(px(buf,x0+x,y0+y),y0+y)
            for j in range(z):
                for i in range(z): p[x*z+i,y*z+j]=c
    im.save(path); return im

# ============================================================ INVARIANTI
def azzera(): buf[:] = pulito
def diversi(): return [i for i in range(len(buf)) if buf[i]!=pulito[i]]

azzera()
for n in range(SPIE_TOT_:=G('SPIE_TOT')): disegna_spia(n,0)
print('\n1. tutte le spie spente (rossa compresa): byte diversi dal pannello =',len(diversi()))

azzera(); disegna_spia(4,G('SPIA_FASI')-1)
fuori=[(x,y) for y in range(80) for x in range(320)
       if px(buf,x,y)!=px(pulito,x,y) and not (G('ROSSA_X')<=x<G('ROSSA_X')+G('SPIA_W')
                                               and G('ROSSA_Y')<=y<G('ROSSA_Y')+G('SPIA_H'))]
tinte={px(buf,x,y) for y in range(80) for x in range(320) if px(buf,x,y)!=px(pulito,x,y)}
print('2. spia rossa accesa: px fuori dalla cella =',len(fuori),' indici usati =',sorted(tinte))

azzera(); disegna_lettera('A')
camb=[(x,y) for y in range(80) for x in range(320) if px(buf,x,y)!=px(pulito,x,y)]
fuori=[c for c in camb if not (282<=c[0]<=294 and 23<=c[1]<=30)]
print('3. lettera A: px cambiati =',len(camb),' fuori dal buco =',len(fuori),
      ' indici =',sorted({px(buf,x,y) for x,y in camb}))
azzera(); disegna_lettera(' ')
print('   lettera spazio: px diversi dal pannello =',len(diversi()))

azzera(); imposta_scritta('THE SACRED ARMOUR OF ANTIRIAD - AMIGA 1200 AGA - ')
print('4. messaggio: %d caratteri, giro di %d px'%(ST['car'],ST['fine']))
for _ in range(40): disegna_scritta()
camb=[(x,y) for y in range(80) for x in range(320) if px(buf,x,y)!=px(pulito,x,y)]
fuori=[c for c in camb if not (G('SCRITTA_X')<=c[0]<G('SCRITTA_X')+G('SCRITTA_BYTE_W')*8
                               and G('SCRITTA_Y')<=c[1]<G('SCRITTA_Y')+G('SCRITTA_H'))]
print('   px cambiati =',len(camb),' fuori dalla finestra =',len(fuori),
      ' indici =',sorted({px(buf,x,y) for x,y in camb}))
byte_camb={i//PBPL for i in diversi()}
print('   piani toccati =',sorted(byte_camb))

# il giro si richiude: dopo ScrittaFine px si torna identici
azzera(); imposta_scritta('ABC')
disegna_scritta(); primo=bytes(buf)
for _ in range(ST['fine']): disegna_scritta()
print('5. giro di %d px su messaggio corto: identico al primo quadro?'%ST['fine'], bytes(buf)==primo)

# ============================================================ ANTEPRIME
azzera()
disegna_schermo(0,0); disegna_quad(0,G('QUAD_POS_OVEST'))
for n in range(5): disegna_spia(n,0)
disegna_lettera('A')
imposta_scritta('THE SACRED ARMOUR OF ANTIRIAD - AMIGA 1200 AGA - ')
for _ in range(1): disegna_scritta()
rendi('sim2_partenza.png')

azzera()
disegna_schermo(0,3); disegna_quad(2,14)
for n in range(5): disegna_spia(n,G('SPIA_FASI')-1)
disegna_lettera('A')
for _ in range(30): disegna_scritta()
rendi('sim2_acceso.png')
rendi('z2_destra.png',6,(210,300,6,70))
rendi('z2_scritta.png',6,(110,216,52,70))

FR=[]
azzera(); imposta_scritta('THE SACRED ARMOUR OF ANTIRIAD - AMIGA 1200 AGA - ')
disegna_quad(0,G('QUAD_POS_OVEST')); disegna_lettera('A')
acc=0
for n in range(120):
    if n in (8,20,32,44,56): acc|=1<<((n-8)//12)
    disegna_schermo(0,(n//2)%8)
    for k in range(5): disegna_spia(k, (G('SPIA_FASI')-1) if (acc>>k)&1 else 0)
    disegna_scritta()
    FR.append(rendi('/tmp/f.png',3))
FR[0].save('sim2_pannello.gif',save_all=True,append_images=FR[1:],duration=60,loop=0)
print('\nanteprime scritte')
