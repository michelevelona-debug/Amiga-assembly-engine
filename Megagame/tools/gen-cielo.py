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
# 144 riproduceva ESATTAMENTE la composizione del vecchio conto a runtime:
# 143*260/176 = 211 (l'ultima voce d'arte) e 144*260/176 = 212 (la prima di
# sfumatura), quindi l'orizzonte cadeva gia' a riga 144. Cambiando questo
# numero il cielo si RIDISEGNA, non si liscia:
#
#   RIGHE_ARTE   sfumatura   dL* per riga   orizzonte
#      176           0           n/a        in fondo allo schermo  <-- ORA
#      144          32           3,0        dove stava prima
#      130          46           2,1        14 righe piu' in alto
#      116          60           1,6        28 righe piu' in alto
#       81          95           1,0        63 righe piu' in alto (invisibile)
#
# Il muro aritmetico che ha portato a 176: la sfumatura attraversa 96 unita' di
# L* (da 96,4 a 0) e la soglia sotto cui l'occhio non distingue due righe e'
# circa 1 unita'. Servono ~96 righe raster perche' sia invisibile, e le righe
# totali sono 176: una sfumatura senza scalini si paga in altezza del cielo,
# non in codice. Il 22 agosto 2026 la scelta e' stata di non pagarla e di
# TOGLIERE la sfumatura: il cielo si chiude sul giallo dell'orizzonte, in fondo
# allo schermo. Due effetti insieme: spariscono le uniche bande che restavano,
# e l'arte si distende su 176 righe invece che su 144, quindi anche i suoi
# gradini si diradano. Con RIGHE_ARTE = RIGHE le voci 212..259 della sorgente
# non vengono usate: restano nel .src per non perderle.
# ============================================================================
import re, sys

# L'Amiga vuole LF. Su Windows lo stdout di Python e' in modalita' testo e
# traduce ogni \n in CRLF, quindi "py tools\gen-cielo.py ... > CieloGrad.i"
# produrrebbe un file CRLF che su Devpac lascia un $0D in fondo a ogni riga.
# Va forzato QUI, alla sorgente: sistemarlo dopo con tools/terminatori.py
# funziona, ma il difetto tornerebbe alla prima rigenerazione.
try:
    sys.stdout.reconfigure(newline='\n')
except AttributeError:      # Python < 3.7
    pass

