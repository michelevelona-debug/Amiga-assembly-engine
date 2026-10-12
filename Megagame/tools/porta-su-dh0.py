#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# porta-su-dh0.py - copia accanto all'eseguibile i file che il gioco APRE a
#   runtime invece di incbinnarli.
#
# USO (dalla cartella Megagame):
#   py tools\porta-su-dh0.py            copia quello che manca o e' vecchio
#   py tools\porta-su-dh0.py --guarda   dice cosa farebbe e non tocca niente
#
# PERCHE' ESISTE. Fino al 11 ottobre 2026 tutta l'arte entrava nell'eseguibile
# con un `incbin`: costruito il Gioco, il gioco era completo. I fogli di tile
# adesso no - li legge CaricaFogli con dos.library - e un file letto a runtime
# deve ESISTERE accanto all'eseguibile, non nella cartella dei sorgenti. Sono
# due posti diversi e non c'e' niente che li tenga in pari: senza questo
# script si ridisegna un foglio, si ricostruisce, e il gioco continua a
# mostrare quello vecchio. In silenzio.
#
# DOVE: l'eseguibile lo dice .vscode/tasks.json (vlink.exefilename), oggi
# "../uae/dh0/Gioco". **QUEL PERCORSO E' RELATIVO A build/**, non alla radice:
# l'estensione Amiga Assembly lancia vlink dalla cartella degli oggetti, e la
# cartella uae sta DENTRO Megagame, non nel suo genitore. Risolverlo dalla
# radice portava i file un livello sopra, fuori dal repository, dove il gioco
# non li avrebbe mai trovati - e senza dire niente. Qui non si indovina: si
# provano le due risoluzioni e si tiene quella che sul disco esiste davvero.
# I file vanno in <cartella dell'eseguibile>/grafica/, perche' il nome che
# CaricaFogli apre e' "grafica/<nome>.raw" - lo genera tools/mappe.py dentro
# Mappe.i, dalla stessa riga `foglio` di risorse/mappe.txt.
#
# COSA COPIA: solo i fogli dichiarati in risorse/mappe.txt. Non e' un elenco
# scritto qui: sarebbe la seconda copia che diverge al primo foglio nuovo.
# ============================================================================
import json
import os
import shutil
import sys

QUI = os.path.dirname(os.path.abspath(__file__))
RADICE = os.path.dirname(QUI)
TASKS = os.path.join(RADICE, '.vscode', 'tasks.json')


def destinazione():
    """La cartella dell'eseguibile, LETTA da .vscode/tasks.json.

    Il percorso non si scrive qui: e' gia' dichiarato la', e due dichiarazioni
    dello stesso fatto divergono. Ma e' RELATIVO alla cartella da cui gira
    vlink, che e' build/, non alla radice - e questo in tasks.json non c'e'
    scritto. Invece di sceglierne una e sperare, si provano tutt'e due e si
    tiene quella che ESISTE: prima quella dove c'e' gia' l'eseguibile, poi
    quella dove almeno la cartella c'e'. Se non torna nessuna ci si ferma:
    copiare l'arte nel posto sbagliato e' peggio che non copiarla, perche' il
    gioco continua a leggere quella vecchia senza dire niente."""
    if not os.path.isfile(TASKS):
        raise SystemExit('manca .vscode/tasks.json: non so dove va '
                         'l\'eseguibile, e non lo indovino.')
    with open(TASKS, encoding='utf-8-sig') as f:
        d = json.load(f)
    exe = None
    for t in d.get('tasks', []):
        exe = t.get('vlink', {}).get('exefilename') or exe
    if not exe:
        raise SystemExit('in .vscode/tasks.json non trovo vlink.exefilename.')
    exe = exe.replace('\\', '/')
    # (da dove vlink lo risolve, perche')
    prove = [(os.path.join(RADICE, 'build'), 'relativo a build/, da cui gira vlink'),
             (RADICE, 'relativo alla radice del progetto')]
    candidati = [(os.path.normpath(os.path.join(base, exe)), perche)
                 for base, perche in prove]
    for p, perche in candidati:
        if os.path.isfile(p):
            print('eseguibile trovato: %s  (%s)' % (p, perche))
            return os.path.dirname(p)
    for p, perche in candidati:
        if os.path.isdir(os.path.dirname(p)):
            print('eseguibile non ancora costruito, ma la cartella c\'e\': %s  '
                  '(%s)' % (os.path.dirname(p), perche))
            return os.path.dirname(p)
    raise SystemExit('non trovo dove va l\'eseguibile. Ho provato:\n'
                     + '\n'.join('  %s  (%s)' % c for c in candidati)
                     + '\nCostruisci almeno una volta, poi rilancia.')


def fogli():
    """I fogli dichiarati in risorse/mappe.txt, nell'ordine."""
    p = os.path.join(RADICE, 'risorse', 'mappe.txt')
    if not os.path.isfile(p):
        raise SystemExit('manca risorse/mappe.txt')
    fuori = []
    for riga in open(p, encoding='utf-8'):
        c = riga.split(';')[0].split()
        if len(c) == 2 and c[0] == 'foglio':
            fuori.append(c[1])
    if not fuori:
        raise SystemExit('risorse/mappe.txt non dichiara nessun foglio.')
    return fuori


def main():
    guarda = '--guarda' in sys.argv
    dest = destinazione()
    destg = os.path.join(dest, 'grafica')
    print('i fogli vanno in %s' % destg)

    da_fare, gia = [], []
    for nome in fogli():
        src = os.path.join(RADICE, 'grafica', nome + '.raw')
        if not os.path.isfile(src):
            raise SystemExit('manca grafica/%s.raw. Lo disegna  '
                             'py tools\\genera-foglio-numerato.py %s.raw'
                             % (nome, nome))
        dst = os.path.join(destg, nome + '.raw')
        uguale = (os.path.isfile(dst)
                  and os.path.getsize(dst) == os.path.getsize(src)
                  and open(dst, 'rb').read() == open(src, 'rb').read())
        (gia if uguale else da_fare).append((src, dst, nome))

    for _, _, nome in gia:
        print('  gia\' aggiornato  %s.raw' % nome)
    if not da_fare:
        print('niente da copiare: quello che c\'e\' la\' e\' gia\' questo.')
        return 0
    for src, dst, nome in da_fare:
        n = os.path.getsize(src)
        if guarda:
            print('  COPIEREI         %s.raw (%d byte) -> %s'
                  % (nome, n, os.path.relpath(dst, RADICE)))
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        # "copiato" non e' una prova: si rilegge e si confronta.
        if open(dst, 'rb').read() != open(src, 'rb').read():
            raise SystemExit('ho copiato %s ma sul disco non c\'e\' lo stesso '
                             'contenuto. Fermo.' % nome)
        print('  copiato          %s.raw (%d byte) -> %s'
              % (nome, n, os.path.relpath(dst, RADICE)))
    if guarda:
        print('\n--guarda: non ho toccato niente.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
