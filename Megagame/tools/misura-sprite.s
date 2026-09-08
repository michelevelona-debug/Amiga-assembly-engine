;=====================================================================
; misura-sprite.s - QUANTI CANALI SPRITE SOPRAVVIVONO, davvero
;
; Codice USA E GETTA. Non e' un pezzo del gioco: si incolla, si guarda,
; si toglie. Sta qui e non in Gioco.s apposta.
;
;---------------------------------------------------------------------
; A CHE DOMANDA RISPONDE
;
; La tabella in convenzioni.md dice che a DDFSTRT $18 sopravvive UN solo
; sprite. Quella tabella descrive il fetch CONTINUO, cioe' il caso in cui
; ogni slot dopo DDFSTRT e' occupato dai bitplane. Con FMODE=3 il fetch e'
; a RAFFICHE - 8 slot ogni 32 color clock, uno per piano - e fra una
; raffica e l'altra restano buchi in cui il DMA sprite puo' vivere.
;
; Quindi la tabella e' probabilmente PESSIMISTICA per questa macchina, e
; "probabilmente" non e' un numero. Questo innesto mette a schermo otto
; barre verticali, una per canale, e le lascia contare.
;
;---------------------------------------------------------------------
; IL NUMERO CHE CAMBIA TUTTO: DDFSTRT VALE $18, NON $38 (2 settembre)
;
; Nella copperlist si legge
;     CL_Ddf:  dc.w $0092,$0038,$0094,$00b8
; ma quei valori sono SEGNAPOSTO, e il commento sopra lo dice: PathBInit li
; sovrascrive al boot con SCROLL_DDFSTRT e SCROLL_DDFSTOP. E
;     SCROLL_DDFSTRT  EQU  $38-32     ; = $18
;
; $18 e' il primo valore della tabella, quello in cui sopravvive UN SOLO
; sprite - e con OTTO bitplane, nemmeno quello. E' il motivo per cui le barre
; si vedono per un istante all'avvio, mentre il display non ha ancora la
; geometria di gioco, e spariscono appena entra in funzione.
;
; MORALE: leggere il DDF dalla copperlist e' leggere un segnaposto. Il valore
; vero e' quello che mostra il profiler col tasto P, che legge CL_Ddf+2 DOPO
; la patch.
;
; E' anche la ragione per cui i tasti 1 e 2 sono la parte piu' importante di
; questo innesto: la misura non e' "quante barre si vedono", e' "quante barre
; si vedono A OGNI VALORE DI DDFSTRT". Con passo 8 si passa per $18, $20, $28,
; $30, $38, cioe' esattamente le righe della tabella classica.
;
;---------------------------------------------------------------------
; LA PRIORITA'. Senza, non si vede niente (2 settembre)
;
; Il primo giro non ha mostrato NESSUNA barra, solo una traccia in fondo al
; pannello. Non era il DMA: era che gli sprite finivano DIETRO al playfield.
;
; Nella copperlist di gioco c'e'
;     dc.w  $104,$0024    ; BPLCON2 = PF2P=4, PF1P=4
; col commento "(4 = primi 4 sprite davanti)". E' FALSO. In BPLCON2 i bit 5-3
; sono PF2P e i 2-0 PF1P, e il valore e' il numero di GRUPPI di sprite davanti
; ai quali sta il playfield:
;
;   0  playfield dietro a tutti gli sprite
;   1  playfield davanti a SPR0-1
;   2  playfield davanti a SPR0-3
;   3  playfield davanti a SPR0-5
;   4  playfield davanti a TUTTI E OTTO
;
; Con 4 su tutti e due i campi gli sprite stanno dietro a un'area di gioco a 8
; piani quasi sempre opaca: ci sono e non si vedono. La traccia in fondo al
; pannello era esattamente questo, un punto dove il pixel vale 0.
;
; L'INNESTO 6 aggiunge un secondo MOVE a $104 subito dopo il primo (nessun WAIT
; in mezzo, quindi vince) che mette $0000. Solo per la durata della misura.
;
; LA PRIORITA' NON C'ENTRA COL DMA: quante barre arrivano non cambia, cambia
; solo che si vedono. Il numero che si misura resta lo stesso.
;
; DA TENERE PRESENTE PER LA PARALLASSE A SPRITE: che gli sprite stiano DIETRO
; al playfield e' esattamente quello che serve a uno sfondo. Il valore attuale
; non e' un difetto da correggere, e' gia' quello giusto per lo scopo.
;
;---------------------------------------------------------------------
; COME SI LEGGE
;
; Le barre attraversano l'area di gioco E il pannello. Il pannello gira a
; 4 bitplane, l'area di gioco a 8: una barra che si vede sul pannello ma
; sparisce sull'area di gioco dice che a ucciderla e' il numero di piani,
; non DDFSTRT. E' la meta' della risposta, gratis.
;
;   barra intera        -> il canale sopravvive dappertutto
;   barra solo in basso -> muore con 8 piani, vive con 4
;   barra assente       -> il canale non c'e'
;
; I tasti 1 e 2 spostano DDFSTRT di MISURA_DDF_PASSO. Il valore corrente
; si legge col tasto P, alla voce DDF del profiler: c'e' gia', la legge
; dalla copperlist.
;
; ATTENZIONE, e non e' un difetto: con un passo di 8 la differenza
; (DDFSTOP-DDFSTRT) smette di essere multipla di 32 e il fetch dei
; bitplane va fuori sincrono. LO SFONDO DIVENTA ILLEGGIBILE. E' atteso:
; gli sprite non c'entrano col fetch dei bitplane, e quello che si conta
; sono le BARRE, non l'immagine. Se vuoi tenere l'immagine sana metti
; MISURA_DDF_PASSO a 32, ma salti tutti i valori interessanti in mezzo.
;
; I colori delle barre li scrive l'INNESTO 4 nella copperlist, dopo la
; palette, cosi' vincono su di essa. Sono scritti con la sola passata
; LOCT0, quindi i nibble bassi restano quelli del gioco: le tinte
; risultano un po' storte ed e' voluto - servono a distinguere le barre,
; non a essere belle.
;
;=====================================================================
; INNESTO 1 - le EQU e i buffer. VA SPEZZATO IN DUE.
;
; 1a) le EQU: IN TESTA a Gioco.s, con le altre, subito dopo DIW_WIDTH.
;     MISURA_SPR_HBASE discende da DIW_H_START, e il MOVEQ dell'INNESTO 2
;     vuole un valore assoluto gia' noto: messe in fondo danno
;     "error 2025: absolute value expected".
; 1b) le SECTION e i buffer: subito PRIMA della direttiva `end`, in fondo.
;     DOPO `end` l'assemblatore non legge piu' niente - le righe ci sono,
;     si leggono, e non esistono. E' l'errore preso il 2 settembre.
;
; Se lo fa lo script (tools/innesta-misura-sprite.py) la divisione e' gia'
; fatta e non c'e' niente da ricordarsi.
;=====================================================================

