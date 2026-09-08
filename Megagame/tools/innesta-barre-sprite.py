#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# innesta-barre-sprite.py - mette e toglie le otto barre di prova DENTRO
#   Gioco.s. Versione ridotta: NIENTE TASTI.
#
#   py tools\innesta-barre-sprite.py            le mette
#   py tools\innesta-barre-sprite.py --togli    le toglie
#
# Rispetto alla versione precedente sono spariti i tasti 1/2/3/4/5: agganciarsi
# alla catena di LeggiTastiera e' costato due difetti in un pomeriggio (un salto
# ripuntato sulla riga sbagliata, e una catena spezzata), e per questa prova non
# serve nessun tasto - le barre ci sono e basta. FMODE e la larghezza degli
# sprite adesso sono interruttori veri in testa a Gioco.s (SCROLL_FMODE32,
# SPRITE64), non manopole da premere.
#
# LE ANCORE SI CERCANO PER TESTO, non per numero di riga: il sorgente si muove
# a ogni consegna e i numeri invecchiano subito. Ogni ancora deve comparire UNA
# volta sola nel file pulito, e lo script si ferma se non e' cosi'.
# ============================================================================
import os, sys, shutil

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORG = os.path.join(RADICE, 'Gioco.s')
BACKUP = SORG + '.prima-barre'
TAG = 'BARRE SPRITE'

EQU = """;=== BARRE SPRITE - EQU (togliere dopo la prova) ===========================
BARRE_N				EQU		8
BARRE_VSTART		EQU		80
BARRE_VSTOP			EQU		290
BARRE_RIGHE			EQU		BARRE_VSTOP-BARRE_VSTART
BARRE_HBASE			EQU		DIW_H_START+12
BARRE_HPASSO		EQU		37
; Formato a 64 bit: per riga 8 byte di piano A e 8 di piano B.
; La regola vera del prelievo sprite: OGNI accesso e' largo quanto dice FMODE,
; e le due word di controllo sono la PRIMA word di DUE accessi distinti. A 64
; bit il blocco di controllo occupa quindi 16 byte, non 8: SPRPOS al byte 0,
; SPRCTL al byte 8. Non e' una congettura, e' la sola lettura che spiega la
; prova del 3 settembre - vedi il commento nel costruttore.
BARRE_CTRL_B		EQU		16
BARRE_RIGA_B		EQU		16
BARRE_FINE_B		EQU		32
BARRE_SZ			EQU		BARRE_CTRL_B+BARRE_RIGHE*BARRE_RIGA_B+BARRE_FINE_B
; Con SPAGEM il puntatore di ogni sprite deve stare su 64 bit: BarreSprite ha
; il suo cnop 0,8, ma se la taglia non fosse multipla di 8 lo perderebbero
; tutti gli sprite dal secondo in poi.
	IFNE	BARRE_SZ&7
ERRORE_BARRE_SZ_NON_ALLINEATA	EQU		1/0
	ENDC
;=== fine EQU =============================================================="""

BUF = """;=== BARRE SPRITE - buffer (togliere dopo la prova) ========================
; PRIMA di `include "ptplayer.i"`: ptplayer ha una sua direttiva `end` e da li'
; in giu' l'assemblatore non legge piu' niente.
	SECTION	BarreSpriteSec,DATA_C
	cnop	0,8
BarreSprite:
	ds.b	BARRE_SZ*BARRE_N
;=== fine buffer ==========================================================="""

