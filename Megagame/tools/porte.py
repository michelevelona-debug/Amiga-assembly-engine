#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# porte.py - le porte fra due mappe REGGONO o buttano il player nel vuoto?
#
# USO (dalla cartella Megagame):
#   py tools\porte.py            controlla tutti i collegamenti di MappaLink
#   py tools\porte.py 1 2        solo la porta fra la mappa 1 e la 2
#
# PERCHE' ESISTE. Il 29 settembre 2026 il passaggio fra due mappe "non
# funzionava": si usciva dal bordo destro e non si arrivava dall'altra parte. Il
# codice era giusto. Il difetto stava nella GEOGRAFIA, e nessuno lo poteva
# vedere perche' le due mappe erano copie identiche: le UNICHE due quote da cui
# si puo' raggiungere il bordo destro camminando erano le righe 16 e 21, e a
# quelle quote il bordo sinistro NON HA PAVIMENTO - il player arrivava in aria e
# cadeva nell'angolo in basso.
#
# Questo e' il tipo di difetto che non si trova rileggendo l'assembly, perche'
# nell'assembly non c'e'. Si trova misurando le due sagome, ed e' un conto che
# si rifa' a ogni modifica di mappa.
#
# LE REGOLE CHE APPLICA, e vengono dal sorgente e non da qui:
#   - il box del player e' BOB_COLL_W x BOB_COLL_H (32x32 = 2x2 tile), ancorato
#     all'angolo alto-sinistra;
#   - per RAGGIUNGERE un bordo camminando serve il box libero E un solido
#     sotto: senza appoggio non ci si arriva, ci si passa cadendo;
#   - per ARRIVARE serve il box libero. Se sotto non c'e' solido non e' un
#     errore - si cade, ed e' voluto quando si arriva in salto - ma se la
#     caduta non incontra niente fino in fondo il passaggio non ha senso.
#   - la quota d'arrivo puo' essere spostata da CercaYLibera a passi di 16 px:
#     qui si riporta anche quella, perche' un arrivo "valido ma spostato di
#     cinque tile" a schermo si legge come un teletrasporto.
#
# Il solido/vuoto lo decide TileFlags in Gioco.s, letta da tools/mappa.py: qui
# non c'e' una seconda copia di quella tabella.
# ============================================================================
import os
import re
import struct
import sys

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valori
import mappa as mappamod


def nome_mappa(n):
    return 'mappa%d' % n


def leggi_raw(n, cols, righe):
    p = os.path.join(RADICE, 'grafica', nome_mappa(n) + '.raw')
    if not os.path.isfile(p):
        raise SystemExit('manca %s: lancia py tools\\mappa.py --mappa %d'
                         % (os.path.relpath(p, RADICE), n))
    d = open(p, 'rb').read()
    atteso = cols * righe * 2
    if len(d) != atteso:
        raise SystemExit('%s e\' %d byte, ne servono %d (%dx%d word)'
                         % (os.path.basename(p), len(d), atteso, cols, righe))
    v = struct.unpack('>%dH' % (cols * righe), d)
    return [list(v[r * cols:(r + 1) * cols]) for r in range(righe)]


def legami(tab):
    """I collegamenti, dalla FONTE: risorse/mappe.txt. Per ogni blocco i versi
    nell'ordine delle EQU VERSO_* (nome oppure `-`), piu' i nomi dei blocchi
    nell'ordine in cui sono dichiarati - che e' l'ordine degli indici.

    Si legge la fonte e non Mappe.i: quello e' un prodotto, e leggere un
    prodotto vuol dire non accorgersi che non e' stato rigenerato. La stessa
    ragione per cui questo strumento legge TileFlags da Gioco.s invece di
    tenersene una copia.
    """
    import mappe as mappemod
    versi = mappemod.ordine_versi()
    blocchi = mappemod.leggi_fonte()
    guai = mappemod.controlla(blocchi, versi,
                              tab['MAPPA_COLS'], tab['MAPPA_ROWS'])
    if guai:
        print('la griglia non e\' coerente: py tools\\mappe.py lo dice in '
              'dettaglio. Qui mi fermo, perche' + "'" + ' controllare la '
              'geografia di collegamenti sbagliati non vuol dire niente.')
        for g in guai:
            print('  - ' + g)
        raise SystemExit(1)
    nomi = [b[0] for b in blocchi]
    return versi, nomi, [dict(zip(versi, b[1])) for b in blocchi]


