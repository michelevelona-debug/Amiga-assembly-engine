****************************************************************************
*				   MEGA GAME												*
*																			*
*   Inserire logica di gioco (PF, punti, game over)							*
*																			*
*****************************************************************************

	SECTION	MegaGame,CODE

	include	"title.i"			; Costanti title screen (TITLE_WIDTH, ...)

*****************************************************************************
	include	"Startup2.i"		; Startup completo AGA + VBR + cache clear
*****************************************************************************
; Con DMASET decidiamo quali canali DMA aprire e quali chiudere

			;5432109876543210
DMASET	EQU	%1000001111100000	; bltr, copper, bitplane, SPRITE ON
;DMASET	EQU	%1000001111100000	; con SPRITE DMA

*****************************************************************************
* COSTANTI
*****************************************************************************
NUM_PLANES			EQU		6				; numero di bitplane (5 + 1 per EHB notte)
PLANE_SIZE      	EQU     40*256          ; 10240 byte = un singolo bitplane
SFONDO_PITCH		EQU		48				; pitch riga di SFONDOGRANDE in byte
											; (era 44, ora 48 per allineamento AGA FMODE=3,
											; multiplo di 8). Larghezza utile = 22 word = 44 byte
											; (= 352 pixel come prima); i 4 byte extra
											; (= ultimi 32 pixel di ogni riga) sono inutilizzati.
BPSF_PITCH			EQU		48
SFONDO_HEIGHT		EQU		288				; altezza SFONDOGRANDE in righe
SFONDO_PLANE_SIZE 	EQU		SFONDO_PITCH*SFONDO_HEIGHT	; 13824 byte/plane

XTiles				EQU		16
YTiles				EQU 	16	

MAPPA_COLS 			EQU		24
MAPPA_ROWS			EQU		22
BUFFER_COLS			EQU		22
BUFFER_ROWS			EQU		18
VIS_COLS			EQU		20
VIS_ROWS			EQU		16

; TILEXMAX / TILEYMAX = numero massimo che TileX/TileY puo' raggiungere.
; Il buffer carica MAPPA[TileY..TileY+BUFFER_ROWS-1][TileX..TileX+BUFFER_COLS-1],
; quindi TileX+BUFFER_COLS-1 <= MAPPA_COLS-1  =>  TileX <= MAPPA_COLS-BUFFER_COLS.
; Con mappa 18x24 e buffer 18x22 => TILEXMAX=2, TILEYMAX=0 (no scroll Y di tile).
; Per abilitare lo scroll Y di tile: estendi MAPPA a >=20 righe e aggiorna MAPPA_ROWS.

TILEXMAX			EQU		MAPPA_COLS-BUFFER_COLS
TILEYMAX			EQU		MAPPA_ROWS-BUFFER_ROWS
PLAYER_MAX_X    	EQU		(MAPPA_COLS*16)-16-32   ; 344 (bob_X max 288 = 320-32 viewport)
PLAYER_MAX_Y    	EQU		(MAPPA_ROWS*16)-16-32   ; 304 (bob_Y max 240 = 256-16 viewport)

; --- Fisica platform (visto di lato) ---
GRAVITY			EQU		1		; px/frame aggiunti a PlayerVelY (accelerazione di gravita')
MAX_FALL		EQU		8		; velocita' di caduta massima (terminale)
JUMP_VEL		EQU		-8		; velocita' iniziale del salto (negativa = verso l'alto)
CAM_STEP_Y		EQU		8		; passo scroll verticale camera (px/frame, DEVE dividere 16: 1/2/4/8)
CAM_DEADZONE_Y	EQU		8		; tolleranza verticale camera (>= CAM_STEP_Y per evitare oscillazione)

;------------------------------------------------------------
; Costanti tasti freccia (identici ai rawkey Intuition)
;------------------------------------------------------------
RAWKEY_UP			EQU 	$4C
RAWKEY_DOWN			EQU 	$4D
RAWKEY_RIGHT		EQU 	$4E
RAWKEY_LEFT		 	EQU 	$4F
RAWKEY_SPACE		EQU 	$40
RAWKEY_N			EQU 	$36			; rawkey del tasto N (toggle giorno/notte)
RAWKEY_M			EQU 	$37			; rawkey del tasto M (toggle musica)
RAWKEY_G			EQU 	$24			; rawkey del tasto G (toggle gravita' / 8-direzioni)

KEY_RELEASE_BIT 	EQU 	7	   		; bit 7 del keycode decodificato
ANIM_DELAY			EQU 	3

HEALTHBAR_COLOR		EQU		14			; colore 14 = rosso/rosa nella palette
HEALTHBAR_YOFFSET 	EQU 	3			; pixel sopra il BOB
INVULN_FRAMES		EQU		50			; frame di invulnerabilita' dopo un hit

; ----- Bullet (proiettile sprite hardware) -----
BULLET_SPEED		EQU		4			; pixel per frame del proiettile
BULLET_TTLC			EQU		60			; frame di vita massima
BULLET_COOLDOWNC	EQU		10			; frame di cooldown tra due spari
BULLET_DAMAGE		EQU		2			; danno inflitto al nemico
BULLET_HEIGHT		EQU		4			; altezza dello sprite proiettile

; ----- Illuminazione (EHB) -----
TILE_LUCE			EQU		19			; numero tile = sorgente di luce
RAGGIO_LUCE			EQU		64			; raggio in pixel della luce (tile 19)

; Maschera statica del disco di luce per il blit del cerchio (vedi
; BuildLightMask / DisegnaCerchioLuceBlitter). Larga 8 word (128px) + 1 word
; di "spillover" per lo shift orizzontale = 9 word. Alta 128 righe (dy -64..63).
; Bit=1 dentro il cerchio. Costruita una volta al boot riusando LightHalfWidthTable.
LIGHT_MASK_W		EQU		9			; word per riga (8 disco + 1 per lo shift)
LIGHT_MASK_H		EQU		128			; righe
LIGHT_MASK_STRIDE	EQU		LIGHT_MASK_W*2	; 18 byte per riga

; ----- DIAGNOSTICA SFARFALLIO (mettere a 1 per testare) -----
; Se =1, UpdateDarkPlane disegna il cerchio in posizione FISSA al centro
; schermo, ignorando camera/scan. Serve a capire la causa del flicker:
;   - flicker SPARISCE  -> la causa e' l'instabilita' di cx/cy (camera/scan)
;   - flicker RESTA      -> la causa e' display/DMA/double-buffer (non il contenuto)
DBG_FIXLIGHT		EQU		0

; Righe di "padding" extra sotto le 256 visibili nel dark plane: assorbono
; un eventuale over-fetch di 1+ righe in fondo, evitando che la DMA legga
; nel buffer adiacente (contenuto diverso tra A e B -> sfarfallio in basso).
DARK_PAD_ROWS		EQU		16
DARK_ROWS			EQU		256+DARK_PAD_ROWS

; Righe di "padding" tra un piano e l'altro di BPSFONDO. Con FMODE=3 (fetch
; AGA a 64 bit) il prefetch in fondo allo schermo legge righe oltre 255 di
; ciascun piano. Con i 5 piani contigui (passo = 40*256), il piano N pesca
; nei dati del piano N+1 -> mosaico "a trattini" sull'ultima riga, visibile
; solo dove la luce notturna lo illumina (assente in OCS perche' senza
; FMODE non c'e' prefetch). Distanziando i piani con BG_PAD_ROWS righe
; blank (mai scritte da CopiaVideo/BOB, restano a 0 = colore 0 del bordo),
; il prefetch legge righe nere consistenti invece dei dati del piano dopo.
; 16 righe coprono anche eventuali BOB sul fondo che debordano oltre 255.
BG_PAD_ROWS			EQU		16
BG_PLANE_STRIDE		EQU		BPSF_PITCH*(256+BG_PAD_ROWS)	; 13056 byte = passo di piano BPSFONDO (pitch 48)

; Numero di righe in fondo allo schermo da NON disegnare (border invisibile).
;
; STORIA: era un cerotto (=12) contro lo sfarfallio AGA sulle ultime ~12
; scanline. Causa vera individuata: il fill del dark plane su CPU (~2.5ms di
; MOVE.L) ritardava i blit dei BOB, che finivano mentre il pennello era gia'
; sul fondo schermo -> contesa DMA blitter/bitplane -> sfarfallio. Spostato il
; fill sul blitter (vedi UpdateDarkPlane STEP 1), tutto finisce ~2ms prima e
; la contesa sparisce. Quindi ora dovrebbe bastare 0 (schermo pieno 256 righe).
;
; >>> Se reimpostando 0 lo sfarfallio NON torna, lascialo a 0 (recuperi 12px).
; >>> Se dovesse tornare un filo, alza al minimo che lo elimina (prova 4, 8...).
;
; Muove insieme: BLTSIZE in CopiaVideo, cull cerchio in DisegnaCerchioLuce,
; DIWSTOP nella copperlist di gioco.
CUT_BOTTOM_ROWS		EQU		0

FaloAnimSpeed		EQU		5			; ogni N frame avanza animazione
ENEMY_COUNT			EQU		4			; numero massimo di nemici

; PT Player: modalita' standard (VBLANK_MUSIC=0, default).
; Timer A gestisce il tick musicale automaticamente via interrupt CIA-B.
; Timer B gestisce il DMA delay automaticamente.
; Gli SFX funzionano sempre, anche a musica spenta.

; ----- Sound effects (PT Player _mt_playfx) -----
; sfx_per: period Paula. Valori indicativi:
;   124  -> ~28.8 kHz (sample HQ)
;   214  -> ~16.6 kHz
;   280  -> ~12.7 kHz (default tutti gli SFX qui)
;   428  -> ~8.3  kHz (C-3 PT standard)
; sfx_vol: 0..64 (64 = max). Indipendente dal master volume musica.
; sfx_cha: -1 = scelta automatica del canale meno usato.
; sfx_pri: 1..127. Priorita' piu' alta vince se il canale e' occupato.
SFX_PER_DEFAULT			EQU		280
SFX_VOL_DEFAULT			EQU		64
SFX_PRI_SPARO			EQU		64
SFX_PRI_HITENEMY		EQU		90
SFX_PRI_HITPLAYER		EQU		100
SFX_PRI_DEATH			EQU		110

WaitDisk EQU 30 ; 50-150 al salvataggio (secondo i casi)
START:
*****************************************************************************
* TITLE SCREEN
*   Setup AGA + PT Player, avvia musica, mostra title.raw, attende SPACE
*   o tasto fire del joystick. Poi ferma la musica e procede col gioco.
*****************************************************************************
	LEA		$DFF000,A6
	MOVE.W	#$3,$1fc(A6)			; FMODE = $03 (AGA fetch 64-bit)
	MOVE.W	#$0c00,$106(A6)			; BPLCON3 default
	MOVE.W	#$0000,$10c(A6)			; BPLCON4 default

	; ----- PT Player: installa interrupt CIA-B -----
	SUBA.L	A0,A0					; VectorBase = 0 (68000)
	MOVEQ	#1,D0					; PAL flag = 1
	JSR		_mt_install
	MOVE.W	#$E000,$DFF09A			; abilita INT level 6 (EXTER) + master enable
	MOVE.W	#$8200,$96(A6)			; DMACON: master DMA on (per audio Paula)

	; Riserva 3 canali alla musica: gli SFX (sfx_cha=-1) potranno usare
	; solo il 4o canale. Evita che uno sparo "buchi" un canale musicale.
	MOVE.B	#3,_mt_MusicChannels

	; ----- Carica modulo e avvia musica -----
	LEA		ANTIRIAD_MOD,A0
	SUBA.L	A1,A1					; campioni embedded
	MOVEQ	#0,D0					; SongPos = 0
	JSR		_mt_init
	MOVE.B	#1,_mt_Enable			; play

	; ----- Mostra title screen e attende input -----
	BSR.W	ShowTitle				; setup 8 BPL AGA + palette + copper
	BSR.W	WaitTitleInput			; busy-loop fino a SPACE o fire

	; ----- Click: ferma la musica della title -----
	MOVE.B	#0,_mt_Enable
	; _mt_Enable=0 mette in pausa il PT Player, ma Paula continua a
	; ripetere in loop l'ultimo sample caricato (= ultima nota infinita).
	; Azzero i 4 volumi audio: in pausa il PT Player non li sovrascrive,
	; quando la musica viene riattivata (tasto M) il player ricarica
	; automaticamente i volumi al primo tick.
	MOVE.W	#0,$a8(A6)				; AUD0VOL = 0
	MOVE.W	#0,$b8(A6)				; AUD1VOL = 0
	MOVE.W	#0,$c8(A6)				; AUD2VOL = 0
	MOVE.W	#0,$d8(A6)				; AUD3VOL = 0

	; ----- Spegne BPL+COP DMA prima di riconfigurare per il gioco -----
	; (audio DMA preservato per il restart musica successivo)
	MOVE.W	#$0180,$96(A6)			; CLR BPLEN+COPEN