; Le barre partono dentro l'area di gioco (che va da $2C=44 a 220) e
; finiscono dentro il pannello (222..302): cosi' una sola occhiata dice
; sia se il canale c'e', sia se muore per colpa degli 8 piani.
MISURA_SPR_N		EQU		8			; gli otto canali
MISURA_SPR_VSTART	EQU		80
MISURA_SPR_VSTOP	EQU		290
MISURA_SPR_RIGHE	EQU		MISURA_SPR_VSTOP-MISURA_SPR_VSTART
; HSTART e' in px lores dal bordo del pennello, e la finestra comincia a
; DIW_H_START: la prima barra cade a 12 px dentro lo schermo.
MISURA_SPR_HBASE	EQU		DIW_H_START+12
MISURA_SPR_HPASSO	EQU		37			; 8 barre da 16 px in 320: ci stanno
MISURA_SPR_WORDS	EQU		2+MISURA_SPR_RIGHE*2+2	; 2 di controllo + corpo + fine
MISURA_SPR_SZ		EQU		MISURA_SPR_WORDS*2
MISURA_DDF_PASSO	EQU		8			; 32 per tenere l'immagine leggibile

	SECTION	MisuraSprite,DATA_C
	cnop	0,8
BarreSprite:
	ds.b	MISURA_SPR_SZ*MISURA_SPR_N

	SECTION	MisuraSpriteVar,DATA
Ddf1Prev:	dc.b	0
Ddf2Prev:	dc.b	0
	EVEN

;=====================================================================
; INNESTO 2 - il costruttore.
; Metti nella SECTION del codice, per esempio subito dopo
; AggiornaCopperSPR.
;=====================================================================