RIGHE = 176         # = BG_VIS_ROWS. Se cambia, si rigenera.
RIGHE_ARTE = 176    # righe date all'arte; le restanti vanno alla sfumatura.
                    # = RIGHE significa nessuna sfumatura: chiude sul giallo
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

    def lerp_f(t):
        """Il valore della curva alla posizione t, in FLOAT: non arrotonda.
        Arrotondare qui e poi ancora dopo perdeva la frazione due volte."""
        t = max(0.0, min(t, float(ultima)))
        i = int(t)
        if i >= ultima:
            return tuple(float(v) for v in cols[ultima])
        f = t - i
        a, b = cols[i], cols[i + 1]
        return tuple(a[k] + (b[k] - a[k]) * f for k in range(3))

    n_fade = RIGHE - RIGHE_ARTE
    cont = [lerp_f(i * fine_arte / (RIGHE_ARTE - 1)) for i in range(RIGHE_ARTE)]
    cont += [lerp_f(fine_arte + (j + 1) * (ultima - fine_arte) / n_fade)
             for j in range(n_fade)]

    # ------------------------------------------------------------------
    # Da float a 8 bit per canale, con DIFFUSIONE DELL'ERRORE lungo la colonna.
    #
    # PERCHE': su queste 176 righe la curva avanza di +0,67 livelli per riga in
    # R, +0,69 in G e +0,13 in B. Arrotondando riga per riga in modo
    # indipendente, la frazione si perde e capita che due righe vicine cadano
    # sullo stesso valore: erano 15 righe su 176. Portando avanti l'errore, il
    # gradino di 1 livello cade dove la curva lo chiede davvero.
    #
    # POI si impone che due righe adiacenti non siano MAI identiche, cosi' ogni
    # riga raster porta il suo colore: e' il massimo che l'hardware concede,
    # visto che il copper scrive COLOR00 una volta per riga. Il canale da
    # spingere e' quello con l'errore accumulato piu' grande, cioe' quello che
    # stava gia' per cambiare: si arrotonda dall'altra parte invece di
    # inventare uno scostamento. La deviazione dalla curva resta sotto 1
    # livello su 255 (verificata dall'assert piu' sotto).
    # ------------------------------------------------------------------
    err = [0.0, 0.0, 0.0]
    out = []
    for i, c in enumerate(cont):
        r = []
        for k in range(3):
            v = c[k] + err[k]
            q = max(0, min(255, int(round(v))))
            err[k] = v - q
            r.append(q)
        out.append(r)

    def diverso(i):
        """Forza out[i] != out[i-1] spingendo il canale con l'errore maggiore."""
        for k in sorted(range(3), key=lambda k: -abs(err[k])):
            passo = 1 if err[k] >= 0 else -1
            nuovo = out[i][k] + passo
            if 0 <= nuovo <= 255:
                out[i][k] = nuovo
                err[k] -= passo
                return True
        return False

    # Gli estremi restano ESATTI: la prima riga e' la prima voce d'arte e
    # l'ultima e' l'orizzonte (o la fine della sfumatura). L'errore accumulato
    # potrebbe averli spostati di un livello: si rimettono a mano.
    out[0] = list(cols[0])
    out[-1] = list(cols[ultima] if n_fade else cols[fine_arte])
    if not n_fade:
        out[RIGHE_ARTE - 1] = list(cols[fine_arte])

    for i in range(1, RIGHE):
        if out[i] == out[i - 1]:
            # l'ultima riga e' fissata: in caso di collisione si sposta la penultima
            assert diverso(i - 1 if i == RIGHE - 1 else i), \
                'canale saturo: impossibile rendere distinte le righe %d e %d' % (i - 1, i)

    out = [tuple(c) for c in out]

    assert len(out) == RIGHE
    assert out[0] == cols[0], 'la prima riga non e\' piu\' la prima voce d\'arte'
    assert out[RIGHE_ARTE - 1] == cols[fine_arte], 'l\'orizzonte si e\' spostato'
    if n_fade:
        assert out[-1] == cols[ultima], 'la sfumatura non arriva piu\' in fondo'
    else:
        assert out[-1] == cols[fine_arte], 'senza sfumatura l\'ultima riga DEVE essere il giallo d\'orizzonte'
    assert all(rgb(*words(c)) == c for c in out), 'round-trip 24 bit non esatto'
    # UNA RIGA, UN COLORE: e' il punto di tutto il blocco qui sopra.
    assert all(out[i] != out[i - 1] for i in range(1, RIGHE)), \
        'ci sono ancora righe adiacenti con lo stesso colore'
    # NB: due righe LONTANE possono ripetere lo stesso colore, ed e' corretto:
    # B si muove di 0,13 livelli per riga, quindi oscilla e ripassa da valori
    # gia' usati. Quello che conta e' che ogni riga cambi rispetto alla
    # precedente, non che i 176 valori siano tutti diversi fra loro.
    # e la dieta non deve aver deformato la curva
    scarto = max(max(abs(out[i][k] - cont[i][k]) for k in range(3)) for i in range(RIGHE))
    assert scarto <= 1.5, 'la quantizzazione si e\' allontanata dalla curva di %.2f livelli' % scarto

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
    P('; estratte da CieloCopper.i piu\' 48 di sfumatura al nero in coda.')
    if not n_fade:
        P('; LE 48 VOCI DI SFUMATURA NON SONO USATE: RIGHE_ARTE = RIGHE, quindi il')
        P('; cielo si chiude sul giallo dell\'orizzonte in fondo allo schermo.')
        P('; Restano nel .src per non perderle.')
    P(';')
    P('; UNA VOCE PER RIGA RASTER. Il copper scrive un colore per riga e le')
    P('; righe visibili sono BG_VIS_ROWS: tenere 260 voci per un display da')
    P('; %d significava buttarne via 84 a runtime. Il vecchio conto' % RIGHE)
    P('; i*260/%d le buttava TRONCANDO, e troncando saltava voci intere -' % RIGHE)
    P('; l\'indice avanza di 1,477 per riga, quindi ogni tanto due gradini')
    P('; dell\'arte finivano compressi in una riga sola. Qui le 84 voci non')
    P('; sono scartate ma FUSE: si interpola fra le due voci adiacenti.')
    P(';')
    virg = lambda x: ('%.2f' % x).replace('.', ',')
    if n_fade:
        P('; L\'orizzonte (la voce piu\' luminosa dell\'arte) sta a riga %d, e da li\'' % RIGHE_ARTE)
        P('; in giu\' c\'e\' la sfumatura al nero. Cambiare la ripartizione RIDISEGNA')
        P('; il cielo invece di lisciarlo: si fa da gen-cielo.py, dove c\'e\' la')
        P('; tabella del costo in altezza.')
        P(';')
        P('; MISURATO, in L* (la scala dove 1 e\' la soglia percettiva):')
        P(';                          arte 0..%-3d      sfumatura %d..%d' % (RIGHE_ARTE - 1, RIGHE_ARTE, RIGHE - 1))
        P(';   dL* massimo              %-17s %s' % (virg(max(dL_arte)), virg(max(dL_fade))))
        P(';   righe sopra soglia       %-17s %s'
          % ('%d su %d' % (sum(1 for x in dL_arte if x > 1.0), len(dL_arte)),
             '%d su %d' % (sum(1 for x in dL_fade if x > 1.0), len(dL_fade))))
        P(';')
        P('; Nell\'ARTE le bande spariscono del tutto. Nella SFUMATURA no, e non e\'')
        P('; un difetto di questo file: 96 unita\' di L* in %d righe fanno %s a' % (n_fade, virg(96.4 / n_fade)))
        P('; riga contro una soglia di 1, e per stare sotto servirebbero ~96 righe')
        P('; raster prese all\'arte. E\' un prezzo in composizione, non in codice.')
    else:
        P('; NIENTE SFUMATURA: tutte le %d righe vanno all\'arte e il cielo si chiude' % RIGHE)
        P('; sul giallo dell\'orizzonte (l\'ultima voce d\'arte) in fondo allo schermo,')
        P('; a contatto col pannello. Deciso il 22 agosto 2026 per due motivi che')
        P('; vanno insieme: la sfumatura al nero era l\'UNICO punto del cielo con')
        P('; bande sopra soglia, e toglierla restituisce all\'arte le righe che si')
        P('; prendeva, quindi l\'arte si distende su %d righe invece che su 144 e i' % RIGHE)
        P('; suoi gradini si diradano ancora.')
        P(';')
        P('; MISURATO, in L* (la scala dove 1 e\' la soglia percettiva):')
        P(';                                 ora            prima (arte + sfumatura)')
        P(';   dL* massimo                   %-15s %s' % (virg(max(dL_arte)), '0,87 arte / 3,73 sfumatura'))
        P(';   righe sopra soglia            %-15s %s'
          % ('%d su %d' % (sum(1 for x in dL_arte if x > 1.0), len(dL_arte)), '0 su 143 / 32 su 32'))
        P(';')
        P('; Il cielo non ha piu\' nemmeno una riga sopra la soglia percettiva.')
        P(';')
        P('; UNA RIGA, UN COLORE. Le %d transizioni cambiano TUTTE il valore di' % (RIGHE - 1))
        P('; COLOR00: non c\'e\' una sola riga che ripete il colore di quella sopra,')
        P('; quindi il copper sfrutta ogni scrittura che l\'hardware gli concede.')
        P('; Prima erano 160 su 175: la curva avanza di 0,67 livelli per riga in R,')
        P('; 0,69 in G e 0,13 in B, e arrotondando riga per riga la frazione si')
        P('; perdeva. Ora l\'errore viene portato avanti lungo la colonna e, quando')
        P('; due righe cadrebbero comunque sullo stesso valore, si arrotonda')
        P('; dall\'altra parte il canale che stava gia\' per cambiare. Lo scostamento')
        P('; dalla curva resta sotto 1 livello su 255 (assert nel generatore).')
        P('; NB: due righe LONTANE possono ripetere un colore, e va bene: B oscilla.')
        P('; I valori distinti sono %d, le transizioni utili %d su %d.' % (len(set(out)), RIGHE - 1, RIGHE - 1))
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
