#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-alba.py - la prima videata dell'intro: il sole che sorge sul lembo
#   della Terra, visto dall'orbita. L'immagine NON si muove mai: si muove solo
#   la palette.
#
# USO (dalla cartella Megagame):
#     python3 tools/genera-alba.py             scrive l'arte
#     python3 tools/genera-alba.py --misure    stampa i numeri e non scrive
#
# COSA SCRIVE
#   grafica/alba.raw          320x256, 8 piani contigui. In CHIP: la legge il
#                             display. E' l'immagine di ARRIVO, cioe' il giorno
#                             pieno; l'alba e' la palette che ci arriva.
#   grafica/alba_rampe.raw    per ogni voce, ALBA_LIVELLI colori GIA' impacchettati
#                             in due word copper (nibble alti, nibble bassi).
#                             In FAST: la legge solo la CPU.
#   grafica/alba_inizio.raw   per ogni voce, il quadro in cui comincia la sua rampa.
#   risorse/grafica/alba.iff        l'immagine da aprire in un editor
#   risorse/grafica/alba-rampe.png  l'anteprima delle rampe: una riga per voce,
#                             una colonna per livello. E' la partitura
#                             dell'effetto, e ci si vede a colpo d'occhio chi
#                             parte quando.
#
# PERCHE' UNA TABELLA E NON UNA FORMULA A RUNTIME
# Il primo piano era: poche palette chiave, interpolazione lineare sull'Amiga.
# MISURATO e scartato: con ogni strato su una tempistica sua e una rampa non
# lineare, l'interpolazione lineare fra 17 chiavi sbaglia ancora di 25 L* nel
# punto peggiore. Il colore di una voce pero' dipende SOLO dalla sua fase,
# quindi si precalcola una rampa per voce e a runtime restano due MOVE.W.
# Tutta l'intelligenza sta qui; il 68000 fa il playback.
#
# LE TRE REGOLE CHE HANNO DECISO LA FORMA DELL'EFFETTO, tutte imparate
# sbagliando:
#
# 1. LA RAMPA VA SCALATA SULLA SINGOLA VOCE. Con una rampa assoluta uguale per
#    tutti, una voce di aureola - il cui colore finale e' gia' scuro - partiva
#    da un rosso PIU' ACCESO del suo punto d'arrivo, e al quadro zero tutto
#    l'alone si vedeva rosso.
#
# 2. LA FASE SEGUE LA LUMINOSITA', NON LA POSIZIONE. Col ritardo proporzionale
#    alla distanza dal punto caldo i bordi sfrigolavano: il DITHERING mescola
#    voci vicine di COLORE, quindi due voci che si mescolano ma stanno a
#    distanze diverse sono a fasi diverse e la mescolanza sfarfalla. Presa la
#    fase dalla luminosita', chi si mescola e' anche vicino di fase. L'effetto
#    non cambia perche' in questa immagine la luminosita' cala allontanandosi
#    dal punto caldo: la luce cresce lo stesso verso l'esterno.
#
# 3. LA RAMPA NON PARTE DAL NERO, PARTE DALLA NOTTE. La prima versione faceva
#    partire l'arco da un nero quasi assoluto (luminanza 0,8) mentre il buio
#    che lo circonda sta a 8,9: al quadro zero si vedeva la SAGOMA della
#    maschera come una macchia nera su un grigio scurissimo, e la maschera e'
#    il 44% dello schermo. Non basta pero' un nero solo: il buio non e' uniforme
#    - lo spazio profondo sta a 4, il bordo del bagliore a 9 - quindi una tinta
#    piatta lascerebbe comunque un gradino da qualche parte.
#    Si ricostruisce percio' la NOTTE SOTTO L'ARCO (`campo_notte`) con una
#    convoluzione normalizzata multiscala: per ogni pixel si usa il raggio piu'
#    PICCOLO che raccoglie abbastanza buio, cosi' vicino al bordo il campo segue
#    il buio locale e in mezzo all'arco subentrano i raggi larghi. Misurato: il
#    gradino al confine scende da 8,1 a 0,5 su 255.
#    Il fondo si somma alla rampa e SVANISCE con la fase - `rampa + fondo*(1-u)`
#    - quindi al livello 0 ogni voce vale esattamente la notte e all'ultimo
#    livello esattamente il suo colore finale. Il giro sui file resta esatto.
#
# NIENTE .iff PER LE RAMPE, E NON E' UNO SCONTO SULLA REGOLA. La regola dice
# .raw di GRAFICA piu' .iff. `alba.raw` e' grafica e passa da `salva`, che
# scrive tutti e due. Le rampe sono una TABELLA di colori, non una bitmap: un
# ILBM vorrebbe una palette indicizzata che qui non ha senso. L'anteprima c'e'
# lo stesso ed e' un PNG, perche' lo scopo della regola - poterla guardare - va
# rispettato anche quando il formato non c'entra.
# ============================================================================
import os, sys
import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grafica

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORGENTE = os.path.join(RADICE, 'risorse', 'grafica', 'alba-sorgente.png')
DEST_IMG = os.path.join(RADICE, 'grafica', 'alba.raw')
DEST_RAMPE = os.path.join(RADICE, 'grafica', 'alba_rampe.raw')
DEST_INIZIO = os.path.join(RADICE, 'grafica', 'alba_inizio.raw')
DEST_PNG = os.path.join(RADICE, 'risorse', 'grafica', 'alba-rampe.png')

