#!/usr/bin/env python3
# ============================================================================
# sposta-risorse.py - sposta in risorse/ la grafica e i suoni che il build
#                     non usa, lasciando al loro posto quelli che servono.
#
# USO (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
#   python3 tools/sposta-risorse.py              <- SIMULA, non tocca niente
#   python3 tools/sposta-risorse.py --esegui     <- sposta davvero
#   python3 tools/sposta-risorse.py --ripristina <- rimette tutto com'era
#
# ---------------------------------------------------------------------------
# COME DECIDE COSA E' USATO
#
# NON c'e' nessuna lista scritta a mano qui dentro: sarebbe una seconda fonte
# di verita' destinata a divergere dal sorgente al primo incbin nuovo. Lo
# script LEGGE i sorgenti (.s .i .asm .cop nella cartella del progetto), tira
# fuori tutti i percorsi degli incbin, e tratta come "da spostare" tutto il
# resto che sta in grafica/ e suono/.
#
# Il caso che rende necessario questo metodo: suono/Sparo.raw e
# suono/HitPlayer.raw sono file da 16 byte, sembrano spazzatura, e invece sono
# incbin-ati. Una lista fatta a occhio li avrebbe portati via rompendo il
# build. Viceversa suono/EnemyDeath.raw e suono/HitEnemy.raw sono identici a
# vederli, ma nessuno li nomina piu'.
#
# Conservativo per costruzione: se un percorso compare in un incbin, anche
# dentro un blocco condizionale spento o in un include che non viene piu'
# incluso, il file RESTA dov'e'. Tenere per sbaglio un file non costa niente;
# spostarne uno vivo rompe l'assemblaggio.
#
# ---------------------------------------------------------------------------
# LA GUARDIA CHE CONTA
#
# Il modo peggiore in cui questo script puo' sbagliare non e' spostare un file
# di troppo: e' essere lanciato dalla cartella sbagliata. Li' non trova nessun
# sorgente, l'insieme degli usati resta VUOTO, e "tutto il resto" diventa
# tutto. Per questo si ferma se non trova sorgenti, o se gli incbin trovati
# sono meno di INCBIN_MINIMI: una scansione vuota va letta come fallimento,
# non come silenzio.
# ============================================================================
import os, re, sys, shutil

CARTELLE = ('grafica', 'suono')          # dove cercare i file da spostare
DESTINAZIONE = 'risorse'                 # sottocartelle: risorse/grafica, ...
ESTENSIONI_SORGENTE = ('.s', '.i', '.asm', '.cop')
REGISTRO = '_spostati.txt'               # dentro DESTINAZIONE, per il ripristino
INCBIN_MINIMI = 5                        # sotto questa soglia si sospetta un errore


def errore(msg):
    print('ERRORE: ' + msg)
    sys.exit(1)


def sorgenti(radice):
    """I file sorgente nella cartella del progetto (non ricorsivo: gli include
    stanno tutti accanto a Gioco.s)."""
    out = []
    for nome in sorted(os.listdir(radice)):
        p = os.path.join(radice, nome)
        if os.path.isfile(p) and nome.lower().endswith(ESTENSIONI_SORGENTE):
            out.append(p)
    return out


def percorsi_incbin(file_sorgenti):
    """Tutti i percorsi citati da un incbin, normalizzati.
    Ritorna (insieme_di_percorsi, elenco_per_diagnostica)."""
    rx = re.compile(r'^\s*incbin\s+"([^"]+)"', re.IGNORECASE | re.MULTILINE)
    usati, dettaglio = set(), []
    for p in file_sorgenti:
        # latin-1 non fallisce mai: qui interessano solo i percorsi, che sono ASCII.
        # (Startup2.i NON e' UTF-8, e leggerlo in UTF-8 fermerebbe lo script.)
        with open(p, encoding='latin-1') as f:
            testo = f.read()
        for m in rx.finditer(testo):
            rel = m.group(1).replace('\\', '/')
            usati.add(rel.lower())
            dettaglio.append((os.path.basename(p), rel))
    return usati, dettaglio


def indice(radice):
    """Mappa 'cartella/nome' MINUSCOLO -> (cartella, nome vero, dimensione).
    Esiste perche' Windows non distingue le maiuscole e altri filesystem si':
    senza un indice unico, confrontare i percorsi in minuscolo e poi cercare il
    file con quel nome fa dire 'MANCA' su un file che c'e'. Un controllo che
    da' falsi allarmi e' peggio di nessun controllo, quindi il confronto e la
    ricerca passano tutti e due da qui."""
    idx = {}
    for cart in CARTELLE:
        d = os.path.join(radice, cart)
        if not os.path.isdir(d):
            print('  (cartella %s assente, salto)' % cart)
            continue
        for nome in sorted(os.listdir(d)):
            p = os.path.join(d, nome)
            if os.path.isfile(p):
                idx[('%s/%s' % (cart, nome)).lower()] = (cart, nome, os.path.getsize(p))
    return idx


def da_spostare(idx, usati):
    """I file presenti che nessun incbin nomina."""
    return [idx[k] for k in sorted(idx) if k not in usati]


def mancanti(radice, idx, usati):
    """Gli incbin che puntano a un file che non c'e'."""
    fuori = []
    for u in sorted(usati):
        if u in idx:
            continue
        # puo' puntare fuori da CARTELLE: allora si guarda direttamente
        if os.path.isfile(os.path.join(radice, *u.split('/'))):
            continue
        fuori.append(u)
    return fuori


