; Init.i - Inizializzazioni: pannello, player, nemici, pietra, maschere BOB
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* 		ROUTINE DI DISEGNO DEL PANNELLO
DisegnaPannello:
	; Copia i 4 piani dell'arte dentro PannelloBuf, che ha il pitch del MONDO.
	; L'arte finisce a DELTA_MAPPAVERA byte dall'inizio di ogni riga, cioe' dove
	; comincia la mappa nel world buffer: cosi' il pannello appare esattamente
	; come apparirebbe il mondo a CameraX=0, e il display non va ritarato.
	; Il resto della riga resta a zero: e' fuori dalla finestra visibile.
	MOVEM.L	D0-D4/A0-A2,-(SP)

	LEA		PannelloBuf,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS,A1		; l'arte parte dove parte la mappa
	LEA		pannello,A2				; sorgente: 4 piani contigui, 40 byte per riga

	MOVEQ	#PANNELLO_BITPLANES-1,D4
	IFNE	PANNELLO_TEST_FILL
	; PROVA: invece dell'arte scrive costanti note, un valore per piano.
	; piano 0 = $FFFF, piano 1 = $0000, piano 2 = $FFFF, piano 3 = $0000
	; -> indice colore 1+4 = 5 su TUTTA la fascia, cioe' un colore solo e piatto.
	;   fascia UNIFORME del colore 5 -> buffer, puntatori e display sono sani, e
	;     il difetto sta nel blit dell'arte o nel file .raw
	;   fascia di ALTRO colore uniforme -> arrivano solo alcuni piani: si guarda
	;     quali bit mancano e si risale al puntatore sbagliato
	;   fascia NON uniforme -> il percorso di display e' rotto a monte
	LEA		PannelloBuf,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS,A1
	MOVEQ	#PANNELLO_BITPLANES-1,D4
.FillPianoPannello:
	MOVE.L	A1,A0
	MOVEQ	#0,D2
	; TUTTI i piani pieni: la fascia deve venire di UN SOLO colore, l'indice 15.
	; Qualunque zona di colore diverso dice esattamente quali piani NON arrivano
	; li': i bit accesi dell'indice sono i piani presenti. Nero = nessun piano.
	MOVE.W	#$FFFF,D2
.FillValore:
	MOVE.W	#PANNELLO_HEIGHT-1,D0
.FillRigaPannello:
	MOVE.W	#PANNELLO_BYTES_PER_ROW/2-1,D1
.FillWordPannello:
	MOVE.W	D2,(A0)+
	DBRA	D1,.FillWordPannello
	ADDA.W	#PANNELLO_BUF_PITCH-PANNELLO_BYTES_PER_ROW,A0
	DBRA	D0,.FillRigaPannello
	ADDA.L	#PANNELLO_BUF_PLANE,A1
	DBRA	D4,.FillPianoPannello
	ENDC

	IFEQ	PANNELLO_TEST_FILL
.BlittaLoopPannello:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM: nessuna maschera
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1: USEA+USED, minterm $F0 (D = A)
	MOVE.W	#0,$64(A6)				; BLTAMOD: sorgente contigua
	MOVE.W	#PANNELLO_BUF_PITCH-PANNELLO_BYTES_PER_ROW,$66(A6)	; BLTDMOD
	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT
	MOVE.W	#(PANNELLO_HEIGHT<<6)|(PANNELLO_BYTES_PER_ROW/2),$58(A6)	; BLTSIZE
	ADD.L	#PANNELLO_BUF_PLANE,A1	; piano successivo nella destinazione
	ADD.L	#PANNELLO_PLANE_SIZE,A2	; piano successivo nella sorgente
	DBRA	D4,.BlittaLoopPannello
	ENDC

	; --- puntatori del pannello nella copperlist, una volta sola: e' fisso ---
	; Niente compensazione della corsa col DMA: le righe di separazione girano
	; a bitplane spenti, quindi non c'e' auto-incremento e i puntatori restano
	; dove li mettiamo. Vedi il blocco su PANNELLO_SEP_ROWS.
	LEA		PannelloBuf,A1
	LEA		BitplanePannello,A2
	MOVEQ	#PANNELLO_BITPLANES-1,D4
