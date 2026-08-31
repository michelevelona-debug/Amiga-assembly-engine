#!/usr/bin/env python3
# ============================================================================
# registri.py - quali registri del chipset scrive ogni percorso, e quali no
#
# USO (dalla cartella Megagame)
#   python3 tools/registri.py
#
# ---------------------------------------------------------------------------
# PERCHE'
#
# Un registro custom che NON scrivi non ha un valore di default: ha il valore
# che ci ha lasciato chi aveva la macchina prima di te (Kickstart, Workbench,
# un interrupt, il percorso di gioco precedente). Dipenderne senza scriverlo e'
# la stessa cosa che leggere una variabile non inizializzata.
#
# E' costato una serata sulla schermata del titolo: FMODE era l'unico registro
# di display che ShowTitle non scriveva, e siccome il DMA bitplane si accende
# PRIMA che il copper arrivi a impostarlo, la title girava per una finestra con
# la geometria di fetch di qualcun altro. In WinUAE non si vedeva.
#
# Questo script non sa cosa sia giusto: elenca i fatti. Per ogni percorso dice
# quali registri scrive, e per i registri di display segnala quelli che il
# percorso NON tocca. Se un registro non compare da nessuna parte in tutto il
# sorgente, lo dice a parte: quello e' il caso da guardare per primo.
#
# ---------------------------------------------------------------------------
# LIMITE DA CONOSCERE
#
# Una riga dc.w e' una copperlist o una tabella di dati, e da fuori non si
# distinguono: in MAPPA o in CieloGrad.i un valore pari e sotto $200 in
# posizione pari verrebbe letto come una scrittura a un registro. Per i
# registri di display il caso non si presenta oggi (verificato a mano), ma se
# un domani il rapporto dice "scrive" su un registro che ti sorprende, la prima
# cosa da controllare e' se quel numero e' un dato travestito.
# Il verso opposto e' peggio e va tenuto d'occhio: un "NO" e' un'affermazione
# forte, e prima di crederci conviene una grep di conferma.
# ============================================================================
import os, re, sys

SORGENTI = ('.s', '.i')
ESCLUSI = ('ptplayer.i',)     # terze parti: ha i suoi registri audio

NOMI = {
    0x02E: 'COPCON',   0x080: 'COP1LC',   0x084: 'COP2LC',
    0x088: 'COPJMP1',  0x08A: 'COPJMP2',
    0x08E: 'DIWSTRT',  0x090: 'DIWSTOP',  0x092: 'DDFSTRT',  0x094: 'DDFSTOP',
    0x096: 'DMACON',   0x098: 'CLXCON',   0x09A: 'INTENA',   0x09C: 'INTREQ',
    0x100: 'BPLCON0',  0x102: 'BPLCON1',  0x104: 'BPLCON2',  0x106: 'BPLCON3',
    0x108: 'BPL1MOD',  0x10A: 'BPL2MOD',  0x10C: 'BPLCON4',  0x10E: 'CLXCON2',
    0x1DC: 'BEAMCON0', 0x1E4: 'DIWHIGH',  0x1FC: 'FMODE',
    0x05A: 'BLTCON0L', 0x064: 'BLTAMOD',  0x066: 'BLTDMOD',
    0x060: 'BLTCMOD',  0x062: 'BLTBMOD',  0x040: 'BLTCON0',  0x042: 'BLTCON1',
    0x044: 'BLTAFWM',  0x046: 'BLTALWM',  0x058: 'BLTSIZE',
    0x050: 'BLTAPT',   0x052: 'BLTBPT',   0x054: 'BLTCPT',   0x056: 'BLTDPT',
}
for i in range(8):
    NOMI[0x0E0 + i*4] = 'BPL%dPT' % (i+1)
    NOMI[0x120 + i*4] = 'SPR%dPT' % i
for i in range(32):
    NOMI[0x180 + i*2] = 'COLOR%02d' % i

# I registri che decidono COME si vede un bitplane. Chi accende il display
# dovrebbe scriverli tutti, e scriverli PRIMA di abilitare il DMA.
DISPLAY = [0x1FC, 0x100, 0x102, 0x104, 0x106, 0x10C, 0x108, 0x10A,
           0x092, 0x094, 0x08E, 0x090, 0x1E4, 0x1DC]


