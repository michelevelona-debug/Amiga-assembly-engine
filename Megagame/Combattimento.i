; Combattimento.i - Pietra, combattimento, uccisioni
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* Proiettile
*   Gestisce il proiettile (1 alla volta): fuoco, lancio, parabola,
*   atterraggio e collisione coi nemici.
*   (l'intestazione diceva ancora "ProcessBullet", nome che non esiste piu')
Proiettile:
	MOVEM.L	D0-D5/A0-A2,-(SP)

	; A2 e non A1: IsTileBlocked usa A1 come appoggio e la distrugge, e qui
	; sotto la chiamiamo per sapere se la pietra ha toccato terra.
	LEA		BobPietra,A2			; A2 = il proiettile per tutta la routine

	IFNE	BULLET_DEBUG
	; PROVA: pietra sempre accesa e inchiodata a schermo fisso.
	MOVE.W	TileX,D0
	LSL.W	#4,D0
	ADD.W	PixelOffX,D0
	ADD.W	#BULLET_DEBUG_X,D0
	MOVE.W	D0,bob_WorldX(A2)
	MOVE.W	TileY,D0
	LSL.W	#4,D0
	ADD.W	PixelOffY,D0
	ADD.W	#BULLET_DEBUG_Y,D0
	MOVE.W	D0,bob_WorldY(A2)
	MOVE.W	#1,bob_Active(A2)
	BRA.W	.esci
	ENDC

	; Ricorda l'ultima direzione ORIZZONTALE del player. La pietra si lancia
	; sempre di lato: se il player guarda in su o in giu' l'ottante non da'
	; nessun verso, e senza memoria il tiro partirebbe sempre a destra.
	LEA		Player,A0
	MOVE.W	bob_Direzione(A0),D0
	AND.W	#7,D0
	LSL.W	#2,D0
	LEA		DirectionDeltas,A0
	MOVE.W	(A0,D0.W),D0			; dx dell'ottante: -1, 0 oppure +1
	BEQ.S	.dir_invariata			; N o S: nessuna orizzontale, tieni l'ultima
	MOVE.W	D0,Player+bob_UltimaDirX
.dir_invariata:

	; Decrementa cooldown se > 0. Il cooldown vive nel PLAYER e non nella
	; pietra: e' stato di CHI SPARA, non del proiettile. Se stesse in
	; BobPietra si azzererebbe insieme al sasso e si potrebbe sparare a
	; raffica ricaricando ad ogni impatto.
	MOVE.W	Player+bob_Cooldown,D0
	BEQ.S	.cooldown_done
	SUBQ.W	#1,D0
	MOVE.W	D0,Player+bob_Cooldown
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

	; ----- Il proiettile e' vivo? Lo dice la sua struct, non piu' una
	; ----- variabile parallela.
	TST.W	bob_Active(A2)
	BNE.W	.update_bullet

	; Non attivo: edge detection + cooldown
	TST.W	D1
	BEQ.W	.save_fire
	TST.W	FirePrev
	BNE.W	.save_fire
	TST.W	Player+bob_Cooldown
	BNE.W	.save_fire

	; --- SPAWN! ---
	; Il proiettile nasce col proprio CENTRO sul centro del player. I due
	; mezzi-fotogrammi vengono da bob_Larghezza/bob_Altezza invece che da un
	; +8 cablato, che era il centro di un bob 16x16 e non e' mai stato
	; aggiornato quando i bob sono passati a 32x32.
	LEA		Player,A0
	MOVE.W	bob_WorldX(A0),D2
	MOVE.W	bob_Larghezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro X del player
	MOVE.W	bob_Larghezza(A2),D3
	LSR.W	#1,D3
	SUB.W	D3,D2					; meno mezzo proiettile
	MOVE.W	D2,bob_WorldX(A2)
	MOVE.W	bob_WorldY(A0),D2
	MOVE.W	bob_Altezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro Y del player
	MOVE.W	bob_Altezza(A2),D3
	LSR.W	#1,D3
	SUB.W	D3,D2
	MOVE.W	D2,bob_WorldY(A2)

	; Velocita' iniziale del lancio: 30 gradi sull'orizzontale, verso l'ultima
	; direzione orizzontale valida. La verticale e' NEGATIVA perche' la Y
	; cresce verso il basso, quindi "su" e' meno.
	MOVE.W	#PIETRA_VEL_X,D2
	MULS.W	Player+bob_UltimaDirX,D2			; +vx a destra, -vx a sinistra
	MOVE.W	D2,bob_VelX(A2)
	MOVE.W	#-PIETRA_VEL_Y,bob_VelY(A2)
	CLR.W	bob_FracX(A2)			; la frazione riparte da zero a ogni lancio
	CLR.W	bob_FracY(A2)

	MOVE.W	#1,bob_Active(A2)
	MOVE.W	#PIETRA_RAGGIO,bob_TTL(A2)	; gittata residua, in PIXEL
	MOVE.W	#BULLET_COOLDOWNC,Player+bob_Cooldown
	LEA		SfxSparo,A0
	BSR.W	PlaySfx
	BRA.W	.save_fire

