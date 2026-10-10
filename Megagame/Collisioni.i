; Collisioni.i - Centro camera, collisioni con tile e BOB, movimento nemici
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* RettangoloScrollNelCentro
*   Decide se la camera deve scrollare in questo frame.
*   Regola: la camera scrolla solo se il player e' al centro dello schermo
*           (bob_X==CENTER_X per X, bob_Y==CENTER_Y per Y, indipendenti).
*   Se il player NON e' al centro su un asse, ScrllX/Y di quell'asse
*   viene azzerato -> camera ferma su quell'asse fino a che il player
*   non torna al centro.
*   Nota: bob_X/Y devono essere stati calcolati prima (AggiornaPlayerScreenPos),
*         altrimenti usiamo la posizione del frame precedente, che e' OK
*         perche' la transizione e' incrementale (1 pixel per frame).
; Centro dello SCHERMO per il BOB, derivato invece che cablato: dipende dalla
; finestra visibile e dalla dimensione del BOB, ed entrambe sono cambiate.
; CENTER_X restava giusto per caso (144 = (320-32)/2), CENTER_Y no: 120 era
; (256-16)/2, cioe' tarato su uno schermo alto 256 righe e un BOB 16x16.
; Con BG_VIS_ROWS=176 e BOB_H=32 il valore corretto e' 72: erano 48 px di
; errore sul punto in cui la camera decide di seguire il player.
CENTER_X        EQU     (VIS_COLS*16-BOB_W)/2   ; = 144
CENTER_Y        EQU     (BG_VIS_ROWS-BOB_H)/2   ; = 72 (era 120)

RettangoloScrollNelCentro:
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

* IsTileBlocked
*   Controlla se la tile a (worldX, worldY) e' bloccata.
*   Input:  D0 = worldX (pixel)
*           D1 = worldY (pixel)
*   Output: D2.b = TileFlags della tile (0 = libera, !=0 = bloccata)
*           Z flag aggiornato (BEQ = libera, BNE = bloccata)
*   Modifica: D0, D1, D2
*   Tile fuori dai bounds della mappa sono considerate bloccate.
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
	MOVEA.L	MappaPtr,A1			; la mappa viva
	MOVE.W	(A1,D1.W),D2			; D2 = numero della tile

	; Lookup nel TileFlags (indicizzato come byte)
	LEA		TileFlags,A1
	MOVE.B	(A1,D2.W),D2			; D2.b = flag (0 = libera)
	; Z aggiornato dal MOVE
	RTS

.blocked:
	MOVEQ	#TF_BLOCK,D2			; non zero
	RTS

* IsBoxBlocked
*   Il box (BOB_COLL_W x BOB_COLL_H) a (worldX, worldY) tocca tile bloccate?
*   Input:  D0 = worldX (bordo sinistro), D1 = worldY (bordo alto)
*   Output: Z flag (BEQ = libero, BNE = collide), D0/D1 preservati
*   NON bastano i 4 angoli: su un box piu' largo di una tile due angoli
*   opposti possono essere liberi mentre la tile IN MEZZO e' un muro, e il
*   BOB ci passa attraverso. Qui si sonda una griglia a passo 16 px (la
*   dimensione della tile) piu' sempre il bordo opposto, cosi' nessuna
*   colonna o riga di tile toccata dal box puo' sfuggire.
*   A 16x16 degenera nei soliti 4 angoli: stesso costo di prima.
*   NIENTE COMPENSAZIONE: il BOB e' disegnato alla SUA posizione mondo (X,Y),
*   cioe' sulle stesse tile che qui vengono controllate.
IsBoxBlocked:
	MOVEM.L	D4-D7,-(SP)
	MOVE.W	D0,D6					; X base
	MOVE.W	D1,D7					; Y base
	MOVEQ	#0,D5					; dy
.loopY:
	MOVEQ	#0,D4					; dx
.loopX:
	MOVE.W	D6,D0
	ADD.W	D4,D0
	MOVE.W	D7,D1
	ADD.W	D5,D1
	BSR.W	IsTileBlocked			; tocca solo D0/D1/D2/A1
	TST.B	D2
	BNE.S	.fine					; una sonda bloccata basta
	CMP.W	#BOB_COLL_W-1,D4
	BEQ.S	.nextY					; era gia' il bordo destro
	ADD.W	#16,D4
	CMP.W	#BOB_COLL_W-1,D4
	BLS.S	.loopX
	MOVE.W	#BOB_COLL_W-1,D4		; ultima sonda = bordo destro
	BRA.S	.loopX
