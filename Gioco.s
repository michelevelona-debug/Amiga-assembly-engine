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
DMASET	EQU	%1000001111100000	; bltr, copper, bitplane, SPRITE DMA (BLTPRI OFF)
								; bit 5 SPREN = 1 per attivare sprite hardware
;DMASET	EQU	%1000010111100000	; alt con BLTPRI=1
;								; bit 10 BLTPRI = 1: bltr ha priorita' su CPU
*****************************************************************************
* COSTANTI
*****************************************************************************
PLANE_SIZE      EQU     40*256          ; 10240 byte = un singolo bitplane
SFONDO_PITCH	EQU		48				; pitch riga di SFONDOGRANDE in byte
										; (era 44, ora 48 per allineamento AGA FMODE=3,
										; multiplo di 8). Larghezza utile = 22 word = 44 byte
										; (= 352 pixel come prima); i 4 byte extra
										; (= ultimi 32 pixel di ogni riga) sono inutilizzati.
SFONDO_HEIGHT	EQU		288				; altezza SFONDOGRANDE in righe
SFONDO_PLANE_SIZE EQU	SFONDO_PITCH*SFONDO_HEIGHT	; 13824 byte/plane

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
RAWKEY_SPACE	EQU $40

KEY_RELEASE_BIT EQU 7	   ; bit 7 del keycode decodificato
ANIM_DELAY		EQU 3

HEALTHBAR_COLOR	EQU	14					; colore 14 = rosso/rosa nella palette
HEALTHBAR_YOFFSET EQU 3					; pixel sopra il BOB
INVULN_FRAMES	EQU	50					; frame di invulnerabilita' dopo un hit

; ----- Bullet (proiettile sprite hardware) -----
BULLET_SPEED		EQU	4				; pixel per frame del proiettile
BULLET_TTL			EQU	60				; frame di vita massima
BULLET_COOLDOWN		EQU	10				; frame di cooldown tra due spari
BULLET_DAMAGE		EQU	2				; danno inflitto al nemico
BULLET_HEIGHT		EQU	4				; altezza dello sprite proiettile

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

;	MOVE.W	#$f,$1fc(A6)			; FMODE = $0F (AGA fetch 64-bit per BPL e SPR)
	MOVE.W	#$3,$1fc(A6)			; FMODE = $03 (AGA fetch 64-bit per BPL, sprite OCS-style)
	MOVE.W	#$c00,$106(A6)			; BPLCON3 = LOCT=0, BANK=0, BRDRBLNK
	MOVE.W	#$11,$10c(A6)			; BPLCON4 = sprite/playfield mask standard

	BSR.W   InitPlayer				; <-- INIZIALIZZA IL PLAYER
	BSR.W   InitEnemies				; <-- INIZIALIZZA I NEMICI
	BSR.W	BuildOminoMask			; Genera la maschera dell'OMINO al boot
	BSR.W	InitSprites				; <-- INIZIALIZZA SPRITE HARDWARE

	BSR.W	DisegnaSfondo			; Routine che disegna lo sfondo

	; Pre-render su entrambi i buffer per evitare il primo frame nero
	BSR.W	CopiaVideo				; copia su CurrentDraw = BPSFONDO_B
	BSR.W	AspettaBlitter
	BSR.S	SwapBuffers				; ora display = B, draw = A
	BSR.W	CopiaVideo				; copia anche su A
;	BSR.W	AspettaBlitter
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
	BSR.W	UpdateEnemies			; AI dei nemici (movimento)
	BSR.W	Combattimento			; gestisce collisioni player-nemici (vita)
	BSR.W	Proiettile				; gestione fire + proiettile (move, collisione)
;	BSR.S 	SxMouse
	BSR.W	DisegnaBOBEnemy			; sui bitplane di CurrentDraw
	BSR.W	DisegnaBOBPlayer		; idem, dopo i nemici per z-ordering
	BSR.W	DisegnaBarraVita		; barre vita rosse sopra ogni BOB attivo
	BSR.W	AggiornaProiettile		; aggiorna SPRPOS/SPRCTL dello sprite proiettile
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
	bne.s	.k_space
	move.b	D1,arrow_rx
	bra.s	.done

.k_space:
	cmp.b	#RAWKEY_SPACE,D2
	bne.s	.done
	move.b	D1,key_space
 
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

; In DESC il blitter parte dall'ultimo word: 287*48 + 42 = 13818
	MOVE.L  #SFONDOGRANDE+287*SFONDO_PITCH+42,A1  
										; in-place: src = dst = fine buffer

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)

; ASH=1, DESC → shift a sinistra di 1 pixel
; D[i] = (A[i] << 1) | (A[i+1] >> 15) con A[22] = 0 (pipeline)
	MOVE.L  #$19F00002,$40(A6)   ; BLTCON0: ASH=1 | BLTCON1: DESC

	MOVE.W  #4,$64(A6)		; BLTAMOD = 4 (= 48-44, blittate 22 word, pitch SFONDO 48) 
							; (22 word × 2 = 44 byte blittate, pitch SFONDOGRANDE = 48)
	MOVE.W  #4,$66(A6)		; BLTDMOD = 4 (= 48-44, blittate 22 word, pitch SFONDO 48)
	BSR.W   AspettaBlitter

	MOVE.L  A1,$50(A6)		   ; BLTAPT
	MOVE.L  A1,$54(A6)		   ; BLTDPT
	MOVE.W  #(288<<6)+22,$58(A6) ; 288 righe × 22 word (TUTTO il buffer)

	ADD.L   #288*SFONDO_PITCH,A1
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

	MOVE.W  #4,$64(A6)		; BLTAMOD = 48-44
	MOVE.W  #4,$66(A6)		; BLTDMOD = 48-44

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  #(288<<6)+22,$58(A6)

	ADD.L   #288*SFONDO_PITCH,A2
	ADD.L   #288*SFONDO_PITCH,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D4/A1-A2
	RTS

****************************************************************************
* SCROLLING IN ALTO
*****************************************************************************
ShiftPixelAlto:
	MOVEM.L D4/A1-A2,-(SP)

	MOVE.L  #SFONDOGRANDE+SFONDO_PITCH,A2
	MOVE.L  #SFONDOGRANDE,A1

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)
	MOVE.L  #$09F00000,$40(A6)

	MOVE.W  #4,$64(A6)		; BLTAMOD = 48-44
	MOVE.W  #4,$66(A6)		; BLTDMOD = 48-44

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  #(287<<6)+22,$58(A6)

	ADD.L   #288*SFONDO_PITCH,A2
	ADD.L   #288*SFONDO_PITCH,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D4/A1-A2
	RTS

****************************************************************************
* SCROLLING IN BASSO
*****************************************************************************
ShiftPixelBasso:
	MOVEM.L D4/A1-A2,-(SP)

	MOVE.L  #SFONDOGRANDE+286*SFONDO_PITCH+42,A2
	MOVE.L  #SFONDOGRANDE+287*SFONDO_PITCH+42,A1

	MOVEQ   #5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)
	MOVE.L  #$09F00002,$40(A6)

	MOVE.W  #4,$64(A6)		; BLTAMOD = 48-44
	MOVE.W  #4,$66(A6)		; BLTDMOD = 48-44

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  #(287<<6)+22,$58(A6)

	ADD.L   #288*SFONDO_PITCH,A2
	ADD.L   #288*SFONDO_PITCH,A1

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

	; Registri "fissi" settati una volta sola per tutta la routine
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)				; BLTAMOD = 40-2
	MOVE.W	#46,$66(A6)				; BLTDMOD = 48-2
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
;	MOVE.L	#$ffffffff,$44(A6)
;	MOVE.L	#$09F00000,$40(A6)
;	MOVE.W	#38,$64(A6)				; BLTAMOD = 40-2
;	MOVE.W	#46,$66(A6)				; BLTDMOD = 48-2 (pitch - 2 byte/word blittata)
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	D6,$58(A6)				; BLTSIZE = (righe slice << 6) + 1
	ADD.L	#256*40,A2				; next plane in TILES
	ADD.L	#288*SFONDO_PITCH,A1	; next plane in SFONDOGRANDE
	DBRA	D4,.sliceP

; Avanza A3 di (16-PixelOffY) righe nel buffer
	MOVE.W	D5,D6
	MULU.W	#SFONDO_PITCH,D6
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
;	MOVE.L	#$ffffffff,$44(A6)
;	MOVE.L	#$09F00000,$40(A6)
;	MOVE.W	#38,$64(A6)
;	MOVE.W	#46,$66(A6)
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)	; tile intera: 16 righe x 1 word
	ADD.L	#256*40,A2
	ADD.L	#288*SFONDO_PITCH,A1
	DBRA	D4,.loopPlane

	ADDA.L	#16*SFONDO_PITCH,A3		; prossima tile: 16 righe piu' in basso
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

	; Registri "fissi" settati una volta sola per tutta la routine
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)				; BLTAMOD = 40-2
	MOVE.W	#46,$66(A6)				; BLTDMOD = 48-2
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
;	MOVE.L	#$ffffffff,$44(A6)
;	MOVE.L	#$09F00000,$40(A6)
;	MOVE.W	#38,$64(A6)
;	MOVE.W	#46,$66(A6)
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	D6,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*SFONDO_PITCH,A1
	DBRA	D4,.sliceP

	; A3 += (16-PixelOffY) * SFONDO_PITCH
	MOVE.W	D5,D6
	MULU.W	#SFONDO_PITCH,D6
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
;	MOVE.L	#$ffffffff,$44(A6)
;	MOVE.L	#$09F00000,$40(A6)
;	MOVE.W	#38,$64(A6)
;	MOVE.W	#46,$66(A6)
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*SFONDO_PITCH,A1
	DBRA	D4,.loopPlane

	ADDA.L	#16*SFONDO_PITCH,A3
	DBRA	D7,.loopTile

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
*****************************************************************************
* ADD RIGA BASSO (con split X)
*
* Scrive nel buffer la riga tile 17 (pixel rows 272..287, byte offset 272*SFONDO_PITCH)
* la riga MAPPA[TileY+17][TileX..TileX+21], allineata al PixelOffX corrente.
*
* TECNICA:
*   Fase 1: 22 tile scritte word-allineate in rows 272..287 del buffer
*		   (codice identico a prima: dest = SFONDOGRANDE + 272*SFONDO_PITCH).
*   Fase 2: shift in-place di PixelOffX bit a SINISTRA sulle stesse 16 righe
*		   appena scritte. Usa lo stesso meccanismo di ShiftPixelSinistra
*		   (DESC + ASH) ma con BLTSIZE limitato a 16 righe invece di 288.
*
*****************************************************************************
AddRigaBasso:
	MOVEM.L	D0-D7/A0-A3,-(SP)
 	; Registri "fissi" settati una volta sola per tutta la routine

	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)				; BLTAMOD = 40-2
	MOVE.W	#46,$66(A6)				; BLTDMOD = 48-2
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
 
	MOVE.L	#SFONDOGRANDE+272*SFONDO_PITCH,A3	; riga pixel 272 nel buffer
 
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
;	MOVE.L	#$ffffffff,$44(A6)
;	MOVE.L	#$09F00000,$40(A6)
;	MOVE.W	#38,$64(A6)
;	MOVE.W	#46,$66(A6)
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*SFONDO_PITCH,A1
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
; riga 287 (ultima delle 16) offset 287*SFONDO_PITCH, word 21 offset 42
	MOVE.L	#SFONDOGRANDE+287*SFONDO_PITCH+42,A1
 
	MOVEQ	#5-1,D4
