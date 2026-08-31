#!/usr/bin/env python3
# ============================================================================
# terminatori.py - controlla (e sistema) i fine riga dei sorgenti
#
# USO (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
#   python3 tools/terminatori.py              <- solo rapporto, non tocca niente
#   python3 tools/terminatori.py --correggi   <- porta tutto a LF + a capo finale
#
# ---------------------------------------------------------------------------
# PERCHE'
#
# L'Amiga usa LF ($0A) da solo. Windows scrive CRLF, e su Devpac quel CR resta
# attaccato in fondo a ogni riga: "EQU 320" diventa "EQU 320\r" e il valore non
# si legge piu'. Editare su Windows e assemblare sull'Amiga significa che il
# file deve stare a LF, sempre.
#
# E l'ULTIMA RIGA vuole il suo a capo. Una riga finale senza terminatore e' il
# caso che morde in silenzio: se l'assemblatore la scarta e li' c'era una
# direttiva, non da' errore, semplicemente quella riga non c'e' piu'. In questo
# progetto e' successo su Pannello.cop, che finiva con un dc.w di quattro
# colori della palette del pannello senza a capo, ed e' incluso due volte.
#
# ---------------------------------------------------------------------------
# COME
#
# Tutto a livello di BYTE, mai decodificando il testo: Startup2.i e' latin-1 e
# leggerlo come UTF-8 fermerebbe lo script (o peggio, lo riscriverebbe rotto).
# CR e LF sono byte singoli che non compaiono dentro nessuna sequenza
# multi-byte, ne' in UTF-8 ne' in latin-1, quindi la sostituzione e' sicura
# qualunque sia la codifica del file.
#
# Prima di riscrivere, lo script VERIFICA che l'unica differenza siano i
# terminatori: spezza vecchio e nuovo in righe e controlla che le righe siano
# le stesse, una per una. Se non lo sono, non scrive e lo dice.
# ============================================================================
import os, sys

ESTENSIONI = ('.s', '.i', '.asm', '.cop')
SALTA = ()          # eventuali file di terze parti da non toccare


def analizza(dati):
    crlf = dati.count(b'\r\n')
    lf = dati.count(b'\n') - crlf
    cr = dati.count(b'\r') - crlf
    if crlf and not lf and not cr:
        tipo = 'CRLF'
    elif lf and not crlf and not cr:
        tipo = 'LF'
    elif cr and not lf and not crlf:
        tipo = 'CR'
    elif not (crlf or lf or cr):
        tipo = 'nessuno'
    else:
        tipo = 'MISTI'
    return crlf, lf, cr, tipo


def normalizza(dati):
    """CRLF e CR isolati -> LF, e garantisce l'a capo finale."""
    out = dati.replace(b'\r\n', b'\n').replace(b'\r', b'\n')
    if out and not out.endswith(b'\n'):
        out += b'\n'
    return out


def righe(dati):
    """Le righe SENZA terminatore, per confrontare il contenuto."""
    return dati.replace(b'\r\n', b'\n').replace(b'\r', b'\n').split(b'\n')


def main():
    radice = os.getcwd()
    correggi = '--correggi' in sys.argv[1:]
    for a in sys.argv[1:]:
        if a != '--correggi':
            print('ERRORE: argomento non riconosciuto: %s' % a)
            return 1

    file = [n for n in sorted(os.listdir(radice))
            if n.lower().endswith(ESTENSIONI) and n not in SALTA
            and os.path.isfile(os.path.join(radice, n))]
    if not file:
        print('ERRORE: nessun sorgente %s qui. Lo script va lanciato DALLA'
              % '/'.join(ESTENSIONI))
        print('       cartella Megagame.')
        return 1

    print('%-18s %9s %7s %8s %8s  %-8s %s'
          % ('file', 'byte', 'CRLF', 'LF soli', 'CR soli', 'tipo', 'ultima riga'))
    print('-' * 82)
    da_correggere = []
    for n in file:
        p = os.path.join(radice, n)
        d = open(p, 'rb').read()
        crlf, lf, cr, tipo = analizza(d)
        finale = d.endswith(b'\n') or not d
        nota = 'ok' if (tipo in ('LF', 'nessuno') and finale) else 'DA SISTEMARE'
        print('%-18s %9d %7d %8d %8d  %-8s %s'
              % (n, len(d), crlf, lf, cr, tipo,
                 'con a capo' if finale else 'SENZA a capo'))
        if nota == 'DA SISTEMARE':
            da_correggere.append((n, p, d))

    print()
    if not da_correggere:
        print('Tutto a LF con a capo finale: il sorgente e\' pronto per Devpac.')
        return 0

    print('Da sistemare: %d file' % len(da_correggere))
    for n, _, d in da_correggere:
        crlf, lf, cr, tipo = analizza(d)
        motivi = []
        if tipo != 'LF' and tipo != 'nessuno':
            motivi.append('terminatori %s' % tipo)
        if not d.endswith(b'\n'):
            motivi.append('manca l\'a capo finale')
        print('   %-18s %s' % (n, ', '.join(motivi)))

    if not correggi:
        print()
        print('RAPPORTO: non ho toccato niente.')
        print('Per sistemarli:  py tools\\terminatori.py --correggi')
        return 1

    print()
    for n, p, d in da_correggere:
        nuovo = normalizza(d)
        # la prova che cambia SOLO il terminatore, non il contenuto
        if righe(d) != righe(nuovo)[:len(righe(d))]:
            print('   SALTATO %s: il contenuto non coincide, non riscrivo.' % n)
            continue
        vecchie, nuove = righe(d), righe(nuovo)
        if vecchie != nuove and vecchie + [b''] != nuove:
            print('   SALTATO %s: differenza inattesa nelle righe, non riscrivo.' % n)
            continue
        with open(p, 'wb') as f:
            f.write(nuovo)
        print('   %-18s %d -> %d byte' % (n, len(d), len(nuovo)))
    print()
    print('Fatto. Rilancia senza --correggi per riverificare.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
