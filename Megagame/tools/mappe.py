#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# mappe.py - la GRIGLIA dei blocchi: da risorse/mappe.txt a Mappe.i
#
# USO (dalla cartella Megagame):
#   py tools\mappe.py            controlla e riscrive Mappe.i
#   py tools\mappe.py --guarda   controlla e NON scrive: dice solo cosa c'e'
#
# PERCHE' ESISTE. I collegamenti fra i blocchi sono quattro numeri per blocco,
# e portano dentro un invariante che nessun assemblatore puo' controllare: **se
# la destra di A e' B, la sinistra di B deve essere A.** Con due blocchi sono
# quattro numeri e si tengono a mente; con i sedici che serviranno per coprire
# il rettangolone dell'originale (14x12 stanze = 252x96 tile, cioe' 4x4 blocchi
# da 73x24) sono sessantaquattro, e il primo sbaglio si presenta come una porta
# che porta nel posto sbagliato - a mesi di distanza da quando e' stato scritto.
#
# Quindi la tabella in assembly NON E' UNA FONTE: e' un prodotto. La fonte e'
# `risorse/mappe.txt`, dove i collegamenti si scrivono per NOME e non per
# indice, e questo script rifiuta di generare se la reciprocita' non torna.
# Stesso rapporto che c'e' fra risorse/mappa1.txt e grafica/mappa1.raw.
#
# COSA CONTROLLA, e ognuno di questi ha fermato qualcosa almeno una volta
# in progetti come questo:
#   - un nome citato come destinazione che non e' dichiarato;
#   - un blocco collegato a se stesso;
#   - due blocchi con lo stesso nome;
#   - il .raw del blocco che non esiste o non e' della misura giusta;
#   - **la reciprocita' dei quattro versi**, che e' il motivo per cui esiste.
#
# COSA NON CONTROLLA: la geografia, cioe' se chi esce da un bordo trova
# pavimento dall'altra parte. Quello lo fa `tools/porte.py`, e sono due domande
# diverse: qui "la tabella e' coerente", la' "il salto e' giocabile".
# ============================================================================
import os
import re
import sys

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import valori

FONTE = os.path.join(RADICE, 'risorse', 'mappe.txt')
USCITA = os.path.join(RADICE, 'Mappe.i')

# L'ordine dei versi e' quello delle EQU VERSO_* in Gioco.s, e non si sceglie
# qui: si LEGGE da la'. Se un giorno cambia l'ordine delle EQU, la tabella
# generata lo segue invece di contraddirlo in silenzio.
VERSI = ('sinistra', 'destra', 'sopra', 'sotto')

MODELLO = """; ============================================================================
; Mappe.i - GENERATO da tools/mappe.py, NON si modifica a mano.
; La fonte e' risorse/mappe.txt. Per cambiare un collegamento si tocca quello e
; si rilancia `py tools\\mappe.py`: qui dentro una modifica a mano sopravvive
; fino alla prossima generazione e poi sparisce senza dire niente.
;
; I quattro versi seguono le EQU VERSO_* di Gioco.s, in quest'ordine:
;   %(ordine)s
; Un -1 vuol dire "quel bordo e' un muro".
;
; LA RECIPROCITA' E' STATA CONTROLLATA da chi ha generato questo file: per ogni
; collegamento A -> B esiste il ritorno B -> A sul verso opposto. Non e' un
; invariante che l'assemblatore possa verificare, ed e' il motivo per cui
; questa tabella non si scrive a mano.
; ============================================================================

MAPPE_N				EQU		%(n)d

%(incbin)s
	cnop	0,4
MappaBase:
%(base)s
MappaBaseFine:
	IFNE	(MappaBaseFine-MappaBase)/4-MAPPE_N
GUARDIA_MAPPA_BASE	EQU		1/0
	ENDC

; Una voce per blocco, VERSI_N word: l'indice del vicino o -1.
	cnop	0,2
MappaLink:
%(link)s
MappaLinkFine:
	IFNE	(MappaLinkFine-MappaLink)/(VERSI_N*2)-MAPPE_N
GUARDIA_MAPPA_LINK	EQU		1/0
	ENDC
"""


def ordine_versi():
    """L'ordine dei versi come lo dicono le EQU VERSO_* di Gioco.s."""
    src = '\n'.join(valori._espandi(valori.SORGENTE))
    fuori = {}
    for m in re.finditer(r'^VERSO_(\w+)\s+EQU\s+(\d+)', src, re.M):
        fuori[int(m.group(2))] = m.group(1).lower()
    if not fuori:
        raise SystemExit('in Gioco.s non trovo le EQU VERSO_*: definiscile la\','
                         ' non qui')
    if sorted(fuori) != list(range(len(fuori))):
        raise SystemExit('le EQU VERSO_* non sono 0..%d consecutive: %s'
                         % (len(fuori) - 1, fuori))
    corti = {'sx': 'sinistra', 'dx': 'destra', 'su': 'sopra', 'giu': 'sotto'}
    return [corti.get(fuori[i], fuori[i]) for i in range(len(fuori))]