COSTR = """;=== BARRE SPRITE - il costruttore (togliere dopo la prova) ================
;   Otto barre verticali, una per canale. Gli sprite PARI usano il valore 1 e
;   i DISPARI il 2: dentro una coppia i due canali condividono le tre tinte,
;   cosi' ognuno degli otto prende una voce di colore diversa.
;
;   PERCHE' IL BLOCCO DI CONTROLLO E' DI 16 BYTE, E COME LO SAPPIAMO.
;   La versione precedente ne metteva 8 e ha dato DUE barre invece delle
;   cinque gia' misurate. Il conto torna in un modo solo: l'hardware legge
;   SPRCTL dal byte 8, cioe' dalla prima word dei dati.
;     - canali PARI: li' c'e' $FFFF, quindi il bit 2 di SPRCTL (VSTART bit 8)
;       e' acceso, VSTART diventa 80+256=336 e lo sprite non esce MAI.
;     - canali DISPARI: li' c'e' $0000, quindi VSTOP=0, che dopo la riga 80
;       non arriva piu': la barra scende fino in fondo al quadro.
;   Restano vive solo SPR1 e SPR3, alte quanto tutto lo schermo, e i dati
;   letti sfasati di 8 byte danno a entrambe il valore 1: arancione (voce 17)
;   e blu (voce 21), alle x 49 e 123. Numero, altezza, colore e posizione:
;   tornano tutti e quattro. I canali non erano scesi da cinque a due, tre li
;   aveva uccisi questo blocco di controllo.
;   DISTRUGGE: nulla (salva tutto).
BuildBarreSprite:
	MOVEM.L	D0-D5/A0-A1,-(SP)
	LEA		BarreSprite,A0
	LEA		Sprites,A1					; la tabella dentro la copperlist
	MOVEQ	#0,D4						; indice del canale
	MOVEQ	#BARRE_N-1,D5
.canale:
	MOVE.L	A0,D0
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	ADDQ.W	#8,A1

	MOVE.W	D4,D0
	MULU	#BARRE_HPASSO,D0
	ADD.W	#BARRE_HBASE,D0				; D0 = HSTART

	MOVE.W	D0,D1
	LSR.W	#1,D1
	AND.W	#$FF,D1
	OR.W	#(BARRE_VSTART&$FF)<<8,D1
	MOVE.W	D1,(A0)+					; SPRPOS: prima word del 1o prelievo
	CLR.W	(A0)+						; le altre tre word del 1o prelievo
	CLR.W	(A0)+
	CLR.W	(A0)+

	MOVE.W	#((BARRE_VSTOP&$FF)<<8)|(((BARRE_VSTART>>8)&1)<<2)|(((BARRE_VSTOP>>8)&1)<<1),D1
	AND.W	#1,D0						; bit 0 di HSTART
	OR.W	D0,D1
	MOVE.W	D1,(A0)+					; SPRCTL: prima word del 2o prelievo
	CLR.W	(A0)+						; le altre tre word del 2o prelievo
	CLR.W	(A0)+
	CLR.W	(A0)+

	MOVE.W	#$FFFF,D2
	MOVEQ	#0,D3
	BTST	#0,D4
	BEQ.S	.pari
	EXG		D2,D3						; i dispari sul secondo piano
.pari:
	MOVE.W	#BARRE_RIGHE-1,D0
.riga:
	; 64 px per riga, ma accesi solo i primi 16: cosi' le barre restano
	; distinguibili anche con lo stesso passo di prima, e se il formato dei
	; dati e' quello giusto si vedono PULITE invece che spezzate.
	MOVE.W	D2,(A0)+					; piano A, px 0..15
	CLR.W	(A0)+						; piano A, px 16..31
	CLR.W	(A0)+						; piano A, px 32..47
	CLR.W	(A0)+						; piano A, px 48..63
	MOVE.W	D3,(A0)+					; piano B, px 0..15
	CLR.W	(A0)+
	CLR.W	(A0)+
	CLR.W	(A0)+
	DBRA	D0,.riga
	; Terminatore: due prelievi interi a zero, cioe' un blocco di controllo
	; con VSTART=VSTOP=0. Stessa taglia del blocco di controllo in testa.
	CLR.L	(A0)+
	CLR.L	(A0)+
	CLR.L	(A0)+
	CLR.L	(A0)+
	CLR.L	(A0)+
	CLR.L	(A0)+
	CLR.L	(A0)+
	CLR.L	(A0)+

	ADDQ.W	#1,D4
	DBRA	D5,.canale
	MOVEM.L	(SP)+,D0-D5/A0-A1
	RTS
;=== fine costruttore ======================================================"""

