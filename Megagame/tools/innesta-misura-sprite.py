#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ============================================================================
# innesta-misura-sprite.py - mette e toglie i cinque innesti di
#   tools/misura-sprite.s DENTRO Gioco.s.
#
#   py tools\innesta-misura-sprite.py            mette gli innesti
#   py tools\innesta-misura-sprite.py --togli    li toglie
#
# ---------------------------------------------------------------------------
# PERCHE' DENTRO Gioco.s E NON IN UN FILE A PARTE
#
# Il primo tentativo produceva Gioco-misura-sprite.s accanto all'originale. Non
# funziona: il build assembla TUTTI i .s della cartella e linka tutti gli .o,
# quindi i due file danno "Global symbol _mt_install ... is already defined".
# Un innesto usa e getta deve stare dove il build guarda gia'.
#
# ---------------------------------------------------------------------------
# COME SI TORNA INDIETRO
#
# Ogni blocco e' delimitato da due righe marcatore, quindi --togli lo ritaglia
# via esattamente. NON ricopia il backup: cosi' le modifiche fatte a Gioco.s
# mentre gli innesti erano dentro non si perdono.
#
# Il backup c'e' lo stesso (backup/Gioco.s.prima-misura-sprite, instradato da
# tools/copie.py) e serve all'INVARIANTE che lo script stampa: dopo --togli il
# file deve tornare IDENTICO byte per byte. Se non lo e', lo dice.
#
# ---------------------------------------------------------------------------
# DUE COSE IMPARATE A CARO PREZZO, ed e' il motivo della forma degli innesti
#
#   a) le EQU vanno IN TESTA, con le altre. In fondo, il MOVEQ dell'innesto 2
#      dava "error 2025: absolute value expected": MOVEQ vuole un valore
#      assoluto subito, per stare negli 8 bit, e non tollera un riferimento in
#      avanti come gli altri immediati.
#   b) i buffer vanno subito PRIMA della direttiva `end`. Dopo `end`
#      l'assemblatore non guarda piu' niente: le righe ci sono, si leggono, e
#      non esistono. Adesso lo controlla anche tools/controlla-forward.py.
#
# Gli innesti si ancorano a INDICI DI RIGA verificati, non a ricerche di
# stringa. Ogni ancora porta con se' il testo che DEVE trovarci: se non lo
# trova si ferma, perche' vuol dire che il sorgente si e' mosso sotto i piedi.
# ============================================================================
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import copie

RADICE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SORG = os.path.join(RADICE, 'Gioco.s')
SUFFISSO = 'misura-sprite'


def backup():
    """La copia di Gioco.s di questo innesto. NON e' una costante: sta in
    backup/, ma se un innesto e' stato messo prima del trasloco la sua copia
    e' ancora accanto a Gioco.s, e `--togli` deve trovare quella. Lo decide
    copie.dove(), che guarda i due posti."""
    return copie.dove(SORG, SUFFISSO)

TAG = 'MISURA SPRITE'          # sta in ogni marcatore: e' quello che cerca --togli

# ---------------------------------------------------------------------------
# I blocchi. Prima riga = marcatore di apertura, ultima = di chiusura: cosi'
# --togli ritaglia esattamente quello che ha messo, senza righe vuote avanzate.
# ---------------------------------------------------------------------------

