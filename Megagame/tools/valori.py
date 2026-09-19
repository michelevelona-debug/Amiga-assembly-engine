#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# valori.py - calcola il valore VERO delle EQU di Gioco.s, rami condizionali
#             compresi.
#
# USO (dalla cartella Megagame):
#     python3 tools/valori.py                 stampa il quadro di geometria
#     python3 tools/valori.py NOME [NOME...]  stampa solo quelle EQU
#     python3 tools/valori.py --chip          l'inventario della chip RAM
#
# PERCHE' ESISTE
# Meta' delle EQU di questo sorgente sono definite PIU' VOLTE, una per ramo di
# un IFEQ/IFNE. Uno script che cerca "^NOME EQU" e prende la prima riga che
# trova legge il ramo SBAGLIATO e non se ne accorge: e' successo il 6 settembre
# 2026 e ha prodotto numeri pubblicati come misure - SFONDO_PITCH 64 quando vale
# 56, SCROLL_BLOCCO_PX 64 quando vale 16, e un risparmio di 46 KB che non
# esiste. Quel giorno il difetto non era nel sorgente ma nello strumento.
#
# Questo modulo tiene una pila di rami e scarta le righe che l'assemblatore non
# vedrebbe, poi risolve le espressioni per sostituzione ripetuta finche' non
# scopre piu' niente di nuovo (una EQU puo' usarne una definita piu' avanti).
#
# LIMITI, dichiarati perche' non diventino trappole:
# - la divisione e' INTERA e tronca verso lo zero, come fa l'assemblatore;
# - gli operatori riconosciuti sono quelli aritmetici e & | ^ << >>;
# - se una EQU non si risolve resta assente invece di prendere un valore finto.
# ============================================================================
import os, re, sys

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORGENTE = os.path.join(RADICE, 'Gioco.s')


def _numero(espr, tab):
    e = re.sub(r'\$([0-9A-Fa-f]+)', lambda g: str(int(g.group(1), 16)), espr)
    e = re.sub(r'%([01]+)', lambda g: str(int(g.group(1), 2)), e)
    for t in sorted(set(re.findall(r'[A-Za-z_]\w*', e)), key=len, reverse=True):
        if t not in tab:
            raise KeyError(t)
        e = e.replace(t, '(' + str(tab[t]) + ')')
    if not re.fullmatch(r'[-+*/()&|^<>\s\d]+', e):
        raise ValueError(espr)
    return eval(e.replace('/', '//'))


def leggi(path=SORGENTE):
    """Le EQU con il valore del ramo VIVO. Ritorna un dizionario."""
    righe = open(path, encoding='utf-8').read().split('\n')
    tab = {}
    for _ in range(8):                       # finche' scopre roba nuova
        pila = [True]
        nuove = 0
        for l in righe:
            c = l.split(';')[0].rstrip()
            m = re.match(r'^\s+IF(NE|EQ)\s+(.+)$', c, re.I)
            if m:
                try:
                    v = _numero(m.group(2).strip(), tab)
                    vivo = (v != 0) if m.group(1).upper() == 'NE' else (v == 0)
                except Exception:
                    vivo = None              # non ancora calcolabile: si tiene
                pila.append(pila[-1] and (vivo is not False))
                continue
            if re.match(r'^\s+ENDC\b', c, re.I):
                if len(pila) > 1:
                    pila.pop()
                continue
            if not pila[-1]:
                continue
            m = re.match(r'^([A-Za-z_]\w*)\s+EQU\s+(.+)$', c)
            if m and m.group(1) not in tab:
                try:
                    tab[m.group(1)] = _numero(m.group(2).strip(), tab)
                    nuove += 1
                except Exception:
                    pass
        if not nuove:
            break
    return tab