def sorgenti(radice):
    return [os.path.join(radice, n) for n in sorted(os.listdir(radice))
            if n.lower().endswith(SORGENTI) and n not in ESCLUSI
            and os.path.isfile(os.path.join(radice, n))]


def scritture(path):
    """(riga, registro, come) per ogni scrittura a un registro custom."""
    out = []
    # CPU:  MOVE.x <qualcosa>,$NNN(A6)   oppure   ...,$dffNNN
    #
    # Una MOVE.L su un registro custom ne scrive DUE, non uno: i registri sono
    # word e stanno consecutivi, quindi MOVE.L #$ffffffff,$44(A6) mette a posto
    # BLTAFWM ($44) E BLTALWM ($46). Contarne uno solo fa risultare mai scritta
    # la meta' bassa di ogni coppia: sul blitter di questo progetto sarebbe
    # BLTALWM su tutte le routine di disegno, cioe' un buco inventato.
    rx_a6 = re.compile(r'\bMOVE(M?)\.([BWL])\s+[^;,]+,\s*\$([0-9a-fA-F]{1,3})\(A6\)', re.I)
    rx_ab = re.compile(r'\bMOVE(M?)\.([BWL])\s+[^;,]+,\s*\$dff([0-9a-fA-F]{3})', re.I)

    def cpu(i, m, out):
        movem, size, reg = m.group(1), m.group(2).upper(), int(m.group(3), 16)
        out.append((i, reg, 'CPU'))
        if movem:
            # MOVEM ne scrive quanti sono i registri in lista, e quanti siano
            # da qui non si sa: si segnala invece di indovinare.
            out.append((i, -reg, 'MOVEM'))
        elif size == 'L':
            out.append((i, reg + 2, 'CPU'))
    # copper: una riga dc.w porta PIU' coppie (registro,valore), non una sola.
    # "dc.w $0092,$0038,$0094,$00b8" sono DUE MOVE: DDFSTRT e DDFSTOP. Leggere
    # solo la prima word della riga faceva risultare DDFSTOP e DIWSTOP mai
    # scritti, cioe' un buco inventato. Si prendono gli elementi PARI.
    # I WAIT si scartano da soli: hanno il bit 0 a 1 (es. $2C01) o un valore
    # fuori dallo spazio dei registri (es. $FFDF), mentre un registro custom
    # e' sempre pari e sotto $200.
    rx_cop = re.compile(r'^\s*dc\.w\s+(.+)$', re.I)
    for i, l in enumerate(open(path, encoding='latin-1').read().split('\n'), 1):
        code = re.sub(r';.*$', '', l)
        for m in rx_a6.finditer(code):
            cpu(i, m, out)
        for m in rx_ab.finditer(code):
            cpu(i, m, out)
        m = rx_cop.match(code)
        if m:
            voci = [t.strip() for t in m.group(1).split(',')]
            for k in range(0, len(voci), 2):
                t = voci[k]
                if not t.startswith('$'):
                    continue
                try:
                    r = int(t[1:], 16)
                except ValueError:
                    continue
                if r < 0x200 and (r & 1) == 0 and (r in NOMI or 0x020 <= r <= 0x1FE):
                    out.append((i, r, 'copper'))
    return out


def blocchi(path, marcatori):
    """Righe di inizio dei blocchi che ci interessano, in ordine."""
    r = open(path, encoding='latin-1').read().split('\n')
    trovati = {}
    for i, l in enumerate(r, 1):
        for nome, prefisso in marcatori:
            if l.startswith(prefisso):
                trovati.setdefault(nome, i)
    return trovati, len(r)