.update_bullet:
	; ----- PARABOLA -----
	; L'orizzontale resta costante, la verticale accelera verso il basso: e'
	; tutta qui la differenza fra un lancio e il vecchio tiro rettilineo.
	ADD.W	#PIETRA_GRAVITA,bob_VelY(A2)

	; X: si somma la velocita' alla frazione accumulata, si portano nel mondo
	; i pixel INTERI che ne escono e si tiene il resto per il frame dopo.
	; L'ASR ha segno, quindi funziona anche andando a sinistra: con frazione 0
	; e velocita' -1365 si ottengono -6 px e una frazione di 171/256, che
	; sommati fanno esattamente -5,33.
	MOVE.W	bob_FracX(A2),D2
	ADD.W	bob_VelX(A2),D2
	MOVE.W	D2,D3
	ASR.W	#8,D3					; pixel interi, con segno
	ADD.W	D3,bob_WorldX(A2)
	AND.W	#$00FF,D2				; resta solo la frazione
	MOVE.W	D2,bob_FracX(A2)

	; La gittata si consuma in PIXEL, non in frame: bob_TTL dice quanti ne
	; restano dei PIETRA_RAGGIO di partenza. Contare i pixel fa valere il
	; tetto alla lettera, qualunque cosa facciano parabola e terreno.
	TST.W	D3
	BPL.S	.dx_positivo
	NEG.W	D3						; verso sinistra: conta il valore assoluto
.dx_positivo:
	SUB.W	D3,bob_TTL(A2)
	BGT.S	.muovi_y
	CLR.W	bob_Active(A2)			; gittata esaurita
	BRA.W	.save_fire
.muovi_y:
	; Y: stessa aritmetica della X
	MOVE.W	bob_FracY(A2),D2
	ADD.W	bob_VelY(A2),D2
	MOVE.W	D2,D3
	ASR.W	#8,D3
	ADD.W	D3,bob_WorldY(A2)
	AND.W	#$00FF,D2
	MOVE.W	D2,bob_FracY(A2)

.check_bullet_bounds:
	; Gli stessi limiti che usa il cull di DisegnaBOB: cosi' il proiettile non
	; resta vivo nella logica dopo essere sparito dal disegno.
	MOVE.W	bob_WorldX(A2),D2
	BMI.S	.bullet_off
	MOVE.W	#MAPPA_COLS*16,D3
	SUB.W	bob_Larghezza(A2),D3
	CMP.W	D3,D2
	BGT.S	.bullet_off
	MOVE.W	bob_WorldY(A2),D2
	BMI.S	.bullet_off
	MOVE.W	#MAPPA_ROWS*16,D3
	SUB.W	bob_Altezza(A2),D3
	CMP.W	D3,D2
	BGT.S	.bullet_off
	BRA.S	.check_atterraggio
.bullet_off:
	CLR.W	bob_Active(A2)
	BRA.W	.save_fire

.check_atterraggio:
	; ----- ATTERRAGGIO -----
	; Si sonda la tile sotto il CENTRO della pietra: essendo 16x16 come una
	; tile, un solo campione basta, e ferma anche il tiro che va a sbattere di
	; lato contro un muro invece che a terra.
	MOVE.W	bob_WorldX(A2),D0
	MOVE.W	bob_Larghezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D0					; centro X
	MOVE.W	bob_WorldY(A2),D1
	MOVE.W	bob_Altezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D1					; centro Y
	BSR.W	IsTileBlocked			; NB: distrugge D0/D1/D2 e A1
	TST.B	D2						; 0 = tile libera (come fa IsBoxBlocked:
	BEQ.S	.check_bullet_collision	;  si ricontrolla D2 invece di fidarsi
	CLR.W	bob_Active(A2)			;  del flag Z attraverso la BSR)
	BRA.W	.save_fire

.check_bullet_collision:
	; Centro del proiettile, calcolato una volta sola per tutto il ciclo.
	MOVE.W	bob_WorldX(A2),D4
	MOVE.W	bob_Larghezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D4					; D4 = centro X del proiettile
	MOVE.W	bob_WorldY(A2),D5
	MOVE.W	bob_Altezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D5					; D5 = centro Y del proiettile

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.coll_loop:
	TST.W	bob_Active(A0)
	BEQ.S	.coll_next

	; Distanza fra i due CENTRI, entrambi derivati dalle dimensioni vere.
	MOVE.W	bob_WorldX(A0),D2
	MOVE.W	bob_Larghezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro X del nemico
	SUB.W	D4,D2
	BPL.S	.coll_absx
	NEG.W	D2
