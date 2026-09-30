#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-alberi-sprite.py - la parallasse come ALBERI SEPARATI: uno sprite per
#   albero, ognuno con la sua Y fissa, il suo livello di profondita' e
#   VENTO_POSE fotogrammi di oscillazione.
#
# USO (dalla cartella Megagame):  python3 tools/genera-alberi-sprite.py
#
# PERCHE' NON LE FETTE
# Le fette erano l'approccio precedente: genera-fette-parallasse.py tagliava
# grafica/parallasse.raw in strisce da 64 px. Tolto l'8 settembre 2026 insieme
# ai suoi file; resta qui il MOTIVO, che e' quello che serve sapere.
# Con le fette tutta la parallasse e' una striscia
# sola: sei canali affiancati che si muovono insieme, quindi UNA velocita'. Due
# livelli a velocita' diverse vorrebbero due sprite sulla stessa riga dello
# stesso canale, e un canale ne mostra uno solo.
#
# Con un albero per sprite il vincolo cambia natura: due alberi in canali
# DIVERSI si sovrappongono quanto vogliono. E siccome un albero si muove solo
# in X, la sua Y non cambia mai: l'assegnazione albero->canale si calcola una
# volta e non si tocca piu'. Resta un vincolo solo:
#
#     numero di canali = massimo numero di alberi che condividono una riga
#
# IL VENTO E' DISEGNATO, NON CALCOLATO
# Il primo tentativo tagliava l'albero in tre sprite impilati e spostava in X
# la cima e il mezzo. Funzionava - stesso canale, stesso costo - ma l'effetto
# era brutto: tre segmenti rigidi che scorrono uno sull'altro, con due scalini
# visibili nei punti di taglio. Un albero non si spezza in tre, si FLETTE.
#
# Adesso ogni albero ha VENTO_POSE disegni completi, uno per grado di
# flessione, e il vento e' un cambio di puntatore. La curva e'
#
#     scostamento(h) = piega * h^2      con h = altezza dalla base, 0..1
#
# cioe' la deflessione di una trave incastrata: zero alla base - l'albero non
# pattina sul terreno - e massima in cima. I rami seguono l'asse, quindi non
# sfarfallano: fra una posa e l'altra la loro FORMA e' identica, cambia solo
# dove l'asse li porta. Per questo ogni posa si ridisegna con lo STESSO SEME.
#
# Il prezzo e' la chip RAM: VENTO_POSE copie dell'arte. Lo stampa lo script.
#
# IL PERIODO E' 384 = DIW_WIDTH + 64, e non e' una scelta estetica:
#     x_liv  = (x_albero - offset_del_livello) mod 384
#     HSTART = DIW_H_START - 64 + x_liv
# fa stare HSTART fra 65 e 449, cioe' sempre dentro i 9 bit del registro. A 65
# l'albero finisce appena fuori a sinistra, a 449 comincia dove la finestra
# chiude: esce e rientra da solo, senza un ramo "se e' fuori schermo".
#
# QUELLO CHE NON DECIDE QUESTO SCRIPT
# Le tinte e la geometria si LEGGONO da Gioco.s. La tabella degli alberi la
# stampa lui e va incollata li': e' l'unico punto in cui i due file si devono
# somigliare, e la guardia sulla lunghezza del .raw se ne accorge se divergono.
# ============================================================================
import os, sys, random, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import grafica

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(RADICE, 'grafica', 'alberi_parallasse.raw')

SPR_W = 64                      # un prelievo sprite a 64 bit
CTRL_B, RIGA_B, FINE_B = 16, 16, 16
PIANI = 2

DIW_H_START = grafica.equ('DIW_H_START')
VIS = 256 - grafica.equ('CUT_BOTTOM_ROWS')
RASTER0 = 0x2C                  # prima riga della finestra di display
PERIODO = 320 + SPR_W           # vedi il commento in testa