def leggi_fonte():
    if not os.path.isfile(FONTE):
        raise SystemExit('manca %s' % os.path.relpath(FONTE, RADICE))
    blocchi = []
    for n, riga in enumerate(open(FONTE, encoding='utf-8'), 1):
        c = riga.split(';')[0].strip()
        if not c:
            continue
        p = c.split()
        if len(p) != 1 + len(VERSI):
            raise SystemExit('%s riga %d: ci vogliono 1 nome piu\' %d versi '
                             '(%s), trovati %d campi'
                             % (os.path.relpath(FONTE, RADICE), n, len(VERSI),
                                ' '.join(VERSI), len(p)))
        blocchi.append((p[0], p[1:], n))
    if not blocchi:
        raise SystemExit('%s non dichiara nessun blocco'
                         % os.path.relpath(FONTE, RADICE))
    return blocchi


def controlla(blocchi, versi, cols, righe):
    nomi = [b[0] for b in blocchi]
    guai = []
    for i, nome in enumerate(nomi):
        if nomi.index(nome) != i:
            guai.append('il nome %r e\' dichiarato due volte' % nome)
    # il .raw di ogni blocco deve esserci e essere della misura giusta
    atteso = cols * righe * 2
    for nome, _, n in blocchi:
        p = os.path.join(RADICE, 'grafica', nome + '.raw')
        if not os.path.isfile(p):
            guai.append('manca grafica/%s.raw: lancia py tools\\mappa.py '
                        '--mappa %s' % (nome, nome[5:]))
        elif os.path.getsize(p) != atteso:
            guai.append('grafica/%s.raw e\' %d byte, ne servono %d (%dx%d word)'
                        % (nome, os.path.getsize(p), atteso, cols, righe))
    # i nomi citati come destinazione devono esistere, e nessuno cita se stesso
    for nome, dest, n in blocchi:
        for v, d in zip(versi, dest):
            if d == '-':
                continue
            if d == nome:
                guai.append('riga %d: %s si collega a se stesso a %s' % (n, nome, v))
            elif d not in nomi:
                guai.append('riga %d: %s a %s cita %r, che non e\' dichiarato'
                            % (n, nome, v, d))
    if guai:
        return guai
    # LA RECIPROCITA', che e' il motivo per cui questo script esiste
    opposto = {'sinistra': 'destra', 'destra': 'sinistra',
               'sopra': 'sotto', 'sotto': 'sopra'}
    per_nome = {b[0]: dict(zip(versi, b[1])) for b in blocchi}
    for nome, dest, n in blocchi:
        for v, d in zip(versi, dest):
            if d == '-':
                continue
            op = opposto[v]
            se_torna = per_nome[d].get(op, '-')
            if se_torna != nome:
                guai.append('riga %d: %s a %s va in %s, ma %s a %s %s'
                            % (n, nome, v, d, d, op,
                               'e\' un muro' if se_torna == '-'
                               else 'va in ' + se_torna))
    return guai


def main():
    t = valori.leggi()
    cols, righe = t['MAPPA_COLS'], t['MAPPA_ROWS']
    versi = ordine_versi()
    blocchi = leggi_fonte()
    print('%s: %d blocchi, versi %s'
          % (os.path.relpath(FONTE, RADICE), len(blocchi), ', '.join(versi)))
    guai = controlla(blocchi, versi, cols, righe)
    nomi = [b[0] for b in blocchi]
    for i, (nome, dest, _) in enumerate(blocchi):
        print('  %d %-8s %s' % (i, nome,
              '  '.join('%s=%s' % (v, d) for v, d in zip(versi, dest))))
    if guai:
        print('\n%d PROBLEMA%s, Mappe.i NON e\' stato riscritto:'
              % (len(guai), '' if len(guai) == 1 else 'I'))
        for g in guai:
            print('  - ' + g)
        return 1

    incbin = []
    base = []
    for i, nome in enumerate(nomi):
        et = 'MAPPA%d' % (i + 1)
        incbin.append('\tcnop\t0,2\n%s:\n\tincbin\t"grafica/%s.raw"\n%s_FINE:\n'
                      '\tIFNE\t(%s_FINE-%s)-MAPPA_ATTESA\n'
                      'GUARDIA_%s_RAW\tEQU\t\t1/0\n\tENDC'
                      % (et, nome, et, et, et, et))
        base.append('\tdc.l\t%s\t\t\t; %d = %s' % (et, i, nome))
    link = []
    for nome, dest, _ in blocchi:
        v = ['-1' if d == '-' else str(nomi.index(d)) for d in dest]
        link.append('\tdc.w\t%s\t; %s' % (','.join('%3s' % x for x in v), nome))
    testo = MODELLO % dict(n=len(nomi), ordine=', '.join(versi),
                           incbin='\n'.join(incbin), base='\n'.join(base),
                           link='\n'.join(link))
    if '--guarda' in sys.argv:
        print('\n--guarda: non scrivo. Mappe.i verrebbe cosi\':\n')
        print(testo)
        return 0
    with open(USCITA, 'w', encoding='utf-8', newline='\n') as f:
        f.write(testo)
    print('\nscritto %s (%d blocchi). La reciprocita\' torna.'
          % (os.path.relpath(USCITA, RADICE), len(nomi)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
