#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# mappa-budget.py - quanto costa un pezzo di mappa in chip RAM.
#
# USO (dalla cartella Megagame):
#     python3 tools/mappa-budget.py                  la legge e le tabelle
#     python3 tools/mappa-budget.py --zona 31 70     una zona 31 colonne x 70 righe
#     python3 tools/mappa-budget.py --circolare 13   buffer circolare da 13 righe
#     python3 tools/mappa-budget.py --riserva 256    KB da tenere liberi
#     python3 tools/mappa-budget.py --ignoti 150     KB dei file non misurabili qui
#
# PERCHE' ESISTE
# In Path B il world buffer contiene TUTTA la zona di gioco, quindi la sua
# dimensione non e' una scelta di gusto ma di byte. Prima di disegnare un
# livello serve il prezzo, e serve espresso nell'unita' in cui si pensa un
# livello: la tile e la schermata.
#
# LA LEGGE, che e' una moltiplicazione sola:
#   16 piani scalano con l'altezza (3 buffer del mondo x 5 piani + il darkplane)
#   una tile e' 16 righe x 2 byte per piano
#   -> 16 x 16 x 2 = 512 BYTE DI CHIP PER OGNI TILE DI MAPPA
# Una schermata e' 20x11 tile, quindi 110 KB. Vale finche' la larghezza della
# mappa comanda il pitch; sotto le 31 colonne il pitch ha un pavimento
# (SFONDO_ROW_FETCH) e si paga comunque per 31.
#
# COSA NON HA DENTRO: costanti ricopiate. Le EQU le legge con tools/valori.py
# (rami condizionali valutati), e quali buffer scalano lo SCOPRE cercando
# SFONDO_PLANE_SIZE nelle ds.b delle sezioni chip.
#
# LIMITE DICHIARATO: alcuni incbin non sono in ogni copia di lavoro
# (title.raw, il modulo, i campioni). Non si stimano: entrano come un unico
# numero passato con --ignoti, da misurare sul disco vero.
# ============================================================================
import os, re, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valori

CHIP_TOT = 2 * 1024 * 1024

# La stanza dell'originale C64, MISURATA sullo screenshot: area di gioco
# 289x129 px con tile da 16, cioe' 18x8 tile. La NOSTRA schermata invece e'
# BG_VIS_ROWS/16 = 11 righe, non 8: sono due unita' diverse e vanno sempre
# dette tutte e due.
STANZA_C, STANZA_R = 18, 8