# ---------------------------------------------------------------- geometria
LARG, ALT, PIANI = 320, 256, 8
VOCI = 1 << PIANI

# Quante voci delle 256 vanno all'ARCO invece che al buio. Il buio e' il 56%
# dei pixel ma e' liscio e scuro: gli bastano poche voci. L'arco e' la cosa
# che si guarda, e a lui vanno le altre. Misurato: con 180 l'errore dentro
# l'arco e' 2,48 e nel buio 0,50; a 200 l'arco migliora di poco e il buio
# peggiora del 50%.
VOCI_ARCO = 180

# La maschera dell'arco. La soglia NON e' a occhio: a 26 la cosa piu' luminosa
# lasciata fuori valeva 47/255 e si vedeva accesa gia' al primo quadro, come
# un filo che non si spegne mai; a 12 vale 22, ed e' il disco scuro del
# pianeta, che deve restare visibile - lo schermo non e' mai del tutto nero.
ARCO_SOGLIA = 12
ARCO_SFOCA = 6

# ---------------------------------------------------------------- tempi
# I livelli della rampa. MISURATO: la voce che viaggia di piu' copre 87 L*,
# quindi il gradino e' 87/LIVELLI. Con 64 sarebbe 1,36 L*, con 128 e' 0,68,
# cioe' sotto la soglia percettiva anche col metro SPAZIALE, che qui e' pure
# troppo severo (questo gradino e' nel TEMPO, e a 50 Hz l'occhio perdona di
# piu'). Dimezzando i livelli si dimezza la tabella: e' la manopola.
LIVELLI = 128
LIV_SH = 1                       # quadri per livello = 2^LIV_SH
RAMPA_QUADRI = LIVELLI << LIV_SH        # 256 quadri per una rampa intera
SPREAD_QUADRI = 192                     # scarto fra la prima voce e l'ultima
TOT_QUADRI = SPREAD_QUADRI + RAMPA_QUADRI   # 448 = 8,96 s a 50 Hz

# La rampa del colore, in FRAZIONI del colore finale della voce.
# Brace -> rosso -> arancio -> giallo -> il colore vero. Da nero a bianco si
# passerebbe per il grigio, e un arco grigio non sembra una luce che si
# accende, sembra una foto sbiadita.
# Il primo punto e' ZERO e non un rosso cupo: al livello 0 quello che si deve
# vedere e' la notte, e la notte la mette `campo_notte` sommandosi qui sopra.
STOP = [(0.00, (0.000, 0.000, 0.000)),
        (0.26, (0.470, 0.086, 0.012)),
        (0.50, (0.880, 0.345, 0.055)),
        (0.76, (1.000, 0.725, 0.337))]

# Il campo della notte: raggi provati in ordine, si tiene il primo che raccoglie
# almeno NOTTE_SOGLIA di buio. Il piu' piccolo che basta e' quello che segue il
# buio locale, ed e' quello che fa sparire il gradino al confine.
NOTTE_RAGGI = (8, 12, 18, 26, 40, 60, 90)
NOTTE_SOGLIA = 0.10
NOTTE_LISCIA = 5                 # una passata finale, toglie le venature

