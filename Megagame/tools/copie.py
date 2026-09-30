#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# copie.py - DOVE vanno le copie di sicurezza, e cosa E' una copia.
#
# USO (dalla cartella Megagame):
#   py tools\copie.py              elenca le copie e dove andrebbero
#   py tools\copie.py --raduna     le stesse, ma SIMULA lo spostamento
#   py tools\copie.py --raduna --esegui    le sposta davvero in backup/
#
# Si importa anche: chi sta per sovrascrivere un file chiama `metti_da_parte`
# e non decide niente sul nome ne' sulla cartella.
#
# PERCHE' ESISTE. La regola 15 del progetto dice "prima di sovrascrivere un
# asset, fanne la copia", e cinque script la rispettano - ognuno a modo suo,
# ognuno lasciando la copia ACCANTO all'originale. Il risultato e' che
# `grafica/` conteneva 15 file di backup mescolati ai 40 che l'assemblatore
# incbinna, e quella cartella ha un invariante preciso da difendere:
#
#   grafica/ = ESATTAMENTE l'insieme dei file che servono alla build
#
# E' l'invariante su cui si regge `tools/sposta-risorse.py`, che estrae i
# percorsi dagli `incbin` e chiama "da spostare" tutto il resto. Con i backup
# la' dentro quel controllo aveva 15 falsi allarmi, e un controllo che da'
# falsi allarmi si smette di leggere.
#
# Quindi le copie hanno una cartella loro, `backup/`, e la destinazione e'
# scritta in UN POSTO SOLO: `CARTELLA` qui sotto. E' la stessa idea di
# `IFF_DIR` in `tools/grafica.py` - chi salva passa il percorso del file e
# basta, l'instradamento non e' un argomento da ricordarsi di passare giusto.
#
# L'ALBERO SI RISPECCHIA: la copia di `grafica/mappa1.raw` va in
# `backup/grafica/mappa1.raw.prima-3`, non in `backup/mappa1.raw.prima-3`.
# Due motivi, il secondo piu' importante del primo: due file con lo stesso
# nome in cartelle diverse non possono collidere, e dalla copia si RISALE al
# posto da cui viene. Una cartella piatta di backup, dopo un anno, e' un
# mucchio di file di cui non si sa piu' dove andavano rimessi.
#
# IL NOME DELLA COPIA NON DEVE MAI FINIRE IN .s (ne' .i, .asm, .cop).
# Il build assembla i sorgenti per estensione e linka tutti gli .o: un secondo
# `Gioco.s` da qualche parte diventa un secondo programma completo, con dentro
# un'altra copia di ptplayer, e il linker si ferma su
# `_mt_install is already defined`. Il suffisso (`Gioco.s.prima-porta`) e'
# quello che tiene la copia fuori dalla vista dell'assemblatore, ed e' per
# questo che qui sotto c'e' una guardia invece di un promemoria.
# NOTA su `.vscode/tasks.json`: l'elenco dei file da assemblare e'
# `*.{s,S,asm,ASM}`, cioe' con UN asterisco, che nella sintassi dei glob di VS
# Code non scende nelle sottocartelle. Se e' davvero cosi', `backup/` sarebbe
# al sicuro anche senza suffisso - ma qui non si puo' lanciare il build, quindi
# e' una lettura e non una misura, e la guardia resta.
#
# COSA E' UNA COPIA. Due forme, entrambe gia' in uso nel progetto:
#   1. `nome.ext.prima-qualcosa`  - Gioco.s.prima-porta, mappa.raw.prima-3,
#      Tiles.raw.prima-51-77, Pannello.raw.prima-rimappa
#   2. `nome.ext.qualcosa` con `nome.ext` ancora presente nella stessa cartella
#      - parallasse.raw.alberi-secchi, alberi_parallasse.raw.piatto,
#        genera-alberi-sprite.py.un-albero
# La seconda forma si riconosce guardando il disco, non un elenco di suffissi
# scritto qui: un elenco sarebbe una seconda fonte di verita' che va stantia al
# primo suffisso nuovo. Per le copie NUOVE vale solo la forma 1, che e' quella
# che `metti_da_parte` produce.
# ============================================================================
import os
import shutil
import sys

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# La destinazione, in un posto solo.
CARTELLA = 'backup'