*****************************************************************************
*	PUNTIAMO I BITPLANES DELLE TILES
*****************************************************************************

	MOVE.L	CurrentDisplay,D0		; in D0 l'indirizzo della memoria per la mappa,
	MOVE.L	#DARKPLANE_A,D2			; dark plane iniziale = A

	BSR.W	AggiornaCopperBPL 		; aggiorna i puntatori bitplane nella copperlist

	BSR.W	AggiornaCopperSPR 		; aggiorna anche i puntatori sprite nella copperlist

	LEA		$dff000,A6
	MOVE.W	#DMASET,$96(A6)			; DMACON - abilita dma
	MOVE.L	#CopperList,$80(A6)		; Puntiamo la nostra COP
	MOVE.W	D0,$88(A6)				; Facciamo partire la COP

	; Ripristina FMODE/BPLCON3/BPLCON4 per il gioco (la title li aveva
	; impostati ma per sicurezza li riscriviamo, in caso siano cambiati).
	MOVE.W	#$3,$1fc(A6)			; FMODE = $03 (fetch 64-bit AGA)
	MOVE.W	#$0c00,$106(A6)			; BPLCON3 default
	MOVE.W	#$0011,$10c(A6)			; BPLCON4: BPLAM=0, ESPRM=$1, OSPRM=$1 (entrambi sprite a COLOR17-19 arancione)
;	MOVE.W	#$1000,$10c(A6)			; BPLCON4: ESPRM=$10 (SPR0 falo' a COLOR17-19 arancione), OSPRM/BPLAM=$00
	; ----- DEBUG: scrivi SPR0PT direttamente nei registri custom -----
	; In caso la copperlist non riesca ad aggiornare i puntatori sprite,
	; settiamo manualmente SPR0PT su FuocoFrame_0 e SPR1..7 su EmptySprite.
	MOVE.L	#FuocoFrame_0,$120(A6)	; SPR0PT (scrittura long su $120 = high+low)
	MOVE.L	#EmptySprite,$124(A6)	; SPR1PT
	MOVE.L	#EmptySprite,$128(A6)	; SPR2PT
	MOVE.L	#EmptySprite,$12c(A6)	; SPR3PT
	MOVE.L	#EmptySprite,$130(A6)	; SPR4PT
	MOVE.L	#EmptySprite,$134(A6)	; SPR5PT
	MOVE.L	#EmptySprite,$138(A6)	; SPR6PT
	MOVE.L	#EmptySprite,$13c(A6)	; SPR7PT

	BSR.W   InitPlayer				; <-- INIZIALIZZA IL PLAYER
	BSR.W   InitEnemies				; <-- INIZIALIZZA I NEMICI
	BSR.W	BuildOminoMask			; Genera la maschera dell'OMINO al boot

	; ----- Musica: resta in pausa dopo il click sulla title.
	; L'utente la riattiva con M (toggle MusicOn -> _mt_Enable via GestisciMusica).
	; MusicOn=0/MusicOnPrev=0 -> nessun cambio rilevato, _mt_Enable resta 0.
	MOVE.B	#0,MusicOn
	MOVE.B	#0,MusicOnPrev

	BSR.W	DisegnaSfondo			; Routine che disegna lo sfondo

	; Pre-render su entrambi i buffer per evitare il primo frame nero
	BSR.W	CopiaVideo				; copia su CurrentDraw = BPSFONDO_B
	BSR.W	AspettaBlitter
	BSR.W	SwapBuffers				; ora display = B, draw = A
	BSR.W	CopiaVideo				; copia anche su A
	; (al primo giro del loop il display è B, e disegnamo su A — entrambi pronti)

	BSR.W	BuildLightMask			; costruisce una volta la maschera del disco di luce
.mainloop:
*****************************************************************************
	BSR.W	ReadKeyboard			; Routine che legge la tastiera
	BSR.W	LeggiJoystick			; Routine che legge il Joystick	
	BSR.W	GateScrollByCenter		; Se bob NON al centro, azzera ScrllX/Y
	BSR.W	UpdatePlayerPhysics		; gravita' + salto -> IntentY
	BSR.W	UpdatePlayerWorldPos	; Aggiorna PlayerWorldX/Y (Fase 2)
	BSR.W	ComputeCameraFollowY	; camera insegue il player in verticale -> ScrllY
	BSR.W	ControllaBordi			; Controllo dei bordi
	BSR.W	GestisciShiftPixel		; Esegue lo scrolling fine
	BSR.W	AggiornaTiles			; Gestisce l'agggiunta di tiles dalla mappa
									; al buffer	
	BSR.W	UpdateDarkPlane			; fill dark plane + lampioni (sempre ogni frame)
	; NOTA: il dark plane e' gia' double-buffered correttamente.
	; UpdateDarkPlane scrive SOLO CurrentDarkDraw (mai il buffer in display);
	; SwapBuffers alterna A/B e aggiorna BPL5PT. Nessuna copia extra serve qui:
	; copiare in CurrentDarkDisplay = scrivere nel piano EHB mentre il pennello
	; lo legge -> tearing visibile sul bordo del cerchio (lo "sfarfallio in basso").

	BSR.W	AnimaFalo				; anima sprite falò e lo posiziona su tile 19
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
	BSR.W	GestisciMusica			; start/stop + tick PT Player (chiama _mt_music ogni VBL)
	BSR.S	SwapBuffers				; aggiorna BPL pointers in copperlist + scambia variabili

	BTST.B	#6,$bfe001				; tasto sx del mouse premuto?
	BNE.S	.mainloop

	; ----- Cleanup PT Player prima di tornare all'OS -----
	LEA		$DFF000,A6
	JSR		_mt_end					; ferma replay + azzera canali audio
	JSR		_mt_remove				; rimuove handler CIA-B, ripristina timer
	RTS
*****************************************************************************
* ROUTINE DI SWAP DEL BUFFER
*****************************************************************************
SwapBuffers:
	MOVEM.L D0-D2,-(SP)
; Scambia CurrentDisplay e CurrentDraw
	MOVE.L  CurrentDisplay,D0
	MOVE.L  CurrentDraw,D1
	MOVE.L  D1,CurrentDisplay
	MOVE.L  D0,CurrentDraw

; Scambia anche CurrentDarkDisplay e CurrentDarkDraw
	MOVE.L  CurrentDarkDisplay,D0
	MOVE.L  CurrentDarkDraw,D2
	MOVE.L  D2,CurrentDarkDisplay
	MOVE.L  D0,CurrentDarkDraw
	; D2 = nuovo CurrentDarkDisplay (= il valore vecchio di CurrentDarkDraw)
	; D1 = nuovo CurrentDisplay

; Aggiorna copperlist con i nuovi puntatori
	MOVE.L  D1,D0
	BSR.S   AggiornaCopperBPL

	movem.l (SP)+,D0-D2
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
* AGGIORNA I BPL POINTER NELLA COPPERLIST
* INPUT:  D0 = indirizzo del primo bitplane
* OUTPUT: 5 BPL pointer aggiornati a partire da BitPlaneTiles
* DISTRUGGE: D0, A1 (e usa internamente D1)
*****************************************************************************
AggiornaCopperBPL:
	MOVEM.L D1/A1,-(SP)
	LEA	 BitPlaneTiles,A1

	; --- Primi 5 plane: standard BPSFONDO ---
	MOVEQ   #5-1,D1
.loop:
	MOVE.W	D0,6(A1)			; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)			; word alta
	SWAP	D0
	ADD.L	#BG_PLANE_STRIDE,D0	; prossimo bitplane (passo con padding anti over-fetch FMODE=3)
	ADDQ.W	#8,A1				; prossimi 4 dc.w nella copperlist
	DBRA	D1,.loop

	; --- 6° plane: DARK plane (gestito separatamente) ---
	; A1 punta ora a $f4,0,$f6,0 (BPL5PT entry)
	MOVE.W	D2,6(A1)			; BPL5PTL word bassa
	SWAP	D2
	MOVE.W	D2,2(A1)			; BPL5PTH word alta
	
	MOVEM.L	(SP)+,D1/A1
	RTS 
*****************************************************************************
* GestisciMusica
*   Chiamata ogni frame nel main loop.
*   In modalita' standard Timer-A gestisce il tick automaticamente:
*   qui ci limitiamo a propagare MusicOn -> _mt_Enable.
*   - MusicOn=1 -> _mt_Enable=1: Timer-A chiama il player automaticamente.
*   - MusicOn=0 -> _mt_Enable=0: Timer-A chiama solo mt_sfxonly (SFX ok).
*****************************************************************************
GestisciMusica:
	MOVEM.L	D0/A6,-(SP)

	MOVE.B	MusicOn,D0
	CMP.B	MusicOnPrev,D0
	BEQ.S	.done
	MOVE.B	D0,MusicOnPrev
	MOVE.B	D0,_mt_Enable		; 1 = play, 0 = pausa (SFX restano attivi)

.done:
	MOVEM.L	(SP)+,D0/A6
	RTS

*****************************************************************************
* AggiornaCopperSPR
*   Aggiorna gli sprite pointer nella copperlist (entry "Sprites").
*   - SPR0 -> frame corrente del falò (FuocoFrame_N, secondo FaloAnimFrame)
*   - SPR1..SPR7 -> EmptySprite (= disattivati)
* DISTRUGGE: D0/D1/A0/A1 (preserva tramite stack)
*****************************************************************************
AggiornaCopperSPR:
	MOVEM.L D0-D1/A0-A1,-(SP)

	; --- SPR0: punta al frame corrente del falò ---
	LEA		FaloFrameTable,A0
	MOVE.W	FaloAnimFrame,D0
	ANDI.W	#7,D0					; sicurezza: 0..7
	LSL.W	#2,D0					; *4 (long per entry)
	MOVE.L	(A0,D0.W),D0			; D0 = indirizzo FuocoFrame_N
	LEA		Sprites,A1
	; SPR0PT: i registri sono (reg_high, val_high, reg_low, val_low)
	; A1+2 = val_high (parte alta), A1+6 = val_low (parte bassa)
	MOVE.W	D0,6(A1)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)				; word alta

	; --- SPR1..SPR7: tutti puntano a EmptySprite ---
	MOVE.L	#EmptySprite,D0
	LEA		Sprites+8,A1			; SPR1PT entry
	MOVEQ	#7-1,D1					; 7 sprite da disattivare
.loop:
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	SWAP	D0
	ADDQ.W	#8,A1					; prossima entry sprite nella copperlist
	DBRA	D1,.loop

	MOVEM.L	(SP)+,D0-D1/A0-A1
	RTS 

*****************************************************************************
* FaloFrameTable
*   Indirizzi dei 6 frame del falò (per indicizzazione veloce).
*****************************************************************************
FaloFrameTable:
	dc.l	FuocoFrame_0
	dc.l	FuocoFrame_1
	dc.l	FuocoFrame_2
	dc.l	FuocoFrame_3
	dc.l	FuocoFrame_4
	dc.l	FuocoFrame_5
	dc.l	FuocoFrame_0			; padding per ANDI #7 sicurezza
	dc.l	FuocoFrame_0

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
	MOVE.W	#0,UpNow	; azzero lo stato del tasto salto per questo frame
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
	BEQ.S	.NOALTO		; se no, controlla giu'
	MOVE.W	#1,UpNow	; su = richiesta salto (platform)
	SUBQ.W	#1,ScrllY	; su = -1 (usato in 8-direzioni)
	BRA.S	.ENDJOYST
.NOALTO:
	BTST	#0,D3		; testiamo se va in basso
	BEQ.S	.ENDJOYST	; se no, finito
	ADDQ.W	#1,ScrllY	; giu' = +1 (usato in 8-direzioni)
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
	MOVE.w	#1,UpNow	; freccia su = salto (platform)
	SUBQ.W	#1,ScrllY	; su = -1 (8-direzioni)
.no_kup:
	TST.b	arrow_dn
	BEQ.s	.no_kdn
	ADDQ.W	#1,ScrllY	; giu' = +1 (8-direzioni)
.no_kdn:

	tst.b	arrow_sx
	beq.s	.no_ksx
	move.w	#-1,ScrllX
.no_ksx:
	tst.b	arrow_rx
	beq.s	.no_krx
	move.w	#1,ScrllX
.no_krx:

	; In platform il movimento verticale viene da gravita'/salto, NON dall'input:
	; azzera ScrllY cosi' direzione sprite, gate e scroll non vedono su/giu' da input.
	; In 8-direzioni invece ScrllY resta e muove il player in lockstep.
	TST.W	GravityOn
	BEQ.S	.keepInputY
	CLR.W	ScrllY
.keepInputY:

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
	MOVE.W	ScrllY,IntentY	; 8-direzioni: lockstep. In platform ScrllY=0 qui e IntentY lo sovrascrive la fisica.

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
	bra.w	.done
 
.k_down:
	cmp.b	#RAWKEY_DOWN,D2
	bne.s	.k_left
	move.b	D1,arrow_dn
	bra.w	.done
 
.k_left:
	cmp.b	#RAWKEY_LEFT,D2
	bne.s	.k_right
	move.b	D1,arrow_sx
	bra.w	.done
 
.k_right:
	cmp.b	#RAWKEY_RIGHT,D2
	bne.s	.k_space
	move.b	D1,arrow_rx
	bra.w	.done

.k_space:
	cmp.b	#RAWKEY_SPACE,D2
	bne.s	.k_night
	move.b	D1,key_space
	bra.s	.done

.k_night:
	cmp.b	#RAWKEY_N,D2
	bne.s	.k_music
	; D1 = 1 (premuto) o 0 (rilasciato)
	; Toggle solo al "press" (edge): se NightKeyPrev=0 e D1=1, toggle
	tst.b	D1
	beq.s	.n_release				; rilasciato -> aggiorna prev e basta
	tst.b	NightKeyPrev
	bne.s	.n_release				; era gia' premuto -> no edge
	; Edge press: toggle NightMode
	eori.b	#1,NightMode
