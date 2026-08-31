#!/usr/bin/env python3
# ============================================================================
# rimappa-pannello.py - libera voci di palette nel pannello, senza cambiare
#                       un solo pixel di quello che si vede.
#
# USO (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
#   python3 tools/rimappa-pannello.py            <- SIMULA, non tocca niente
#   python3 tools/rimappa-pannello.py --esegui   <- riscrive Pannello.raw
#
# ---------------------------------------------------------------------------
# PERCHE' VA RILANCIATO DOPO OGNI RI-ESPORTAZIONE
#
# Questo script lavora su Pannello.raw, non su Pannello.png. Ri-esportando il
# pannello dall'editor gli indici tornano quelli del PNG e la rimappatura
# sparisce: le voci liberate tornano occupate e i colori nuovi in Pannello.cop
# si vedono addosso all'arte. Quindi: ri-esporti, e SUBITO DOPO rilanci questo.
#
# Per questo la tabella qui sotto contiene TUTTE le rimappature, anche quelle
# gia' fatte in passato: dopo una ri-esportazione vanno rifatte tutte insieme,
# e averle in un posto solo e' l'unico modo di non dimenticarne una.
#
# ---------------------------------------------------------------------------
# COME FUNZIONA
#
# Il pannello usa tutte e sedici le voci, ma alcune portano lo STESSO identico
# colore. Portando i pixel di una sull'altra, la prima resta senza clienti e si
# puo' ridipingere. L'immagine non cambia di un pixel, perche' il colore che
# quei pixel mostravano e quello che mostreranno sono lo stesso.
#
# LA PROVA, CHE E' IL PUNTO DI QUESTO SCRIPT
#
# Non basta dire che i colori sono uguali: si decodifica il pannello PRIMA e
# DOPO con la palette vera, e si confronta pixel per pixel. Se un solo pixel
# cambia colore, lo script non scrive. La palette la legge da Pannello.cop.
#
# Secondo controllo: che dopo la rimappatura gli indici liberati non compaiano
# piu' in nessun pixel. Se ne resta uno, la voce non e' libera e ridipingerla
# si vedrebbe.
#
# ATTENZIONE alla palette letta: se Pannello.cop contiene GIA' i colori nuovi
# (perche' l'hai gia' modificato), le voci liberate non portano piu' il colore
# della sorgente e il confronto fallirebbe a ragione. Per questo lo script
# confronta usando il colore della DESTINAZIONE per entrambe: e' quello che si
# vedra' davvero.
# ============================================================================
import os, re, sys, shutil

RAW        = 'grafica/Pannello.raw'
COP        = 'Pannello.cop'
W, H, PIANI = 320, 80, 4
ROWB       = W // 8
PSZ        = ROWB * H

# indice sorgente -> indice destinazione.
# Ogni riga vale solo se i due indici portano lo stesso colore NELL'ARTE
# originale, cioe' nel PNG da cui esce Pannello.raw.
RIMAPPA = {
    # --- liberate il 29 agosto per la rotella del punteggio ---
    #     2, 3, 4, 5 e 6 portavano tutte $88f
    4: 3,
    5: 3,
    6: 3,
    # --- liberate per i due indicatori di sinistra ---
    #     2 porta lo stesso colore del 3 ($88f)
    #     13 e 14 portano nero come il 15 ($000)
    2: 3,
    13: 15,
    14: 15,
}

# Cosa ci va dopo, per comodita' di chi legge il rapporto.
#
# I colori dell'indicatore sono MISURATI su risorse/grafica/indicatore_anteprima.png,
# che e' l'anteprima colorata dell'arte: non sono scelti qui. La 13 e la 14 sono
# la coppia scura/viva della barra e le riscrive il copper a runtime secondo il
# livello (rampa misurata sulla stessa anteprima):
#     livelli 0..3   ROSSO    $c23 / $f68
#     livelli 4..6   ARANCIO  $e60 / $fb7
#     livelli 7..10  GIALLO   $ea0 / $fe7
# Il valore qui sotto e' solo quello di partenza.
NUOVI = {
    4:  (0x334, 'rotella: grigio scuro   #333344'),
    5:  (0x99a, 'rotella: grigio medio   #9999aa'),
    6:  (0xeee, 'rotella: quasi bianco   #eeeeee'),
    2:  (0x334, 'indicatore: traccia     #38384a'),
    13: (0xc23, 'indicatore: barra scura #c8203c  (rosso, poi la cambia il copper)'),
    14: (0xf68, 'indicatore: barra viva  #ff6e82  (rosso, poi la cambia il copper)'),
}


def errore(msg):
    print('ERRORE: ' + msg)
    sys.exit(1)


