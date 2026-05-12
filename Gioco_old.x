*****************************************************************************
*                   MEGA GAME                                               *
*                                                                           *
*   Aggiungere omino BOB                                                    *
*   Muovere omino in tutte le direzioni                                     *
*   Condizionare lo scrolling alla posizine del bob                         *
*   Gestire collisioni                                                      *
*   Aggiungere effetti audio                                                *
*   Aggiungere musica                                                       *
*                                                                           *
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

XTiles		EQU	16
YTiles		EQU 16

MAPPA_COLS 	EQU	24
MAPPA_ROWS	EQU	18
BUFFER_COLS	EQU	22
BUFFER_ROWS	EQU	18
VIS_COLS	EQU	20
VIS_ROWS	EQU	16

TILEXMAX	EQU	MAPPA_COLS-VIS_COLS-2
TILEYMAX	EQU	MAPPA_ROWS-VIS_ROWS
;------------------------------------------------------------
; Costanti tasti freccia (identici ai rawkey Intuition)
;------------------------------------------------------------
RAWKEY_UP       EQU $4C
RAWKEY_DOWN     EQU $4D
RAWKEY_RIGHT    EQU $4E
RAWKEY_LEFT     EQU $4F

KEY_RELEASE_BIT EQU 7       ; bit 7 del keycode decodificato
*****************************************************************************
* VARIABILI
*****************************************************************************
ScrllX:		dc.w	0		; Movimento orizzontale +-1 
ScrllY:		dc.w	0		; Movimento verticale +-1
TileX		dc.w	1
TileY		dc.w	0
PixelOffX	dc.w	0
PixelOffY	dc.w	0
BufferOffX	dc.w	16
BufferOffY	dc.w	16

arrow_up:       DS.B 1
arrow_down:     DS.B 1
arrow_left:     DS.B 1
arrow_right:    DS.B 1

START:
*****************************************************************************
*	PUNTIAMO I BITPLANES DELLE TILES
*****************************************************************************

	MOVE.L	#BPSFONDO,D0		; in d0 l'indirizzo della memoria per la mappa,
	LEA	BitPlaneTiles,A1	; in a1 i puntatori della COPPERLIST
	MOVEQ	#3-1,D1			; numero di bitplanes -1 
.POINTBP:
	MOVE.W	D0,6(A1)		; copia la word BASSA dell'indirizzo del plane
	SWAP	D0			; scambia le 2 word di d0 (es: 1234 > 3412)
	MOVE.W	D0,2(A1)		; copia la word ALTA dell'indirizzo del plane
	SWAP	D0			; scambia le 2 word di d0 (es: 3412 > 1234)
	ADD.L	#40*256,D0		; + lunghezza bitplane -> prossimo bitplane
	ADDQ.w	#8,A1			; andiamo ai prossimi bplpointers nella COP
	DBRA	D1,.POINTBP		; Rifai D1 volte POINTBP (D1=num of bitplanes)

	LEA	$dff000,A6
	MOVE.W	#DMASET,$96(A6)		; DMACON - abilita dma
	MOVE.L	#CopperList,$80(A6)	; Puntiamo la nostra COP
	MOVE.W	d0,$88(A6)		; Facciamo partire la COP
	MOVE.W	#0,$1fc(A6)		; Disattiva l'AGA
	MOVE.W	#$c00,$106(A6)		; Disattiva l'AGA
	MOVE.W	#$11,$10c(A6)		; Disattiva l'AGA


	BSR.W	DisegnaSfondo		; Routine che disegna lo sfondo
.mainloop:
	MOVE.L	#$1ff00,D1		; bit per la selezione tramite AND
	MOVE.L	#$10800,D2		; linea da aspettare = $108

.Waity1:
	MOVE.L	4(A6),D0		; VPOSR e VHPOSR - $dff004/$dff006
	AND.L	D1,D0			; Seleziona solo i bit della pos. verticale
	CMP.L	D2,D0			; aspetta la linea $130 (304)
	BNE.S	.Waity1

*****************************************************************************
	BSR.W	LeggiJoystick		; Routine che legge il Joystick	
	BSR.W	ReadKeyboard	
	BSR.W	ControllaBordi		; Controllo dei bordi
	BSR.W	CopiaVideo			; Disegna lo schermo
;	BSR.W	CopiaCornice		; Disegna la cornice
;	BSR.S 	SxMouse

	BTST.B	#6,$bfe001		; tasto sx del mouse premuto?
	BNE.S	.mainloop