.PuntaLoopPannello:
	MOVE.L	A1,D0
	MOVE.W	D0,6(A2)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A2)				; word alta
	ADDA.L	#PANNELLO_BUF_PLANE,A1
	ADDQ.W	#8,A2
	DBRA	D4,.PuntaLoopPannello

	MOVEM.L	(SP)+,D0-D4/A0-A2
	RTS
* InitPlayer - inizializza la struttura Player con i valori iniziali
InitPlayer:
	MOVEM.L	A0,-(SP)

	LEA	 	Player,A0
	MOVE.W	#1,bob_Speed(A0)			; velocità default
	MOVE.W	#2,bob_Direzione(A0)		; 0 = guarda a sud
	MOVE.W	#0,bob_AnimFrame(A0)		; primo frame
	MOVE.L	#OMINO,bob_Gfx(A0)			; puntatore allo spritesheet
	MOVE.L	#OMINO_MASK,bob_Mask(A0)	; maschera per-frame dello stesso sheet
	MOVE.W	#BOB_W,bob_Larghezza(A0)
	MOVE.W	#BOB_H,bob_Altezza(A0)
	; geometria dello sheet: bastano fotogrammi e bande, il resto lo deriva
	; DisegnaBOB. I valori derivati coincidono con le vecchie EQU:
	; blitW 3, slot 6, pitch 48, banda 1536, piano 12288 = PLANE_SIZE
	MOVE.W	#OMINO_FRAMES,bob_Frames(A0)
	MOVE.W	#OMINO_DIR,bob_Bande(A0)
	MOVE.W	#ANIM_DELAY,bob_AnimDelay(A0)
		MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVE.W	#1,bob_Active(A0)
	; Posizione di RIPIEGO. La posizione vera la decide la mappa, con la tile
	; TILE_VIA che cerca TrovaPartenza in coda a questa routine: questi due
	; valori restano solo per una mappa che non ne abbia nessuna, cosi' il
	; gioco parte lo stesso. Chi li guarda per sapere dove nasce il player
	; guarda il posto sbagliato: e' risorse/mappa1.txt.
	MOVE.W	#PLAYER_SPAWN_X,bob_WorldX(A0)
	MOVE.W	#PLAYER_SPAWN_Y,bob_WorldY(A0)
	MOVE.W	#0,bob_AI(A0)
	; --- Hit Points ---
	MOVE.W	#PLAYER_PF_MAX,bob_PF(A0)	; punti ferita iniziali: la stessa EQU da
	; cui l'indicatore ricava il fondo scala
	MOVE.W	#PLAYER_DANNO,bob_Damage(A0)		; quanto toglie al nemico al contatto
	MOVE.W	#0,bob_Invuln(A0)					; vulnerabile all'inizio
	MOVE.W	#PLAYER_INVULN_MAX,bob_InvulnMax(A0)	; recupero dopo un colpo subito
	; SENZA questa riga InvulnMax resta 0 (la
	; struct sta in BSS): il player verrebbe
	; colpito a ogni frame di contatto e i
	; suoi punti ferita sparirebbero in mezzo
	; secondo. I nemici ce l'hanno dalla loro
	; tabella, il player no e nessuno se n'era
	; accorto perche' non c'era la barra.

	; --- stato per-entita' che prima erano variabili globali ---
	MOVE.W	#0,bob_VelY(A0)				; fermo in verticale
	MOVE.W	#0,bob_FracY(A0)
	MOVE.W	#0,bob_Grounded(A0)			; nasce in aria e cade sul primo tile
	MOVE.W	#0,bob_GroundedPrev(A0)		; nessun fronte al primo frame
	; La X di riferimento dei passi parte dallo spawn e non da zero: partendo
	; da zero il primo confronto vedrebbe uno spostamento di 48 px inesistente
	; e farebbe suonare un passo all'avvio.
	MOVE.W	#PLAYER_SPAWN_X,bob_PrevX(A0)
	MOVE.W	#1,bob_PassoTimer(A0)		; a 1 il primo passo parte appena cammina
	MOVE.W	#1,bob_UltimaDirX(A0)		; guarda a destra
	MOVE.W	#0,bob_Cooldown(A0)			; puo' sparare subito

	MOVEM.L	(SP)+,A0
	BRA.W	TrovaPartenza			; la posizione la decide la mappa

