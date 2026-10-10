; Nemici.i - Intelligenza dei nemici
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

* AI_Patrol
*   Ronda generica a 8 direzioni: usa DirectionDeltas per calcolare il
*   movimento (dx, dy) in base a bob_Direzione. Quando bloccato, ruota
*   la direzione di 180° (dir XOR 4), che funziona per tutte le 8
*   direzioni: E<->W, SE<->NW, S<->N, SW<->NE.
*   INPUT: A0 = struct nemico
AI_Patrol:
	MOVEM.L	D0-D4/A0-A2,-(SP)
	MOVE.L	A0,A2					; A2 = nemico stesso (per esclusione overlap)

	; Indice nella tabella: bob_Direzione * 4 (4 byte per riga: 2 word)
	MOVE.W	bob_Direzione(A0),D2
	AND.W	#7,D2					; sicurezza:  0..7
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

* AI_Hunt
*   Inseguimento del Player con asse alternato:
*   1) Calcola dx, dy con il Player
*   2) Sceglie l'asse "preferito" (quello con differenza maggiore)
*   3) Tenta movimento sull'asse preferito
*   4) Se bloccato, prova sull'altro asse
*   5) Se entrambi bloccati, fermo
AI_Hunt:
	MOVEM.L	D0-D5/A0/A2,-(SP)
	MOVE.L	A0,A2

	; D3 = dx (player - nemico), D4 = dy
	MOVE.W	Player+bob_WorldX,D3
	SUB.W	bob_WorldX(A0),D3
	MOVE.W	Player+bob_WorldY,D4
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
