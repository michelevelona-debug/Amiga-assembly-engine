*****************************************************************************
*				   MEGA GAME												*
*																			*
*   Gestire collisioni														*
*   Aggiungere nemico Bob													*
*   Muovere omino in tutte le direzioni con una sua AI						*
*   Gestire collisioni con sfondo e sprite									*
*   Inserire grafiche 														*
*   Aggiungere effetti audio												*
*   Aggiungere musica														*
*   Inserire logica di gioco (PF, punti, game over)							*
*																			*
*****************************************************************************

	SECTION	MegaGame,CODE

*****************************************************************************
	include	"startup1.i"		; Salva Copperlist Etc.
*****************************************************************************
; Con DMASET decidiamo quali canali DMA aprire e quali chiudere

			;5432109876543210
DMASET	EQU	%1000001111000000	; blitter, copper, bitplane DMA

*****************************************************************************
* COSTANTI
*****************************************************************************
PLANE_SIZE      EQU     40*256          ; 10240 byte = un singolo bitplane

XTiles			EQU	16
YTiles			EQU 16

MAPPA_COLS 		EQU	24
MAPPA_ROWS		EQU	22
BUFFER_COLS		EQU	22
BUFFER_ROWS		EQU	18
VIS_COLS		EQU	20
VIS_ROWS		EQU	16

; TILEXMAX / TILEYMAX = numero massimo che TileX/TileY puo' raggiungere.
; Il buffer carica MAPPA[TileY..TileY+BUFFER_ROWS-1][TileX..TileX+BUFFER_COLS-1],
; quindi TileX+BUFFER_COLS-1 <= MAPPA_COLS-1  =>  TileX <= MAPPA_COLS-BUFFER_COLS.
; Con mappa 18x24 e buffer 18x22 => TILEXMAX=2, TILEYMAX=0 (no scroll Y di tile).
; Per abilitare lo scroll Y di tile: estendi MAPPA a >=20 righe e aggiorna MAPPA_ROWS.

TILEXMAX		EQU	MAPPA_COLS-BUFFER_COLS
TILEYMAX		EQU	MAPPA_ROWS-BUFFER_ROWS
PLAYER_MAX_X    EQU	(MAPPA_COLS*16)-16-32   ; 344 (bob_X max 288 = 320-32 viewport)
PLAYER_MAX_Y    EQU	(MAPPA_ROWS*16)-16-32   ; 304 (bob_Y max 240 = 256-16 viewport)

;------------------------------------------------------------
; Costanti tasti freccia (identici ai rawkey Intuition)
;------------------------------------------------------------
RAWKEY_UP		EQU $4C
RAWKEY_DOWN		EQU $4D
RAWKEY_RIGHT	EQU $4E
RAWKEY_LEFT	 	EQU $4F

KEY_RELEASE_BIT EQU 7	   ; bit 7 del keycode decodificato
ANIM_DELAY		EQU 3
START:
*****************************************************************************
*	PUNTIAMO I BITPLANES DELLE TILES
*****************************************************************************

	MOVE.L	CurrentDisplay,D0		; in d0 l'indirizzo della memoria per la mappa,
	BSR.W	AggiornaCopperBPL

	LEA		$dff000,A6
	MOVE.W	#DMASET,$96(A6)			; DMACON - abilita dma
	MOVE.L	#CopperList,$80(A6)		; Puntiamo la nostra COP
	MOVE.W	d0,$88(A6)				; Facciamo partire la COP
	MOVE.W	#0,$1fc(A6)				; Disattiva l'AGA
	MOVE.W	#$c00,$106(A6)			; Disattiva l'AGA
	MOVE.W	#$11,$10c(A6)			; Disattiva l'AGA

	BSR.W   InitPlayer				; <-- INIZIALIZZA IL PLAYER
	BSR.W	BuildOminoMask			; Genera la maschera dell'OMINO al boot

	BSR.W	DisegnaSfondo			; Routine che disegna lo sfondo

	; Pre-render su entrambi i buffer per evitare il primo frame nero
	BSR.W	CopiaVideo				; copia su CurrentDraw = BPSFONDO_B
	BSR.W	AspettaBlitter
	BSR.S	SwapBuffers				; ora display = B, draw = A
	BSR.W	CopiaVideo				; copia anche su A
	BSR.W	AspettaBlitter
	; (al primo giro del loop il display è B, e disegnamo su A — entrambi pronti)
 
.mainloop:
*****************************************************************************
	BSR.W	ReadKeyboard			; Routine che legge la tastiera
	BSR.W	LeggiJoystick			; Routine che legge il Joystick	
	BSR.W	GateScrollByCenter		; Se bob NON al centro, azzera ScrllX/Y
	BSR.W	UpdatePlayerWorldPos	; Aggiorna PlayerWorldX/Y (Fase 2)
	BSR.W	ControllaBordi			; Controllo dei bordi
	BSR.W	GestisciShiftPixel		; Esegue lo scrolling fine
	BSR.W	AggiornaTiles			; Gestisce l'agggiunta di tiles dalla mappa
									; al buffer	
	BSR.W	CopiaVideo				; Disegna lo schermo
	BSR.W	UpdatePlayerScreenPos	; Calcola bob_X/Y dalle coord. mondo 
;	BSR.S 	SxMouse
;	BSR.W	DisegnaBOBNemici		; sui bitplane di CurrentDraw
	BSR.W	DisegnaBOBPlayer		; idem, dopo i nemici per z-ordering

; --- Sincronizzazione e swap ---
	BSR.W	AspettaBlitter
	BSR.S	AspettaVBL
	BSR.S	SwapBuffers				; aggiorna BPL pointers in copperlist + scambia variabili

	BTST.B	#6,$bfe001				; tasto sx del mouse premuto?
	BNE.S	.mainloop
	RTS
*****************************************************************************
* ASPETTA VBL
*****************************************************************************
AspettaVBL:
	MOVEM.L D0-D2,-(SP)

	MOVE.L  #$1ff00,D1
	MOVE.L  #$10800,D2		  ; linea $108
.wait:
	MOVE.L  $dff004,D0		  ; VPOSR
	AND.L   D1,D0
	CMP.L   D2,D0
	BNE.S   .wait
	movem.l (SP)+,D0-D2
	RTS

*****************************************************************************
* ROUTINE DI SWAP DEL BUFFER
*****************************************************************************
*****************************************************************************
SwapBuffers:
	MOVEM.L D0-D1,-(SP)
; Scambia CurrentDisplay e CurrentDraw
	MOVE.L  CurrentDisplay,D0
	MOVE.L  CurrentDraw,D1
	MOVE.L  D1,CurrentDisplay
	MOVE.L  D0,CurrentDraw

; Aggiorna copperlist con il nuovo CurrentDisplay (= D1)
	MOVE.L  D1,D0
	BSR.S   AggiornaCopperBPL

	movem.l (SP)+,D0-D1
	RTS

*****************************************************************************
* AGGIORNA I BPL POINTER NELLA COPPERLIST
* INPUT:  D0 = indirizzo del primo bitplane
* OUTPUT: 5 BPL pointer aggiornati a partire da BitPlaneTiles
* DISTRUGGE: D0, A1 (e usa internamente D1)
*****************************************************************************
AggiornaCopperBPL:
	MOVEM.L D1/A1,-(SP)
	LEA	 BitPlaneTiles,A1
	MOVEQ   #5-1,D1				; 5 bitplane
.loop:
	MOVE.W	D0,6(A1)			; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)			; word alta
	SWAP	D0
	ADD.L	#40*256,D0			; prossimo bitplane
	ADDQ.W	#8,A1				; prossimi 4 dc.w nella copperlist
	DBRA	D1,.loop
	
	MOVEM.L	(SP)+,D1/A1
	RTS
 
*****************************************************************************
* ROUTINE DI ATTESA TASTO DI SX DEL MOUSE 
*****************************************************************************
SxMouse:
.waitsxpress:
	BTST.B	#6,$bfe001		; tasto sx del mouse premuto?
	BNE.S	.waitsxpress
.waitsxrelease:
	BTST.B	#6,$bfe001		; tasto sx del mouse rilasciato?
	BEQ.S	.waitsxrelease
	RTS

*****************************************************************************
* ROUTINE DI ATTESA
*****************************************************************************
Attesa:
	movem.l d7,-(SP)
	MOVE.L	#1000000,D7
.attesaloop:
	SUBQ.L	#1,D7
	BNE		.attesaloop
	movem.l (SP)+,d7
	RTS

*****************************************************************************
* LEGGI JOYSTICK 
*****************************************************************************
LeggiJoystick:
	movem.l D0-D3/A0-A1,-(SP)

	MOVE.W	#0,ScrllX	; inizializzo lo spostamento orizzontale
	MOVE.W	#0,ScrllY	; inizializzo lo spostamento verticale
						; Mappatura bit dopo NOT:
						; Bit 0 = Destra
						; Bit 1 = Sinistra
						; Bit 8 = Basso
						; Bit 9 = Alto

	MOVE.W	$DFF00C,D3	; JOY1DAT
	BTST.L	#1,D3		; il bit 1 ci dice se si va a destra
	BEQ.S	.NODESTRA	; se vale zero non si va a destra
	ADDQ.W	#1,ScrllX	; 
	BRA.S	.CHECK_Y	; vai al controllo della Y
.NODESTRA:
	BTST	#9,D3		; il bit 9 ci dice se si va a sinistra
	BEQ.S	.CHECK_Y	; se vale zero non si va a sinistra
	SUBQ.W	#1,ScrllX	; 
.CHECK_Y:
	MOVE.W	D3,D2		; copia il valore del registro
	LSR.W	#1,D2		; fa scorrere i bit di un posto verso destra 
	EOR.W	D2,D3		; esegue l'or esclusivo. Ora possiamo testare
	BTST	#8,D3		; testiamo se va in alto
	BEQ.S	.NOALTO		; se no controlla se va in basso
	SUBQ.W	#1,ScrllY	; se si scrolling in basso
	BRA.S	.ENDJOYST
.NOALTO:
	BTST	#0,D3		; testiamo se va in basso
	BEQ.S	.ENDJOYST	; se no finisci
	ADDQ.W	#1,ScrllY	; se si scrolling in alto