.shiftPlane:
	BSR.W	AspettaBlitter
;	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	D0,$40(A6)		; BLTCON0/BLTCON1 con ASH=PixelOffX, DESC
	MOVE.W	#4,$64(A6)		; BLTAMOD = 4 (= 48-44, blittate 22 word, pitch SFONDO 48) (22 word = pitch)
	MOVE.W	#4,$66(A6)		; BLTDMOD = 4 (= 48-44, blittate 22 word, pitch SFONDO 48)
;	BSR.W	AspettaBlitter
	MOVE.L	A1,$50(A6)		; BLTAPT (in-place: src=dst)
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(16<<6)+22,$58(A6)	; 16 righe x 22 word (solo nuova riga tile)
	ADD.L	#288*SFONDO_PITCH,A1		; prossimo plane
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
 
	; Registri "fissi" settati una volta sola per tutta la routine
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)				; BLTAMOD = 40-2
	MOVE.W	#46,$66(A6)				; BLTDMOD = 48-2
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
;	MOVE.L	#$ffffffff,$44(A6)
;	MOVE.L	#$09F00000,$40(A6)
;	MOVE.W	#38,$64(A6)
;	MOVE.W	#46,$66(A6)
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)
	ADD.L	#256*40,A2
	ADD.L	#288*SFONDO_PITCH,A1
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
 
; Indirizzo DESC = ultima word della riga 15: 15*SFONDO_PITCH + 42 = 762
	MOVE.L	#SFONDOGRANDE+15*SFONDO_PITCH+42,A1
 
	MOVEQ	#5-1,D4
.shiftPlane:
	BSR.W	AspettaBlitter
;	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	D0,$40(A6)
	MOVE.W	#4,$64(A6)		; BLTAMOD = 48-44
	MOVE.W	#4,$66(A6)		; BLTDMOD = 48-44
;	BSR.W	AspettaBlitter
	MOVE.L	A1,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+22,$58(A6)	; 16 righe x 22 word
	ADD.L	#288*SFONDO_PITCH,A1
	DBRA	D4,.shiftPlane
 
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

*****************************************************************************
* 		ROUTINE DI COMPOSIZIONE DELLO SFONDO
*
* Riempio il buffer di SFONDO_PITCH*288 con il rettangolo in alto a sinistra 
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
	MOVE.W	#46,$66(A6)			; BLTDMOD 
