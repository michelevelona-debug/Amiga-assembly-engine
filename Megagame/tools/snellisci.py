#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# snellisci.py - toglie i commenti dal sorgente per la copia che va sull'Amiga.
#
# USO (dalla cartella Megagame):
#     python3 tools/snellisci.py              scrive in snello/
#     python3 tools/snellisci.py --rapporto   dice solo quanto si risparmia
#
# PERCHE'
# Gioco.s e' commentato al 70%: il codice vero e' un quarto del file. Sul PC
# quei commenti servono, sull'Amiga no - Devpac li legge, li scarta e intanto
# ha impiegato il tempo a caricarli, e il file ci mette a passare per il
# trasferimento. Togliendoli il sorgente passa da 334 a 89 KB.
#
# LA COPIA SNELLA E' UN PRODOTTO, NON UN SORGENTE. Si rigenera, non si edita:
# una modifica fatta li' dentro sparisce alla prima rigenerazione. Il sorgente
# resta uno solo, quello commentato.
#
# ATTENZIONE AL BUILD. Il build assembla TUTTI i .s della cartella e linka tutti
# gli .o: se lo script di build guarda anche nelle sottocartelle, snello/Gioco.s
# diventa un SECONDO programma completo, con dentro un'altra copia di ptplayer, e
# il linker si ferma su "Global symbol _mt_install is already defined". Prima di
# usare snello/ va guardato come il build elenca i sorgenti; in caso, la cartella
# va tenuta fuori dall'albero del progetto.
#
# COSA GARANTISCE
# Il codice esce IDENTICO BYTE PER BYTE a meno dei commenti, e lo script se lo
# verifica prima di scrivere: se il controllo non torna non scrive niente.
# Il controllo NON confronta l'uscita con se stessa - sarebbe una guardia che
# passa sempre. Sono DUE implementazioni scritte in modo diverso (una scansione
# a mano e una espressione regolare) che devono concordare sul punto di taglio,
# piu' la prova che ogni riga uscita e' un PREFISSO di quella da cui viene:
# cosi' un carattere di codice non puo' essere cambiato ne' aggiunto.
# Le due strade divergerebbero proprio sui casi difficili, quindi il fatto che
# concordino su tutto il sorgente dice che quei casi non ci sono.
#
# IL PUNTO E VIRGOLA DENTRO UNA STRINGA NON E' UN COMMENTO. incbin "a;b" e
# dc.b 'ciao; mondo' hanno un ';' che appartiene al dato. Il taglio quindi non
# e' uno split(';'): e' una scansione che conta gli apici.
# ============================================================================
import os, sys

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEST = os.path.join(RADICE, 'snello')

# ptplayer.i NON si tocca: e' di Frank Wille, si copia com'e'.
INTATTI = {'ptplayer.i'}


def taglia(riga):
    """La riga senza il commento. None se la riga sparisce del tutto."""
    s = riga.lstrip()
    if s.startswith(';') or s.startswith('*'):
        return None                      # riga di solo commento
    apice = None
    for i, c in enumerate(riga):
        if apice:
            if c == apice:
                apice = None
        elif c in '"\'':
            apice = c
        elif c == ';':
            riga = riga[:i]
            break
    riga = riga.rstrip()
    return riga if riga else None        # una riga vuota non serve a Devpac


def snellisci(testo):
    fuori = []
    for riga in testo.split('\n'):
        r = taglia(riga)
        if r is not None:
            fuori.append(r)
    return '\n'.join(fuori) + '\n'


import re

# Seconda implementazione, scritta in un altro modo apposta: taglia con una
# espressione regolare invece che con una scansione a mano. Serve a controllare
# la prima, e per farlo deve essere INDIPENDENTE - confrontare snellisci() con
# se stessa e' una guardia finta che passa sempre.
_STRINGA = re.compile(r'"[^"]*"|\'[^\']*\'')

def _taglio_regex(riga):
    """Posizione del ';' che apre il commento, o None. Neutralizza prima il
    contenuto delle stringhe sostituendolo con spazi, cosi' un ';' li' dentro
    non si vede piu'."""
    finta = _STRINGA.sub(lambda m: ' ' * len(m.group(0)), riga)
    i = finta.find(';')
    return None if i < 0 else i


def verifica(testo, prodotto):
    """Due controlli, e nessuno dei due usa snellisci().
    1. ogni riga uscita deve essere un PREFISSO della riga da cui viene: prova
       che si e' solo troncato, mai cambiato o aggiunto un carattere;
    2. il punto di taglio deve coincidere con quello che trova la regex.
    Ritorna None se va bene, altrimenti la riga che non torna."""
    dentro = testo.split('\n')
    fuori = prodotto.split('\n')
    if fuori and fuori[-1] == '':
        fuori = fuori[:-1]
    k = 0
    for n, riga in enumerate(dentro, 1):
        s = riga.lstrip()
        if s.startswith(';') or s.startswith('*'):
            continue                     # riga di solo commento: sparisce
        i = _taglio_regex(riga)
        atteso = (riga if i is None else riga[:i]).rstrip()
        if not atteso:
            continue                     # riga vuota o solo commento in coda
        if k >= len(fuori):
            return 'riga %d persa: %r' % (n, atteso)
        if fuori[k] != atteso:
            return 'riga %d: la scansione da %r, la regex da %r' % (n, fuori[k], atteso)
        if not riga.startswith(fuori[k]):
            return 'riga %d: l\'uscita non e\' un prefisso dell\'entrata' % n
        k += 1
    if k != len(fuori):
        return 'in uscita ci sono %d righe in piu\'' % (len(fuori) - k)
    return None


def main():
    solo_rapporto = '--rapporto' in sys.argv
    if not solo_rapporto:
        os.makedirs(DEST, exist_ok=True)

    nomi = ['Gioco.s'] + sorted(f for f in os.listdir(RADICE)
                                if f.endswith(('.i', '.cop')))
    ta = tb = 0
    print('%-16s %9s %9s   %s' % ('file', 'prima', 'dopo', 'risparmio'))
    for n in nomi:
        src = os.path.join(RADICE, n)
        if not os.path.isfile(src):
            continue
        grezzo = open(src, 'rb').read()
        if n in INTATTI:
            fuori = grezzo
            nota = 'intatto (terze parti)'
        else:
            # latin-1 come byte: Startup2.i non e' UTF-8 e decodificarlo lo rompe
            testo = grezzo.decode('latin-1')
            prodotto = snellisci(testo)
            guaio = verifica(testo, prodotto)
            if guaio:
                print('  %s: %s -- non scrivo niente' % (n, guaio))
                return 1
            fuori = prodotto.encode('latin-1')
            nota = '%.0f%%' % (100.0 * (len(grezzo) - len(fuori)) / max(1, len(grezzo)))
        ta += len(grezzo); tb += len(fuori)
        print('%-16s %9d %9d   %s' % (n, len(grezzo), len(fuori), nota))
        if not solo_rapporto:
            open(os.path.join(DEST, n), 'wb').write(fuori)
    print('%-16s %9d %9d   %.0f%% in meno (%.0f KB risparmiati)'
          % ('TOTALE', ta, tb, 100.0*(ta-tb)/ta, (ta-tb)/1024.0))
    if not solo_rapporto:
        print('\nscritti in %s/ - e\' la copia da portare sull\'Amiga.' %
              os.path.relpath(DEST, RADICE))
        print('NON modificarla: si rigenera da qui a ogni cambio del sorgente.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