LUM = np.array([0.299, 0.587, 0.114])


def sorgente():
    """L'immagine ritagliata a 320x256. Il sorgente e' 480x360 (rapporto
    1.333), la destinazione 1.250: si toglie dai lati, non dall'alto."""
    im = Image.open(SORGENTE).convert('RGB')
    W, H = im.size
    largo = int(round(H * LARG / ALT))
    x0 = (W - largo) // 2
    return im.crop((x0, 0, x0 + largo, H)).resize((LARG, ALT), Image.LANCZOS)


def maschera_arco(a):
    """Chi si accende e chi no. L'arco e' la fascia luminosa del lembo piu' la
    sua aureola; il resto - il disco scuro del pianeta e lo spazio - non si
    anima affatto e si vede dal primo quadro."""
    lum = (a * LUM).sum(axis=2)
    sf = np.asarray(Image.fromarray(lum.astype(np.uint8))
                    .filter(ImageFilter.GaussianBlur(ARCO_SFOCA))).astype(float)
    return sf > ARCO_SOGLIA


def _media_mobile(x, r, asse):
    n = x.shape[asse]
    pad = [(0, 0)] * x.ndim
    pad[asse] = (r + 1, r)
    c = np.cumsum(np.pad(x, pad, mode='edge'), axis=asse)
    sl = lambda p, q: tuple(slice(p, q) if i == asse else slice(None)
                            for i in range(x.ndim))
    return (c[sl(2 * r + 1, None)] - c[sl(0, n)]) / (2 * r + 1)


def sfoca(x, r):
    """Sfocatura in virgola mobile. Non si usa PIL: il suo GaussianBlur vuole
    un'immagine a byte, e qui i valori in gioco sono 4..11 su 255 - passare da
    un uint8 li troncherebbe proprio dove serve precisione. Tre passate di
    media mobile approssimano una gaussiana abbastanza bene per un fondo."""
    for _ in range(3):
        x = _media_mobile(_media_mobile(x, r, 0), r, 1)
    return x


def campo_notte(a, arco):
    """Che aspetto ha la scena PRIMA che si accenda: il buio vero dove c'e', e
    sotto l'arco il buio che ci sarebbe se l'arco non fosse illuminato.
    Convoluzione normalizzata multiscala - vedi la regola 3 in testa al file."""
    buio = (~arco).astype(float)
    fuori = np.zeros_like(a)
    fatto = np.zeros(arco.shape, bool)
    for r in NOTTE_RAGGI:
        peso = sfoca(buio, r)
        n = np.stack([sfoca(a[:, :, k] * buio, r) / np.maximum(peso, 1e-9)
                      for k in range(3)], axis=2)
        ok = (peso > NOTTE_SOGLIA) & ~fatto
        fuori[ok] = n[ok]
        fatto |= ok
    if not fatto.all():                       # non dovrebbe succedere mai
        fuori[~fatto] = a[~arco].mean(axis=0)
    fuori = np.stack([sfoca(fuori[:, :, k], NOTTE_LISCIA) for k in range(3)], axis=2)
    fuori[~arco] = a[~arco]                   # fuori dall'arco la notte E' l'immagine
    return np.clip(fuori, 0, 255)


def quantizza(a, arco):
    """Palette e indici. Le due zone si quantizzano SEPARATAMENTE, se no il
    buio - che e' la maggioranza dei pixel - si prende quasi tutte le voci e
    l'arco resta a scalini. Le prime VOCI_ARCO sono l'arco, per costruzione:
    a runtime 'questa voce si anima?' e' un confronto, non una tabella."""
    tavole = []
    for m, n in ((arco, VOCI_ARCO), (~arco, VOCI - VOCI_ARCO)):
        img = Image.fromarray(np.where(m[:, :, None], a, 0).astype(np.uint8))
        q = img.quantize(colors=n, method=Image.MEDIANCUT)
        tavole.append(np.array(q.getpalette()[:3 * n]).reshape(n, 3).astype(float))
    p1, p2 = tavole
    pal = np.vstack([p1, p2])
    idx = np.zeros((ALT, LARG), int)
    for m, off, pp in ((arco, 0, p1), (~arco, VOCI_ARCO, p2)):
        d = ((a[m][:, None, :] - pp[None, :, :]) ** 2).sum(axis=2)
        idx[m] = d.argmin(axis=1) + off
    return pal, idx