;	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)			; BLTAPT
	MOVE.L	A1,$54(A6)			; BLTDPT
	MOVE.W	#(16*64)+1,$58(A6)	; BLTSIZE
	ADD.L	#256*40,A2				; prossimo plane sorgente
	ADD.L	#288*SFONDO_PITCH,A1	; prossimo plane destinazione
	DBRA	D4,.BlittaLoopSfondo
	DBRA	D1,.CicloTile
	; Avanza PuntaSfondoGr alla riga di tile successiva.
	; Era a fine riga di tile corrente (= +BUFFER_COLS*2 byte dall'inizio).
	; Deve andare a 16 righe sotto, colonna 0 dell'inizio.
	; delta = 16*pitch - BUFFER_COLS*2
	ADD.L	#16*SFONDO_PITCH-BUFFER_COLS*2,PuntaSfondoGr	; ANDIAMO A CAPO	
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

	MOVE.L	#SFONDOGRANDE+16*SFONDO_PITCH+2,A2	; ind. sorgente A
	MOVE.L  CurrentDraw,A1				; ind. destinazione D

	; Registri "fissi" settati una sola volta fuori dal loop
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM = $FFFF/$FFFF
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#8,$64(A6)				; BLTAMOD = 48-40 (sorgente pitch 48)
	MOVE.W	#0,$66(A6)				; BLTDMOD = 40-40 (dest pitch 40)

	MOVEQ	#5-1,D4					; Numero blittate = 5 per 5 planes
.BlittaLoopVideo:
	BSR.W	AspettaBlitter			; Aspetta che il blit precedente finisca
	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT
	MOVE.W	#(256<<6)+20,$58(A6)	; BLTSIZE = 256 righe * 20 word

	ADD.L	#288*SFONDO_PITCH,A2	; prossimo plane sorgente
	ADD.L	#256*40,A1				; prossimo plane destinazione

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
	MOVE.W	#48,bob_X(A0)				; inizio X 
	MOVE.W	#16,bob_Y(A0)				; inizio Y
	MOVE.W	#1,bob_Speed(A0)			; velocità default
	MOVE.W	#2,bob_Direzione(A0)		; 0 = guarda a sud
	MOVE.W	#0,bob_AnimFrame(A0)		; primo frame
	MOVE.L	#OMINO,bob_Gfx(A0)			; puntatore allo spritesheet
	MOVE.W	#(16*64)+1,bob_BltSize(A0)  ; 16 righe x 1 word
	MOVE.W	#16,bob_Larghezza(A0)
	MOVE.W	#16,bob_Altezza(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVE.W	#1,bob_Active(A0)
	MOVE.W	#0,bob_WorldX(A0)
	MOVE.W	#0,bob_WorldY(A0)
	MOVE.W	#0,bob_AI(A0)
		; --- Hit Points ---
	MOVE.W	#20,bob_PFmax(A0)			; player ha 20 PF max
	MOVE.W	#20,bob_PF(A0)				; PF correnti = max
	MOVE.W	#1,bob_Damage(A0)			; player danno 1 (non utilizzato per ora, scontro)
	MOVE.W	#0,bob_Invuln(A0)			; vulnerabile all'inizio
	
	MOVEM.L	(SP)+,A0
	RTS

*****************************************************************************
* InitEnemies
*   Inizializza l'array Enemies con ENEMY_COUNT nemici, posizionati a
*   coordinate mondo predefinite.
*   bob_Active = 1 -> nemico attivo (da renderizzare)
*   bob_Active = 0 -> slot vuoto (skippato dal rendering)
*****************************************************************************
InitEnemies:
	MOVEM.L	D0/A0/A1,-(SP)

	LEA		Enemies,A0
	LEA		EnemyInitTable,A1
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; A0 = struct del nemico corrente
	; A1 = puntatore alla riga della tabella init 
	;			(8 word: WorldX, WorldY, Direzione, Active, AI, PFmax, 
	;					 Damage, InvulnMax)
	MOVE.W	#2,bob_Type(A0)					; 2 = Nemico
	MOVE.W	(A1)+,bob_WorldX(A0)			; posizione mondo X
	MOVE.W	(A1)+,bob_WorldY(A0)			; posizione mondo Y
	MOVE.W	(A1)+,bob_Direzione(A0)
	MOVE.W	(A1)+,bob_Active(A0)
	MOVE.W	(A1)+,bob_AI(A0)
	MOVE.W	(A1),bob_PFmax(A0)				; PF massimi
	MOVE.W	(A1)+,bob_PF(A0)				; PF correnti = max (carico stesso valore)
	MOVE.W	(A1)+,bob_Damage(A0)			; danno inflitto
	MOVE.W	(A1)+,bob_InvulnMax(A0)			; frame di invuln dopo hit
	MOVE.W	#0,bob_Invuln(A0)				; vulnerabile all'inizio
	MOVE.W	#1,bob_Speed(A0)
	MOVE.W	#0,bob_X(A0)
	MOVE.W	#0,bob_Y(A0)
	MOVE.W	#1,bob_Speed(A0)
	MOVE.W	#0,bob_AnimFrame(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVE.L	#NEMICO,bob_Gfx(A0)				; spritesheet del nemico
	MOVE.W	#16,bob_Larghezza(A0)
	MOVE.W	#16,bob_Altezza(A0)
	; bob_X, bob_Y verranno calcolati al rendering da World - Camera

	LEA		bob_Length(A0),A0				; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0/A0/A1
	RTS
	
*****************************************************************************
* BuildOminoMask
*   Genera OMINO_MASK come OR dei 5 bitplane di OMINO.
*   Da chiamare UNA SOLA VOLTA al boot (i dati sono statici).
*
*   Logica: per ogni word dei 10240 byte = 5120 word del plane,
*           OMINO_MASK[i] = OMINO[plane0][i] OR ... OR OMINO[plane4][i]
***************************************************************************** 
BuildOminoMask:
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
	; *** FIX RENDERING: il rendering visualizza le tile sfasate di 1 tile
	; rispetto alle coordinate logiche. Compensiamo aggiungendo 16 ai check.
	ADDI.W	#16,D0
	ADDI.W	#16,D1
	MOVE.W	D0,D6					; salva worldX (input + 16)
	MOVE.W	D1,D7					; salva worldY (input + 16)

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
	; Ripristino D0/D1 input ORIGINALI (= D6/D7 - 16)
	MOVE.W	D6,D0
	SUBI.W	#16,D0
	MOVE.W	D7,D1
	SUBI.W	#16,D1
	MOVEM.L	(SP)+,D6-D7
	; Riapplico Z flag come "TST D2"
	TST.B	D2
	RTS
*****************************************************************************
* IsOverlapEnemies
*   Controlla se un BOB 16x16 a posizione (D0, D1) si sovrappone con
*   uno qualunque dei nemici attivi.
*
*   Due BOB 16x16 a (Xa, Ya) e (Xb, Yb) si sovrappongono se:
*     |Xa - Xb| < 16 AND |Ya - Yb| < 16
*   equivalente a:
*     (Xa - Xb) >= -15 AND (Xa - Xb) <= 15
*     (Ya - Yb) >= -15 AND (Ya - Yb) <= 15
*
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*           A2 = puntatore opzionale a un BOB DA ESCLUDERE (puo' essere 0)
*           [usato se un nemico controlla rispetto agli altri nemici, per
*            non confrontarsi con se stesso]
*   OUTPUT: Z=1 se NESSUN overlap (libero), Z=0 se overlap rilevato
*           D0/D1 preservati
*           D2 = 0 se libero, !=0 se overlap (per coerenza con IsBoxBlocked)
*           Tutti gli altri registri preservati.
*****************************************************************************
IsOverlapEnemies:
	MOVEM.L	D3-D5/A0,-(SP)

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D5
	MOVEQ	#0,D2					; default: nessun overlap
.loop:
	; Skip se nemico non attivo
	TST.W	bob_Active(A0)
	BEQ.S	.next
	; Skip se questo nemico e' quello da escludere
	CMPA.L	A2,A0
	BEQ.S	.next

	; Test sovrapposizione X: |D0 - bob_WorldX(A0)| < 16
	MOVE.W	D0,D3
	SUB.W	bob_WorldX(A0),D3		; D3 = D0 - enemyX
	; D3 in range [-15, 15] ?
	CMP.W	#-15,D3
	BLT.S	.next					; D3 < -15 -> non sovrappone
	CMP.W	#16,D3
	BGE.S	.next					; D3 >= 16 -> non sovrappone

	; Test sovrapposizione Y
	MOVE.W	D1,D4
	SUB.W	bob_WorldY(A0),D4		; D4 = D1 - enemyY
	CMP.W	#-15,D4
	BLT.S	.next
	CMP.W	#16,D4
	BGE.S	.next

	; Sia X che Y sovrapposti -> COLLISIONE
	MOVEQ	#1,D2					; segnala overlap
	BRA.S	.done					; esci dal loop appena trovo

.next:
	LEA		bob_Length(A0),A0		; prossimo nemico
	DBRA	D5,.loop

.done:
	MOVEM.L	(SP)+,D3-D5/A0
	TST.B	D2						; setta Z in base al risultato
	RTS

*****************************************************************************
* IsOverlapPlayer
*   Controlla se un BOB 16x16 a posizione (D0, D1) si sovrappone con
*   il Player.
*   Usato dai nemici per evitare di camminare sul player.
*
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*   OUTPUT: Z=1 se NO overlap, Z=0 se overlap
*           D2 = 0 libero, !=0 overlap
*           D0/D1 preservati
*****************************************************************************
IsOverlapPlayer:
	MOVEM.L	D3-D4,-(SP)
	MOVEQ	#0,D2					; default libero

	; Test X
	MOVE.W	D0,D3
	SUB.W	PlayerWorldX,D3
	CMP.W	#-15,D3
	BLT.S	.done
	CMP.W	#16,D3
	BGE.S	.done

	; Test Y
	MOVE.W	D1,D4
	SUB.W	PlayerWorldY,D4
	CMP.W	#-15,D4
	BLT.S	.done
	CMP.W	#16,D4
	BGE.S	.done

	MOVEQ	#1,D2					; overlap
.done:
	MOVEM.L	(SP)+,D3-D4
	TST.B	D2
	RTS

*****************************************************************************
* IsEnemyBlocked
*   Controlla se un nemico puo' muoversi a (D0, D1):
*   - tile bloccata?
*   - sovrapposizione col player?
*   - sovrapposizione con un ALTRO nemico (escluso A2 = se stesso)?
*
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*           A2 = puntatore al nemico stesso (per escluderlo da IsOverlapEnemies)
*   OUTPUT: Z=1 libero, Z=0 bloccato
*           D2 = 0 libero, !=0 bloccato
*           D0/D1 preservati
*****************************************************************************
IsEnemyBlocked:
	BSR.W	IsBoxBlocked			; tile?
	BNE.S	.blocked
	BSR.W	IsOverlapPlayer			; player?
	BNE.S	.blocked
	BSR.W	IsOverlapEnemies		; altri nemici (A2 escluso)?
	BNE.S	.blocked
	; libero
	MOVEQ	#0,D2
	RTS
.blocked:
	MOVEQ	#1,D2
	RTS

*****************************************************************************
* UpdateEnemies
*   Per ogni nemico attivo, aggiorna la sua posizione in base a bob_AI:
*     0 = fermo
*     1 = ronda su/giù
*     2 = ronda dx/sx
*     3 = caccia il player
*****************************************************************************
UpdateEnemies:
	MOVEM.L	D0/A0,-(SP)

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; Skip nemico inattivo
	TST.W	bob_Active(A0)
	BEQ.S	.next

	; Switch su bob_AI
	MOVE.W	bob_AI(A0),D1
	BEQ.S	.next					; AI=0 -> fermo
	CMP.W	#1,D1
	BEQ.S	.do_patrol
	CMP.W	#2,D1
	BEQ.S	.do_hunt
	BRA.S	.next					; AI sconosciuta -> skip

.do_patrol:
	BSR.W	AI_Patrol
	BRA.S	.next
.do_hunt:
	BSR.W	AI_Hunt

.next:
	LEA		bob_Length(A0),A0		; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0/A0
	RTS
* InitSprites
*   Setup degli sprite hardware:
*   - SPR0 punta a BulletSprite
*   - SPR1..SPR7 puntano a EmptySprite
*****************************************************************************
InitSprites:
	MOVEM.L	D0-D2/A0/A1,-(SP)

	; Inizializza header BulletSprite OFF
	LEA		BulletSprite,A0
	MOVE.W	#0,(A0)
	MOVE.W	#0,2(A0)

	; A0 = inizio Sprites nella copperlist
	LEA		Sprites,A0

	; SPR0 -> BulletSprite
	MOVE.L	#BulletSprite,D0
	MOVE.W	D0,6(A0)						; SPR0PTL valore (offset 6)
	SWAP	D0
	MOVE.W	D0,2(A0)						; SPR0PTH valore (offset 2)

	; SPR1..SPR7 -> EmptySprite
	MOVE.L	#EmptySprite,D1
	LEA		8(A0),A1						; A1 punta a SPR1 entry
	MOVEQ	#7-1,D2
.spr_loop:
	MOVE.L	D1,D0
	MOVE.W	D0,6(A1)						; SPRxPTL valore
	SWAP	D0
	MOVE.W	D0,2(A1)						; SPRxPTH valore
	ADDA.L	#8,A1
	DBRA	D2,.spr_loop

	MOVEM.L	(SP)+,D0-D2/A0/A1
	RTS

*****************************************************************************
* ProcessBullet
*   Gestisce il proiettile (1 alla volta).
*****************************************************************************
Proiettile:
	MOVEM.L	D0-D5/A0,-(SP)

	; Decrementa cooldown se > 0
	MOVE.W	Bullet_Cooldown,D0
	BEQ.S	.cooldown_done
	SUBQ.W	#1,D0
	MOVE.W	D0,Bullet_Cooldown
.cooldown_done:

	; ----- Stato fire corrente -----
	MOVE.B	$bfe001,D0
	NOT.B	D0
	AND.B	#$80,D0
	BEQ.S	.no_joy_fire
	MOVEQ	#1,D1
	BRA.S	.fire_check_space
.no_joy_fire:
	MOVEQ	#0,D1
.fire_check_space:
	TST.B	key_space
	BEQ.S	.fire_done
	MOVEQ	#1,D1
.fire_done:

	; ----- Stato bullet -----
	TST.W	Bullet_Active
	BNE.W	.update_bullet

	; Non attivo: edge detection + cooldown
	TST.W	D1
	BEQ.W	.save_fire
	TST.W	FirePrev
	BNE.W	.save_fire
	TST.W	Bullet_Cooldown
	BNE.W	.save_fire

	; --- SPAWN! ---
	LEA		Player,A0
	MOVE.W	bob_WorldX(A0),D2
	ADDI.W	#8,D2
	MOVE.W	D2,Bullet_X
	MOVE.W	bob_WorldY(A0),D3
	ADDI.W	#8,D3
	MOVE.W	D3,Bullet_Y

	MOVE.W	bob_Direzione(A0),D2
	AND.W	#7,D2
	LSL.W	#2,D2
	LEA		DirectionDeltas,A0
	MOVE.W	(A0,D2.W),Bullet_DirX
	MOVE.W	2(A0,D2.W),Bullet_DirY

	MOVE.W	#1,Bullet_Active
	MOVE.W	#BULLET_TTL,Bullet_TTL
	MOVE.W	#BULLET_COOLDOWN,Bullet_Cooldown
	BRA.W	.save_fire

.update_bullet:
	; Muovi
	MOVE.W	Bullet_DirX,D2
	MULS.W	#BULLET_SPEED,D2
	ADD.W	D2,Bullet_X
	MOVE.W	Bullet_DirY,D2
	MULS.W	#BULLET_SPEED,D2
	ADD.W	D2,Bullet_Y

	; Decrementa TTL
	MOVE.W	Bullet_TTL,D2
	SUBQ.W	#1,D2
	MOVE.W	D2,Bullet_TTL
	BNE.S	.check_bullet_bounds
	MOVE.W	#0,Bullet_Active
	BRA.W	.save_fire

.check_bullet_bounds:
	MOVE.W	Bullet_X,D2
	BMI.S	.bullet_off
	CMP.W	#MAPPA_COLS*16,D2
	BGE.S	.bullet_off
	MOVE.W	Bullet_Y,D2
	BMI.S	.bullet_off
	CMP.W	#MAPPA_ROWS*16,D2
	BGE.S	.bullet_off
	BRA.S	.check_bullet_collision
.bullet_off:
	MOVE.W	#0,Bullet_Active
	BRA.W	.save_fire

.check_bullet_collision:
	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D5
.coll_loop:
	TST.W	bob_Active(A0)
	BEQ.S	.coll_next

	MOVE.W	bob_WorldX(A0),D2
	ADDI.W	#8,D2
	SUB.W	Bullet_X,D2
	BPL.S	.coll_absx
	NEG.W	D2
.coll_absx:
	CMP.W	#10,D2
	BGE.S	.coll_next

	MOVE.W	bob_WorldY(A0),D2
	ADDI.W	#8,D2
	SUB.W	Bullet_Y,D2
	BPL.S	.coll_absy
	NEG.W	D2
.coll_absy:
	CMP.W	#10,D2
	BGE.S	.coll_next

	; HIT!
	MOVE.W	bob_PF(A0),D2
	SUB.W	#BULLET_DAMAGE,D2
	BPL.S	.coll_hit_alive
	MOVE.W	#0,D2
.coll_hit_alive:
	MOVE.W	D2,bob_PF(A0)
	MOVE.W	#2,bob_AI(A0)
	MOVE.W	bob_InvulnMax(A0),bob_Invuln(A0)
	MOVE.W	#0,Bullet_Active
	TST.W	bob_PF(A0)
	BNE.S	.save_fire
	MOVE.W	#0,bob_Active(A0)
	BRA.S	.save_fire

.coll_next:
	LEA		bob_Length(A0),A0
	DBRA	D5,.coll_loop

.save_fire:
	MOVE.W	D1,FirePrev

	MOVEM.L	(SP)+,D0-D5/A0
	RTS

*****************************************************************************
* UpdateBulletSprite
*   Aggiorna SPRPOS/SPRCTL dello sprite hardware del proiettile.
*****************************************************************************
AggiornaProiettile:
	MOVEM.L	D0-D3/A0,-(SP)

	LEA		BulletSprite,A0

	TST.W	Bullet_Active
	BNE.S	.spr_on
	MOVE.W	#0,(A0)
	MOVE.W	#0,2(A0)
	BRA.W	.done

.spr_on:
	; screenX = Bullet_X - CameraX
	MOVE.W	TileX,D0
	LSL.W	#4,D0
	ADD.W	PixelOffX,D0
	MOVE.W	Bullet_X,D2
	SUB.W	D0,D2

	; screenY = Bullet_Y - CameraY
	MOVE.W	TileY,D0
	LSL.W	#4,D0
	ADD.W	PixelOffY,D0
	MOVE.W	Bullet_Y,D3
	SUB.W	D0,D3

	; Cull
	TST.W	D2
	BMI.S	.spr_off
	CMP.W	#320,D2
	BGE.S	.spr_off
	TST.W	D3
	BMI.S	.spr_off
	CMP.W	#256-BULLET_HEIGHT,D3
	BGE.S	.spr_off

	; VSTART = screenY + $2C, HSTART = screenX + $81
	ADDI.W	#$2C,D3
	ADDI.W	#$81,D2

	; SPRPOS = (VSTART low << 8) | (HSTART >> 1)
	MOVE.W	D3,D0
	ANDI.W	#$FF,D0
	LSL.W	#8,D0
	MOVE.W	D2,D1
	LSR.W	#1,D1
	ANDI.W	#$FF,D1
	OR.W	D1,D0
	MOVE.W	D0,(A0)

	; SPRCTL = (VSTOP low << 8) | bits estensione
	MOVE.W	D3,D0
	ADDI.W	#BULLET_HEIGHT,D0
	ANDI.W	#$FF,D0
	LSL.W	#8,D0
	BTST	#8,D3
	BEQ.S	.no_vs8
	BSET	#2,D0
.no_vs8:
	MOVE.W	D3,D1
	ADDI.W	#BULLET_HEIGHT,D1
	BTST	#8,D1
	BEQ.S	.no_vp8
	BSET	#1,D0
.no_vp8:
	BTST	#0,D2
	BEQ.S	.no_h0
	BSET	#0,D0
.no_h0:
	MOVE.W	D0,2(A0)
	BRA.S	.done

.spr_off:
	MOVE.W	#0,(A0)
	MOVE.W	#0,2(A0)
.done:
	MOVEM.L	(SP)+,D0-D3/A0
	RTS

*****************************************************************************
* ProcessCombat
*   Gestisce gli scontri player <-> nemici.
*   Logica:
*   1. Decrementa Invuln di tutti i BOB (player + nemici)
*   2. Per ogni nemico attivo non invulnerabile e player non invulnerabile:
*      - se in collisione (AABB):
*        - player.PF -= nemico.Damage
*        - nemico.PF -= player.Damage
*        - entrambi Invuln = 50
*        - se PF <= 0: morte (Active=0 per nemico; flag per player)
*****************************************************************************
Combattimento:
	MOVEM.L	D0-D5/A0/A1,-(SP)

	; --- Decrementa Invuln del player ---
	LEA		Player,A1
	MOVE.W	bob_Invuln(A1),D2
	BEQ.S	.player_inv_done
	SUBQ.W	#1,D2
	MOVE.W	D2,bob_Invuln(A1)
.player_inv_done:

	; --- Loop nemici ---
	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; Skip nemico non attivo
	TST.W	bob_Active(A0)
	BEQ.W	.next

	; Decrementa Invuln del nemico
	MOVE.W	bob_Invuln(A0),D2
	BEQ.S	.check_collision
	SUBQ.W	#1,D2
	MOVE.W	D2,bob_Invuln(A0)
	BRA.W	.next						; se era invulnerabile, no collision check

.check_collision:
	; Test overlap player-nemico (AABB, soglia 17 = anche contatto tangente)
	; IsOverlapEnemies usa soglia 16 = i BOB possono essere adiacenti (dx=16 esatto)
	; Combattimento usa 17 per scattare anche quando si toccano sui bordi.
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	bob_WorldX(A1),D1
	BPL.S	.absx_ok
	NEG.W	D1
.absx_ok:
	CMP.W	#17,D1
	BGE.W	.next						; no overlap X

	MOVE.W	bob_WorldY(A0),D1
	SUB.W	bob_WorldY(A1),D1
	BPL.S	.absy_ok
	NEG.W	D1
.absy_ok:
	CMP.W	#17,D1
	BGE.W	.next						; no overlap Y

	; --- COLLISIONE GEOMETRICA! ---
	; Ognuno infligge danno solo se sta GUARDANDO il bersaglio.
	; "Guardare" = octante del vettore verso il bersaglio entro ±1 da bob_Direzione.

	; --- 1) Player colpisce nemico se guarda verso nemico ---
	MOVE.W	bob_WorldX(A0),D4
	SUB.W	bob_WorldX(A1),D4			; D4 = dx (nemico.X - player.X)
	MOVE.W	bob_WorldY(A0),D5
	SUB.W	bob_WorldY(A1),D5			; D5 = dy (nemico.Y - player.Y)
	BSR.W	DirezioneVerso				; D4 = octante player -> nemico
	MOVE.W	bob_Direzione(A1),D5
	BSR.W	OctantsClose				; D5 = 1 se vicini
	TST.W	D5
	BEQ.S	.player_no_hit
	; Player colpisce nemico
	MOVE.W	bob_Damage(A1),D1			; danno player
	MOVE.W	bob_PF(A0),D2
	SUB.W	D1,D2
	BPL.S	.enemy_alive
	MOVE.W	#0,D2
.enemy_alive:
	MOVE.W	D2,bob_PF(A0)
	MOVE.W	bob_InvulnMax(A0),bob_Invuln(A0)
	; Cambia AI nemico a Hunt (allarme!)
	MOVE.W	#2,bob_AI(A0)
	; Knockback nemico nella direzione del player
	; A0 = nemico (target), A1 = player (attacker) — ordine giusto
	BSR.W	ApplyKnockback
	; Se PF nemico = 0 -> disattiva
	TST.W	bob_PF(A0)
	BNE.S	.player_no_hit
	MOVE.W	#0,bob_Active(A0)
.player_no_hit:

	; --- 2) Nemico colpisce player se guarda verso player ---
	; Player era invulnerabile? Skip
	TST.W	bob_Invuln(A1)
	BNE.W	.next
	MOVE.W	bob_WorldX(A1),D4
	SUB.W	bob_WorldX(A0),D4			; D4 = dx (player.X - nemico.X)
	MOVE.W	bob_WorldY(A1),D5
	SUB.W	bob_WorldY(A0),D5			; D5 = dy (player.Y - nemico.Y)
	BSR.W	DirezioneVerso				; D4 = octante nemico -> player
	MOVE.W	bob_Direzione(A0),D5
	BSR.W	OctantsClose
	TST.W	D5
	BEQ.W	.next
	; Nemico colpisce player
	MOVE.W	bob_Damage(A0),D1			; danno nemico
	MOVE.W	bob_PF(A1),D2
	SUB.W	D1,D2
	BPL.S	.player_alive
	MOVE.W	#0,D2