# Il prefisso del suffisso delle copie nuove: nome.ext.prima-qualcosa, oppure
# nome.ext.prima-3 quando sono numerate.
PREFISSO = 'prima'

# Le estensioni che il build assembla: una copia non puo' finire con una di
# queste. (L'elenco autorevole per il build e' `.vscode/tasks.json`; qui serve
# solo a impedire un nome pericoloso, e i due possono divergere solo verso il
# sicuro - un'estensione in piu' qui vieta un nome che al build non darebbe
# fastidio, non il contrario.)
ASSEMBLATE = ('.s', '.i', '.asm', '.cop')

# Le cartelle in cui `--raduna` va a cercare copie sparse. Non e' ricorsivo e
# non ci sono `backup` ne' `suono`: il primo e' la destinazione, nel secondo
# non e' mai finita una copia. Aggiungerne una qui e' una riga.
CERCA_IN = ('', 'grafica', 'risorse', os.path.join('risorse', 'grafica'),
            'tools')


# ---------------------------------------------------------------------------
# La regola
# ---------------------------------------------------------------------------
def _suffisso(suffisso):
    """Il suffisso completo, col prefisso davanti UNA volta sola.

    ''               -> 'prima'         (poi numerato: 'prima-1', come da sempre)
    'porta'          -> 'prima-porta'
    'prima-rimappa'  -> 'prima-rimappa' (chi lo porta gia' non se lo raddoppia)"""
    s = suffisso.strip('-')
    if s == PREFISSO or s.startswith(PREFISSO + '-'):
        return s
    return PREFISSO + ('-' + s if s else '')


def e_copia(nome, dentro=None):
    """Vero se `nome` e' una copia di sicurezza.

    `dentro` e' la cartella in cui il file sta: serve a riconoscere la forma 2
    (suffisso libero accanto all'originale). Senza `dentro` si riconosce solo
    la forma 1, che e' quella delle copie nuove."""
    if nome.lower().endswith(ASSEMBLATE):
        return False                       # un sorgente non e' una copia
    base, punto, suff = nome.rpartition('.')
    if not punto or not base or '.' not in base:
        return False                       # ci vogliono due punti: nome.ext.suff
    if suff == PREFISSO or suff.startswith(PREFISSO + '-'):
        return True
    if dentro is not None and os.path.isfile(os.path.join(dentro, base)):
        return True
    return False


def destinazione(path):
    """Dove va la copia del file `path`: l'albero rispecchiato sotto backup/.

    Prende il percorso dell'ORIGINALE (non della copia) e torna la cartella,
    non il file: il nome lo compone `metti_da_parte`."""
    p = os.path.abspath(path)
    rel = os.path.relpath(os.path.dirname(p), RADICE)
    if rel.startswith('..'):
        raise ValueError('%s e\' fuori dalla cartella del progetto: non so dove '
                         'metterne la copia' % path)
    if rel == '.':
        return os.path.join(RADICE, CARTELLA)
    return os.path.join(RADICE, CARTELLA, rel)