.ENDJOYST:
;--- POLLING TASTIERA --------------------------------------
; Le flag arrow_* sono settate da ProcessArrowKey alla pressione
; e azzerate al rilascio. Qui le leggiamo ogni frame per generare
; movimento continuo finche' il tasto resta premuto.
; Nota: i tasti freccia possono sommarsi al joystick (entrambi
; settano +1/-1 sulla stessa variabile), quindi se premi joystick
; destra E freccia destra contemporaneamente non si raddoppia: il
; valore si limita comunque a +/-1 perche' usiamo flag binarie.
	TST.b	arrow_up
	BEQ.s	.no_kup
	MOVE.w	#-1,ScrllY
.no_kup:
	TST.b	arrow_dn
	BEQ.s	.no_kdn
	MOVE.w	#1,ScrllY
.no_kdn:
	tst.b	arrow_sx
	beq.s	.no_ksx
	move.w	#-1,ScrllX
.no_ksx:
	tst.b	arrow_rx
	beq.s	.no_krx
	move.w	#1,ScrllX
.no_krx:

;------------------------------------------------------------
; CALCOLO DIREZIONE DEL PLAYER da ScrllX/ScrllY
;
; Indice nella tabella = (ScrllY+1)*3 + (ScrllX+1)
;
;            ScrllX:   -1     0     +1
;   ScrllY=-1:    NW(5)  N(6)  NE(7)
;   ScrllY= 0:     W(4)  --    E(0)
;   ScrllY=+1:    SW(3)  S(2)  SE(1)
;
; Se siamo fermi (centro tabella) la direzione corrente NON viene
; modificata: il player conserva l'ultima direzione di movimento
; (utile per scegliere il giusto sprite "idle" facing).
;------------------------------------------------------------
	LEA		Player,A0
	MOVE.w	ScrllY,D0
	MOVE.W  D0,bob_IsMoving(A0)
	ADDQ.w	#1,D0			; d0 = ScrllY+1 (0..2)
	MULU.w	#3,D0			; d0 = (ScrllY+1)*3 (0,3,6)
	MOVE.w	ScrllX,D1
	OR.W  	D1,bob_IsMoving(A0)
	ADDQ.w	#1,D1			; d1 = ScrllX+1 (0..2)
	ADD.w	D1,D0			; d0 = indice tabella (0..8)
 
	LEA		DirLookupTable,A1
	MOVE.b	(A1,D0.w),D0		; d0.b = direzione (0..7) o 255 se fermo
 
	CMPI.b	#255,D0
	BEQ.s	.no_dir_update		; ScrllX=ScrllY=0: mantieni direzione attuale
 
	AND.w	#$FF,D0			; estendi byte -> word (zero extend)
	MOVE.w	D0,bob_Direzione(A0)
.no_dir_update:

	MOVE.W	ScrllX,IntentX
	MOVE.W	ScrllY,IntentY

	MOVEM.l (SP)+,D0-D3/A0-A1
	RTS
;------------------------------------------------------------
; ReadKeyboard
;   Legge UN keycode dalla CIA-A (se disponibile),
;   decodifica e aggiorna ScrollX / ScrollY.
;   Registri modificati: d0, d1  (salvati/ripristinati)
;------------------------------------------------------------
ReadKeyboard:
	movem.l D0-D1,-(SP)

;--- Controlla se c'è un tasto in arrivo --------
	move.b  $BFED01,D0		; lettura ICR azzera i flag
	btst	#3,D0			; bit 3 = SP (keyboard data ready)
	beq		.no_key			; nessun tasto → esci

;--- Leggi il keycode grezzo dalla CIA-A --------
	move.b  $BFEC01,D0		; byte grezzo (bit invertiti, ruotato)

;--- Decodifica: NOT + ROR ----------------------
; Il keyboard controller Amiga invia i bit:
;   key[6],key[5]...key[0],release  (MSB first, active low)
; CIA-A li memorizza in SDR con bit 7 = primo bit ricevuto.
; NOT inverte la polarità, ROR #1 porta il release in bit 7.
	not.b   D0				; step 1: inverti polarità
	ror.b   #1,D0			; step 2: ruota → bit7=release, bit6-0=keycode

;--- Handshake obbligatorio ---------------------
; Dopo la lettura bisogna segnalare alla tastiera
; che il byte è stato ricevuto: SP in output per ~85μs,
; poi di nuovo in input. Senza questo la tastiera si blocca.
	move.b  $BFEE01,D1
	or.b	#$40,D1
	move.b  D1,$BFEE01		; SP → modalità output (bit 6 = 1)

	move.w  #150,D1			; ~85μs a 7.09 MHz ≈ 600 cicli
.ack:   
	dbf		D1,.ack			; busy wait (3 cicli × 151 ≈ 453 cicli, ok)

	move.b  $BFEE01,D1
	and.b   #$BF,d1
	move.b  D1,$BFEE01		; SP → modalità input (bit 6 = 0)
	;--- Processa frecce ----------------------------
	bsr	 ProcessArrowKey

.no_key:
	movem.l (SP)+,D0-D1
	rts

;------------------------------------------------------------
; ProcessArrowKey
;   Input : d0.b = keycode decodificato
;			  bit7 = 0 pressione, 1 rilascio
;			  bit6-0 = codice tasto
;   Output: aggiorna arrow_*
;			non scrive ScrollX, ScrollY che vengono scritti 
;			da LeggiJoystick
;   Registri modificati: d2 (salvato/ripristinato)
;------------------------------------------------------------
ProcessArrowKey:
	movem.l	D1-D2,-(SP)

	move.b	D0,D2
	and.b	#$7F,D2		 ; isola codice (senza bit rilascio)

	; Determina il valore da scrivere nella flag:
	;   pressione (bit7=0) -> 1
	;   rilascio  (bit7=1) -> 0
	moveq	#0,D1
	btst	#KEY_RELEASE_BIT,D0
	bne.s	.is_release
	moveq	#1,D1			; pressione: scriveremo 1 nella flag
.is_release:
	; (rilascio: d1 resta 0, scriveremo 0 nella flag)
 
;--- Identifica quale tasto e aggiorna la flag relativa ---
	cmp.b	#RAWKEY_UP,D2
	bne.s	.k_down
	move.b	D1,arrow_up
	bra.s	.done
 
.k_down:
	cmp.b	#RAWKEY_DOWN,D2
	bne.s	.k_left
	move.b	D1,arrow_dn
	bra.s	.done
 
.k_left:
	cmp.b	#RAWKEY_LEFT,D2
	bne.s	.k_right
	move.b	D1,arrow_sx
	bra.s	.done
 
.k_right:
	cmp.b	#RAWKEY_RIGHT,D2
	bne.s	.done
	move.b	D1,arrow_rx
 
.done:

	movem.l	(SP)+,D1-D2
	rts
*****************************************************************************
* 		ROUTINE DI ESECUZIONE SHIFT FINE
*****************************************************************************
GestisciShiftPixel:
	MOVEM.L	D0-D1,-(SP)

	MOVE.W	ScrllX,D0
	MOVE.W	ScrllY,D1
;========================
; ORIZZONTALE
;========================
	TST.W  D0
	BEQ.S  .NoX

	BPL.S  .VersoSinistra
	BSR.W  ShiftPixelDestra
	BRA.S  .NoX

.VersoSinistra:
	BSR.W  ShiftPixelSinistra

.NoX:

;========================
; VERTICALE
;========================
	TST.W  D1
	BEQ.S  .NoY

	BPL.S  .VersoAlto
	BSR.W  ShiftPixelBasso
	BRA.S  .NoY

.VersoAlto:
	BSR.W  ShiftPixelAlto

.NoY:
	MOVEM.L	(SP)+,D0-D1

	RTS
*****************************************************************************
* AGGIORNA TILES
*
* Chiamata DOPO GestisciShiftPixel. Processa i flag "Pending*" impostati
* da ControllaBordi e chiama le Add* routines quando il buffer e' pronto.
*
*****************************************************************************
AggiornaTiles:
	MOVEM.L	D0-D1,-(SP)
; ---------- DESTRA ----------
; Non aspetta nulla: AddColonnaDestra gestisce internamente lo split Y.
	MOVE.W	PdngAddRx,D0
	TST.W   D0
	BEQ.S   .NoRight
	BSR.W   AddColonnaDestra
	CLR.W   PdngAddRx
.NoRight:
 