def rampa(u, finale, scala):
    """Il colore di una voce alla fase u (0..1). `scala` e' la luminanza della
    voce: e' lei a rendere la rampa RELATIVA invece che assoluta."""
    out = np.zeros((len(u), 3))
    for k in range(len(STOP) - 1):
        a0, c0 = STOP[k]
        a1, c1 = STOP[k + 1]
        m = (u >= a0) & (u < a1)
        if m.any():
            f = ((u - a0) / (a1 - a0))[m][:, None]
            out[m] = (np.array(c0) * (1 - f) + np.array(c1) * f) * scala[m][:, None]
    a0, c0 = STOP[-1]
    m = u >= a0
    if m.any():
        f = ((u - a0) / (1 - a0))[m][:, None]
        out[m] = (np.array(c0) * scala[m][:, None]) * (1 - f) + finale[m] * f
    return np.clip(out, 0, 255)


def inizio_per_voce(lum_v):
    """Il quadro in cui ogni voce comincia. Le piu' luminose per prime: e' la
    regola 2 in testa al file. L'esponente 0,75 anticipa un po' le mediane,
    che altrimenti si accalcano in fondo."""
    ini = np.zeros(VOCI, dtype=int)
    lm = lum_v[:VOCI_ARCO]
    ini[:VOCI_ARCO] = np.round(SPREAD_QUADRI * (1 - lm / lm.max()) ** 0.75)
    return ini


def impacchetta(c):
    """RGB a 8 bit -> le due word che il copper scrive su un COLORxx: prima i
    nibble ALTI di ogni componente, poi i BASSI. E' la stessa coppia di
    passate che fa LoadAGAPalette256, precalcolata."""
    r, g, b = [np.clip(c[:, i], 0, 255).astype(int) for i in range(3)]
    hi = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4)
    lo = ((r & 15) << 8) | ((g & 15) << 4) | (b & 15)
    return hi, lo


