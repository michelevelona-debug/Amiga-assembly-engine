#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# impronta.py - QUALE versione del sorgente c'e' sul disco, in una riga.
#
# USO (dalla cartella Megagame):
#   py tools\impronta.py                 impronta di Gioco.s e degli include
#   py tools\impronta.py 77deb594        confronta Gioco.s con quell'impronta
#   py tools\impronta.py --copie         cerca a quale copia .prima-* somiglia
#                                        (in backup/, e accanto al sorgente)
#
# PERCHE' ESISTE. Il 22, 23 e 24 settembre 2026 Gioco.s e' tornato indietro da
# solo piu' volte: ogni scrittura andava a buon fine e poco dopo sul disco
# c'era una versione PRECEDENTE, sempre una di quelle consegnate prima. Nessuno
# dei due se ne accorgeva subito, e si e' lavorato su basi diverse per mezza
# giornata. Il BUILD non c'entra (`.vscode/tasks.json` legge i .s e scrive solo
# `uae/dh0/Gioco`), quindi l'unico che puo' riscrivere il file e' un editor che
# lo tiene aperto con un buffer vecchio: VS Code ricarica da solo un buffer
# PULITO, ma se e' sporco - o se e' sopravvissuto a una chiusura col ripristino
# automatico - il primo Ctrl+S ci scrive sopra quello che aveva in pancia.
#
# Il rimedio non e' ricordarsi di guardare: e' UN numero da confrontare. Chi
# consegna dice l'impronta, chi ha il disco la stampa. Se differiscono si sta
# guardando due file diversi, e si scopre in dieci secondi invece che dopo tre
# consegne perse.
#
# L'impronta e' il md5 dei byte del file, non una data e non la dimensione: due
# versioni diverse possono avere gli stessi byte di lunghezza (e' successo con
# `Tiles.raw`, che e' sempre 51200), mentre byte identici sono lo stesso file.
# I primi 8 caratteri bastano per parlarne; il confronto accetta un prefisso.
# ============================================================================
import hashlib
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import copie

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# I file che si portano sull'Amiga e che quindi contano. ptplayer.i non c'e':
# e' di terze parti e non lo si tocca, quindi un suo cambiamento sarebbe una
# notizia diversa da quella che questo strumento cerca.
SORGENTI = ['Gioco.s', 'ScrollHW.i', 'Testo.i', 'CieloGrad.i', 'Intro.i',
            'Startup2.i', 'Pannello.cop']


def impronta(path):
    """(md5 esadecimale, byte, righe). Le righe si contano sui byte: il file
    puo' non essere UTF-8 (Startup2.i e' latin-1) e qui non si decodifica."""
    with open(path, 'rb') as f:
        d = f.read()
    return hashlib.md5(d).hexdigest(), len(d), d.count(b'\n') + (
        0 if d.endswith(b'\n') or not d else 1)


def elenco_copie(nome='Gioco.s'):
    """Le copie di sicurezza del sorgente: backup/Gioco.s.prima-qualcosa.

    Chi le cerca e' `copie.cerca`, che guarda in backup/ E accanto al file.
    Questa distinzione e' load-bearing proprio qui: se le copie si spostano in
    backup/ e questo strumento continuasse a guardare solo la radice,
    diventerebbe cieco esattamente sul difetto per cui e' nato - e lo sarebbe
    in silenzio, stampando 'nessuna copia' invece di un errore."""
    return copie.cerca(nome)


def main():
    argv = sys.argv[1:]
    cerca_copie = '--copie' in argv
    atteso = next((a for a in argv if not a.startswith('--')), None)

    if atteso and len(atteso) < 6:
        sys.exit('l\'impronta attesa vuole almeno 6 caratteri: %s' % atteso)

    esito = 0
    vivo = {}
    for nome in SORGENTI:
        p = os.path.join(RADICE, nome)
        if not os.path.isfile(p):
            print('%-14s MANCA' % nome)
            continue
        md5, byte, righe = impronta(p)
        vivo[nome] = md5
        print('%-14s %s  %7d byte  %5d righe' % (nome, md5[:12], byte, righe))

    if atteso:
        md5 = vivo.get('Gioco.s')
        if md5 is None:
            print('\nGioco.s non c\'e\': niente da confrontare.')
            return 1
        if md5.startswith(atteso.lower()):
            print('\nGioco.s CORRISPONDE all\'impronta attesa %s.' % atteso)
            return esito
        print('\nGioco.s NON corrisponde: atteso %s, trovato %s.'
              % (atteso, md5[:len(atteso)]))
        print('Il file sul disco non e\' quello della consegna. Prima di')
        print('toccare altro: chiudere la scheda di Gioco.s nell\'editor')
        print('(o File > Revert File), poi rileggerlo.')
        # se e' tornato indietro, di solito coincide con una copia nota
        cerca_copie = True
        esito = 1

    if cerca_copie:
        md5 = vivo.get('Gioco.s')
        elenco = elenco_copie()
        if not elenco:
            print('\nNessuna copia Gioco.s.prima-* in %s/ ne\' accanto al sorgente.'
                  % copie.CARTELLA)
            return esito
        print('\ncopie di sicurezza:')
        for p in elenco:
            m, b, r = impronta(p)
            nota = '   <== E\' QUESTA, il file e\' tornato indietro' \
                if m == md5 else ''
            print('  %-44s %s  %7d byte%s'
                  % (os.path.relpath(p, RADICE), m[:12], b, nota))
    return esito


if __name__ == '__main__':
    sys.exit(main())
