#!/usr/bin/env python3
# ============================================================================
# gen-cielo.py - genera CieloGrad.i dalla tabella d'arte a 260 voci
#
# USO (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
#   python3 tools/gen-cielo.py tools/CieloGrad-arte-260.src > CieloGrad.i
#
# L'arte a 260 voci sta in tools/ e con estensione .src, non accanto ai
# sorgenti come .i: definisce gli stessi simboli (SkyGradient, SKY_SRC_ROWS)
# del file generato, quindi nella cartella del progetto sarebbe un doppione
# pronto a scattare al primo include distratto. E' l'ORIGINALE byte per byte
# del vecchio CieloGrad.i, non una copia rimaneggiata.
#
# ---------------------------------------------------------------------------
# PERCHE' ESISTE
#
# La lista copper del cielo scrive UN colore per riga raster: su RIGHE righe
# visibili ci sono RIGHE colori, non uno di piu'. La tabella d'arte pero' ne
# ha 260, quindi 84 vanno tolte. BuildSkyCopper lo faceva a runtime con
#
#       indice = i * 260 / RIGHE        troncato dalla DIVU
#
# e troncando SALTA voci intere: fra una riga e la successiva l'indice avanza
# di 1,477, quindi ogni tanto due gradini dell'arte finiscono compressi in una
# riga sola. Qui invece si INTERPOLA fra le due voci adiacenti: nessuna viene
# buttata, vengono fuse.
#
# ---------------------------------------------------------------------------
# LA RIPARTIZIONE E' UNA SCELTA DI COMPOSIZIONE, NON DI QUALITA'
#
# La tabella d'arte e' fatta di due pezzi diversi:
#   voci   0..211  l'ARTE vera, dal viola in cima al giallo dell'orizzonte
#   voci 212..259  una SFUMATURA AL NERO aggiunta a mano, che serve solo a
#                  chiudere il cielo sopra il pannello senza cucitura
#
# RIGHE_ARTE decide quante righe raster vanno al primo pezzo. E' la posizione
# dell'ORIZZONTE sullo schermo, quindi va scelta guardando, non calcolando.
#
# 144 riproduce ESATTAMENTE la composizione di prima: con il vecchio conto
# 143*260/176 = 211 (l'ultima voce d'arte) e 144*260/176 = 212 (la prima di
# sfumatura), quindi l'orizzonte cadeva gia' a riga 144. Cambiando questo
# numero il cielo si RIDISEGNA, non si liscia:
#
#   RIGHE_ARTE   sfumatura   dL* per riga   orizzonte
#      144          32           3,0        dove sta adesso
#      130          46           2,1        14 righe piu' in alto
#      116          60           1,6        28 righe piu' in alto
#       81          95           1,0        63 righe piu' in alto (invisibile)
#
# Il muro aritmetico: la sfumatura attraversa 96 unita' di L* (da 96,4 a 0) e
# la soglia sotto cui l'occhio non distingue due righe e' circa 1 unita'.
# Servono ~96 righe raster perche' sia invisibile, e le righe totali sono 176:
# una sfumatura senza scalini si paga in altezza del cielo, non in codice.
# ============================================================================
import re, sys

RIGHE = 176         # = BG_VIS_ROWS. Se cambia, si rigenera.
RIGHE_ARTE = 144    # righe date all'arte; le restanti vanno alla sfumatura
VOCI_ARTE = 212     # voci 0..211 = arte, 212..259 = sfumatura al nero


def leggi(path):
    """Estrae le coppie di word (hi,lo) dai dc.w del file sorgente."""
    w = []
    for m in re.finditer(r'dc\.w\s+([^\n;]+)', open(path, encoding='latin-1').read()):
        for t in m.group(1).split(','):
            t = t.strip()
            if t.startswith('$'):
                w.append(int(t[1:], 16))
    return [(w[i], w[i + 1]) for i in range(0, len(w), 2)]


def rgb(hi, lo):
    """AGA 24 bit: nibble alti in una word, nibble bassi nell'altra."""
    return (((hi >> 8) & 15) << 4 | ((lo >> 8) & 15),
            ((hi >> 4) & 15) << 4 | ((lo >> 4) & 15),
            ((hi) & 15) << 4 | (lo & 15))