.nextY:
	CMP.W	#BOB_COLL_H-1,D5
	BEQ.S	.fine					; era gia' il bordo basso
	ADD.W	#16,D5
	CMP.W	#BOB_COLL_H-1,D5
	BLS.S	.loopY
	MOVE.W	#BOB_COLL_H-1,D5		; ultima sonda = bordo basso
	BRA.S	.loopY
.fine:
	MOVE.W	D6,D0					; ripristino gli input
	MOVE.W	D7,D1
	MOVEM.L	(SP)+,D4-D7
	TST.B	D2						; riapplico Z
	RTS
* IsOverlapEnemies
*   Controlla se un BOB 16x16 a posizione (D0, D1) si sovrappone con
*   uno qualunque dei nemici attivi.
*   Due BOB 16x16 a (Xa, Ya) e (Xb, Yb) si sovrappongono se:
*     |Xa - Xb| < 16 AND |Ya - Yb| < 16
*   equivalente a:
*     (Xa - Xb) >= -15 AND (Xa - Xb) <= 15
*     (Ya - Yb) >= -15 AND (Ya - Yb) <= 15
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*           A2 = puntatore opzionale a un BOB DA ESCLUDERE (puo' essere 0)
*           [usato se un nemico controlla rispetto agli altri nemici, per
*            non confrontarsi con se stesso]
*   OUTPUT: Z=1 se NESSUN overlap (libero), Z=0 se overlap rilevato
*           D0/D1 preservati
*           D2 = 0 se libero, !=0 se overlap (per coerenza con IsBoxBlocked)
*           Tutti gli altri registri preservati.
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
	CMP.W	#-(BOB_COLL_W-1),D3
	BLT.S	.next					; troppo a sinistra -> non sovrappone
	CMP.W	#BOB_COLL_W,D3
	BGE.S	.next					; troppo a destra -> non sovrappone

	; Test sovrapposizione Y
	MOVE.W	D1,D4
	SUB.W	bob_WorldY(A0),D4		; D4 = D1 - enemyY
	CMP.W	#-(BOB_COLL_H-1),D4
	BLT.S	.next
	CMP.W	#BOB_COLL_H,D4
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

* IsOverlapPlayer
*   Controlla se un BOB 16x16 a posizione (D0, D1) si sovrappone con
*   il Player.
*   Usato dai nemici per evitare di camminare sul player.
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*   OUTPUT: Z=1 se NO overlap, Z=0 se overlap
*           D2 = 0 libero, !=0 overlap
*           D0/D1 preservati
IsOverlapPlayer:
	MOVEM.L	D3-D4,-(SP)
	MOVEQ	#0,D2					; default libero

	; Test X
	MOVE.W	D0,D3
	SUB.W	Player+bob_WorldX,D3
	CMP.W	#-(BOB_COLL_W-1),D3
	BLT.S	.done
	CMP.W	#BOB_COLL_W,D3
	BGE.S	.done

	; Test Y
	MOVE.W	D1,D4
	SUB.W	Player+bob_WorldY,D4
	CMP.W	#-(BOB_COLL_H-1),D4
	BLT.S	.done
	CMP.W	#BOB_COLL_H,D4
	BGE.S	.done

	MOVEQ	#1,D2					; overlap
.done:
	MOVEM.L	(SP)+,D3-D4
	TST.B	D2
	RTS

* IsEnemyBlocked
*   Controlla se un nemico puo' muoversi a (D0, D1):
*   - tile bloccata?
*   - sovrapposizione col player?
*   - sovrapposizione con un ALTRO nemico (escluso A2 = se stesso)?
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*           A2 = puntatore al nemico stesso (per escluderlo da IsOverlapEnemies)
*   OUTPUT: Z=1 libero, Z=0 bloccato
*           D2 = 0 libero, !=0 bloccato
*           D0/D1 preservati
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

* AggiornaNemici
*   Per ogni nemico attivo, aggiorna la sua posizione in base a bob_AI:
*     0 = fermo
*     1 = ronda su/giù
*     2 = ronda dx/sx
*     3 = caccia il player
AggiornaNemici:
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
