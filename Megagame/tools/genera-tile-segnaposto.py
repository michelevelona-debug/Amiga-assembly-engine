#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-tile-segnaposto.py - riempie gli slot VUOTI del foglio delle tile con
#   un quadrato leggibile, cosi' il livello si puo' scrivere prima dell'arte.
#
# USO (dalla cartella Megagame):
#   python3 tools/genera-tile-segnaposto.py            quelle che usa la mappa
#   python3 tools/genera-tile-segnaposto.py 43 44 45   solo queste
#   python3 tools/genera-tile-segnaposto.py --anche-marcatori
#   python3 tools/genera-tile-segnaposto.py --togli 43 44
#
# COSA DISEGNA: fondo verde, cornice bianca, il numero della tile in bianco.
# Il numero e' la cosa importante: guardando l'anteprima della mappa si legge
# QUALE tile manca e dove, senza contare le colonne.
#
# PERCHE' ESISTE. Con la mappa scritta a numeri si puo' piazzare una tile che
# non esiste ancora, ed e' il motivo per cui la mappa e' un file di testo. Ma
# fino a qui quelle caselle erano buchi: il gioco ci mostrava il cielo e
# l'anteprima un quadrato magenta. Con un segnaposto disegnato DAVVERO dentro
# Tiles.raw il livello si puo' provare sull'Amiga con la sua geometria giusta,
# e l'arte vera arriva dopo, uno slot alla volta.
#
# I COLORI NON SI RICOPIANO: si leggono dai blocchi GamePalHi/GamePalLo di
# Gioco.s e si cerca li' dentro il bianco e il verde piu' acceso. Se domani la
# palette cambia, cambiano anche i segnaposto, e restano quelli del gioco.
#
# COSA NON TOCCA: gli slot che hanno gia' un disegno, mai. E per difetto
# nemmeno i MARCATORI, cioe' le tile dichiarate da una EQU TILE_* (TILE_LUCE,
# TILE_VIA): quelle devono restare INVISIBILI nel gioco finito, perche'
# marcano un punto e non disegnano niente. `--anche-marcatori` le include lo
# stesso, che durante lo sviluppo e' comodo: si vede dove sono. Ricordarsi di
# toglierle con `--togli` prima di considerare finita la grafica.
#
# REGOLA 15: il Tiles.raw di prima viene messo da parte, mai sovrascritto e
# basta. REGOLA 14: si scrive con `salva` di tools/grafica.py, che produce
# ANCHE l'.iff in risorse/grafica/ - che per Tiles.raw non era mai esistito.
# ============================================================================
import importlib.util, os, sys

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)
import copie
import valori


def _modulo(nome, file):
    sp = importlib.util.spec_from_file_location(nome, os.path.join(QUI, file))
    mo = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(mo)
    return mo


mappa = _modulo('mappa', 'mappa.py')
grafica = _modulo('grafica', 'grafica.py')

RADICE = valori.RADICE
TILES = os.path.join(RADICE, 'grafica', 'Tiles.raw')
TILE = mappa.TILE
COLS = mappa.FOGLIO_COLS
PITCH = mappa.FOGLIO_PITCH
RIGHE = mappa.FOGLIO_RIGHE
PIANI = mappa.PIANI

# Cifre 3x5. Piccole apposta: due ci stanno comode dentro 16 px con la cornice,
# tre pure. Piu' grandi non servono, il numero si legge a 3x di zoom.
CIFRE = {
    '0': ('111', '101', '101', '101', '111'),
    '1': ('010', '110', '010', '010', '111'),
    '2': ('111', '001', '111', '100', '111'),
    '3': ('111', '001', '111', '001', '111'),
    '4': ('101', '101', '111', '001', '001'),
    '5': ('111', '100', '111', '001', '111'),
    '6': ('111', '100', '111', '101', '111'),
    '7': ('111', '001', '001', '001', '001'),
    '8': ('111', '101', '111', '101', '111'),
    '9': ('111', '101', '111', '001', '111'),
}


def indici_colore(pal):
    """(verde, bianco) come INDICI di palette, cercati nella palette vera.
    Non si scrivono a mano: se cambia la palette cambiano loro."""
    bianco = max(range(len(pal)), key=lambda i: sum(pal[i]))
    verde = max(range(len(pal)),
                key=lambda i: pal[i][1] - max(pal[i][0], pal[i][2]))
    return verde, bianco