; ---------- SINISTRA ----------
; Aspetta PixelOffX=0 (16 shift dx cumulativi dopo il boundary, bug #1).
; Lo split Y in AddColonnaSinistra gestisce PixelOffY qualunque.
	MOVE.W	PdngAddSx,D0
	TST.W   D0
	BEQ.S   .NoLeft
	MOVE.W	PixelOffX,D1
	TST.W   D1
	BNE.S   .NoLeft
	BSR.W   AddColonnaSinistra
	CLR.W   PdngAddSx
.NoLeft:
 
; ---------- BASSO ----------
; Non aspetta nulla: AddRigaBasso gestisce internamente lo split X.
	MOVE.W	PdngAddBot,D0
	TST.W   D0
	BEQ.S   .NoBot
	BSR.W   AddRigaBasso
	CLR.W   PdngAddBot
.NoBot:
 
; ---------- ALTO ----------
; Aspetta PixelOffY=0 (16 shift basso cumulativi dopo il boundary, bug #1).
; Lo split X in AddRigaAlto gestisce PixelOffX qualunque.
	MOVE.W	PdngAddTop,D0
	TST.W   D0
	BEQ.S   .NoTop
	MOVE.W	PixelOffY,D1
	TST.W   D1
	BNE.S   .NoTop
	BSR.W   AddRigaAlto
	CLR.W   PdngAddTop
.NoTop:
	MOVEM.L	(SP)+,D0-D1
	RTS
 
AggiornaTiles_old:
	MOVEM.L	D0-D1,-(SP)
; ---------- DESTRA ----------
; Non aspetta nulla: AddColonnaDestra gestisce internamente lo split Y.
	MOVE.W	PdngAddRx,D0
	TST.W   D0
	BEQ.S   .NoRight
	BSR.W   AddColonnaDestra
	CLR.W   PdngAddRx
.NoRight:

; ---------- SINISTRA ----------
; Aspetta PixelOffX=0 (16 shift dx cumulativi dopo il boundary, bug #1).
; Lo split Y in AddColonnaSinistra gestisce PixelOffY qualunque.
	MOVE.W	PdngAddSx,D0
	TST.W   D0
	BEQ.S   .NoLeft
	MOVE.W	PixelOffX,D1
	TST.W   D1
	BNE.S   .NoLeft
	BSR.W   AddColonnaSinistra
	CLR.W   PdngAddSx
.NoLeft:

; ---------- BASSO ----------
; Aspetta PixelOffX=0 (griglia X allineata, bug #2 asse Y non splittato).
	MOVE.W	PdngAddBot,D0
	TST.W   D0
	BEQ.S   .NoBot
	MOVE.W	PixelOffX,D1
	TST.W   D1
	BNE.S   .NoBot
	BSR.W   AddRigaBasso
	CLR.W   PdngAddBot
.NoBot:

; ---------- ALTO ----------
; Aspetta PixelOffY=0 (bug #1) AND PixelOffX=0 (bug #2 asse Y non splittato).
	MOVE.W	PdngAddTop,D0
	TST.W   D0
	BEQ.S   .NoTop
	MOVE.W	PixelOffX,D1
	TST.W   D1
	BNE.S   .NoTop
	MOVE.W	PixelOffY,D1
	TST.W   D1
	BNE.S   .NoTop
	BSR.W   AddRigaAlto
	CLR.W   PdngAddTop
.NoTop:
	MOVEM.L	(SP)+,D0-D1
	RTS

*****************************************************************************
* 		ROUTINE DI CONTROLLO DEI BORDI
* TILE BOUNDARY - SHIFT BUFFER
*****************************************************************************
ControllaBordi:
	MOVEM.L D0-D2,-(SP)
 
;==========================================================================
; PRE-Check per simmetria con .AzzeroXMin/.AzzeroYMin
;==========================================================================
 
; --- Y axis pre-Check ---
	MOVE.W  ScrllY,D0
	BEQ.S   .PreCheckYFatto		  ; ScrllY=0, niente da bloccare
	BMI.S   .PreCheckYMin		   ; ScrllY<0: check upper boundary
; ScrllY>0: check lower boundary
	MOVE.W  TileY,D0
	CMP.W   #TILEYMAX,D0
	BLT.S   .PreCheckYFatto		  ; TileY<TILEYMAX, OK
	MOVE.W  PixelOffY,D0
	BNE.S   .PreCheckYFatto		  ; PixelOffY!=0 (ciclo in corso), OK
	CLR.W   ScrllY				  ; al fondo + PixelOffY=0 + premuto giu': BLOCK
	BRA.S   .PreCheckYFatto
.PreCheckYMin:
	MOVE.W  TileY,D0
	BGT.S   .PreCheckYFatto		  ; TileY>0, OK
	MOVE.W  PixelOffY,D0
	BNE.S   .PreCheckYFatto		  ; PixelOffY!=0 (ciclo in corso), OK
	CLR.W   ScrllY				  ; in cima + PixelOffY=0 + premuto su': BLOCK
.PreCheckYFatto:
 
; --- X axis pre-Check (simmetrico) ---
	MOVE.W  ScrllX,D0
	BEQ.S   .PreCheckXFatto
	BMI.S   .PreCheckXMin
	MOVE.W  TileX,D0
	CMP.W   #TILEXMAX,D0
	BLT.S   .PreCheckXFatto
	MOVE.W  PixelOffX,D0
	BNE.S   .PreCheckXFatto
	CLR.W   ScrllX
	BRA.S   .PreCheckXFatto
.PreCheckXMin:
	MOVE.W  TileX,D0
	BGT.S   .PreCheckXFatto
	MOVE.W  PixelOffX,D0
	BNE.S   .PreCheckXFatto
	CLR.W   ScrllX
.PreCheckXFatto:
 
	MOVE.W  PixelOffX,D0
	MOVE.W  PixelOffY,D1
	ADD.W   ScrllX,D0
	ADD.W   ScrllY,D1
 
	CMP.W   #16,D0
	BLT.S   .ControlloXMin
	MOVE.W  TileX,D2
	CMP.W   #TILEXMAX,D2
	BGE.S   .AzzeroXMax
	SUB.W   #16,D0
	ADD.W   #1,TileX
	MOVE.W  #1,PdngAddRx	; era BSR.W AddColonnaDestra
	CLR.W   PdngAddSx		; annulla pending-left se presente
	BRA.S   .ControlloY
.AzzeroXMax:
	MOVE.W  #0,ScrllX
	MOVEQ   #15,D0
	BRA.S   .ControlloY
.ControlloXMin:
	TST.W   D0
	BGE.S   .ControlloY
	MOVE.W  TileX,D2
	CMP.W   #0,D2			  ; era #1 → corretto a #0
	BLE.S   .AzzeroXMin
	ADD.W   #16,D0
	SUB.W   #1,TileX
	MOVE.W  #1,PdngAddSx	; era BSR.W AddColonnaSinistra
	CLR.W   PdngAddRx		; annulla pending-right se presente
	BRA.S   .ControlloY
.AzzeroXMin:
	MOVE.W  #0,ScrllX
	MOVEQ   #0,D0
.ControlloY:
	CMP.W   #16,D1
	BLT.S   .ControlloYMin
	MOVE.W  TileY,D2
	CMP.W   #TILEYMAX,D2		; coerente con check X: #TILEXMAX
	BGE.S   .AzzeroYMax
	SUB.W   #16,D1
	ADD.W   #1,TileY
	MOVE.W  #1,PdngAddBot	; era BSR.W AddRigaBasso
	CLR.W   PdngAddTop		; annulla pending-top se presente
	BRA.S   .FineControlli
.AzzeroYMax:
	MOVE.W  #0,ScrllY
	MOVEQ   #15,D1
	BRA.S   .FineControlli
.ControlloYMin:
	TST.W   D1
	BGE.S   .FineControlli
	MOVE.W  TileY,D2
	CMP.W   #0,D2
	BLE.S   .AzzeroYMin
	ADD.W   #16,D1
	SUB.W   #1,TileY
	MOVE.W  #1,PdngAddTop	; era BSR.W AddRigaAlto
	CLR.W   PdngAddBot		; annulla pending-bot se presente
	BRA.S   .FineControlli
.AzzeroYMin:
	MOVE.W  #0,ScrllY
	MOVEQ   #0,D1
.FineControlli:
	MOVE.W  D0,PixelOffX
	MOVE.W  D1,PixelOffY
	MOVEM.L (SP)+,D0-D2
	RTS
 
*****************************************************************************
* SCROLLING A SINISTRA
*****************************************************************************
ShiftPixelSinistra:
	MOVEM.L D4/A1,-(SP)

	; In DESC il blitter parte dall'ultimo word: 287*44 + 42 = 12670
	MOVE.L  #SFONDOGRANDE+12670,A1  ; in-place: src = dst = fine buffer

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)

; ASH=1, DESC → shift a sinistra di 1 pixel
; D[i] = (A[i] << 1) | (A[i+1] >> 15) con A[22] = 0 (pipeline)
	MOVE.L  #$19F00002,$40(A6)   ; BLTCON0: ASH=1 | BLTCON1: DESC

	MOVE.W  #0,$64(A6)		   ; BLTAMOD = 0 (22 word × 2 = 44 = pitch)
	MOVE.W  #0,$66(A6)		   ; BLTDMOD = 0

	BSR.W   AspettaBlitter

	MOVE.L  A1,$50(A6)		   ; BLTAPT
	MOVE.L  A1,$54(A6)		   ; BLTDPT
	MOVE.W  #(288<<6)+22,$58(A6) ; 288 righe × 22 word (TUTTO il buffer)

	ADD.L   #288*44,A1
	DBRA	D4,.loop

	MOVEM.L (SP)+,D4/A1
	RTS

****************************************************************************
* SCROLLING A DESTRA
*****************************************************************************
ShiftPixelDestra:
	MOVEM.L D4/A1-A2,-(SP)

	MOVE.L  #SFONDOGRANDE,A2
	MOVE.L  #SFONDOGRANDE,A1

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)

	; DESC + shift 1 bit
	MOVE.L  #$19F00000,$40(A6)

	MOVE.W  #0,$64(A6)
	MOVE.W  #0,$66(A6)

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  #(288<<6)+22,$58(A6)

	ADD.L   #288*44,A2
	ADD.L   #288*44,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D4/A1-A2
	RTS

****************************************************************************
* SCROLLING IN ALTO
*****************************************************************************
ShiftPixelAlto:
	MOVEM.L D4/A1-A2,-(SP)

	MOVE.L  #SFONDOGRANDE+44,A2
	MOVE.L  #SFONDOGRANDE,A1

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)
	MOVE.L  #$09F00000,$40(A6)

	MOVE.W  #0,$64(A6)
	MOVE.W  #0,$66(A6)

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  #(287<<6)+22,$58(A6)

	ADD.L   #288*44,A2
	ADD.L   #288*44,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D4/A1-A2
	RTS

****************************************************************************
* SCROLLING IN BASSO
*****************************************************************************
ShiftPixelBasso:
	MOVEM.L D4/A1-A2,-(SP)

	MOVE.L  #SFONDOGRANDE+286*44+42,A2
	MOVE.L  #SFONDOGRANDE+287*44+42,A1

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)
	MOVE.L  #$09F00002,$40(A6)

	MOVE.W  #0,$64(A6)
	MOVE.W  #0,$66(A6)

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  #(287<<6)+22,$58(A6)

	ADD.L   #288*44,A2
	ADD.L   #288*44,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D4/A1-A2
	RTS
*****************************************************************************
* ADD COLONNA DESTRA (con split Y)
*
* Blitta nella colonna 21 del buffer (byte offset 42) la colonna
* MAPPA[TileY..TileY+17][TileX+21], allineata al PixelOffY corrente.
*
*****************************************************************************
AddColonnaDestra:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	; A0 = MAPPA[TileY][TileX+21]
	MOVE.W	TileX,D0
	ADDI.W	#BUFFER_COLS-1,D0	; colonna piu' a destra nel buffer = TileX+21
	MOVE.W	TileY,D1
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0			; *2 byte per word
	LEA	MAPPA,A0
	ADDA.W	D1,A0
	ADDA.W	D0,A0

; A3 = buffer col 21 row 0
	MOVE.L	#SFONDOGRANDE+42,A3

; D2 = PixelOffY (preservato per tutta la routine)
	MOVE.W	PixelOffY,D2

;=========================================================
; SLICE: MAPPA[TileY] pixel rows PixelOffY..15
;		-> buffer rows 0..(15-PixelOffY)
;		numero righe = 16-PixelOffY
;=========================================================
	MOVEQ	#0,D3
	MOVE.W	(A0),D3			; numero tile
	ADDA.L	#MAPPA_COLS*2,A0	; scendi di una riga nella MAPPA

; Calcola source tile in TILES (plane 0)
	MOVE.L	D3,D4
	DIVU.W	#20,D4			; D4.w = riga tile, resto = col tile
	MOVE.W	D4,D5
	MULU.W	#16*40,D5
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2			; A2 = TILES[tile] plane 0 row 0

; Skip PixelOffY righe dentro la tile: A2 += PixelOffY * 40
	MOVE.W	D2,D5
	MULU.W	#40,D5
	ADD.L	D5,A2			; A2 punta al pixel row PixelOffY della tile

; D5 = numero righe da scrivere = 16 - PixelOffY
	MOVE.W	#16,D5
	SUB.W	D2,D5
; BLTSIZE = (D5 << 6) + 1
	MOVE.W	D5,D6
	LSL.W	#6,D6
	ADDQ.W	#1,D6			; D6 = BLTSIZE per la slice

	MOVE.L	A3,A1			; A1 = dest plane 0 (buffer col 21 row 0)

	MOVEQ	#5-1,D4			; 5 planes
.sliceP:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)		; BLTAMOD = 40-2
	MOVE.W	#42,$66(A6)		; BLTDMOD = 44-2
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	D6,$58(A6)		; BLTSIZE = (righe slice << 6) + 1
	ADD.L	#256*40,A2		; next plane in TILES
	ADD.L	#288*44,A1		; next plane in SFONDOGRANDE
	DBRA	D4,.sliceP