CHIAMATA = "\tBSR.W\tBuildBarreSprite\t\t; BARRE SPRITE - la chiamata (togliere)"

COLORI = """	;=== BARRE SPRITE - i colori (togliere dopo la prova) ==================
	; Gli sprite NON prendono piu' i colori 16-31. Quelle voci sono dell'arte:
	; toccarne cinque il 2 settembre ha ridipinto il gioco e ha fatto sembrare
	; sprite quello che sprite non era, e lasciarle intatte fa l'errore
	; opposto - una barra del colore di una tile e' una barra che non si vede.
	; Con BPU=6 l'arte arriva all'indice 63: le voci 64..255 sono TUTTE libere.
	; BPLCON4 con ESPRM=OSPRM=$4 porta gli sprite a 64..79 (e' anche il valore
	; che il progetto della parallasse prevede, quindi questa prova lo verifica
	; per conto suo). BPLAM resta $00: i bitplane non si spostano di un indice.
	; Le voci sopra la 31 si scrivono cambiando BANCA in BPLCON3: banca 2 sono
	; i colori 64..95, e i registri $0180..$019e diventano le voci 64..79.
	; Otto colori che l'arte non puo' produrre: se si vede uno di questi, e'
	; uno sprite, senza discussione. La coppia k usa 64+4k+1 per il canale
	; PARI (valore 1) e 64+4k+2 per il DISPARI (valore 2).
	; Una scrittura con LOCT=0 duplica il nibble anche nei bit bassi, quindi
	; $0f00 esce come #FF0000 pieno.
	dc.w	$010c,$0044			; BPLCON4: ESPRM=OSPRM=$4, sprite a 64..79
	dc.w	$0106,(2<<BPLCON3_BANK_SHIFT)|BPLCON3_LOCT0
	dc.w	$0182,$0f00			; voce 65   SPR0   rosso
	dc.w	$0184,$0f80			; voce 66   SPR1   arancio
	dc.w	$018a,$0ff0			; voce 69   SPR2   giallo
	dc.w	$018c,$00f0			; voce 70   SPR3   verde
	dc.w	$0192,$00ff			; voce 73   SPR4   ciano
	dc.w	$0194,$004f			; voce 74   SPR5   blu
	dc.w	$019a,$0f0f			; voce 77   SPR6   magenta
	dc.w	$019c,$0fff			; voce 78   SPR7   bianco
	dc.w	$0106,BPLCON3_LOCT0	; banca 0: da qui in giu' tutto come prima
	;=== fine colori ======================================================="""

BPU6 = """	;=== BARRE SPRITE - sei bitplane (togliere dopo la prova) ==============
	; Un secondo BPLCON0 subito dopo il primo: senza WAIT in mezzo vince
	; questo. Spegne i piani 7-8, cioe' la parallasse. Serve perche' la
	; configurazione che stiamo misurando e' quella DOPO il trasloco, e il
	; numero di canali dipende da quanto DMA bitplane c'e'.
	dc.w	$0100,%0110001000000001		; BPU=6
	;=== fine sei bitplane ================================================="""

PAROFF = """;=== BARRE SPRITE - blit della parallasse spenti (togliere) ================
; Non basta togliere i PIANI: finche' AggiornaParallax blitta, il blitter si
; prende slot e il 2 settembre si e' mangiato l'ultimo canale sprite. Qui la
; routine esce subito. Sta PRIMA della MOVEM: nessun registro sullo stack,
; quindi l'RTS e' pulito.
; (PAR_DISABLE non serve a questo: rende la parallasse invisibile, non spenta.)
	RTS
;=== fine blit spenti ======================================================"""

PRIORITA = """	;=== BARRE SPRITE - la priorita' (togliere dopo la prova) ==============
	; Il MOVE qui sopra mette PF2P=4 e PF1P=4, e il commento accanto e' FALSO:
	; 4 non vuol dire "i primi 4 sprite davanti", vuol dire PLAYFIELD DAVANTI
	; A TUTTI E OTTO. Con l'area di gioco opaca gli sprite ci sono e non si
	; vedono - e' quello che e' successo il 2 settembre.
	; Questo secondo MOVE vince sul primo (non c'e' nessun WAIT in mezzo).
	; La priorita' non c'entra col DMA: quante barre ARRIVANO non cambia,
	; cambia solo che si vedono.
	dc.w	$0104,$0000			; PF2P=0, PF1P=0: sprite davanti al playfield
	;=== fine priorita' ===================================================="""