.player_alive:
	MOVE.W	D2,bob_PF(A1)
	MOVE.W	bob_InvulnMax(A1),bob_Invuln(A1)
	; Knockback player nella direzione del nemico
	; Per ApplyKnockback serve A0=target, A1=attacker
	; Qui A0=nemico, A1=player -> dobbiamo SCAMBIARLI
	EXG		A0,A1					; A0=player (target), A1=nemico (attacker)
	BSR.W	ApplyKnockback
	EXG		A0,A1					; ripristina A0=nemico, A1=player
	; Sync bob_WorldX/Y del Player con PlayerWorldX/Y (se il player e' stato spostato)
	MOVE.W	bob_WorldX(A1),PlayerWorldX
	MOVE.W	bob_WorldY(A1),PlayerWorldY

.next:
	LEA		bob_Length(A0),A0			; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D5/A0/A1
	RTS

*****************************************************************************
* DirezioneVerso
*   Calcola l'octante (direzione 0..7) di un vettore (dx, dy).
*   INPUT:  D4.w = dx, D5.w = dy
*   OUTPUT: D4.w = octante 0..7 secondo la convenzione bob_Direzione:
*           0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
*   Se dx = dy = 0, ritorna 0 (E) come default.
*****************************************************************************
DirezioneVerso:
	MOVEM.L	D0-D3,-(SP)

	; Segni e valori assoluti
	MOVE.W	D4,D0					; D0 = dx
	MOVE.W	D5,D1					; D1 = dy
	; |dx|
	MOVE.W	D0,D2
	BPL.S	.ax_ok
	NEG.W	D2
.ax_ok:
	; |dy|
	MOVE.W	D1,D3
	BPL.S	.ay_ok
	NEG.W	D3
.ay_ok:
	; Default octante 0
	MOVEQ	#0,D4

	; Caso dx==dy==0 -> resta 0
	TST.W	D2
	BNE.S	.check
	TST.W	D3
	BEQ.S	.done
.check:
	; Regole:
	;   |dx| > 2*|dy| -> orizzontale puro (E o W)
	;   |dy| > 2*|dx| -> verticale puro (S o N)
	;   altrimenti -> diagonale

	; Confronto: 2*|dy| < |dx| ?
	MOVE.W	D3,D5
	ADD.W	D5,D5					; D5 = 2*|dy|
	CMP.W	D2,D5
	BGE.S	.not_horiz
	; Orizzontale puro
	TST.W	D0
	BMI.S	.W_dir
	MOVEQ	#0,D4					; E
	BRA.S	.done
.W_dir:
	MOVEQ	#4,D4					; W
	BRA.S	.done
.not_horiz:
	; |dy| > 2*|dx| ?
	MOVE.W	D2,D5
	ADD.W	D5,D5					; D5 = 2*|dx|
	CMP.W	D3,D5
	BGE.S	.diagonal
	; Verticale puro
	TST.W	D1
	BMI.S	.N_dir
	MOVEQ	#2,D4					; S
	BRA.S	.done
.N_dir:
	MOVEQ	#6,D4					; N
	BRA.S	.done
.diagonal:
	; Diagonale: 4 casi su (segno_dx, segno_dy)
	TST.W	D0
	BMI.S	.diag_W
	; dx >= 0
	TST.W	D1
	BMI.S	.NE_dir
	MOVEQ	#1,D4					; SE
	BRA.S	.done
.NE_dir:
	MOVEQ	#7,D4					; NE
	BRA.S	.done
.diag_W:
	; dx < 0
	TST.W	D1
	BMI.S	.NW_dir
	MOVEQ	#3,D4					; SW
	BRA.S	.done
.NW_dir:
	MOVEQ	#5,D4					; NW
.done:
	MOVEM.L	(SP)+,D0-D3
	RTS

*****************************************************************************
* OctantsClose
*   Verifica se due octanti (0..7) sono "vicini" entro ±1 modulo 8.
*   INPUT:  D4.w = octante A, D5.w = octante B (sara' bob_Direzione)
*   OUTPUT: D5.w = 1 se vicini (|A-B| <= 1 modulo 8), 0 altrimenti
*****************************************************************************
OctantsClose:
	MOVEM.L	D0,-(SP)

	; D0 = (A - B) modulo 8
	MOVE.W	D4,D0
	SUB.W	D5,D0
	AND.W	#7,D0					; modulo 8

	; "Close" se D0 == 0, 1, o 7
	MOVEQ	#0,D5					; default = non vicini
	TST.W	D0
	BEQ.S	.close
	CMP.W	#1,D0
	BEQ.S	.close
	CMP.W	#7,D0
	BNE.S	.done
.close:
	MOVEQ	#1,D5
.done:
	MOVEM.L	(SP)+,D0
	RTS
*****************************************************************************
* ApplyKnockback
*   Applica una spinta al BOB "target" nella direzione dell'attaccante.
*   Il movimento e' di (attacker.*2) pixel nella direzione attacker.Direzione.
*   Se la nuova posizione e' bloccata (muro/fuori mappa), prova step piu' piccoli.
*
*   INPUT:
*     A0 = target (BOB che riceve il knockback)
*     A1 = attacker (BOB che lo infligge)
*   USA: D0-D5 (scratch, non preserva)
*   PRESERVA: A0, A1
*****************************************************************************
ApplyKnockback:
	MOVEM.L	D0-D5/A0-A2,-(SP)

	; Carica delta dalla DirectionDeltas[attacker.Direzione]
	MOVE.W	bob_Direzione(A1),D2
	AND.W	#7,D2					; sicurezza: clamp 0..7
	LSL.W	#2,D2					; *4 (4 byte per entry: dx + dy word)
	LEA		DirectionDeltas,A2
	MOVE.W	(A2,D2.W),D3			; D3 = dx normalizzato (-1, 0, 1)
	MOVE.W	2(A2,D2.W),D4			; D4 = dy normalizzato

	; Moltiplica per attacker.Speed
	MOVE.W	bob_Speed(A1),D5
	MULS.W	D5,D3					; D3 = dx_totale
	MULS.W	D5,D4					; D4 = dy_totale

	; Provo a muovere il target di (D3, D4)
	; Strategia: provo a step interi, riducendo fino a 0 se bloccato.
	; Loop: provo (D3, D4), se bloccato provo (D3/2, D4/2), ecc.
	; Approccio semplice: tentativo singolo, se bloccato accorciamo step
	;
	; In realta' poiche' DirectionDeltas restituisce sempre valori in {-1,0,1}
	; e Speed e' tipicamente piccolo (1-3), facciamo step-by-step di 1 pixel
	; finche' non siamo bloccati.

	; Determino unitDX/unitDY (segno di D3/D4)
	MOVE.W	D3,D0					; segno di dx
	BEQ.S	.unitdx_zero
	BPL.S	.unitdx_pos
	MOVEQ	#-1,D0
	BRA.S	.unitdx_done
.unitdx_pos:
	MOVEQ	#1,D0
.unitdx_done:
	; D0 = unitDX (-1, 0, 1)
.unitdx_zero:
	MOVE.W	D4,D1					; segno di dy
	BEQ.S	.unitdy_zero
	BPL.S	.unitdy_pos
	MOVEQ	#-1,D1
	BRA.S	.unitdy_done
.unitdy_pos:
	MOVEQ	#1,D1
.unitdy_done:
.unitdy_zero:
	; D0 = unitDX, D1 = unitDY

	; Numero di step da provare = |Speed| * 2 (knockback raddoppiato per impatto piu' evidente)
	MOVE.W	bob_Speed(A1),D5
	LSL.W	#4,D5					; D5 *= 4
;	ADD.W	D5,D5					; D5 *= 2
	BEQ.S	.kb_done				; speed 0, niente knockback

	; Loop step
.kb_loop:
	; Prossima posizione candidata
	MOVE.W	bob_WorldX(A0),D2
	ADD.W	D0,D2					; D2 = X candidato
	MOVE.W	bob_WorldY(A0),D3
	ADD.W	D1,D3					; D3 = Y candidato

	; Test IsBoxBlocked(D0=X, D1=Y) -> ma D0/D1 sono gia' i deltas.
	; Devo salvare D0/D1 e passare i candidati.
	MOVEM.L	D0/D1,-(SP)
	MOVE.W	D2,D0
	MOVE.W	D3,D1
	BSR.W	IsBoxBlocked
	; D2 = 0 libero, 1 bloccato
	MOVEM.L	(SP)+,D0/D1

	TST.B	D2
	BNE.S	.kb_done				; bloccato -> stop, niente piu' step

	; Step accettato: aggiorna posizione
	MOVE.W	bob_WorldX(A0),D2
	ADD.W	D0,D2
	MOVE.W	D2,bob_WorldX(A0)
	MOVE.W	bob_WorldY(A0),D3
	ADD.W	D1,D3
	MOVE.W	D3,bob_WorldY(A0)

	SUBQ.W	#1,D5
	BNE.S	.kb_loop

.kb_done:
	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

*****************************************************************************
* DisegnaHealthBars
*   Disegna una barra di vita rossa (16 pixel × 2 righe) sopra ogni BOB attivo
*   (player + nemici). La lunghezza della barra è proporzionale a PF/PFmax.
*   Posizione: 3 pixel sopra il BOB (riga bob_Y - 3 e bob_Y - 2).
*   Colore: 14 (rosso/rosa nella palette = bit 1+2+3 = $0E).
*   Disegnata DOPO i BOB (= sopra di essi, ultima cosa renderizzata).
*
*   Per ogni BOB attivo:
*   1. Calcola N = (bob_PF * 16) / bob_PFmax  (= pixel da accendere)
*   2. Crea bitmask N pixel a sinistra: $FFFF << (16-N)
*   3. Per ogni plane:
*      - Se plane fa parte del colore: scrivi mask
*      - Altrimenti: scrivi 0
*   4. Scrivi su 2 righe (bob_Y-3, bob_Y-2)
*
*   Posizione su backbuffer:
*     offset_riga = (bob_Y - 3) * 40
*     offset_col_byte = (bob_X / 16) * 2     [word allineato]
*     pero' se bob_X non e' allineato a 16, dobbiamo scrivere su 2 word
*     (per ora SEMPLIFICAZIONE: blittiamo solo a posizione word allineata,
*      la barra "salta a scatti di 16 pixel" durante lo scroll fine)
*****************************************************************************
DisegnaBarraVita:
	MOVEM.L	D0-D7/A0-A2,-(SP)

	; Aspetta che il blitter finisca i BOB prima di scrivere col CPU
	BSR.W	AspettaBlitter

	; Disegna prima la barra del player
	LEA		Player,A0
	BSR.S	.draw_one
	; Poi le barre dei nemici
	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D7
.loop:
	BSR.S	.draw_one
	LEA		bob_Length(A0),A0
	DBRA	D7,.loop

	MOVEM.L	(SP)+,D0-D7/A0-A2
	RTS

; ----------------- subroutine: disegna barra per UN BOB -----------------
; INPUT: A0 = BOB
; PRESERVA TUTTI i registri usati (D1-D7, A0, A1) per non corrompere lo stato
; del chiamante che usa D7 come counter del loop.
.draw_one:
	MOVEM.L	D0-D7/A0-A1,-(SP)
	; Skip se non attivo
	TST.W	bob_Active(A0)
	BEQ.W	.skip

	; Skip se PFmax = 0 (sicurezza)
	MOVE.W	bob_PFmax(A0),D2
	BEQ.W	.skip

	; Calcola N = (PF * 16) / PFmax
	MOVE.W	bob_PF(A0),D1
	BEQ.W	.skip						; PF=0, niente barra
	LSL.W	#4,D1						; PF * 16
	DIVU.W	D2,D1						; / PFmax
	; D1.w = N (0..16)
	CMP.W	#16,D1
	BLE.S	.n_ok
	MOVE.W	#16,D1
.n_ok:

	; Costruisci bitmask con N bit alti a 1: $FFFF << (16-N)
	MOVE.W	#16,D2
	SUB.W	D1,D2						; D2 = 16-N
	MOVE.W	#$FFFF,D1
	; Shifta a sinistra di 0..16
	CMP.W	#16,D2
	BLT.S	.shift_ok
	MOVE.W	#0,D1						; tutti 0 se N=0
	BRA.S	.mask_done
.shift_ok:
	LSL.W	D2,D1
.mask_done:
	; D1.w = bitmask della barra (1 = pixel acceso del colore rosso)

	; Verifica che bob_X sia in viewport [0, 288]
	; (288 perché blittiamo 2 word a partire da bob_X allineato a word; per
	;  bob_X > 288 la second word esce dal display e wrappa nella riga successiva)
	MOVE.W	bob_X(A0),D2
	BMI.W	.skip						; bob_X < 0 -> skip
	CMP.W	#289,D2
	BGE.W	.skip						; bob_X >= 289 -> skip
	MOVE.W	bob_Y(A0),D3
	; Verifica bob_Y in range "visibile" [-15, 240]
	; bob_Y < -15: BOB completamente fuori in alto -> skip
	; bob_Y > 240: BOB esce in basso -> per ora skip anche se parziale
	CMP.W	#-15,D3
	BLT.W	.skip
	CMP.W	#241,D3
	BGE.W	.skip

	; Decide se disegnare la barra SOPRA o SOTTO il BOB
	; Sopra (preferito): bob_Y - 3.  Sotto (fallback): bob_Y + 16.
	; Se bob_Y < 3, mettiamo la barra SOTTO
	CMP.W	#HEALTHBAR_YOFFSET,D3
	BLT.S	.bar_below
	; bar_above
	SUB.W	#HEALTHBAR_YOFFSET,D3		; D3 = bob_Y - 3
	BRA.S	.y_ok
.bar_below:
	; bob_Y < 3 -> mettiamo la barra a bob_Y + 16 (sotto il BOB)
	ADDI.W	#16,D3
	; Verifica che D3+1 stia nello schermo (D3 <= 254)
	CMP.W	#255,D3
	BGE.W	.skip
.y_ok:
	; D3 = riga di partenza barra (0..254). Deve essere positivo a questo punto.
	TST.W	D3
	BMI.W	.skip						; safety check

	; ----- Calcolo bitmask 32-bit shiftata -----
	; D1 = bitmask 16-bit (N bit alti a 1). Vogliamo posizionarla a pixel bob_X.
	; Strategia: estendi a 32 bit (bitmask << 16), poi shifta a destra di (bob_X mod 16).
	; Risultato: D1.long = pattern 32-bit dove i bit della barra sono a posizione (bob_X mod 16).
	;
	; D2 = bob_X (gia' caricato sopra)
	; shift = bob_X & 15
	MOVE.W	D2,D4						; D4 = bob_X
	ANDI.W	#15,D4						; D4 = shift (0..15)
	SWAP	D1							; D1.high = bitmask, D1.low = 0
	; LSR.L con count immediato 0..8. Se shift > 8 dividiamo in 2 passi.
	CMP.W	#8,D4
	BLT.S	.shift_once
	LSR.L	#8,D1
	SUB.W	#8,D4
.shift_once:
	; Adesso shift e' 0..7, posso usarlo come immediato? No, LSR.L con count variabile
	; serve un registro come count.
	; Trick: uso un loop di shift singoli, oppure shift con register
	TST.W	D4
	BEQ.S	.shift_done
.shift_more:
	LSR.L	#1,D1
	SUBQ.W	#1,D4
	BNE.S	.shift_more
.shift_done:
	; D1.long = bitmask shiftata. Bit alti = word di sinistra (a posizione word_x).
	; Bit bassi = word di destra (word_x + 1).

	; ----- Calcolo offset destinazione (allineato a word) -----
	; byte_offset = (bob_X / 16) * 2 + D3 * 40
	MOVE.W	D2,D4
	LSR.W	#4,D4						; D4 = bob_X / 16
	LSL.W	#1,D4						; D4 = byte offset di word
	MOVE.W	D3,D5
	MULU.W	#40,D5						; D5.l = D3*40
	ADD.L	D4,D5						; D5.l = offset totale plane 0 riga D3

	; A1 = base del backbuffer (CurrentDraw)
	MOVE.L	CurrentDraw,A1
	ADD.L	D5,A1						; A1 = posizione barra sul plane 0

	; ----- Loop sui 5 plane -----
	; Per ogni plane:
	;   se HEALTHBAR_COLOR ha bit acceso -> pixel |= bitmask (OR per accendere)
	;   se HEALTHBAR_COLOR ha bit spento -> pixel &= ~bitmask (AND per spegnere)
	; Cosi' i pixel della barra piena vengono colorati, ma i pixel "vuoti"
	; (dove bitmask = 0) restano invariati = mostrano lo sfondo sotto = trasparenza.
	; Per ogni plane scriviamo 2 righe (riga D3, riga D3+1)
	MOVE.W	#HEALTHBAR_COLOR,D6
	MOVE.L	D1,D2						; D2 = bitmask (uso per OR)
	NOT.L	D1							; D1 = ~bitmask (uso per AND)
	MOVEQ	#5-1,D5
.plane_loop:
	BTST	#0,D6
	BEQ.S	.plane_off
	; Plane acceso: OR con bitmask (accende i pixel della barra)
	OR.L	D2,(A1)						; riga D3
	OR.L	D2,40(A1)					; riga D3+1
	BRA.S	.plane_next
.plane_off:
	; Plane spento: AND con NOT bitmask (spegne i pixel della barra)
	AND.L	D1,(A1)						; riga D3
	AND.L	D1,40(A1)					; riga D3+1
.plane_next:
	; Prossimo plane
	ADDA.L	#40*256,A1
	LSR.W	#1,D6
	DBRA	D5,.plane_loop
.skip:
	MOVEM.L	(SP)+,D0-D7/A0-A1
	RTS
*****************************************************************************
* AI_Patrol
*   Ronda generica a 8 direzioni: usa DirectionDeltas per calcolare il
*   movimento (dx, dy) in base a bob_Direzione. Quando bloccato, ruota
*   la direzione di 180° (dir XOR 4), che funziona per tutte le 8
*   direzioni: E<->W, SE<->NW, S<->N, SW<->NE.
*   INPUT: A0 = struct nemico
*****************************************************************************
AI_Patrol:
	MOVEM.L	D0-D4/A0-A2,-(SP)
	MOVE.L	A0,A2					; A2 = nemico stesso (per esclusione overlap)

	; Indice nella tabella: bob_Direzione * 4 (4 byte per riga: 2 word)
	MOVE.W	bob_Direzione(A0),D2
	AND.W	#7,D2					; sicurezza: clamp 0..7
	LSL.W	#2,D2					; *4
	LEA		DirectionDeltas,A1
	; Carico dx, dy (segnati) e moltiplico per Speed
	MOVE.W	(A1,D2.W),D3			; D3 = dx (-1, 0, +1)
	MOVE.W	2(A1,D2.W),D4			; D4 = dy (-1, 0, +1)
	MOVE.W	bob_Speed(A0),D1
	MULS.W	D1,D3					; D3 = dx * Speed
	MULS.W	D1,D4					; D4 = dy * Speed

	; Calcolo nuova posizione candidata
	MOVE.W	bob_WorldX(A0),D0
	ADD.W	D3,D0					; D0 = X candidata
	MOVE.W	bob_WorldY(A0),D1
	ADD.W	D4,D1					; D1 = Y candidata

	BSR.W	IsEnemyBlocked
	BNE.S	.flip
	; Movimento accettato
	MOVE.W	D0,bob_WorldX(A0)
	MOVE.W	D1,bob_WorldY(A0)
	MOVE.W	#1,bob_IsMoving(A0)
	BRA.S	.done

.flip:
	; Inverte direzione di 180° (XOR 4 per tutte le 8 direzioni)
	MOVE.W	bob_Direzione(A0),D0
	EORI.W	#4,D0
	AND.W	#7,D0					; sicurezza
	MOVE.W	D0,bob_Direzione(A0)
	MOVE.W	#0,bob_IsMoving(A0)		; questo frame fermo
.done:
	MOVEM.L	(SP)+,D0-D4/A0-A2
	RTS

*****************************************************************************
* AI_Hunt
*   Inseguimento del Player con asse alternato:
*   1) Calcola dx, dy con il Player
*   2) Sceglie l'asse "preferito" (quello con differenza maggiore)
*   3) Tenta movimento sull'asse preferito
*   4) Se bloccato, prova sull'altro asse
*   5) Se entrambi bloccati, fermo
*****************************************************************************
AI_Hunt:
	MOVEM.L	D0-D5/A0/A2,-(SP)
	MOVE.L	A0,A2

	; D3 = dx (player - nemico), D4 = dy
	MOVE.W	PlayerWorldX,D3
	SUB.W	bob_WorldX(A0),D3
	MOVE.W	PlayerWorldY,D4
	SUB.W	bob_WorldY(A0),D4

	; |dx| in D5, |dy| in D6 ... usiamo solo D5 e ricalcolo |dy| dopo
	MOVE.W	D3,D5
	BPL.S	.absdx_ok
	NEG.W	D5