def disegna(n, verde, bianco):
    """Una cella 16x16 di indici: fondo verde, cornice e numero bianchi."""
    c = [[verde] * TILE for _ in range(TILE)]
    for k in range(TILE):
        c[0][k] = c[TILE - 1][k] = bianco
        c[k][0] = c[k][TILE - 1] = bianco
    testo = str(n)
    larg = len(testo) * 4 - 1
    x0 = (TILE - larg) // 2
    y0 = (TILE - 5) // 2
    for k, ch in enumerate(testo):
        g = CIFRE.get(ch)
        if not g:
            continue
        for y in range(5):
            for x in range(3):
                if g[y][x] == '1':
                    c[y0 + y][x0 + k * 4 + x] = bianco
    return c


def celle_dal_foglio(tile):
    """Il foglio intero come matrice RIGHE x 320 di indici, pronta per salva()."""
    largh = COLS * TILE
    out = [[0] * largh for _ in range(RIGHE)]
    for n, cella in enumerate(tile):
        tr, tc = divmod(n, COLS)
        for y in range(TILE):
            riga = out[tr * TILE + y]
            for x in range(TILE):
                riga[tc * TILE + x] = cella[y][x]
    return out


def main():
    arg = sys.argv[1:]
    anche_marc = '--anche-marcatori' in arg
    togli = '--togli' in arg
    numeri = [int(a) for a in arg if a.isdigit()]

    tab = valori.leggi()
    pal = mappa.palette_gioco(tab)
    tile = mappa.foglio_tile()
    segni = mappa.segnaposto(tab)
    verde, bianco = indici_colore(pal)
    vuoti = {n for n in range(len(tile))
             if all(v == 0 for r in tile[n] for v in r) and n != 0}
    print('palette: verde = indice %d rgb%s, bianco = indice %d rgb%s'
          % (verde, pal[verde], bianco, pal[bianco]))

    if numeri:
        voluti = numeri
    else:
        if not os.path.exists(mappa.TXT):
            raise SystemExit('manca %s: passa i numeri a mano'
                             % os.path.relpath(mappa.TXT, RADICE))
        righe, errori = mappa.leggi_txt(mappa.TXT, segni)
        if errori:
            print('il .txt ha %d problemi, li elenca tools/mappa.py' % len(errori))
        usate = {v for fila in righe for v in fila}
        voluti = sorted(usate & vuoti)
        print('dalla mappa: %d tile usate senza disegno' % len(voluti))

    if not togli and not anche_marc:
        marc = [n for n in voluti if n in segni]
        if marc:
            print('  salto i marcatori %s: devono restare invisibili nel gioco.'
                  % ', '.join('%d (%s)' % (n, segni[n]) for n in marc))
            print('  --anche-marcatori se li vuoi visibili mentre costruisci.')
        voluti = [n for n in voluti if n not in segni]

    pieni = [n for n in voluti if n not in vuoti]
    if pieni and not togli:
        raise SystemExit('NON TOCCO uno slot gia\' disegnato: %s'
                         % ', '.join(map(str, pieni)))
    if not voluti:
        print('niente da fare.')
        return 0

    for n in voluti:
        tile[n] = ([[0] * TILE for _ in range(TILE)] if togli
                   else disegna(n, verde, bianco))
    print('%s: %s' % ('SVUOTO' if togli else 'disegno',
                      ', '.join(map(str, voluti))))

    # regola 15. Dove va la copia la decide copie.py, non qui.
    vecchio = copie.metti_da_parte(TILES, sposta=True, numera=True)
    if vecchio:
        print('vecchio foglio messo da parte come %s'
              % os.path.relpath(vecchio, RADICE))

    n_raw, n_iff, p_iff = grafica.salva(
        TILES, celle_dal_foglio(tile), COLS * TILE, RIGHE, PIANI, pal)
    print('scritti: grafica/Tiles.raw (%d byte) e %s (%d byte)'
          % (n_raw, os.path.relpath(p_iff, RADICE), n_iff))
    print('adesso rilancia  py tools\\mappa.py  per rifare l\'anteprima.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