; Avanza A3 di (16-PixelOffY) righe nel buffer
	MOVE.W	D5,D6
	MULU.W	#44,D6
	ADDA.L	D6,A3

;=========================================================
; 17 TILE INTERE: MAPPA[TileY+1..TileY+17]
;=========================================================
	MOVEQ	#17-1,D7
.loopTile:
	MOVEQ	#0,D3
	MOVE.W	(A0),D3
	ADDA.L	#MAPPA_COLS*2,A0

	MOVE.L	D3,D4
	DIVU.W	#20,D4
	MOVE.W	D4,D5
	MULU.W	#16*40,D5
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2

	MOVE.L	A3,A1
	MOVEQ	#5-1,D4
.loopPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)
	MOVE.W	#42,$66(A6)
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)	; tile intera: 16 righe x 1 word
	ADD.L	#256*40,A2
	ADD.L	#288*44,A1
	DBRA	D4,.loopPlane

	ADDA.L	#16*44,A3		; prossima tile: 16 righe piu' in basso
	DBRA	D7,.loopTile

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

*****************************************************************************
* ADD COLONNA SINISTRA (con split Y)
*
* Blitta nella colonna 0 del buffer (byte offset 0) la colonna
* MAPPA[TileY..TileY+17][TileX]. TileX e' gia' stato decrementato
* da ControllaBordi. Stesso split Y di AddColonnaDestra.
*****************************************************************************
AddColonnaSinistra:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	; A0 = MAPPA[TileY][TileX]  (TileX gia' decrementato)
	MOVE.W	TileX,D0
	MOVE.W	TileY,D1
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0
	LEA		MAPPA,A0
	ADDA.W	D1,A0
	ADDA.W	D0,A0

	; A3 = buffer col 0 row 0
	MOVE.L	#SFONDOGRANDE,A3

	; D2 = PixelOffY
	MOVE.W	PixelOffY,D2

;=========================================================
; SLICE: MAPPA[TileY] pixel rows PixelOffY..15
;=========================================================
	MOVEQ	#0,D3
	MOVE.W	(A0),D3
	ADDA.L	#MAPPA_COLS*2,A0

	MOVE.L	D3,D4
	DIVU.W	#20,D4
	MOVE.W	D4,D5
	MULU.W	#16*40,D5
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2

	MOVE.W	D2,D5
	MULU.W	#40,D5
	ADD.L	D5,A2			; A2 += PixelOffY * 40

	MOVE.W	#16,D5
	SUB.W	D2,D5			; D5 = 16 - PixelOffY = righe slice
	MOVE.W	D5,D6
	LSL.W	#6,D6
	ADDQ.W	#1,D6			; D6 = BLTSIZE slice

	MOVE.L	A3,A1

	MOVEQ	#5-1,D4
.sliceP:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)
	MOVE.W	#42,$66(A6)
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	D6,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*44,A1
	DBRA	D4,.sliceP

	; A3 += (16-PixelOffY) * 44
	MOVE.W	D5,D6
	MULU.W	#44,D6
	ADDA.L	D6,A3

;=========================================================
; 17 TILE INTERE: MAPPA[TileY+1..TileY+17]
;=========================================================
	MOVEQ	#17-1,D7
.loopTile:
	MOVEQ	#0,D3
	MOVE.W	(A0),D3
	ADDA.L	#MAPPA_COLS*2,A0

	MOVE.L	D3,D4
	DIVU.W	#20,D4
	MOVE.W	D4,D5
	MULU.W	#16*40,D5
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2

	MOVE.L	A3,A1
	MOVEQ	#5-1,D4
.loopPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)
	MOVE.W	#42,$66(A6)
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*44,A1
	DBRA	D4,.loopPlane

	ADDA.L	#16*44,A3
	DBRA	D7,.loopTile

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
*****************************************************************************
* ADD RIGA BASSO (con split X)
*
* Scrive nel buffer la riga tile 17 (pixel rows 272..287, byte offset 272*44)
* la riga MAPPA[TileY+17][TileX..TileX+21], allineata al PixelOffX corrente.
*
* TECNICA:
*   Fase 1: 22 tile scritte word-allineate in rows 272..287 del buffer
*		   (codice identico a prima: dest = SFONDOGRANDE + 272*44).
*   Fase 2: shift in-place di PixelOffX bit a SINISTRA sulle stesse 16 righe
*		   appena scritte. Usa lo stesso meccanismo di ShiftPixelSinistra
*		   (DESC + ASH) ma con BLTSIZE limitato a 16 righe invece di 288.
*
*****************************************************************************
AddRigaBasso:
	MOVEM.L	D0-D7/A0-A3,-(SP)
 
;=========================================================
; FASE 1: scrittura delle 22 tile word-allineate
;=========================================================
	MOVE.W	TileY,D1
	ADDI.W	#BUFFER_ROWS-1,D1	; riga piu' in basso del buffer = TileY+17
	MOVE.W	TileX,D0
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0
	LEA		MAPPA,A0
	ADDA.W	D1,A0
	ADDA.W	D0,A0
 
	MOVE.L	#SFONDOGRANDE+272*44,A3	; riga pixel 272 nel buffer
 
	MOVEQ	#BUFFER_COLS-1,D7		; 22 tile per riga
.loopTile:
	MOVEQ	#0,D3
	MOVE.W	(A0)+,D3		; tile successive: post-increment di 2 byte
 
	MOVE.L	D3,D4
	DIVU.W	#20,D4
	MOVE.W	D4,D5
	MULU.W	#16*40,D5
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2
 
	MOVE.L	A3,A1
	MOVEQ	#5-1,D4
.loopPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)
	MOVE.W	#42,$66(A6)
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*44,A1
	DBRA	D4,.loopPlane
 
	ADDQ.L	#2,A3			; prossima tile: 2 byte a destra
	DBRA	D7,.loopTile
 
;=========================================================
; FASE 2: shift in-place di PixelOffX bit a sx sulle righe 272..287
;		 (identico a ShiftPixelSinistra ma con ASH=PixelOffX
;		  e BLTSIZE = 16 righe x 22 word = solo la nuova riga tile)
;=========================================================
; Calcola BLTCON0|BLTCON1 = (ASH<<12 | $09F0) | DESC
;   BLTCON0 bits 15-12 = ASH = PixelOffX
;   BLTCON0 bits 11-8  = $9 (USEA=1, USED=1, no B, no C)
;   BLTCON0 bits  7-0  = $F0 (LF = A, copia diretta)
;   BLTCON1 bit 1	  = DESC=1
;=========================================================
	MOVEQ	#0,D0			; per azzerare tutti i 32 bit
	MOVE.W	PixelOffX,D0
	LSL.W	#8,D0			; D0.w = PixelOffX << 8
	LSL.W	#4,D0			; D0.w = PixelOffX << 12 (ASH in bit 15-12)
	SWAP	D0			; D0 high = (PixelOffX<<12), low = 0
	OR.L	#$09F00002,D0		; aggiungi USEA/USED/LF e DESC
 
; Indirizzo di partenza in modo DESC = ultima word della ultima riga:
; riga 287 (ultima delle 16) offset 287*44, word 21 offset 42
	MOVE.L	#SFONDOGRANDE+287*44+42,A1
 
	MOVEQ	#5-1,D4
.shiftPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	D0,$40(A6)		; BLTCON0/BLTCON1 con ASH=PixelOffX, DESC
	MOVE.W	#0,$64(A6)		; BLTAMOD = 0 (22 word = pitch)
	MOVE.W	#0,$66(A6)		; BLTDMOD = 0
	BSR.W	AspettaBlitter
	MOVE.L	A1,$50(A6)		; BLTAPT (in-place: src=dst)
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(16<<6)+22,$58(A6)	; 16 righe x 22 word (solo nuova riga tile)
	ADD.L	#288*44,A1		; prossimo plane
	DBRA	D4,.shiftPlane
 
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
 