# ---------------------------------------------------------------- il vento
# VENTO_POSE disegni per albero, percorsi da un ciclo che va avanti e indietro
# (cosi' il ritorno non ha lo scatto di un 4->0). La sua lunghezza DEVE essere
# potenza di due: il gioco la maschera con un AND.
VENTO_POSE = 5
VENTO_CICLO_N = 16              # passi del ciclo, potenza di due
VENTO_LENTO = 3                 # quadri per passo, 2^VENTO_LENTO
# Il ciclo NON e' lineare: e' un seno campionato, cioe' le pose percorse con la
# cadenza di un pendolo - lento agli estremi, svelto in mezzo. Un ciclo lineare
# (0,1,2,3,4,3,2,1) fa avanzare la cima di due pixel a intervalli uguali, e piu'
# lo si rallenta piu' quei due pixel si vedono come uno scatto. Con la
# campionatura a seno la posa estrema si ripete tre volte di fila - l'albero
# resta fermo dove un pendolo sarebbe fermo - e il movimento e' concentrato
# dove l'occhio se lo aspetta.
VENTO_CICLO = [int(round((VENTO_POSE-1)/2.0
                         * (1 + math.sin(2*math.pi*k/VENTO_CICLO_N))))
               for k in range(VENTO_CICLO_N)]
VENTO_AMPIEZZA = 4              # px di flessione della CIMA, dal centro

# ---------------------------------------------------------- l'ombreggiatura
# I tre valori di un pixel sprite non sono piu' tre livelli di profondita' ma
# tre gradi di LUCE dentro un albero solo. La profondita' la decide il canale:
# le coppie 0 e 1 (canali 0..3) portano la rampa dei vicini, le coppie 2 e 3
# (canali 4..6) quella dei lontani, e i colori li scrive la copperlist.
OMBRA, CORPO, LUCE = 1, 2, 3
OMBRA_DA = 3                    # spessore minimo per la lama scura
LUCE_DA = 4                     # ... e per quella chiara, che chiede di piu'
# piega di ogni posa: -A .. +A, con la posa centrale dritta
PIEGHE = [(-1.0 + 2.0*k/(VENTO_POSE-1)) * VENTO_AMPIEZZA
          for k in range(VENTO_POSE)]

# ---------------------------------------------------------------- la scena
# (nome, livello, base in righe visibili, altezza, larghezza base, larghezza
#  chioma, x nel periodo, seme, quanti alberi). Il livello e' anche il VALORE
#  pixel, quindi la tinta:
#  1 = SKYLINE_C1_RGB, la piu' scura -> i vicini, DAVANTI
#  3 = SKYLINE_C3_RGB, la piu' chiara -> i lontani, DIETRO
#  La 2 (mezzatinta) non serve con due soli livelli.
# I VICINI vanno nei canali BASSI perche' fra sprite vince il numero piu'
# basso: l'ordine di profondita' lo fa l'hardware, non la palette.
#
# TUTTI GLI ALBERI SI APPOGGIANO AL FONDO dell'area di gioco: la base e' VIS
# per ognuno, e cambia solo l'altezza. Ha una conseguenza che va guardata in
# faccia: se tutti arrivano in fondo, tutti condividono le righe basse, quindi
# il picco di sovrapposizione E' il numero di alberi. Sette e' il tetto esatto,
# non uno di piu' - e per averne di piu' l'unica strada sarebbe staccarne
# qualcuno dal fondo.
# L'ultimo campo e' QUANTI alberi stanno in quello sprite. Si alternano 3 e 2
# su tutti e due i livelli: un gruppo fitto e uno rado, cosi' il bosco non ha
# una densita' uniforme che tradirebbe la ripetizione dei sette rettangoli.
# Il davanti fa 3,2,3,2 come chiesto; il dietro fa 3,2,3 e non 3,2,3,2 perche'
# i canali sono SETTE - vedi il commento in testa: quattro piu' quattro sono
# otto, e l'ottavo non esiste.
ALBERI = [
    # nome livello base altezza largh_base largh_chioma  x   seme quanti
    ('V0', 1, 176, 152, 13, 34,   0, 3011, 3),
    ('V1', 1, 176, 148, 12, 32,  96, 3022, 2),
    ('V2', 1, 176, 156, 14, 36, 192, 3033, 3),
    ('V3', 1, 176, 142, 11, 28, 288, 3044, 2),
    ('L0', 3, 176, 134,  9, 24,  48, 1011, 3),
    ('L1', 3, 176, 126,  8, 22, 176, 1022, 2),
    ('L2', 3, 176, 140, 10, 26, 304, 1033, 3),
]