INNESTO_1A = """;=== MISURA SPRITE - INNESTO 1a: le EQU (togliere dopo la misura) ==========
; Stanno QUI, in mezzo alle altre EQU, e non in fondo: MISURA_SPR_HBASE
; discende da DIW_H_START qui sopra, e il MOVEQ dell'INNESTO 2 vuole un valore
; assoluto gia' noto.
MISURA_SPR_N		EQU		8
MISURA_SPR_VSTART	EQU		80
MISURA_SPR_VSTOP	EQU		290
MISURA_SPR_RIGHE	EQU		MISURA_SPR_VSTOP-MISURA_SPR_VSTART
MISURA_SPR_HBASE	EQU		DIW_H_START+12
MISURA_SPR_HPASSO	EQU		37
MISURA_SPR_WORDS	EQU		2+MISURA_SPR_RIGHE*2+2
MISURA_SPR_SZ		EQU		MISURA_SPR_WORDS*2
MISURA_DDF_PASSO	EQU		8
; I due valori di BPLCON0 fra cui commuta il tasto 3. Il secondo spegne i
; piani 7-8, cioe' la parallasse: e' la prova che dice se quei due piani, una
; volta liberati, ridanno canali sprite.
MISURA_BPU8		EQU		%0000001000010001	; BPU3=1 -> 8 bitplane
MISURA_BPU6		EQU		%0110001000000001	; BPU=6, parallasse spenta
; I due valori di FMODE fra cui commuta il tasto 4. Con $0003 il fetch e' a 64
; bit e i BPLxPT devono stare allineati a 8 byte, cioe' 64 px: da li' viene il
; prefetch da 64 px che costringe DDFSTRT a $18. Con $0001 il fetch e' a 32 bit
; e l'allineamento scende a 4 byte = 32 px: il prefetch dimezza e DDFSTRT
; potrebbe salire a $28, dove la tabella promette 5 canali. Il prezzo e' il
; doppio degli accessi bitplane, e se quel prezzo si mangia il guadagno lo dice
; solo la prova.
MISURA_FMODE64		EQU		$0003		; BPL32+BPAGEM: fetch a 64 bit (il gioco)
MISURA_FMODE32		EQU		$0001		; BPL32: fetch a 32 bit
;=== fine INNESTO 1a ======================================================="""

INNESTO_1B = """;=== MISURA SPRITE - INNESTO 1b: i buffer (togliere dopo la misura) ========
; STA QUI, PRIMA di `include "ptplayer.i"`, e non piu' in fondo al file.
; ptplayer.i ha una SUA direttiva `end` (riga 3974): l'assemblatore si ferma
; li', e tutto quello che sta dopo quell'include non esiste - compreso l'`end`
; di Gioco.s. Messo in fondo, questo blocco dava
;     Link Error 21: Reference to undefined symbol BarreSprite
; cioe' l'assemblatore trasformava BarreSprite in un simbolo esterno.
; Le due SECTION qui sotto stanno PRIMA di `SECTION PTPlayerCode,CODE`, che
; resta cosi' l'ultima prima dell'include: ptplayer continua a ereditare CODE.
	SECTION	MisuraSprite,DATA_C
	cnop	0,8
BarreSprite:
	ds.b	MISURA_SPR_SZ*MISURA_SPR_N

	SECTION	MisuraSpriteVar,DATA
Ddf1Prev:	dc.b	0
Ddf2Prev:	dc.b	0
Ddf3Prev:	dc.b	0
Ddf4Prev:	dc.b	0
	EVEN
;=== fine INNESTO 1b ======================================================="""