;---------------------------------------------------------------------
; BuildBarreSprite - otto barre verticali, una per canale, e i puntatori
;   scritti nella tabella Sprites della copperlist.
;
;   Gli sprite PARI usano il valore 1 e i DISPARI il valore 2: dentro una
;   coppia i due canali condividono i colori, e cosi' ognuno degli otto
;   prende una voce diversa (17/18, 21/22, 25/26, 29/30).
;
;   DISTRUGGE: nulla (salva tutto).
;---------------------------------------------------------------------
BuildBarreSprite:
	MOVEM.L	D0-D5/A0-A1,-(SP)
	LEA		BarreSprite,A0
	LEA		Sprites,A1					; la tabella dentro la copperlist
	MOVEQ	#0,D4						; indice del canale
	MOVEQ	#MISURA_SPR_N-1,D5
.canale:
	; --- il puntatore, nella forma che vuole la copperlist ---
	MOVE.L	A0,D0
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	ADDQ.W	#8,A1

	; --- HSTART di questa barra ---
	MOVE.W	D4,D0
	MULU	#MISURA_SPR_HPASSO,D0
	ADD.W	#MISURA_SPR_HBASE,D0		; D0 = HSTART

	; SPRPOS = VSTART basso su 8 bit, HSTART senza il bit 0
	MOVE.W	D0,D1
	LSR.W	#1,D1
	AND.W	#$FF,D1
	OR.W	#(MISURA_SPR_VSTART&$FF)<<8,D1
	MOVE.W	D1,(A0)+

	; SPRCTL = VSTOP basso, piu' i bit alti di VSTART/VSTOP e il bit 0 di
	; HSTART. VSTOP e' oltre la riga 255, quindi il suo bit 8 e' acceso.
	MOVE.W	#((MISURA_SPR_VSTOP&$FF)<<8)|(((MISURA_SPR_VSTART>>8)&1)<<2)|(((MISURA_SPR_VSTOP>>8)&1)<<1),D1
	AND.W	#1,D0						; bit 0 di HSTART
	OR.W	D0,D1
	MOVE.W	D1,(A0)+

	; --- il corpo: tutto acceso su un piano solo ---
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

;=====================================================================
; INNESTO 3 - la chiamata.
; Va DOPO AggiornaCopperSPR, che punta tutti e otto gli sprite a
; EmptySprite: chiamandola prima verrebbe sovrascritta.
; Cerca in Gioco.s la riga
;     BSR.W  AggiornaCopperSPR
; e mettici sotto:
;=====================================================================
;	BSR.W	BuildBarreSprite		; INNESTO: le otto barre di prova
;
; DMACON non si tocca: DMASET ha gia' SPREN acceso.

;=====================================================================
; INNESTO 4 - i colori delle barre.
; Nella copperlist del GIOCO (CopperList, non TitleCopperList), subito
; DOPO il secondo blocco di palette, cioe' dopo GamePalLo e la riga che
; rimette BPLCON3 a LOCT0. Le voci sono le prime due di ogni coppia:
; 17/18 per SPR0-1, 21/22 per SPR2-3, 25/26 per SPR4-5, 29/30 per SPR6-7.
;=====================================================================
;	dc.w	$01a2,$0f00, $01a4,$00f0	; SPR0 rosso   SPR1 verde
;	dc.w	$01aa,$004f, $01ac,$0ff0	; SPR2 blu     SPR3 giallo
;	dc.w	$01b2,$0f0f, $01b4,$00ff	; SPR4 magenta SPR5 ciano
;	dc.w	$01ba,$0fff, $01bc,$0f80	; SPR6 bianco  SPR7 arancio

