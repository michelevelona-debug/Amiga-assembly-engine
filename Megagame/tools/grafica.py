#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# grafica.py - il modulo che scrive l'arte. NON si usa da solo: lo importano i
#   generatori (genera-strumenti.py, genera-parallasse.py).
#
# REGOLA DEL PROGETTO: quando si genera un .raw si genera ANCHE l'.iff.
# Il .raw e' quello che l'Amiga incbinna; l'.iff e' quello che si apre in un
# editor per guardarlo o ritoccarlo a mano. Un .raw senza il suo .iff e' arte
# che si puo' solo rigenerare, mai correggere.
#
# La regola non e' affidata alla buona volonta': c'e' UNA funzione che scrive,
# `salva`, e scrive tutti e due. Non esiste un modo di scrivere solo il .raw.
#
# VANNO IN DUE CARTELLE DIVERSE, e non e' pignoleria:
#   grafica/          SOLO i file che l'assemblatore incbinna
#   risorse/grafica/  il materiale da aprire a mano: sorgenti, anteprime, .iff
# Tenendoli separati, `grafica/` resta esattamente l'insieme dei file che
# servono alla build - che e' anche quello che controlla tools/sposta-risorse.py
# estraendo i percorsi dagli incbin. Un .iff dentro grafica/ e' un file che
# nessun incbin nomina e che sembrerebbe orfano.
#
# I COLORI NON SI RICOPIANO. Le tinte vere stanno in Gioco.s (SPIA_COL1,
# ROSSA_COL1, SKYLINE_C1_RGB...) e in Pannello.cop: qui si LEGGONO da li'.
# Ricopiarle vorrebbe dire aprire l'IFF e vedere colori che il gioco non ha.
# ============================================================================
import os, re, struct

# Dove va l'.iff, sempre, qualunque sia la cartella del .raw. Vedi il perche'
# in testa al file.
IFF_DIR = os.path.join('risorse', 'grafica')

def _radice():
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def equ(nome, sorgente='Gioco.s'):
    """Il valore di una EQU letto DAL SORGENTE. Solo le forme semplici:
    un numero decimale o $esadecimale. Se non c'e', si alza: meglio fermarsi
    che scrivere un colore inventato."""
    t = open(os.path.join(_radice(), sorgente), encoding='utf-8').read()
    m = re.search(r'^%s\s+EQU\s+\$?([0-9a-fA-F]+)\s*(?:;.*)?$' % re.escape(nome),
                  t, re.M)
    if not m:
        raise KeyError('EQU %s non trovata in %s' % (nome, sorgente))
    g = m.group(0)
    return int(m.group(1), 16 if '$' in g.split('EQU')[1] else 10)

def colore_pannello(i, cop='Pannello.cop'):
    """La voce i della palette del pannello, dal blocco copper. Stessa lettura
    che fa rimappa-pannello.py."""
    t = open(os.path.join(_radice(), cop), encoding='latin-1').read()
    v = re.findall(r'\$([0-9a-fA-F]{4})', t)
    for k in range(0, len(v)-1, 2):
        r = int(v[k], 16)
        if r == 0x180 + i*2:
            return int(v[k+1], 16)
    raise KeyError('COLOR%02d non trovato in %s' % (i, cop))

def rgb12(v):
    """$rgb a 12 bit -> (r,g,b) a 8 bit, con l'espansione del nibble che usa
    anche il chipset: $f diventa $ff."""
    return (((v >> 8) & 15)*17, ((v >> 4) & 15)*17, (v & 15)*17)

def rgb24(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)

# ----------------------------------------------------------------- ILBM
def _chunk(nome, dati):
    p = b'\x00' if len(dati) & 1 else b''
    return nome + struct.pack('>I', len(dati)) + dati + p

def _interlaccia(dati, w, h, piani):
    """Il .raw ha i piani SEPARATI e contigui (tutto il piano 0, poi il piano
    1...). L'ILBM li vuole INTERLACCIATI per riga: riga 0 di ogni piano, poi
    riga 1 di ogni piano. E' l'unica differenza fra i due formati."""
    rowb = w // 8
    psz = rowb * h
    out = bytearray()
    for y in range(h):
        for k in range(piani):
            out += dati[k*psz + y*rowb : k*psz + (y+1)*rowb]
    return bytes(out)