def disegna_conifera(tela, cx0, y_fondo, altezza, largh_base, largh_chioma,
                     val, rnd, piega):
    """Disegna UNA conifera dentro una tela gia' fatta, con la base a y_fondo.
    Sta separata dalla creazione della tela apposta: cosi' uno sprite puo'
    ospitarne due o tre, che dentro 64 px e' un gruppo di alberi vicini.

    La forma segue l'immagine di riferimento: il tronco si allarga verso il
    basso come t^2.2 - quindi resta sottile per quasi tutta l'altezza e si apre
    solo negli ultimi pixel - sale con una curva lenta, e i rami sono corti e
    finiscono in ciuffi tondi. Sotto il 62% resta il fusto nudo.

    `piega` e' lo scostamento in px della CIMA. Entra nell'asse come h^2 con h
    = altezza dalla base: alla base vale zero, quindi l'albero si flette invece
    di scivolare. I rami leggono lo stesso asse, quindi seguono la flessione
    senza cambiare forma.
    """
    H = len(tela)
    y_cima = y_fondo - altezza + 1

    def punto(x, y):
        if 0 <= x < SPR_W and 0 <= y < H:
            tela[y][x] = val

    def disco(cx, cy, r):
        ri = int(r) + 1
        for dy in range(-ri, ri+1):
            for dx in range(-ri, ri+1):
                if dx*dx + dy*dy <= r*r:
                    punto(cx+dx, cy+dy)

    fase = rnd.uniform(0, 6.28)
    ampiezza = rnd.uniform(1.5, 3.0)
    # La CIMA e' una punta vera: nelle prime k_punta righe la semilarghezza
    # sale da zero, quindi l'albero comincia con un pixel solo e si apre. Il
    # profilo del tronco (t^2.2) da solo lascerebbe una cima tozza di 3-4 px.
    k_punta = max(4, int(altezza * 0.09))
    asse = []
    for k in range(altezza):
        t = k / float(altezza - 1)          # 0 in cima, 1 alla base
        semi = 1.5 + (largh_base/2.0 - 1.5) * (t ** 2.2)
        if k < k_punta:
            semi = min(semi, 0.1 + 1.4 * (k / float(k_punta)))
        h = 1.0 - t                         # altezza dalla base, 0..1
        cx = cx0 + ampiezza * math.sin(2.2*t + fase) + piega * h * h
        asse.append(cx)
        y = y_cima + k
        for dx in range(-int(semi+0.5), int(semi+0.5)+1):
            punto(int(round(cx)) + dx, y)

    # i rami cominciano SOTTO la punta, se no la rimpolpano e la punta sparisce
    k_alto = int(altezza * 0.15)
    k_basso = int(altezza * 0.62)
    passo = max(5, int(altezza * 0.055))
    lato = 1 if rnd.random() < 0.5 else -1
    k = k_alto
    while k < k_basso:
        t = (k - k_alto) / float(max(1, k_basso - k_alto))
        lung = (largh_chioma/2.0) * (0.35 + 0.65*t) * rnd.uniform(0.75, 1.05)
        cx = asse[k]
        cala = rnd.uniform(0.10, 0.30) * lung
        passi = max(3, int(lung))
        for i in range(passi + 1):
            u = i / float(passi)
            xx = int(round(cx + lato*lung*u))
            yy = int(round(y_cima + k + cala*u*u))
            punto(xx, yy)
            # Il ramo resta di UN pixel per quasi tutta la sua corsa e si
            # ispessisce solo nell'ultimo terzo, dove attacca il ciuffo. Prima
            # raddoppiava dopo un quarto, e con piu' alberi per sprite i rami
            # si toccavano fra un albero e l'altro: la chioma diventava una
            # massa unica e le sagome sparivano.
            if u > 0.66:
                punto(xx, yy + 1)
        tx = int(round(cx + lato*lung))
        ty = int(round(y_cima + k + cala))
        r = rnd.uniform(1.7, 2.9)           # ciuffi piu' piccoli, stessa forma
        disco(tx, ty, r)
        disco(tx - lato*int(r), ty - int(r*0.7), r*0.68)
        if rnd.random() < 0.4:
            disco(tx, ty - int(r*1.3), r*0.60)
        lato = -lato
        k += passo + rnd.randint(-1, 2)

    # niente disco sulla cima: la punta la fa il tronco. Un ciuffo qui la
    # rimpallottolava, ed e' proprio quello che non si voleva.