def inventario(tab):
    """(scalanti, fissi, mancanti) in byte. Scalante = il suo ds.b nomina
    SFONDO_PLANE_SIZE, cioe' cresce con l'altezza della mappa."""
    righe = valori._espandi(valori.SORGENTE)
    sez = None
    etichetta = '?'
    scalanti, fissi, mancanti = [], [], []
    for l in righe:
        c = l.split(';')[0].rstrip()
        m = re.match(r'^\s*section\s+(\w+)\s*,\s*(\w+)', c, re.I)
        if m:
            sez = m.group(2).upper()
            continue
        m = re.match(r'^([A-Za-z_]\w*):', c)
        if m:
            etichetta = m.group(1)
        m = re.search(r'\bds\.([bwl])\s+(.+)$', c, re.I)
        if m and sez in ('BSS_C', 'DATA_C'):
            larg = {'b': 1, 'w': 2, 'l': 4}[m.group(1).lower()]
            espr = m.group(2).strip()
            try:
                n = valori._numero(espr, tab) * larg
            except Exception:
                mancanti.append(etichetta)
                continue
            if 'SFONDO_PLANE_SIZE' in espr:
                scalanti.append((etichetta, n, n // tab['SFONDO_PLANE_SIZE']))
            else:
                fissi.append((etichetta, n))
        m = re.match(r'^\s*incbin\s+"([^"]+)"', c, re.I)
        if m and sez in ('BSS_C', 'DATA_C'):
            p = os.path.join(valori.RADICE, m.group(1))
            if os.path.exists(p):
                fissi.append((m.group(1), os.path.getsize(p)))
            else:
                mancanti.append(m.group(1))
    return scalanti, fissi, mancanti


def pitch_per_colonne(tab, cols):
    """La stessa catena di Gioco.s (righe 359-360 e 486-494), colonne a piacere.

    QUI C'ERA UN ERRORE, ed e' costato una scelta di progetto presa sul numero
    sbagliato: `SFONDO_ROW_FETCH` veniva letto come una COSTANTE, mentre
    dipende dalla larghezza della mappa attraverso SCROLL_OFS_MAX, che e'
    l'offset massimo che il puntatore del display puo' raggiungere e cresce
    con la corsa della camera. Il risultato: pitch sottostimato su ogni mappa
    piu' larga di quella di partenza (152 invece di 160 a 73 colonne) e quindi
    il costo di OGNI blocco. Lezione gia' vista due volte in questo progetto:
    un valore che si LEGGE dalla tabella delle EQU e' giusto per la
    configurazione corrente e basta; se lo si vuole per un'altra, va
    RIDERIVATO dalla sua catena.

    Di fatto il fetch vince sempre: 2*cols+14 contro 2*cols+2 della mappa."""
    camera_px = cols * 16 - tab['DIW_WIDTH']
    if camera_px < 0:
        camera_px = 0
    blocco = tab['SCROLL_BLOCCO_PX']
    ofs_max = ((camera_px + blocco - 1) // blocco) * tab['SCROLL_BYTES_FETCH']
    riga_fetch = (tab['DELTA_MAPPAVERA'] + ofs_max
                  + tab['DISPLAY_FETCH_BYTES'] + tab['SFONDO_ROW_SCORTA'])
    riga_mappa = tab['DELTA_MAPPAVERA'] + tab['BG_ORIGIN_X'] + cols * 2
    need = riga_mappa if riga_mappa >= riga_fetch else riga_fetch
    return ((need + 7) // 8) * 8


def costo(tab, piani, cols, righe_buffer):
    """Byte di chip per un buffer largo `cols` tile e alto `righe_buffer` tile."""
    return piani * righe_buffer * 16 * pitch_per_colonne(tab, cols)


def main():
    riserva, ignoti = 256, 150
    zona = circolare = None
    a = sys.argv
    for i, x in enumerate(a):
        if x == '--riserva':
            riserva = int(a[i + 1])
        if x == '--ignoti':
            ignoti = int(a[i + 1])
        if x == '--zona':
            zona = (int(a[i + 1]), int(a[i + 2]))
        if x == '--circolare':
            circolare = int(a[i + 1])

    tab = valori.leggi()
    scalanti, fissi, mancanti = inventario(tab)
    piani = sum(p for _, _, p in scalanti)
    vis_c, vis_r = tab['VIS_COLS'], tab['BG_VIS_ROWS'] // 16
    per_tile = piani * 16 * 2
    per_schermata = per_tile * vis_c * vis_r

    fisso = sum(b for _, b in fissi) + ignoti * 1024
    mondo_ora = sum(b for _, b, _ in scalanti)
    libero = CHIP_TOT - (fisso - 0) - riserva * 1024
    # il mondo di oggi e' dentro `fisso`? no: scalanti e fissi sono disgiunti.
    disponibile = CHIP_TOT - fisso - riserva * 1024

    print('--- LA LEGGE ---')
    print('  %d piani scalano con l\'altezza  (%s)'
          % (piani, ', '.join('%s x%d' % (n, p) for n, _, p in scalanti)))
    print('  una tile = 16 righe x 2 byte per piano')
    print('  -> %d BYTE DI CHIP PER TILE DI MAPPA' % per_tile)
    print('  -> una schermata (%dx%d tile) = %d byte = %.0f KB'
          % (vis_c, vis_r, per_schermata, per_schermata / 1024.0))
    print('  (vale finche\' la larghezza comanda il pitch: sotto le 31 colonne')
    print('   il pitch ha il pavimento del fetch e si paga comunque per 31)')

    print('\n--- IL PORTAFOGLIO ---')
    print('  chip totale                        %8d = %6.1f KB' % (CHIP_TOT, CHIP_TOT / 1024.0))
    print('  tutto cio\' che non e\' il mondo     %8d = %6.1f KB' % (fisso, fisso / 1024.0))
    if mancanti:
        print('    (compresi %d KB passati con --ignoti: %s)'
              % (ignoti, ', '.join(mancanti)))
    print('  riserva richiesta                  %8d = %6.1f KB'
          % (riserva * 1024, float(riserva)))
    print('  RESTA PER IL MONDO                 %8d = %6.1f KB  = %.1f schermate'
          % (disponibile, disponibile / 1024.0, disponibile / float(per_schermata)))
    print('  (il mondo di oggi ne occupa %d = %.1f KB)' % (mondo_ora, mondo_ora / 1024.0))

    if zona:
        c, r = zona
        p = pitch_per_colonne(tab, c)
        b = costo(tab, piani, c, r + 1)
        print('\n--- ZONA %d colonne x %d righe ---' % (c, r))
        # DUE UNITA', e vanno dette tutte e due ogni volta. Confonderle e' gia'
        # costato una discussione: 24 righe sono 3 STANZE dell'originale (8
        # righe l'una) ma solo 2,2 NOSTRE SCHERMATE (11 righe l'una, perche'
        # BG_VIS_ROWS e' 176). "Tre" da solo non vuol dire niente.
        print('  %d x %d px' % (c * 16, r * 16))
        print('  = %.1f x %.1f STANZE dell\'originale (%dx%d tile)'
              % (c / float(STANZA_C), r / float(STANZA_R), STANZA_C, STANZA_R))
        print('  = %.1f x %.1f NOSTRE SCHERMATE (%dx%d tile), %.1f di area'
              % (c / float(vis_c), r / float(vis_r), vis_c, vis_r,
                 c * r / float(vis_c * vis_r)))
        print('  pitch %d   buffer %d byte = %.1f KB   %s'
              % (p, b, b / 1024.0,
                 'CI STA' if b <= disponibile else 'NON CI STA (%.1f KB di troppo)'
                 % ((b - disponibile) / 1024.0)))
        cmax = c
        while pitch_per_colonne(tab, cmax + 1) == p:
            cmax += 1
        if cmax > c:
            print('  ATTENZIONE: con questo pitch ci stanno %d colonne. Le %d in piu\''
                  % (cmax, cmax - c))
            print('  non costano NIENTE: il pitch si arrotonda a 8 e le stai gia\' pagando.')
        # il lavoro di una transizione, in conteggi (non in stime)
        piano = p * (r + 1) * 16
        print('\n  LAVORO DI UNA TRANSIZIONE, contato:')
        print('    tile da blittare      %d tile x 5 piani = %d blit da 16 word' % (c * r, c * r * 5))
        print('    copie master + B      2 x %d byte = %d byte' % (5 * piano, 10 * piano))
        w = 10 * piano // 2
        print('    limite INFERIORE aritmetico delle sole copie: %d word x 2 CCK' % w)
        print('    = %d CCK = %.1f quadri. NON e\' una misura: il totale vero lo da\''
              % (w * 2, w * 2 / (227 * 313.0)))
        print('    l\'harness, e i blit delle tile sono dominati dal setup, non dal transfer.')
        return 0

    if circolare:
        print('\n--- BUFFER CIRCOLARE VERTICALE, %d righe di tile ---' % circolare)
        print('  altezza della mappa: ILLIMITATA. Il costo lo fa solo la LARGHEZZA.')
        print('  %8s %8s %10s %12s' % ('colonne', 'px', 'pitch', 'KB'))
        for c in (20, 25, 31, 40, 60, 80, 100):
            b = costo(tab, piani, c, circolare)
            print('  %8d %8d %10d %12.1f %s'
                  % (c, c * 16, pitch_per_colonne(tab, c), b / 1024.0,
                     '' if b <= disponibile else '<-- oltre il budget'))
        return 0

    print('\n--- LE LARGHEZZE CHE NON SPRECANO NIENTE ---')
    print('  Il pitch e\' (2 + 2 x colonne) arrotondato a 8: se non ci cade sopra,')
    print('  stai pagando colonne che non usi. Portale al massimo, e\' gratis.')
    print('  %8s %8s %8s %s' % ('colonne', 'pitch', 'max', 'in regalo'))
    for base in (20, 40, 60, 80, 100):
        p = pitch_per_colonne(tab, base)
        cmax = base
        while pitch_per_colonne(tab, cmax + 1) == p:
            cmax += 1
        print('  %8d %8d %8d %s' % (base, p, cmax, '+%d' % (cmax - base)))

    print('\n--- ZONA MONOLITICA: cosa ci sta, per forma ---')
    print('  %8s %8s %10s %12s %14s' % ('colonne', 'schermi', 'pitch', 'righe max', 'schermi alto'))
    for c in (20, 25, 31, 40, 60, 80, 100):
        p = pitch_per_colonne(tab, c)
        rmax = disponibile // (piani * 16 * p) - 1
        print('  %8d %8.1f %10d %12d %14.1f'
              % (c, c / float(vis_c), p, rmax, rmax / float(vis_r)))
    print('\n  In ogni riga l\'AREA e\' quasi la stessa: si paga la superficie,')
    print('  non la forma. Quello che cambia e\' come la si distribuisce.')

    print('\n--- BUFFER CIRCOLARE VERTICALE: il confronto ---')
    print('  Un buffer alto una schermata piu\' un margine, che si richiude:')
    print('  l\'altezza della mappa diventa illimitata e il costo dipende solo')
    print('  dalla larghezza. Righe di buffer = %d visibili + margine.' % vis_r)
    print('  %8s %12s %12s %12s' % ('colonne', '12 righe', '13 righe', '16 righe'))
    for c in (20, 25, 31, 40, 60, 80, 100):
        print('  %8d %11.1fK %11.1fK %11.1fK'
              % (c, costo(tab, piani, c, 12) / 1024.0,
                 costo(tab, piani, c, 13) / 1024.0,
                 costo(tab, piani, c, 16) / 1024.0))
    print('\n  Oggi il mondo costa %.1f KB per 2 schermate di mappa.' % (mondo_ora / 1024.0))
    return 0


if __name__ == '__main__':
    sys.exit(main())
