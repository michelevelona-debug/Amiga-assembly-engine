; ============================================================================
; Intro.i - PRIMA VIDEATA DELL'INTRO: l'alba sul lembo della Terra.
;
; L'immagine non si muove MAI. Si muove solo la palette, e il copper la scrive
; in cima al quadro dove non si vede niente.
;
; COME STA IN PIEDI, dall'alto:
;   grafica/alba.raw        320x256 a 8 piani. E' l'immagine di ARRIVO, cioe'
;                           il giorno pieno. In chip: la legge il display.
;   AlbaCopper              un blocco di copperlist da ALBA_COP_WORDS word:
;                           per ogni banco di palette una MOVE su BPLCON3 e 32
;                           MOVE sui COLORxx, due volte (nibble alti e bassi).
;                           Le word di REGISTRO le scrive AlbaCostruisciCopper
;                           una volta al boot; quelle di VALORE cambiano a ogni
;                           quadro.
;   AlbaRampe               per ogni voce, ALBA_LIVELLI colori GIA' impacchettati
;                           nelle due word che il copper scrive. In fast.
;   AlbaInizio              per ogni voce, il quadro in cui parte la sua rampa.
;
; PERCHE' IL COPPER E NON LA CPU, ed e' aritmetica e non gusto.
; 256 voci a 24 bit sono 528 MOVE: 8 banchi x 2 passate x (1 BPLCON3 + 32
; COLOR). Se le scrivesse la CPU nei registri non finirebbe dentro il blank
; verticale, e il pennello beccherebbe meta' palette vecchia e meta' nuova:
; una cucitura orizzontale nei colori, per giunta mobile. Il copper le stesse
; 528 MOVE le fa in 528x4 = 2112 color clock, cioe' ~9,3 righe raster su 44 di
; blank. Alla CPU resta solo COSTRUIRE il blocco, e lo fa quando il copper ci
; e' gia' passato sopra: nessun doppio buffer.
;
; PERCHE' UNA TABELLA E NON UNA FORMULA.
; Il piano iniziale era: poche palette chiave, interpolazione lineare qui.
; MISURATO e scartato - con ogni voce su una tempistica sua e una rampa non
; lineare, l'interpolazione fra 17 chiavi sbaglia ancora 25 L*. Ma il colore
; di una voce dipende SOLO dalla sua fase, quindi la rampa si precalcola voce
; per voce e qui restano due MOVE.W. L'intelligenza sta in
; tools/genera-alba.py; questo file fa il playback.
;
; QUANDO SI SCRIVE, rispetto al pennello: AspettaVBL torna alla riga
; VBL_SYNC_LINE (220) e il blocco copper gira fra la riga 0 e la ~10. Si
; riscrive quindi per il quadro DOPO, con 90 righe di margine davanti e il
; copper gia' passato dietro.
; ============================================================================

* AlbaCostruisciCopper - le word di REGISTRO del blocco, una volta al boot
*   Il blocco nasce a zero (ds.w) e a zero sarebbe una MOVE su BLTDDAT: va
*   riempito PRIMA di puntarci il copper. I valori li lascia a zero: li scrive
*   AlbaPalette, che gira comunque prima che la lista vada a video.
AlbaCostruisciCopper:
	MOVEM.L	D0-D3/A0,-(SP)
	LEA		AlbaCopper,A0
	MOVEQ	#0,D0					; banco di palette, 0..ALBA_COP_BANCHI-1
.banco:
	MOVE.W	D0,D1
	LSL.W	#5,D1
	LSL.W	#8,D1					; banco << 13, come fa LoadAGAPalette256
									; (lo shift immediato si ferma a 8)
	; ---- passata dei nibble ALTI ----
	MOVE.W	D1,D2
	OR.W	#BPLCON3_LOCT0,D2
	MOVE.W	#$0106,(A0)+			; BPLCON3
	MOVE.W	D2,(A0)+
	MOVE.W	#$0180,D3				; COLOR00
	MOVEQ	#ALBA_COP_SLOT-1,D2
.alti:
	MOVE.W	D3,(A0)+				; il registro
	CLR.W	(A0)+					; il valore: lo mette AlbaPalette
	ADDQ.W	#2,D3
	DBRA	D2,.alti
	; ---- passata dei nibble BASSI ----
	MOVE.W	D1,D2
	OR.W	#BPLCON3_LOCT1,D2
	MOVE.W	#$0106,(A0)+
	MOVE.W	D2,(A0)+
	MOVE.W	#$0180,D3
	MOVEQ	#ALBA_COP_SLOT-1,D2
.bassi:
	MOVE.W	D3,(A0)+
	CLR.W	(A0)+
	ADDQ.W	#2,D3
	DBRA	D2,.bassi

	ADDQ.W	#1,D0
	CMP.W	#ALBA_COP_BANCHI,D0
	BLT.W	.banco					; .W e non .S: il corpo e' lungo
	MOVEM.L	(SP)+,D0-D3/A0
	RTS