INNESTO_2 = """;=== MISURA SPRITE - INNESTO 2: il costruttore (togliere dopo la misura) ====
;   Otto barre verticali, una per canale. Gli sprite PARI usano il valore 1 e
;   i DISPARI il 2: dentro una coppia i due canali condividono i colori, cosi'
;   ognuno degli otto prende una voce diversa (17/18, 21/22, 25/26, 29/30).
;   DISTRUGGE: nulla (salva tutto).
BuildBarreSprite:
	MOVEM.L	D0-D5/A0-A1,-(SP)
	LEA		BarreSprite,A0
	LEA		Sprites,A1					; la tabella dentro la copperlist
	MOVEQ	#0,D4						; indice del canale
	MOVEQ	#MISURA_SPR_N-1,D5
.canale:
	MOVE.L	A0,D0
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	ADDQ.W	#8,A1

	MOVE.W	D4,D0
	MULU	#MISURA_SPR_HPASSO,D0
	ADD.W	#MISURA_SPR_HBASE,D0		; D0 = HSTART

	MOVE.W	D0,D1
	LSR.W	#1,D1
	AND.W	#$FF,D1
	OR.W	#(MISURA_SPR_VSTART&$FF)<<8,D1
	MOVE.W	D1,(A0)+					; SPRPOS

	MOVE.W	#((MISURA_SPR_VSTOP&$FF)<<8)|(((MISURA_SPR_VSTART>>8)&1)<<2)|(((MISURA_SPR_VSTOP>>8)&1)<<1),D1
	AND.W	#1,D0						; bit 0 di HSTART
	OR.W	D0,D1
	MOVE.W	D1,(A0)+					; SPRCTL

	MOVE.W	#$FFFF,D2
	MOVEQ	#0,D3
	BTST	#0,D4
	BEQ.S	.pari
	EXG		D2,D3						; i dispari sul secondo piano
.pari:
	MOVE.W	#MISURA_SPR_RIGHE-1,D0
.riga:
	MOVE.W	D2,(A0)+
	MOVE.W	D3,(A0)+
	DBRA	D0,.riga
	CLR.L	(A0)+						; le due word di fine sprite

	ADDQ.W	#1,D4
	DBRA	D5,.canale
	MOVEM.L	(SP)+,D0-D5/A0-A1
	RTS
;=== fine INNESTO 2 ========================================================"""

# riga singola: la riconosce il TAG nel commento
INNESTO_3 = "\tBSR.W\tBuildBarreSprite\t\t; MISURA SPRITE - INNESTO 3 (togliere)"

INNESTO_4 = """	;=== MISURA SPRITE - INNESTO 4: i colori delle barre (togliere) ========
	; Dopo la palette, cosi' vincono su di essa.
	;
	; SI TOCCANO SOLO LE VOCI CHE L'ARTE NON USA. La prima versione riscriveva
	; anche 17, 18 e 25, che sono dell'arte (16-20 le sagome, 24/25/27 la
	; pietra): il tronco degli alberi veniva verde e rosso, e quei "residui"
	; sembravano sprite mentre erano il gioco ridipinto. Un diagnostico che
	; sporca la scena che stai guardando non e' un diagnostico.
	;
	; Voci libere fra quelle degli sprite (ESPRM/OSPRM=$1 -> colori 16..31):
	;   21, 22, 23, 26, 29, 30, 31.   Occupate dall'arte: 17, 18, 19, 25, 27.
	; Quindi SPR0, SPR1 e SPR4 restano coi grigi del gioco e si riconoscono
	; dalla POSIZIONE. Gli altri cinque sono sgargianti.
	;
	; NB: una scrittura con LOCT=0 duplica il nibble anche nei bit bassi,
	; quindi $0f0 diventa $00FF00 pieno. Le tinte NON vengono storte: era
	; sbagliato anche quello.
	dc.w	$01aa,$004f			; SPR2  voce 21  blu
	dc.w	$01ac,$0ff0			; SPR3  voce 22  giallo
	dc.w	$01b4,$00ff			; SPR5  voce 26  ciano
	dc.w	$01ba,$0f0f			; SPR6  voce 29  magenta
	dc.w	$01bc,$0f80			; SPR7  voce 30  arancio
	;=== fine INNESTO 4 ===================================================="""

INNESTO_7 = """	;=== MISURA SPRITE - INNESTO 7: etichetta per i tasti 3 e 4 (togliere) ==
	; Le due dc.w qui sotto non avevano un nome e i tasti 3 e 4 devono scriverci
	; dentro. Dall'etichetta: FMODE sta a +2, il valore di BPLCON0 a +6.
	; L'etichetta e' su una riga sua, cosi' --togli la porta via senza toccare
	; nessuna riga del gioco.
CL_GeomM:
	;=== fine INNESTO 7 ===================================================="""