.n_release:
	move.b	D1,NightKeyPrev

.k_music:
	cmp.b	#RAWKEY_M,D2
	bne.s	.k_gravity
	; D1 = 1 (premuto) o 0 (rilasciato)
	; Toggle solo al "press" (edge): se MusicKeyPrev=0 e D1=1, toggle
	tst.b	D1
	beq.s	.m_release				; rilasciato -> aggiorna prev e basta
	tst.b	MusicKeyPrev
	bne.s	.m_release				; era gia' premuto -> no edge
	; Edge press: toggle MusicOn
	eori.b	#1,MusicOn
	; Se MusicOn appena cambiato, dovremo gestirlo nel main loop
	; (= start/stop player). Per ora basta cambiare il flag.
.m_release:
	move.b	D1,MusicKeyPrev
.k_gravity:
	cmp.b	#RAWKEY_G,D2
	bne.s	.done
	; D1 = 1 (premuto) o 0 (rilasciato); toggle solo sul fronte di pressione
	tst.b	D1
	beq.s	.g_release				; rilasciato -> aggiorna prev e basta
	tst.b	GravKeyPrev
	bne.s	.g_release				; era gia' premuto -> no edge
	; Edge press: inverti gravita' (platform <-> 8 direzioni)
	eori.w	#1,GravityOn
	move.w	#1,VScrollStep			; default 1px; in platform ComputeCameraFollowY lo rialza a CAM_STEP_Y
	clr.w	PlayerVelY				; reset stato fisica (rilevante al rientro in platform)
	clr.w	UpPrev
	clr.w	PlayerGrounded
.g_release:
	move.b	D1,GravKeyPrev
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
; AddRigaAlto riscrive le righe 0-15 (serbatoio superiore) con MAPPA[TileY].
; Lo split X in AddRigaAlto gestisce PixelOffX qualunque.
;
; FIX smear: ShiftPixelBasso lascia la riga 0 NON riscritta -> quel pixel-row
; si propaga verso il basso 1 riga/frame. Va ripulito a OGNI PixelOffY==0
; mentre si scrolla verso l'alto (ScrllY<0), non solo quando c'e' un boundary
; pendente (PdngAddTop). Altrimenti, partendo da PixelOffY!=0 (discesa fermata
; a meta' tile), lo smear accumula prima del boundary + i 16 frame di rinvio,
; supera le 16 righe del serbatoio e trabocca nell'area visibile.
	MOVE.W	PixelOffY,D1
	TST.W   D1
	BNE.S   .NoTop			; non allineato: nessun refill
	MOVE.W	PdngAddTop,D0
	TST.W   D0
	BNE.S   .DoTop			; boundary pendente -> refill
	MOVE.W	ScrllY,D0
	BPL.S   .NoTop			; ScrllY>=0 (non si sale) -> nessun refill
.DoTop:
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
	MOVEQ   #16-CAM_STEP_Y,D1	; clamp allineato al passo (15 se step=1, 8 se step=8)
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

	MOVEQ	#5-1,D4
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

	MOVEQ	#5-1,D4
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
	MOVEM.L D0-D1/D4/A1-A2,-(SP)

	; sorgente = riga VScrollStep ; dest = riga 0
	MOVE.W  VScrollStep,D0
	MULU.W  #SFONDO_PITCH,D0			; D0 = VScrollStep * SFONDO_PITCH
	MOVE.L  #SFONDOGRANDE,A2
	ADDA.L  D0,A2
	MOVE.L  #SFONDOGRANDE,A1

	; BLTSIZE = ((288-VScrollStep)<<6)+22
	MOVE.W  #288,D1
	SUB.W   VScrollStep,D1
	LSL.W   #6,D1
	ADD.W   #22,D1

	MOVEQ	#5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)
	MOVE.L  #$09F00000,$40(A6)

	MOVE.W  #4,$64(A6)		; BLTAMOD = 48-44
	MOVE.W  #4,$66(A6)		; BLTDMOD = 48-44

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  D1,$58(A6)		; (288-VScrollStep) righe x 22 word

	ADD.L   #288*SFONDO_PITCH,A2
	ADD.L   #288*SFONDO_PITCH,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D0-D1/D4/A1-A2
	RTS

****************************************************************************
* SCROLLING IN BASSO
*****************************************************************************
ShiftPixelBasso:
	MOVEM.L D0-D1/D4/A1-A2,-(SP)

	; sorgente DESC = ultima word di riga (287 - VScrollStep) ; dest DESC = ultima word riga 287
	MOVE.W  #287,D0
	SUB.W   VScrollStep,D0
	MULU.W  #SFONDO_PITCH,D0
	MOVE.L  #SFONDOGRANDE+42,A2
	ADDA.L  D0,A2
	MOVE.L  #SFONDOGRANDE+287*SFONDO_PITCH+42,A1

	; BLTSIZE = ((288-VScrollStep)<<6)+22
	MOVE.W  #288,D1
	SUB.W   VScrollStep,D1
	LSL.W   #6,D1
	ADD.W   #22,D1

	MOVEQ	#5-1,D4
.loop:
	BSR.W   AspettaBlitter

	MOVE.L  #$ffffffff,$44(A6)
	MOVE.L  #$09F00002,$40(A6)

	MOVE.W  #4,$64(A6)		; BLTAMOD = 48-44
	MOVE.W  #4,$66(A6)		; BLTDMOD = 48-44

	MOVE.L  A2,$50(A6)
	MOVE.L  A1,$54(A6)

	MOVE.W  D1,$58(A6)		; (288-VScrollStep) righe x 22 word

	ADD.L   #288*SFONDO_PITCH,A2
	ADD.L   #288*SFONDO_PITCH,A1

	DBRA	D4,.loop
	MOVEM.L (SP)+,D0-D1/D4/A1-A2
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

	MOVEQ	#5-1,D4
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

	MOVEQ	#5-1,D4
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
	MOVE.W	#BPSF_PITCH-40,$66(A6)	; BLTDMOD = 48-40 (dest BPSFONDO pitch 48, copia 20 word)

	MOVEQ	#5-1,D4
.BlittaLoopVideo:
	BSR.W	AspettaBlitter			; Aspetta che il blit precedente finisca
	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT
	MOVE.W	#((256-CUT_BOTTOM_ROWS)<<6)+20,$58(A6)	; BLTSIZE = (256-CUT) righe * 20 word

	ADD.L	#288*SFONDO_PITCH,A2	; prossimo plane sorgente
	ADD.L	#BG_PLANE_STRIDE,A1		; prossimo plane destinazione BPSFONDO

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

*****************************************************************************
* LoadAGAPalette256
*   Carica una palette AGA a 256 colori dal buffer title_pal (256 long
*   $00RRGGBB) nei registri COLOR00..COLOR31, attraverso le 8 banche di
*   BPLCON3. Per ogni banca esegue due pass:
*     - LOCT=0: scrive i nibble ALTI di ogni componente RGB
*     - LOCT=1: scrive i nibble BASSI
*   Al termine ripristina BPLCON3 = $0c00 (banca 0, LOCT=0).
*****************************************************************************
LoadAGAPalette256:
	MOVEM.L	D0-D5/A0-A2/A6,-(SP)
	LEA		$DFF000,A6
	LEA		title_pal,A0			; sorgente: 256 long $00RRGGBB
	MOVE.W	#0,D4					; bank index 0..7
	MOVEQ	#8-1,D5
.bank_loop:
	MOVE.L	A0,A2					; salva inizio banca per il low pass

	; ----- HIGH NIBBLES PASS (LOCT=0) -----
	MOVE.W	D4,D0
	LSL.W	#5,D0
	LSL.W	#8,D0					; D0 = bank << 13
	OR.W	#$0c00,D0				; LOCT=0, BRDRBLNK=1
	MOVE.W	D0,$106(A6)				; BPLCON3
	LEA		$180(A6),A1				; COLOR00
	MOVEQ	#32-1,D1
.hi_loop:
	MOVE.L	(A0)+,D2				; D2 = $00RRGGBB
	MOVE.L	D2,D3
	LSR.L	#4,D3
	AND.W	#$000F,D3				; B high
	MOVE.L	D2,D0
	LSR.L	#8,D0
	AND.W	#$00F0,D0				; G high << 4
	OR.W	D0,D3
	MOVE.L	D2,D0
	LSR.L	#8,D0
	LSR.L	#4,D0					; shift totale 12 (immediato max 8)
	AND.W	#$0F00,D0				; R high << 8
	OR.W	D0,D3
	MOVE.W	D3,(A1)+				; COLORn
	DBRA	D1,.hi_loop

	; ----- LOW NIBBLES PASS (LOCT=1) -----
	MOVE.L	A2,A0					; rewind A0 a inizio banca
	MOVE.W	D4,D0
	LSL.W	#5,D0
	LSL.W	#8,D0
	OR.W	#$0e00,D0				; LOCT=1, BRDRBLNK=1
	MOVE.W	D0,$106(A6)
	LEA		$180(A6),A1
	MOVEQ	#32-1,D1
.lo_loop:
	MOVE.L	(A0)+,D2
	MOVE.W	D2,D3
	AND.W	#$000F,D3				; B low
	MOVE.W	D2,D0
	LSR.W	#4,D0
	AND.W	#$00F0,D0				; G low << 4
	OR.W	D0,D3
	MOVE.L	D2,D0
	LSR.L	#8,D0
	AND.W	#$0F00,D0				; R low << 8
	OR.W	D0,D3
	MOVE.W	D3,(A1)+
	DBRA	D1,.lo_loop

	ADDQ.W	#1,D4
	DBRA	D5,.bank_loop

	MOVE.W	#$0000,$106(A6)			; ripristina BPLCON3 (banca 0, LOCT=0, no offset)
	MOVEM.L	(SP)+,D0-D5/A0-A2/A6
	RTS

*****************************************************************************
* ShowTitle
*   1) Patcha i puntatori BPL1..8PT della TitleCopperList su title_bpl.
*   2) Carica la palette AGA 256 colori via CPU da title_pal.
*   3) Punta il copper a TitleCopperList e abilita BPL+COPPER DMA.
*****************************************************************************
ShowTitle:
	MOVEM.L	D0-D1/A1/A6,-(SP)
	LEA		$DFF000,A6

	; --- Setup display via CPU (ridondante con la copperlist ma garantisce
	;     valori corretti gia' al primo frame, anche se il copper non parte). ---
	MOVE.W	#$0211,$100(A6)			; BPLCON0: BPU3=1 (=8 BPL) + COLOR + ECSENA (no UHRES)
	MOVE.W	#$0000,$102(A6)			; BPLCON1
	MOVE.W	#$0024,$104(A6)			; BPLCON2: PF2P=4, PF1P=4 (come gioco)
	MOVE.W	#$0000,$106(A6)			; BPLCON3: banca 0, LOCT=0, no offset
	MOVE.W	#$0000,$10c(A6)			; BPLCON4
	MOVE.W	#$0000,$108(A6)			; BPL1MOD (sequential layout)
	MOVE.W	#$0000,$10a(A6)			; BPL2MOD
	; AGA 8 BPL lores FMODE=3: DDFSTRT/STOP allineati al fetch interval di 32cc.
	; ($A8 - $28) / 32 = 4 -> esattamente 5 fetch per riga, 5*64px = 320px.
	MOVE.W	#$0028,$92(A6)			; DDFSTRT
	MOVE.W	#$00a8,$94(A6)			; DDFSTOP (5 fetch FMODE=3 allineati)
	MOVE.W	#$2c81,$8e(A6)			; DIWSTRT
	MOVE.W	#$2cc1,$90(A6)			; DIWSTOP

	; --- Setup BPL pointers via CPU (8 plane SEQUENTIAL, 10240 byte/plane) ---
	MOVE.L	#title_bpl,$E0(A6)								; BPL1PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE,$E4(A6)				; BPL2PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*2,$E8(A6)			; BPL3PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*3,$EC(A6)			; BPL4PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*4,$F0(A6)			; BPL5PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*5,$F4(A6)			; BPL6PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*6,$F8(A6)			; BPL7PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*7,$FC(A6)			; BPL8PT

	; --- Patch BPL pointers anche nella TitleCopperList (per i frame
	;     successivi al primo: il copper li resetta a ogni vertical blank). ---
	LEA		TitleBPL_0,A1
	MOVE.L	#title_bpl,D0
	MOVEQ	#8-1,D1
.bpl_loop:
	MOVE.W	D0,6(A1)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)				; word alta
	SWAP	D0
	ADD.L	#TITLE_PLANE_SIZE,D0	; prossimo plane (sequential)
	ADDQ.L	#8,A1
	DBRA	D1,.bpl_loop

	; --- Carica palette AGA 256 colori via CPU ---
	BSR.W	LoadAGAPalette256

	; --- Ordine identico al setup del gioco: DMA on, COP1LC, strobe ---
	MOVE.W	#$8380,$96(A6)				; SET + DMAEN + BPLEN + COPEN
	MOVE.L	#TitleCopperList,$80(A6)	; COP1LCH
	MOVE.W	D0,$88(A6)					; COPJMP1 strobe

	MOVEM.L	(SP)+,D0-D1/A1/A6
	RTS