.coll_absx:
	CMP.W	#BULLET_HIT_DIST,D2
	BGE.S	.coll_next

	MOVE.W	bob_WorldY(A0),D2
	MOVE.W	bob_Altezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro Y del nemico
	SUB.W	D5,D2
	BPL.S	.coll_absy
	NEG.W	D2
.coll_absy:
	CMP.W	#BULLET_HIT_DIST,D2
	BGE.S	.coll_next

	; HIT!
	MOVE.W	bob_PF(A0),D2
	SUB.W	bob_Damage(A2),D2		; danno del proiettile, dalla SUA struct
	BPL.S	.coll_hit_alive
	MOVEQ	#0,D2
.coll_hit_alive:
	MOVE.W	D2,bob_PF(A0)
	MOVE.W	#2,bob_AI(A0)
	MOVE.W	bob_InvulnMax(A0),bob_Invuln(A0)
	CLR.W	bob_Active(A2)			; il proiettile si consuma nel colpo
	TST.W	bob_PF(A0)
	BNE.S	.sfx_hit_alive
	BSR.W	NemicoUcciso			; Active, punti e suono in un posto solo
	BRA.S	.save_fire
.sfx_hit_alive:
	LEA		SfxNemicoColpito,A0
	BSR.W	PlaySfx
	BRA.S	.save_fire

.coll_next:
	LEA		bob_Length(A0),A0
	DBRA	D0,.coll_loop

.save_fire:
	MOVE.W	D1,FirePrev
.esci:
	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

* Combattimento - lo scontro al CONTATTO fra player e nemici
*   Gira una volta per quadro, prima del disegno. Per ogni nemico attivo:
*   1. scala di uno il suo recupero (bob_Invuln); se stava ancora recuperando lo
*      salta del tutto: non colpisce e non e' colpibile.
*   2. sovrapposizione col player, AABB con soglia BOB_COLL_W+1 / BOB_COLL_H+1.
*      La soglia DISCENDE dalla dimensione del bob e non e' scritta a mano: due
*      riquadri si toccano quando la distanza fra gli angoli e' BOB_COLL_W, e il
*      +1 fa scattare anche il contatto tangente.
*   3. IL CONTATTO FA MALE A TUTTI E DUE e non dipende da dove uno guarda. Il
*      cancello sull'ottante e' stato tolto: con nemici che non si girano mai
*      (AI 0) il contatto quasi non si vedeva. DirezioneVerso e OctantsClose
*      restano nel sorgente se lo si volesse rimettere.
*   4. chi colpisce mette al bersaglio bob_InvulnMax quadri di recupero. Se
*      restasse a zero il contatto toglierebbe un punto ferita a OGNI quadro.
*   5. il nemico a zero punti ferita passa da NemicoUcciso (Active, punti e
*      suono) e il ciclo va oltre: da morto non colpisce piu' in questo quadro.
*      Chi lo colpisce passa in AI 2, l'allarme.
*   COSA NON FA, e va saputo: quando i punti ferita del PLAYER arrivano a zero
*   non succede niente. Non c'e' morte ne' fine partita.
*   DISTRUGGE: nulla (salva tutto).
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
	; Sovrapposizione player-nemico, AABB sulle coordinate mondo.
	; La soglia DISCENDE dalla dimensione del bob e non e' scritta a mano:
	; due riquadri larghi BOB_COLL_W si toccano quando la distanza fra gli
	; angoli e' BOB_COLL_W esatti, e si sovrappongono quando e' meno. Il +1
	; serve a far scattare anche il contatto tangente, che e' il caso in cui a
	; schermo i due si sfiorano.
	; QUI C'ERA UN 17 SCRITTO A MANO, giusto quando i bob erano 16x16 e mai
	; aggiornato quando l'arte e' passata a 32x32: chiedeva che i due fossero
	; sovrapposti per meta', cioe' molto piu' che "in contatto". E' il motivo
	; per cui la vita non scendeva quasi mai. IsOverlapEnemies, che il numero
	; lo derivava gia', non aveva il problema.
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	bob_WorldX(A1),D1
	BPL.S	.absx_ok
	NEG.W	D1
.absx_ok:
	CMP.W	#BOB_COLL_W+1,D1
	BGE.W	.next						; no overlap X

	MOVE.W	bob_WorldY(A0),D1
	SUB.W	bob_WorldY(A1),D1
	BPL.S	.absy_ok
	NEG.W	D1
