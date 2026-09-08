#!/usr/bin/env python3
# Due controlli che qui si possono fare e l'assemblatore non c'e' per farli.
#
# 1. Le EQU (e le IFxx) che usano un simbolo definito PIU' AVANTI.
#    vasm le risolve con piu' passate, Devpac no: da' "absolute expression must
#    evaluate" sulla riga della EQU. Il sorgente deve andare bene a entrambi.
#
# 2. Il codice DOPO la direttiva `end`. Dall'`end` in giu' l'assemblatore non
#    guarda piu' niente: le righe ci sono, si leggono, si modificano, e non
#    esistono. Aggiunto il 2 settembre 2026 dopo averci sbattuto: un innesto
#    appeso in fondo al file dava "error 2025: absolute value expected" su un
#    MOVEQ a 7000 righe di distanza, e nessuno dei tre controlli se ne
#    accorgeva - anzi, QUESTO contava i suoi simboli fra i definiti.
import re, os, sys

RADICE = os.getcwd()
ESCLUSI = ('ptplayer.i',)          # terze parti, incluso in fondo: niente dopo

def espandi(nome, visti=None, catena=None):
    """Restituisce [(file, n_riga, testo)] nell'ordine in cui l'assemblatore
    le vede, seguendo gli include."""
    visti = visti if visti is not None else set()
    out = []
    p = os.path.join(RADICE, nome)
    if not os.path.isfile(p):
        out.append((nome, 0, '; *** include mancante: %s' % nome))
        return out
    with open(p, encoding='latin-1') as f:
        righe = f.read().split('\n')
    for i, l in enumerate(righe, 1):
        m = re.match(r'^\s*include\s+"([^"]+)"', l, re.I)
        if m:
            sub = m.group(1)
            if os.path.basename(sub) in ESCLUSI:
                out.append((nome, i, '; *** include saltato: %s' % sub))
                # Saltato per i SIMBOLI, non per l'`end`. Se un include escluso
                # contiene una direttiva `end`, quella vale per tutti: da li' in
                # giu' l'assemblatore non legge piu' NIENTE, nemmeno il resto
                # del file che l'ha incluso. ptplayer.i ne ha una alla sua riga
                # 3974, ed e' il motivo per cui il 2 settembre un blocco messo
                # in fondo a Gioco.s dava "Link Error 21: Reference to undefined
                # symbol BarreSprite": l'assemblatore non l'aveva mai visto.
                p2 = os.path.join(RADICE, sub)
                if os.path.isfile(p2):
                    with open(p2, encoding='latin-1') as f2:
                        for j, l2 in enumerate(f2.read().split('\n'), 1):
                            if re.sub(r';.*$', '', l2).strip().lower() == 'end':
                                out.append((sub, j, '\tend'))
                                break
                continue
            out.append((nome, i, l))
            out += espandi(sub, visti)
        else:
            out.append((nome, i, l))
    return out

DEF_EQU = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s+(EQU|SET|=)\s+(.+)$', re.I)
DEF_LAB = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:')
DEF_RS  = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*)\s*:?\s+(RS|__RS)\.[bwl]', re.I)
COND    = re.compile(r'^\s*(IFNE|IFEQ|IFGE|IFLT|IFGT|IFLE)\s+(.+)$', re.I)
PAROLA  = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
# nomi che non sono simboli: registri, suffissi, direttive comuni
NON_SIMBOLI = {'d0','d1','d2','d3','d4','d5','d6','d7','a0','a1','a2','a3','a4','a5','a6','a7',
               'sp','pc','sr','ccr','usp','vbr','b','w','l','s','x','rs','narg'}