*****************************************************************************
	RTS

SxMouse:
.waitsxpress:
	BTST.B	#6,$bfe001		; tasto sx del mouse premuto?
	BNE.S	.waitsxpress
.waitsxrelease:
	BTST.B	#6,$bfe001		; tasto sx del mouse rilasciato?
	BEQ.S	.waitsxrelease
	RTS

Attesa:
	MOVE.L	#1000000,D7
.attesaloop:
	SUBQ.L	#1,D7
	BNE	.attesaloop
	RTS

*****************************************************************************
* LEGGI JOYSTICK 
*****************************************************************************
LeggiJoystick:
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
	RTS
;------------------------------------------------------------
; ReadKeyboard
;   Chiama questa routine nel tuo game loop.
;   Legge UN keycode dalla CIA-A (se disponibile),
;   decodifica e aggiorna ScrollX / ScrollY.
;
;   Registri modificati: d0, d1  (salvati/ripristinati)
;------------------------------------------------------------
ReadKeyboard:
        movem.l d0-d1,-(sp)

        ;--- Controlla se c'è un tasto in arrivo --------
        move.b  $BFED01,d0       ; lettura ICR azzera i flag
        btst    #3,d0           ; bit 3 = SP (keyboard data ready)
        beq     .no_key         ; nessun tasto → esci

        ;--- Leggi il keycode grezzo dalla CIA-A --------
        move.b  $BFEC01,d0       ; byte grezzo (bit invertiti, ruotato)

        ;--- Decodifica: NOT + ROR ----------------------
        ; Il keyboard controller Amiga invia i bit:
        ;   key[6],key[5]...key[0],release  (MSB first, active low)
        ; CIA-A li memorizza in SDR con bit 7 = primo bit ricevuto.
        ; NOT inverte la polarità, ROR #1 porta il release in bit 7.
        not.b   d0              ; step 1: inverti polarità
        ror.b   #1,d0           ; step 2: ruota → bit7=release, bit6-0=keycode

        ;--- Handshake obbligatorio ---------------------
        ; Dopo la lettura bisogna segnalare alla tastiera
        ; che il byte è stato ricevuto: SP in output per ~85μs,
        ; poi di nuovo in input. Senza questo la tastiera si blocca.
        move.b  $BFEE01,d1
        or.b    #$40,d1
        move.b  d1,$BFEE01       ; SP → modalità output (bit 6 = 1)

        move.w  #150,d1         ; ~85μs a 7.09 MHz ≈ 600 cicli
.ack:   dbf     d1,.ack         ; busy wait (3 cicli × 151 ≈ 453 cicli, ok)

        move.b  $BFEE01,d1
        and.b   #$BF,d1
        move.b  d1,$BFEE01       ; SP → modalità input (bit 6 = 0)

        ;--- Processa frecce ----------------------------
        bsr     ProcessArrowKey

.no_key:
        movem.l (sp)+,d0-d1
        rts

;------------------------------------------------------------
; ProcessArrowKey
;   Input : d0.b = keycode decodificato
;              bit7 = 0 pressione, 1 rilascio
;              bit6-0 = codice tasto
;   Output: aggiorna arrow_*, ScrollX, ScrollY
;   Registri modificati: d2 (salvato/ripristinato)
;------------------------------------------------------------
ProcessArrowKey:
        move.l  d2,-(sp)

        move.b  d0,d2
        and.b   #$7F,d2         ; isola codice (senza bit rilascio)

        btst    #KEY_RELEASE_BIT,d0
        bne     .release

;--- PRESSIONE: segna il tasto come premuto ---------------
.press:
        cmp.b   #RAWKEY_UP,d2
        bne     .p_down
        move.b  #1,arrow_up
        bra     .done

.p_down:
        cmp.b   #RAWKEY_DOWN,d2
        bne     .p_left
        move.b  #1,arrow_down
        bra     .done

.p_left:
        cmp.b   #RAWKEY_LEFT,d2
        bne     .p_right
        move.b  #1,arrow_left
        bra     .done

.p_right:
        cmp.b   #RAWKEY_RIGHT,d2
        bne     .done
        move.b  #1,arrow_right
        bra     .done

;--- RILASCIO: azzera flag + aggiorna ScrollX / ScrollY ---
.release:
        cmp.b   #RAWKEY_UP,d2
        bne     .r_down
        clr.b   arrow_up
        move.w  #-1,ScrllY         ; ↑ → ScrollY = -1
        bra     .done