def sagoma(altezza, largh_base, largh_chioma, val, seme, quanti, piega):
    """La tela di uno sprite: `quanti` alberi affiancati dentro i 64 px.

    Piu' alberi nello stesso sprite NON costano un byte: la tela e' gia' larga
    64 px e alta quanto il gruppo a ogni posa, quindi disegnarci dentro tre
    alberi invece di uno riempie spazio gia' pagato. Quello che si spende e'
    altrove: gli alberi di uno stesso sprite hanno lo STESSO HSTART, quindi si
    muovono rigidi fra loro e oscillano in fase. Dentro 64 px va bene - una
    folata prende insieme gli alberi vicini - ma e' il motivo per cui non si
    puo' fare un bosco intero con un canale.

    Il PRIMO albero e' alto quanto la tela: e' lui a fissare VSTART, e se
    fossero tutti piu' bassi la tela avrebbe righe vuote in cima, cioe' byte
    di chip sprecati. Gli altri sono scalati, e siccome un albero piu' basso si
    flette meno (la curva e' h^2) il gruppo si piega a ventaglio invece che in
    blocco.

    IL SEME RIPARTE DA CAPO A OGNI POSA. E' la ragione per cui l'oscillazione
    non sfarfalla: rami, ciuffi e ondulazione del fusto escono identici, e
    l'unica cosa che cambia da una posa all'altra e' `piega`."""
    tela = [[0]*SPR_W for _ in range(altezza)]
    # I tronchi stanno RIENTRATI dai bordi: un ramo tagliato dal bordo dello
    # sprite si legge come un taglio dritto, e fra due sprite vicini si vedrebbe
    # la cucitura. Il rientro lascia ai rami esterni lo spazio per finire.
    centri = {1: [32], 2: [21, 43], 3: [14, 32, 50]}[quanti]
    # con piu' alberi le chiome si stringono, se no si fondono in una massa
    stretta = {1: 1.00, 2: 0.82, 3: 0.64}[quanti]
    for i, cx in enumerate(centri):
        rnd = random.Random(seme + i*97)
        alt = altezza if i == 0 else int(altezza * rnd.uniform(0.74, 0.94))
        p = piega * (alt/float(altezza))**2
        disegna_conifera(tela, cx, altezza-1, alt,
                         largh_base * rnd.uniform(0.80, 1.0),
                         largh_chioma * stretta * rnd.uniform(0.85, 1.05),
                         CORPO, rnd, p)
    return cilindro(tela)