*****************************************************************************
* ADD RIGA ALTO (con split X)
*
* Scrive la riga tile 0 del buffer (pixel rows 0..15) con MAPPA[TileY]
* [TileX..TileX+21]. TileY e' gia' stato decrementato da ControllaBordi.
* Stesso split X di AddRigaBasso ma applicato alle righe 0..15.
*****************************************************************************
AddRigaAlto:
	MOVEM.L	D0-D7/A0-A3,-(SP)
 
;=========================================================
; FASE 1: scrittura delle 22 tile word-allineate
;=========================================================
	MOVE.W	TileY,D1		; TileY gia' decrementato
	MOVE.W	TileX,D0
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0
	LEA		MAPPA,A0
	ADDA.W	D1,A0
	ADDA.W	D0,A0
 
	MOVE.L	#SFONDOGRANDE,A3	; riga 0 = inizio buffer
 
	MOVEQ	#BUFFER_COLS-1,D7
.loopTile:
	MOVEQ	#0,D3
	MOVE.W	(A0)+,D3
 
	MOVE.L	D3,D4
	DIVU.W	#20,D4
	MOVE.W	D4,D5
	MULU.W	#16*40,D5
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2
 
	MOVE.L	A3,A1
	MOVEQ	#5-1,D4
.loopPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)
	MOVE.W	#42,$66(A6)
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*44,A1
	DBRA	D4,.loopPlane
 
	ADDQ.L	#2,A3
	DBRA	D7,.loopTile
 
;=========================================================
; FASE 2: shift in-place di PixelOffX bit a sx sulle righe 0..15
;=========================================================
; BLTCON0|BLTCON1 come in AddRigaBasso
;=========================================================

	MOVEQ	#0,D0			; per azzerare tutti i 32 bit

	MOVE.W	PixelOffX,D0
	LSL.W	#8,D0
	LSL.W	#4,D0
	SWAP	D0
	OR.L	#$09F00002,D0
 
; Indirizzo DESC = ultima word della riga 15: 15*44 + 42 = 702
	MOVE.L	#SFONDOGRANDE+15*44+42,A1
 
	MOVEQ	#5-1,D4
.shiftPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	D0,$40(A6)
	MOVE.W	#0,$64(A6)
	MOVE.W	#0,$66(A6)
	BSR.W	AspettaBlitter
	MOVE.L	A1,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+22,$58(A6)	; 16 righe x 22 word
	ADD.L	#288*44,A1
	DBRA	D4,.shiftPlane
 
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

*****************************************************************************
* 		ROUTINE DI COMPOSIZIONE DELLO SFONDO
*
* Riempio il buffer di 44*288 con il rettangolo in alto a sinistra 
* della mappa.
* 
*****************************************************************************
DisegnaSfondo:
	MOVEM.L	D0-D6/A0-A2,-(SP)

	LEA		MAPPA,A0			; Salvo in A0 il punt. alla mappa
	MOVE.W	TileX,D0			; colonna di partenza
	ADD.W	D0,D0				; *2 perché ogni tile è una word
	ADDA.W	D0,A0				; salta le colonne a sinistra
	MOVE.L	#SFONDOGRANDE,PuntaSfondoGr
	MOVEQ	#BUFFER_COLS-1,D1	; d1 = numero colonne
	MOVEQ	#BUFFER_ROWS-1,D2	; d2 = numero righe
.CicloTile:
	MOVEQ	#0,D3				; Pulisci d3
	MOVE.W	(A0)+,D3			; d3 = numero della tile da stampare


	MOVE.L	D3,D5
	DIVU	#20,D5
	MOVE.W	D5,D6
	MULU	#16*40,D6
	SWAP	D5
	MOVE.W	D5,D7
	MULU	#2,D7
	MOVE.L	D6,A2
	ADD.L	D7,A2

	ADD.L	#TILES,A2			; TROVA LA TILE DESIDERATA

	MOVE.L	PuntaSfondoGr,A1	; destinazione in a1
	ADDQ.L	#2,PuntaSfondoGr 	; avanziamo di 16 bit (PROSSIMA TILE)

	MOVEQ	#5-1,D4				; Numero blittate = 5 per 5 planes
.BlittaLoopSfondo:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
								; BLTAFWM = $ffff - passa tutto
								; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09F00000,$40(A6)	; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)			; BLTAMOD 
	MOVE.W	#42,$66(A6)			; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)			; BLTAPT
	MOVE.L	A1,$54(A6)			; BLTDPT
	MOVE.W	#(16*64)+1,$58(A6)	; BLTSIZE

	ADD.L	#256*40,A2			; prossimo plane sorgente
	ADD.L	#288*44,A1			; prossimo plane destinazione

	DBRA	D4,.BlittaLoopSfondo
	DBRA	D1,.CicloTile
	ADD.L	#44*15,PuntaSfondoGr	; ANDIAMO A CAPO
	MOVEQ	#BUFFER_COLS-1,D1		; resetto il contatore delle colonne
	ADD.W	#(MAPPA_COLS-BUFFER_COLS)*2,A0
	DBRA	D2,.CicloTile
.FineMappa:

	MOVEM.L	(SP)+,D0-D6/A0-A2

	RTS

*****************************************************************************
*			  ROUTINE DI COPIA DELLA PARTE VISIBILE SUI BITPLANE
*****************************************************************************
CopiaVideo:
	MOVEM.L	D3-D7/A1-A2,-(SP)

	MOVE.L	#SFONDOGRANDE+16*44+2,A2	; ind. sorgente A
	MOVE.L  CurrentDraw,A1				; ind. destinazione D

	MOVEQ	#5-1,D4					; Numero blittate = 5 per 5 planes
.BlittaLoopVideo:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM e BLTALWM
									; BLTAFWM = $ffff - passa tutto
									; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#4,$64(A6)				; BLTAMOD 
	MOVE.W	#0,$66(A6)				; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT
	MOVE.W	#(256<<6)+20,$58(A6)	; BLTSIZE  256<<6 + 20

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#256*40,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoopVideo

	MOVEM.L	(SP)+,D3-D7/A1-A2
	RTS
*****************************************************************************
* InitPlayer - inizializza la struttura Player con i valori iniziali
*****************************************************************************
InitPlayer:
	MOVEM.L	A0,-(SP)

	LEA	 	Player,A0
	MOVE.W	#1,bob_Type(A0)				; 1 = Player
	MOVE.W	#144,bob_X(A0)				; centro X (allineato a 16)
	MOVE.W	#120,bob_Y(A0)				; centro Y
	MOVE.W	#1,bob_Speed(A0)			; velocità default
	MOVE.W	#2,bob_Direzione(A0)		; 0 = guarda a sud
	MOVE.W	#0,bob_AnimFrame(A0)		; primo frame
	MOVE.L	#OMINO,bob_Gfx(A0)			; puntatore allo spritesheet
	MOVE.W	#(16*64)+1,bob_BltSize(A0)  ; 16 righe x 1 word
	MOVE.W	#16,bob_Larghezza(A0)
	MOVE.W	#16,bob_Altezza(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVEM.L	(SP)+,A0
	RTS
*****************************************************************************
* BuildOminoMask
*   Genera OMINO_MASK come OR dei 5 bitplane di OMINO.
*   Da chiamare UNA SOLA VOLTA al boot (i dati sono statici).
*
*   Logica: per ogni word dei 10240 byte = 5120 word del plane,
*           OMINO_MASK[i] = OMINO[plane0][i] OR ... OR OMINO[plane4][i]
***************************************************************************** 
 ** 
BuildOminoMask:
	MOVEM.L	D0-D1/A0-A5,-(SP)

	; *** DEBUG: forza tutta la maschera a $FFFFFFFF
	; Se con questo il BOB appare il cookie cut funziona,
	; il problema e' nella generazione della maschera.
	LEA		OMINO_MASK,A0
	MOVE.W	#(40*256/4)-1,D0
	MOVE.L	#$FFFFFFFF,D1
.dbgloop:
	MOVE.L	D1,(A0)+
	DBRA	D0,.dbgloop

	MOVEM.L	(SP)+,D0-D1/A0-A5
	RTS
 BuildOminoMask_old:
	MOVEM.L	D0-D1/A0-A5,-(SP)
 
	LEA		OMINO,A1					; A1 = plane 0
	LEA		PLANE_SIZE(A1),A2			; A2 = plane 1
	LEA		PLANE_SIZE(A2),A3			; A3 = plane 2
	LEA		PLANE_SIZE(A3),A4			; A4 = plane 3
	LEA		PLANE_SIZE(A4),A5			; A5 = plane 4
	LEA		OMINO_MASK,A0				; destinazione
 
	; Loop a long (4 byte per iterazione = 2560 long per coprire 10240 byte)
	MOVE.W	#(PLANE_SIZE/4)-1,D0
.loop:
	MOVE.L	(A1)+,D1
	OR.L	(A2)+,D1
	OR.L	(A3)+,D1
	OR.L	(A4)+,D1
	OR.L	(A5)+,D1
	MOVE.L	D1,(A0)+
	DBRA	D0,.loop
 
	MOVEM.L	(SP)+,D0-D1/A0-A5
	RTS
 
*****************************************************************************
* GateScrollByCenter
*   Decide se la camera deve scrollare in questo frame.
*   Regola: la camera scrolla solo se il player e' al centro dello schermo
*           (bob_X==CENTER_X per X, bob_Y==CENTER_Y per Y, indipendenti).
*   Se il player NON e' al centro su un asse, ScrllX/Y di quell'asse
*   viene azzerato -> camera ferma su quell'asse fino a che il player
*   non torna al centro.
*
*   Nota: bob_X/Y devono essere stati calcolati prima (UpdatePlayerScreenPos),
*         altrimenti usiamo la posizione del frame precedente, che e' OK
*         perche' la transizione e' incrementale (1 pixel per frame).
*****************************************************************************
CENTER_X        EQU     144         ; centro X iniziale del player (bob_X)
CENTER_Y        EQU     120         ; centro Y iniziale del player (bob_Y)

GateScrollByCenter:
	MOVEM.L	D0/A0,-(SP)
	LEA		Player,A0

	; Asse X: se bob_X != CENTER_X, azzera ScrllX
	MOVE.W	bob_X(A0),D0
	CMP.W	#CENTER_X,D0
	BEQ.S	.x_centered
	CLR.W	ScrllX
