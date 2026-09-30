#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# misura-salti.py - la distanza dei salti CORTI, e quanto una consegna li ha
#   allungati.
#
# USO (dalla cartella Megagame):
#   python3 tools/misura-salti.py                 tutti i salti corti di Gioco.s
#   python3 tools/misura-salti.py ALTRO.s         un altro file
#   python3 tools/misura-salti.py --contro VEC.s  confronto con la versione
#                                                 precedente: stampa SOLO i
#                                                 salti che si sono allungati
#
# PERCHE' ESISTE. Un `Bcc.S` copre -128..+127 byte. **Inserire righe allunga i
# salti corti che erano gia' li'**, quindi una consegna che non tocca nemmeno
# una riga esistente puo' comunque spingerne uno fuori portata, e l'errore
# esce su una riga che non e' stata scritta oggi. Non bastano i salti nuovi:
# vanno guardati quelli SCAVALCATI.
#
# LIMITE DICHIARATO, e va letto prima di credere a un numero: la dimensione
# delle istruzioni qui e' STIMATA, non assemblata. La stima e' per ECCESSO -
# ogni operando di forma incerta conta il massimo - quindi un numero sotto 127
# e' affidabile e uno appena sopra va GUARDATO, non creduto. Per esserne certi
# si assembla.
# ============================================================================
import os, re, sys

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Salti a spiazzamento CORTO: 2 byte in tutto, portata -128..+127 dal byte
# successivo all'opcode. DBRA non c'e' dentro apposta: il suo spiazzamento e'
# sempre a 16 bit e non puo' uscire di portata.
CORTI = re.compile(r'^\s+(B(?:RA|SR|HI|LS|CC|CS|NE|EQ|VC|VS|PL|MI|GE|LT|GT|LE)'
                   r')\.S\s+([.\w]+)', re.I)
ETICHETTA = re.compile(r'^([.\w]+):')
DIRETTIVA = re.compile(r'^\s+(dc|dcb|ds)\.([bwl])\s+(.*)$', re.I)


def _dimensione(riga):
    """Byte occupati dalla riga. STIMA PER ECCESSO: vedi il limite in testa."""
    c = riga.split(';')[0].rstrip()
    if not c.strip():
        return 0
    m = DIRETTIVA.match(c)
    if m:
        larg = {'b': 1, 'w': 2, 'l': 4}[m.group(2).lower()]
        corpo = m.group(3)
        if m.group(1).lower() == 'ds':
            return 0            # BSS: non e' codice, non sposta i salti
        if m.group(1).lower() == 'dcb':
            return 0            # idem: sta nei dati
        # una stringa 'ABC' conta i suoi caratteri, non le virgole
        n = 0
        for pezzo in re.findall(r"'[^']*'|[^,]+", corpo):
            n += len(pezzo) - 2 if pezzo.startswith("'") else 1
        return n * larg
    if ETICHETTA.match(c) and not c[len(ETICHETTA.match(c).group(0)):].strip():
        return 0
    c = re.sub(r'^[.\w]+:', '', c)
    if not c.strip():
        return 0
    m = re.match(r'^\s+([A-Za-z_][\w.]*)\s*(.*)$', c)
    if not m:
        return 0
    mnem, operandi = m.group(1).lower(), m.group(2)
    if mnem.split('.')[0] in ('equ', 'set', 'section', 'include', 'incbin',
                              'even', 'cnop', 'end', 'macro', 'endm', 'ifne',
                              'ifeq', 'ifge', 'ifgt', 'ifle', 'iflt', 'endc',
                              'else', 'rept', 'endr', 'opt', 'output', 'list',
                              'nolist', 'fail', 'printt', 'printv'):
        return 0
    if CORTI.match(riga):
        return 2
    # base 2 byte, piu' il massimo che ogni operando puo' portarsi dietro
    n = 2
    for op in re.findall(r"'[^']*'|[^,]+", operandi):
        op = op.strip()
        if not op:
            continue
        if op.startswith('#'):
            n += 4 if ('.l' in mnem or mnem.startswith('move.l')) else 2
            if 'movem' in mnem:
                n -= 2
        elif re.match(r'^\$?[0-9A-Fa-f]+\([Aa]\d', op) or re.match(r'^-?\d+\([Aa]\d', op):
            n += 2
        elif re.search(r'\([AaPp][\dCc]', op):
            n += 2          # indicizzato o d16(An): 2 byte
        elif re.match(r'^[-$%\w]+$', op) and not re.match(r'^[AaDd]\d$', op) \
                and op.lower() not in ('sp', 'pc', 'ccr', 'sr', 'usp'):
            n += 4          # assoluto: si conta lungo, che e' il caso peggiore
    return n


