; Player.i - Fisica e posizione del player
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* AggiornaFisicaPlayer
*   Genera IntentY dalla fisica del platform, al posto dell'input verticale.
*   - Gravita': bob_VelY += GRAVITA_88 ogni frame, con cap a MAX_FALL_88.
*   - Salto: solo sul FRONTE di salita di UpNow (tasto appena premuto) E se il
*     player e' a terra -> bob_VelY = JUMP_VEL_88 (negativa = su), grounded = 0.
*     Cosi' si salta una volta per pressione e solo da terra.
*   - IntentY = i pixel INTERI che escono dall'accumulatore 8.8 (puo' essere 0).
*   bob_Grounded viene aggiornato da AggPosizioneGlobalePlayer in base alle
*   collisioni verticali (giu' bloccato = a terra; su bloccato = testata).
AggiornaFisicaPlayer:
	MOVEM.L	D0-D1,-(SP)
	TST.W	GravityOn
	BEQ.S	.skipGrav			; gravita' OFF (8 direzioni): IntentY viene gia' dall'input (lockstep)
	; --- Gravita' (applicata solo in platform) ---
	MOVE.W	Player+bob_VelY,D0
	ADD.W	#GRAVITA_88,D0
	CMP.W	#MAX_FALL_88,D0
	BLE.S	.noCap
	MOVE.W	#MAX_FALL_88,D0			; set alla velocita' terminale
.noCap:
	MOVE.W	D0,Player+bob_VelY
	; --- Salto: fronte di salita di UpNow + player a terra ---
	TST.W	UpNow
	BEQ.S	.noJump					; tasto su non premuto
	TST.W	UpPrev
	BNE.S	.noJump					; era gia' premuto -> non e' un fronte
	TST.W	Player+bob_Grounded
	BEQ.S	.noJump					; in aria -> niente salto
	MOVE.W	#JUMP_VEL_88,Player+bob_VelY	; SALTO! (sovrascrive la gravita' di questo frame)
	CLR.W	Player+bob_FracY				; lo slancio riparte da un pixel netto
	CLR.W	Player+bob_Grounded
.noJump:
	MOVE.W	UpNow,UpPrev			; memorizza stato per il prossimo fronte
	; IntentY = i PIXEL INTERI che escono dall'accumulatore in questo frame.
	; Con la gravita' frazionaria ci sono frame in cui non ne esce nessuno e
	; IntentY vale 0: AggPosizioneGlobalePlayer lo intercetta con il suo
	; "BEQ .skipY" e salta tutto il blocco Y, quindi il player non viene
	; scambiato per atterrato restando a mezz'aria.
	MOVE.W	Player+bob_FracY,D0
	ADD.W	Player+bob_VelY,D0
	MOVE.W	D0,D1
	ASR.W	#8,D1					; pixel interi, con segno
	MOVE.W	D1,IntentY
	AND.W	#$00FF,D0				; resta la frazione per il frame dopo
	MOVE.W	D0,Player+bob_FracY
.skipGrav:
	MOVEM.L	(SP)+,D0-D1
	RTS
* AggPosizioneGlobalePlayer (Fase 2 + Fase 4)
*   Aggiorna bob_WorldX/Y in base a ScrllX/Y (intent dell'utente).
*   setta il risultato in modo che il BOB (16x16, blittato come 2 word)
*   non esca mai dal bitplane visibile.
*   Limiti calcolati per evitare wrap-around del blit:
*     bob_X max = (viewport_width - BOB_width) = 320 - 16 = 304
*     bob_Y max = (viewport_height - BOB_height) = 256 - 16 = 240
*   bob_WorldX max = bob_X_max + CameraX_max = 304 + (TILEXMAX*16) = 304 + 32 = 336
*   bob_WorldY max = bob_Y_max + CameraY_max = 240 + (TILEYMAX*16) = 240 + 64 = 304
* AggPosizioneGlobalePlayer (Fase 2 + Fase 4 + Collisioni)
*   Aggiorna bob_WorldX/Y in base a IntentX/IntentY, applicando:
*   1) Collision detection contro le tile bloccate (sliding X poi Y)
*   2) Fissa ai bordi della mappa
AggPosizioneGlobalePlayer:
	MOVEM.L	D0-D2/A2,-(SP)

	; ASSE X: tenta di muovere solo X (Y invariato)
	MOVE.W	IntentX,D0
	BEQ.S	.skipX					; se intent=0, salta
	ADD.W	Player+bob_WorldX,D0			; D0 = nuova X candidata
	; Fissa ai bordi mappa
	BPL.S	.x_setHi
	MOVEQ	#0,D0					; X<0 -> 0
	BRA.S	.x_check
