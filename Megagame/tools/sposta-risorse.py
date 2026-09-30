#!/usr/bin/env python3
# ============================================================================
# sposta-risorse.py - lascia in RADICE, grafica/ e suono/ soltanto i file che
#                     servono a far andare il gioco. Tutto il resto in
#                     risorse/, le copie di sicurezza in backup/.
#
# USO (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
#   python3 tools/sposta-risorse.py              <- SIMULA, non tocca niente
#   python3 tools/sposta-risorse.py --esegui     <- sposta davvero
#   python3 tools/sposta-risorse.py --ripristina <- disfa l'ULTIMA esecuzione
#   python3 tools/sposta-risorse.py --ripristina --tutto  <- disfa tutte
#
# L'INVARIANTE, che e' il motivo per cui questo script esiste:
#
#   i file di radice + grafica/ + suono/ = ESATTAMENTE quelli che servono
#   al build. Niente di piu'.
#
# Cosi' quelle tre cartelle si possono leggere come l'elenco dei pezzi del
# gioco, e un file che non si riconosce e' una notizia invece di rumore.
#
# ---------------------------------------------------------------------------
# COME DECIDE COSA E' USATO
#
# NON c'e' nessuna lista scritta a mano qui dentro: sarebbe una seconda fonte
# di verita' destinata a divergere dal sorgente al primo incbin nuovo. Lo
# script LEGGE i sorgenti (.s .i .asm .cop in radice) e tira fuori tutti i
# percorsi che compaiono in un `incbin` O in un `include`. Quelli restano; il
# resto se ne va.
#
# Il caso che rende necessario questo metodo: suono/Sparo.raw e
# suono/HitPlayer.raw sono file da 16 byte, sembrano spazzatura, e invece sono
# incbin-ati. Una lista fatta a occhio li avrebbe portati via rompendo il
# build. Viceversa suono/EnemyDeath.raw e suono/HitEnemy.raw sono identici a
# vederli, ma nessuno li nomina piu'.
#
# Conservativo per costruzione: se un percorso compare in un incbin o in un
# include, anche dentro un blocco condizionale spento o in un file che non
# viene piu' incluso, il file RESTA dov'e'. Tenere per sbaglio un file non
# costa niente; spostarne uno vivo rompe l'assemblaggio.
#
# ---------------------------------------------------------------------------
# LE DUE GUARDIE CHE CONTANO
#
# 1. **UN SORGENTE NON SI SPOSTA MAI.** Un file con un'estensione che il build
#    assembla o include (.s .i .asm .cop) resta in radice qualunque cosa dica
#    l'analisi, anche se nessuno lo nomina. E' la rete sotto tutto il resto:
#    il peggio che questo script puo' fare e' portare via un PNG, e per quello
#    c'e' --ripristina. Un sorgente che nessuno include viene SEGNALATO, non
#    spostato, perche' la decisione non e' meccanica (vedi la nota sui .s in
#    radice piu' sotto).
#
# 2. Il modo peggiore in cui questo script puo' sbagliare non e' spostare un
#    file di troppo: e' essere lanciato dalla cartella sbagliata. Li' non
#    trova nessun sorgente, l'insieme degli usati resta VUOTO, e "tutto il
#    resto" diventa tutto. Per questo si ferma se non trova sorgenti, o se i
#    riferimenti trovati sono meno di RIFERIMENTI_MINIMI: una scansione vuota
#    va letta come fallimento, non come silenzio.
#
# I .s IN RADICE. Il build assembla TUTTI i .s della cartella e linka tutti
# gli .o, quindi un secondo .s accanto a Gioco.s non e' un file di prova: e'
# un secondo programma. L'entrypoint vero lo dice `.vscode/tasks.json`, e lo
# script lo legge da la' per poter segnalare gli altri.
# ============================================================================
import json, os, re, sys, shutil, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import copie

# Le cartelle che devono contenere solo il necessario. '' e' la RADICE.
CARTELLE = ('', 'grafica', 'suono')
DESTINAZIONE = 'risorse'                 # sottocartelle: risorse/grafica, ...
ESTENSIONI_SORGENTE = ('.s', '.i', '.asm', '.cop')
REGISTRO = '_spostati.txt'               # dentro DESTINAZIONE, per il ripristino
MARCATORE = '#--- esecuzione'            # apre un gruppo di righe nel registro
RIFERIMENTI_MINIMI = 5                   # sotto questa soglia si sospetta un errore
TASKS = os.path.join('.vscode', 'tasks.json')