def leggi_palette(path):
    """I 16 colori a 12 bit dal blocco copper del pannello."""
    testo = open(path, encoding='latin-1').read()
    val = re.findall(r'\$([0-9a-fA-F]{4})', testo)
    pal = {}
    for i in range(0, len(val) - 1, 2):
        reg = int(val[i], 16)
        if 0x180 <= reg <= 0x1be:
            pal[(reg - 0x180) // 2] = int(val[i + 1], 16)
    return pal


def decodifica(d):
    """Indice di palette di ogni pixel, come lo vede il chipset."""
    out = bytearray(W * H)
    for y in range(H):
        for x in range(W):
            v = 0
            for p in range(PIANI):
                if (d[p * PSZ + y * ROWB + (x >> 3)] >> (7 - (x & 7))) & 1:
                    v |= 1 << p
            out[y * W + x] = v
    return out


def codifica(idx):
    """Dagli indici ai quattro bitplane."""
    d = bytearray(PSZ * PIANI)
    for y in range(H):
        for x in range(W):
            v = idx[y * W + x]
            for p in range(PIANI):
                if (v >> p) & 1:
                    d[p * PSZ + y * ROWB + (x >> 3)] |= 1 << (7 - (x & 7))
    return bytes(d)


def main():
    radice = os.getcwd()
    modo = sys.argv[1] if len(sys.argv) > 1 else ''
    if modo not in ('', '--esegui'):
        errore('argomento non riconosciuto: %s (usa --esegui)' % modo)
    praw, pcop = os.path.join(radice, RAW), os.path.join(radice, COP)
    if not os.path.isfile(praw) or not os.path.isfile(pcop):
        errore('non trovo %s o %s.\n'
               '       Lo script va lanciato DALLA cartella Megagame.' % (RAW, COP))

    d = open(praw, 'rb').read()
    if len(d) != PSZ * PIANI:
        errore('%s e\' %d byte, me ne aspettavo %d (%dx%d a %d piani).'
               % (RAW, len(d), PSZ * PIANI, W, H, PIANI))

    pal = leggi_palette(pcop)
    if len(pal) != 16:
        errore('in %s ho trovato %d colori invece di 16.' % (COP, len(pal)))

    idx = decodifica(d)
    prima = {i: 0 for i in range(16)}
    for v in idx:
        prima[v] += 1

    # --- gia' fatto? -------------------------------------------------------
    da_fare = [s for s in RIMAPPA if prima[s]]
    if not da_fare:
        print('Nessun pixel usa gli indici %s: la rimappatura c\'e\' gia\'.'
              % ', '.join(str(i) for i in sorted(RIMAPPA)))
        print('Non c\'e\' niente da fare.')
        return

    print('Indici usati adesso da %s:' % RAW)
    for i in range(16):
        nota = '  -> diventeranno %d' % RIMAPPA[i] if i in RIMAPPA else ''
        print('   %2d  $%03x  %6d px%s' % (i, pal[i], prima[i], nota))

    # --- il colore che conta e' quello della DESTINAZIONE -------------------
    # Se Pannello.cop e' gia' stato aggiornato, la voce sorgente porta il colore
    # nuovo e confrontarla con la destinazione direbbe "diverso" a ragione. Il
    # confronto giusto e' fra quello che si vede PRIMA (colore sorgente
    # ORIGINALE, che e' quello della destinazione, perche' erano duplicati) e
    # quello che si vedra' DOPO.
    vista = dict(pal)
    for src, dst in RIMAPPA.items():
        vista[src] = pal[dst]

    spostati = sum(prima[i] for i in RIMAPPA)
    print()
    print('Da rimappare: %d pixel su %d.' % (spostati, W * H))

    # --- applica su una copia e verifica -----------------------------------
    nuovo_idx = bytearray(RIMAPPA.get(v, v) for v in idx)
    dopo = {i: 0 for i in range(16)}
    for v in nuovo_idx:
        dopo[v] += 1

    rimasti = [i for i in RIMAPPA if dopo[i]]
    if rimasti:
        errore('dopo la rimappatura le voci %s hanno ancora pixel: non sono\n'
               '       libere e ridipingerle si vedrebbe.' % rimasti)

    diversi = sum(1 for a, b in zip(idx, nuovo_idx) if vista[a] != pal[b])
    print('Pixel che cambierebbero COLORE: %d' % diversi)
    if diversi:
        errore('la rimappatura cambierebbe cio\' che si vede. Non scrivo.')
    print('-> l\'immagine e\' identica pixel per pixel.')

    nuovo = codifica(nuovo_idx)
    if len(nuovo) != len(d):
        errore('la ricodifica ha prodotto %d byte invece di %d.' % (len(nuovo), len(d)))
    if decodifica(nuovo) != nuovo_idx:
        errore('ricodifica e decodifica non tornano. Non scrivo.')

    print()
    print('Voci che restano LIBERE: %s' % ', '.join(str(i) for i in sorted(RIMAPPA)))
    print('Da mettere in %s:' % COP)
    for i in sorted(NUOVI):
        v, desc = NUOVI[i]
        stato = 'gia\' a posto' if pal[i] == v else 'DA CAMBIARE (adesso $%03x)' % pal[i]
        print('   COLOR%02d ($%03x)  ->  $%03x   %-38s %s' % (i, 0x180 + i * 2, v, desc, stato))

    if modo != '--esegui':
        print()
        print('SIMULAZIONE: non ho scritto niente.')
        print('Per farlo davvero:  py tools\\rimappa-pannello.py --esegui')
        return

    # backup numerato: lo script si rilancia a ogni ri-esportazione, quindi il
    # backup non puo' essere uno solo.
    n = 0
    while True:
        backup = '%s.prima-rimappa%s' % (praw, '' if n == 0 else str(n))
        if not os.path.exists(backup):
            break
        n += 1
    shutil.copy2(praw, backup)
    open(praw, 'wb').write(nuovo)
    print()
    print('Scritto %s (%d byte). Originale in %s.'
          % (RAW, len(nuovo), os.path.basename(backup)))
    print('Adesso tocca a %s: le righe qui sopra marcate DA CAMBIARE.' % COP)


if __name__ == '__main__':
    main()