def words(c):
    r, g, b = c
    return (((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4),
            ((r & 15) << 8) | ((g & 15) << 4) | (b & 15))


def dist(a, b):
    """Distanza fra due colori = il canale che si muove di piu'. E' il massimo
    e non la media perche' una banda si vede per il canale peggiore."""
    return max(abs(x - y) for x, y in zip(a, b))


def lin(u):
    u /= 255.0
    return u / 12.92 if u <= 0.04045 else ((u + 0.055) / 1.055) ** 2.4


def Lstar(c):
    """Chiarezza CIE L*. E' la scala in cui una differenza di 1 e' circa la
    soglia percettiva, quindi e' con questa che si giudica una banda: in RGB
    puro un salto di 8 sul chiaro e' invisibile e sullo scuro e' un gradino."""
    r, g, b = (lin(v) for v in c)
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return 116 * (Y ** (1 / 3)) - 16 if Y > 0.008856 else 903.3 * Y


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else 'tools/CieloGrad-arte-260.src'
    cols = [rgb(*e) for e in leggi(src)]
    ultima = len(cols) - 1
    fine_arte = VOCI_ARTE - 1

    def lerp(t):
        t = max(0.0, min(t, float(ultima)))
        i = int(t)
        if i >= ultima:
            return cols[ultima]
        f = t - i
        a, b = cols[i], cols[i + 1]
        return tuple(max(0, min(255, int(round(a[k] + (b[k] - a[k]) * f))))
                     for k in range(3))

    n_fade = RIGHE - RIGHE_ARTE
    out = [lerp(i * fine_arte / (RIGHE_ARTE - 1)) for i in range(RIGHE_ARTE)]
    out += [lerp(fine_arte + (j + 1) * (ultima - fine_arte) / n_fade)
            for j in range(n_fade)]

    assert len(out) == RIGHE
    assert out[0] == cols[0], 'la prima riga non e\' piu\' la prima voce d\'arte'
    assert out[RIGHE_ARTE - 1] == cols[fine_arte], 'l\'orizzonte si e\' spostato'
    assert out[-1] == cols[ultima], 'la sfumatura non arriva piu\' in fondo'
    assert all(rgb(*words(c)) == c for c in out), 'round-trip 24 bit non esatto'

    passi = [dist(a, b) for a, b in zip(out, out[1:])]
    L = [Lstar(c) for c in out]
    dL = [abs(a - b) for a, b in zip(L, L[1:])]
    dL_arte, dL_fade = dL[:RIGHE_ARTE - 1], dL[RIGHE_ARTE - 1:]

    P = print
    P('; =====================================================================')
    P('; CieloGrad.i - tabella colori del gradiente cielo')
    P(';')
    P('; GENERATO da tools/gen-cielo.py: NON modificare a mano, si rigenera.')
    P(';   python3 tools/gen-cielo.py tools/CieloGrad-arte-260.src > CieloGrad.i')
    P('; (dalla cartella Megagame; su Windows \'py\' al posto di \'python3\')')
    P('; La sorgente e\' tools/CieloGrad-arte-260.src, l\'arte a 260 voci: 212 righe')
    P('; estratte da CieloCopper.i piu\' 48 di sfumatura al nero aggiunte per')
    P('; chiudere il cielo sopra il pannello senza cucitura.')
    P(';')
    P('; UNA VOCE PER RIGA RASTER. Il copper scrive un colore per riga e le')
    P('; righe visibili sono BG_VIS_ROWS: tenere 260 voci per un display da')
    P('; %d significava buttarne via 84 a runtime. Il vecchio conto' % RIGHE)
    P('; i*260/%d le buttava TRONCANDO, e troncando saltava voci intere -' % RIGHE)
    P('; l\'indice avanza di 1,477 per riga, quindi ogni tanto due gradini')
    P('; dell\'arte finivano compressi in una riga sola. Qui le 84 voci non')
    P('; sono scartate ma FUSE: si interpola fra le due voci adiacenti.')
    P(';')
    P('; LA COMPOSIZIONE NON CAMBIA. L\'orizzonte (la voce piu\' luminosa')
    P('; dell\'arte) resta a riga %d come prima, perche\' col vecchio conto' % RIGHE_ARTE)
    P('; 143*260/%d dava 211 e 144*260/%d dava 212. Cambiare la ripartizione' % (RIGHE, RIGHE))
    P('; RIDISEGNA il cielo invece di lisciarlo: si fa da gen-cielo.py, dove')
    P('; c\'e\' la tabella del costo in altezza.')
    P(';')
    P('; MISURATO, in L* (la scala dove 1 e\' la soglia percettiva):')
    P(';                          arte 0..%-3d      sfumatura %d..%d' % (RIGHE_ARTE - 1, RIGHE_ARTE, RIGHE - 1))
    virg = lambda x: ('%.2f' % x).replace('.', ',')
    P(';   dL* massimo              %-17s %s' % (virg(max(dL_arte)), virg(max(dL_fade))))
    P(';   righe sopra soglia       %-17s %s'
      % ('%d su %d' % (sum(1 for x in dL_arte if x > 1.0), len(dL_arte)),
         '%d su %d' % (sum(1 for x in dL_fade if x > 1.0), len(dL_fade))))
    P(';   prima era                %-17s %s' % ('4 righe, dL* 1,12', '32 righe, dL* 4,99'))
    P(';')
    P('; Quindi: nell\'ARTE le bande spariscono del tutto. Nella SFUMATURA no,')
    P('; e non e\' un difetto di questo file: 96 unita\' di L* in %d righe fanno' % n_fade)
    P('; %s a riga contro una soglia di 1, e per stare sotto servirebbero ~96' % virg(96.4 / n_fade))
    P('; righe raster prese all\'arte. E\' un prezzo in composizione, non in')
    P('; codice, quindi la scelta non e\' mia.')
    P(';')
    P('; Salto massimo in RGB grezzo: %d livelli su 255 (prima: 11).' % max(passi))
    P(';')
    P('; Ogni voce sono le DUE word che il copper scrive su COLOR00: la prima')
    P('; con BPLCON3 LOCT=0 (nibble alti), la seconda con LOCT=1 (nibble')
    P('; bassi) - e\' il colore AGA a 24 bit spezzato come vuole l\'hardware.')
    P('; =====================================================================')
    P('; La prima riga raster e\' $2C. NON e\' una EQU qui: c\'era, non la')
    P('; leggeva nessuno, e il valore vive gia\' cablato in BuildSkyCopper')
    P('; (ADD.W #$2C), in DIWSTRT e in PANNELLO_TOP_RASTER. Una quarta copia')
    P('; mai letta non aiutava; unificare le altre tre e\' un lavoro a parte.')
    P('SKY_SRC_ROWS    EQU     %d             ; voci = righe raster visibili (1:1)' % RIGHE)
    P('')
    P('SkyGradient:')
    for i in range(0, RIGHE, 4):
        blocco = out[i:i + 4]
        celle = ','.join('$%04x,$%04x' % words(c) for c in blocco)
        nota = '  <-- orizzonte' if i <= RIGHE_ARTE - 1 < i + 4 else ''
        P('        dc.w    %-47s ; righe %3d..%3d%s'
          % (celle, i, i + len(blocco) - 1, nota))
    P('')
    P('; La tabella e\' 1:1 con le righe raster: SKY_SRC_ROWS DEVE valere quanto')
    P('; SKY_STEPS, altrimenti BuildSkyCopper torna a ricampionare per indice e')
    P('; le bande tornano IN SILENZIO. Se cambi CUT_BOTTOM_ROWS, rigenera questo')
    P('; file con il nuovo RIGHE. FAIL viene ignorata dall\'assemblatore, quindi')
    P('; si usa la divisione per zero: il messaggio e\' brutto ma il nome del')
    P('; simbolo dice cosa fare. SKY_STEPS e\' definita in Gioco.s, che include')
    P('; questo file piu\' sotto.')
    P('ERRORE_CIELOGRAD_DA_RIGENERARE  EQU     SKY_SRC_ROWS-SKY_STEPS')
    P('        IFNE    ERRORE_CIELOGRAD_DA_RIGENERARE')
    P('GUARDIA_CIELOGRAD       EQU     1/0')
    P('        ENDC')


if __name__ == '__main__':
    main()