* AlbaPalette - scrive nel blocco copper la palette del quadro D0
*   IN: D0.w = numero del quadro. Sopra ALBA_QUADRI-1 non succede niente di
*       male: ogni voce si ferma sull'ultimo livello, cioe' sul giorno pieno.
*   Le due word di una voce NON sono adiacenti nel blocco: i nibble alti
*   stanno nella prima passata del banco e i bassi nella seconda, a
*   ALBA_COP_LO_OFS byte di distanza. Nella tabella invece sono attaccate, e
*   una MOVE.L le prende tutte e due.
AlbaPalette:
	MOVEM.L	D0-D5/A0-A2,-(SP)
	LEA		AlbaInizio,A0			; il quadro d'inizio, voce per voce
	LEA		AlbaRampe,A1			; la rampa della voce corrente
	LEA		AlbaCopper+6,A2			; la word di VALORE della prima MOVE:
									; +0 e' il registro BPLCON3, +4 il registro
									; COLOR00, +6 il suo valore
	MOVEQ	#ALBA_COP_BANCHI-1,D5
.banco:
	MOVEQ	#ALBA_COP_SLOT-1,D1
.voce:
	MOVE.W	D0,D4
	SUB.W	(A0)+,D4				; quadro - inizio DI QUESTA voce
	BPL.S	.partita
	MOVEQ	#0,D4					; non e' ancora il suo turno
.partita:
	LSR.W	#ALBA_LIV_SH,D4			; -> livello nella rampa
	CMP.W	#ALBA_LIVELLI-1,D4
	BLE.S	.dentro
	MOVE.W	#ALBA_LIVELLI-1,D4		; arrivata in fondo, e li' resta
.dentro:
	ADD.W	D4,D4
	ADD.W	D4,D4					; livello * 4 byte
	MOVE.L	0(A1,D4.W),D3			; nibble alti << 16 | nibble bassi
	MOVE.W	D3,ALBA_COP_LO_OFS(A2)	; i bassi, nella seconda passata
	SWAP	D3
	MOVE.W	D3,(A2)					; gli alti, in questa
	ADDA.W	#ALBA_RAMPA_VOCE,A1		; prossima voce nella tabella
	ADDQ.W	#4,A2					; prossima MOVE del copper
	DBRA	D1,.voce
	ADDA.W	#ALBA_COP_SALTO,A2		; scavalca il BPLCON3 e la passata bassa
	DBRA	D5,.banco
	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

* IntroEsegui - la scena. Torna quando l'utente preme fuoco o barra.
*   La musica del titolo continua: la ferma il chiamante, dopo.
*   LA GEOMETRIA DI DISPLAY E' QUELLA DEL TITOLO - 8 piani, prelievo a 64 bit,
*   DDF $28..$a8 - e non e' pigrizia: condividendola, il passaggio
*   titolo -> intro non tocca un registro e non c'e' una terza configurazione
*   da tenere in pari. Il nome della routine dice "Titolo" perche' e' li' che i
*   valori sono definiti; quando anche l'intro sara' provata sul ferro vale la
*   pena rinominare le due in ImpostaDisplay8Piani.
*   Il DMA non si tocca: BPL, COP e master sono gia' accesi da ShowTitle.
IntroEsegui:
	MOVEM.L	D0-D7/A0-A6,-(SP)
	LEA		$DFF000,A6

	BSR.W	AlbaCostruisciCopper

	; i puntatori bitplane della lista dell'intro, sull'immagine di arrivo
	LEA		IntroBPL_0,A1
	MOVE.L	#AlbaImg,D0
	MOVEQ	#ALBA_PIANI-1,D1
.bpl:
	MOVE.W	D0,6(A1)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)				; word alta
	SWAP	D0
	ADD.L	#ALBA_PLANE_SIZE,D0
	ADDQ.L	#8,A1
	DBRA	D1,.bpl

	; il quadro 0 PRIMA di mostrare la lista: se no il primo quadro uscirebbe
	; con le word di valore ancora a zero, cioe' schermo nero per un quadro
	CLR.W	AlbaQuadro
	MOVEQ	#0,D0
	BSR.W	AlbaPalette

	BSR.W	AspettaVBL				; si cambia lista nel blank, non a meta' quadro
	BSR.W	ImpostaDisplayTitolo
	MOVE.L	#IntroCopperList,$80(A6)	; COP1LCH
	MOVE.W	D0,$88(A6)				; COPJMP1 (strobe: il valore non conta)

.giro:
	BSR.W	AspettaVBL
	MOVE.W	AlbaQuadro,D0
	BSR.W	AlbaPalette
	CMP.W	#ALBA_QUADRI-1,AlbaQuadro
	BGE.S	.ferma
	ADDQ.W	#1,AlbaQuadro
.ferma:
	BSR.W	LeggiTastiera
	TST.B	key_space
	BNE.S	.premuto
	MOVE.B	$bfe001,D0				; CIA-A PRA: bit 7 = fuoco joy1, attivo basso
	NOT.B	D0
	AND.B	#$80,D0
	BEQ.S	.giro

.premuto:
	; Si aspetta il RILASCIO, come fa WaitTitleInput: se no il gioco vede
	; subito un colpo di fuoco che l'utente non ha dato. L'alba intanto
	; continua, cosi' tenere premuto non la congela.
.rilascio:
	BSR.W	AspettaVBL
	MOVE.W	AlbaQuadro,D0
	BSR.W	AlbaPalette
	CMP.W	#ALBA_QUADRI-1,AlbaQuadro
	BGE.S	.ferma2
	ADDQ.W	#1,AlbaQuadro
.ferma2:
	BSR.W	LeggiTastiera
	TST.B	key_space
	BNE.S	.rilascio
	MOVE.B	$bfe001,D0
	NOT.B	D0
	AND.B	#$80,D0
	BNE.S	.rilascio

	MOVE.W	#0,FirePrev
	MOVE.B	#0,key_space
	MOVEM.L	(SP)+,D0-D7/A0-A6
	RTS