def main():
    a = np.asarray(sorgente()).astype(float)
    arco = maschera_arco(a)
    notte = campo_notte(a, arco)
    pal, idx = quantizza(a, arco)
    err = np.sqrt(((a - pal[idx]) ** 2).sum(axis=2))
    lum_v = pal @ LUM
    ini = inizio_per_voce(lum_v)
    scala = np.maximum(lum_v, 1.0)

    # Il fondo di ogni voce: di che colore e' la notte dove stanno i suoi pixel.
    # Voce per voce e non uno solo per tutte, se no il gradino si sposta invece
    # di sparire.
    fondo = np.zeros((VOCI, 3))
    for v in range(VOCI_ARCO):
        m = idx == v
        fondo[v] = notte[m].mean(axis=0) if m.any() else 0.0

    # la rampa di ogni voce, LIVELLI colori. Le voci che non si animano hanno
    # una rampa costante: cosi' il ciclo a runtime non ha casi speciali.
    rampe = np.zeros((VOCI, LIVELLI, 3))
    u = np.arange(LIVELLI) / (LIVELLI - 1)
    u = u * u * (3 - 2 * u)                     # smoothstep: parte e finisce piano
    for k in range(LIVELLI):
        uu = np.full(VOCI_ARCO, u[k])
        c = rampa(uu, pal[:VOCI_ARCO], scala[:VOCI_ARCO])
        # il fondo si SOMMA e svanisce con la fase: al livello 0 la voce vale
        # esattamente la notte, all'ultimo esattamente il suo colore finale
        rampe[:VOCI_ARCO, k] = np.clip(c + fondo[:VOCI_ARCO] * (1 - u[k]), 0, 255)
        rampe[VOCI_ARCO:, k] = pal[VOCI_ARCO:]

    corsa = None
    if '--misure' in sys.argv or True:
        def L(rgb):
            c = np.clip(rgb, 0, 255) / 255.0
            c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
            Y = c @ np.array([0.2126, 0.7152, 0.0722])
            return np.where(Y > 0.008856, 116 * np.cbrt(Y) - 16, 903.3 * Y)
        Ls = np.array([L(rampe[:, k]) for k in range(LIVELLI)])
        corsa = (Ls.max(axis=0) - Ls.min(axis=0))
        print('errore di quantizzazione: arco %.2f, buio %.2f, totale %.2f'
              % (err[arco].mean(), err[~arco].mean(), err.mean()))
        print('corsa massima in L*: %.1f -> gradino %.2f L* con %d livelli'
              % (corsa.max(), corsa.max() / LIVELLI, LIVELLI))
        prima = rampe[np.arange(VOCI), np.maximum(0, -ini)]
        print('al quadro 0 il pixel piu acceso vale %.0f su 255'
              % (prima[idx] @ LUM).max())
        # il gradino al confine dell'arco: e' il difetto che il fondo toglie
        bordo = maschera_arco(a) ^ arco
        gonfio = np.zeros_like(arco)
        gonfio[1:] |= arco[:-1]; gonfio[:-1] |= arco[1:]
        gonfio[:, 1:] |= arco[:, :-1]; gonfio[:, :-1] |= arco[:, 1:]
        fu = (prima[idx] @ LUM)[gonfio & ~arco].mean()
        de = (prima[idx] @ LUM)[arco & ~(~gonfio | ~arco)].mean() if arco.any() else 0
        de = (prima[idx] @ LUM)[arco].mean()
        print('al quadro 0, luminanza media: fuori dall arco %.2f, dentro %.2f'
              % (fu, de))
        ult = rampe[:, LIVELLI - 1]
        print('scarto fra l ultimo livello e la palette di arrivo: %.0f (0 = esatto)'
              % np.abs(ult - pal).max())
        print('durata: %d quadri = %.2f s a 50 Hz (rampa %d + scarto %d)'
              % (TOT_QUADRI, TOT_QUADRI / 50.0, RAMPA_QUADRI, SPREAD_QUADRI))
    if '--misure' in sys.argv:
        return 0

    # ---- l'immagine, dalla via unica ----
    n_img, n_iff, p_iff = grafica.salva(DEST_IMG, [list(r) for r in idx],
                                        LARG, ALT, PIANI, [tuple(c) for c in
                                                           pal.round().astype(int)])
    # ---- la tabella delle rampe: voce per voce, livello per livello ----
    buf = bytearray()
    for v in range(VOCI):
        hi, lo = impacchetta(rampe[v])
        for k in range(LIVELLI):
            buf += int(hi[k]).to_bytes(2, 'big') + int(lo[k]).to_bytes(2, 'big')
    open(DEST_RAMPE, 'wb').write(bytes(buf))
    # ---- il quadro d'inizio di ogni voce ----
    open(DEST_INIZIO, 'wb').write(b''.join(int(x).to_bytes(2, 'big') for x in ini))

    # ---- l'anteprima delle rampe: la partitura dell'effetto ----
    part = np.zeros((VOCI, LIVELLI, 3), np.uint8)
    for v in range(VOCI):
        part[v] = rampe[v].round().astype(np.uint8)
    Image.fromarray(part).resize((LIVELLI * 3, VOCI * 2), Image.NEAREST).save(DEST_PNG)

    print()
    print('alba.raw         %6d byte   %dx%d, %d piani' % (n_img, LARG, ALT, PIANI))
    print('alba_rampe.raw   %6d byte   %d voci x %d livelli x 2 word'
          % (len(buf), VOCI, LIVELLI))
    print('alba_inizio.raw  %6d byte   %d word' % (VOCI * 2, VOCI))
    print('anteprime        %s' % os.path.relpath(p_iff, RADICE))
    print('                 %s' % os.path.relpath(DEST_PNG, RADICE))
    print()
    print('Le EQU da tenere in pari (Gioco.s):')
    print('  ALBA_VOCI_ARCO      %d' % VOCI_ARCO)
    print('  ALBA_LIVELLI        %d' % LIVELLI)
    print('  ALBA_LIV_SH         %d' % LIV_SH)
    print('  ALBA_SPREAD         %d' % SPREAD_QUADRI)
    print('  ALBA_QUADRI         %d' % TOT_QUADRI)
    print('  ALBA_LEN_ATTESA     %d' % n_img)
    print('  ALBA_RAMPE_ATTESA   %d' % len(buf))
    print('  ALBA_INIZIO_ATTESA  %d' % (VOCI * 2))
    return 0


if __name__ == '__main__':
    sys.exit(main())