def analizza(nome, griglia, flags, cols, righe, boxc, boxr):
    def solido(c, r):
        if not (0 <= c < cols and 0 <= r < righe):
            return False
        t = griglia[r][c]
        return t < len(flags) and flags[t] != 0

    def libero(c, r):
        return not any(solido(c + dc, r + dr)
                       for dc in range(boxc) for dr in range(boxr))

    def appoggio(c, r):
        return any(solido(c + dc, r + boxr) for dc in range(boxc))
    return solido, libero, appoggio



def _gruppi(v):
    """[1,2,3,7,8] -> "1..3, 7..8": settantatre numeri in fila non si leggono."""
    if not v:
        return 'nessuna'
    fuori, a, b = [], v[0], v[0]
    for x in v[1:]:
        if x == b + 1:
            b = x
        else:
            fuori.append((a, b)); a = b = x
    fuori.append((a, b))
    return ', '.join('%d' % x if x == y else '%d..%d' % (x, y) for x, y in fuori)


def orizzontale(da, a, verso, lib_da, app_da, lib_a, app_a, cols, righe,
                boxc, boxr):
    """Bordi SINISTRO e DESTRO: ci si arriva CAMMINANDO, quindi serve il box
    libero E un solido sotto. All'arrivo si conserva la quota e CercaYLibera la
    sposta in verticale se e' occupata."""
    col_da = cols - boxc if verso == 'destra' else 0
    col_a = 0 if verso == 'destra' else cols - boxc
    print('\n=== mappa %d, bordo %s -> mappa %d, colonna %d ==='
          % (da, verso, a, col_a))
    guai = 0
    partenze = [r for r in range(righe - boxr + 1)
                if lib_da(col_da, r) and app_da(col_da, r)]
    if not partenze:
        print('  NESSUNA quota da cui si possa raggiungere quel bordo '
              'camminando: il box non e\' mai libero con un solido sotto.')
        return 1
    print('  quote da cui si esce camminando (riga di tile): %s'
          % _gruppi(partenze))
    for r in partenze:
        dove = _cerca(r, righe - boxr, lambda q: lib_a(col_a, q))
        if dove is None:
            print('  riga %2d -> NESSUNA quota libera: il passaggio si ANNULLA' % r)
            guai += 1
            continue
        spost = '' if dove == r else ' (spostato a %d da CercaYLibera)' % dove
        if app_a(col_a, dove):
            print('  riga %2d -> arriva a %2d e ATTERRA%s' % (r, dove, spost))
        else:
            cad = dove
            while cad <= righe - boxr and not app_a(col_a, cad):
                cad += 1
            if cad > righe - boxr:
                print('  riga %2d -> arriva a %2d%s e CADE NEL VUOTO fino in '
                      'fondo: niente pavimento sulle colonne %d..%d'
                      % (r, dove, spost, col_a, col_a + boxc - 1))
                guai += 1
            else:
                print('  riga %2d -> arriva a %2d%s, cade e atterra a %d'
                      % (r, dove, spost, cad))
    return guai