.absdx_ok:
	MOVE.W	D4,D2					; D2 = |dy|
	BPL.S	.absdy_ok
	NEG.W	D2
.absdy_ok:

	; Se siamo gia' addosso al player (entro 16 px su entrambi assi), non muovere
	; (gia' impedito da IsEnemyBlocked, ma evitiamo movimento inutile)
	; Asse preferito: quello con valore assoluto maggiore
	CMP.W	D5,D2
	BHI.S	.tryY_first				; |dy| > |dx| -> Y prima
	; Altrimenti X prima
	BSR.S	.tryX
	TST.B	D2						; success?
	BEQ.S	.done
	BSR.S	.tryY
	BRA.S	.done

.tryY_first:
	BSR.S	.tryY
	TST.B	D2
	BEQ.S	.done
	BSR.S	.tryX

.done:
	MOVEM.L	(SP)+,D0-D5/A0/A2
	RTS

; ---- subroutine locali per AI_Hunt ----
; .tryX: tenta movimento sull'asse X verso il player
; INPUT: D3 = dx (segno = direzione), A0 = nemico, A2 = nemico stesso
; OUTPUT: D2 = 0 se mosso, !=0 se bloccato
.tryX:
	TST.W	D3
	BEQ.S	.tryX_blocked			; dx = 0, niente da fare
	MOVE.W	bob_WorldX(A0),D0
	MOVE.W	bob_Speed(A0),D1
	TST.W	D3
	BMI.S	.tryX_left
	; dx > 0 -> verso destra (E)
	ADD.W	D1,D0
	MOVE.W	#0,bob_Direzione(A0)
	BRA.S	.tryX_check
.tryX_left:
	; dx < 0 -> verso sinistra (W)
	SUB.W	D1,D0
	MOVE.W	#4,bob_Direzione(A0)
.tryX_check:
	MOVE.W	bob_WorldY(A0),D1
	BSR.W	IsEnemyBlocked
	BNE.S	.tryX_blocked
	MOVE.W	D0,bob_WorldX(A0)
	MOVE.W	#1,bob_IsMoving(A0)
	MOVEQ	#0,D2					; mosso
	RTS
.tryX_blocked:
	MOVEQ	#1,D2					; bloccato
	RTS

; .tryY: tenta movimento sull'asse Y verso il player
.tryY:
	TST.W	D4
	BEQ.S	.tryY_blocked
	MOVE.W	bob_WorldY(A0),D1
	MOVE.W	bob_Speed(A0),D0
	TST.W	D4
	BMI.S	.tryY_up
	; dy > 0 -> verso giù (S)
	ADD.W	D0,D1
	MOVE.W	#2,bob_Direzione(A0)
	BRA.S	.tryY_check
.tryY_up:
	; dy < 0 -> verso su (N)
	SUB.W	D0,D1
	MOVE.W	#6,bob_Direzione(A0)
.tryY_check:
	MOVE.W	bob_WorldX(A0),D0
	BSR.W	IsEnemyBlocked
	BNE.S	.tryY_blocked
	MOVE.W	D1,bob_WorldY(A0)
	MOVE.W	#1,bob_IsMoving(A0)
	MOVEQ	#0,D2
	RTS
.tryY_blocked:
	MOVEQ	#1,D2
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
	MOVEM.L	D0-D2/A2,-(SP)

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
	BNE.S	.x_blocked				; collide con tile, rifiuta movimento X
	; Controllo collision con i nemici (player NON puo' entrare in un nemico)
	MOVE.L	#0,A2					; A2=0 -> non escludere nessun BOB
	BSR.W	IsOverlapEnemies
	BNE.S	.x_blocked				; overlap con nemico -> rifiuta	
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
	BNE.S	.y_blocked				; collide con tile, rifiuta movimento Y
	; Controllo collision con i nemici
	MOVE.L	#0,A2					; A2=0 -> non escludere nessun BOB
	BSR.W	IsOverlapEnemies
	BNE.S	.y_blocked				; overlap con nemico -> rifiuta	
	CMP.W	PlayerWorldY,D1
	BEQ.S	.y_blocked				; non si e' mosso (clamp) -> azzera ScrllY
	MOVE.W	D1,PlayerWorldY
	BRA.S	.skipY
.y_blocked:
	CLR.W	ScrllY					; sincronizza camera: niente scroll su Y
.skipY:

	; Sync bob_WorldX/Y del Player con le variabili globali
	; (cosi' Combattimento e altre routine possono leggerle uniformemente)
	LEA		Player,A2	
	MOVE.W	PlayerWorldX,bob_WorldX(A2)
	MOVE.W	PlayerWorldY,bob_WorldY(A2)

	MOVEM.L	(SP)+,D0-D2/A2
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
*****************************************************************************
* DisegnaBOB - routine generica di rendering del BOB
*   Input: A0 = puntatore alla struct bob_*
*   Funziona per Player e Nemici (qualunque entità con la stessa struct).
*   Utilizza bob_X/Y come coordinate SCHERMO (gia' calcolate dal chiamante).
*****************************************************************************
DisegnaBOB:
	MOVEM.L	D0-D7/A0-A3,-(SP)
	; A0 e' gia' settato dal chiamante (NON sovrascritto qui)

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
	; Layout: ogni frame occupa 2 word (32 pixel) per via del padding nero
	; che evita di blittare il frame successivo durante lo shift orizzontale.
	MOVE.W	bob_Direzione(A0),D3
	MULU.W	#640,D3					; Direzione * 16 righe * 40 byte
	MOVE.W	bob_AnimFrame(A0),D5
	ADD.W	D5,D5					; AnimFrame * 2
	ADD.W	D5,D5					; AnimFrame * 4 (= 2 word, con padding)
	ADD.W	D5,D3					; D3 = offset frame nel plane 0
 
	; ----------------- A2 = sorgente A (spritesheet plane 0) -----------------
	MOVE.L 	bob_Gfx(A0),A2
	ADDA.W	D3,A2
	; Applica clip top: sposta A2 in avanti di SkipRows * 40 byte
	MOVE.W	BobClipSkipRows,D2
	MULU.W	#40,D2					; D2 = skip * 40 (long)
	ADDA.L	D2,A2					; A2 punta alla riga di partenza del frame
 	; ----------------- A3 = sorgente B (maschera FISSA 16x16) -----------------
	; La maschera e' la stessa per tutti i frame (BOB e' un quadrato pieno).
	; NON aggiungiamo D3 (offset frame) perche' non ne ha senso.
	; Applico anche qui il clip top: salto SkipRows * 4 byte (pitch maschera = 4)
	LEA		OMINO_MASK_FIXED,A3
	MOVE.W	BobClipSkipRows,D2
	LSL.W	#2,D2					; D2 = skip * 4
	ADDA.W	D2,A3

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
	OR.W	#$0FCA,D5				; D5.w = BLTCON0 (cookie cut)
 
	; ----------------- BLTCON1 = BSH << 12 -----------------
	MOVE.W	D7,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; D6.w = BSH << 12 = BLTCON1
 
	; ----------------- BLTSIZE: NumRows righe x 2 word -----------------
	; NumRows = numero righe da blittare (default 16, o ridotto se clip Y)
	; 2 word per riga per gestire lo shift orizzontale.
	MOVE.W	BobClipNumRows,D4
	LSL.W	#6,D4					; D4 = NumRows << 6
	ADDQ.W	#2,D4					; +2 per le 2 word per riga

	; ----------------- Registri "fissi" del blit settati una sola volta -----------------
	; Questi registri sono uguali per tutti i 5 plane, quindi li settiamo PRIMA
	; del loop dei plane invece che ad ogni iterazione.
	BSR.W	AspettaBlitter			; assicura che il blit precedente sia finito

	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM = $FFFF/$FFFF
	MOVE.W	D5,$40(A6)				; BLTCON0 (con ASH = shift sulla MASCHERA = A)
	MOVE.W	D6,$42(A6)				; BLTCON1 (BSH = shift sul BOB = B)
	MOVE.W	#36,$60(A6)				; BLTCMOD = 40 - 4 (sfondo, pitch 40 byte)
	MOVE.W	#36,$62(A6)				; BLTBMOD = 40 - 4 (BOB, pitch 40 byte)
	MOVE.W	#0,$64(A6)				; BLTAMOD = 4 - 4 (MASK fissa 4 byte/riga)
	MOVE.W	#36,$66(A6)				; BLTDMOD = 40 - 4 (destinazione, pitch 40 byte)
 
	; ----------------- Loop sui 5 bitplane -----------------
	; L'incremento per passare al plane successivo e' SEMPRE plane_size = 10240 byte.
	; Il valore di A1/A2 nei registri CPU NON viene modificato dal blitter
	; (il blitter modifica BLTAPT/BLTBPT/BLTCPT/BLTDPT, registri propri).
	MOVEQ	#5-1,D0
.BlittaLoopBob:
	BSR.W	AspettaBlitter			; aspetta che il blit del plane precedente finisca
	MOVE.L	A1,$48(A6)				; BLTCPT (sfondo)
	MOVE.L	A2,$4C(A6)				; BLTBPT = BOB sorgente
	MOVE.L	A3,$50(A6)				; BLTAPT = MASCHERA
	MOVE.L	A1,$54(A6)				; BLTDPT (destinazione)

	MOVE.W	D4,$58(A6)				; BLTSIZE -> avvia blit
 

	ADD.L	#40*256,A2				; prossimo plane sorgente BOB (B): +10240
	ADD.L	#40*256,A1				; prossimo plane destinazione/sfondo: +10240

	; A3 (MASCHERA = A) NON avanza: e' una sola per tutti i plane
 
	DBRA	D0,.BlittaLoopBob
 
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
*****************************************************************************
* DisegnaBOBPlayer - wrapper che chiama DisegnaBOB con A0 = Player
*****************************************************************************
DisegnaBOBPlayer:
	MOVEM.L	A0,-(SP)
	; Player non viene mai clippato (ha PLAYER_MAX_X/Y che lo tiene dentro)
	MOVE.W	#0,BobClipSkipRows
	MOVE.W	#16,BobClipNumRows

	; bob_X/bob_Y del Player gia' calcolati da UpdatePlayerScreenPos
	LEA		Player,A0
	BSR.W	DisegnaBOB
	MOVEM.L	(SP)+,A0
	RTS

*****************************************************************************
* DisegnaBOBNemici
*   Per ogni nemico attivo:
*   1) calcola bob_X/Y (schermo) da bob_WorldX/Y - Camera
*   2) skippa se fuori dallo schermo (cull)
*   3) chiama DisegnaBOB
*****************************************************************************
DisegnaBOBEnemy:
	MOVEM.L	D0-D4/A0,-(SP)

	; Pre-calcolo CameraX/Y in pixel (D2, D3)
	MOVE.W	TileX,D2
	LSL.W	#4,D2					; D2 = TileX*16
	ADD.W	PixelOffX,D2			; D2 = CameraX in pixel

	MOVE.W	TileY,D3
	LSL.W	#4,D3					; D3 = TileY*16
	ADD.W	PixelOffY,D3			; D3 = CameraY

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; Skip se nemico non attivo
	TST.W	bob_Active(A0)
	BEQ.S	.next

	; ----- Calcolo bob_X e bob_Y schermo (SEMPRE aggiornati per uso esterno) -----
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	D2,D1					; D1 = bob_X schermo
	MOVE.W	D1,bob_X(A0)			; SEMPRE aggiornato (usato da DisegnaBarraVita)
	MOVE.W	bob_WorldY(A0),D4
	SUB.W	D3,D4					; D4 = bob_Y schermo
	MOVE.W	D4,bob_Y(A0)			; SEMPRE aggiornato

	; ----- Cull X: se completamente fuori, skippa rendering -----
	TST.W	D1
	BMI.S	.next					; bob_X < 0
	CMP.W	#305,D1
	BGE.S	.next					; bob_X >= 305

	; ----- Cull Y / preparazione clip Y -----
	MOVE.W	D4,D1					; D1 = bob_Y (per uso successivo)
	; Cull se bob_Y < -15 oppure bob_Y >= 256 (BOB completamente fuori)
	CMP.W	#-15,D1
	BLT.S	.next
	CMP.W	#256,D1
	BGE.S	.next

	; Default: no clip
	MOVE.W	#0,BobClipSkipRows
	MOVE.W	#16,BobClipNumRows

	; Clip TOP: se bob_Y < 0, salta -bob_Y righe e blitta 16+bob_Y righe
	TST.W	D1
	BPL.S	.check_bottom
	; bob_Y < 0: salta righe e parti dalla cima
	MOVE.W	D1,D4					; D4 = bob_Y (negativo)
	NEG.W	D4						; D4 = -bob_Y = righe da skippare
	MOVE.W	D4,BobClipSkipRows
	MOVE.W	#16,D4
	ADD.W	D1,D4					; D4 = 16 + bob_Y = righe da blittare
	MOVE.W	D4,BobClipNumRows
	MOVE.W	#0,D1					; bob_Y schermo = 0 (parte dalla cima del display)
	BRA.S	.set_y