def cilindro(tela):
    """Il tronco letto come un CILINDRO: una lama di LUCE a sinistra e una di
    OMBRA a destra, messe solo dove la sagoma e' abbastanza spessa.

    I due lati NON sono simmetrici, e il motivo e' il fondo. Il cielo e' chiaro:
    SCURIRE aumenta il contrasto della sagoma, quindi l'ombra si puo' caricare;
    SCHIARIRE lo riduce, e su un ramo da un pixel lo fa proprio sparire. E' lo
    stesso errore gia' annotato in SKYLINE_MIX, dove il mix col cielo scioglieva
    i rami. Per questo la lama chiara parte da uno spessore piu' alto di quella
    scura, e nessuna delle due tocca i rami sottili.

    Il valore del pixel non porta piu' la profondita': quella la decide QUALE
    CANALE ospita l'albero. Porta l'ombreggiatura, e i tre colori di ogni
    coppia di sprite sono la rampa del suo livello."""
    H = len(tela); W = len(tela[0])
    out = [r[:] for r in tela]
    for y in range(H):
        x = 0
        while x < W:
            if not tela[y][x]:
                x += 1; continue
            a = x
            while x < W and tela[y][x]:
                x += 1
            sp = x - a                       # spessore del tratto pieno
            if sp >= OMBRA_DA:
                out[y][x-1] = OMBRA
                if sp >= OMBRA_DA*2: out[y][x-2] = OMBRA
            if sp >= LUCE_DA:
                out[y][a] = LUCE
                if sp >= LUCE_DA*2: out[y][a+1] = LUCE
    return out


def impagina(tela, vstart, vstop):
    """Dalla tela ai byte di UNO sprite a 64 bit, terminatore compreso.

    Il terminatore chiude la lista del canale. Qui ogni posa e' un pezzo unico
    e ne porta uno; quando invece si impilano piu' sprite nello stesso canale
    va messo SOLO dopo l'ultimo, se no il DMA si ferma sul primo - il 5
    settembre a schermo si vedevano le sole punte."""
    out = bytearray()
    sprpos = ((vstart & 0xFF) << 8) | ((DIW_H_START >> 1) & 0xFF)
    sprctl = (((vstop & 0xFF) << 8)
              | (((vstart >> 8) & 1) << 2)
              | (((vstop >> 8) & 1) << 1)
              | (DIW_H_START & 1))
    out += sprpos.to_bytes(2, 'big') + b'\0'*6
    out += sprctl.to_bytes(2, 'big') + b'\0'*6
    for riga in tela:
        a = bytearray(8); b = bytearray(8)
        for i, v in enumerate(riga):
            if not v: continue
            bit = 1 << (7 - (i & 7))
            if v & 1: a[i >> 3] |= bit
            if v & 2: b[i >> 3] |= bit
        out += bytes(a) + bytes(b)
    out += b'\0' * FINE_B
    return bytes(out)


def assegna_canali(alberi):
    """Greedy su intervalli: e' l'ottimo. I VICINI per primi, cosi' finiscono
    nei canali bassi e stanno davanti."""
    canali = []
    for a in sorted(alberi, key=lambda a: (a[1], a[2]-a[3])):
        y0, y1 = a[2]-a[3], a[2]
        for c in canali:
            if c[-1][2] < y0:
                c.append((a[0], y0, y1)); break
        else:
            canali.append([(a[0], y0, y1)])
    return canali