.r_down:
        cmp.b   #RAWKEY_DOWN,d2
        bne     .r_left
        clr.b   arrow_down
        move.w  #1,ScrllY          ; ↓ → ScrollY = +1
        bra     .done

.r_left:
        cmp.b   #RAWKEY_LEFT,d2
        bne     .r_right
        clr.b   arrow_left
        move.w  #-1,ScrllX         ; ← → ScrollX = -1
        bra     .done

.r_right:
        cmp.b   #RAWKEY_RIGHT,d2
        bne     .done
        clr.b   arrow_right
        move.w  #1,ScrllX          ; → → ScrollX = +1

.done:
        move.l  (sp)+,d2
        rts

*****************************************************************************
* 		ROUTINE DI CONTROLLO DEI BORDI
* TILE BOUNDARY - SHIFT BUFFER
*****************************************************************************
ControllaBordi:
	MOVEM.L	D0-D1,-(SP)
	
	MOVE.W	PixelOffX,D0
	MOVE.W	PixelOffY,D1

	ADD.W	ScrllX,D0
	ADD.W	ScrllY,D1

	CMP.W	#16,D0			; check se X supera bordo dx tile
	BLT.S	.ControlloXMin
	MOVE.W	TileX,D2
	CMP.W	#TILEXMAX,D2
	BGE.S	.AzzeroXMax		; gia' a bordo mappa
	SUB.W	#16,D0
	ADD.W	#1,TileX
	BSR.W	ShiftSfondoSinistra
	BSR.W	AddColonnaDestra
	BRA.S	.ControlloY
.AzzeroXMax:
	MOVE.W	#0,ScrllX
	MOVEQ	#15,D0			; tieni al massimo pixel
	BRA.S	.ControlloY
.ControlloXMin:	
	TST.W	D0			; check se X supera bordo sx tile
	BGE.S	.ControlloY
	MOVE.W	TileX,D2
	CMP.W	#1,D2
	BLE.S	.AzzeroXMin
	ADD.W	#16,D0
	SUB.W	#1,TileX
	BSR.W	ShiftSfondoDestra
	BSR.W	AddColonnaSinistra
	BRA.S	.ControlloY
.AzzeroXMin:
	MOVE.W	#0,ScrllX
	MOVEQ	#0,D0
.ControlloY:	
	CMP.W 	#16,D1			; check se Y supera bordo inf tile
	BLT.S	.ControlloYMin
	MOVE.W	TileY,D2
	CMP.W	#TILEYMAX-1,D2
	BGE.S	.AzzeroYMax
	SUB.W	#16,D1
	ADD.W	#1,TileY
	BSR.W	ShiftSfondoAlto
	BSR.W	AddRigaBasso
	BRA.S	.FineControlli
.AzzeroYMax:
	MOVE.W	#0,ScrllY
	MOVEQ	#15,D1
	BRA.S	.FineControlli
.ControlloYMin:
	TST.W	D1			; check se Y supera bordo sup tile
	BGE.S	.FineControlli
	MOVE.W	TileY,D2
	CMP.W	#0,D2
	BLE.S	.AzzeroYMin
	ADD.W	#16,D1
	SUB.W	#1,TileY
	BSR.W	ShiftSfondoBasso
	BSR.W	AddRigaAlto
	BRA.S	.FineControlli
.AzzeroYMin:
	MOVE.W	#0,ScrllY
	MOVEQ	#0,D1
.FineControlli:
	MOVE.W	D0,PixelOffX
	MOVE.W	D1,PixelOffY
	MOVEM.L	(SP)+,D0-D1

	RTS

*****************************************************************************
* SHIFT SINISTRA
*****************************************************************************
ShiftSfondoSinistra:
	MOVEM.L	D4/A1-A2,-(SP)
	MOVE.L	#SFONDOGRANDE+2,A2	; ind. sorgente A
	MOVE.L  #SFONDOGRANDE,A1	; ind. destinazione D

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoop:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09f00000,$40(A6)	; 
	MOVE.W	#2,$64(A6)		; BLTAMOD 
	MOVE.W	#2,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(288<<6)+21,$58(A6)	; BLTSIZE  288x21 

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#288*44,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoop
	MOVEM.L	(SP)+,D4/A1-A2
	RTS

