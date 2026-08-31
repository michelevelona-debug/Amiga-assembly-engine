#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# misura-salti.py - stima la distanza di OGNI salto corto (Bcc.S) del sorgente
#   e segnala quelli fuori dai -128..+127 byte, PRIMA di dare il file a Devpac.
#
# USO (dalla cartella Megagame):  python3 tools/misura-salti.py
#
# PERCHE' ESISTE: inserendo righe in mezzo a un blocco si allunga la distanza di
# salti che erano gia' li' e che si e' sicuri di non aver toccato. E' successo il
# 30 agosto: i tre blocchi dei tasti di prova hanno spinto .k_prof fuori dalla
# portata del bne.s di .k_gravity, che nessuno aveva modificato.
#
# La stima SOVRASTIMA di proposito: dove non sa, conta l'indirizzamento assoluto
# lungo (4 byte). Un falso allarme costa un'occhiata, un salto non visto costa
# un giro di assemblaggio. Quindi un numero appena sopra 127 NON e' una
# condanna: lo decide l'assemblatore.
#
# TARATURA, 30 agosto 2026. Devpac ha accettato questi quattro, che lo strumento
# stima fra 102 e 128 byte. Se ricompaiono senza che nessuno abbia toccato quelle
# routine, sono loro e vanno bene:
#     Proiettile              -> .coll_next  (due volte)
#     AggiornaFisicaPlayer    -> .skipGrav
#     AggPosizioneGlobalePlayer -> .skipY
# Quello che invece era rotto davvero, e che questo strumento ha ripreso in
# pieno, era .k_gravity -> .k_prof in LeggiTastiera: 202 byte stimati, ed era il
# 2029 di Devpac.
# ============================================================================
import io, re, sys

LIMITE = 127
righe = io.open('Gioco.s', encoding='utf-8').read().split('\n')

def pulisci(r):
    # via i commenti: ';' ovunque, '*' solo a inizio riga
    if r.lstrip().startswith('*'): return ''
    return r.split(';')[0].rstrip()

def taglia_ea(op, dim):
    op = op.strip()
    if not op: return 0
    if op.startswith('#'): return 4 if dim == 'L' else 2
    if re.match(r'^-?\(?A\d\)?\+?$', op, re.I): return 0
    if re.match(r'^[AD]\d$', op, re.I): return 0
    if re.match(r'^-\(A\d\)$', op, re.I): return 0
    if re.match(r'^\(A\d\)\+?$', op, re.I): return 0
    if re.search(r'\(\s*(A\d|PC)\s*,', op, re.I): return 2      # indicizzato
    if re.search(r'\(\s*(A\d|PC)\s*\)$', op, re.I): return 2    # d16(An)
    return 4                                                    # assoluto lungo

def dimensione(riga):
    t = pulisci(riga)
    if not t or not t[0] in ' \t': 
        t2 = re.sub(r'^[A-Za-z_.][A-Za-z0-9_.]*:?', '', t)
        if not t2.strip(): return 0
        t = t2
    t = t.strip()
    if not t: return 0
    p = t.split(None, 1)
    mn = p[0].upper()
    ops = p[1] if len(p) > 1 else ''
    base, _, suf = mn.partition('.')
    dim = suf if suf in ('B','W','L') else 'W'
    if base in ('EQU','SET','RS','RSRESET','RSSET','SECTION','INCLUDE','MACRO','ENDM',
                'IFNE','IFEQ','IFGE','IFGT','IFLE','IFLT','IFD','IFND','ENDC','ELSE',
                'END','OPT','EVEN','CNOP','INCBIN','ORG','OUTPUT','FAIL'):
        return 0
    if base == 'DC':
        n = len(re.findall(r',', ops)) + 1
        return n * {'B':1,'W':2,'L':4}[dim]
    if base == 'DS':
        return 0
    if base.startswith('B') and base not in ('BTST','BSET','BCLR','BCHG'):
        return 2 if suf == 'S' else (6 if suf == 'L' else 4)
    if base.startswith('DB'): return 4
    if base == 'MOVEQ': return 2
    if base == 'MOVEM':
        a, _, b = ops.partition(',')
        return 4 + taglia_ea(a if '/' not in a and '-' not in a else b, 'L')
    tot = 2
    if ops:
        # separa i due operandi tenendo conto delle parentesi
        liv = 0; sp = -1
        for i, c in enumerate(ops):
            if c == '(': liv += 1
            elif c == ')': liv -= 1
            elif c == ',' and liv == 0: sp = i; break
        parti = [ops[:sp], ops[sp+1:]] if sp >= 0 else [ops]
        for o in parti: tot += taglia_ea(o, dim)
    return tot

# --- indice delle etichette, con l'ambito dei nomi locali ---
etichette = {}       # (ambito, nome) -> riga
ambito = ''
for i, r in enumerate(righe):
    t = pulisci(r)
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):?(?:\s|$)', t)
    if m and not re.match(r'^\S+\s+(EQU|SET|RS|MACRO)', t, re.I):
        ambito = m.group(1); etichette[('', ambito)] = i
    m = re.match(r'^(\.[A-Za-z0-9_]+):?(?:\s|$)', t)
    if m: etichette[(ambito, m.group(1))] = i

problemi = []; esaminati = 0
ambito = ''
for i, r in enumerate(righe):
    t = pulisci(r)
    m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):?(?:\s|$)', t)
    if m and not re.match(r'^\S+\s+(EQU|SET|RS|MACRO)', t, re.I): ambito = m.group(1)
    m = re.search(r'^\s+(B(?:RA|SR|EQ|NE|CC|CS|PL|MI|GE|GT|LE|LT|HI|LS|VC|VS))\.S\s+(\S+)',
                  t, re.I)
    if not m: continue
    esaminati += 1
    dest = m.group(2).strip()
    k = (ambito, dest) if dest.startswith('.') else ('', dest)
    if k not in etichette: 
        problemi.append((i+1, dest, None, 'etichetta non trovata')); continue
    j = etichette[k]
    if j > i:
        d = sum(dimensione(righe[x]) for x in range(i+1, j))
        stato = 'DA GUARDARE' if d > LIMITE else ('al limite' if d > 100 else '')
    else:
        d = -sum(dimensione(righe[x]) for x in range(j, i+1))
        stato = 'DA GUARDARE' if d < -128 else ('al limite' if d < -100 else '')
    if stato: problemi.append((i+1, dest, d, stato))

print('salti corti esaminati: %d' % esaminati)
if not problemi:
    print('Nessun salto corto oltre i 100 byte stimati.')
else:
    for ln, dest, d, st in problemi:
        print('   riga %-6d %-22s %s byte   <-- %s' % (ln, dest, d if d is not None else '?', st))
sys.exit(1 if any(p[3] == 'DA GUARDARE' for p in problemi) else 0)
