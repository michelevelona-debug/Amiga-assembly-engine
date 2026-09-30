#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# mappa.py - la mappa si SCRIVE come numeri e si CONVERTE con questo.
#
# USO (dalla cartella Megagame):
#   python3 tools/mappa.py --da-gioco      una volta sola: prende il blocco
#                                          MAPPA: di Gioco.s e ne fa il .txt
#   python3 tools/mappa.py --nuova 72 24   crea un .txt vuoto di quelle tile
#   python3 tools/mappa.py                 il giro normale: txt -> .raw + anteprime
#   python3 tools/mappa.py --riordina      riallinea le colonne del .txt
#   python3 tools/mappa.py --dimensiona 72 11   porta la mappa a quella misura
#   python3 tools/mappa.py --tavola        solo la tavola di riferimento
#   python3 tools/mappa.py --mappa 3       lavora sulla TERZA mappa, cioe' su
#                                          risorse/mappa3.txt -> grafica/mappa3.raw
#
# `--mappa N` vale per ogni altro comando e si combina con tutti: `--mappa 3
# --dimensiona 73 24` ridimensiona la terza. Senza il flag si lavora sulla
# PRIMA, che dal 30 settembre 2026 si chiama `mappa1`: fino a quel giorno era
# `mappa` senza suffisso, ed era l'unica del gruppo a non avere il suo numero.
#
# LA FONTE E' `risorse/mappa1.txt`, UN NUMERO PER TILE (e mappa2, mappa3...).
# Sta in risorse/ e non in grafica/ perche' grafica/ e' solo cio' che
# l'assemblatore incbinna, e perche' non e' un'immagine: e' una tabella che si
# apre e si modifica a mano. Il .raw e' il prodotto, il .txt e' la fonte.
#
# PERCHE' NUMERI E NON UN'IMMAGINE (deciso da Michele il 20 settembre): con i
# numeri si puo' scrivere una tile CHE NON ESISTE ANCORA. In un editor a pixel
# non si puo' dipingere un colore che non c'e', quindi il livello non puo'
# correre avanti all'arte. Qui invece si scrive 112 dove andra' una tile da
# disegnare, e lo strumento la mette nella lista di quelle che mancano - che
# diventa da sola l'elenco del lavoro di grafica da fare.
#
# COSA SI PUO' SCRIVERE IN UNA CASELLA:
#   un numero          0..319, lo slot nel foglio Tiles.raw
#   un nome            una EQU TILE_* di Gioco.s, col prefisso o senza:
#                      `LUCE` e `TILE_LUCE` sono tutti e due la tile 50.
#                      I segnaposto non hanno arte, quindi in mezzo ai numeri
#                      sarebbero invisibili: scritti per nome si vedono.
#   `;` a inizio riga  commento, la riga non conta
#
# QUELLO CHE LO STRUMENTO RIFIUTA (errore, non converte):
#   - un numero fuori da 0..319, che il foglio non puo' contenere;
#   - righe di lunghezza diversa fra loro;
#   - un nome che non e' una EQU TILE_* del sorgente.
# QUELLO CHE SEGNALA E BASTA (avviso, converte lo stesso):
#   - tile usate che non hanno ancora arte -> la lista del lavoro da fare;
#   - tile oltre la fine di TileFlags -> stampa i dc.b da aggiungere.
# La differenza non e' pignoleria: il primo gruppo e' sbagliato, il secondo e'
# solo non ancora finito, e bloccare il secondo vorrebbe dire non poter
# disegnare il livello prima dell'arte, che e' esattamente il punto.
# ============================================================================
import os, re, struct, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import copie
import valori

from PIL import Image, ImageDraw

RADICE = valori.RADICE
# I CINQUE FILE DI UNA MAPPA, instradati da UN posto solo. Dal 29 settembre
# 2026 le mappe sono piu' di una: `mappa` e' la prima (nomi senza suffisso, come
# sono sempre stati), `mappa2` la seconda, e cosi' via. Chi aggiunge una mappa
# non aggiunge cinque percorsi: passa `--mappa N`.
NOME = 'mappa1'
TXT = RAW = ANTEPRIMA = TAVOLA = SAGOMA = None