def verticale(da, a, verso, lib_da, app_da, lib_a, app_a, cols, righe,
              boxc, boxr):
    """Bordi ALTO e BASSO, e la domanda NON e' la stessa dell'orizzontale.

    In basso non ci si arriva camminando: ci si CADE, e il motore scatta
    sull'unico quadro in cui il player e' a PLAYER_MAX_Y con la velocita' ancora
    verso il basso. Quindi non serve un appoggio, serve che il box sia libero
    sulle righe di fondo - cioe' che il pavimento LI' NON CI SIA.

    In alto ci si arriva solo saltando, e **se il salto arrivi fino a la' questo
    strumento non lo dimostra**: guarda la condizione necessaria (box libero
    sulla riga 0) e non la raggiungibilita'. Il limite e' dichiarato perche' un
    verdetto "regge" su un bordo alto irraggiungibile sarebbe peggio di nessun
    verdetto.
    """
    riga_da = righe - boxr if verso == 'sotto' else 0
    riga_a = 0 if verso == 'sotto' else righe - boxr
    print('\n=== mappa %d, bordo %s -> mappa %d, riga %d ==='
          % (da, verso, a, riga_a))
    guai = 0
    partenze = [c for c in range(cols - boxc + 1) if lib_da(c, riga_da)]
    if not partenze:
        print('  NESSUNA colonna con il box libero sulla riga %d: quel bordo e\' '
              'chiuso da un muro continuo, e la porta non si aprira\' mai.'
              % riga_da)
        return 1
    if verso == 'sotto':
        print('  colonne da cui si CADE fuori (riga %d libera): %s'
              % (riga_da, _gruppi(partenze)))
    else:
        print('  colonne con il box libero sulla riga 0, cioe\' da cui si PUO\' '
              'uscire saltando abbastanza alto: %s' % _gruppi(partenze))
    # l'arrivo: si conserva la colonna, CercaXLibera la sposta se serve
    spostati, annullati, atterra, cadono = [], [], [], []
    for c in partenze:
        dove = _cerca(c, cols - boxc, lambda q: lib_a(q, riga_a))
        if dove is None:
            annullati.append(c)
            continue
        if dove != c:
            spostati.append((c, dove))
        if verso == 'sotto':
            # entra dall'alto e continua a cadere: dove atterra?
            q = riga_a
            while q <= righe - boxr and not app_a(dove, q):
                q += 1
            (atterra if q <= righe - boxr else cadono).append(c)
        else:
            atterra.append(c)      # entra dal basso salendo: non deve atterrare
    if annullati:
        print('  ANNULLATE, nessuna colonna libera all\'arrivo: %s'
              % _gruppi(annullati))
        guai += 1
    if spostati:
        peggio = max(abs(x - y) for x, y in spostati)
        print('  spostate di lato da CercaXLibera: %d colonne, al massimo di %d '
              'tile%s' % (len(spostati), peggio,
                          ' - oltre due tile a schermo si legge come un '
                          'teletrasporto' if peggio > 2 else ''))
        if peggio > 2:
            guai += 1
    if verso == 'sotto' and cadono:
        print('  CADONO FINO IN FONDO senza incontrare pavimento: %s'
              % _gruppi(cadono))
        guai += 1
    if not guai:
        print('  tutte le colonne di quel bordo arrivano in una casella libera.')
    return guai


def _cerca(voluto, massimo, libero):
    """CercaYLibera / CercaXLibera in Python: la voluta, poi a passi di una tile
    alternando prima e dopo, e a pari distanza vince quella prima."""
    for d in range(0, massimo + 1):
        for cand in ((voluto - d,) if d == 0 else (voluto - d, voluto + d)):
            if 0 <= cand <= massimo and libero(cand):
                return cand
    return None


def main():
    tab = valori.leggi()
    cols, righe = tab['MAPPA_COLS'], tab['MAPPA_ROWS']
    # Il box in TILE: si deriva dalle EQU, non si scrive 2.
    boxc = tab['BOB_COLL_W'] // 16
    boxr = tab['BOB_COLL_H'] // 16
    flags = mappamod.leggi_tileflags()
    versi, nomi, link = legami(tab)
    print('mappe %dx%d tile, box del player %dx%d tile, TileFlags %d voci'
          % (cols, righe, boxc, boxr, len(flags)))
    print('colonne di bordo: sinistra 0..%d, destra %d..%d'
          % (boxc - 1, cols - boxc, cols - 1))

    coppie = []
    for i, d in enumerate(link):
        for v in versi:
            if d[v] != '-':
                coppie.append((i + 1, nomi.index(d[v]) + 1, v))
    if not coppie:
        print('\nnessun collegamento in MappaLink.')
        return 0

    guai = 0
    ORIZZ = ('sinistra', 'destra')
    for da, a, verso in coppie:
        gda = leggi_raw(da, cols, righe)
        ga = leggi_raw(a, cols, righe)
        _, lib_da, app_da = analizza('', gda, flags, cols, righe, boxc, boxr)
        _, lib_a, app_a = analizza('', ga, flags, cols, righe, boxc, boxr)
        if verso in ORIZZ:
            guai += orizzontale(da, a, verso, lib_da, app_da, lib_a, app_a,
                                cols, righe, boxc, boxr)
        else:
            guai += verticale(da, a, verso, lib_da, app_da, lib_a, app_a,
                              cols, righe, boxc, boxr)
    print()
    if guai:
        print('%d PORTE DA SISTEMARE. Il rimedio sta nel .txt, non nel codice: '
              'le colonne di bordo della mappa di arrivo devono accogliere il '
              'player alle quote da cui si esce.' % guai)
        return 1
    print('tutte le porte reggono.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