# Dove va un file di RADICE che non serve al build. Per grafica/ e suono/ la
# destinazione e' ovvia (risorse/grafica, risorse/suono); per la radice si
# guarda di che materiale e', cosi' un PNG finisce fra i PNG invece che in
# mezzo ai .txt delle mappe. E' la regola 14 applicata a un file sciolto.
ARTE = ('.png', '.xcf', '.psd', '.iff', '.ilbm', '.gif', '.jpg', '.jpeg',
        '.bmp', '.pal', '.fnt', '.raw', '.lbm')
SUONI = ('.mod', '.wav', '.aiff', '.8svx', '.iff-8svx')


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


def chiave(cart, nome):
    """La chiave dell'indice, MINUSCOLA e nella forma degli include: 'nome' per
    un file di radice, 'cartella/nome' per gli altri. Deve combaciare con
    quello che sta scritto fra gli apici di un incbin."""
    return mostra(cart, nome).lower()


def mostra(cart, nome):
    """Lo stesso percorso ma col nome VERO. Da stampare si usa questo, non
    `chiave`: un elenco tutto minuscolo fa credere che lo script rinomini i
    file (`license`, `alieno.png`), e su Windows non si nota subito."""
    return '%s/%s' % (cart, nome) if cart else nome


def riferimenti(file_sorgenti):
    """Tutti i percorsi citati da un `incbin` O da un `include`, normalizzati.

    L'`include` c'e' insieme all'incbin perche' l'invariante adesso copre la
    radice: senza di lui Startup2.i, Testo.i, ScrollHW.i e gli altri sarebbero
    orfani da portare via, e sono il gioco. Ritorna
    (insieme_di_percorsi, elenco_per_diagnostica)."""
    rx = re.compile(r'^\s*(incbin|include)\s+"([^"]+)"',
                    re.IGNORECASE | re.MULTILINE)
    usati, dettaglio = set(), []
    for p in file_sorgenti:
        # latin-1 non fallisce mai: qui interessano solo i percorsi, che sono ASCII.
        # (Startup2.i NON e' UTF-8, e leggerlo in UTF-8 fermerebbe lo script.)
        with open(p, encoding='latin-1') as f:
            testo = f.read()
        for m in rx.finditer(testo):
            rel = m.group(2).replace('\\', '/')
            usati.add(rel.lower())
            dettaglio.append((os.path.basename(p), rel))
    return usati, dettaglio


def entrypoint(radice):
    """Il sorgente da cui parte il programma, LETTO da .vscode/tasks.json.

    Serve solo a segnalare gli altri .s di radice, e se il file non c'e' o e'
    fatto in un altro modo si rinuncia alla segnalazione: meglio un controllo
    in meno che un controllo che indovina."""
    p = os.path.join(radice, TASKS)
    if not os.path.isfile(p):
        return None
    try:
        with open(p, encoding='utf-8-sig') as f:
            d = json.load(f)
        for t in d.get('tasks', []):
            e = t.get('vlink', {}).get('entrypoint')
            if e:
                return e.lower()
    except (ValueError, AttributeError):
        return None
    return None


def indice(radice):
    """Mappa chiave MINUSCOLA -> (cartella, nome vero, dimensione).
    Esiste perche' Windows non distingue le maiuscole e altri filesystem si':
    senza un indice unico, confrontare i percorsi in minuscolo e poi cercare il
    file con quel nome fa dire 'MANCA' su un file che c'e'. Un controllo che
    da' falsi allarmi e' peggio di nessun controllo, quindi il confronto e la
    ricerca passano tutti e due da qui."""
    idx = {}
    for cart in CARTELLE:
        d = os.path.join(radice, cart) if cart else radice
        if not os.path.isdir(d):
            print('  (cartella %s assente, salto)' % cart)
            continue
        for nome in sorted(os.listdir(d)):
            p = os.path.join(d, nome)
            if os.path.isfile(p):
                idx[chiave(cart, nome)] = (cart, nome, os.path.getsize(p))
    return idx