.absy_ok:
	CMP.W	#BOB_COLL_H+1,D1
	BGE.W	.next						; no overlap Y

	; --- COLLISIONE GEOMETRICA! ---
	; Il contatto fa male a TUTTI E DUE, e non dipende da dove uno sta
	; guardando. Prima c'era un cancello in piu': ognuno colpiva solo se
	; l'octante del vettore verso il bersaglio stava entro +-1 dalla sua
	; bob_Direzione. Con nemici che non si girano mai (AI 0) voleva dire che il
	; contatto quasi non si vedeva, ed e' il motivo per cui la vita non
	; scendeva. Se un domani lo si vuole rimettere, DirezioneVerso e
	; OctantsClose sono ancora nel sorgente e fanno esattamente quel conto.

	; --- 1) Player colpisce nemico ---
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
	BNE.S	.nemico_vivo
	BSR.W	NemicoUcciso			; punti e suono: prima qui c'era il solo
	BRA.W	.next					; bob_Active, e uccidere un nemico addosso
.nemico_vivo:						; non dava punti
	; Il salto qui sopra e' la seconda meta' della correzione del 6 settembre:
	; un nemico che muore in questo quadro NON deve piu' colpire. Prima si
	; cadeva dentro il blocco 2 comunque, quindi il colpo che uccideva faceva
	; male anche a chi lo dava - e a schermo era indistinguibile da un colpo
	; incassato per niente. Il percorso della pietra questo problema non l'ha
	; mai avuto: li' dopo NemicoUcciso si va a .save_fire e si esce.
	; A0 sopravvive a NemicoUcciso, quindi .next avanza dal nemico giusto.
	; BRA.W e non BRA.S: la distanza oggi sta in un byte, ma questo blocco e'
	; gia' cresciuto due volte e un Bcc.S che va fuori portata si scopre solo
	; all'assemblaggio.

	; --- 2) Nemico colpisce player ---
	; Player ancora in recupero da un colpo precedente? Allora niente.
	TST.W	bob_Invuln(A1)
	BNE.W	.next
	MOVE.W	bob_Damage(A0),D1			; danno nemico
	MOVE.W	bob_PF(A1),D2
	SUB.W	D1,D2
	BPL.S	.player_alive
	MOVE.W	#0,D2
.player_alive:
	MOVE.W	D2,bob_PF(A1)
	MOVE.W	bob_InvulnMax(A1),bob_Invuln(A1)
	; A0 e' il puntatore al NEMICO su cui sta girando il ciclo, e PlaySfx vuole
	; la struttura del suono proprio in A0: senza salvarlo, .next avanzerebbe da
	; SfxHitPlayer invece che dal nemico e le iterazioni restanti leggerebbero
	; - e scriverebbero - fuori dall'array dei nemici.
	MOVE.L	A0,-(SP)
	LEA		SfxHitPlayer,A0
	BSR.W	PlaySfx
	MOVE.L	(SP)+,A0
.next:
	LEA		bob_Length(A0),A0			; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D5/A0/A1
	RTS

* NemicoUcciso - quello che succede quando un nemico arriva a zero PF
*   UNA strada sola per i due modi di morire: il colpo di pietra e il contatto
*   col player. Fino al 6 settembre i punti e il suono stavano scritti solo nel
*   primo, quindi uccidere un nemico addosso non dava niente - nessun errore,
*   nessun crash, un punteggio che non saliva. Non era un difetto di calcolo:
*   era la stessa cosa scritta in due posti e aggiornata in uno solo.
*   Se nasce un terzo modo di morire, chiama questa e non puo' dimenticarsene.
*   INPUT:  A0 = il nemico
*   DISTRUGGE: nulla. A0 va salvato PERCHE' LA LEA DEL SUONO LO SOVRASCRIVE,
*   non perche' lo tocchi PlaySfx (quella preserva tutto): il chiamante ci sta
*   ciclando sopra, e senza salvarlo il ciclo avanzerebbe da SfxNemicoMorto
*   invece che dall'array dei nemici.
NemicoUcciso:
	MOVE.L	A0,-(SP)
	CLR.W	bob_Active(A0)
	ADD.L	#PUNTI_NEMICO,Punteggio		; Punteggio e' un LONG: a word il
	; riporto non passerebbe nella parte alta
	LEA		SfxNemicoMorto,A0
	BSR.W	PlaySfx
	MOVE.L	(SP)+,A0
	RTS

* DirezioneVerso
*   Calcola l'octante (direzione 0..7) di un vettore (dx, dy).
*   INPUT:  D4.w = dx, D5.w = dy
*   OUTPUT: D4.w = octante 0..7 secondo la convenzione bob_Direzione:
*           0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
*   Se dx = dy = 0, ritorna 0 (E) come default.
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

* OctantsClose
*   Verifica se due octanti (0..7) sono "vicini" entro ±1 modulo 8.
*   INPUT:  D4.w = octante A, D5.w = octante B (sara' bob_Direzione)
*   OUTPUT: D5.w = 1 se vicini (|A-B| <= 1 modulo 8), 0 altrimenti
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