def metti_da_parte(path, suffisso='', sposta=False, numera=False):
    """Fa la copia di sicurezza di `path` in backup/, e torna il suo percorso.

    `suffisso`  la parte dopo il prefisso: 'porta' da 'Gioco.s.prima-porta'.
                Vuoto piu' `numera` da' la forma storica 'prima-1'.
    `sposta`    True = l'originale si SPOSTA (i suoi byte diventano la copia,
                e chi chiama sta per riscrivere il file da zero);
                False = si COPIA e l'originale resta dov'e'.
    `numera`    True = al suffisso si attacca il primo numero libero, per chi
                si rilancia piu' volte (mappa.py, il foglio delle tile).

    Torna None se `path` non esiste: non e' un errore, e' il primo giro."""
    if not os.path.isfile(path):
        return None
    suffisso = _suffisso(suffisso)
    dest = destinazione(path)
    nome = os.path.basename(path)
    accanto = os.path.dirname(os.path.abspath(path))

    def libero(s):
        # si guarda in DUE posti: la destinazione e - finche' `--raduna` non e'
        # passato - anche accanto all'originale, dove le copie vecchie stanno
        # ancora. Cosi' due file non finiscono a chiamarsi '.prima-3' volendo
        # dire cose diverse.
        return (not os.path.exists(os.path.join(dest, '%s.%s' % (nome, s)))
                and not os.path.exists(os.path.join(accanto, '%s.%s' % (nome, s))))

    if numera:
        k = 1
        while not libero('%s-%d' % (suffisso, k)):
            k += 1
        suffisso = '%s-%d' % (suffisso, k)
    finale = '%s.%s' % (nome, suffisso)
    if finale.lower().endswith(ASSEMBLATE):
        raise ValueError('la copia si chiamerebbe %s, che il build assemblerebbe '
                         'come sorgente. Cambia suffisso.' % finale)
    os.makedirs(dest, exist_ok=True)
    fuori = os.path.join(dest, finale)
    if sposta:
        os.replace(path, fuori)
    else:
        shutil.copy2(path, fuori)
    return fuori


def dove(path, suffisso):
    """Il percorso della copia di `path` con QUEL suffisso.

    Serve a chi la RILEGGE - gli innesti, che dopo `--togli` confrontano il
    sorgente ripulito con la copia - e deve dare la risposta giusta prima e
    dopo il trasloco: la nuova in `backup/` se c'e' (o se non c'e' da nessuna
    parte), quella vecchia accanto all'originale se e' ancora solo la'.
    Dopo un `metti_da_parte` torna sempre la nuova, quindi chi scrive e chi
    rilegge non possono guardare due file diversi."""
    nome = '%s.%s' % (os.path.basename(path), _suffisso(suffisso))
    nuovo = os.path.join(destinazione(path), nome)
    accanto = os.path.join(os.path.dirname(os.path.abspath(path)), nome)
    if not os.path.isfile(nuovo) and os.path.isfile(accanto):
        return accanto
    return nuovo


def cerca(nome, dentro=''):
    """Le copie di `nome` (es. 'Gioco.s'), in backup/ e accanto all'originale.

    I due posti servono entrambi, e non solo durante il trasloco: una copia
    fatta a mano da Michele finisce accanto al file, ed e' giusto che gli
    strumenti la vedano. Torna percorsi assoluti, ordinati per nome."""
    fuori = []
    for d in (os.path.join(RADICE, CARTELLA, dentro), os.path.join(RADICE, dentro)):
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.startswith(nome + '.') and os.path.isfile(os.path.join(d, f)) \
                    and e_copia(f, d):
                fuori.append(os.path.join(d, f))
    return fuori


# ---------------------------------------------------------------------------
# --raduna: le copie sparse finiscono in backup/
# ---------------------------------------------------------------------------
def _testo_sorgenti():
    """Il testo di tutti i sorgenti, concatenato, per la guardia qui sotto."""
    pezzi = []
    for f in sorted(os.listdir(RADICE)):
        if f.lower().endswith(ASSEMBLATE) and os.path.isfile(os.path.join(RADICE, f)):
            # latin-1 non fallisce mai: qui interessa solo cercare dei nomi.
            with open(os.path.join(RADICE, f), encoding='latin-1') as h:
                pezzi.append(h.read())
    return '\n'.join(pezzi)