def main():
    if len(VENTO_CICLO) & (len(VENTO_CICLO)-1):
        print('VENTO_CICLO deve essere lungo una potenza di due'); return 1
    if max(VENTO_CICLO) >= VENTO_POSE:
        print('VENTO_CICLO nomina una posa che non esiste'); return 1

    pezzi, blocchi = [], []
    offset = 0
    rnd_fasi = random.Random(4242)
    for nome, liv, base, alt, lbase, lchioma, x, seme, quanti in ALBERI:
        vstart = RASTER0 + base - alt
        vstop = RASTER0 + base
        base_ofs = offset
        passo = None
        for piega in PIEGHE:
            tela = sagoma(alt, lbase, lchioma, liv, seme, quanti, piega)
            d = impagina(tela, vstart, vstop)
            if passo is None:
                passo = len(d)
            elif len(d) != passo:
                print('le pose di %s non hanno la stessa taglia' % nome); return 1
            blocchi.append(d)
            offset += len(d)
        fase = rnd_fasi.randrange(len(VENTO_CICLO))
        pezzi.append((nome, liv, x, alt, vstart, vstop, base_ofs, passo, fase))
    blob = b''.join(blocchi)

    canali = assegna_canali([(n, l, b, a) for n, l, b, a, _, _, _, _, _ in ALBERI])
    picco = max(sum(1 for _, l, b, a, *_ in ALBERI if b-a <= y <= b)
                for y in range(VIS))

    # La COPPIA di sprite decide il colore, quindi l'assegnazione canale->livello
    # non e' piu' un dettaglio interno: se un vicino finisse in un canale alto
    # uscirebbe con la rampa dei lontani. Qui si controlla che i canali 0..3
    # siano tutti vicini e i 4..6 tutti lontani, che e' quello che la copperlist
    # da' per scontato scrivendo due terne invece di quattro.
    liv_di = {n: l for n, l, *_ in ALBERI}
    mappa = [liv_di[c[0][0]] for c in canali]
    atteso = [1, 1, 1, 1, 3, 3, 3]
    if mappa != atteso:
        print('canale->livello e\' %s, la copperlist si aspetta %s' % (mappa, atteso))
        print('le due coppie basse devono essere i vicini e le due alte i lontani')
        return 1
    print('canale->livello: %s   coppie: vicini 0-1, lontani 2-3   OK' % mappa)

    print('alberi: %d   pose: %d   canali necessari: %d   picco su una riga: %d   %s'
          % (len(ALBERI), VENTO_POSE, len(canali), picco,
             'OK' if len(canali) <= 7 else 'SFORA I SETTE CANALI'))
    print('chip: %d byte (%.1f KB), periodo %d px' % (len(blob), len(blob)/1024, PERIODO))
    if len(blob) > 32767:
        print('offset oltre i 32767: il campo offset della tabella e\' un LONG')
    print()
    print('; --- tabella da incollare in Gioco.s ---')
    print('; nome liv  x  alt  VSTART VSTOP  passo   offset della posa 0')
    for nome, liv, x, alt, vs, vp, ofs, passo, fase in pezzi:
        print(';  %-4s %d  %3d  %3d   %3d   %3d   %5d   %6d'
              % (nome, liv, x, alt, vs, vp, passo, ofs))
    print('ALBERI_N        EQU     %d' % len(ALBERI))
    print('ALBERI_LEN_ATTESA EQU   %d\t; guardia: la lunghezza del .raw' % len(blob))
    print('VENTO_POSE      EQU     %d' % VENTO_POSE)
    print('VENTO_CICLO     EQU     %d' % len(VENTO_CICLO))
    print('VENTO_LENTO     EQU     %d\t; il giro dura %d quadri, %.2f s a 50 Hz'
          % (VENTO_LENTO, len(VENTO_CICLO)<<VENTO_LENTO,
             (len(VENTO_CICLO)<<VENTO_LENTO)/50.0))
    print('AlberiTab:')
    for i, c in enumerate(canali):
        for nome, y0, y1 in c:
            p = [q for q in pezzi if q[0] == nome][0]
            print('\tdc.l\t%d' % p[6])
            print('\tdc.w\t%d,%d,%d,%d\t; canale %d, %s'
                  % (p[7], p[2], p[1], p[8], i, nome))
    print('VentoCiclo:')
    print('\tdc.b\t' + ','.join(str(v) for v in VENTO_CICLO))

    # L'anteprima ha TRE piani, non due come il .raw: il bit 2 dice il livello,
    # cosi' vicini e lontani si vedono con la LORO rampa invece che con una
    # rampa sola buona per meta' dell'immagine. Le sei tinte si leggono dalle
    # stesse EQU che scrive la copperlist, non si ricopiano.
    PIANI_IFF = 3
    palette = [grafica.rgb24(grafica.equ('CIELO_FISSO_RGB')),
               grafica.rgb24(grafica.equ('ALBERI_V_OMBRA_RGB')),
               grafica.rgb24(grafica.equ('ALBERI_V_CORPO_RGB')),
               grafica.rgb24(grafica.equ('ALBERI_V_LUCE_RGB')),
               grafica.rgb24(grafica.equ('CIELO_FISSO_RGB')),
               grafica.rgb24(grafica.equ('ALBERI_L_OMBRA_RGB')),
               grafica.rgb24(grafica.equ('ALBERI_L_CORPO_RGB')),
               grafica.rgb24(grafica.equ('ALBERI_L_LUCE_RGB'))]

    def decodifica(dati):
        """Anteprima: una colonna da 64 px per POSA, alta VIS, gli alberi in
        fila e le loro pose accanto.

        Non si fida degli offset calcolati qui sopra: PERCORRE LA LISTA COME IL
        DMA. Parte dal blocco della posa, legge VSTART/VSTOP dai byte veri,
        disegna le righe fino a VSTOP, poi legge il blocco che segue; si ferma
        quando trova il terminatore (blocco di controllo a zero).

        E' questo che rende l'anteprima una verifica e non un disegno: se un
        terminatore finisse in mezzo alla lista - il bug del 5 settembre - la
        colonna mostrerebbe la sola cima, esattamente come lo schermo."""
        colonne = len(canali) * VENTO_POSE
        rowb = (SPR_W*colonne)//8
        psz = rowb*VIS
        p = bytearray(psz*PIANI_IFF)
        rendiconto = []
        for i, c in enumerate(canali):
            nome = c[0][0]
            q = [z for z in pezzi if z[0] == nome][0]
            lontano = (q[1] != 1)
            letti = []
            for k in range(VENTO_POSE):
                pos = q[6] + k*q[7]
                col = i*VENTO_POSE + k
                visti = 0
                while pos + CTRL_B <= len(dati):
                    sprpos = int.from_bytes(dati[pos:pos+2], 'big')
                    sprctl = int.from_bytes(dati[pos+8:pos+10], 'big')
                    if sprpos == 0 and sprctl == 0:
                        break                   # terminatore: lista finita
                    vstart = ((sprctl & 4) << 6) | (sprpos >> 8)
                    vstop = ((sprctl & 2) << 7) | (sprctl >> 8)
                    righe = vstop - vstart
                    if righe <= 0 or righe > VIS:
                        rendiconto.append('%s posa %d: blocco malformato' % (nome, k))
                        break
                    for r in range(righe):
                        o = pos + CTRL_B + r*RIGA_B
                        y = (vstart - RASTER0) + r
                        if not (0 <= y < VIS): continue
                        for j in range(8):
                            dst = y*rowb + col*8 + j
                            p[dst] = dati[o+j]
                            p[psz+dst] = dati[o+8+j]
                            if lontano:
                                # terzo piano acceso dove c'e' un pixel: manda
                                # questo albero sulla seconda meta' della palette
                                p[2*psz+dst] = dati[o+j] | dati[o+8+j]
                    visti += 1
                    pos += CTRL_B + righe*RIGA_B
                letti.append(visti)
            rendiconto.append('canale %d  %-4s  pezzi letti dal DMA per posa: %s'
                              % (i, nome, letti))
        for r in rendiconto:
            print('   ' + r)
        return bytes(p)

    print()
    print('vento: %d pose, ciclo %s' % (VENTO_POSE, VENTO_CICLO))
    print('       un passo ogni %d quadri, giro completo in %d quadri (%.2f s)'
          % (1<<VENTO_LENTO, len(VENTO_CICLO)<<VENTO_LENTO,
             (len(VENTO_CICLO)<<VENTO_LENTO)/50.0))
    print()
    print('; --- rilettura del .raw seguendo la lista come il DMA ---')
    n, n_iff, p_iff = grafica.salva_sprite(
        DEST, blob, decodifica,
        SPR_W*len(canali)*VENTO_POSE, VIS, PIANI_IFF, palette)
    print()
    print('alberi_parallasse.raw  %d byte' % n)
    print('anteprima: %s' % os.path.relpath(p_iff, RADICE))
    return 0 if len(canali) <= 7 else 1


if __name__ == '__main__':
    sys.exit(main())
