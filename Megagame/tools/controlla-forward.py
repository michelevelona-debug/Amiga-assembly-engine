#!/usr/bin/env python3
# Trova le EQU (e le IFxx) che usano un simbolo definito PIU' AVANTI.
# vasm le risolve con piu' passate, Devpac no: da' "absolute expression must
# evaluate" sulla riga della EQU. Il sorgente deve andare bene a entrambi.
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

def main():
    righe = espandi('Gioco.s')
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
    if not problemi:
        print('\nNessun riferimento in avanti: il sorgente va bene anche a Devpac.')
        return 0
    print('\n%d riferimenti IN AVANTI (Devpac: "absolute expression must evaluate"):\n' % len(problemi))
    for file, n, nome, expr, mancanti, tipo in problemi:
        print('  %s riga %d   %s' % (file, n, nome))
        print('      %s' % expr)
        print('      non ancora definiti: %s' % ', '.join(mancanti))
    return 1

sys.exit(main())
