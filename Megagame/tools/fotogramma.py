#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# fotogramma.py - ricostruisce QUELLO CHE IL CHIPSET MANDA A VIDEO, dai file
#   veri, senza Amiga e senza emulatore.
#
# USO (dalla cartella Megagame):
#   python3 tools/fotogramma.py                 il quadro d'avvio
#   python3 tools/fotogramma.py --cam 848 208   un quadro qualsiasi
#   python3 tools/fotogramma.py --verifica      tutta la corsa della camera
#   python3 tools/fotogramma.py --mappa 2       su un altro blocco (difetto: il 1)
#
# PERCHE' ESISTE. Quando lo scroll "si rompe" non c'e' modo di sapere da qui
# se il difetto sta nel BUFFER (montato male) o nel PERCORSO DI DISPLAY
# (puntatore, BPLCON1, DDF, moduli): a occhio i due si somigliano, e una
# risposta a occhio e' esattamente cio' che le regole del progetto vietano.
# Questo modulo rifa' i tre passi separatamente, con la stessa aritmetica del
# sorgente:
#   1. monta il world buffer come DisegnaSfondo, tile per tile, byte per byte;
#   2. calcola offset e ritardo come ScrollHWCalc;
#   3. preleva le 22 word per riga e ricava i 320 px visibili come il chipset.
# Poi confronta il risultato con quello ATTESO, che e' banale da scrivere:
# la colonna x dello schermo deve mostrare il pixel (CameraX+x) della mappa.
# Se i due coincidono, il percorso di display non e' il colpevole e si cerca
# altrove; se non coincidono, la differenza dice DOVE.
#
# NIENTE VALORI RICOPIATI: pitch, altezza, guardia, fetch, moduli, palette e
# geometria del foglio tile vengono da tools/valori.py, cioe' dalle EQU vive
# di Gioco.s. Se domani cambia la larghezza della mappa, cambia anche qui.
#
# LIMITI, dichiarati: questo simula il PERCORSO DI SFONDO (i 5 piani del
# mondo). Non disegna bob, darkplane, pannello ne' gli alberi sprite, che
# vivono su altri piani e altri canali. Serve a rispondere a una domanda
# sola, e la risponde per intero.
# ============================================================================
import importlib.util, os, struct, sys

QUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, QUI)
import valori

from PIL import Image, ImageDraw


def _modulo(nome, file):
    sp = importlib.util.spec_from_file_location(nome, os.path.join(QUI, file))
    mo = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(mo)
    return mo


mappa = _modulo('mappa', 'mappa.py')
RADICE = valori.RADICE
USCITA = os.path.join(RADICE, 'risorse', 'grafica')


def costanti():
    t = valori.leggi()
    k = dict(
        pitch=t['SFONDO_PITCH'], altezza=t['SFONDO_HEIGHT'],
        piano=t['SFONDO_PLANE_SIZE'], delta=t['DELTA_MAPPAVERA'],
        origine=t['BG_ORIGIN_OFS'], cols=t['MAPPA_COLS'], rows=t['MAPPA_ROWS'],
        bcols=t['BUFFER_COLS'], fetches=t['SCROLL_FETCHES'],
        bfetch=t['SCROLL_BYTES_FETCH'], blocco=t['SCROLL_BLOCCO_PX'],
        bplmod=t['SCROLL_BPLMOD'], vis_r=t['BG_VIS_ROWS'], vis_w=t['DIW_WIDTH'],
        camx_max=t['SCROLL_CAMERA_PX'], camy_max=t['TILEYMAX'] * 16,
        centro_x=t['CENTER_X'], centro_y=t['CENTER_Y'], via=t['TILE_VIA'],
        piani=mappa.PIANI, sh_pitch=mappa.FOGLIO_PITCH,
        sh_piano=mappa.FOGLIO_RIGHE * mappa.FOGLIO_PITCH,
        sh_cols=mappa.FOGLIO_COLS, tile=mappa.TILE)
    return t, k