def salti(path):
    """{ (routine, riga, mnemonico, destinazione) : distanza in byte }"""
    righe = open(path, encoding='utf-8').read().split('\n')
    # primo giro: posizione in byte di ogni riga e di ogni etichetta
    pos, p = [], 0
    ultima_globale = '?'
    etichette = {}
    for l in righe:
        pos.append(p)
        m = ETICHETTA.match(l)
        if m:
            nome = m.group(1)
            if not nome.startswith('.'):
                ultima_globale = nome
            etichette[(ultima_globale, nome)] = p
        p += _dimensione(l)
    # secondo giro: i salti corti
    fuori = {}
    ultima_globale = '?'
    for n, l in enumerate(righe):
        m = ETICHETTA.match(l)
        if m and not m.group(1).startswith('.'):
            ultima_globale = m.group(1)
        m = CORTI.match(l)
        if not m:
            continue
        dest = etichette.get((ultima_globale, m.group(2)))
        if dest is None:
            continue
        fuori[(ultima_globale, m.group(1).upper(), m.group(2), n + 1)] = \
            dest - (pos[n] + 2)
    return fuori


def main():
    arg = [a for a in sys.argv[1:] if not a.startswith('--')]
    path = arg[0] if arg else os.path.join(RADICE, 'Gioco.s')
    ora = salti(path)
    if '--contro' in sys.argv:
        prima = salti(arg[1])
        allungati = []
        # Una routine puo' avere DUE salti identici alla stessa etichetta
        # (WaitTitleInput ne ha due a .wait_release). Abbinarli per nome
        # prenderebbe sempre il primo e produrrebbe allungamenti inventati;
        # abbinarli per riga piu' vicina e' peggio, perche' le righe si sono
        # spostate proprio per via della consegna. Si abbinano per ORDINE:
        # l'ennesimo di quel gruppo prima con l'ennesimo adesso.
        def gruppi(d):
            fuori = {}
            for k in sorted(d, key=lambda kk: kk[3]):
                fuori.setdefault(k[:3], []).append((k, d[k]))
            return fuori
        gp, gn = gruppi(prima), gruppi(ora)
        for firma, voci in gn.items():
            vecchie = gp.get(firma, [])
            for i, (k, v) in enumerate(voci):
                if i >= len(vecchie):
                    allungati.append((k, None, v))
                    continue
                vecchio = vecchie[i][1]
                if abs(v) > abs(vecchio):
                    allungati.append((k, vecchio, v))
        print('salti corti: %d prima, %d adesso' % (len(prima), len(ora)))
        if not allungati:
            print('NESSUNO si e\' allungato.')
            return 0
        for (rout, mnem, dest, riga), vecchio, nuovo in sorted(
                allungati, key=lambda x: -abs(x[2])):
            nota = '  <-- DA GUARDARE' if abs(nuovo) > 120 else ''
            print('  riga %5d %-26s %s.S %-20s %s -> %+d%s'
                  % (riga, rout, mnem, dest,
                     ('nuovo' if vecchio is None else '%+d' % vecchio),
                     nuovo, nota))
        return 0
    guardare = [(k, v) for k, v in ora.items() if abs(v) > 120]
    print('salti corti: %d' % len(ora))
    peggio = sorted(ora.items(), key=lambda x: -abs(x[1]))[:10]
    for (rout, mnem, dest, riga), v in peggio:
        nota = '  <-- DA GUARDARE' if abs(v) > 120 else ''
        print('  riga %5d %-26s %s.S %-20s %+d%s' % (riga, rout, mnem, dest, v, nota))
    print('%d oltre 120 byte (la stima e\' per eccesso: vanno guardati, non creduti)'
          % len(guardare))
    return 0


if __name__ == '__main__':
    sys.exit(main())