.x_setHi:
	CMP.W	#PLAYER_MAX_X,D0
	BLE.S	.x_check
	MOVE.W	#PLAYER_MAX_X,D0		; X>max -> max
.x_check:
	; D0 = nuova X candidata, controllo collisioni
	MOVE.W	Player+bob_WorldY,D1			; Y attuale (non ancora cambiato)
	BSR.W	IsBoxBlocked
	BNE.S	.x_blocked				; collide con tile, rifiuta movimento X
	; Controllo collision con i nemici (player NON puo' entrare in un nemico)
	MOVE.L	#0,A2					; A2=0 -> non escludere nessun BOB
	BSR.W	IsOverlapEnemies
	BNE.S	.x_blocked				; overlap con nemico -> rifiuta
	; Movimento X accettato.
	CMP.W	Player+bob_WorldX,D0
	BEQ.S	.x_blocked				; non si e' mosso (set) -> azzera ScrllX
	MOVE.W	D0,Player+bob_WorldX
	BRA.S	.skipX
.x_blocked:
	CLR.W	ScrllX					; sincronizza camera: niente scroll su X

.skipX:

	; ASSE Y: tenta di muovere solo Y (X eventualmente gia' aggiornata)
	MOVE.W	IntentY,D1
	BEQ.S	.skipY
	ADD.W	Player+bob_WorldY,D1			; D1 = nuova Y candidata
	; Fissa ai bordi mappa
	BPL.S	.y_setHi
	MOVEQ	#0,D1
	BRA.S	.y_check
.y_setHi:
	CMP.W	#PLAYER_MAX_Y,D1
	BLE.S	.y_check
	MOVE.W	#PLAYER_MAX_Y,D1
.y_check:
	; D1 = nuova Y candidata, controllo collisioni
	MOVE.W	Player+bob_WorldX,D0			; X attuale (eventualmente gia' aggiornata)
	BSR.W	IsBoxBlocked
	BNE.S	.y_blocked				; collide con tile, rifiuta movimento Y
	; Controllo collision con i nemici
	MOVE.L	#0,A2					; A2=0 -> non escludere nessun BOB
	BSR.W	IsOverlapEnemies
	BNE.S	.y_blocked				; overlap con nemico -> rifiuta
	CMP.W	Player+bob_WorldY,D1
	BEQ.S	.y_blocked				; non si e' mosso (set) -> azzera ScrllY
	MOVE.W	D1,Player+bob_WorldY
	CLR.W	Player+bob_Grounded			; movimento verticale riuscito -> player in aria
	BRA.S	.skipY
.y_blocked:
	CLR.W	ScrllY					; sincronizza camera: niente scroll su Y
	; --- stato verticale: giu' bloccato = a terra, su bloccato = testata ---
	MOVE.W	IntentY,D0
	BPL.S	.y_land					; IntentY>=0 (scendeva) -> atterrato sul tile
	CLR.W	Player+bob_VelY				; IntentY<0 (saliva) -> testata sul soffitto
	CLR.W	Player+bob_FracY				; con la velocita' si azzera anche la frazione
	BRA.S	.skipY
.y_land:
	MOVE.W	#1,Player+bob_Grounded		; piedi su tile solido -> puo' saltare
	CLR.W	Player+bob_VelY
	CLR.W	Player+bob_FracY
.skipY:

	MOVEM.L	(SP)+,D0-D2/A2
	RTS

* CalcolaInseguimentoCameraY
*   Solo in modalita' platform (GravityOn=1): scroll verticale per inseguire
*   il player. In 8-direzioni (GravityOn=0) NON tocca nulla: ScrllY e' gia'
*   impostato dall'input (lockstep a 1px).
*   Passo adattivo (auto-riallineamento):
*   - se PixelOffY e' multiplo di CAM_STEP_Y -> passo pieno CAM_STEP_Y
*   - altrimenti -> passo 1px (nella direzione dell'inseguimento) finche'
*     PixelOffY torna allineato. Serve perche' il refill richiede passi
*     multipli che mantengano PixelOffY allineato; entrando da 8-direzioni
*     (passo 1) PixelOffY puo' essere qualsiasi, e cosi' si riallinea liscio.
*   errore = (bob_WorldY - CENTER_Y) - (TileY*16 + PixelOffY)
*   |errore| <= CAM_DEADZONE_Y -> fermo.
CalcolaInseguimentoCameraY:
	MOVEM.L	D0-D2,-(SP)
	TST.W	GravityOn
	BEQ.W	.skip					; 8-direzioni: gestito dall'input (lockstep)
	MOVE.W	TileY,D0
	LSL.W	#4,D0					; TileY*16
	ADD.W	PixelOffY,D0			; D0 = CameraY corrente (px)
	MOVE.W	Player+bob_WorldY,D1
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
	MOVE.W	#CAM_STEP_Y,ScrllY
	BRA.S	.skip
.down1:
	MOVE.W	#1,ScrllY
	BRA.S	.skip
.needUp:
	MOVE.W	PixelOffY,D2
	AND.W	#CAM_STEP_Y-1,D2
	BNE.S	.up1
	MOVE.W	#-CAM_STEP_Y,ScrllY
	BRA.S	.skip
.up1:
	MOVE.W	#-1,ScrllY
.skip:
	MOVEM.L	(SP)+,D0-D2
	RTS
* AggiornaPlayerScreenPos
*   Calcola bob_X/bob_Y (coordinate schermo del player) come differenza
*   tra bob_WorldX/Y (coordinate mondo) e la posizione della camera.
*   CameraX_pixel = TileX * 16 + PixelOffX
*   CameraY_pixel = TileY * 16 + PixelOffY
*   bob_X = bob_WorldX - CameraX_pixel
*   bob_Y = bob_WorldY - CameraY_pixel
*   In Fase 1 bob_WorldX/Y NON cambiano, quindi bob_X/Y resteranno
*   costanti a (144, 120) come prima -> nessun cambiamento visivo.
AggiornaPlayerScreenPos:
	MOVEM.L	D0-D1/A0,-(SP)

	LEA		Player,A0

	; Calcola CameraX_pixel = TileX*16 + PixelOffX
	MOVE.W	TileX,D0
	LSL.W	#4,D0					; D0 = TileX * 16
	ADD.W	PixelOffX,D0			; D0 = CameraX_pixel
	; bob_X = bob_WorldX - CameraX
	MOVE.W	Player+bob_WorldX,D1
	SUB.W	D0,D1
	MOVE.W	D1,bob_X(A0)

	; Calcola CameraY_pixel = TileY*16 + PixelOffY
	MOVE.W	TileY,D0
	LSL.W	#4,D0					; D0 = TileY * 16
	ADD.W	PixelOffY,D0			; D0 = CameraY_pixel
	; bob_Y = bob_WorldY - CameraY
	MOVE.W	Player+bob_WorldY,D1
	SUB.W	D0,D1
	MOVE.W	D1,bob_Y(A0)

	MOVEM.L	(SP)+,D0-D1/A0
	RTS