def main():
    radice = os.getcwd()
    srcs = sorgenti(radice)
    if not srcs:
        print('ERRORE: nessun sorgente qui. Lancialo dalla cartella Megagame.')
        return 1
    principale = os.path.join(radice, 'Gioco.s')
    if not os.path.isfile(principale):
        print('ERRORE: Gioco.s non trovato.')
        return 1

    tutte = {}
    movem = []
    for p in srcs:
        for riga, reg, come in scritture(p):
            if come == 'MOVEM':
                movem.append((os.path.basename(p), riga, -reg))
                continue
            tutte.setdefault(reg, []).append((os.path.basename(p), riga, come))

    # --- 1. i percorsi che accendono un display -------------------------
    marcatori = [('ShowTitle', 'ShowTitle:'),
                 ('TitleCopperList', 'TitleCopperList:'),
                 ('CopperList', 'CopperList:'),
                 ('START', 'START:')]
    inizi, nrighe = blocchi(principale, marcatori)
    # confine di ogni blocco = prossimo marcatore o etichetta a colonna 0
    r = open(principale, encoding='latin-1').read().split('\n')

    def fine_blocco(da, copperlist=False):
        """Fine del blocco. Per una COPPERLIST non ci si puo' fermare alla prima
        etichetta a colonna 0: CL_BplCon1, TitleBPL_0, BitPlaneTiles e le altre
        stanno DENTRO la lista, e fermarsi li' significa leggerne un pezzo e
        riportare buchi che non esistono. La lista finisce al suo terminatore."""
        if copperlist:
            for i in range(da, len(r)):
                if re.match(r'^\s*dc\.w\s+\$FFFF\s*,\s*\$FFFE', r[i], re.I):
                    return i + 1
            return len(r)
        for i in range(da, len(r)):
            l = r[i]
            if l and (l[0].isalpha() or l[0] == '_') and re.match(r'^[A-Za-z_][A-Za-z0-9_]*:', l):
                return i
        return len(r)

    scritte_gioco = scritture(principale)
    print('REGISTRI CUSTOM SCRITTI, per percorso')
    print('=' * 70)
    percorsi = {}
    for nome in ('ShowTitle', 'TitleCopperList', 'CopperList'):
        if nome not in inizi:
            continue
        a = inizi[nome]
        b = fine_blocco(a, copperlist=nome.endswith('CopperList'))
        regs = sorted({reg for riga, reg, c in scritte_gioco
                       if c != 'MOVEM' and a <= riga <= b})
        percorsi[nome] = set(regs)
        print('\n%s  (righe %d..%d)' % (nome, a, b))
        print('   ' + ', '.join(NOMI.get(x, '$%03X' % x) for x in regs))

    # START e' lungo: si guarda solo fino alla chiamata a ShowTitle
    if 'START' in inizi:
        a = inizi['START']
        b = inizi.get('ShowTitle_call', None)
        for i, l in enumerate(r, 1):
            if 'BSR.W' in l and 'ShowTitle' in l:
                b = i
                break
        regs = sorted({reg for riga, reg, c in scritte_gioco
                       if c != 'MOVEM' and a <= riga <= (b or a)})
        percorsi['START->ShowTitle'] = set(regs)
        print('\nSTART fino alla chiamata a ShowTitle  (righe %d..%d)' % (a, b))
        print('   ' + ', '.join(NOMI.get(x, '$%03X' % x) for x in regs))

    # --- 2. i buchi sui registri di display -----------------------------
    print('\n\nREGISTRI DI DISPLAY NON SCRITTI DAL PERCORSO')
    print('=' * 70)
    print('(un registro assente da TUTTE le colonne e\' quello da guardare per primo)')
    print()
    intest = [n for n in ('ShowTitle', 'TitleCopperList', 'CopperList') if n in percorsi]
    print('%-10s %s' % ('registro', '  '.join('%-16s' % n for n in intest)))
    print('-' * 70)
    mai = []
    for reg in DISPLAY:
        nome = NOMI.get(reg, '$%03X' % reg)
        celle = []
        for p in intest:
            celle.append('%-16s' % ('scrive' if reg in percorsi[p] else 'NO'))
        if reg not in tutte:
            mai.append(nome)
        print('%-10s %s' % (nome, '  '.join(celle)))

    print('\n\nMAI SCRITTI IN TUTTO IL SORGENTE')
    print('=' * 70)
    if mai:
        for n in mai:
            print('   %s' % n)
        print('\nQuesti hanno il valore che ci ha lasciato chi c\'era prima.')
    else:
        print('   nessuno fra i registri di display elencati')

    if movem:
        print('\n\nMOVEM VERSO UN REGISTRO CUSTOM: NON MODELLATE')
        print('=' * 70)
        print('Una MOVEM scrive tanti registri quanti sono quelli in lista, e')
        print('quanti siano non si vede da qui. Queste righe vanno lette a mano:')
        for f, riga, reg in movem:
            print('   %s r.%d  a partire da %s' % (f, riga, NOMI.get(reg, '$%03X' % reg)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