****************************************************************************
* SHIFT DESTRA
*****************************************************************************
ShiftSfondoDestra:
	MOVEM.L	D4/A1-A2,-(SP)
	MOVE.L	#SFONDOGRANDE+12668,A2	; ind. sorgente A
	MOVE.L  #SFONDOGRANDE+12670,A1	; ind. destinazione D

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoop:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09f00002,$40(A6)	; DESC mode
	MOVE.W	#2,$64(A6)		; BLTAMOD 
	MOVE.W	#2,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(288<<6)+21,$58(A6)	; BLTSIZE  288x21 

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#288*44,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoop
	MOVEM.L	(SP)+,D4/A1-A2

	RTS

****************************************************************************
* SHIFT ALTO
*****************************************************************************
ShiftSfondoAlto:
	MOVEM.L	D4-D5/A1-A2,-(SP)
	MOVE.L	#SFONDOGRANDE+16*44,A2	; ind. sorgente A
	MOVE.L  #SFONDOGRANDE,A1	; ind. destinazione D

	MOVEQ	#0,D5
	MOVE.W	PixelOffY,D5
	MULU.W	#44,D5
	ADD.L	D5,A2

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoop:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09f00000,$40(A6)	; 
	MOVE.W	#0,$64(A6)		; BLTAMOD 
	MOVE.W	#0,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(272<<6)+22,$58(A6)	; BLTSIZE  272x22 

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#288*44,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoop
	MOVEM.L	(SP)+,D4-D5/A1-A2

	RTS

****************************************************************************
* SHIFT BASSO
*****************************************************************************
ShiftSfondoBasso:
	MOVEM.L	D4-D5/A1-A2,-(SP)
	MOVE.L	#SFONDOGRANDE+11966,A2	; ind. sorgente A
	MOVE.L  #SFONDOGRANDE+12670,A1	; ind. destinazione D

	MOVEQ	#0,D5
	MOVE.W	PixelOffY,D5
	MULU.W	#44,D5
	ADD.L	D5,A2

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoop:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09f00002,$40(A6)	; DESC mode
	MOVE.W	#0,$64(A6)		; BLTAMOD 
	MOVE.W	#0,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(272<<6)+22,$58(A6)	; BLTSIZE  272x22 

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#288*44,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoop
	MOVEM.L	(SP)+,D4-D5/A1-A2

	RTS

*****************************************************************************
* AGGI COLONNA DESTRA
* Blitta in SFONDOGRANDE (colonna 21, byte offset 42) le 18 tile
* dalla colonna MAPPA[TileX+21][TileY .. TileY+17]
*****************************************************************************
AddColonnaDestra:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	; Punta alla prima tile della colonna nella MAPPA
	MOVE.W	TileX,D0
	ADDI.W	#21,D0			; colonna visibile più a destra
	MOVE.W	TileY,D1
	MULU.W	#MAPPA_COLS*2,D1	; offset riga in MAPPA (in byte)
	ADD.W	D0,D0			; offset colonna in byte
	LEA	MAPPA,A0
	ADDA.W	D1,A0
	ADDA.W	D0,A0			; A0 = MAPPA[TileX+21][TileY]

	; Destinazione: colonna 21 = offset 42 nel buffer
	MOVE.L	#SFONDOGRANDE+42,A3

	MOVEQ	#BUFFER_ROWS-1,D7		; 18 tile per colonna
.loopTile:
	MOVEQ	#0,D3
	MOVE.W	(A0),D3			; numero tile
	ADDA.L	#MAPPA_COLS*2,A0	; riga successiva nella MAPPA

	; Calcola indirizzo sorgente in TILES
	MOVE.L	D3,D4
	DIVU.W	#20,D4			; D4.w = riga tile, D4 resto = col tile
	MOVE.W	D4,D5
	MULU.W	#16*40,D5		; offset riga in TILES
	SWAP	D4
	MOVE.W	D4,D6
	MULU.W	#2,D6			; offset colonna in TILES
	MOVE.L	#TILES,A2
	ADD.L	D5,A2
	ADD.L	D6,A2			; A2 = TILES[riga][col] piano 0

	MOVE.L	A3,A1			; A1 = dest in SFONDOGRANDE

	MOVEQ	#3-1,D4
.loopPlane:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.L	#$09F00000,$40(A6)
	MOVE.W	#38,$64(A6)		; BLTAMOD = 40-2 = 38 (tile 16px=1 word)
	MOVE.W	#42,$66(A6)		; BLTDMOD = 44-2 = 42
	BSR.W	AspettaBlitter
	MOVE.L	A2,$50(A6)
	MOVE.L	A1,$54(A6)
	MOVE.W	#(16<<6)+1,$58(A6)	; 16 righe × 1 word
	ADD.L	#256*40,A2		; prossimo piano in TILES
	ADD.L	#288*44,A1		; prossimo piano in SFONDOGRANDE
	DBRA	D4,.loopPlane

	ADDA.L	#16*44,A3		; scende di 1 tile nel buffer (16 righe)
	DBRA	D7,.loopTile

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