.x_centered:

	; Asse Y: se bob_Y != CENTER_Y, azzera ScrllY
	MOVE.W	bob_Y(A0),D0
	CMP.W	#CENTER_Y,D0
	BEQ.S	.y_centered
	CLR.W	ScrllY
.y_centered:

	MOVEM.L	(SP)+,D0/A0
	RTS

*****************************************************************************
* IsTileBlocked
*   Controlla se la tile a (worldX, worldY) e' bloccata.
*   Input:  D0 = worldX (pixel)
*           D1 = worldY (pixel)
*   Output: D2.b = TileFlags della tile (0 = libera, !=0 = bloccata)
*           Z flag aggiornato (BEQ = libera, BNE = bloccata)
*   Modifica: D0, D1, D2
*
*   Tile fuori dai bounds della mappa sono considerate bloccate.
*****************************************************************************
IsTileBlocked:
	; Se worldX o worldY < 0 -> bloccato (fuori mappa)
	TST.W	D0
	BMI.S	.blocked
	TST.W	D1
	BMI.S	.blocked

	; tileX = worldX / 16, tileY = worldY / 16
	LSR.W	#4,D0					; D0 = tileX
	LSR.W	#4,D1					; D1 = tileY

	; Bounds check su mappa
	CMP.W	#MAPPA_COLS,D0
	BGE.S	.blocked
	CMP.W	#MAPPA_ROWS,D1
	BGE.S	.blocked

	; Calcolo offset nella mappa: (tileY * MAPPA_COLS + tileX) * 2  (word)
	MULU.W	#MAPPA_COLS,D1
	ADD.W	D0,D1
	ADD.W	D1,D1					; *2 perche' dc.w (word per ogni tile)

	; Recupero il numero di tile
	LEA		MAPPA,A1
	MOVE.W	(A1,D1.W),D2			; D2 = numero della tile

	; Lookup nel TileFlags (indicizzato come byte)
	LEA		TileFlags,A1
	MOVE.B	(A1,D2.W),D2			; D2.b = flag (0 = libera)
	; Z aggiornato dal MOVE
	RTS

.blocked:
	MOVEQ	#TF_BLOCK,D2			; non zero
	RTS

*****************************************************************************
* IsBoxBlocked
*   Controlla se un BOB 16x16 a posizione (worldX, worldY) collide con tile
*   bloccate. Verifica i 4 angoli del bounding box.
*   Input:  D0 = worldX (pixel del bordo sinistro del BOB)
*           D1 = worldY (pixel del bordo alto del BOB)
*   Output: Z flag (BEQ = libero, BNE = collide)
*   Modifica: D0-D5/A1
*
*   I 4 angoli testati sono:
*   - (X    , Y    )  alto-sinistra
*   - (X+15 , Y    )  alto-destra
*   - (X    , Y+15)  basso-sinistra
*   - (X+15 , Y+15)  basso-destra
*****************************************************************************
IsBoxBlocked:
	MOVEM.L	D6-D7,-(SP)
	MOVE.W	D0,D6					; salva worldX (input)
	MOVE.W	D1,D7					; salva worldY (input)

	; Angolo alto-sinistra
	BSR.W	IsTileBlocked
	TST.B	D2
	BNE.S	.endCheck

	; Angolo alto-destra (X+15, Y)
	MOVE.W	D6,D0
	ADDI.W	#15,D0
	MOVE.W	D7,D1
	BSR.W	IsTileBlocked
	TST.B	D2
	BNE.S	.endCheck

	; Angolo basso-sinistra (X, Y+15)
	MOVE.W	D6,D0
	MOVE.W	D7,D1
	ADDI.W	#15,D1
	BSR.W	IsTileBlocked
	TST.B	D2
	BNE.S	.endCheck

	; Angolo basso-destra (X+15, Y+15)
	MOVE.W	D6,D0
	ADDI.W	#15,D0
	MOVE.W	D7,D1
	ADDI.W	#15,D1
	BSR.W	IsTileBlocked
	; D2 contiene il risultato finale

.endCheck:
	; Ripristino D0/D1 input. D2 contiene 0=libero, !=0=bloccato.
	MOVE.W	D6,D0
	MOVE.W	D7,D1
	MOVEM.L	(SP)+,D6-D7
	; Riapplico Z flag come "TST D2"
	TST.B	D2
	RTS
	
*****************************************************************************
* UpdatePlayerWorldPos (Fase 2 + Fase 4)
*   Aggiorna PlayerWorldX/Y in base a ScrllX/Y (intent dell'utente).
*   Clampa il risultato in modo che il BOB (16x16, blittato come 2 word)
*   non esca mai dal bitplane visibile.
*
*   Limiti calcolati per evitare wrap-around del blit:
*     bob_X max = (viewport_width - BOB_width) = 320 - 16 = 304
*     bob_Y max = (viewport_height - BOB_height) = 256 - 16 = 240
*
*   PlayerWorldX max = bob_X_max + CameraX_max = 304 + (TILEXMAX*16) = 304 + 32 = 336
*   PlayerWorldY max = bob_Y_max + CameraY_max = 240 + (TILEYMAX*16) = 240 + 64 = 304
*****************************************************************************
*****************************************************************************
* UpdatePlayerWorldPos (Fase 2 + Fase 4 + Collisioni)
*   Aggiorna PlayerWorldX/Y in base a IntentX/IntentY, applicando:
*   1) Collision detection contro le tile bloccate (sliding X poi Y)
*   2) Clamp ai bordi della mappa
*****************************************************************************
UpdatePlayerWorldPos:
	MOVEM.L	D0-D2,-(SP)

	;-------------------------------------------------------------
	; ASSE X: tenta di muovere solo X (Y invariato)
	;-------------------------------------------------------------
	MOVE.W	IntentX,D0
	BEQ.S	.skipX					; se intent=0, salta
	ADD.W	PlayerWorldX,D0			; D0 = nuova X candidata
	; Clamp ai bordi mappa
	BPL.S	.x_clampHi
	MOVEQ	#0,D0					; X<0 -> 0
	BRA.S	.x_check
.x_clampHi:
	CMP.W	#PLAYER_MAX_X,D0
	BLE.S	.x_check
	MOVE.W	#PLAYER_MAX_X,D0		; X>max -> max
.x_check:
	; D0 = nuova X candidata, controllo collisioni
	MOVE.W	PlayerWorldY,D1			; Y attuale (non ancora cambiato)
	BSR.W	IsBoxBlocked
	BNE.S	.x_blocked				; collide, rifiuta movimento X
	; Movimento X accettato. Aggiorna anche se =0 per via del clamp (es. era a max)
	CMP.W	PlayerWorldX,D0
	BEQ.S	.x_blocked				; non si e' mosso (clamp) -> azzera ScrllX
	MOVE.W	D0,PlayerWorldX
	BRA.S	.skipX
.x_blocked:
	CLR.W	ScrllX					; sincronizza camera: niente scroll su X