;=====================================================================
; INNESTO 5 - i due tasti che spostano DDFSTRT.
; Nella catena di LeggiTastiera. Aggancia il blocco alla catena come gli
; altri: l'ultimo test prima di .k_prof deve saltare a .k_ddfgiu, e
; .k_ddfsu deve saltare a .k_prof.
;
; DDFSTRT si scrive nella COPPERLIST (CL_Ddf+2) e non nel registro: e' il
; copper a riscriverlo a ogni quadro, quindi il registro tornerebbe
; indietro subito. E' la stessa word che legge il profiler per mostrare
; DDF, quindi il numero a schermo e' sempre quello vero.
;=====================================================================
;.k_ddfgiu:
;	cmp.b	#$01,D2					; tasto 1
;	bne.s	.k_ddfsu
;	tst.b	D1
;	beq.s	.dg_release
;	tst.b	Ddf1Prev
;	bne.s	.dg_release
;	move.l	D0,-(sp)
;	move.w	CL_Ddf+2,D0
;	sub.w	#MISURA_DDF_PASSO,D0
;	cmp.w	#$18,D0
;	bcc.s	.dg_ok
;	move.w	#$18,D0
;.dg_ok:
;	move.w	D0,CL_Ddf+2
;	move.l	(sp)+,D0
;.dg_release:
;	move.b	D1,Ddf1Prev
;
;.k_ddfsu:
;	cmp.b	#$02,D2					; tasto 2
;	bne.s	.k_prof
;	tst.b	D1
;	beq.s	.ds_release
;	tst.b	Ddf2Prev
;	bne.s	.ds_release
;	move.l	D0,-(sp)
;	move.w	CL_Ddf+2,D0
;	add.w	#MISURA_DDF_PASSO,D0
;	cmp.w	#$38,D0
;	bls.s	.ds_ok
;	move.w	#$38,D0
;.ds_ok:
;	move.w	D0,CL_Ddf+2
;	move.l	(sp)+,D0
;.ds_release:
;	move.b	D1,Ddf2Prev

;=====================================================================
; LA SECONDA MISURA, quella che vale quanto la prima
;
; Rifai il giro con SEI bitplane invece di otto. E' una riga sola: nella
; CopperList del gioco, il BPLCON0 che dice 8 piani
;     dc.w  $0100,%0000001000010001
; diventa
;     dc.w  $0100,%0110001000000001      ; BPU=6
; La parallasse sparisce (i piani 7-8 non vengono piu' letti) ed e'
; proprio la domanda: se togliendo quei due piani tornano dei canali,
; allora spostare la parallasse sugli sprite se li ripaga da sola.
;
; QUELLO CHE ANCORA NON SI SA DOPO QUESTA PROVA: gli sprite da 64 px.
; Vogliono i bit sprite di FMODE ($0F invece di $03), che cambiano anche
; il formato dei dati sprite, e FMODE e' il registro che ha gia' reso
; illeggibile la title screen sul ferro vero mentre in WinUAE era
; perfetta. Va provato a parte, e presto.
;
;---------------------------------------------------------------------
; BPLCON4: DOMANDA CHIUSA, e l'errore era mio (2 settembre)
;
; C'era scritto qui che il commento della copperlist fosse falso, cioe'
; che $0011 mettesse $11 in BPLAM. Era sbagliato: il layout vero e'
;
;   bit 15-8  BPLAM   XOR sull'indice di colore dei bitplane
;   bit 7-4   ESPRM   4 bit ALTI dell'indice degli sprite PARI
;   bit 3-0   OSPRM   4 bit ALTI dell'indice degli sprite DISPARI
;
; che e' quello scritto nell'intestazione di PALETTE in Gioco.s. Quindi
; $0011 = BPLAM $00, ESPRM $1, OSPRM $1, ed e' anche il valore di reset
; dell'AGA: e' il modo di dire "sprite ai colori 16-31 come su OCS".
;
; Le due strade che lo confermano senza accendere la macchina:
;   - se BPLAM valesse $11 tutti i colori del gioco sarebbero in XOR con
;     $11, e non lo sono. Il copper scrive $0011 a ogni quadro;
;   - un valore di reset che sporca i bitplane non avrebbe senso.
;
; Cade con l'errore anche il "compromesso" descritto in copperlist: BPLAM
; e OSPRM NON condividono bit, quindi sprite pari e dispari si possono
; mandare su due blocchi di 16 colori qualsiasi, ognuno per conto suo,
; con i bitplane intatti. Per una parallasse a sprite e' esattamente la
; leva che serve: ESPRM=$4 porta gli sprite pari ai colori $40..$4F.
;
; QUESTO INNESTO LO RIVERIFICA DA SOLO, gratis: le otto barre prendono i
; colori 17/18, 21/22, 25/26, 29/30 SOLO se ESPRM/OSPRM valgono davvero
; $1. Se le barre escono coi colori del gioco invece che con le tinte
; sgargianti dell'INNESTO 4, allora il layout e' un altro e questa nota
; va riscritta.
;
; EFFETTO COLLATERALE ATTESO dell'INNESTO 4: le voci 17, 18 e 25 le usa
; l'arte del gioco (16-20 le sagome, 24/25/27 la pietra). Durante la
; misura quei colori sono sbagliati. E' cosmetico e sparisce togliendo
; l'innesto.
;=====================================================================