INNESTO_6 = """	;=== MISURA SPRITE - INNESTO 6: la priorita' (togliere dopo la misura) ==
	; Il MOVE qui sopra mette PF2P=4 e PF1P=4, e il commento accanto e' FALSO:
	; 4 non vuol dire "i primi 4 sprite davanti", vuol dire PLAYFIELD DAVANTI
	; A TUTTI E OTTO. Con l'area di gioco a 8 piani quasi sempre opaca, gli
	; sprite ci sono e non si vedono. E' quello che e' successo il 2 settembre:
	; nessuna barra, e solo una traccia in fondo al pannello, cioe' dove capita
	; un pixel di colore 0.
	; Questo secondo MOVE vince sul primo (non c'e' nessun WAIT in mezzo).
	; NB: la priorita' non c'entra col DMA. Quante barre ARRIVANO non cambia,
	; cambia solo che adesso si vedono: la misura resta quella.
	dc.w	$0104,$0000			; PF2P=0, PF1P=0: sprite davanti al playfield
	;=== fine INNESTO 6 ===================================================="""

INNESTO_5 = """;=== MISURA SPRITE - INNESTO 5: i due tasti che spostano DDFSTRT (togliere) =
; DDFSTRT si scrive nella COPPERLIST (CL_Ddf+2) e non nel registro: e' il
; copper a riscriverlo a ogni quadro. E' la stessa word che legge il profiler
; per mostrare DDF, quindi il numero a schermo e' sempre quello vero.
.k_ddfgiu:
	cmp.b	#$01,D2					; tasto 1
	bne.s	.k_ddfsu
	tst.b	D1
	beq.s	.dg_release
	tst.b	Ddf1Prev
	bne.s	.dg_release
	move.l	D0,-(sp)
	move.w	CL_Ddf+2,D0
	sub.w	#MISURA_DDF_PASSO,D0
	cmp.w	#$18,D0
	bcc.s	.dg_ok
	move.w	#$18,D0
.dg_ok:
	move.w	D0,CL_Ddf+2
	move.l	(sp)+,D0
.dg_release:
	move.b	D1,Ddf1Prev

.k_ddfsu:
	cmp.b	#$02,D2					; tasto 2
	bne.s	.k_bpu
	tst.b	D1
	beq.s	.ds_release
	tst.b	Ddf2Prev
	bne.s	.ds_release
	move.l	D0,-(sp)
	move.w	CL_Ddf+2,D0
	add.w	#MISURA_DDF_PASSO,D0
	cmp.w	#$38,D0
	bls.s	.ds_ok
	move.w	#$38,D0
.ds_ok:
	move.w	D0,CL_Ddf+2
	move.l	(sp)+,D0
.ds_release:
	move.b	D1,Ddf2Prev

; --- tasto 3: 8 bitplane <-> 6 bitplane, cioe' parallasse accesa o spenta ---
; La domanda che vale piu' di tutte: se liberando i due piani della parallasse
; tornano dei canali sprite, allora spostare la parallasse sugli sprite si
; ripaga da sola. Commutando dal vivo si confronta senza ricompilare.
.k_bpu:
	cmp.b	#$03,D2					; tasto 3
	bne.s	.k_fmode
	tst.b	D1
	beq.s	.bp_release
	tst.b	Ddf3Prev
	bne.s	.bp_release
	move.l	D0,-(sp)
	move.w	CL_GeomM+6,D0
	cmp.w	#MISURA_BPU8,D0
	bne.s	.bp_otto
	move.w	#MISURA_BPU6,CL_GeomM+6
	bra.s	.bp_fatto
.bp_otto:
	move.w	#MISURA_BPU8,CL_GeomM+6
.bp_fatto:
	move.l	(sp)+,D0
.bp_release:
	move.b	D1,Ddf3Prev

; --- tasto 4: FMODE 64 bit <-> 32 bit ---
; A 32 bit l'allineamento dei BPLxPT scende da 8 a 4 byte, quindi il prefetch
; che serve allo scroll dimezza (64 -> 32 px) e DDFSTRT potrebbe stare a $28.
; L'immagine diventa illeggibile perche' la geometria non e' ritarata: non
; importa, si contano le BARRE. Sequenza della prova: tasto 4, poi tasto 2 due
; volte (DDF $18 -> $28), poi conta.
.k_fmode:
	cmp.b	#$04,D2					; tasto 4
	bne.s	.k_prof
	tst.b	D1
	beq.s	.fm_release
	tst.b	Ddf4Prev
	bne.s	.fm_release
	move.l	D0,-(sp)
	move.w	CL_GeomM+2,D0
	cmp.w	#MISURA_FMODE64,D0
	bne.s	.fm_64
	move.w	#MISURA_FMODE32,CL_GeomM+2
	bra.s	.fm_fatto
.fm_64:
	move.w	#MISURA_FMODE64,CL_GeomM+2
.fm_fatto:
	move.l	(sp)+,D0
.fm_release:
	move.b	D1,Ddf4Prev
;=== fine INNESTO 5 ========================================================"""