def percorsi(nome):
    global NOME, TXT, RAW, ANTEPRIMA, TAVOLA, SAGOMA
    NOME = nome
    TXT = os.path.join(RADICE, 'risorse', nome + '.txt')
    RAW = os.path.join(RADICE, 'grafica', nome + '.raw')
    ANTEPRIMA = os.path.join(RADICE, 'risorse', 'grafica', nome + '-arte.png')
    TAVOLA = os.path.join(RADICE, 'risorse', 'grafica', nome + '-tavola.png')
    SAGOMA = os.path.join(RADICE, 'risorse', nome + '-sagoma.txt')


percorsi('mappa1')

TILE = 16
FOGLIO_COLS = 20          # tile per riga in Tiles.raw: lo dice la DIVU #20 di
FOGLIO_PITCH = 40         # DisegnaSfondo, non un commento
FOGLIO_RIGHE = 256
FOGLIO_SLOT = FOGLIO_COLS * (FOGLIO_RIGHE // TILE)      # 320
PIANI = 5

# La stanza dell'originale C64, MISURATA sullo screenshot (autocorrelazione sul
# suolo e sulle piattaforme, scala dai 200 px di altezza del quadro): area di
# gioco 289x129 px con tile da 16, cioe' 18x8 tile.
STANZA_C, STANZA_R = 18, 8
# La NOSTRA finestra: VIS_COLS colonne e BG_VIS_ROWS/16 righe, cioe' 20x11.
# Stanza e schermata sono DUE UNITA' DIVERSE e vanno dette tutte e due ogni
# volta: 24 righe sono 3 stanze ma 2,2 schermate, e "tre" da solo non vuol dire
# niente. I due numeri NON si scrivono qui: sono EQU, e ricopiarle vorrebbe dire
# tenerle in pari a mano. Le mette main() leggendo il sorgente.
VIS_C = VIS_R = None
# Il blocco scelto: 4x3 stanze. Vedi claude/mappa.md.
BLOCCO_C, BLOCCO_R = STANZA_C * 4, STANZA_R * 3


# ---------------------------------------------------------------- sorgente --
def _rami_vivi(righe, tab):
    """Le righe che l'assemblatore vede davvero, valutando i condizionali."""
    pila, fuori = [True], []
    for l in righe:
        c = l.split(';')[0].rstrip()
        m = re.match(r'^\s+IF(NE|EQ|GE|GT|LE|LT)\s+(.+)$', c, re.I)
        if m:
            try:
                vivo = valori._CONDIZIONI[m.group(1).upper()](
                    valori._numero(m.group(2).strip(), tab))
            except Exception:
                vivo = True
            pila.append(pila[-1] and vivo)
            continue
        if re.match(r'^\s+ENDC\b', c, re.I):
            if len(pila) > 1:
                pila.pop()
            continue
        if pila[-1]:
            fuori.append(c)
    return fuori


def palette_gioco(tab):
    """I 32 colori del gioco come (r,g,b), da GamePalHi/GamePalLo."""
    testo = valori._espandi(valori.SORGENTE)
    i_hi = next(i for i, l in enumerate(testo) if l.startswith('GamePalHi:'))
    i_lo = next(i for i, l in enumerate(testo) if l.startswith('GamePalLo:'))
    fine = next(i for i, l in enumerate(testo[i_lo:], i_lo) if 'Ripristino BPLCON3' in l)

    def coppie(blocco):
        out = {}
        for c in _rami_vivi(blocco, tab):
            m = re.search(r'\bdc\.w\s+(.+)$', c, re.I)
            if not m:
                continue
            v = [x.strip() for x in m.group(1).split(',')]
            for k in range(0, len(v) - 1, 2):
                try:
                    reg, val = valori._numero(v[k], tab), valori._numero(v[k + 1], tab)
                except Exception:
                    continue
                if 0x180 <= reg <= 0x1be and not (reg & 1):
                    out[(reg - 0x180) // 2] = val
        return out

    hi, lo = coppie(testo[i_hi:i_lo]), coppie(testo[i_lo:fine])
    pal = []
    for i in range(32):
        h, b = hi.get(i, 0), lo.get(i, 0)
        pal.append((((h >> 8) & 15) << 4 | ((b >> 8) & 15),
                    ((h >> 4) & 15) << 4 | ((b >> 4) & 15),
                    (h & 15) << 4 | (b & 15)))
    return pal


def foglio_tile():
    """Ogni slot del foglio come 16x16 indici di palette."""
    dati = open(os.path.join(RADICE, 'grafica', 'Tiles.raw'), 'rb').read()
    atteso = FOGLIO_PITCH * FOGLIO_RIGHE * PIANI
    if len(dati) != atteso:
        raise SystemExit('Tiles.raw e\' %d byte, ne servono %d' % (len(dati), atteso))
    piano = FOGLIO_PITCH * FOGLIO_RIGHE
    out = []
    for tr in range(FOGLIO_RIGHE // TILE):
        for tc in range(FOGLIO_COLS):
            cella = []
            for y in range(TILE):
                riga = tr * TILE + y
                px = []
                for x in range(TILE):
                    bx, bit = tc * 2 + (x >> 3), 7 - (x & 7)
                    v = 0
                    for p in range(PIANI):
                        v |= ((dati[p * piano + riga * FOGLIO_PITCH + bx] >> bit) & 1) << p
                    px.append(v)
                cella.append(px)
            out.append(cella)
    return out


def segnaposto(tab):
    """{numero: NOME} da OGNI EQU TILE_* del sorgente. Aggiungerne una la rende
    scrivibile per nome nella mappa senza toccare questo file."""
    return {v: k for k, v in tab.items()
            if k.startswith('TILE_') and isinstance(v, int) and 0 <= v < FOGLIO_SLOT}


def leggi_tileflags():
    """I byte di TileFlags, per sapere fin dove arriva."""
    testo = valori._espandi(valori.SORGENTE)
    i = next(k for k, l in enumerate(testo) if l.startswith('TileFlags:'))
    out = []
    for l in testo[i + 1:]:
        c = l.split(';')[0].rstrip()
        m = re.search(r'\bdc\.b\s+(.+)$', c, re.I)
        if not m:
            if out and c.strip():
                break
            continue
        out += [int(v.strip()) for v in m.group(1).split(',')]
    return out


def mappa_da_gioco(tab):
    """Le righe del blocco MAPPA: di Gioco.s."""
    testo = valori._espandi(valori.SORGENTE)
    i = next(k for k, l in enumerate(testo) if l.startswith('MAPPA:'))
    out = []
    for l in testo[i + 1:]:
        c = l.split(';')[0].rstrip()
        m = re.search(r'\bdc\.w\s+(.+)$', c, re.I)
        if not m:
            if out and c.strip():
                break
            continue
        out.append([int(v.strip()) for v in m.group(1).split(',')])
        if len(out) == tab['MAPPA_ROWS']:
            break
    return out


# ------------------------------------------------------------------- .txt --
def leggi_txt(path, segni):
    """Le righe della mappa. Tollerante in lettura: spazi o virgole, numero di
    riga facoltativo davanti ai due punti, commenti con ';'."""
    nomi = {}
    for n, s in segni.items():
        nomi[s.upper()] = n
        nomi[s.upper().replace('TILE_', '', 1)] = n
    righe, errori = [], []
    for nr, l in enumerate(open(path, encoding='utf-8'), 1):
        c = l.split(';')[0].strip()
        if not c:
            continue
        c = re.sub(r'^\s*\d+\s*:', '', c)          # l'etichetta di riga
        voci = [t for t in re.split(r'[\s,]+', c) if t]
        fila = []
        for t in voci:
            if re.fullmatch(r'\d+', t):
                v = int(t)
                if v >= FOGLIO_SLOT:
                    errori.append('riga %d: %s e\' fuori dal foglio (0..%d)'
                                  % (nr, t, FOGLIO_SLOT - 1))
                    v = 0
            elif t.upper() in nomi:
                v = nomi[t.upper()]
            else:
                errori.append('riga %d: "%s" non e\' un numero ne\' una EQU TILE_* '
                              'di Gioco.s' % (nr, t))
                v = 0
            fila.append(v)
        righe.append((nr, fila))
    if not righe:
        raise SystemExit('%s non contiene nessuna riga di mappa' % path)
    larg = len(righe[0][1])
    for nr, fila in righe:
        if len(fila) != larg:
            errori.append('riga %d: %d caselle, ma la prima riga ne ha %d'
                          % (nr, len(fila), larg))
    return [f for _, f in righe], errori


def scrivi_txt(path, righe, segni, intestazione=None):
    """Forma canonica: colonne allineate, righello in cima, numero di riga."""
    larg = len(righe[0])
    nomi = {n: s.replace('TILE_', '', 1) for n, s in segni.items()}
    # LA LARGHEZZA DELLA COLONNA E' UNIFORME, quindi UN nome lungo allarga OGNI
    # riga del file. Si guardano solo i nomi DAVVERO USATI: dichiarare una EQU
    # TILE_ lunga che nessuna casella usa non deve costare niente.
    usati = {v for fila in righe for v in fila}
    w = max(4, max([len(v) + 1 for n, v in nomi.items() if n in usati] or [0]))
    out = []
    out += intestazione or [
        '; Mappa di MegaGame. UNA CASELLA = UNA TILE.',
        '; Il numero e\' lo slot nel foglio grafica/Tiles.raw; la tavola con',
        '; numero e disegno di ogni tile e\' nella tavola accanto a questo file.',
        '; Si puo\' scrivere anche il NOME di una EQU TILE_* (LUCE = 50).',
        '; Dopo ogni modifica:  py tools\\mappa.py',
        ';',
        '; %d colonne x %d righe = %d x %d px' % (larg, len(righe), larg * 16,
                                                  len(righe) * 16),
        '; = %.1f x %.1f STANZE dell\'originale (%dx%d tile)'
        % (larg / float(STANZA_C), len(righe) / float(STANZA_R), STANZA_C, STANZA_R),
        '; = %.1f x %.1f NOSTRE SCHERMATE (%dx%d tile) - sono due unita\' diverse'
        % (larg / float(VIS_C), len(righe) / float(VIS_R), VIS_C, VIS_R),
    ]
    rig = '     ' + ''.join(('%d' % c).rjust(w) if c % 5 == 0 else '.'.rjust(w)
                            for c in range(larg))
    out.append(';' + rig[1:])
    for y, fila in enumerate(righe):
        cel = ''.join((nomi[v] if v in nomi else str(v)).rjust(w) for v in fila)
        out.append('%4d:%s' % (y, cel))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')
    return larg, len(righe)


def commenti_in_testa(path):
    """Le righe di commento gia' presenti in cima al file, per non buttarle via
    quando si riordina. Il righello (che comincia con ';   ') si rigenera."""
    if not os.path.exists(path):
        return None
    fuori = []
    for l in open(path, encoding='utf-8'):
        s = l.rstrip('\n')
        if not s.strip():
            continue
        if not s.lstrip().startswith(';'):
            break
        # il righello e' la sola riga fatta di soli numeri, punti e spazi:
        # "; 25 colonne x 22 righe" comincia anche lei con una cifra e va tenuta
        if re.fullmatch(r';[\s\d.]*', s):
            continue
        fuori.append(s)
    return fuori or None


# ------------------------------------------------------------- anteprime ---
def anteprima(righe, tile, pal, senza_arte, path):
    h, w = len(righe), len(righe[0])
    im = Image.new('RGB', (w * TILE, h * TILE))
    px = im.load()
    for ty, fila in enumerate(righe):
        for tx, n in enumerate(fila):
            if n in senza_arte:
                continue
            c = tile[n]
            for y in range(TILE):
                for x in range(TILE):
                    px[tx * TILE + x, ty * TILE + y] = pal[c[y][x]]
    dr = ImageDraw.Draw(im)
    for ty, fila in enumerate(righe):               # le tile che mancano
        for tx, n in enumerate(fila):
            if n not in senza_arte:
                continue
            x0, y0 = tx * TILE, ty * TILE
            dr.rectangle([x0, y0, x0 + TILE - 1, y0 + TILE - 1], fill=(200, 0, 200))
            dr.text((x0 + 1, y0 + 4), str(n), fill=(255, 255, 255))
    for x in range(0, w, STANZA_C):                 # griglia delle stanze
        dr.line([(x * TILE, 0), (x * TILE, h * TILE)], fill=(90, 90, 110))
    for y in range(0, h, STANZA_R):
        dr.line([(0, y * TILE), (w * TILE, y * TILE)], fill=(90, 90, 110))
    for x in range(0, w, BLOCCO_C):                 # confini dei blocchi
        dr.rectangle([x * TILE, 0, x * TILE + 1, h * TILE], fill=(255, 60, 60))
    for y in range(0, h, BLOCCO_R):
        dr.rectangle([0, y * TILE, w * TILE, y * TILE + 1], fill=(255, 60, 60))
    im.save(path)


def tavola(tile, pal, segni, senza_arte, path):
    """Numero e disegno di ogni tile usabile. E' il foglio da tenere aperto
    mentre si scrivono i numeri."""
    vive = [n for n in range(len(tile))
            if n not in senza_arte or n in segni]
    per_riga = 12
    cell, passo = TILE * 3, TILE * 3 + 24
    im = Image.new('RGB', (per_riga * (cell + 14) + 10,
                   ((len(vive) + per_riga - 1) // per_riga) * passo + 10), (18, 18, 24))
    dr = ImageDraw.Draw(im)
    for k, n in enumerate(vive):
        cx = (k % per_riga) * (cell + 14) + 6
        cy = (k // per_riga) * passo + 16
        if n in senza_arte:
            dr.rectangle([cx, cy, cx + cell, cy + cell], fill=(120, 0, 120))
        else:
            c = tile[n]
            t = Image.new('RGB', (TILE, TILE))
            tp = t.load()
            for y in range(TILE):
                for x in range(TILE):
                    tp[x, y] = pal[c[y][x]]
            im.paste(t.resize((cell, cell), Image.NEAREST), (cx, cy))
        dr.text((cx, cy - 12),
                '%d%s' % (n, ' ' + segni[n].replace('TILE_', '') if n in segni else ''),
                fill=(210, 210, 220))
    im.save(path)


def sagoma(righe, flags, path):
    """La mappa vista come SOLIDO/VUOTO, derivata da TileFlags. Nessuna seconda
    tabella da tenere in pari: il carattere lo decide il bit TF_BLOCK."""
    out = ['; sagoma delle collisioni, DERIVATA da TileFlags: # bloccata, . libera',
           '; prodotto di tools/mappa.py, non si modifica a mano']
    for y, fila in enumerate(righe):
        out.append('%4d %s' % (y, ''.join(
            '#' if (n < len(flags) and flags[n] & 1) else '.' for n in fila)))
    open(path, 'w', encoding='utf-8').write('\n'.join(out) + '\n')


# ------------------------------------------------------------------ main ---
def main():
    global VIS_C, VIS_R
    # PRIMA DI TUTTO: su quale mappa si sta lavorando. Va instradato qui, prima
    # che qualunque ramo apra un file, se no --mappa 2 leggerebbe il .txt della
    # prima e scriverebbe il .raw della seconda.
    if '--mappa' in sys.argv:
        i = sys.argv.index('--mappa')
        if i + 1 >= len(sys.argv):
            raise SystemExit('--mappa vuole un numero (1 = risorse/mappa1.txt)')
        n = sys.argv[i + 1]
        if not re.fullmatch(r'[1-9][0-9]?', n):
            raise SystemExit('--mappa vuole un numero da 1 a 99, non %r' % n)
        percorsi('mappa' + n)
    tab = valori.leggi()
    VIS_C, VIS_R = tab['VIS_COLS'], tab['BG_VIS_ROWS'] // 16
    pal = palette_gioco(tab)
    tile = foglio_tile()
    segni = segnaposto(tab)
    flags = leggi_tileflags()
    senza_arte = {n for n in range(len(tile))
                  if all(v == 0 for r in tile[n] for v in r) and n != 0}

    if '--tavola' in sys.argv:
        tavola(tile, pal, segni, senza_arte, TAVOLA)
        print('scritta %s' % os.path.relpath(TAVOLA, RADICE))
        return 0

    if '--da-gioco' in sys.argv:
        if os.path.exists(TXT):
            raise SystemExit('%s esiste gia\'. Spostalo prima, non lo sovrascrivo.'
                             % os.path.relpath(TXT, RADICE))
        w, h = scrivi_txt(TXT, mappa_da_gioco(tab), segni)
        tavola(tile, pal, segni, senza_arte, TAVOLA)
        print('scritto %s: %d x %d tile, dal blocco MAPPA: di Gioco.s'
              % (os.path.relpath(TXT, RADICE), w, h))
        return 0

    if '--nuova' in sys.argv:
        i = sys.argv.index('--nuova')
        w, h = int(sys.argv[i + 1]), int(sys.argv[i + 2])
        if os.path.exists(TXT):
            raise SystemExit('%s esiste gia\'. Spostalo prima, non lo sovrascrivo.'
                             % os.path.relpath(TXT, RADICE))
        scrivi_txt(TXT, [[0] * w for _ in range(h)], segni)
        tavola(tile, pal, segni, senza_arte, TAVOLA)
        print('scritto %s vuoto: %d x %d tile' % (os.path.relpath(TXT, RADICE), w, h))
        return 0

    if not os.path.exists(TXT):
        raise SystemExit('manca %s. Comincia con --da-gioco oppure --nuova C R'
                         % os.path.relpath(TXT, RADICE))
    righe, errori = leggi_txt(TXT, segni)
    if errori:
        print('NON CONVERTO. %d problemi nel .txt:' % len(errori))
        for e in errori:
            print('  ' + e)
        return 1
    h, w = len(righe), len(righe[0])

    if '--dimensiona' in sys.argv:
        i = sys.argv.index('--dimensiona')
        nc, nr = int(sys.argv[i + 1]), int(sys.argv[i + 2])
        # TAGLIARE PUO' BUTTARE VIA LAVORO IN SILENZIO: si taglia solo il vuoto.
        persi = []
        for y in range(h):
            for x in range(w):
                if (x >= nc or y >= nr) and righe[y][x] != 0:
                    persi.append((y, x, righe[y][x]))
        if persi:
            # riassunto per riga e per colonna: un elenco di 49 caselle non si
            # legge, "la riga 11 e' il pavimento" si'
            rr = sorted({y for y, _, _ in persi})
            cc = sorted({x for _, x, _ in persi})
            print('NON RIDIMENSIONO: fuori da %dx%d restano %d caselle piene.'
                  % (nc, nr, len(persi)))
            if any(y >= nr for y in rr):
                print('   righe che si perderebbero: %s'
                      % ', '.join('%d (%d caselle)'
                                  % (y, sum(1 for a, _, _ in persi if a == y))
                                  for y in rr if y >= nr))
            if any(x >= nc for x in cc):
                print('   colonne che si perderebbero: %s'
                      % ', '.join('%d (%d caselle)'
                                  % (x, sum(1 for _, b, _ in persi if b == x))
                                  for x in cc if x >= nc))
            return 1
        nuove = [[(righe[y][x] if y < h and x < w else 0) for x in range(nc)]
                 for y in range(nr)]
        scrivi_txt(TXT, nuove, segni, commenti_in_testa(TXT))
        print('da %dx%d a %dx%d: %s' % (w, h, nc, nr,
              'solo vuoto tolto/aggiunto' if (nc, nr) != (w, h) else 'niente da fare'))
        return 0

    if '--riordina' in sys.argv:
        scrivi_txt(TXT, righe, segni, commenti_in_testa(TXT))
        print('riallineato %s: %d x %d tile' % (os.path.relpath(TXT, RADICE), w, h))
        return 0

    print('mappa: %d x %d tile = %d x %d px' % (w, h, w * 16, h * 16))
    print('  %.1f x %.1f stanze da %dx%d   |   %.1f x %.1f nostre schermate da %dx%d'
          % (w / float(STANZA_C), h / float(STANZA_R), STANZA_C, STANZA_R,
             w / float(VIS_C), h / float(VIS_R), VIS_C, VIS_R))
    # IL RETTANGOLO DEL CONTENUTO. Righe e colonne vuote ai bordi si pagano
    # come le piene (512 byte a tile), e a occhio non si contano: qui si
    # vedono, e --dimensiona le toglie.
    pc = [x for x in range(w) if any(righe[y][x] for y in range(h))]
    pr = [y for y in range(h) if any(righe[y])]
    if pc and pr and (pc[0] or pr[0] or pc[-1] != w - 1 or pr[-1] != h - 1):
        print('  contenuto nelle colonne %d..%d e nelle righe %d..%d:'
              % (pc[0], pc[-1], pr[0], pr[-1]))
        print('  %d colonne e %d righe ai bordi sono solo cielo, e costano %d KB'
              % (w - (pc[-1] - pc[0] + 1), h - (pr[-1] - pr[0] + 1),
                 (w * h - (pc[-1] - pc[0] + 1) * (pr[-1] - pr[0] + 1)) * 512 // 1024))

    usate = {}
    for fila in righe:
        for n in fila:
            usate[n] = usate.get(n, 0) + 1
    print('tile distinte: %d   (le tre piu\' frequenti: %s)'
          % (len(usate), ', '.join('%d x%d' % (n, c) for n, c in
             sorted(usate.items(), key=lambda t: -t[1])[:3])))
    for n in sorted(set(segni) & set(usate)):
        # UN SEGNAPOSTO BLOCCATO E' QUASI SEMPRE UNO SBAGLIO: ci si entra sopra
        # (la partenza, un passaggio, uno spawn), quindi vuole TF_BLOCK a zero.
        stato = ''
        if n < len(flags) and (flags[n] & 1):
            stato = '   <-- BLOCCATA in TileFlags: un segnaposto si calpesta'
        print('  segnaposto %-16s tile %3d, %d volte%s'
              % (segni[n], n, usate[n], stato))
    # un nome lungo allarga OGNI riga del file, e il conto va fatto vedere
    lunghi = [segni[n].replace('TILE_', '', 1) for n in set(segni) & set(usate)]
    piu_lungo = max([len(v) for v in lunghi] or [0])
    if piu_lungo + 1 > 4:
        print('  colonne larghe %d per il nome piu\' lungo in uso (%d caratteri):'
              % (piu_lungo + 1, piu_lungo))
        print('  righe del .txt da %d caratteri invece di %d. I nomi corti costano'
              % (w * (piu_lungo + 1), w * 4))
        print('  meno: la larghezza e\' uniforme, quindi UNO lungo allarga TUTTO.')

    manca = sorted(n for n in usate if n in senza_arte and n not in segni)
    if manca:
        print('\nARTE DA DISEGNARE: %d tile usate che non hanno ancora un disegno.'
              % len(manca))
        print('  (nell\'anteprima sono quadrati magenta col numero dentro)')
        for n in manca:
            print('    tile %3d  usata %4d volte' % (n, usate[n]))
    oltre = sorted(n for n in usate if n >= len(flags))
    if oltre:
        print('\nTILEFLAGS si ferma a %d e la mappa usa fino a %d.'
              % (len(flags) - 1, max(oltre)))
        print('  Da aggiungere in coda a TileFlags (0 = libera, 1 = bloccata):')
        for base in range(len(flags), max(oltre) + 1, 16):
            print(';   tile: ' + ' '.join('%3d' % k for k in range(base, base + 16)))
            print('\tdc.b\t' + ','.join('  0' for _ in range(16)))

    # regola 15: copia prima. Dove va la decide copie.py, non qui.
    vecchia = copie.metti_da_parte(RAW, sposta=True, numera=True)
    if vecchia:
        print('\nvecchio .raw messo da parte come %s'
              % os.path.relpath(vecchia, RADICE))
    with open(RAW, 'wb') as f:
        for fila in righe:
            f.write(struct.pack('>%dH' % w, *fila))
    anteprima(righe, tile, pal, senza_arte, ANTEPRIMA)
    tavola(tile, pal, segni, senza_arte, TAVOLA)
    sagoma(righe, flags, SAGOMA)
    print('scritti: %s (%d byte), %s, %s, %s'
          % (os.path.relpath(RAW, RADICE), w * h * 2,
             os.path.relpath(ANTEPRIMA, RADICE), os.path.relpath(TAVOLA, RADICE),
             os.path.relpath(SAGOMA, RADICE)))
    print('\nDa avere in Gioco.s, con la guardia sulla dimensione del file:')
    print('MAPPA_COLS\t\tEQU\t%d' % w)
    print('MAPPA_ROWS\t\tEQU\t%d' % h)
    print('MAPPA_ATTESA\tEQU\tMAPPA_COLS*MAPPA_ROWS*2')
    # L'etichetta segue il NOME della mappa, cosi' il suggerimento si puo'
    # incollare senza correggerlo a mano: la prima e' MAPPA1 (il nome del file
    # non ha suffisso, l'etichetta si', perche' in Gioco.s le mappe sono una
    # tabella e non una), le altre MAPPA2, MAPPA3...
    et = NOME.upper()
    print('%s:\tincbin\t"grafica/%s.raw"' % (et, NOME))
    print('%s_FINE:' % et)
    print('\tIFNE\t(%s_FINE-%s)-MAPPA_ATTESA' % (et, et))
    print('GUARDIA_%s_RAW\tEQU\t1/0' % et)
    print('\tENDC')
    print('e la voce in MappaBase: \tdc.l\t%s' % et)
    return 0


if __name__ == '__main__':
    sys.exit(main())