def leggi_mappa(n=None):
    """Il blocco su cui verificare il percorso di display. Di difetto il primo.
    Il nome NON e' piu' cablato a 'mappa.raw': dal 30 settembre 2026 i blocchi
    hanno tutti il loro numero, e questo strumento serve su uno qualunque."""
    if n is None:
        n = 1
        if '--mappa' in sys.argv:
            i = sys.argv.index('--mappa')
            if i + 1 >= len(sys.argv) or not sys.argv[i + 1].isdigit():
                raise SystemExit('--mappa vuole un numero')
            n = int(sys.argv[i + 1])
    p = os.path.join(RADICE, 'grafica', 'mappa%d.raw' % n)
    if not os.path.isfile(p):
        raise SystemExit('manca %s: lancia py tools\\mappa.py --mappa %d'
                         % (os.path.relpath(p, RADICE), n))
    d = open(p, 'rb').read()
    return list(struct.unpack('>%dH' % (len(d) // 2), d))


def costruisci_buffer(k, mp, tiles):
    """I 5 piani del mondo montati come li monta DisegnaSfondo.
    Un piano per elemento della lista, cosi' un indice fuori posto esplode
    invece di finire silenziosamente nel piano accanto."""
    buf = [bytearray(k['piano']) for _ in range(k['piani'])]
    punta = k['delta'] + k['origine']
    a0 = 0
    for _riga in range(k['rows']):
        for _col in range(k['bcols']):
            t = mp[a0]; a0 += 1
            srow, scol = divmod(t, k['sh_cols'])        # la DIVU #20
            a2 = srow * (k['tile'] * k['sh_pitch']) + scol * 2
            a1 = punta; punta += 2
            for p in range(k['piani']):
                s = a2 + p * k['sh_piano']
                for y in range(k['tile']):              # BLTSIZE 16 x 1 word
                    o = s + y * k['sh_pitch']
                    q = a1 + y * k['pitch']
                    buf[p][q] = tiles[o]
                    buf[p][q + 1] = tiles[o + 1]
        punta += k['tile'] * k['pitch'] - k['bcols'] * 2
        a0 += k['cols'] - k['bcols']
    return buf


def hardware(k, camx, camy):
    """offset, ritardo BPLCON1: la stessa aritmetica di ScrollHWCalc."""
    blocchi = (camx + k['blocco'] - 1) // k['blocco']
    ritardo = blocchi * k['blocco'] - camx
    return blocchi * k['bfetch'] + camy * k['pitch'], ritardo


def finestra(k, buf, camx, camy):
    """I 320xBG_VIS_ROWS pixel visibili, prelevati come li preleva il chipset.
    Ritorna anche gli indirizzi finiti fuori dal piano: quelli sono il
    sintomo che si vede a schermo come spazzatura."""
    ofs, ritardo = hardware(k, camx, camy)
    passo = k['fetches'] * k['bfetch'] + k['bplmod']    # deve fare un pitch
    out = [[0] * k['vis_w'] for _ in range(k['vis_r'])]
    fuori = 0
    for y in range(k['vis_r']):
        base = ofs + y * passo
        for x in range(k['vis_w']):
            kpx = x + (k['blocco'] - ritardo)           # pixel PRELEVATO
            b = base + (kpx >> 3)
            if b < 0 or b >= k['piano']:
                fuori += 1
                continue
            bit = 7 - (kpx & 7)
            v = 0
            for p in range(k['piani']):
                if buf[p][b] >> bit & 1:
                    v |= 1 << p
            out[y][x] = v
    return out, ofs, ritardo, fuori


def atteso(k, mp, tiles, camx, camy):
    """Quello che DEVE apparire: la colonna x mostra il pixel CameraX+x."""
    out = [[0] * k['vis_w'] for _ in range(k['vis_r'])]
    for y in range(k['vis_r']):
        tr, py = divmod(camy + y, k['tile'])
        if tr >= k['rows']:
            continue
        for x in range(k['vis_w']):
            tc, px = divmod(camx + x, k['tile'])
            if tc >= k['cols']:
                continue
            t = mp[tr * k['cols'] + tc]
            srow, scol = divmod(t, k['sh_cols'])
            o = (srow * k['tile'] * k['sh_pitch'] + scol * 2
                 + py * k['sh_pitch'] + (px >> 3))
            bit = 7 - (px & 7)
            v = 0
            for p in range(k['piani']):
                if tiles[o + p * k['sh_piano']] >> bit & 1:
                    v |= 1 << p
            out[y][x] = v
    return out


def camera_avvio(k, mp):
    """Dove parte la camera: TrovaPartenza piu' CentraCameraSulPlayer.
    La prima TILE_VIA in ordine di lettura, come fa il BEQ del sorgente."""
    px = py = None
    for i, v in enumerate(mp):
        if v == k['via']:
            px = (i % k['cols']) * 16
            py = (i // k['cols']) * 16
            break
    if px is None:
        return 0, 0, None, None
    cx = min(max(px - k['centro_x'], 0), k['camx_max'])
    cy = min(max(py - k['centro_y'], 0), k['camy_max'])
    return cx, cy, px, py


def png(k, pixel, pal, path, player=None):
    im = Image.new('RGB', (k['vis_w'], k['vis_r']))
    p = im.load()
    for y in range(k['vis_r']):
        for x in range(k['vis_w']):
            p[x, y] = pal[pixel[y][x]]
    if player:
        ImageDraw.Draw(im).rectangle(
            [player[0], player[1], player[0] + 31, player[1] + 31],
            outline=(255, 0, 0))
    im.save(path)
    return path


def verifica(k):
    """La corsa INTERA della camera, in aritmetica pura: per ogni posizione
    la colonna 0 deve cadere sul pixel CameraX e l'ultimo prelievo deve
    restare dentro il piano. 320 conti per posizione invece di 56320 pixel,
    quindi si puo' passare tutto invece di campionare."""
    passo = k['fetches'] * k['bfetch'] + k['bplmod']
    guasti = []
    if passo != k['pitch']:
        guasti.append('fetch %d + bplmod %d = %d, ma il pitch e\' %d: ogni riga'
                      ' slitta di %d byte'
                      % (k['fetches'] * k['bfetch'], k['bplmod'], passo,
                         k['pitch'], passo - k['pitch']))
    for camy in range(0, k['camy_max'] + 1):
        for camx in range(0, k['camx_max'] + 1):
            ofs, ritardo = hardware(k, camx, camy)
            if not 0 <= ritardo < k['blocco']:
                guasti.append('cam %d,%d: ritardo %d fuori da 0..%d'
                              % (camx, camy, ritardo, k['blocco'] - 1))
            # colonna 0 e colonna 319: i due estremi bastano, in mezzo e' lineare
            for x in (0, k['vis_w'] - 1):
                kpx = x + (k['blocco'] - ritardo)
                b = ofs + (kpx >> 3)
                visto = (b - k['delta'] - camy * k['pitch']) * 8 + (kpx & 7)
                if visto != camx + x:
                    guasti.append('cam %d,%d col %d: mostra il pixel %d invece'
                                  ' di %d' % (camx, camy, x, visto, camx + x))
            ultimo = ofs + (k['vis_r'] - 1) * passo + k['fetches'] * k['bfetch'] - 1
            if ultimo >= k['piano']:
                guasti.append('cam %d,%d: l\'ultimo prelievo tocca il byte %d,'
                              ' il piano ne ha %d'
                              % (camx, camy, ultimo, k['piano']))
            if len(guasti) > 12:
                return guasti
    return guasti


def main():
    arg = sys.argv[1:]
    t, k = costanti()
    mp = leggi_mappa()
    tiles = open(os.path.join(RADICE, 'grafica', 'Tiles.raw'), 'rb').read()
    pal = mappa.palette_gioco(t)

    print('pitch %d, piano %d byte, prelievo %d byte/riga, BPLMOD %d'
          % (k['pitch'], k['piano'], k['fetches'] * k['bfetch'], k['bplmod']))
    print('corsa della camera: X 0..%d, Y 0..%d' % (k['camx_max'], k['camy_max']))

    if '--verifica' in arg:
        guasti = verifica(k)
        if guasti:
            print('\nGUASTI (primi %d):' % len(guasti))
            for g in guasti:
                print('  ' + g)
            return 1
        print('\nTutta la corsa della camera e\' esatta: nessuna posizione'
              ' mostra il pixel sbagliato\ne nessun prelievo esce dal piano.')
        return 0

    if '--cam' in arg:
        i = arg.index('--cam')
        camx, camy = int(arg[i + 1]), int(arg[i + 2])
        px = py = None
        nome = 'fotogramma-%d-%d.png' % (camx, camy)
    else:
        camx, camy, px, py = camera_avvio(k, mp)
        nome = 'fotogramma-avvio.png'
        if px is None:
            print('\nnessuna TILE_VIA nella mappa: camera a 0,0')
        else:
            print('\nTILE_VIA a (%d,%d) tile = (%d,%d) px'
                  % (px // 16, py // 16, px, py))

    buf = costruisci_buffer(k, mp, tiles)
    vis, ofs, ritardo, fuori = finestra(k, buf, camx, camy)
    att = atteso(k, mp, tiles, camx, camy)
    sbagliati = sum(1 for y in range(k['vis_r']) for x in range(k['vis_w'])
                    if vis[y][x] != att[y][x])

    print('camera (%d,%d): offset %d, ritardo BPLCON1 %d'
          % (camx, camy, ofs, ritardo))
    print('pixel diversi da quelli attesi: %d   prelievi fuori dal piano: %d'
          % (sbagliati, fuori))

    player = None
    if px is not None:
        player = (px - camx, py - camy)
        print('il player cade a schermo in (%d,%d); il centro e\' (%d,%d)'
              % (player[0], player[1], k['centro_x'], k['centro_y']))
    p = png(k, vis, pal, os.path.join(USCITA, nome), player)
    print('scritto ' + os.path.relpath(p, RADICE))
    return 0


if __name__ == '__main__':
    sys.exit(main())
