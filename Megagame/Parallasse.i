; Parallasse.i - Parallasse degli alberi sugli sprite
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

* InitParallasseSprite - i puntatori dei canali, una volta al boot
*   La lista di ogni canale e' UN albero, e l'assegnazione albero->canale non
*   cambia mai: la Y di un albero e' fissa, quindi l'ha gia' decisa
*   tools/genera-alberi-sprite.py e sta in AlberiTab, in ordine di canale.
*   Qui si punta la posa 0 di ciascuno; da li' in poi il puntatore lo riscrive
*   AggiornaParallasseSprite a ogni quadro, perche' e' cosi' che si oscilla.
*   Questa routine serve a non far partire il display su puntatori mai scritti.
*   DISTRUGGE: nulla (salva tutto).
InitParallasseSprite:
	MOVEM.L	D0-D2/A0-A2,-(SP)
	LEA		AlberiTab,A0
	LEA		Sprites,A1					; la tabella dentro la copperlist
	MOVEQ	#ALBERI_N-1,D2
.canale:
	MOVE.L	ALBERI_OFS_POSA0(A0),D0		; offset della posa 0, LONG: l'arte
	ADD.L	#AlberiParallasse,D0		; supera i 32 KB
	MOVE.W	D0,6(A1)					; word bassa del puntatore
	SWAP	D0
	MOVE.W	D0,2(A1)					; word alta
	ADDQ.W	#8,A1
	LEA		ALBERI_VOCE(A0),A0
	DBRA	D2,.canale
	MOVEM.L	(SP)+,D0-D2/A0-A2
	RTS

* AggiornaParallasseSprite - la posizione dei sette alberi, e il vento
*   Il vento e' arte, non aritmetica: ogni albero ha VENTO_POSE disegni, uno
*   per grado di flessione, e oscillare vuol dire cambiare il PUNTATORE del
*   canale nella copperlist. Le pose sono contigue e lunghe uguali, quindi
*   l'indirizzo e' base + offset + posa*passo.
*   Il primo tentativo tagliava l'albero in tre sprite impilati e spostava in X
*   la cima e il mezzo. Costava un quinto della memoria e a schermo era brutto:
*   tre segmenti rigidi che scorrono uno sull'altro. La flessione disegnata e'
*   continua e tiene il fusto piantato a terra.
*   Posizione: HSTART = DIW_H_START - 64 + (x - offset) mod ALBERI_PERIODO,
*   con offset CameraX>>1 per i vicini e >>2 per i lontani. Il mod si fa UNA
*   VOLTA PER LIVELLO, non per albero: ridotto l'offset a 0..PERIODO-1,
*   x-offset sta in -(P-1)..P-1 e basta una addizione a raddrizzarlo.
*   NIENTE COMPENSAZIONE DI PathBDelay: gli sprite hanno HSTART assoluto.
*   DISTRUGGE: nulla (salva tutto).
AggiornaParallasseSprite:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	MOVEQ	#0,D0						; pulisce la parola alta per la DIVU
	MOVE.W	TileX,D0
	LSL.W	#4,D0						; TileX*16
	ADD.W	PixelOffX,D0				; D0 = CameraX
	MOVE.W	D0,ParSprOfs				; solo per la voce PO del profiler

	MOVE.L	D0,D1
	LSR.W	#ALBERI_SH_VICINO,D1
	DIVU	#ALBERI_PERIODO,D1
	SWAP	D1							; D1 = offset vicini, ridotto al periodo

	LSR.W	#ALBERI_SH_LONTANO,D0
	DIVU	#ALBERI_PERIODO,D0
	SWAP	D0							; D0 = offset lontani, ridotto

	; --- il tempo del vento. Un passo ogni 2^VENTO_LENTO quadri: il giro dura
	; VENTO_CICLO<<VENTO_LENTO quadri. A un passo per quadro sembrerebbe un
	; metronomo.
	ADDQ.W	#1,VentoT
	MOVE.W	VentoT,D7
	LSR.W	#VENTO_LENTO,D7

	LEA		AlberiTab,A0
	LEA		AlberiParallasse,A2
	LEA		Sprites,A3					; i puntatori dentro la copperlist
	MOVEQ	#ALBERI_N-1,D6
.albero:
	MOVE.W	ALBERI_OFS_X(A0),D3			; x nel periodo
	MOVE.W	ALBERI_OFS_LIV(A0),D4		; livello: 1 = vicino, 3 = lontano
	SUBQ.W	#1,D4
	BNE.S	.lontano
	SUB.W	D1,D3
	BRA.S	.ridotto
.lontano:
	SUB.W	D0,D3
.ridotto:
	BPL.S	.positivo					; x-offset sta in -(P-1)..P-1:
	ADD.W	#ALBERI_PERIODO,D3			; una sola addizione lo raddrizza
.positivo:
	ADD.W	#DIW_H_START-64,D3			; D3 = HSTART, fra 65 e 448

	; --- quale POSA mostra questo albero in questo quadro ---
	MOVE.W	ALBERI_OFS_FASE(A0),D5		; la sua fase, cosi' non vanno
	ADD.W	D7,D5						; all'unisono
	AND.W	#VENTO_CICLO-1,D5
	LEA		VentoCiclo,A1
	MOVE.B	0(A1,D5.W),D5
	EXT.W	D5							; D5 = posa, 0..VENTO_POSE-1

	; --- il puntatore del canale: base + offset della posa 0 + posa*passo ---
	MOVE.W	ALBERI_OFS_PASSO(A0),D4		; le pose sono lunghe uguali, quindi
	MULU	D4,D5						; il passo e' uno solo per albero
	MOVE.L	ALBERI_OFS_POSA0(A0),D2
	ADD.L	D2,D5
	ADD.L	A2,D5
	MOVE.W	D5,6(A3)					; word bassa di SPRxPT
	SWAP	D5
	MOVE.W	D5,2(A3)					; word alta
	ADDQ.W	#8,A3						; due MOVE di copper per canale

	; --- HSTART in TUTTE le pose, non solo in quella mostrata ---
	; Il copper legge i puntatori in cima al quadro, e questa routine gira dopo:
	; il cambio di posa arriva a schermo con un quadro di ritardo. Scrivendo
	; HSTART solo nella posa "corrente" il quadro in cui la posa cambia
	; mostrerebbe un blocco con l'HSTART vecchio di otto quadri, cioe' uno
	; scatto orizzontale. Scriverle tutte e cinque toglie la classe di problema
	; invece di rincorrere il timing: sono 4 istruzioni per posa.
	; Le pose di un albero hanno lo STESSO VSTART e lo stesso VSTOP, quindi
	; anche lo stesso SPRCTL: si compone una volta e si ricopia.
	MOVEA.L	A2,A1
	ADDA.L	D2,A1						; prima posa di questo albero
	MOVE.W	D3,D5
	LSR.W	#1,D5						; HSTART>>1 nel byte basso di SPRPOS
	AND.W	#1,D3						; il bit 0 sta nel byte basso di SPRCTL
	MOVE.B	ALBERO_OFS_CTL(A1),D2
	AND.B	#$FE,D2						; via il vecchio bit 0 di HSTART
	OR.B	D3,D2
	MOVEQ	#VENTO_POSE-1,D3
.posa:
	MOVE.B	D5,ALBERO_OFS_HSTART(A1)
	MOVE.B	D2,ALBERO_OFS_CTL(A1)
	ADDA.W	D4,A1
	DBRA	D3,.posa

	LEA		ALBERI_VOCE(A0),A0
	DBRA	D6,.albero

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