.check_bottom:
	; Clip BOTTOM: se bob_Y > 240, blitta 256-bob_Y righe
	CMP.W	#240,D1
	BLE.S	.set_y
	; bob_Y > 240
	MOVE.W	#256,D4
	SUB.W	D1,D4					; D4 = 256 - bob_Y = righe da blittare
	MOVE.W	D4,BobClipNumRows

.set_y:
	; bob_Y resta col valore "vero" (settato gia' a inizio loop)
	; D1 contiene il valore clippato che serve al rendering, lo passo via variabile.
	; In realta' DisegnaBOB legge bob_X/Y, ma il rendering usa il valore "schermo"
	; del BOB. Per il clip top, il BOB deve partire da y=0, quindi sovrascriviamo
	; SOLO per il rendering, e ripristiniamo dopo.
	MOVE.W	bob_Y(A0),D4				; salva bob_Y vero in D4
	MOVE.W	D1,bob_Y(A0)				; metti valore clippato per il rendering

	; Renderizza il nemico (A0 e' gia' settato)
	BSR.W	DisegnaBOB

	; Ripristina bob_Y vero (per DisegnaBarraVita e logica)
	MOVE.W	D4,bob_Y(A0)

.next:
	LEA		bob_Length(A0),A0		; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D4/A0
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
	dc.b	1,	1,	0,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1
	even

*****************************************************************************
* Disegno la mappa con le tiles 
*****************************************************************************

MAPPA:
;			 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ;	 
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;0
	dc.w	 0, 2, 8,18, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 4, 0	;1
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
TileX:		dc.w	0
TileY:		dc.w	0
PixelOffX:	dc.w	0
PixelOffY:	dc.w	0
BufferOffX:	dc.w	0
BufferOffY:	dc.w	0
; Coordinate del player nel mondo (in pixel, non tile).
; Range valido: 0..MAP_WIDTH-16 per X, 0..MAP_HEIGHT-16 per Y
; Mappa = MAPPA_COLS*16 x MAPPA_ROWS*16 = 384 x 352 pixel
; Inizializzazione: player parte sopra la tile 18 (porta nel bordo nord)
;   tile 18 = MAPPA[1][3] -> world pixel (48, 16)
;   CameraX/Y iniziale = 0, quindi bob_X/Y schermo = (48, 16)
PlayerWorldX:	dc.w	32
PlayerWorldY:	dc.w	0
; Intent dell'utente (movimento desiderato): -1, 0, +1
; Distinto da ScrllX/Y che invece e' "camera scroll" (gated dal centro schermo).
; PlayerWorldX += IntentX sempre; ScrllX = IntentX solo se player al centro.
IntentX:		dc.w	0
IntentY:		dc.w	0
; Variabili di clipping per DisegnaBOB:
;   BobClipSkipRows: numero di righe da saltare all'inizio del frame (clip top)
;   BobClipNumRows:  numero di righe totali da blittare
; Vanno settate dal chiamante PRIMA di chiamare DisegnaBOB.
; Default per BOB completi (no clip): SkipRows=0, NumRows=16.
BobClipSkipRows:	dc.w	0
BobClipNumRows:		dc.w	16
; Flag per posticipare le chiamate Add* a DOPO lo shift pixel.
PdngAddRx:	dc.w	0	; boundary dx: scrivi col 21 subito dopo lo shift
PdngAddSx:	dc.w	0	; boundary sx: aspetta PixelOffX=0 (16 shift dx)
PdngAddBot:	dc.w	0	; boundary giu': scrivi riga bassa dopo lo shift
PdngAddTop:	dc.w	0	; boundary su: aspetta PixelOffY=0 (16 shift basso)
 
arrow_up:	dc.b 	0
arrow_dn:	dc.b 	0
arrow_sx:	dc.b 	0
arrow_rx:	dc.b 	0
key_space:	dc.b 	0			; 1 se SPACE premuta, 0 altrimenti

	EVEN

; ----- Stato proiettile -----
Bullet_Active:	dc.w	0		; 1 = proiettile vivo
Bullet_X:		dc.w	0		; coordinata mondo X (centro)
Bullet_Y:		dc.w	0		; coordinata mondo Y (centro)
Bullet_DirX:	dc.w	0		; vettore mov X (-1, 0, +1)
Bullet_DirY:	dc.w	0		; vettore mov Y (-1, 0, +1)
Bullet_TTL:		dc.w	0		; frame restanti
Bullet_Cooldown: dc.w	0		; cooldown corrente (0 = pronto a sparare)
FirePrev:		dc.w	0		; stato fire al frame precedente (per edge-detect)

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
								; 2 = Enemy
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
bob_Stato		rs.W	1		; campo per lo stato del bob
bob_Active		rs.W	1		; 1=attivo (da renderizzare/aggiornare), 0=morto/inesistente
bob_AI 			rs.w	1		; 0=fermo; 1=fa la ronda; 2=in cacccia
bob_WorldX		rs.w	1		; coordinata X nel mondo (in pixel)
bob_WorldY		rs.w	1		; coordinata Y nel mondo (in pixel)
bob_PFmax		rs.w	1		; punti ferita massimi
bob_PF			rs.w	1		; punti ferita correnti (0 = morto)
bob_Damage		rs.w	1		; danno che infligge al contatto
bob_Invuln		rs.w	1		; frame restanti di invulnerabilita' (0 = vulnerabile)
bob_InvulnMax	rs.w	1		; frame di invulnerabilita' impostati dopo un hit
bob_Length		rs.B	0		; dimensione della struttura

EnemyInitTable:
;       WorldX, WorldY, Direzione, Active, AI, PFmax, Damage, InvulnMax
	dc.w	64,		208,	2,		1,		0,	3,	1,	30
				; nemico 0: basso a sinistra, fermo, recupero 30 frame
	dc.w	288,	64,		3,		1,		2,	8,	3,	60
				; nemico 1: alto a destra, caccia, recupero 60 frame (lento, e' un TANK)
	dc.w	80,		208,	2,		1,		1,	4,	2,	40
				; nemico 2: ronda Y, recupero 40 frame
	dc.w	304,	224,	4,		1,		1,	5,	2,	50
				; nemico 3: ronda X, recupero 50 frame
*****************************************************************************
* DirectionDeltas
*   Tabella di delta (dx, dy) per ogni direzione, in unità di "Speed".
*   I valori sono normalizzati a -1, 0, +1 e poi moltiplicati per bob_Speed.
*   Indicizzata da bob_Direzione (0..7).
*****************************************************************************
DirectionDeltas:
;       dx,  dy
	dc.w	 1,  0	; 0 = E
	dc.w	 1,  1	; 1 = SE
	dc.w	 0,  1	; 2 = S
	dc.w	-1,  1	; 3 = SW
	dc.w	-1,  0	; 4 = W
	dc.w	-1, -1	; 5 = NW
	dc.w	 0, -1	; 6 = N
	dc.w	 1, -1	; 7 = NE

*****************************************************************************
*
* 		COPPER
*
*****************************************************************************	
		
	Section	ChipStuff,data_c

CopperList:
	dc.w	$0100,%0101001000000001		; BPLCON0 (ECSENA on per AGA palette)
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

; ============================================================================
; PALETTE AGA (24-bit, 32 colori)
; Strutturata come due blocchi consecutivi nella copperlist:
;   - Blocco 1: BPLCON3 con LOCT=0, scrive nibble ALTI di ogni canale RGB
;   - Blocco 2: BPLCON3 con LOCT=1, scrive nibble BASSI di ogni canale RGB
;
; Conversione OCS->AGA per ognuno dei 32 colori:
;   colore OCS $0RGB -> 24-bit $0RRGGBB con R duplicato in RR, ecc.
;   es. $0fff -> $0FFFFFF (R=$FF, G=$FF, B=$FF)
;   In questo caso i 4 bit alti = i 4 bit bassi = il valore originale.
;   Quindi entrambe le passate scrivono lo stesso valore di nibble.
;
; BPLCON3 = $0a0c0:
;   bit 9   = LOCT (0 = nibble alti, 1 = nibble bassi)
;   bit 13-15 = PALBANK (0 = banca 0)
;   bit 10  = BRDRBLNK (1 = bordo blank)
;   bit 6   = SPRES (0 = sprite a hires)
;   bit 5-4 = riservati 0
;   bit 0-3 = utilizzati per setting vari (qui = $0)
; Valore $0c00 = LOCT=0, banca 0, bordo blank
; Valore $0e00 = LOCT=1, banca 0, bordo blank
; ============================================================================
PALETTE:
	; ----- Blocco 1: nibble ALTI (LOCT=0) -----
	dc.w	$0106,$0c00			; BPLCON3 = LOCT=0

	dc.w 	$0180,$0000,$0182,$0fff,$0184,$0040,$0186,$0070	
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880	
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	dc.w 	$0198,$000f,$019a,$070f,$019c,$0c0e,$019e,$0c08
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca	
	dc.w 	$01a8,$0333,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff

	; ----- Blocco 2: nibble BASSI (LOCT=1) -----
	dc.w	$0106,$0e00			; BPLCON3 = LOCT=1
	dc.w 	$0180,$0000,$0182,$0fff,$0184,$0040,$0186,$0070
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	dc.w 	$0198,$000f,$019a,$070f,$019c,$0c0e,$019e,$0c08
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca
	dc.w 	$01a8,$0333,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff

	; Ripristino BPLCON3 a default LOCT=0 (per il prossimo frame)
	dc.w	$0106,$0c00
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
	dc.w	$0100,$0201		; BPLCON0: 0 bitplane, Color burst, ECSENA
 
	dc.w	$FFFF,$FFFE		; FINE DELLA COPPERLIST
 

*****************************************************************************
* Qui sono memorizzate le tiles dello sfondo
*****************************************************************************
	
TILES:
	incbin	"Tiles.raw"	

OMINO:
	incbin	"Omino.raw"	

NEMICO:
	incbin	"Nemico.raw"	

*****************************************************************************
* OMINO_MASK_FIXED: maschera fissa 16x16 per il cookie cut del BOB.
* Il BOB e' un quadrato pieno (no buchi interni), quindi la maschera e':
*   - prima word ($FFFF): 16 pixel "presenza BOB"
*   - seconda word ($0000): 16 pixel padding (zona "no BOB")
*   - per 16 righe
* Stessa maschera valida per TUTTI i frame e TUTTI i bitplane.
* Pitch maschera: 4 byte/riga -> BLTBMOD = 0.
*****************************************************************************
OMINO_MASK_FIXED:
	dc.w	$FFFF,$0000	; riga 0
	dc.w	$FFFF,$0000	; riga 1
	dc.w	$FFFF,$0000	; riga 2
	dc.w	$FFFF,$0000	; riga 3
	dc.w	$FFFF,$0000	; riga 4
	dc.w	$FFFF,$0000	; riga 5
	dc.w	$FFFF,$0000	; riga 6
	dc.w	$FFFF,$0000	; riga 7
	dc.w	$FFFF,$0000	; riga 8
	dc.w	$FFFF,$0000	; riga 9
	dc.w	$FFFF,$0000	; riga 10
	dc.w	$FFFF,$0000	; riga 11
	dc.w	$FFFF,$0000	; riga 12
	dc.w	$FFFF,$0000	; riga 13
	dc.w	$FFFF,$0000	; riga 14
	dc.w	$FFFF,$0000	; riga 15	
*****************************************************************************

	SECTION	PLANEVUOTO,BSS_C

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
BPSFONDO_A:
	ds.b	5*40*256		; bitplanes  

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
BPSFONDO_B:
	ds.b	5*40*256		; bitplanes  

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
SFONDOGRANDE:
	ds.b	5*SFONDO_PLANE_SIZE	; 5 plane * 48 byte/riga * 288 righe = 69120 byte


; Maschera dell'OMINO: 1 bitplane (10240 byte = 40*256) calcolata al boot
; come OR dei 5 bitplane dello spritesheet originale.
; Il blitter la usa come canale B per il cookie-cut nei BOB.
OMINO_MASK:
	ds.b	40*256			; 1 plane mask (stesso pitch di OMINO)

	SECTION	BulletSpr,data_c
	cnop	0,8				; allineamento sprite

; Sprite hardware del proiettile:
;   header (2 word) + dati (4 righe x 2 word) + terminator (2 word) = 12 word
; SPRPOS, SPRCTL vengono settate runtime; i dati graphici inizializzati al boot.
BulletSprite:
	dc.w	0,0				; SPRPOS, SPRCTL (runtime)
	dc.w	$3C00,$0000		; riga 0: 4 pixel centrali, plane 0=1, plane 1=0 -> colore 1
	dc.w	$7E00,$7E00		; riga 1: 6 pixel centrali, plane 0=1 plane 1=1 -> colore 3
	dc.w	$7E00,$7E00		; riga 2: idem
	dc.w	$3C00,$0000		; riga 3: 4 pixel centrali, colore 1
	dc.w	0,0				; terminator

	cnop	0,8
; Sprite vuoto per disattivare gli sprite non usati (SPR1..SPR7)
EmptySprite:
	dc.w	0,0				; SPRPOS, SPRCTL
	dc.w	0,0				; terminator

	SECTION	Entities,BSS
ENEMY_COUNT		EQU		4		; numero massimo di nemici

	EVEN
Player:
	ds.b	bob_Length		  		; alloca la struct player
Enemies:
	ds.b	bob_Length*ENEMY_COUNT	; arrey di nemici

	end

*****************************************************************************