# (testo dell'ancora, blocco, 'dopo' | 'prima')
ANCORE = [
    ("DIW_WIDTH\t\t\tEQU\t\t(DIW_H_STOP+256)-DIW_H_START",  EQU,       'dopo'),
    ("\tBSR.W\tAggiornaCopperSPR ",                          CHIAMATA,  'dopo'),
    ("*****************************************************************************\n* BuildFaloSheet", COSTR, 'prima'),
    ("\tdc.w\t$104,$0024\t\t; BPLCON2 = PF2P=4",             PRIORITA,  'dopo'),
    ("\tdc.w\t$0100,%0000001000010001\t\t; BPLCON0: 8 bitplane", BPU6,   'dopo'),
    ("AggiornaParallax:",                                    PAROFF,    'dopo'),
    ("\t; Ripristino BPLCON3 a default LOCT=0 (per il prossimo frame)\n\tdc.w\t$0106,BPLCON3_LOCT0", COLORI, 'dopo'),
    ("\tSECTION\tPTPlayerCode,CODE",                          BUF,       'prima'),
]


def togli(righe):
    out, dentro, n = [], False, 0
    for r in righe:
        s = r.strip()
        if s.startswith(';===') and TAG in s:
            dentro = True; n += 1; continue
        if dentro:
            n += 1
            if s.startswith(';===') and s.startswith(';=== fine'):
                dentro = False
            continue
        if TAG in r:
            n += 1; continue
        out.append(r)
    if dentro:
        sys.exit('marcatore di apertura senza chiusura: non tolgo niente')
    return out, n


def main():
    testo = open(SORG, encoding='utf-8').read()
    righe = testo.split('\n')

    if '--togli' in sys.argv:
        if TAG not in testo:
            print('Gioco.s non ha le barre: niente da togliere.'); return 0
        out, n = togli(righe)
        t = '\n'.join(out)
        if not t.endswith('\n'): t += '\n'
        open(SORG, 'w', encoding='utf-8', newline='\n').write(t)
        print('tolte %d righe' % n)
        if os.path.isfile(BACKUP):
            uguale = open(BACKUP, 'rb').read() == open(SORG, 'rb').read()
            print('INVARIANTE: identico al backup?', 'SI' if uguale else 'NO')
        return 0

    if TAG in testo:
        sys.exit("Gioco.s HA GIA' le barre. Prima --togli.")

    # le ancore si cercano per TESTO e devono essere uniche
    posizioni = []
    for ancora, blocco, modo in ANCORE:
        if testo.count(ancora) != 1:
            sys.exit('ANCORA NON UNIVOCA (%d occorrenze): %r'
                     % (testo.count(ancora), ancora[:50]))
        prima = testo[:testo.index(ancora)]
        n = prima.count('\n') + 1               # riga 1-based dell'ancora
        if modo == 'dopo':
            n += ancora.count('\n')             # dopo l'ultima riga dell'ancora
            posizioni.append((n, blocco))
        else:
            posizioni.append((n - 1, blocco))
    print('tutte le %d ancore trovate una volta sola' % len(posizioni))

    shutil.copy2(SORG, BACKUP)
    print('backup: %s' % os.path.basename(BACKUP))
    for n, blocco in sorted(posizioni, key=lambda t: -t[0]):
        righe[n:n] = blocco.split('\n')
        print('  riga %5d: +%d righe' % (n, len(blocco.split('\n'))))
    t = '\n'.join(righe)
    if not t.endswith('\n'): t += '\n'
    open(SORG, 'w', encoding='utf-8', newline='\n').write(t)
    print('\nfatto. Per togliere: py tools\\innesta-barre-sprite.py --togli')
    return 0


if __name__ == '__main__':
    sys.exit(main())