*****************************************************************************
* AGGI COLONNA SINISTRA
* Blitta in SFONDOGRANDE (colonna 0, byte offset 0) le 18 tile
* dalla colonna MAPPA[TileX][TileY .. TileY+17]
*****************************************************************************
AddColonnaSinistra:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	MOVE.W	TileX,D0		; colonna: TileX già decrementato
	MOVE.W	TileY,D1
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0
	LEA	MAPPA,A0
	ADDA.W	D1,A0
	ADDA.W	D0,A0

	MOVE.L	#SFONDOGRANDE,A3	; colonna 0 = inizio buffer

	MOVEQ	#BUFFER_ROWS-1,D7
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
	MOVEQ	#3-1,D4
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
* AGGI RIGA BASSO
* Blitta in SFONDOGRANDE (riga tile 17 = pixel 272, offset 272*44=11968)
* le 22 tile dalla riga MAPPA[TileX..TileX+21][TileY+17]
*****************************************************************************
AddRigaBasso:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	MOVE.W	TileY,D1
	ADDI.W	#17,D1			; riga più in basso visibile
	MOVE.W	TileX,D0
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0
	LEA	MAPPA,A0
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
	MOVEQ	#3-1,D4
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

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

*****************************************************************************
* AGGI RIGA ALTO
* Blitta in SFONDOGRANDE (riga tile 0 = pixel 0, offset 0) le 22 tile
* dalla riga MAPPA[TileX..TileX+21][TileY]
*****************************************************************************
AddRigaAlto:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	MOVE.W	TileY,D1		; TileY già decrementato
	MOVE.W	TileX,D0
	MULU.W	#MAPPA_COLS*2,D1
	ADD.W	D0,D0
	LEA	MAPPA,A0
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
	MOVEQ	#3-1,D4
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
	MOVEM.L	D1-D6/A1-A2,-(SP)

	LEA		MAPPA,A0		; Salvo in A0 il punt. alla mappa
	MOVE.W	TileX,D0        ; colonna di partenza
	ADD.W	D0,D0           ; *2 perché ogni tile è una word
	ADDA.W	D0,A0           ; salta le colonne a sinistra
	MOVE.L	#SFONDOGRANDE,PuntaSfondoGr
	MOVEQ	#BUFFER_COLS-1,D1		; d1 = numero colonne
	MOVEQ	#BUFFER_ROWS-1,D2		; d2 = numero righe
.CicloTile:
	MOVEQ	#0,D3			; Pulisci d3
	MOVE.W	(A0)+,D3		; d3 = numero della tile da stampare


	MOVE.L	D3,D5
	DIVU	#20,D5
	MOVE.W	D5,D6
	MULU	#16*40,D6
	SWAP	D5
	MOVE.W	D5,D7
	MULU	#2,D7
	MOVE.L	D6,A2
	ADD.L	D7,A2

	ADD.L	#TILES,A2		; TROVA LA TILE DESIDERATA

	MOVE.L	PuntaSfondoGr,A1	; destinazione in a1
	ADDQ.L	#2,PuntaSfondoGr 	; avanziamo di 16 bit (PROSSIMA TILE)

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoopSfondo:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09F00000,$40(A6)	; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)		; BLTAMOD 
	MOVE.W	#42,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(16*64)+1,$58(A6)	; BLTSIZE

	ADD.L	#256*40,A2		; prossimo plane sorgente
	ADD.L	#288*44,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoopSfondo
	DBRA	D1,.CicloTile
	ADD.L	#44*15,PuntaSfondoGr	; ANDIAMO A CAPO
	MOVEQ	#BUFFER_COLS-1,D1		; resetto il contatore delle colonne
	ADD.W	#(MAPPA_COLS-BUFFER_COLS)*2,A0
	DBRA	D2,.CicloTile
.FineMappa:

	MOVEM.L	(SP)+,D1-D6/A1-A2

	RTS