def raduna(esegui):
    """Elenca (e con `esegui` sposta) le copie sparse nelle CERCA_IN.

    LA GUARDIA: non si sposta un file il cui nome COMPARE nei sorgenti, in
    qualunque forma - non solo dentro un `incbin`. E' piu' severa della regola
    vera di proposito: tenere per sbaglio una copia dove sta non costa niente,
    portare via un file che il build nomina rompe l'assemblaggio."""
    testo = _testo_sorgenti()
    if not testo:
        print('ERRORE: nessun sorgente %s qui. Lo script va lanciato DALLA'
              % '/'.join(ASSEMBLATE))
        print('        cartella Megagame:  py tools\\copie.py --raduna')
        return 1

    trovate, nominate, dubbie = [], [], []
    for cart in CERCA_IN:
        d = os.path.join(RADICE, cart) if cart else RADICE
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            p = os.path.join(d, f)
            if not os.path.isfile(p):
                continue
            if not e_copia(f, d):
                # QUASI una copia: due punti ma la regola l'ha scartata. Si
                # stampa, perche' il caso vero e' che l'ORIGINALE non c'e' piu':
                # la forma 2 ('nome.ext.suffisso') si riconosce guardando se
                # `nome.ext` sta la' accanto, e cancellato quello le sue copie
                # smettono di essere riconosciute - in silenzio, che e' il modo
                # peggiore. Chi e' nominato nei sorgenti non e' un dubbio.
                if f.count('.') >= 2 and not f.lower().endswith(ASSEMBLATE) \
                        and f not in testo:
                    dubbie.append((cart, f))
                continue
            if f in testo:
                nominate.append((cart, f))
                continue
            trovate.append((cart, f, os.path.getsize(p)))

    if nominate:
        print('NON le tocco, il loro nome compare nei sorgenti:')
        for cart, f in nominate:
            print('   %s' % os.path.join(cart, f))
        print()
    if dubbie:
        print('DA GUARDARE: hanno la forma di una copia ma non lo sono per la')
        print('regola, perche\' l\'originale non sta piu\' accanto a loro - se hai')
        print('lanciato sposta-risorse.py --esegui prima di questo, e\' lui che')
        print('l\'ha portato in risorse/. Se sono copie, rinominale in')
        print('.%s-qualcosa e le prendo.' % PREFISSO)
        for cart, f in dubbie:
            print('   %s' % os.path.join(cart, f))
        print()

    if not trovate:
        print('Nessuna copia fuori posto: %s/ e\' gia\' l\'unico posto dove stanno.'
              % CARTELLA)
        return 0

    tot = sum(s for _, _, s in trovate)
    print('Copie da radunare in %s/: %d file, %.1f KB'
          % (CARTELLA, len(trovate), tot / 1024.0))
    cart_prec = None
    for cart, f, size in trovate:
        if cart != cart_prec:
            print('   %s' % ((cart + os.sep) if cart else '(radice)'))
            cart_prec = cart
        print('      %-38s %9d byte' % (f, size))

    if not esegui:
        print()
        print('SIMULAZIONE: non ho spostato niente.')
        print('Per farlo davvero:  py tools\\copie.py --raduna --esegui')
        return 0

    n = 0
    for cart, f, _ in trovate:
        src = os.path.join(RADICE, cart, f) if cart else os.path.join(RADICE, f)
        dcart = os.path.join(RADICE, CARTELLA, cart)
        dst = os.path.join(dcart, f)
        if os.path.exists(dst):
            print('ERRORE: esiste gia\' %s. Non sovrascrivo niente e mi fermo.'
                  % os.path.relpath(dst, RADICE))
            return 1
        os.makedirs(dcart, exist_ok=True)
        shutil.move(src, dst)
        n += 1
    print()
    print('Radunate %d copie in %s/. L\'albero e\' rispecchiato, quindi da una'
          % (n, CARTELLA))
    print('copia si risale alla cartella da cui viene.')
    return 0


def main():
    argv = sys.argv[1:]
    for a in argv:
        if a not in ('--raduna', '--esegui'):
            print('ERRORE: argomento non riconosciuto: %s' % a)
            return 1
    if '--esegui' in argv and '--raduna' not in argv:
        print('ERRORE: --esegui da solo non fa niente. Vuoi --raduna --esegui.')
        return 1
    if '--raduna' in argv:
        return raduna('--esegui' in argv)
    return raduna(False)


if __name__ == '__main__':
    sys.exit(main())