def dopo_end(righe):
    """Le righe di codice che stanno DOPO la direttiva `end`: l'assemblatore
    non le vede. Restituisce (n_end, [(file, n, testo)])."""
    n_end = None
    for k, (file, n, testo) in enumerate(righe):
        if re.sub(r';.*$', '', testo).strip().lower() == 'end':
            n_end = (k, file, n)
            break
    if n_end is None:
        return None, []
    k, _f, _n = n_end
    # Un secondo `end` piu' in basso e' innocuo (e' quello di Gioco.s, reso
    # ridondante dall'end di ptplayer.i): non e' codice che qualcuno si aspetta
    # veda la luce. Tutto il resto si', ed e' il caso da segnalare.
    morte = [(f, n, t) for f, n, t in righe[k + 1:]
             if re.sub(r';.*$', '', t).strip()
             and re.sub(r';.*$', '', t).strip().lower() != 'end'
             and not t.lstrip().startswith('*')]
    return n_end, morte


def main():
    righe = espandi('Gioco.s')
    n_end, morte = dopo_end(righe)
    if n_end is not None:
        righe = righe[:n_end[0] + 1]      # oltre l'end il sorgente non esiste
    definiti = set()
    problemi = []
    for file, n, testo in righe:
        code = re.sub(r';.*$', '', testo).rstrip()
        if not code.strip():
            continue
        m = DEF_EQU.match(code)
        if m:
            nome, expr = m.group(1), m.group(3)
            usati = {w for w in PAROLA.findall(re.sub(r'\$[0-9A-Fa-f]+|%[01]+', ' ', expr))
                     if w.lower() not in NON_SIMBOLI}
            mancanti = sorted(u for u in usati if u not in definiti)
            if mancanti:
                problemi.append((file, n, nome, expr.strip(), mancanti, 'EQU'))
            definiti.add(nome)
            continue
        c = COND.match(code)
        if c:
            expr = c.group(2)
            usati = {w for w in PAROLA.findall(re.sub(r'\$[0-9A-Fa-f]+|%[01]+', ' ', expr))
                     if w.lower() not in NON_SIMBOLI}
            mancanti = sorted(u for u in usati if u not in definiti)
            if mancanti:
                problemi.append((file, n, c.group(1).upper(), expr.strip(), mancanti, 'IF'))
            continue
        m = DEF_RS.match(code)
        if m:
            definiti.add(m.group(1)); continue
        m = DEF_LAB.match(code)
        if m:
            definiti.add(m.group(1)); continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s+(MACRO)\b', code, re.I)
        if m:
            definiti.add(m.group(1))

    print('righe esaminate: %d   simboli definiti: %d' % (len(righe), len(definiti)))
    if n_end is not None:
        print('direttiva `end`: %s riga %d' % (n_end[1], n_end[2]))
    else:
        print('ATTENZIONE: nessuna direttiva `end` trovata.')

    esito = 0
    if morte:
        esito = 1
        print('\n%d righe di codice DOPO `end`: NON vengono assemblate.' % len(morte))
        simboli = []
        for f, n, t in morte:
            code = re.sub(r';.*$', '', t).rstrip()
            for rx in (DEF_EQU, DEF_RS, DEF_LAB):
                m = rx.match(code)
                if m:
                    simboli.append(m.group(1)); break
        for f, n, t in morte[:12]:
            print('  %s riga %d   %s' % (f, n, t.strip()[:60]))
        if len(morte) > 12:
            print('  ... e altre %d' % (len(morte) - 12))
        if simboli:
            print('  simboli che sembrano definiti e NON lo sono: %s'
                  % ', '.join(simboli[:15]))

    if not problemi:
        print('\nNessun riferimento in avanti: il sorgente va bene anche a Devpac.')
        return esito
    print('\n%d riferimenti IN AVANTI (Devpac: "absolute expression must evaluate"):\n' % len(problemi))
    for file, n, nome, expr, mancanti, tipo in problemi:
        print('  %s riga %d   %s' % (file, n, nome))
        print('      %s' % expr)
        print('      non ancora definiti: %s' % ', '.join(mancanti))
    return 1

sys.exit(main())