* InitEnemies
*   Inizializza l'array Enemies con ENEMY_COUNT nemici, posizionati a
*   coordinate mondo predefinite.
*   bob_Active = 1 -> nemico attivo (da renderizzare)
*   bob_Active = 0 -> slot vuoto (skippato dal rendering)
InitEnemies:
	MOVEM.L	D0/A0/A1,-(SP)

	LEA		Enemies,A0
	LEA		EnemyInitTable,A1
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; A0 = struct del nemico corrente
	; A1 = puntatore alla riga della tabella init
	;			(8 word: WorldX, WorldY, Direzione, Active, AI, PF,
	;					 Damage, InvulnMax)
	MOVE.W	(A1)+,bob_WorldX(A0)			; posizione mondo X
	MOVE.W	(A1)+,bob_WorldY(A0)			; posizione mondo Y
	MOVE.W	(A1)+,bob_Direzione(A0)
	MOVE.W	(A1)+,bob_Active(A0)
	MOVE.W	(A1)+,bob_AI(A0)
	MOVE.W	(A1)+,bob_PF(A0)				; punti ferita iniziali
	MOVE.W	(A1)+,bob_Damage(A0)			; danno inflitto
	MOVE.W	(A1)+,bob_InvulnMax(A0)			; frame di invuln dopo hit
	MOVE.W	#0,bob_Invuln(A0)				; vulnerabile all'inizio
	MOVE.W	#1,bob_Speed(A0)
	MOVE.W	#0,bob_X(A0)
	MOVE.W	#0,bob_Y(A0)
	MOVE.W	#0,bob_AnimFrame(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVE.L	#NEMICO,bob_Gfx(A0)				; spritesheet del nemico
	MOVE.L	#NEMICO_MASK,bob_Mask(A0)		; maschera per-frame del nemico
	MOVE.W	#BOB_W,bob_Larghezza(A0)
	MOVE.W	#BOB_H,bob_Altezza(A0)
	; geometria dello sheet: il nemico ha lo STESSO layout dell'omino
	MOVE.W	#OMINO_FRAMES,bob_Frames(A0)
	MOVE.W	#OMINO_DIR,bob_Bande(A0)
	MOVE.W	#ANIM_DELAY,bob_AnimDelay(A0)
	; bob_X, bob_Y verranno calcolati al rendering da World - Camera

	LEA		bob_Length(A0),A0				; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0/A0/A1
	RTS

* InitPietra - inizializza il BOB del proiettile
*   La pietra usa la STESSA struct e le STESSE routine di disegno di player e
*   nemici: cambia solo la geometria, che ora vive nella struct invece che
*   nelle EQU globali. Sheet 256x16 a 5 piani, 8 frame da 16 px di arte in
*   slot da 32, UNA sola banda (nessuna direzione).
*   Nasce spento: lo accende, lo posiziona e lo muove Proiettile.
InitPietra:
	MOVEM.L	A0,-(SP)

	LEA	 	BobPietra,A0
	MOVE.W	#0,bob_Active(A0)			; spento finche' non si spara
	MOVE.L	#PIETRA,bob_Gfx(A0)			; sheet della pietra
	MOVE.L	#PIETRA_MASK,bob_Mask(A0)	; maschera costruita da BuildBobMasks
	MOVE.W	#PIETRA_W,bob_Larghezza(A0)
	MOVE.W	#PIETRA_H,bob_Altezza(A0)
	; geometria dello sheet: e' QUESTO che permette di riusare DisegnaBOB.
	; Derivati a runtime: blitW 2, slot 4, pitch 32, piano 512 = PIETRA_PLANE_SIZE
	MOVE.W	#PIETRA_FRAMES,bob_Frames(A0)
	MOVE.W	#PIETRA_BANDE,bob_Bande(A0)
	; passo dell'animazione: alza o abbassa QUI per far girare la pietra
	; piu' o meno in fretta, senza toccare omino e nemici
	MOVE.W	#ANIM_DELAY,bob_AnimDelay(A0)
	; danno inflitto: era la EQU BULLET_DAMAGE letta direttamente dalla logica,
	; ora e' il campo che gia' esisteva. bob_Speed NON si usa: la pietra si
	; muove per velocita' (bob_VelX/Y), non per ottante x scalare.
	MOVE.W	#BULLET_DAMAGE,bob_Damage(A0)
	MOVE.W	#0,bob_TTL(A0)
	MOVE.W	#0,bob_VelX(A0)
	MOVE.W	#0,bob_VelY(A0)
	MOVE.W	#0,bob_FracX(A0)
	MOVE.W	#0,bob_FracY(A0)
	; stato di animazione: la pietra ruota sempre mentre vola
	MOVE.W	#0,bob_Direzione(A0)		; resta 0: lo sheet ha una banda sola
	MOVE.W	#0,bob_AnimFrame(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#1,bob_IsMoving(A0)			; 1 = DisegnaBOB fa avanzare i frame
	MOVE.W	#0,bob_X(A0)
	MOVE.W	#0,bob_Y(A0)
	MOVE.W	#0,bob_WorldX(A0)
	MOVE.W	#0,bob_WorldY(A0)

	MOVEM.L	(SP)+,A0
	RTS