*****************************************************************************
* WaitTitleInput
*   Attende che venga premuto SPACE o il tasto fire del joystick (port 1).
*   Aspetta poi il rilascio di entrambi prima di tornare, in modo che il
*   gioco non veda subito un evento di sparo o un edge "spurio".
*****************************************************************************
WaitTitleInput:
	MOVEM.L	D0,-(SP)
.wait_press:
	BSR.W	AspettaVBL
	BSR.W	ReadKeyboard				; aggiorna key_space
	TST.B	key_space
	BNE.S	.pressed
	MOVE.B	$bfe001,D0					; CIA-A PRA: bit 7 = fire joy1 (active low)
	NOT.B	D0
	AND.B	#$80,D0
	BEQ.S	.wait_press					; D0=0 -> fire NON premuto
.pressed:
.wait_release:
	BSR.W	AspettaVBL
	BSR.W	ReadKeyboard
	TST.B	key_space
	BNE.S	.wait_release
	MOVE.B	$bfe001,D0
	NOT.B	D0
	AND.B	#$80,D0
	BNE.S	.wait_release				; D0!=0 -> fire ANCORA premuto

	; Reset stato fire per il gioco
	MOVE.W	#0,FirePrev
	MOVE.B	#0,key_space
	MOVEM.L	(SP)+,D0
	RTS

*****************************************************************************
* PlaySfx
*   Suona un sound effect via PT Player.
*   INPUT:  A0 = puntatore SfxStructure (sfx_ptr/len/per/vol/cha/pri)
*   OUTPUT: nessuno (lo status del canale ritornato da _mt_playfx e' ignorato)
*   Preserva tutti i registri. Non richiede A6 settato dal chiamante.
*****************************************************************************
PlaySfx:
	MOVEM.L	D0-D7/A0-A6,-(SP)
	LEA		$DFF000,A6
	JSR		_mt_playfx			; A0 = SfxStructure
	MOVEM.L	(SP)+,D0-D7/A0-A6
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
	MOVE.W	#BULLET_TTLC,Bullet_TTL
	MOVE.W	#BULLET_COOLDOWNC,Bullet_Cooldown
	LEA		SfxSparo,A0
	BSR.W	PlaySfx
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
	BNE.S	.sfx_hit_alive
	MOVE.W	#0,bob_Active(A0)
	LEA		SfxEnemyDeath,A0
	BSR.W	PlaySfx
	BRA.S	.save_fire
.sfx_hit_alive:
	LEA		SfxHitEnemy,A0
	BSR.W	PlaySfx
	BRA.S	.save_fire

.coll_next:
	LEA		bob_Length(A0),A0
	DBRA	D5,.coll_loop

.save_fire:
	MOVE.W	D1,FirePrev

	MOVEM.L	(SP)+,D0-D5/A0
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
	LEA		SfxHitPlayer,A0
	BSR.W	PlaySfx
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
* AnimaFalo
*   Gestisce l'animazione del falò (sprite hardware SPR0):
*   - Avanza FaloAnimFrame ogni FaloAnimSpeed frame
*   - Trova la prima tile 19 nella viewport e calcola posizione schermo
*   - Costruisce SPRPOS/SPRCTL per quel frame
*   - Aggiorna SPR0PT nella copperlist (Sprites entry)
*   Se nessuna tile 19 visibile: SPR0PT -> EmptySprite (invisibile).
*****************************************************************************
AnimaFalo:
	MOVEM.L	D0-D7/A0-A4,-(SP)
	
	; ----- Di giorno (NightMode=0): sprite invisibile, esci subito -----
	TST.B	NightMode
	BNE.S	.is_night
	; Giorno: SPR0 -> EmptySprite
	MOVE.L	#EmptySprite,D0
	LEA		Sprites,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	BRA.W	.done
.is_night:
	; ----- Avanza il frame di animazione ogni FaloAnimSpeed frame -----
	ADDQ.W	#1,FaloAnimDelay
	CMP.W	#FaloAnimSpeed,FaloAnimDelay
	BLT.S	.no_advance
	CLR.W	FaloAnimDelay
	ADDQ.W	#1,FaloAnimFrame
	CMP.W	#6,FaloAnimFrame
	BLT.S	.no_advance
	CLR.W	FaloAnimFrame
.no_advance:

	; ===== DEBUG: posizione fissa basata su tile 19 in MAPPA[15][5] =====
	; Sottraggo TileX/TileY per compensare lo scroll
	; D3 = 5 - TileX, D7 = 15 - TileY
	; (Verificato: lo sprite NON e' la causa dello sfarfallio sulle ultime
	;  ~12 scanline - quello e' contesa DMA blitter/bitplane su AGA FMODE=3.)
	MOVE.W	#5,D3
	SUB.W	TileX,D3				; D3 = col buffer della tile 19
	MOVE.W	#15,D7
	SUB.W	TileY,D7				; D7 = row buffer della tile 19

	; Cull: se fuori dal buffer visibile, sprite invisibile
	TST.W	D3
	BMI.W	.no_falo
	CMP.W	#BUFFER_COLS,D3
	BGE.W	.no_falo
	TST.W	D7
	BMI.W	.no_falo
	CMP.W	#BUFFER_ROWS,D7
	BGE.W	.no_falo

	BRA.W	.found_falo

.no_falo:
	; Sprite invisibile (fuori viewport)
	MOVE.L	#EmptySprite,D0
	LEA		Sprites,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	BRA.W	.done

.found_falo:
	; D3 = col buffer, D7 = row buffer
	; Il rendering visualizza le tile sfasate di 1 tile: la tile buffer (D3,D7)
	; appare a screen ((D3-1)*16 - PixelOffX, (D7-1)*16 - PixelOffY).
	; Per uno sprite 16x16 sovrapposto alla tile:
	;   topleft_x = (D3-1)*16 - PixelOffX = D3*16 - 16 - PixelOffX
	;   topleft_y = (D7-1)*16 - PixelOffY = D7*16 - 16 - PixelOffY
	MOVE.W	D3,D0
	LSL.W	#4,D0					; D0 = D3*16
	SUBI.W	#16,D0					; -16 (fix sfasamento rendering)
	SUB.W	PixelOffX,D0			; D0 = topleft_x

	MOVE.W	D7,D1
	LSL.W	#4,D1
	SUBI.W	#16,D1
	SUB.W	PixelOffY,D1			; D1 = topleft_y

	; ----- Costruisco SPRPOS/SPRCTL -----
	; VSTART_reg = $2C + screen_y
	; VSTOP_reg  = VSTART_reg + 16
	; HSTART_reg = $81 + screen_x  (pixel lores 1-to-1)
	ADDI.W	#$2C,D1					; D1 = VSTART
	MOVE.W	D1,D2
	ADDI.W	#16,D2					; D2 = VSTOP

	ADDI.W	#$81,D0					; D0 = HSTART

	; ----- Costruisco SPRPOS/SPRCTL -----
	; SPRPOS: bit 15-8 = SV7-SV0 (= VSTART[7:0])
	;         bit 7-0  = SH8-SH1 (= HSTART[8:1])  <- importante!
	; SPRCTL: bit 15-8 = EV7-EV0 (= VSTOP[7:0])
	;         bit 7    = ATT
	;         bit 2    = SV8 (= VSTART[8])
	;         bit 1    = EV8 (= VSTOP[8])
	;         bit 0    = SH0 (= HSTART[0])

	; D3 = SPRPOS (build): (VSTART[7:0] << 8) | (HSTART[8:1])
	MOVE.W	D1,D3
	ANDI.W	#$FF,D3
	LSL.W	#8,D3					; bit 15-8 = VSTART[7:0]
	MOVE.W	D0,D4
	LSR.W	#1,D4					; D4 = HSTART >> 1
	ANDI.W	#$FF,D4
	OR.W	D4,D3					; D3 = SPRPOS

	; D5 = SPRCTL (build): (VSTOP[7:0] << 8) | flags
	MOVE.W	D2,D5
	ANDI.W	#$FF,D5
	LSL.W	#8,D5					; bit 15-8 = VSTOP[7:0]
	BTST	#8,D1
	BEQ.S	.no_v8a
	BSET	#2,D5					; VSTART[8] (SV8)
.no_v8a:
	BTST	#8,D2
	BEQ.S	.no_v8b
	BSET	#1,D5					; VSTOP[8] (EV8)
.no_v8b:
	BTST	#0,D0
	BEQ.S	.no_h0
	BSET	#0,D5					; HSTART[0] (SH0)
.no_h0:

	; ----- Scrivo SPRPOS/SPRCTL in TUTTI i 6 frame -----
	; Cosi' qualunque sia il frame corrente, la posizione e' sempre corretta.
	LEA		FaloFrameTable,A0
	MOVEQ	#6-1,D7					; 6 frame
.write_pos_loop:
	MOVE.L	(A0)+,A2				; A2 = FuocoFrame_N
	MOVE.W	D3,(A2)					; SPRPOS
	MOVE.W	D5,2(A2)				; SPRCTL
	DBRA	D7,.write_pos_loop

	; ----- Aggiorno SPR0PT nella copperlist (Sprites entry) -----
	LEA		FaloFrameTable,A0
	MOVE.W	FaloAnimFrame,D4
	LSL.W	#2,D4
	MOVE.L	(A0,D4.W),D0			; D0 = FuocoFrame_N corrente
	LEA		Sprites,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)

.done:
	MOVEM.L	(SP)+,D0-D7/A0-A4
	RTS

*****************************************************************************
* AggiornaProiettile
*   Aggiorna sprite SPR1 (BulletSprite) in base allo stato del proiettile:
*   - Bullet_Active=0 -> SPR1PT punta a EmptySprite (= invisibile)
*   - Bullet_Active=1 -> calcola SPRPOS/SPRCTL da Bullet_X/Y (world coords),
*                        converte a screen coords e aggiorna BulletSprite
*
*   Camera world->screen:
*     screen_x = Bullet_X - (TileX*16 + PixelOffX)
*     screen_y = Bullet_Y - (TileY*16 + PixelOffY)
*   Top-left sprite (16x16, fix sfasamento rendering -8 -8):
*     topleft_x = screen_x - 8 - 8 = screen_x - 16
*     topleft_y = screen_y - 8 - 8 = screen_y - 16
*   (= stesso fix usato per AnimaFalo, sprite hardware ha coord native DIW)
*
*   SPRPOS/SPRCTL: stessa logica di AnimaFalo (bit mapping HSTART corretto).
*****************************************************************************
AggiornaProiettile:
	MOVEM.L	D0-D5/A0-A2,-(SP)

	; ----- Se proiettile inattivo: SPR1PT -> EmptySprite, esci -----
	TST.W	Bullet_Active
	BNE.S	.is_active
	MOVE.L	#EmptySprite,D0
	LEA		Sprites+8,A1			; Sprites+8 = SPR1PT entry
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	BRA.W	.done

.is_active:
	; ----- Calcola screen_x = Bullet_X - CameraX -----
	MOVE.W	TileX,D2
	LSL.W	#4,D2					; D2 = TileX*16
	ADD.W	PixelOffX,D2			; D2 = CameraX
	MOVE.W	Bullet_X,D0
	SUB.W	D2,D0					; D0 = screen_x

	; ----- Calcola screen_y = Bullet_Y - CameraY -----
	MOVE.W	TileY,D2
	LSL.W	#4,D2
	ADD.W	PixelOffY,D2			; D2 = CameraY
	MOVE.W	Bullet_Y,D1
	SUB.W	D2,D1					; D1 = screen_y

	; ----- Cull: se fuori schermo, sprite invisibile -----
	CMP.W	#-16,D0
	BLT.S	.cull
	CMP.W	#320,D0
	BGE.S	.cull
	CMP.W	#-16,D1
	BLT.S	.cull
	CMP.W	#256,D1
	BLT.S	.in_screen
.cull:
	MOVE.L	#EmptySprite,D0
	LEA		Sprites+8,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	BRA.W	.done

.in_screen:
	; ----- Top-left sprite: applichiamo il fix -16/-16 per rendering sfasato -----
	SUBI.W	#16,D0					; D0 = topleft_x
	SUBI.W	#16,D1					; D1 = topleft_y

	; ----- Costruisci SPRPOS/SPRCTL (stessa logica di AnimaFalo) -----
	; VSTART_reg = $2C + screen_y
	; VSTOP_reg  = VSTART_reg + 16
	; HSTART_reg = $81 + screen_x (NO divisione - bit mapping in SPRPOS gestisce)
	ADDI.W	#$2C,D1					; D1 = VSTART
	MOVE.W	D1,D2
	ADDI.W	#16,D2					; D2 = VSTOP

	ADDI.W	#$81,D0					; D0 = HSTART (9 bit possibili)

	; SPRPOS: bit 15-8 = SV7-SV0 (VSTART[7:0]), bit 7-0 = SH8-SH1 (HSTART[8:1])
	MOVE.W	D1,D3
	ANDI.W	#$FF,D3
	LSL.W	#8,D3
	MOVE.W	D0,D4
	LSR.W	#1,D4					; HSTART >> 1
	ANDI.W	#$FF,D4
	OR.W	D4,D3					; D3 = SPRPOS

	; SPRCTL: bit 15-8 = EV7-EV0, bit 2 = SV8, bit 1 = EV8, bit 0 = SH0
	MOVE.W	D2,D5
	ANDI.W	#$FF,D5
	LSL.W	#8,D5
	BTST	#8,D1
	BEQ.S	.no_v8a
	BSET	#2,D5
.no_v8a:
	BTST	#8,D2
	BEQ.S	.no_v8b
	BSET	#1,D5
.no_v8b:
	BTST	#0,D0
	BEQ.S	.no_h0
	BSET	#0,D5
.no_h0:

	; ----- Scrivi SPRPOS/SPRCTL nel BulletSprite -----
	LEA		BulletSprite,A2
	MOVE.W	D3,(A2)					; SPRPOS
	MOVE.W	D5,2(A2)				; SPRCTL

	; ----- SPR1PT -> BulletSprite nella copperlist -----
	MOVE.L	A2,D0
	LEA		Sprites+8,A1			; SPR1PT entry (Sprites+0 = SPR0PT)
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)