# ---------------------------------------------------------------------------
# Le ancore, sul Gioco.s PULITO: (riga 1-based, testo che deve starci, blocco)
# ---------------------------------------------------------------------------
ANCORE = [
    (648,  'DIW_WIDTH',                     INNESTO_1A),
    (1532, 'BSR.W\tAggiornaCopperSPR',      INNESTO_3),
    (1910, None,                            INNESTO_2),   # riga vuota dopo l'RTS
    (2757, 'move.b\tD1,LetteraKeyPrev',     INNESTO_5),
    (8398, 'BG_PLANE_BANDA',                INNESTO_7),
    (8421, 'bit 5-3 = PF2P',                INNESTO_6),
    (8550, 'dc.w\t$0106,BPLCON3_LOCT0',     INNESTO_4),
]
ANCORA_K_LETTERA = (2732, 'bne.s\t.k_prof')


def leggi():
    return open(SORG, encoding='utf-8').read().split('\n')


def scrivi(righe):
    t = '\n'.join(righe)
    if not t.endswith('\n'):
        t += '\n'
    open(SORG, 'w', encoding='utf-8', newline='\n').write(t)


def innestato(righe):
    return any(TAG in r for r in righe)


def togli(righe):
    """Ritaglia i blocchi marcati e rimette il salto di .k_lettera."""
    out, dentro, tolte = [], False, 0
    for r in righe:
        s = r.strip()
        if s.startswith(';===') and TAG in s:
            dentro = True
            tolte += 1
            continue
        if dentro:
            tolte += 1
            if s.startswith(';===') and 'fine INNESTO' in s:
                dentro = False
            continue
        if TAG in r:                      # l'INNESTO 3, riga singola
            tolte += 1
            continue
        out.append(r)
    if dentro:
        sys.exit('marcatore di apertura senza chiusura: non tolgo niente')
    n = sum(1 for r in out if '.k_ddfgiu' in r)
    out = [r.replace('.k_ddfgiu', '.k_prof') if '.k_ddfgiu' in r else r for r in out]
    return out, tolte, n


