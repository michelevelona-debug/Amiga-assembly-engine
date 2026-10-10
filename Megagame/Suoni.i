; Suoni.i - Effetti sonori
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* PlaySfx
*   Suona un sound effect via PT Player.
*   INPUT:  A0 = puntatore SfxStructure (sfx_ptr/len/per/vol/cha/pri)
*   OUTPUT: nessuno (lo status del canale ritornato da _mt_playfx e' ignorato)
*   Preserva tutti i registri. Non richiede A6 settato dal chiamante.
PlaySfx:
	MOVEM.L	D0-D7/A0-A6,-(SP)
	LEA		$DFF000,A6
	JSR		_mt_playfx			; A0 = SfxStructure
	MOVEM.L	(SP)+,D0-D7/A0-A6
	RTS

* SuonoPassi
*   Decide se far sentire un passo in questo frame.
*   Regola voluta: si sente mentre il player CAMMINA, non mentre salta e non
*   da fermo. Unica eccezione l'ATTERRAGGIO, che suona anche se il player
*   arriva a terra senza spostarsi di lato.
*   "Cammina" = a terra E con la X MONDO cambiata rispetto al frame scorso.
*   Prima si guardava ScrllX, ed era sbagliato: ScrllX e' lo scroll della
*   CAMERA, e RettangoloScrollNelCentro lo azzera ogni volta che il player non
*   e' al centro dello schermo. Risultato, camminando senza far scorrere lo
*   sfondo non si sentiva nulla. bob_WorldX invece e' il player, non la
*   telecamera: cambia se e solo se ha camminato davvero, quindi resta zitto
*   anche contro un muro o al bordo mappa, dove il movimento viene rifiutato.
*   In 8 direzioni (GravityOn=0) il salto non esiste e bob_Grounded resta a
*   zero, quindi li' il requisito "a terra" si salta e basta il movimento.
SuonoPassi:
	MOVEM.L	D0-D1/A0,-(SP)

	; ----- atterraggio: fronte di salita di bob_Grounded -----
	MOVE.W	Player+bob_Grounded,D0
	MOVE.W	Player+bob_GroundedPrev,D1
	MOVE.W	D0,Player+bob_GroundedPrev			; sempre aggiornato, anche senza fronte
	TST.W	D0
	BEQ.S	.non_a_terra			; ora e' in aria
	TST.W	D1
	BEQ.S	.suona					; era in aria e ora no: ATTERRATO
.non_a_terra:

	; ----- passi mentre cammina -----
	TST.W	GravityOn
	BEQ.S	.controlla_moto			; 8 direzioni: niente salto, niente requisito
	TST.W	Player+bob_Grounded
	BEQ.S	.fermo					; in aria: silenzio
.controlla_moto:
	; si e' spostato in orizzontale rispetto al frame scorso?
	MOVE.W	Player+bob_WorldX,D0
	CMP.W	Player+bob_PrevX,D0
	BEQ.S	.fermo					; stessa X: silenzio

	SUBQ.W	#1,Player+bob_PassoTimer
	BGT.S	.fine					; non e' ancora ora
.suona:
	MOVE.W	#PASSO_INTERVALLO,Player+bob_PassoTimer
	LEA		SfxPasso,A0
	BSR.W	PlaySfx
	BRA.S	.fine

.fermo:
	; Fermo o in aria: si riarma a 1 cosi' il passo successivo parte subito
	; quando riprende a camminare, invece di far aspettare mezzo intervallo.
	MOVE.W	#1,Player+bob_PassoTimer
.fine:
	; La X di riferimento si aggiorna QUI e non nel ramo che suona: l'uscita e'
	; una sola, quindi cosi' e' aggiornata su OGNI percorso. Aggiornandola solo
	; quando suona, un frame di sosta lascerebbe un valore vecchio e il
	; confronto successivo farebbe scattare un passo falso.
	MOVE.W	Player+bob_WorldX,Player+bob_PrevX
	MOVEM.L	(SP)+,D0-D1/A0
	RTS