def destinazione_di(cart, nome):
    """La cartella di arrivo, relativa alla radice. Vedi ARTE/SUONI in testa."""
    if cart:
        return os.path.join(DESTINAZIONE, cart)
    est = os.path.splitext(nome)[1].lower()
    if est in ARTE:
        return os.path.join(DESTINAZIONE, 'grafica')
    if est in SUONI:
        return os.path.join(DESTINAZIONE, 'suono')
    return DESTINAZIONE


def da_spostare(radice, idx, usati, entry):
    """I file che nessun incbin e nessun include nomina, divisi in TRE mucchi.

    1. `fuori` - materiale: se ne va in risorse/.
    2. `copie_trovate` - LE COPIE DI SICUREZZA NON VANNO IN risorse/. Sono
       orfane per l'incbin esattamente come un PNG sorgente, ma non sono la
       stessa cosa: `risorse/` e' il materiale da aprire a mano, `backup/` e'
       la roba da cui si torna indietro. Mescolarle vuol dire che fra un anno,
       in risorse/grafica/, un .iff e un .iff.piatto stanno accanto e non si sa
       piu' quale dei due si apre. Chi le raduna e'
       `py tools\\copie.py --raduna`, e la regola che decide cosa E' una copia
       sta in un posto solo, `copie.e_copia`.
    3. `sorgenti_orfani` - un .s/.i/.asm/.cop che nessuno include. NON si
       sposta (guardia 1): si segnala, perche' in radice un .s in piu' e' un
       secondo programma per il build e la cosa giusta da farne la decide chi
       sa cos'era."""
    fuori, copie_trovate, sorgenti_orfani = [], [], []
    for k in sorted(idx):
        if k in usati:
            continue
        cart, nome, size = idx[k]
        if nome.lower().endswith(ESTENSIONI_SORGENTE):
            if k != entry:
                sorgenti_orfani.append(idx[k])
            continue
        if copie.e_copia(nome, os.path.join(radice, cart) if cart else radice):
            copie_trovate.append(idx[k])
        else:
            fuori.append(idx[k])
    return fuori, copie_trovate, sorgenti_orfani


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
    argv = sys.argv[1:]
    for a in argv:
        if a not in ('--esegui', '--ripristina', '--tutto'):
            errore('argomento non riconosciuto: %s\n'
                   '       usa --esegui, --ripristina, --ripristina --tutto' % a)
    if '--tutto' in argv and '--ripristina' not in argv:
        errore('--tutto vale solo insieme a --ripristina.')
    modo = '--ripristina' if '--ripristina' in argv else \
           ('--esegui' if '--esegui' in argv else '')

    if modo == '--ripristina':
        ripristina(radice, '--tutto' in argv)
        return

    # ---- 1. da dove nasce la verita': i sorgenti -------------------------
    srcs = sorgenti(radice)
    if not srcs:
        errore('nessun sorgente %s in questa cartella.\n'
               '       Lo script va lanciato DALLA cartella Megagame:\n'
               '         cd "...\\Megagame"  e poi  py tools\\sposta-risorse.py'
               % '/'.join(ESTENSIONI_SORGENTE))
    usati, dettaglio = riferimenti(srcs)
    if len(usati) < RIFERIMENTI_MINIMI:
        errore('trovati solo %d fra incbin e include in %d sorgenti: troppo\n'
               '       pochi, qualcosa non torna. Mi fermo invece di spostare\n'
               '       mezzo progetto.' % (len(usati), len(srcs)))

    print('Sorgenti letti: %d (%s)' % (len(srcs), ', '.join(os.path.basename(s) for s in srcs)))
    idx = indice(radice)
    entry = entrypoint(radice)
    print('File nominati da un incbin o da un include: %d' % len(usati))
    if entry:
        print('Entrypoint da %s: %s' % (TASKS, entry))
    for u in sorted(usati):
        chi = ', '.join(sorted({c for c, r in dettaglio if r.lower() == u}))
        # si mostra il nome VERO su disco, non quello normalizzato
        vero = mostra(*idx[u][:2]) if u in idx else u
        print('   RESTA  %-32s (%s)' % (vero, chi))
    if entry and entry in idx:
        print('   RESTA  %-32s (entrypoint del build)' % entry)

    persi = mancanti(radice, idx, usati)
    if persi:
        print()
        print('ATTENZIONE: questi incbin/include puntano a file che non esistono.')
        print('Non blocca lo spostamento, ma il build non assembla:')
        for m in persi:
            print('   MANCA  %s' % m)

    # ---- 2. tutto il resto ------------------------------------------------
    fuori, copie_trovate, orfani = da_spostare(radice, idx, usati, entry)
    if copie_trovate:
        print()
        print('COPIE DI SICUREZZA: %d file. Non le tocco, non vanno in %s/.'
              % (len(copie_trovate), DESTINAZIONE))
        for cart, nome, size in copie_trovate:
            print('   COPIA  %-38s %9d byte' % (mostra(cart, nome), size))
        # L'ORDINE CONTA, e conta in un modo che non si indovina: una copia col
        # suffisso libero (parallasse.raw.alberi-secchi) si riconosce perche'
        # l'ORIGINALE le sta accanto. Se --esegui porta prima via l'originale in
        # risorse/, quella copia non e' piu' riconoscibile e resta in grafica/.
        print('   PRIMA di --esegui:  py tools\\copie.py --raduna --esegui')
        print('   (poi si rilancia questo: dopo il raduno l\'elenco e\' pulito)')
    if orfani:
        print()
        print('SORGENTI CHE NESSUNO INCLUDE: %d. NON li sposto (un sorgente non'
              % len(orfani))
        print('si sposta mai), ma in radice un .s in piu\' e\' un SECONDO')
        print('programma per il build, con dentro un\'altra copia di ptplayer:')
        for cart, nome, size in orfani:
            print('   ORFANO %-38s %9d byte' % (mostra(cart, nome), size))
        print('   Da guardare a mano: o serve e va incluso, o va in %s/.'
              % copie.CARTELLA)
    print()
    if not fuori:
        print('Niente da spostare: in radice, grafica/ e suono/ non c\'e\' nessun')
        print('file che il build non usi.')
        return
    tot = sum(s for _, _, s in fuori)
    print('Da spostare in %s/: %d file, %.1f KB' % (DESTINAZIONE, len(fuori), tot / 1024.0))
    for cart, nome, size in fuori:
        print('   %-38s -> %s/  %9d byte'
              % (mostra(cart, nome), destinazione_di(cart, nome).replace(os.sep, '/'),
                 size))

    if modo != '--esegui':
        print()
        print('SIMULAZIONE: non ho spostato niente.')
        print('Per farlo davvero:  py tools\\sposta-risorse.py --esegui')
        return

    # ---- 3. spostamento, con registro per tornare indietro ---------------
    # Il registro porta ORIGINE e DESTINAZIONE separate da un TAB, perche' con
    # la radice fra le cartelle la destinazione non si ricava piu' dall'origine.
    # Le righe vecchie (senza tab) si leggono ancora: vedi ripristina().
    righe = []
    for cart, nome, _ in fuori:
        rel_src = os.path.join(cart, nome) if cart else nome
        rel_dst = os.path.join(destinazione_di(cart, nome), nome)
        src = os.path.join(radice, rel_src)
        dst = os.path.join(radice, rel_dst)
        if os.path.exists(dst):
            errore('esiste gia\' %s.\n'
                   '       Non sovrascrivo niente: svuota o rinomina la destinazione.'
                   % rel_dst)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.move(src, dst)
        righe.append('%s\t%s' % (rel_src.replace(os.sep, '/'),
                                 rel_dst.replace(os.sep, '/')))
    reg = os.path.join(radice, DESTINAZIONE, REGISTRO)
    os.makedirs(os.path.dirname(reg), exist_ok=True)
    with open(reg, 'a', encoding='utf-8', newline='\n') as f:
        f.write('%s %s %d file\n'
                % (MARCATORE, time.strftime('%Y-%m-%d %H:%M'), len(righe)))
        for r in righe:
            f.write(r + '\n')
    print()
    print('Spostati %d file. Registro in %s/%s.' % (len(righe), DESTINAZIONE, REGISTRO))
    print('Per tornare indietro:  py tools\\sposta-risorse.py --ripristina')