def scrivi_ilbm(path, dati, w, h, piani, palette, trasparente=0):
    """palette = lista di (r,g,b), 2**piani voci."""
    assert w % 16 == 0, 'ILBM vuole righe di byte pari'
    assert len(palette) == 1 << piani, (len(palette), 1 << piani)
    bmhd = struct.pack('>HHhhBBBBHBBHH',
                       w, h, 0, 0,
                       piani,
                       2,            # masking = colore trasparente dichiarato
                       0,            # nessuna compressione: si legge ovunque
                       0,
                       trasparente,
                       10, 11,       # aspetto lores PAL
                       w, h)
    cmap = b''.join(bytes(c) for c in palette)
    body = _interlaccia(dati, w, h, piani)
    corpo = b'ILBM' + _chunk(b'BMHD', bmhd) + _chunk(b'CMAP', cmap) + _chunk(b'BODY', body)
    open(path, 'wb').write(b'FORM' + struct.pack('>I', len(corpo)) + corpo)
    return os.path.getsize(path)

# ------------------------------------------------- arte in formato SPRITE
def salva_sprite(path_raw, dati, decodifica, w, h, piani, palette):
    """Come `salva`, ma per l'arte che sul disco NON e' una bitmap planare:
    i dati degli sprite hardware, dove ogni riga porta le due parole dei piani
    una dopo l'altra e in testa c'e' un blocco di controllo. `salva` non va
    bene per quella roba - asserisce che i byte siano piani separati e
    contigui, e lo sono di proposito.

    La regola del progetto pero' resta: **niente .raw senza il suo .iff**. Qui
    l'.iff e' l'ANTEPRIMA, e si ottiene RILEGGENDO il file appena scritto e
    passandolo a `decodifica`. Non e' una copia di comodo: e' la stessa arte
    fatta il giro completo, quindi se la codifica sbaglia l'anteprima lo mostra
    invece di nasconderlo. Un'anteprima costruita dai dati di partenza non
    avrebbe questa proprieta' e sarebbe inutile.

    decodifica: bytes del .raw -> bytes planari (piani separati, contigui).
    """
    open(path_raw, 'wb').write(bytes(dati))
    planare = decodifica(open(path_raw, 'rb').read())
    atteso = (w // 8) * h * piani
    assert len(planare) == atteso, (len(planare), atteso)
    d_iff = os.path.join(_radice(), IFF_DIR)
    os.makedirs(d_iff, exist_ok=True)
    nome = os.path.splitext(os.path.basename(path_raw))[0] + '.iff'
    path_iff = os.path.join(d_iff, nome)
    n_iff = scrivi_ilbm(path_iff, planare, w, h, piani, palette)
    return len(dati), n_iff, path_iff

# ----------------------------------------------------------------- l'unica via
def salva(path_raw, celle_o_dati, w, h, piani, palette):
    """Scrive il .raw E l'.iff. E' l'unico modo di scrivere arte in questo
    progetto: chi vuole solo il .raw deve prima cambiare questa funzione, e a
    quel punto se ne assume la responsabilita' per iscritto.

    celle_o_dati: o i byte gia' planari, o una matrice h x w di valori."""
    if isinstance(celle_o_dati, (bytes, bytearray)):
        dati = bytes(celle_o_dati)
    else:
        rowb = w // 8
        psz = rowb * h
        d = bytearray(psz * piani)
        for y in range(h):
            riga = celle_o_dati[y]
            for x in range(w):
                v = riga[x]
                if not v: continue
                for k in range(piani):
                    if (v >> k) & 1:
                        d[k*psz + y*rowb + (x >> 3)] |= 1 << (7 - (x & 7))
        dati = bytes(d)
    assert len(dati) == (w//8)*h*piani, (len(dati), (w//8)*h*piani)
    open(path_raw, 'wb').write(dati)
    # l'.iff NON va accanto al .raw: vedi IFF_DIR in testa al file
    d_iff = os.path.join(_radice(), IFF_DIR)
    os.makedirs(d_iff, exist_ok=True)
    nome = os.path.splitext(os.path.basename(path_raw))[0] + '.iff'
    path_iff = os.path.join(d_iff, nome)
    n_iff = scrivi_ilbm(path_iff, dati, w, h, piani, palette)
    return len(dati), n_iff, path_iff