.done:
	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

*****************************************************************************
* UpdateDarkPlane
*   Aggiorna il dark plane (DARKPLANE_*) ad ogni frame, in 2 step:
*
*   STEP 1: Fill del DARKPLANE_corrente (= CurrentDarkDraw)
*     - NightMode=0 (giorno): tutto $00 -> nessun pixel half-bright
*     - NightMode=1 (notte): tutto $FF -> tutto half-bright (scuro)
*
*   STEP 2: Disegna sorgenti luminose (solo se notte)
*     Scansiona le 22x18 tile del buffer visibile. Per ogni tile=TILE_LUCE
*     disegna un cerchio di "luce" (= pixel a 0 sul dark plane) centrato sulla
*     tile, raggio = RAGGIO_LUCE.
*
*   Il cerchio è disegnato con una tabella di "mezza-larghezza per riga"
*   (LightHalfWidthTable) per evitare sqrt a runtime.
*****************************************************************************
UpdateDarkPlane:
	MOVEM.L	D0-D7/A0-A4,-(SP)

	; ----- STEP 1: Fill del DARKPLANE_corrente via BLITTER -----
	; Blit "destination-only": il minterm LF non dipende da A/B/C.
	;   notte  -> LF=$FF -> D=$FFFF (tutto half-bright = scuro)
	;   giorno -> LF=$00 -> D=$0000 (nessun pixel half-bright)
	; Niente canali sorgente, niente BLTADAT: bulletproof. Libera ~2.5ms di CPU.
	BSR.W	AspettaBlitter

	MOVE.W	#$0100,D1				; BLTCON0 base: USED on, LF=$00 (D=0) -> giorno
	TST.B	NightMode
	BEQ.S	.fillcon_ok
	MOVE.W	#$01FF,D1				; notte: LF=$FF -> D=$FFFF