def geometria(tab):
    print('--- prelievo e finestra ---')
    for n in ('SCROLL_FETCH_BIT', 'SCROLL_BLOCCO_PX', 'SCROLL_BYTES_FETCH',
              'SCROLL_DDFSTRT', 'SCROLL_DDFSTOP', 'SCROLL_FETCHES',
              'SCROLL_FMODE_VAL', 'DIW_H_START', 'DIW_H_STOP', 'DIW_WIDTH',
              'VIS_COLS', 'PANNELLO_ART_BYTE_OFS'):
        v = tab.get(n)
        print('  %-22s %s' % (n, ('%6d   $%X' % (v, v)) if v is not None else '?'))
    if all(k in tab for k in ('SCROLL_DDFSTRT', 'SCROLL_BLOCCO_PX', 'DIW_H_START')):
        d = tab['SCROLL_DDFSTRT'] * 2
        b = tab['SCROLL_BLOCCO_PX']
        print('\n  DDFSTRT vale %d px lores; il ritardo BPLCON1 arriva a %d;' % (d, b-1))
        print('  la finestra apre a %d, quindi la latenza di pipeline deve stare'
              % tab['DIW_H_START'])
        print('  sotto %d px perche\' il primo pixel abbia gia\' il suo dato.'
              % (tab['DIW_H_START'] - d - (b-1)))

    print('\n--- il mondo ---')
    for n in ('MAPPA_COLS', 'MAPPA_ROWS', 'SFONDO_ROW_NEED', 'SFONDO_ROW_SCORTA',
              'SFONDO_PITCH', 'SFONDO_HEIGHT', 'SFONDO_PLANE_SIZE', 'BG_VIS_ROWS'):
        v = tab.get(n)
        print('  %-22s %s' % (n, ('%6d' % v) if v is not None else '?'))


def chip(tab):
    """Quanto occupa la chip RAM: i buffer BSS_C piu' gli incbin in DATA_C.
    I buffer si leggono dal sorgente (ds.b in sezione _C), non da una lista
    scritta a mano che si scollerebbe."""
    righe = open(SORGENTE, encoding='utf-8').read().split('\n')
    sez = None
    voci = []
    ultima_etichetta = '?'
    for l in righe:
        c = l.split(';')[0].rstrip()
        m = re.match(r'^\s*section\s+(\w+)\s*,\s*(\w+)', c, re.I)
        if m:
            sez = m.group(2).upper()
            continue
        m = re.match(r'^([A-Za-z_]\w*):', c)
        if m:
            ultima_etichetta = m.group(1)
        m = re.search(r'\bds\.b\s+(.+)$', c)
        if m and sez in ('BSS_C', 'DATA_C'):
            try:
                voci.append((ultima_etichetta, _numero(m.group(1).strip(), tab)))
            except Exception:
                voci.append((ultima_etichetta, None))
        m = re.match(r'^\s*incbin\s+"([^"]+)"', c, re.I)
        if m and sez in ('BSS_C', 'DATA_C'):
            p = os.path.join(RADICE, m.group(1))
            voci.append((m.group(1), os.path.getsize(p) if os.path.exists(p) else None))
    tot = 0
    manca = 0
    print('%-30s %10s' % ('cosa', 'byte'))
    for n, v in voci:
        print('  %-28s %10s' % (n, v if v is not None else 'non calcolabile'))
        if v:
            tot += v
        else:
            manca += 1
    print('  %-28s %10d  = %.1f KB su 2048 KB' % ('TOTALE NOTO', tot, tot/1024.0))
    if manca:
        print('  (%d voci non calcolabili: non sono nel totale)' % manca)


def main():
    tab = leggi()
    arg = [a for a in sys.argv[1:] if not a.startswith('--')]
    if '--chip' in sys.argv:
        chip(tab)
    elif arg:
        for n in arg:
            v = tab.get(n)
            print('%-24s %s' % (n, ('%d   $%X' % (v, v)) if v is not None else 'non risolta'))
    else:
        geometria(tab)
        print('\n(EQU risolte: %d)' % len(tab))
    return 0


if __name__ == '__main__':
    sys.exit(main())