* BuildBobMasks / BuildBobMask
*   Genera la maschera per-frame di uno spritesheet come OR dei suoi 5
*   bitplane: dove almeno un piano ha un bit, li' c'e' il BOB.
*   Da chiamare UNA SOLA VOLTA al boot (i dati sono statici).
*   La maschera esce gia' corretta anche nel margine dello shift: la word
*   di stacco fra un frame e l'altro e' nera su tutti i piani, quindi l'OR
*   la lascia a zero. E' il padding da 16 px nello sheet a garantirlo.
*   BuildBobMask:  IN A1 = sheet (plane 0), A0 = destinazione maschera,
*                     D2.l = byte di UN bitplane di QUESTO sheet.
*   La dimensione del piano era la EQU globale PLANE_SIZE, cioe' quella
*   dell'omino: andava bene finche' tutti gli sheet erano fatti uguali. La
*   pietra ha un piano da PIETRA_PLANE_SIZE byte, quindi ora e' un parametro.
BuildBobMasks:
	MOVEM.L	D2/A0-A1,-(SP)
	LEA		OMINO,A1
	LEA		OMINO_MASK,A0
	MOVE.L	#PLANE_SIZE,D2
	BSR.S	BuildBobMask
	LEA		NEMICO,A1
	LEA		NEMICO_MASK,A0
	MOVE.L	#PLANE_SIZE,D2
	BSR.S	BuildBobMask
	LEA		PIETRA,A1
	LEA		PIETRA_MASK,A0
	MOVE.L	#PIETRA_PLANE_SIZE,D2
	BSR.S	BuildBobMask
	; Il falo' NON e' qui: il suo sheet non esiste su disco, lo costruisce
	; BuildFaloSheet al boot, e la sua maschera si fa li' subito dopo. Vedi il
	; commento in quella routine per il perche' l'ordine non e' un dettaglio.
	MOVEM.L	(SP)+,D2/A0-A1
	RTS

BuildBobMask:
	MOVEM.L	D0-D2/A0-A5,-(SP)

	; i cinque piani sono contigui: ognuno dista D2 byte dal precedente.
	; Con un valore in registro non si puo' piu' usare il displacement della
	; LEA (d16), che accetta solo una costante.
	MOVEA.L	A1,A2
	ADDA.L	D2,A2						; A2 = plane 1
	MOVEA.L	A2,A3
	ADDA.L	D2,A3						; A3 = plane 2
	MOVEA.L	A3,A4
	ADDA.L	D2,A4						; A4 = plane 3
	MOVEA.L	A4,A5
	ADDA.L	D2,A5						; A5 = plane 4

	; Loop a long: (byte del piano)/4 iterazioni
	MOVE.L	D2,D0
	LSR.L	#2,D0
	SUBQ.W	#1,D0
.loop:
	MOVE.L	(A1)+,D1
	OR.L	(A2)+,D1
	OR.L	(A3)+,D1
	OR.L	(A4)+,D1
	OR.L	(A5)+,D1
	MOVE.L	D1,(A0)+
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D2/A0-A5
	RTS