def ripristina(radice, tutto=False):
    reg = os.path.join(radice, DESTINAZIONE, REGISTRO)
    if not os.path.isfile(reg):
        errore('nessun registro in %s: non c\'e\' niente da ripristinare.'
               % os.path.relpath(reg, radice))
    with open(reg, encoding='utf-8') as f:
        tutte = [r.rstrip('\n') for r in f if r.strip()]

    # IL REGISTRO E' CUMULATIVO, e prima non si vedeva: ci sono dentro anche gli
    # spostamenti di mesi fa. Un --ripristina che disfa tutto rovescia in
    # grafica/ ventisette file del 22 settembre insieme a quelli di oggi, e chi
    # lo lancia per annullare l'ultimo comando non se lo aspetta. Quindi si
    # disfa SOLO L'ULTIMA esecuzione, e per tutto il resto serve --tutto.
    gruppi, testa = [], []
    for r in tutte:
        if r.startswith(MARCATORE):
            gruppi.append([])
        elif gruppi:
            gruppi[-1].append(r)
        else:
            testa.append(r)             # righe senza marcatore: le piu' vecchie
    if tutto:
        righe, resto = testa + [r for g in gruppi for r in g], []
    elif gruppi:
        righe = gruppi[-1]
        resto = testa + [r for g in gruppi[:-1] for r in g]
    else:
        righe, resto = testa, []
        print('Il registro non ha marcatori di esecuzione: e\' tutto di prima')
        print('che ci fossero, quindi lo disfo tutto (%d voci).' % len(righe))
    if resto:
        print('Disfo l\'ultima esecuzione: %d file. Nel registro ce ne restano'
              % len(righe))
        print('%d di esecuzioni precedenti; per quelli serve --tutto.' % len(resto))

    fatti, saltati, cartelle_toccate = 0, [], set()
    for riga in righe:
        # DUE forme, e la vecchia deve continuare a funzionare: le righe scritte
        # prima che la radice entrasse nell'invariante sono un solo campo
        # 'cartella/nome', e la destinazione era per definizione risorse/quello.
        if '\t' in riga:
            rel_src, rel_dst = riga.split('\t', 1)
        else:
            rel_src, rel_dst = riga, '%s/%s' % (DESTINAZIONE, riga)
        src = os.path.join(radice, *rel_dst.split('/'))
        dst = os.path.join(radice, *rel_src.split('/'))
        if not os.path.isfile(src):
            saltati.append(rel_src + ' (non e\' piu\' in %s)' % DESTINAZIONE)
            continue
        if os.path.exists(dst):
            saltati.append(rel_src + ' (ne esiste gia\' uno al posto originale)')
            continue
        os.makedirs(os.path.dirname(dst) or radice, exist_ok=True)
        shutil.move(src, dst)
        cartelle_toccate.add(os.path.dirname(src))
        fatti += 1
    print('Rimessi al loro posto: %d file.' % fatti)
    for s in saltati:
        print('   SALTATO  %s' % s)
    if fatti and not saltati:
        if resto:
            # non si svuota: si riscrive con quello che NON si e' disfatto, se no
            # le esecuzioni precedenti perdono il modo di tornare indietro.
            with open(reg, 'w', encoding='utf-8', newline='\n') as f:
                for r in resto:
                    f.write(r + '\n')
            print('Registro riscritto con le %d voci piu\' vecchie.' % len(resto))
        else:
            os.remove(reg)
            print('Registro svuotato.')
        # e le cartelle rimaste vuote, cosi' il ripristino e' davvero completo.
        # Solo se VUOTE: se ci hai messo dentro qualcos'altro, resta dov'e'.
        # Dalla piu' profonda alla piu' corta, se no la madre non si svuota mai.
        for d in sorted(cartelle_toccate, key=len, reverse=True) + \
                [os.path.join(radice, DESTINAZIONE)]:
            try:
                os.rmdir(d)
            except OSError:
                pass
    elif saltati:
        print('Registro lasciato dov\'e\': ci sono voci da guardare a mano.')


if __name__ == '__main__':
    main()