.skipX:

	;-------------------------------------------------------------
	; ASSE Y: tenta di muovere solo Y (X eventualmente gia' aggiornata)
	;-------------------------------------------------------------
	MOVE.W	IntentY,D1
	BEQ.S	.skipY
	ADD.W	PlayerWorldY,D1			; D1 = nuova Y candidata
	; Clamp ai bordi mappa
	BPL.S	.y_clampHi
	MOVEQ	#0,D1
	BRA.S	.y_check
.y_clampHi:
	CMP.W	#PLAYER_MAX_Y,D1
	BLE.S	.y_check
	MOVE.W	#PLAYER_MAX_Y,D1
.y_check:
	; D1 = nuova Y candidata, controllo collisioni
	MOVE.W	PlayerWorldX,D0			; X attuale (eventualmente gia' aggiornata)
	BSR.W	IsBoxBlocked
	BNE.S	.y_blocked				; collide, rifiuta movimento Y
	CMP.W	PlayerWorldY,D1
	BEQ.S	.y_blocked				; non si e' mosso (clamp) -> azzera ScrllY
	MOVE.W	D1,PlayerWorldY
	BRA.S	.skipY
.y_blocked:
	CLR.W	ScrllY					; sincronizza camera: niente scroll su Y
.skipY:

	MOVEM.L	(SP)+,D0-D2
	RTS
*****************************************************************************
* UpdatePlayerScreenPos
*   Calcola bob_X/bob_Y (coordinate schermo del player) come differenza
*   tra PlayerWorldX/Y (coordinate mondo) e la posizione della camera.
*
*   CameraX_pixel = TileX * 16 + PixelOffX
*   CameraY_pixel = TileY * 16 + PixelOffY
*
*   bob_X = PlayerWorldX - CameraX_pixel
*   bob_Y = PlayerWorldY - CameraY_pixel
*
*   In Fase 1 PlayerWorldX/Y NON cambiano, quindi bob_X/Y resteranno
*   costanti a (144, 120) come prima -> nessun cambiamento visivo.
*****************************************************************************
UpdatePlayerScreenPos:
	MOVEM.L	D0-D1/A0,-(SP)
 
	LEA		Player,A0
 
	; Calcola CameraX_pixel = TileX*16 + PixelOffX
	MOVE.W	TileX,D0
	LSL.W	#4,D0					; D0 = TileX * 16
	ADD.W	PixelOffX,D0			; D0 = CameraX_pixel
	; bob_X = PlayerWorldX - CameraX
	MOVE.W	PlayerWorldX,D1
	SUB.W	D0,D1
	MOVE.W	D1,bob_X(A0)
 
	; Calcola CameraY_pixel = TileY*16 + PixelOffY
	MOVE.W	TileY,D0
	LSL.W	#4,D0					; D0 = TileY * 16
	ADD.W	PixelOffY,D0			; D0 = CameraY_pixel
	; bob_Y = PlayerWorldY - CameraY
	MOVE.W	PlayerWorldY,D1
	SUB.W	D0,D1
	MOVE.W	D1,bob_Y(A0)
 
	MOVEM.L	(SP)+,D0-D1/A0
	RTS
 
*****************************************************************************
*			  ROUTINE DI COPIA DELLA PARTE VISIBILE SUI BITPLANE
*****************************************************************************
DisegnaBOBPlayer:
	MOVEM.L	D0-D7/A0-A3,-(SP)
 
	LEA		Player,A0				; A0 puntatore alla struttura
 
	; ----------------- Animazione -----------------
	TST.W	bob_IsMoving(A0)
	BEQ.S	.notmoving
	ADD.W	#1,bob_FrameCont(A0)
	CMP.W	#ANIM_DELAY,bob_FrameCont(A0)
	BLT.S	.fineAnimazione
	CLR.W	bob_FrameCont(A0)
	ADDQ.W	#1,bob_AnimFrame(A0)
	AND.W	#7,bob_AnimFrame(A0)
	BRA.S	.fineAnimazione
.notmoving:
	CLR.W	bob_FrameCont(A0)
	CLR.W	bob_AnimFrame(A0)
.fineAnimazione:
 
	; ----------------- Calcolo offset frame nello spritesheet -----------------
	MOVE.W	bob_Direzione(A0),D3
	MULU.W	#640,D3					; Direzione * 16 righe * 40 byte
	MOVE.W	bob_AnimFrame(A0),D5
	ADD.W	D5,D5					; AnimFrame * 2 (1 word/frame)
	ADD.W	D5,D3					; D3 = offset frame nel plane 0
 
	; ----------------- A2 = sorgente A (spritesheet plane 0) -----------------
	MOVE.L 	bob_Gfx(A0),A2
	ADDA.W	D3,A2
 
	; ----------------- A3 = sorgente B (maschera) -----------------
	LEA		OMINO_MASK,A3
	ADDA.W	D3,A3
 
	; ----------------- Calcolo destinazione e shift -----------------
	; bob_X = posizione X in pixel
	; D7 = shift = bob_X mod 16
	; D6 = byte offset (allineato a word) = (bob_X / 16) * 2
	MOVE.W	bob_X(A0),D6
	MOVE.W	D6,D7
	AND.W	#15,D7					; D7 = shift (0..15)
	LSR.W	#3,D6					; D6 = bob_X / 8 (in byte)
	AND.W	#$FFFE,D6				; D6 allineato a word
 
	; A1 = destinazione (CurrentDraw + Y*40 + word_offset)
	MOVE.L	CurrentDraw,A1
	MOVE.W	bob_Y(A0),D0
	MULU.W	#40,D0					; D0 = Y * 40
	ADD.W	D6,D0
	ADDA.W	D0,A1					; A1 = posizione plane 0 destinazione
 
	; ----------------- BLTCON0 = (shift << 12) | $0FCA -----------------
	; bit 15-12: ASH (shift sorgente A)
	; bit 11-8:  USEA|USEB|USEC|USED = $F
	; bit  7-0:  LF = $CA (cookie cut: D = (A AND B) OR (C AND NOT B))
	MOVE.W	D7,D5
	LSL.W	#8,D5
	LSL.W	#4,D5					; D5 = shift << 12
	;OR.W	#$0DEC,D5				; *** DEBUG: 3 canali A+C+D, OR (no B)
	OR.W	#$0FCA,D5				; D5.w = BLTCON0 (cookie cut)
 
	; ----------------- BLTCON1 = BSH << 12 -----------------
	; *** FIX: maschera B deve avere stesso shift di A (BSH = ASH)
	MOVE.W	D7,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; D6.w = BSH << 12 = BLTCON1
 
	; ----------------- BLTSIZE: 16 righe x 2 word -----------------
	MOVE.W	#(16<<6)+1,D4					; *** DEBUG: 1 word per riga (no shift)
 
	; ----------------- Loop sui 5 bitplane -----------------
	MOVEQ	#5-1,D0
.BlittaLoopBob:
	BSR.W	AspettaBlitter
 
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM = $FFFF/$FFFF
	MOVE.W	D5,$40(A6)				; BLTCON0
	MOVE.W	#0,$42(A6)				; BLTCON1 (con BSH = ASH)  <-- FIX
;	MOVE.W	D6,$42(A6)				; BLTCON1 (con BSH = ASH)  <-- FIX	
	MOVE.W	#38,$60(A6)				; *** DEBUG: BLTCMOD = 40-2 (1 word)
	MOVE.W	#38,$62(A6)				; *** DEBUG: BLTBMOD
	MOVE.W	#38,$64(A6)				; *** DEBUG: BLTAMOD
	MOVE.W	#38,$66(A6)				; *** DEBUG: BLTDMOD
 
	MOVE.L	A1,$48(A6)				; BLTCPT prima (canonico)
	MOVE.L	A3,$4C(A6)				; BLTBPT
	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT ultimo

	MOVE.W	D4,$58(A6)				; BLTSIZE -> avvia blit
 
	ADD.L	#40*256,A2				; prossimo plane sorgente
	ADD.L	#40*256,A1				; prossimo plane destinazione/sfondo
	; A3 (maschera) NON avanza: e' una sola per tutti i plane
 
	DBRA	D0,.BlittaLoopBob
 
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
DisegnaBOBPlayer_old:
	MOVEM.L	D0-D7/A0-A3,-(SP)
 
	LEA		Player,A0				; A0 puntatore alla struttura
 
	; ----------------- Animazione -----------------
	TST.W	bob_IsMoving(A0)
	BEQ.S	.notmoving
	ADD.W	#1,bob_FrameCont(A0)
	CMP.W	#ANIM_DELAY,bob_FrameCont(A0)
	BLT.S	.fineAnimazione
	CLR.W	bob_FrameCont(A0)
	ADDQ.W	#1,bob_AnimFrame(A0)
	AND.W	#7,bob_AnimFrame(A0)
	BRA.S	.fineAnimazione
.notmoving:
	CLR.W	bob_FrameCont(A0)
	CLR.W	bob_AnimFrame(A0)
.fineAnimazione:
 
	; ----------------- Calcolo offset frame nello spritesheet -----------------
	MOVE.W	bob_Direzione(A0),D3
	MULU.W	#640,D3					; Direzione * 16 righe * 40 byte
	MOVE.W	bob_AnimFrame(A0),D5
	ADD.W	D5,D5					; AnimFrame * 2 (1 word/frame)
	ADD.W	D5,D5					; AnimFrame * 2 (1 word/frame)
	ADD.W	D5,D3					; D3 = offset frame nel plane 0
 
	; ----------------- A2 = sorgente A (spritesheet plane 0) -----------------
	MOVE.L 	bob_Gfx(A0),A2
	ADDA.W	D3,A2
 
	; ----------------- A3 = sorgente B (maschera) -----------------
	LEA		OMINO_MASK,A3
	ADDA.W	D3,A3
 
	; ----------------- Calcolo destinazione e shift -----------------
	; bob_X = posizione X in pixel
	; D7 = shift = bob_X mod 16
	; D6 = byte offset (allineato a word) = (bob_X / 16) * 2
	MOVE.W	bob_X(A0),D6
	MOVE.W	D6,D7
	AND.W	#15,D7					; D7 = shift (0..15)
	LSR.W	#3,D6					; D6 = bob_X / 8 (in byte)
	AND.W	#$FFFE,D6				; D6 allineato a word
 
	; A1 = destinazione (CurrentDraw + Y*40 + word_offset)
	MOVE.L	CurrentDraw,A1
	MOVE.W	bob_Y(A0),D0
	MULU.W	#40,D0					; D0 = Y * 40
	ADD.W	D6,D0
	ADDA.W	D0,A1					; A1 = posizione plane 0 destinazione
 
	; ----------------- BLTCON0 = (shift << 12) | $0FCA -----------------
	; bit 15-12: ASH (shift sorgente A)
	; bit 11-8:  USEA|USEB|USEC|USED = $F
	; bit  7-0:  LF = $CA (cookie cut: D = (A AND B) OR (C AND NOT B))
	MOVE.W	D7,D5
	LSL.W	#8,D5
	LSL.W	#4,D5					; D5 = shift << 12
	OR.W	#$0FCA,D5				; D5.w = BLTCON0
; 	OR.W	#$09F0,D5				; D5.w = BLTCON0
 
	; ----------------- BLTCON1 = BSH << 12 -----------------
	; *** FIX: maschera B deve avere stesso shift di A (BSH = ASH)
	MOVE.W	D7,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; D6.w = BSH << 12 = BLTCON1
 
	; ----------------- BLTSIZE: 16 righe x 2 word -----------------
	MOVE.W	#(16<<6)+2,D4
 
	; ----------------- Loop sui 5 bitplane -----------------
	MOVEQ	#5-1,D0
.BlittaLoopBob:
	BSR.W	AspettaBlitter
 
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM = $FFFF/$FFFF
	MOVE.W	D5,$40(A6)				; BLTCON0
;	MOVE.W	D6,$42(A6)				; BLTCON1 (con BSH = ASH)  <-- FIX
	MOVE.W	#0,$42(A6)				; BLTCON1 (con BSH = ASH)  <-- FIX
	MOVE.W	#36,$60(A6)				; BLTCMOD = 40 - 4 (sfondo)
	MOVE.W	#36,$62(A6)				; BLTBMOD = 40 - 4 (maschera)
	MOVE.W	#36,$64(A6)				; BLTAMOD = 40 - 4 (sprite)
	MOVE.W	#36,$66(A6)				; BLTDMOD = 40 - 4 (destinazione)
 
	MOVE.L	A1,$48(A6)				; BLTCPT (sfondo)
	MOVE.L	A3,$4C(A6)				; BLTBPT (maschera, stessa per ogni plane)
	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT (destinazione = stessa di sfondo)
 
	MOVE.W	D4,$58(A6)				; BLTSIZE -> avvia blit
 
	ADD.L	#40*256,A2				; prossimo plane sorgente
	ADD.L	#40*256,A1				; prossimo plane destinazione/sfondo
	; A3 (maschera) NON avanza: e' una sola per tutti i plane
 
	DBRA	D0,.BlittaLoopBob
 
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
  
*****************************************************************************
* Routine che aspetta il blitter
*****************************************************************************
AspettaBlitter:
	BTST	#6,2(a6)		; dmaconr - waitblit
.bltw:
	BTST	#6,2(a6)		; dmaconr - waitblit
	BNE.S	.bltw
	RTS

	SECTION	DATI,DATA

CurrentDisplay:	
	dc.l	BPSFONDO_A	; bitplane attualmente visibili
CurrentDraw:	
	dc.l	BPSFONDO_B	; bitplane su cui disegnare


*****************************************************************************
* TileFlags
*   Tabella delle proprieta' delle tile, indicizzata dal numero di tile.
*   bit 0 (TF_BLOCK) = 1 -> tile bloccata (non calpestabile)
*   In futuro si possono aggiungere altri flag (TF_DAMAGE, TF_WATER, ecc).
*
*   Per ora: tile 1 = libera, tutte le altre bloccate.
*   Estendi se aggiungi nuove tile alla mappa.
*****************************************************************************
TF_BLOCK        EQU     1

TileFlags:
;       tile:   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
	dc.b	1,	0,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1
;       tile:  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30  31
	dc.b	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1
	even

*****************************************************************************
* Disegno la mappa con le tiles 
*****************************************************************************

MAPPA:
;			 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ;	 
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;0
	dc.w	 0, 2, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4, 0	;1
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;2
	dc.w	 0, 6, 1, 1, 1,10,13, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;3
	dc.w	 0, 6, 1, 1, 1,11,12, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;4
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;5
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1,10,13, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;6
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1,11,12, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;7
	dc.w	 0, 6, 1, 1,10, 9,13, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;8
	dc.w	 0, 6, 1, 1, 7,14, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;9
	dc.w	 0, 6, 1,10, 5, 2,12, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;10
	dc.w	 0, 6, 1, 7, 2,12, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;11
	dc.w	 0, 6, 1,11,12, 1, 1, 1, 1, 1, 1, 1, 1, 1,10,13, 1, 1, 1, 1, 1, 1, 7, 0	;12
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,10, 5, 3, 9,13, 1, 1, 1, 1, 7, 0	;13
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7,14,14,14, 6, 1, 1, 1, 1, 7, 0	;14
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,11, 8, 8, 8,12, 1, 1, 1, 1, 7, 0	;15
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;16
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;17
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;18
	dc.w	 0, 6, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 7, 0	;19
	dc.w	 0, 3, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 5, 0	;20
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;21
	
*****************************************************************************
* VARIABILI
*****************************************************************************
ScrllX:		dc.w	0		; Movimento orizzontale +-1 
ScrllY:		dc.w	0		; Movimento verticale +-1
TileX:		dc.w	1
TileY:		dc.w	0
PixelOffX:	dc.w	0
PixelOffY:	dc.w	0
BufferOffX:	dc.w	0
BufferOffY:	dc.w	0
; Coordinate del player nel mondo (in pixel, non tile).
; Range valido: 0..MAP_WIDTH-16 per X, 0..MAP_HEIGHT-16 per Y
; Mappa = MAPPA_COLS*16 x MAPPA_ROWS*16 = 384 x 352 pixel
; Inizializzazione coerente con TileX=1,PixelOffX=0,bob_X=144:
;   CameraX_iniziale = TileX*16 + PixelOffX = 16
;   PlayerWorldX = CameraX + bob_X = 16 + 144 = 160
;   PlayerWorldY = CameraY + bob_Y = 0 + 120 = 120
PlayerWorldX:	dc.w	160
PlayerWorldY:	dc.w	120
; Intent dell'utente (movimento desiderato): -1, 0, +1
; Distinto da ScrllX/Y che invece e' "camera scroll" (gated dal centro schermo).
; PlayerWorldX += IntentX sempre; ScrllX = IntentX solo se player al centro.
IntentX:		dc.w	0
IntentY:		dc.w	0
; Flag per posticipare le chiamate Add* a DOPO lo shift pixel.
PdngAddRx:	dc.w	0	; boundary dx: scrivi col 21 subito dopo lo shift
PdngAddSx:	dc.w	0	; boundary sx: aspetta PixelOffX=0 (16 shift dx)
PdngAddBot:	dc.w	0	; boundary giu': scrivi riga bassa dopo lo shift
PdngAddTop:	dc.w	0	; boundary su: aspetta PixelOffY=0 (16 shift basso)
 
arrow_up:	dc.b 	0
arrow_dn:	dc.b 	0
arrow_sx:	dc.b 	0
arrow_rx:	dc.b 	0

;------------------------------------------------------------
; Tabella di lookup direzione: 9 byte indicizzati da
; (ScrllY+1)*3 + (ScrllX+1).
; Ordine direzioni: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
; Valore 255 = nessun movimento (centro tabella).
;------------------------------------------------------------
DirLookupTable:
	dc.b	5, 6, 7			; ScrllY=-1: NW, N, NE
	dc.b	4, 255, 0		; ScrllY= 0: W, fermo, E
	dc.b	3, 2, 1			; ScrllY=+1: SW, S, SE
	even

PuntaSfondoGr:
	dc.l	SFONDOGRANDE
xmappa:
	dc.b	0
ymappa:
	dc.b	0

; bob
	rsreset
bob_Type		rs.W	1		; 1 = Player 
								; 2 = Nemico
bob_X			rs.w	1		; coordinata X
bob_Y 			rs.w	1		; coordinata Y
bob_Speed 		rs.W	1		; velocità da 1 a 3
bob_Direzione	rs.W	1		; 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
bob_AnimFrame	rs.W	1		; 0..7: frame di animazione 
bob_Gfx			rs.L	1		; puntatore alla grafica
bob_BltSize		rs.W	1		; dimensione del bob
bob_Larghezza	rs.W	1		; larghezza del bob
bob_Altezza		rs.W	1		; larghezza del bob
bob_FrameCont	rs.W	1		; conteggio frame per cambio
bob_IsMoving	rs.W	1			
bob_Length		rs.B	0		; dimensione della struttura

*****************************************************************************
*
* 		COPPER
*
*****************************************************************************	
		
	Section	ChipStuff,data_c

CopperList:
	dc.w	$0100,%0101001000000000	; BPLCON0
				  ;5432109876543210	
; bit 15		HiRes
; bit 14-12		Numero di Bitplanes
; bit 11		HAM
; bit 10 		Dual Playfield
; bit 9			Color burst
; bit 8			GENLOCK AUDIO
; bit 7-4		non utilizzati
; bit 3			Light Pen
; bit 2			LACE
; bit 1			External Resync
; bit 0 		non utilizzato

	dc.w	$102,0			; BplCon1
	dc.w	$104,0			; BplCon1
	dc.w	$108,0			; BPL1BTH
	dc.w	$10A,0			; BPL1PTL
	dc.w 	$0092,$0038,$0094,$00d0 ; DdfStrt - DdfStop
	dc.w	$008e,$2c81,$0090,$2cc1	; DiwStrt - DiwStop

BitPlaneTiles:
	dc.w 	$e0,$0000,$e2,$0000	;primo   bitplane - BPL0PT
	dc.w 	$e4,$0000,$e6,$0000	;secondo bitplane - BPL1PT
	dc.w 	$e8,$0000,$ea,$0000	;terzo   bitplane - BPL2PT
	dc.w 	$ec,$0000,$ee,$0000	;quarto  bitplane - BPL3PT
	dc.w 	$f0,$0000,$f2,$0000	;quarto  bitplane - BPL3PT

Sprites:
	dc.w	$120,$0000,$122,$0000,$124,$0000,$126,$0000,$128,$0000
	dc.w	$12a,$0000,$12c,$0000,$12e,$0000,$130,$0000,$132,$0000
	dc.w	$134,$0000,$136,$0000,$138,$0000,$13a,$0000,$13c,$0000
	dc.w	$13e,$0000

PALETTE:
	dc.w 	$0180,$0000,$0182,$0fff,$0184,$0040,$0186,$0070	
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880	
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	dc.w 	$0198,$000f,$019a,$070f,$019c,$0c0e,$019e,$0c08
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca	
	dc.w 	$01a8,$0333,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff
; Dopo la fine del DIW (scanline 300 = V=$12c) spegne la DMA
; bitplane. Senza questo, WinUAE (e hardware reale in modalita'
; overscan) continua a fetchare memoria oltre BPSFONDO per
; riempire le righe sotto al viewport. Il fetch usa BPLxMOD=0
; (pitch 40 byte/riga) ma trova oltre BPSFONDO il buffer
; SFONDOGRANDE che ha pitch 44, quindi legge "a mosaico"
; pezzi di righe diverse -> appaiono righe parziali e disallineate
; in fondo allo schermo, piu' o meno evidenti in base a PixelOffX
; e al contenuto della MAPPA.
;
; Il copper VP e' 8 bit, quindi per V>=256 serve il "trick"
; past-line-255: prima WAIT($FFDF,$FFFE) manda il copper oltre
; V=255 (incrementa il V8 flip-flop interno), poi il WAIT
; successivo usa V8 implicito.
	dc.w	$FFDF,$FFFE		; past end of line 255
	dc.w	$2C01,$FF00		; WAIT V=300 (=$12c), H=any -> fine DIW
	dc.w	$0100,$0200		; BPLCON0: 0 bitplane, solo Color burst
 
	dc.w	$FFFF,$FFFE		; FINE DELLA COPPERLIST
 

*****************************************************************************
* Qui sono memorizzate le tiles dello sfondo
*****************************************************************************
	
TILES:
	incbin	"Tiles.raw"	

OMINO:
	incbin	"Omino.raw"	
	
*****************************************************************************

	SECTION	PLANEVUOTO,BSS_C

BPSFONDO_A:
	ds.b	5*40*256		; bitplanes  
BPSFONDO_B:
	ds.b	5*40*256		; bitplanes  
SFONDOGRANDE:
	ds.b	5*44*288		; mappa pi� grande

; Maschera dell'OMINO: 1 bitplane (10240 byte = 40*256) calcolata al boot
; come OR dei 5 bitplane dello spritesheet originale.
; Il blitter la usa come canale B per il cookie-cut nei BOB.
OMINO_MASK:
	ds.b	40*256			; 1 plane mask (stesso pitch di OMINO)

	SECTION	Entities,BSS

	EVEN
Player:
	ds.b	bob_Length		  ; alloca 22 byte azzerati

	end

*****************************************************************************