def metti(righe):
    for n, atteso, _b in ANCORE:
        if atteso and atteso not in righe[n - 1]:
            sys.exit('ANCORA ROTTA riga %d: mi aspettavo %r, trovo %r'
                     % (n, atteso, righe[n - 1]))
    n, atteso = ANCORA_K_LETTERA
    if atteso not in righe[n - 1]:
        sys.exit('ANCORA ROTTA riga %d (.k_lettera): trovo %r' % (n, righe[n - 1]))
    if 'RTS' not in righe[1908]:          # riga 1909, l'RTS di AggiornaCopperSPR
        sys.exit('ANCORA ROTTA: riga 1909 non e\' l\'RTS di AggiornaCopperSPR')

    # L'ancora dell'INNESTO 1b NON e' la direttiva `end` di Gioco.s: quella e'
    # gia' morta, perche' ptplayer.i ne ha una sua (riga 3974) e viene incluso
    # prima. Il punto giusto e' subito PRIMA di `SECTION PTPlayerCode,CODE`,
    # che cosi' resta l'ultima SECTION prima dell'include (ptplayer eredita la
    # SECTION corrente, e deve restare CODE).
    pt = [i for i, r in enumerate(righe, 1)
          if r.strip().upper().startswith('SECTION') and 'PTPlayerCode' in r]
    if len(pt) != 1:
        sys.exit('mi aspettavo UNA `SECTION PTPlayerCode`, ne trovo %d' % len(pt))
    n_pt = pt[0]
    inc = [i for i, r in enumerate(righe, 1)
           if 'include' in r.lower() and 'ptplayer.i' in r]
    if not inc or inc[0] <= n_pt:
        sys.exit('`include "ptplayer.i"` non e\' dopo SECTION PTPlayerCode')
    print('ancore verificate; SECTION PTPlayerCode riga %d, include riga %d'
          % (n_pt, inc[0]))

    # PRIMA il ripuntamento, POI gli inserimenti: e' una sostituzione, non
    # cambia il numero di righe, e farla dopo vorrebbe dire cercare la riga
    # 2732 quando gli inserimenti l'hanno gia' spostata a 2798. E' successo,
    # e l'ha preso misura-salti.py: .k_lettera continuava a saltare a .k_prof,
    # che gli inserimenti avevano portato a 194 byte di distanza.
    n, _a = ANCORA_K_LETTERA
    righe[n - 1] = righe[n - 1].replace('.k_prof', '.k_ddfgiu')
    if '.k_ddfgiu' not in righe[n - 1]:
        sys.exit('INVARIANTE ROTTO: riga %d non punta a .k_ddfgiu' % n)
    print('  riga %5d: .k_lettera salta a .k_ddfgiu' % n)

    tutte = list(ANCORE) + [(n_pt - 1, None, INNESTO_1B)]
    for n, _a, blocco in sorted(tutte, key=lambda t: -t[0]):
        righe[n:n] = blocco.split('\n')
        print('  riga %5d: +%d righe' % (n, len(blocco.split('\n'))))

    if sum(1 for r in righe if '.k_ddfgiu' in r) != 2:
        sys.exit('INVARIANTE ROTTO: .k_ddfgiu deve comparire 2 volte '
                 '(il salto di .k_lettera e la sua etichetta)')
    return righe


def main():
    righe = leggi()

    if '--togli' in sys.argv:
        if not innestato(righe):
            print('Gioco.s non ha innesti: niente da togliere.')
            return 0
        out, tolte, n_salti = togli(righe)
        scrivi(out)
        print('tolte %d righe, %d salto/i rimessi a .k_prof' % (tolte, n_salti))
        bk = backup()
        if os.path.isfile(bk):
            a = open(bk, 'rb').read()
            b = open(SORG, 'rb').read()
            print('INVARIANTE: identico al backup? %s' % ('SI' if a == b else 'NO'))
            if a != b:
                print('  NO va benissimo se hai modificato Gioco.s mentre gli')
                print('  innesti erano dentro: quelle modifiche sono ancora li\'.')
                print('  Per esserne sicuro: diff col backup %s'
                      % os.path.relpath(bk, RADICE))
        else:
            print('(nessun backup con cui confrontare)')
        return 0

    if innestato(righe):
        sys.exit('Gioco.s HA GIA\' gli innesti. Prima --togli.')

    print('backup: %s'
          % os.path.relpath(copie.metti_da_parte(SORG, SUFFISSO), RADICE))
    scrivi(metti(righe))
    print('\nGioco.s innestato. Per tornare indietro: '
          'py tools\\innesta-misura-sprite.py --togli')
    return 0


if __name__ == '__main__':
    sys.exit(main())