def main():
    radice = os.getcwd()
    modo = sys.argv[1] if len(sys.argv) > 1 else ''
    if modo not in ('', '--esegui', '--ripristina'):
        errore('argomento non riconosciuto: %s (usa --esegui o --ripristina)' % modo)

    if modo == '--ripristina':
        ripristina(radice)
        return

    # ---- 1. da dove nasce la verita': i sorgenti -------------------------
    srcs = sorgenti(radice)
    if not srcs:
        errore('nessun sorgente %s in questa cartella.\n'
               '       Lo script va lanciato DALLA cartella Megagame:\n'
               '         cd "...\\Megagame"  e poi  py tools\\sposta-risorse.py'
               % '/'.join(ESTENSIONI_SORGENTE))
    usati, dettaglio = percorsi_incbin(srcs)
    if len(usati) < INCBIN_MINIMI:
        errore('trovati solo %d incbin in %d sorgenti: troppo pochi, qualcosa non\n'
               '       torna. Mi fermo invece di spostare mezzo progetto.'
               % (len(usati), len(srcs)))

    print('Sorgenti letti: %d (%s)' % (len(srcs), ', '.join(os.path.basename(s) for s in srcs)))
    idx = indice(radice)
    print('File nominati da un incbin: %d' % len(usati))
    for u in sorted(usati):
        chi = ', '.join(sorted({c for c, r in dettaglio if r.lower() == u}))
        # si mostra il nome VERO su disco, non quello normalizzato
        vero = '%s/%s' % (idx[u][0], idx[u][1]) if u in idx else u
        print('   RESTA  %-32s (%s)' % (vero, chi))

    persi = mancanti(radice, idx, usati)
    if persi:
        print()
        print('ATTENZIONE: questi incbin puntano a file che non esistono.')
        print('Non blocca lo spostamento, ma il build non assembla:')
        for m in persi:
            print('   MANCA  %s' % m)

    # ---- 2. tutto il resto ------------------------------------------------
    fuori = da_spostare(idx, usati)
    print()
    if not fuori:
        print('Niente da spostare: in %s non c\'e\' nessun file inutilizzato.'
              % ' e '.join(CARTELLE))
        return
    tot = sum(s for _, _, s in fuori)
    print('Da spostare in %s/: %d file, %.1f KB' % (DESTINAZIONE, len(fuori), tot / 1024.0))
    cart_prec = None
    for cart, nome, size in fuori:
        if cart != cart_prec:
            print('   %s/' % cart)
            cart_prec = cart
        print('      %-28s %8d byte' % (nome, size))

    if modo != '--esegui':
        print()
        print('SIMULAZIONE: non ho spostato niente.')
        print('Per farlo davvero:  py tools\\sposta-risorse.py --esegui')
        return

    # ---- 3. spostamento, con registro per tornare indietro ---------------
    righe = []
    for cart, nome, _ in fuori:
        src = os.path.join(radice, cart, nome)
        dcart = os.path.join(radice, DESTINAZIONE, cart)
        dst = os.path.join(dcart, nome)
        if os.path.exists(dst):
            errore('esiste gia\' %s.\n'
                   '       Non sovrascrivo niente: svuota o rinomina la destinazione.'
                   % os.path.relpath(dst, radice))
        os.makedirs(dcart, exist_ok=True)
        shutil.move(src, dst)
        righe.append('%s/%s' % (cart, nome))
    reg = os.path.join(radice, DESTINAZIONE, REGISTRO)
    with open(reg, 'a', encoding='utf-8') as f:
        for r in righe:
            f.write(r + '\n')
    print()
    print('Spostati %d file. Registro in %s/%s.' % (len(righe), DESTINAZIONE, REGISTRO))
    print('Per tornare indietro:  py tools\\sposta-risorse.py --ripristina')


def ripristina(radice):
    reg = os.path.join(radice, DESTINAZIONE, REGISTRO)
    if not os.path.isfile(reg):
        errore('nessun registro in %s: non c\'e\' niente da ripristinare.'
               % os.path.relpath(reg, radice))
    with open(reg, encoding='utf-8') as f:
        righe = [r.strip() for r in f if r.strip()]
    fatti, saltati = 0, []
    for rel in righe:
        cart, nome = rel.split('/', 1)
        src = os.path.join(radice, DESTINAZIONE, cart, nome)
        dst = os.path.join(radice, cart, nome)
        if not os.path.isfile(src):
            saltati.append(rel + ' (non e\' piu\' in %s)' % DESTINAZIONE)
            continue
        if os.path.exists(dst):
            saltati.append(rel + ' (ne esiste gia\' uno al posto originale)')
            continue
        shutil.move(src, dst)
        fatti += 1
    print('Rimessi al loro posto: %d file.' % fatti)
    for s in saltati:
        print('   SALTATO  %s' % s)
    if fatti and not saltati:
        os.remove(reg)
        print('Registro svuotato.')
        # e le cartelle rimaste vuote, cosi' il ripristino e' davvero completo.
        # Solo se VUOTE: se ci hai messo dentro qualcos'altro, resta dov'e'.
        for cart in CARTELLE + ('',):
            d = os.path.join(radice, DESTINAZIONE, cart)
            try:
                os.rmdir(d)
            except OSError:
                pass
    elif saltati:
        print('Registro lasciato dov\'e\': ci sono voci da guardare a mano.')


if __name__ == '__main__':
    main()