*****************************************************************************
*              ROUTINE DI COPIA DELLA PARTE VISIBILE SUI BITPLANE
*****************************************************************************
CopiaVideo:
	MOVEM.L	D3-D7/A1-A2,-(SP)

	MOVE.L	#SFONDOGRANDE,A2	; ind. sorgente A
	MOVE.L  #BPSFONDO,A1		; ind. destinazione D

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoopVideo:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09F00000,$40(A6)	; BLTCON0/1 - copia normale
	MOVE.W	#4,$64(A6)		; BLTAMOD 
	MOVE.W	#0,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(256<<6)+20,$58(A6)		; BLTSIZE  256<<6 + 20

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#256*40,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoopVideo

	MOVEM.L	(SP)+,D3-D7/A1-A2

	RTS
		
*****************************************************************************
*              ROUTINE DI STAMPA SUI BITPLANE
*****************************************************************************
CopiaVideoBackUp:
	MOVEM.L	D3-D7/A1-A2,-(SP)

	MOVE.L	#SFONDOGRANDE+2,A2	; ind. sorgente A
	MOVE.L  #BPSFONDO,A1		; ind. destinazione D
	
    ; Calcola offset Y nel buffer
	MOVEQ	#0,D5
	MOVE.W	PixelOffY,D5
	MULU.W	#44,D5
	ADD.L	D5,A2

	MOVEQ	#0,D3
	MOVE.W	PixelOffX,D3
	BEQ.S	.noxscroll
	ADDQ.L	#2,A2
	MOVE.W	#16,D3
	SUB.W	PixelOffX,D3
.noxscroll
	LSL.W	#4,D3
	SWAP	D3
	LSL.L	#8,D3
	OR.L	#$09f00000,D3

	MOVEQ	#3-1,D4			; Numero blittate = 3 per 3 planes
.BlittaLoopVideo:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
					; BLTAFWM = $ffff - passa tutto
					; BLTALWM = $ffff = passa tutto
	MOVE.L	D3,$40(A6)		; BLTCON0/1 - copia normale
	MOVE.W	#4,$64(A6)		; BLTAMOD 
	MOVE.W	#0,$66(A6)		; BLTDMOD 

	BSR.W	AspettaBlitter

	MOVE.L	A2,$50(A6)		; BLTAPT
	MOVE.L	A1,$54(A6)		; BLTDPT
	MOVE.W	#(256<<6)+20,$58(A6)		; BLTSIZE  256<<6 + 20

	ADD.L	#288*44,A2		; prossimo plane sorgente
	ADD.L	#256*40,A1		; prossimo plane destinazione

	DBRA	D4,.BlittaLoopVideo

	MOVEM.L	(SP)+,D3-D7/A1-A2

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

*****************************************************************************
* Disegno la mappa con le tiles 
* Per il momento la disegnamo come uno schermo 20*16 
* ma poi sar� da ingrandire
*****************************************************************************

MAPPA:
;		 1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22
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
	dc.w	 0, 3, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 5, 0	;18
	

*****************************************************************************
* VARIABILI 
*****************************************************************************
PuntaSfondoGr:
	dc.l	SFONDOGRANDE
xmappa:
	dc.b	0
ymappa:
	dc.b	0
	
*****************************************************************************
*
* 		COPPER
*
*****************************************************************************	
		
	Section	ChipStuff,data_c

CopperList:
	dc.w	$0100,%0011001000000000	; BPLCON0
		     ; 5432109876543210	
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
;	dc.w 	$ec,$0000,$ee,$0000	;quarto  bitplane - BPL3PT

Sprites:
	dc.w	$120,$0000,$122,$0000,$124,$0000,$126,$0000,$128,$0000
	dc.w	$12a,$0000,$12c,$0000,$12e,$0000,$130,$0000,$132,$0000
	dc.w	$134,$0000,$136,$0000,$138,$0000,$13a,$0000,$13c,$0000
	dc.w	$13e,$0000

PALETTE:
	dc.w 	$0180,$0000,$0182,$0fff,$0184,$0040,$0186,$0070
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880

	dc.w	$FFFF,$FFFE		; FINE DELLA COPPERLIST

*****************************************************************************
* Qui sono memorizzate le tiles dello sfondo
*****************************************************************************
	
TILES:
	incbin	"Tiles.raw"	
	
*****************************************************************************

	SECTION	PLANEVUOTO,BSS_C

BPSFONDO:
	ds.b	3*40*256		; bitplanes  
SFONDOGRANDE:
	ds.b	3*44*288		; mappa pi� grande
CORNICEVERTICALE:
	ds.b    3*2*256			; cornice verticale
CORNICESUPERIORE:
	ds.b    3*40*16			; cornice superiore
CORNICEINFERIORE:
	ds.b    3*40*16			; cornice inferiore

	end

*****************************************************************************

