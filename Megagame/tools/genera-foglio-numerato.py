#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# genera-foglio-numerato.py - un foglio di tile dove OGNI slot grida il suo
#   numero. Serve come secondo foglio segnaposto, e come prova a costanti note
#   del caricamento: se a schermo compare l'arancione, in chip c'e' questo
#   foglio e non l'altro. Non c'e' modo di confondersi, che e' il punto.
#
# USO (dalla cartella Megagame):
#   python3 tools/genera-foglio-numerato.py                 -> grafica/Tiles2.raw
#   python3 tools/genera-foglio-numerato.py Tiles3.raw      un altro nome
#   python3 tools/genera-foglio-numerato.py --vuoti 0 64 92 questi slot vuoti
#
# QUANTE TILE: esattamente quelle del foglio di riferimento
# (mappa.FOGLIO_FILE). Non e' un numero scritto qui: si legge la LUNGHEZZA di
# quel file e si ricava la geometria, cosi' i due fogli restano intercambiabili
# per costruzione. Se il riferimento cambia forma, questo si adegua o si ferma.
#
# I COLORI NON SI INVENTANO (regola del progetto). L'arancione e il bianco si
# CERCANO nella palette vera del gioco, letta da GamePalHi/GamePalLo. Se in
# palette non c'e' niente di arancione lo script si FERMA invece di scegliere
# un colore che il gioco non ha: un foglio diagnostico col colore sbagliato non
# diagnostica niente.
#
# LE CIFRE non sono ridisegnate qui: sono quelle di genera-tile-segnaposto.py,
# importato come modulo. Una sola copia del disegno dei numeri.
#
# REGOLA 14: si scrive con `salva` di tools/grafica.py, che produce ANCHE
# l'.iff in risorse/grafica/. REGOLA 15: se il file esiste gia' viene messo da
# parte prima, non sovrascritto.
# ============================================================================
import colorsys, importlib.util, os, sys

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
segnaposto = _modulo('segnaposto', 'genera-tile-segnaposto.py')

RADICE = valori.RADICE
TILE = mappa.TILE
COLS = mappa.FOGLIO_COLS
PITCH = mappa.FOGLIO_PITCH
PIANI = mappa.PIANI

# Finestra di tonalita' che chiamiamo "arancione", in gradi. Il rosso puro (0)
# e il giallo puro (60) restano fuori di proposito: dentro la palette del gioco
# ci sono entrambi, e un rosso al posto dell'arancione renderebbe questo foglio
# indistinguibile dai mattoni.
TONO_MIN, TONO_MAX = 18.0, 48.0


def indice_arancione(pal):
    """L'indice di palette piu' arancione, con il suo punteggio.

    Punteggio = saturazione x luminosita', fra le sole voci la cui tonalita'
    cade nella finestra. Non si guarda la distanza da un arancione campione:
    un campione sarebbe un colore ricopiato, cioe' esattamente quello che la
    regola vieta. Si guarda solo QUANTO e' acceso un colore che e' GIA'
    arancione per tonalita'."""
    candidati = []
    for i, (r, g, b) in enumerate(pal):
        h, s, v = colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0)
        gradi = h * 360.0
        if TONO_MIN <= gradi <= TONO_MAX:
            candidati.append((s * v, i, gradi, s, v))
    if not candidati:
        raise SystemExit("nella palette del gioco non c'e' nessun colore con "
                         "tonalita' fra %g e %g gradi: niente arancione, e non "
                         "ne invento uno." % (TONO_MIN, TONO_MAX))
    candidati.sort(reverse=True)
    return candidati[0]


def geometria_dal_riferimento():
    """(slot, righe) ricavati dalla LUNGHEZZA del foglio di riferimento."""
    rif = os.path.join(RADICE, 'grafica', mappa.FOGLIO_FILE)
    if not os.path.isfile(rif):
        raise SystemExit('manca il foglio di riferimento %s'
                         % os.path.relpath(rif, RADICE))
    n = os.path.getsize(rif)
    if n % (PITCH * PIANI):
        raise SystemExit('%s e\' %d byte: non e\' un multiplo di %d '
                         '(passo %d x %d piani). Geometria diversa da quella '
                         'che DisegnaSfondo si aspetta.'
                         % (mappa.FOGLIO_FILE, n, PITCH * PIANI, PITCH, PIANI))
    righe = n // (PITCH * PIANI)
    if righe % TILE:
        raise SystemExit('%s ha %d righe, non multiplo di %d'
                         % (mappa.FOGLIO_FILE, righe, TILE))
    return COLS * (righe // TILE), righe


def main():
    arg = sys.argv[1:]
    vuoti = set()
    if '--vuoti' in arg:
        k = arg.index('--vuoti')
        vuoti = {int(a) for a in arg[k + 1:] if a.lstrip('-').isdigit()}
        arg = arg[:k]
    nome = next((a for a in arg if a.endswith('.raw')), 'Tiles2.raw')

    slot, righe = geometria_dal_riferimento()
    if righe != mappa.FOGLIO_RIGHE:
        raise SystemExit('il riferimento ha %d righe, mappa.FOGLIO_RIGHE dice '
                         '%d: non monto il foglio con due geometrie diverse.'
                         % (righe, mappa.FOGLIO_RIGHE))
    tab = valori.leggi()
    pal = mappa.palette_gioco(tab)
    _, bianco = segnaposto.indici_colore(pal)
    punteggio, arancio, gradi, sat, lum = indice_arancione(pal)
    print('riferimento %s: %d slot, %d righe, %d colonne'
          % (mappa.FOGLIO_FILE, slot, righe, COLS))
    print('arancione = indice %d rgb%s (tono %.0f gradi, sat %.2f, lum %.2f)'
          % (arancio, pal[arancio], gradi, sat, lum))
    print('bianco    = indice %d rgb%s' % (bianco, pal[bianco]))
    if arancio >= 1 << PIANI:
        raise SystemExit('l\'indice %d non entra in %d piani: il foglio '
                         'arriva a %d' % (arancio, PIANI, (1 << PIANI) - 1))

    tile = []
    for n in range(slot):
        if n in vuoti:
            tile.append([[0] * TILE for _ in range(TILE)])
        else:
            tile.append(segnaposto.disegna(n, arancio, bianco))
    if vuoti:
        print('lasciati vuoti: %s' % ', '.join(map(str, sorted(vuoti))))

    path = os.path.join(RADICE, 'grafica', nome)
    vecchio = copie.metti_da_parte(path, sposta=True, numera=True)
    if vecchio:
        print('il %s di prima e\' in %s' % (nome, os.path.relpath(vecchio, RADICE)))

    n_raw, n_iff, p_iff = grafica.salva(
        path, segnaposto.celle_dal_foglio(tile), COLS * TILE, righe, PIANI, pal)
    print('scritti: grafica/%s (%d byte) e %s (%d byte)'
          % (nome, n_raw, os.path.relpath(p_iff, RADICE), n_iff))
    atteso = os.path.getsize(os.path.join(RADICE, 'grafica', mappa.FOGLIO_FILE))
    if n_raw != atteso:
        raise SystemExit('ERRORE: %d byte invece dei %d di %s. I due fogli '
                         'DEVONO essere interscambiabili.'
                         % (n_raw, atteso, mappa.FOGLIO_FILE))
    print('stessa lunghezza di %s: i due fogli sono interscambiabili.'
          % mappa.FOGLIO_FILE)
    return 0


if __name__ == '__main__':
    sys.exit(main())