.fillcon_ok:
	MOVE.W	D1,$40(A6)				; BLTCON0
	MOVE.W	#0,$42(A6)				; BLTCON1 = 0 (no shift, no fill mode)
	MOVE.W	#BPSF_PITCH-40,$66(A6)	; BLTDMOD = 48-40 (dest BPSFONDO pitch 48, copia 20 word)
	MOVE.L	CurrentDarkDraw,$54(A6)	; BLTDPT
	MOVE.W	#(DARK_ROWS<<6)|20,$58(A6)	; BLTSIZE -> avvia (DARK_ROWS righe * 20 word)

	; Il cerchio luce (CPU) modifichera' il dark plane appena riempito:
	; deve attendere la fine del fill blit prima di scriverci.
	BSR.W	AspettaBlitter

	; ----- STEP 2: Lampioni (solo se notte) -----
	TST.B	NightMode
	BEQ.W	.done					; giorno: niente lampioni da disegnare

	IFNE	DBG_FIXLIGHT
	; --- DIAGNOSTICA: cerchio in posizione FISSA, indipendente dalla camera ---
	; cx=160 (centro X), cy=216 (basso, cosi' il cerchio esce in basso come nel bug)
	MOVE.W	#160,D0
	MOVE.W	#216,D1
	BSR.W	DisegnaCerchioLuceBlitter
	BRA.W	.done
	ENDC

	; Scansione viewport: BUFFER_COLS x BUFFER_ROWS tile
	; map_col_start = TileX, map_row_start = TileY
	; Per ogni tile (row, col): se MAPPA[map_row][map_col] == TILE_LUCE,
	;   center_screen_x = col*16 + 8 - PixelOffX
	;   center_screen_y = row*16 + 8 - PixelOffY
	;   disegna cerchio

	MOVE.W	TileY,D6				; D6 = row corrente nella mappa
	MOVEQ	#0,D7					; D7 = row buffer corrente (0..BUFFER_ROWS-1)
.row_loop:
	; Calcola center_screen_y = D7*16 - 8 - PixelOffY
	; (coerente col centro reale passato a DisegnaCerchioLuce piu' sotto)
	MOVE.W	D7,D5
	LSL.W	#4,D5					; D5 = D7*16
	SUBQ.W	#8,D5					; -8 (centro tile, con sfasamento rendering)
	SUB.W	PixelOffY,D5			; D5 = center_screen_y
	; Cull: se y fuori da [-RAGGIO_LUCE, 256+RAGGIO_LUCE], skip
	CMP.W	#-RAGGIO_LUCE,D5
	BLT.W	.next_row
	CMP.W	#256+RAGGIO_LUCE,D5
	BGE.W	.next_row

	; Loop colonne
	MOVE.W	TileX,D4				; D4 = col corrente nella mappa
	MOVEQ	#0,D3					; D3 = col buffer (0..BUFFER_COLS-1)
.col_loop:
	; Bounds check su MAPPA
	CMP.W	#MAPPA_COLS,D4
	BGE.S	.next_col
	CMP.W	#MAPPA_ROWS,D6
	BGE.W	.next_row_full

	; Leggi MAPPA[D6][D4]
	; offset = (D6 * MAPPA_COLS + D4) * 2
	MOVE.W	D6,D2
	MULU.W	#MAPPA_COLS,D2
	ADD.W	D4,D2
	ADD.W	D2,D2					; * 2 (word)
	LEA		MAPPA,A0
	MOVE.W	(A0,D2.W),D2			; D2 = numero tile
	CMP.W	#TILE_LUCE,D2
	BNE.S	.next_col

	; LUCE TROVATA!
	; center_screen_x = D3*16 + 16 - PixelOffX  (+8 offset + 8 centro)
	MOVE.W	D3,D0
	LSL.W	#4,D0
	SUB.W	#8,D0
	SUB.W	PixelOffX,D0			; D0 = center_screen_x
	; center_screen_y = D7*16 + 32 - PixelOffY  (+24 offset + 8 centro)
	MOVE.W	D7,D1
	LSL.W	#4,D1
	SUB.W	#8,D1
	SUB.W	PixelOffY,D1			; D1 = center_screen_y
	BSR.W	DisegnaCerchioLuceBlitter	; INPUT: D0=cx, D1=cy

.next_col:
	ADDQ.W	#1,D3					; col buffer +1
	ADDQ.W	#1,D4					; col mappa +1
	CMP.W	#BUFFER_COLS,D3
	BLT.W	.col_loop

.next_row:
	ADDQ.W	#1,D7					; row buffer +1
	ADDQ.W	#1,D6					; row mappa +1
	CMP.W	#BUFFER_ROWS,D7
	BLT.W	.row_loop
	BRA.S	.done

.next_row_full:
	; Saltiamo direttamente alla prossima riga (= fine col_loop forzata)
	ADDQ.W	#1,D7
	ADDQ.W	#1,D6
	CMP.W	#BUFFER_ROWS,D7
	BLT.W	.row_loop

.done:
	MOVEM.L	(SP)+,D0-D7/A0-A4
	RTS

*****************************************************************************
* DisegnaCerchioLuce
*   Disegna un cerchio di "luce" (= bit a 0) sul dark plane corrente.
*   INPUT:
*     D0.w = center X schermo (puo' essere negativo)
*     D1.w = center Y schermo (idem)
*   Raggio = RAGGIO_LUCE.
*
*   Strategia: per ogni riga dy, calcola span [x_left..x_right] e fa
*   AND-NOT con la maschera sul dark plane (= spegne i pixel = luce).
*****************************************************************************
DisegnaCerchioLuce:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	; Salvo cx, cy in registri "stabili" usando A2, A3 (.w)
	MOVE.W	D0,A2					; A2 = cx
	MOVE.W	D1,A3					; A3 = cy

	; Loop esterno: dy da -RAGGIO_LUCE a +RAGGIO_LUCE
	; Uso D7 come dy (preservato attraverso il loop interno con la stack)
	MOVE.W	#-RAGGIO_LUCE,D7
.dy_loop:
	; Salvo D7 (dy) sullo stack durante il loop interno
	MOVE.W	D7,-(SP)

	; y_riga = cy + dy
	MOVE.W	A3,D3
	ADD.W	D7,D3					; D3 = y_riga
	; Cull verticale (le ultime CUT_BOTTOM_ROWS righe restano "scure", fuori dal display utile)
	BMI.W	.skip_row
	CMP.W	#(256-CUT_BOTTOM_ROWS),D3
	BGE.W	.skip_row

	; half = LightHalfWidthTable[|dy|]
	MOVE.W	D7,D4
	BPL.S	.abs_ok
	NEG.W	D4
.abs_ok:
	LEA		LightHalfWidthTable,A0
	MOVE.B	(A0,D4.W),D5
	EXT.W	D5						; D5 = half
	TST.W	D5
	BEQ.W	.skip_row				; half=0

	; x_left = cx - half, x_right = cx + half - 1
	MOVE.W	A2,D0
	SUB.W	D5,D0					; D0 = x_left
	MOVE.W	A2,D1
	ADD.W	D5,D1
	SUBQ.W	#1,D1					; D1 = x_right

	; Cull orizzontale
	TST.W	D1
	BMI.W	.skip_row
	CMP.W	#320,D0
	BGE.W	.skip_row
	; Clip
	TST.W	D0
	BPL.S	.lc_ok
	MOVEQ	#0,D0
.lc_ok:
	CMP.W	#319,D1
	BLE.S	.rc_ok
	MOVE.W	#319,D1
.rc_ok:
	; D0 = x_left clippato, D1 = x_right clippato

	; A1 = base riga sul dark plane
	MOVE.L	CurrentDarkDraw,A1
	MOVE.W	D3,D4
	MULU.W	#BPSF_PITCH,D4
	ADDA.L	D4,A1

	; byte_left = D0 >> 3, byte_right = D1 >> 3
	; bit_left = D0 & 7, bit_right = D1 & 7
	MOVE.W	D0,D2					; D2 = byte_left
	LSR.W	#3,D2
	MOVE.W	D1,D3					; D3 = byte_right
	LSR.W	#3,D3
	MOVE.W	D0,D4
	ANDI.W	#7,D4					; D4 = bit_left
	MOVE.W	D1,D5
	ANDI.W	#7,D5					; D5 = bit_right

	; A1 += byte_left
	ADDA.W	D2,A1

	; Costruisco maschere PER LATO:
	; left_mask  = $FF >> bit_left   (bit da spegnere nel byte sinistro)
	; right_mask = $FF << (7 - bit_right), poi & $FF
	MOVE.W	#$FF,D6
	LSR.W	D4,D6					; D6 = left_mask
	MOVEQ	#7,D0
	SUB.W	D5,D0					; D0 = 7 - bit_right
	MOVE.W	#$FF,D5
	LSL.W	D0,D5
	ANDI.W	#$FF,D5					; D5 = right_mask

	; Confronto byte_left vs byte_right
	CMP.W	D2,D3
	BNE.S	.multi_byte

	; SINGLE BYTE: mask = left_mask AND right_mask
	AND.B	D5,D6					; D6 = mask combinata
	NOT.B	D6
	AND.B	D6,(A1)
	BRA.S	.skip_row

.multi_byte:
	; Primo byte: AND con NOT left_mask
	MOVE.B	D6,D0
	NOT.B	D0
	AND.B	D0,(A1)+
	; Byte intermedi: tutti a 0
	MOVE.W	D3,D0
	SUB.W	D2,D0					; D0 = byte_right - byte_left
	SUBQ.W	#1,D0					; D0 = numero intermedi (= byte_right - byte_left - 1)
	BLE.S	.middle_done			; <=0: nessun intermedio
	SUBQ.W	#1,D0
	BMI.S	.middle_done
.middle_loop:
	CLR.B	(A1)+
	DBRA	D0,.middle_loop
.middle_done:
	; Ultimo byte: AND con NOT right_mask
	MOVE.B	D5,D0
	NOT.B	D0
	AND.B	D0,(A1)

.skip_row:
	; Ripristina dy dallo stack
	MOVE.W	(SP)+,D7
	ADDQ.W	#1,D7
	CMP.W	#RAGGIO_LUCE+1,D7
	BLT.W	.dy_loop

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

*****************************************************************************
* LightHalfWidthTable
*   Tabella di "mezza-larghezza" per cerchio raggio LIGHT_RADIUS=64.
*   Indicizzata da |dy| (0..64).
*   half[dy] = sqrt(64² - dy²)
*****************************************************************************
LightHalfWidthTable:
	dc.b	64,63,63,63,63,63,63,63		; dy  0.. 7
	dc.b	63,63,63,63,62,62,62,62		; dy  8..15
	dc.b	61,61,61,61,60,60,60,59		; dy 16..23
	dc.b	59,58,58,58,57,57,56,55		; dy 24..31
	dc.b	55,54,54,53,52,52,51,50		; dy 32..39
	dc.b	49,49,48,47,46,45,44,43		; dy 40..47
	dc.b	42,41,39,38,37,35,34,32		; dy 48..55
	dc.b	30,29,27,24,22,19,15,11		; dy 56..63
	dc.b	 0							; dy 64

	EVEN
*****************************************************************************
* BuildLightMask  (chiamata UNA volta al boot)
*   Costruisce LightMask: disco di raggio RAGGIO_LUCE, bit=1 dentro, in un
*   buffer di LIGHT_MASK_W word x LIGHT_MASK_H righe. Riusa LightHalfWidthTable.
*   La 9a word di ogni riga resta 0 (spillover per lo shift del blit).
*****************************************************************************
BuildLightMask:
	MOVEM.L	D0-D4/A0-A1,-(SP)
	LEA		LightMask,A1			; A1 = riga corrente della maschera
	MOVEQ	#0,D0					; D0 = r (0..LIGHT_MASK_H-1)
.row:
	MOVE.W	D0,D1
	SUB.W	#64,D1					; dy = r - 64
	TST.W	D1						; |dy|
	BPL.S	.pos
	NEG.W	D1
.pos:
	LEA		LightHalfWidthTable,A0
	MOVE.B	(A0,D1.W),D2
	EXT.W	D2						; D2 = half
	TST.W	D2
	BEQ.S	.next					; half=0 -> riga vuota (resta 0)
	MOVE.W	#64,D3
	SUB.W	D2,D3					; D3 = x_left  = 64 - half
	MOVE.W	#64,D4
	ADD.W	D2,D4
	SUBQ.W	#1,D4					; D4 = x_right = 64 + half - 1
	BSR.S	SetBitSpan				; setta bit [D3..D4] nella riga A1
.next:
	LEA		LIGHT_MASK_STRIDE(A1),A1	; prossima riga
	ADDQ.W	#1,D0
	CMP.W	#LIGHT_MASK_H,D0
	BLT.S	.row
	MOVEM.L	(SP)+,D0-D4/A0-A1
	RTS

*****************************************************************************
* SetBitSpan  - setta a 1 i bit da D3 a D4 (inclusi) nella riga A1.
*   Ordine bit MSB-first: pixel 0 = bit 7 del byte 0. Solo per il boot.
*****************************************************************************
SetBitSpan:
	MOVEM.L	D3/D5/D6/A2,-(SP)
.sb:
	MOVE.W	D3,D5
	LSR.W	#3,D5					; byte index = x>>3
	MOVE.W	D3,D6
	ANDI.W	#7,D6
	EORI.W	#7,D6					; bit = 7-(x&7)  (MSB = pixel 0)
	LEA		(A1,D5.W),A2
	BSET	D6,(A2)
	ADDQ.W	#1,D3
	CMP.W	D4,D3
	BLE.S	.sb
	MOVEM.L	(SP)+,D3/D5/D6/A2
	RTS

*****************************************************************************
* DisegnaCerchioLuceBlitter
*   Disegna il cerchio di luce sul dark plane (= spegne i bit dentro) usando
*   il BLITTER: minterm D = (NOT A) AND C, con A=LightMask, C/D=dark plane.
*   INPUT: D0.w = cx, D1.w = cy  (centro schermo, come DisegnaCerchioLuce).
*
*   - Shift orizzontale sub-word via ASH in BLTCON0.
*   - Clipping verticale: aggiusta riga di partenza maschera + altezza blit.
*   - Clipping orizzontale (bordo sx/dx): FALLBACK alla routine CPU esistente
*     quando word_x e' fuori [0..11] (cerchio a cavallo del bordo laterale).
*****************************************************************************
DisegnaCerchioLuceBlitter:
	MOVEM.L	D0-D7/A0-A1,-(SP)

	; left_px = cx - 64 ; word_x = left_px>>4 (signed) ; shift = left_px & 15
	MOVE.W	D0,D2
	SUB.W	#RAGGIO_LUCE,D2			; D2 = left_px (signed)
	MOVE.W	D2,D3
	ASR.W	#4,D3					; D3 = word_x (signed)
	ANDI.W	#15,D2					; D2 = shift (0..15)

	; fallback CPU se il cerchio tocca i bordi sx/dx
	TST.W	D3
	BMI.W	.cpu_fallback			; word_x < 0
	CMP.W	#11,D3
	BGT.W	.cpu_fallback			; word_x > 11 -> 9 word non entrano in 20

	; ----- clipping verticale -----
	MOVE.W	D1,D5
	SUB.W	#RAGGIO_LUCE,D5			; D5 = top_row = cy - 64 (signed)
	MOVEQ	#0,D6					; D6 = rows_skip
	TST.W	D5
	BPL.S	.vt_ok
	MOVE.W	D5,D6
	NEG.W	D6						; rows_skip = -top_row
	MOVEQ	#0,D5					; vtop = 0
.vt_ok:
	MOVE.W	D1,D7
	ADD.W	#RAGGIO_LUCE,D7			; D7 = cy + 64 = bottom (esclusivo)
	CMP.W	#256,D7
	BLE.S	.vb_ok
	MOVE.W	#256,D7					; clamp altezza display
.vb_ok:
	MOVE.W	D7,D4
	SUB.W	D5,D4					; D4 = height = vbot - vtop
	BLE.W	.exit					; <=0: cerchio fuori in verticale

	BSR.W	AspettaBlitter

	; A0 = LightMask + rows_skip*stride
	MULU.W	#LIGHT_MASK_STRIDE,D6
	LEA		LightMask,A0
	ADDA.W	D6,A0
	; A1 = CurrentDarkDraw + vtop*48 + word_x*2
	MOVE.L	CurrentDarkDraw,A1
	MOVE.W	D5,D6
	MULU.W	#BPSF_PITCH,D6
	ADDA.W	D6,A1
	MOVE.W	D3,D6
	ADD.W	D6,D6					; word_x*2
	ADDA.W	D6,A1

	MOVE.L	A0,$50(A6)				; BLTAPT = maschera
	MOVE.L	A1,$48(A6)				; BLTCPT = dark plane (lettura)
	MOVE.L	A1,$54(A6)				; BLTDPT = dark plane (scrittura)

	; BLTCON0 = (shift<<12) | USEA|USEC|USED | LF=$0A (D = ~A & C)
	MOVE.W	D2,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; shift << 12
	ORI.W	#$0B0A,D6
	MOVE.W	D6,$40(A6)				; BLTCON0
	MOVE.W	#0,$42(A6)				; BLTCON1 = 0
	MOVE.L	#$FFFFFFFF,$44(A6)		; BLTAFWM/BLTALWM = $FFFF
	MOVE.W	#0,$64(A6)				; BLTAMOD = 0 (maschera 9 word, blit 9 word)
	MOVE.W	#BPSF_PITCH-LIGHT_MASK_W*2,$60(A6)	; BLTCMOD = 48-18 = 30
	MOVE.W	#BPSF_PITCH-LIGHT_MASK_W*2,$66(A6)	; BLTDMOD = 48-18 = 30

	MOVE.W	D4,D6					; height
	LSL.W	#6,D6
	ORI.W	#LIGHT_MASK_W,D6		; | 9 word
	MOVE.W	D6,$58(A6)				; BLTSIZE -> avvia
	BRA.S	.exit

.cpu_fallback:
	; cx (D0) e cy (D1) sono ancora intatti -> uso la routine CPU collaudata.
	; Attendo un eventuale blit cerchio precedente: la CPU scrive direttamente.
	BSR.W	AspettaBlitter
	BSR.W	DisegnaCerchioLuce

.exit:
	MOVEM.L	(SP)+,D0-D7/A0-A1
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
	; D1.w = bitmask 16-bit (N bit alti a 1). Vogliamo posizionarla a pixel bob_X.
	; Strategia: estendi a 32 bit (bitmask << 16), poi shifta a destra di (bob_X mod 16).
	; Risultato: D1.long = pattern 32-bit dove i bit della barra sono a posizione (bob_X mod 16).
	;
	; IMPORTANTE: la word ALTA di D1 puo' contenere garbage (resto di DIVU.W sopra).
	; Devo PULIRLA prima dello SWAP, altrimenti si presenta come "barra fantasma".
	ANDI.L	#$0000FFFF,D1				; pulisco la word alta (era il resto di DIVU)
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
	MULU.W	#BPSF_PITCH,D5						; D5.l = D3*48 (dest pitch)
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
	OR.L	D2,BPSF_PITCH(A1)			; riga D3+1 (dest pitch 48)
	BRA.S	.plane_next
.plane_off:
	; Plane spento: AND con NOT bitmask (spegne i pixel della barra)
	AND.L	D1,(A1)						; riga D3
	AND.L	D1,BPSF_PITCH(A1)			; riga D3+1 (dest pitch 48)
.plane_next:
	; Prossimo plane
	ADDA.L	#BG_PLANE_STRIDE,A1
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
* UpdatePlayerPhysics
*   Genera IntentY dalla fisica del platform, al posto dell'input verticale.
*   - Gravita': PlayerVelY += GRAVITY ogni frame, con cap a MAX_FALL.
*   - Salto: solo sul FRONTE di salita di UpNow (tasto appena premuto) E se il
*     player e' a terra -> PlayerVelY = JUMP_VEL (negativa = su), grounded = 0.
*     Cosi' si salta una volta per pressione e solo da terra.
*   - IntentY = PlayerVelY (spostamento verticale di questo frame).
*   PlayerGrounded viene aggiornato da UpdatePlayerWorldPos in base alle
*   collisioni verticali (giu' bloccato = a terra; su bloccato = testata).
*****************************************************************************
UpdatePlayerPhysics:
	MOVE.W	D0,-(SP)
	TST.W	GravityOn
	BEQ.S	.skipGrav			; gravita' OFF (8 direzioni): IntentY viene gia' dall'input (lockstep)
	; --- Gravita' (applicata solo in platform) ---
	MOVE.W	PlayerVelY,D0
	ADD.W	#GRAVITY,D0
	CMP.W	#MAX_FALL,D0
	BLE.S	.noCap
	MOVE.W	#MAX_FALL,D0			; clamp alla velocita' terminale
.noCap:
	MOVE.W	D0,PlayerVelY
	; --- Salto: fronte di salita di UpNow + player a terra ---
	TST.W	UpNow
	BEQ.S	.noJump					; tasto su non premuto
	TST.W	UpPrev
	BNE.S	.noJump					; era gia' premuto -> non e' un fronte
	TST.W	PlayerGrounded
	BEQ.S	.noJump					; in aria -> niente salto
	MOVE.W	#JUMP_VEL,PlayerVelY	; SALTO! (sovrascrive la gravita' di questo frame)
	CLR.W	PlayerGrounded
.noJump:
	MOVE.W	UpNow,UpPrev			; memorizza stato per il prossimo fronte
	MOVE.W	PlayerVelY,IntentY		; IntentY = velocita' verticale corrente
.skipGrav:
	MOVE.W	(SP)+,D0
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
	CLR.W	PlayerGrounded			; movimento verticale riuscito -> player in aria
	BRA.S	.skipY
.y_blocked:
	CLR.W	ScrllY					; sincronizza camera: niente scroll su Y
	; --- stato verticale: giu' bloccato = a terra, su bloccato = testata ---
	MOVE.W	IntentY,D0
	BPL.S	.y_land					; IntentY>=0 (scendeva) -> atterrato sul tile
	CLR.W	PlayerVelY				; IntentY<0 (saliva) -> testata sul soffitto
	BRA.S	.skipY
.y_land:
	MOVE.W	#1,PlayerGrounded		; piedi su tile solido -> puo' saltare
	CLR.W	PlayerVelY
.skipY:

	; Sync bob_WorldX/Y del Player con le variabili globali
	; (cosi' Combattimento e altre routine possono leggerle uniformemente)
	LEA		Player,A2	
	MOVE.W	PlayerWorldX,bob_WorldX(A2)
	MOVE.W	PlayerWorldY,bob_WorldY(A2)

	MOVEM.L	(SP)+,D0-D2/A2
	RTS

*****************************************************************************
* ComputeCameraFollowY
*   Solo in modalita' platform (GravityOn=1): scroll verticale per inseguire
*   il player. In 8-direzioni (GravityOn=0) NON tocca nulla: ScrllY e
*   VScrollStep sono gia' impostati dall'input (lockstep a 1px).
*
*   Passo adattivo (auto-riallineamento):
*   - se PixelOffY e' multiplo di CAM_STEP_Y -> passo pieno CAM_STEP_Y
*   - altrimenti -> passo 1px (nella direzione dell'inseguimento) finche'
*     PixelOffY torna allineato. Serve perche' il refill richiede passi
*     multipli che mantengano PixelOffY allineato; entrando da 8-direzioni
*     (passo 1) PixelOffY puo' essere qualsiasi, e cosi' si riallinea liscio.
*   VScrollStep viene impostato uguale a |ScrllY| cosi' lo shift combacia.
*
*   errore = (PlayerWorldY - CENTER_Y) - (TileY*16 + PixelOffY)
*   |errore| <= CAM_DEADZONE_Y -> fermo.
*****************************************************************************
ComputeCameraFollowY:
	MOVEM.L	D0-D2,-(SP)
	TST.W	GravityOn
	BEQ.W	.skip					; 8-direzioni: gestito dall'input (lockstep)
	MOVE.W	TileY,D0
	LSL.W	#4,D0					; TileY*16
	ADD.W	PixelOffY,D0			; D0 = CameraY corrente (px)
	MOVE.W	PlayerWorldY,D1
	SUB.W	#CENTER_Y,D1			; D1 = CameraY target
	SUB.W	D0,D1					; D1 = errore (target - corrente)
	CMP.W	#CAM_DEADZONE_Y,D1
	BGT.S	.needDown				; errore > +deadzone -> giu'
	CMP.W	#-CAM_DEADZONE_Y,D1
	BLT.S	.needUp					; errore < -deadzone -> su
	CLR.W	ScrllY					; dentro la dead-zone -> fermo
	BRA.S	.skip
.needDown:
	MOVE.W	PixelOffY,D2
	AND.W	#CAM_STEP_Y-1,D2		; PixelOffY mod CAM_STEP_Y (CAM_STEP_Y e' potenza di 2)
	BNE.S	.down1					; non allineato -> 1px per riallineare
	MOVE.W	#CAM_STEP_Y,VScrollStep
	MOVE.W	#CAM_STEP_Y,ScrllY
	BRA.S	.skip
.down1:
	MOVE.W	#1,VScrollStep
	MOVE.W	#1,ScrllY
	BRA.S	.skip
.needUp:
	MOVE.W	PixelOffY,D2
	AND.W	#CAM_STEP_Y-1,D2
	BNE.S	.up1
	MOVE.W	#CAM_STEP_Y,VScrollStep
	MOVE.W	#-CAM_STEP_Y,ScrllY
	BRA.S	.skip
.up1:
	MOVE.W	#1,VScrollStep
	MOVE.W	#-1,ScrllY
.skip:
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
	MULU.W	#BPSF_PITCH,D0			; D0 = Y * 48 (dest pitch)
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
	MOVE.W	#BPSF_PITCH-4,$60(A6)	; BLTCMOD = 48 - 4 (sfondo = dest, pitch 48 byte)
	MOVE.W	#36,$62(A6)				; BLTBMOD = 40 - 4 (BOB, pitch 40 byte)
	MOVE.W	#0,$64(A6)				; BLTAMOD = 4 - 4 (MASK fissa 4 byte/riga)
	MOVE.W	#BPSF_PITCH-4,$66(A6)	; BLTDMOD = 48 - 4 (destinazione, pitch 48 byte)
 
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
	ADD.L	#BG_PLANE_STRIDE,A1		; prossimo plane destinazione BPSFONDO (con padding)

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

; Palette AGA del title screen (256 colori, format $00RRGGBB long).
; Caricata via CPU in LoadAGAPalette256 prima di mostrare la title.
title_pal:
	incbin	"title.pal"

CurrentDisplay:
	dc.l	BPSFONDO_A	; bitplane attualmente visibili
CurrentDraw:	
	dc.l	BPSFONDO_B	; bitplane su cui disegnare

; Dark plane (6° bitplane EHB): paralleli a CurrentDisplay/Draw
CurrentDarkDisplay:
	dc.l	DARKPLANE_A
CurrentDarkDraw:
	dc.l	DARKPLANE_B

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
;   tile:   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
	dc.b	0,	0,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	0,	0,	0,	0
;   tile:  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30  31
	dc.b	0,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1
;   tile:  32  33  34  35  36  37  38  39  40  41  42  43  44  45  46  47
	dc.b	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1
;   tile:  48  49  50  51  52  53  54  55  56  57  58  59  60  61  62  63
	dc.b	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1

	even	; padding per allineamento word
*****************************************************************************
* Disegno la mappa con le tiles 
*****************************************************************************

MAPPA:
;			 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 ;	 
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;0
	dc.w	 0,32,33,34,35,36,32,33,34,35,36,32,33,34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;1
	dc.w	 0, 2, 3, 0, 0, 0, 0, 0, 0,17,18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;2
	dc.w	 0, 4, 5, 0, 0, 0, 0, 0, 0,19,20, 0, 0, 0, 0, 0,12,13,14, 0, 0, 0, 0, 0	;3
	dc.w	 0, 6, 7, 0, 0, 0, 0, 0, 0,21,22, 0, 0, 0, 0, 0,32,33,34, 0, 0, 0, 0, 0	;4
	dc.w	 0, 8, 9, 0, 0, 0, 0, 0, 0,23,24, 0,12,13,14,15, 0, 0, 0, 0, 0, 0, 0, 0	;5
	dc.w	 0,10,11, 0, 0, 0, 0, 0, 0, 0,25,26,32,33,34,35, 0, 0, 0, 0, 0, 0, 0, 0	;6
	dc.w	 0, 2, 3,12,13,14,15,16, 0, 0,27,28, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;7
	dc.w	 0, 4, 5,32,33,34,35,36, 0, 0,29,30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;8
	dc.w	 0, 6, 7, 0, 0, 0, 0, 0, 0, 0,31,36, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;9
	dc.w	 0, 8, 9, 0, 0, 0, 0, 0, 0, 0,37,38, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;10
	dc.w	 0,10,11,12,13,14,15,16,12,13,14,15,16,12,13,14,15,16,12,13,14,15,16, 0	;11
	dc.w	 0,35,36,32,33,34,35,36,32,33,34,35,36,32,33,34,35,36,32,33,34,35,36, 0	;12
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;13
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;14
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;15
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;16
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;17
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;18
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;19
	dc.w	 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;20
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
PlayerWorldY:	dc.w	32
; Intent dell'utente (movimento desiderato): -1, 0, +1
; Distinto da ScrllX/Y che invece e' "camera scroll" (gated dal centro schermo).
; PlayerWorldX += IntentX sempre; ScrllX = IntentX solo se player al centro.
IntentX:		dc.w	0
IntentY:		dc.w	0

; --- Stato fisica platform ---
PlayerVelY:		dc.w	0		; velocita' verticale (+ = giu', px/frame)
PlayerGrounded:	dc.w	0		; 1 = piedi a terra (puo' saltare), 0 = in aria
UpNow:			dc.w	0		; tasto SU/salto premuto in questo frame
UpPrev:			dc.w	0		; stato del tasto SU nel frame precedente (per il fronte)
GravityOn:		dc.w	1		; 1 = platform (gravita'), 0 = movimento 8 direzioni (toggle col tasto G)
VScrollStep:	dc.w	CAM_STEP_Y	; passo scroll verticale RUNTIME (CAM_STEP_Y in platform, 1 in 8-direzioni)

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
NightMode:	dc.b 	0			; 0 = giorno, 1 = notte (toggle col tasto N)
NightKeyPrev:	dc.b 	0			; stato precedente del tasto N (per edge detect)
NightModePrev:	dc.b	0			; ultimo valore "applicato" di NightMode (per rilevare cambi)
MusicOn:		dc.b	0			; 0 = music off, 1 = music on (toggle col tasto M)
MusicKeyPrev:	dc.b	0			; stato precedente del tasto M (per edge detect)
MusicOnPrev:	dc.b	0			; ultimo valore "applicato" di MusicOn
GravKeyPrev:	dc.b	0			; stato precedente del tasto G (per edge detect)

	EVEN
; ----- Falò sprite hardware -----
FaloAnimFrame:	dc.w	0			; frame corrente (0..5)
FaloAnimDelay:	dc.w	0			; contatore frame per animazione (incrementa ogni VBL)

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

	EVEN
; ----- SfxStructure per i 4 effetti sonori (passate a _mt_playfx) -----
; Layout (vedi ptplayer.i):
;   dc.l sfx_ptr   ; puntatore campione in CHIP RAM (etichetta in SpritesData)
;   dc.w sfx_len   ; lunghezza in WORD (= byte/2)
;   dc.w sfx_per   ; period Paula (vedi costanti SFX_PER_*)
;   dc.w sfx_vol   ; volume 0..64
;   dc.b sfx_cha   ; canale 0..3, oppure -1 = auto
;   dc.b sfx_pri   ; priorita' 1..127
SfxSparo:
	dc.l	SparoSample
	dc.w	SPARO_LEN			; (SparoSampleEnd-SparoSample)/2
	dc.w	SFX_PER_DEFAULT
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_SPARO

SfxHitEnemy:
	dc.l	HitEnemySample
	dc.w	HITENEMY_LEN 		; (HitEnemySampleEnd-HitEnemySample)/2
	dc.w	SFX_PER_DEFAULT
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_HITENEMY

SfxHitPlayer:
	dc.l	HitPlayerSample
	dc.w	HITPLAYER_LEN 		; (HitPlayerSampleEnd-HitPlayerSample)/2	
	dc.w	SFX_PER_DEFAULT
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_HITPLAYER

SfxEnemyDeath:
	dc.l	EnemyDeathSample
	dc.w	ENEMYDEATH_LEN 		; (EnemyDeathSampleEnd-EnemyDeathSample)/2
	dc.w	SFX_PER_DEFAULT
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_DEATH

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

; ============================================================================
; TITLE COPPERLIST - 8 bitplane AGA, lores 320x256, palette caricata via CPU.
; I puntatori BPL1..8PT (etichette TitleBPL_*) vengono patchati a runtime
; in ShowTitle a partire da title_bpl (10240 byte per plane, layout SEQUENTIAL).
; ============================================================================
	cnop	0,4
TitleCopperList:
	; Forza FMODE = $03 (BPL32+BPAGEM) all'inizio del frame, in caso qualcuno
	; (PT Player IRQ, OS, ecc.) lo abbia resettato. FMODE va impostato PRIMA
	; di abilitare BPL DMA per garantire il fetch a 64-bit allineato.
	dc.w	$01fc,$0003			; FMODE = BPL32 + BPAGEM (64-bit fetch)
	dc.w	$0100,$0211			; BPLCON0: BPU3=1 (8 BPL) + COLOR + ECSENA (no UHRES)
	dc.w	$0102,$0000			; BPLCON1
	dc.w	$0104,$0024			; BPLCON2: PF2P=4, PF1P=4 (come gioco)
	dc.w	$0106,$0000			; BPLCON3: banca 0, LOCT=0, no offset
	dc.w	$010c,$0000			; BPLCON4 = 0 (sprite a colori OCS standard 16-31)
	dc.w	$0108,$0000			; BPL1MOD (sequential layout)
	dc.w	$010a,$0000			; BPL2MOD
	dc.w	$0092,$0028			; DDFSTRT lores 8 BPL AGA FMODE=3
	dc.w	$0094,$00a8			; DDFSTOP (5 fetch FMODE=3 allineati)
	dc.w	$008e,$2c81			; DIWSTRT
	dc.w	$0090,$2cc1			; DIWSTOP
TitleBPL_0:	dc.w	$00e0,$0000,$00e2,$0000	; BPL1PT (high, low)
TitleBPL_1:	dc.w	$00e4,$0000,$00e6,$0000	; BPL2PT
TitleBPL_2:	dc.w	$00e8,$0000,$00ea,$0000	; BPL3PT
TitleBPL_3:	dc.w	$00ec,$0000,$00ee,$0000	; BPL4PT
TitleBPL_4:	dc.w	$00f0,$0000,$00f2,$0000	; BPL5PT
TitleBPL_5:	dc.w	$00f4,$0000,$00f6,$0000	; BPL6PT
TitleBPL_6:	dc.w	$00f8,$0000,$00fa,$0000	; BPL7PT
TitleBPL_7:	dc.w	$00fc,$0000,$00fe,$0000	; BPL8PT
	; Past line 255 + wait V=300, poi spegne i bitplane
	dc.w	$FFDF,$FFFE
	dc.w	$2C01,$FF00
	dc.w	$0100,$0201			; BPLCON0 = 0 BPL + ECSENA
	dc.w	$FFFF,$FFFE			; FINE COPPERLIST

CopperList:
	; Il gioco gira a 6 bitplane lores con fetch AGA a 64 bit (FMODE=$0003) per
	; lasciare piu' banda DMA a blitter/CPU. Il "fetch-ahead" a 64 bit in fondo
	; allo schermo legge oltre i piani: per renderlo innocuo i 5 piani di
	; BPSFONDO sono distanziati da BG_PLANE_STRIDE (con righe di padding vuote
	; tra un piano e l'altro), cosi' il prefetch pesca righe blank invece dei
	; dati del piano successivo. Vedi BG_PLANE_STRIDE / BG_PAD_ROWS.
	dc.w	$01fc,$0003			; FMODE = BPL32 + BPAGEM (fetch 64-bit AGA)
	dc.w	$0100,%0110001010000001		; BPLCON0: 6 bitplane, EHB on, ECSENA on
				  ;5432109876543210	
; bit 15		HiRes
; bit 14-12		Numero di Bitplanes
; bit 11		HAM
; bit 10 		Dual Playfield
; bit 9			Color burst
; bit 8			GENLOCK AUDIO
; bit 7			EHB (Extra Half-Brite) — il 6° plane dimezza luminosita'
; bit 6-4		non utilizzati
; bit 3			Light Pen
; bit 2			LACE
; bit 1			External Resync
; bit 0 		non utilizzato (ECSENA per AGA palette)

	dc.w	$102,0			; BplCon1
	dc.w	$104,$0024		; BPLCON2 = PF2P=4, PF1P=4 (sprite 0-3 davanti al playfield)
							; bit 5-3 = PF2P, bit 2-0 = PF1P (4 = primi 4 sprite davanti)
	; Nota: BPLCON3 e BPLCON4 NON sono qui perche' la PALETTE section piu' avanti
	; gia' imposta BPLCON3 (con LOCT alternato) e nessuno modifica BPLCON4 a runtime.
	; Settarli qui rompe la palette degli sprite hardware (es. falo' diventa verde).
	dc.w	$108,BPSF_PITCH-40	; BPL1MOD = 48-40 = 8 (pitch 48, mostra 20 word/riga)
	dc.w	$10A,BPSF_PITCH-40	; BPL2MOD = 48-40 = 8
	dc.w 	$0092,$0038,$0094,$00b8 ; DdfStrt - DdfStop (5 fetch FMODE=3 allineati)
	dc.w	$008e,$2c81,$0090,(($2C-CUT_BOTTOM_ROWS)<<8)|$C1	; DiwStrt - DiwStop (display 256-CUT righe)

BitPlaneTiles:
	dc.w 	$e0,$0000,$e2,$0000	;primo   bitplane - BPL0PT
	dc.w 	$e4,$0000,$e6,$0000	;secondo bitplane - BPL1PT
	dc.w 	$e8,$0000,$ea,$0000	;terzo   bitplane - BPL2PT
	dc.w 	$ec,$0000,$ee,$0000	;quarto  bitplane - BPL3PT
	dc.w 	$f0,$0000,$f2,$0000	;quinto  bitplane - BPL4PT
	dc.w 	$f4,$0000,$f6,$0000	;sesto   bitplane - BPL5PT (EHB dark mask)

Sprites:
	dc.w	$120,0,$122,0			; SPR0PT (InitSprites scrive l'indirizzo)
	dc.w	$124,0,$126,0			; SPR1PT
	dc.w	$128,0,$12a,0			; SPR2PT
	dc.w	$12c,0,$12e,0			; SPR3PT
	dc.w	$130,0,$132,0			; SPR4PT
	dc.w	$134,0,$136,0			; SPR5PT
	dc.w	$138,0,$13a,0			; SPR6PT
	dc.w	$13c,0,$13e,0			; SPR7PT

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
	; AGA BPLCON4:
	;   bit 15-8 = BPLAM (XOR sul bitplane color index, 8 bit)
	;   bit 7-4  = ESPRM (XOR sprite EVEN, 4 bit alti)
	;   bit 3-0  = OSPRM (XOR sprite ODD,  4 bit alti)
	; Servono sprite a COLOR17-19 (arancione): ESPRM=$1, OSPRM=$1.
	; BPLAM=$00 lascia il bitplane invariato.
	dc.w	$010c,$0011			; BPLCON4: BPLAM=0, ESPRM=$1, OSPRM=$1
	; AGA single-PF: BPLCON4 bit 7-0 sono CONDIVISI tra OSPRM (sprite ODD) e
	; BPLAM (bitplane). Quindi non si puo' avere sprite ODD a COLOR16-31
	; E bitplane normale contemporaneamente.
	; Compromesso scelto:
	;   ESPRM=$10 -> sprite EVEN (SPR0 falo') a COLOR17-19 (arancione)
	;   OSPRM=$00 -> sprite ODD (SPR1 proiettile) resta a COLOR1-3 (verdino)
	;   BPLAM=$00 -> bitplane normale (tile colors OK)
;	dc.w	$010c,$1000			; BPLCON4 = ESPRM=$10, OSPRM=$00

	; ----- Blocco 1: nibble ALTI (LOCT=0) -----
	dc.w	$0106,$0c00			; BPLCON3 = LOCT=0

	dc.w 	$0180,$0000,$0182,$0fff,$0184,$0040,$0186,$0070	
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880	
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	dc.w 	$0198,$000f,$019a,$070f,$019c,$0c0e,$019e,$0c08
	dc.w 	$01a0,$0d00,$01a2,$0f70,$01a4,$0ff0,$01a6,$0fca	
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

; include dell'effetto di gradiente cielo, che e' parte della copperlist perche' 
; scrive a BPL1PT..BPL5PT.
	include "CieloCopper.i"		; gradiente cielo 

; Spegne il DMA bitplane in fondo allo schermo. Senza questo, WinUAE
; (e hardware reale in overscan) continua a fetchare oltre BPSFONDO
; (che ha pitch 40) trovando SFONDOGRANDE (pitch 48): legge "a mosaico"
; pezzi di righe diverse -> riga parziale/sfarfallante in fondo, visibile
; soprattutto dove la luce notturna la illumina.
;
; IMPORTANTE: lo spegnimento va fatto a FINE scanline 299 (dopo che la
; riga 255 e' gia' stata prelevata e mostrata: il DIW orizzontale finisce
; a H=$C1, e DDFSTOP e' a $b8) ma PRIMA che inizi il fetch della scanline
; 300. Se invece si aspetta l'INIZIO di V=300 (H=$00), il fetch della
; scanline 300 (DDFSTART=$38) parte prima che il copper - che ha priorita'
; DMA inferiore al bitplane - riesca a scrivere BPLCON0=0: la quantita' di
; over-fetch che trapela dipende dalla contesa di bus (sprite/blitter) e
; varia da frame a frame -> sfarfallio. Spegnendo a V=299/H=$E0 il fetch
; della riga di over-fetch non avviene MAI (race-proof).
;
; Il copper VP e' 8 bit: per V>=256 serve il "trick" past-line-255
; (WAIT $FFDF,$FFFE) che fa scattare il flip-flop interno V8.
	dc.w	$FFDF,$FFFE		; past end of line 255 (arma V8)
	dc.w	$2BE1,$FFFE		; WAIT V=299 ($12b), H>=$E0 (dopo fine riga, prima di V=300)
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
	ds.b	5*BG_PLANE_STRIDE	; 5 piani con padding inter-piano (vedi BG_PAD_ROWS)

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
BPSFONDO_B:
	ds.b	5*BG_PLANE_STRIDE	; idem

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
SFONDOGRANDE:
	ds.b	5*SFONDO_PLANE_SIZE	; 5 plane * 48 byte/riga * 288 righe = 69120 byte

	cnop	0,8

; Dark plane sui buffer di display (= cosa viene effettivamente mostrato).
; Double-buffered come BPSFONDO_A/B. Riempito ad ogni frame da UpdateDarkPlane:
; 1. Fill con $00 (giorno) o $FF (notte)
; 2. Scansione viewport: per ogni tile=TILE_LAMPIONE, disegna cerchio di luce

DARKPLANE_A:
	ds.b	BPSF_PITCH*DARK_ROWS	; 256 righe visibili + padding anti over-fetch (pitch 48)

	cnop	0,8
DARKPLANE_B:
	ds.b	BPSF_PITCH*DARK_ROWS

	cnop	0,8
; Maschera del disco di luce (bit=1 dentro). Sorgente A del blitter in
; DisegnaCerchioLuceBlitter. In chip RAM (la DMA del blitter la legge).
; Costruita una volta al boot da BuildLightMask.
LightMask:
	ds.b	LIGHT_MASK_STRIDE*LIGHT_MASK_H	; 18 byte * 128 righe = 2304 byte

; Maschera dell'OMINO: 1 bitplane (10240 byte = 40*256) calcolata al boot
; come OR dei 5 bitplane dello spritesheet originale.
; Il blitter la usa come canale B per il cookie-cut nei BOB.
OMINO_MASK:
	ds.b	40*256			; 1 plane mask (stesso pitch di OMINO)

	SECTION	SpritesData,data_c
	cnop	0,8				; allineamento sprite
;----------------------------------------------------------------------------
; MOD ProTracker - DEVE essere in chip RAM (data_c) per Paula DMA
;----------------------------------------------------------------------------
	cnop	0,4
ANTIRIAD_MOD:
	incbin	"antiriad.amiga.mod"

;----------------------------------------------------------------------------
; Title screen image: 8 bitplane AGA, 320x256, sequential layout.
; DEVE essere in CHIP RAM per la display DMA.
;----------------------------------------------------------------------------
	cnop	0,8					; allineamento AGA FMODE=3
title_bpl:
	incbin	"title.raw"

;----------------------------------------------------------------------------
; Sound effects samples (8-bit signed PCM raw mono).
; DEVONO essere in CHIP RAM per il DMA audio Paula.
; Lunghezza calcolata a compile-time da (End-Start)/2 nelle SfxStructure,
; quindi puoi sostituire i .raw con sample di lunghezza diversa senza
; toccare il sorgente: basta che il file abbia un numero pari di byte.
;----------------------------------------------------------------------------
	cnop	0,4
SparoSample:
	incbin	"Sparo.raw"
SparoSampleEnd:
SPARO_LEN		EQU	(SparoSampleEnd-SparoSample)/2

	cnop	0,4
HitEnemySample:
	incbin	"HitEnemy.raw"
HitEnemySampleEnd:
HITENEMY_LEN	EQU	(HitEnemySampleEnd-HitEnemySample)/2

	cnop	0,4
HitPlayerSample:
	incbin	"HitPlayer.raw"
HitPlayerSampleEnd:
HITPLAYER_LEN	EQU	(HitPlayerSampleEnd-HitPlayerSample)/2

	cnop	0,4
EnemyDeathSample:
	incbin	"EnemyDeath.raw"
EnemyDeathSampleEnd:
ENEMYDEATH_LEN	EQU	(EnemyDeathSampleEnd-EnemyDeathSample)/2

	cnop	0,8
; ============================================================================
; Sprite hardware FUOCO - 6 frame di animazione
; Ogni frame e' una struttura sprite indipendente:
;   - 2 word header (SPRPOS, SPRCTL) settati a runtime
;   - 16 righe x 2 word interleaved (plane0, plane1) = 32 word = 64 byte dati
;   - 2 word terminator (0, 0)
; Totale per frame: 2 + 32 + 2 = 36 word = 72 byte
;
; A runtime, SPR0PT puntera' a uno dei FuocoFrame_X in base a FaloAnimFrame.
; ============================================================================
FuocoFrame_0:
	dc.w	$0000,$0000				; SPRPOS, SPRCTL (runtime)
	incbin	"Fuoco_Data.raw",0,64	; offset 0, 64 byte (frame 0)
	dc.w	0,0						; terminator

	cnop	0,4
FuocoFrame_1:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",64,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_2:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",128,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_3:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",192,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_4:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",256,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_5:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",320,64
	dc.w	0,0

	cnop	0,8
; Sprite vuoto per disattivare gli sprite non usati (SPR1..SPR7)
EmptySprite:
	dc.w	0,0				; SPRPOS, SPRCTL
	dc.w	0,0				; terminator

	cnop	0,8
; ============================================================================
; Sprite hardware PROIETTILE (BulletSprite, usa SPR1)
; Struttura: 2 word header + 16 righe x 2 word interleaved + 2 word terminator
; Colori: usa SPR1 -> stessa palette di SPR0 (COLOR17/18/19)
;
; PLACEHOLDER: piccolo "+" 4x4 con bordo, da sostituire con il tuo sprite.
; Layout dati per riga: plane0_word, plane1_word
;   plane0=bit basso (colore 1, 2)
;   plane1=bit alto (colore 2, 3)
;   colore 0 = trasparente
;
; Frame placeholder corrente: un piccolo cerchio luminoso 4x4 al centro.
;   bit 6,7,8,9 attivi sulle righe 6,7,8,9 = posizione (6,6)-(9,9) del 16x16
;   = 4 colore 3 (giallo brillante)
; ============================================================================
BulletSprite:
	dc.w	$0000,$0000				; SPRPOS, SPRCTL (runtime)
	; 16 righe di dati interleaved (plane0, plane1)
	; Pattern placeholder: piccolo "+" giallo al centro (colore 3)
	dc.w	$0000,$0000				; riga 0
	dc.w	$0000,$0000				; riga 1
	dc.w	$0000,$0000				; riga 2
	dc.w	$0000,$0000				; riga 3
	dc.w	$0000,$0180				; riga 4 - pixel 7,8 (colore 2)
	dc.w	$0000,$03C0				; riga 5 - pixel 6,7,8,9 (colore 2)
	dc.w	$0180,$07E0				; riga 6 - 7,8 col 1 + 5-A col 3
	dc.w	$03C0,$0FF0				; riga 7 - 6-9 col 1 + 4-B col 3
	dc.w	$03C0,$0FF0				; riga 8 - simmetrica
	dc.w	$0180,$07E0				; riga 9
	dc.w	$0000,$03C0				; riga A
	dc.w	$0000,$0180				; riga B
	dc.w	$0000,$0000				; riga C
	dc.w	$0000,$0000				; riga D
	dc.w	$0000,$0000				; riga E
	dc.w	$0000,$0000				; riga F
	dc.w	$0000,$0000				; terminator

	SECTION	Entities,BSS

	EVEN
Player:
	ds.b	bob_Length		  		; alloca la struct player
Enemies:
	ds.b	bob_Length*ENEMY_COUNT	; arrey di nemici
;----------------------------------------------------------------------------
; PT PLAYER di Frank Wille (rinominato ptplayer.i per evitare la
; compilazione automatica dell'extension vscode-amiga-assembly).
;
; IMPORTANTE: ptplayer.i NON dichiara una propria SECTION code, quindi
; eredita la SECTION corrente. Bisogna riportare la SECTION corrente in
; CODE prima dell'include, altrimenti il codice del player finisce
; in BSS e crasha appena chiamato.
;----------------------------------------------------------------------------
	SECTION	PTPlayerCode,CODE

	include	"ptplayer.i"

	end

*****************************************************************************