; Mondo.i - Camera, bordi, porte fra i blocchi, ricostruzione del mondo
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

* 		ROUTINE DI CONTROLLO DEI BORDI
* TILE BOUNDARY - SHIFT BUFFER
ControllaBordi:
	MOVEM.L D0-D2,-(SP)

; PRE-Check per simmetria con .AzzeroXMin/.AzzeroYMin

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
	BRA.S   .FineControlli
.AzzeroYMax:
	MOVE.W  #0,ScrllY
	MOVEQ   #16-CAM_STEP_Y,D1	; 15 se step=1, 8 se step=8
	BRA.S   .FineControlli
.ControlloYMin:
	TST.W   D1
	BGE.S   .FineControlli
	MOVE.W  TileY,D2
	CMP.W   #0,D2
	BLE.S   .AzzeroYMin
	ADD.W   #16,D1
	SUB.W   #1,TileY
	BRA.S   .FineControlli
.AzzeroYMin:
	MOVE.W  #0,ScrllY
	MOVEQ   #0,D1
.FineControlli:
	; La camera non deve MAI superare TILE*MAX*16 ---
	; I check qui sopra bloccano lo scroll solo quando PixelOff vale 0. Basta
	; arrivare al tile di bordo con un offset residuo — succede cambiando il
	; passo verticale a meta' tile, cioe' premendo G — e la camera prosegue
	; fino a TILEYMAX*16+15, poi si assesta 8 px oltre il limite valido.
	; Questo chiude sia il transitorio sia il regime: al tile di bordo
	; l'offset e' per definizione 0, perche' la finestra finisce esattamente
	; sul bordo della mappa.
	MOVE.W	TileX,D2
	CMP.W	#TILEXMAX,D2
	BLT.S	.setXok
	MOVE.W	#TILEXMAX,TileX
	MOVEQ	#0,D0
.setXok:
	MOVE.W	TileY,D2
	CMP.W	#TILEYMAX,D2
	BLT.S	.setYok
	MOVE.W	#TILEYMAX,TileY
	MOVEQ	#0,D1
.setYok:
	MOVE.W  D0,PixelOffX
	MOVE.W  D1,PixelOffY
	MOVEM.L (SP)+,D0-D2
	RTS

* 		ROUTINE DI COMPOSIZIONE DELLO SFONDO
* Riempio il buffer di SFONDO_PITCH*SFONDO_HEIGHT con il rettangolo in alto a sinistra
* della mappa.
* CentraCameraSulPlayer - porta la camera dove sta il player. Una volta, al boot.
*   Finche' il player nasceva su PLAYER_SPAWN (48,48) la camera ferma a zero
*   andava bene PER CASO: quel punto e' dentro la prima finestra. Con la
*   partenza decisa dalla mappa (TILE_VIA, vedi TrovaPartenza) il player puo'
*   nascere ovunque, e la camera all'angolo alto-sinistro mostra un pezzo di
*   mondo che non c'entra niente mentre il player e' fuori schermo.
*   L'inseguimento del main loop NON rimedia: RettangoloScrollNelCentro e
*   CalcolaInseguimentoCameraY muovono la camera solo quando il player spinge
*   contro il centro, e un player fuori dalla finestra non ci spinge mai.
*   La camera va dove il player cade su (CENTER_X, CENTER_Y), poi si ferma ai
*   bordi del mondo. I due limiti sono gli stessi che usa il clamp qui sotto:
*   SCROLL_CAMERA_PX in orizzontale e TILEYMAX*16 in verticale, e all'estremo
*   la frazione di pixel deve essere zero, esattamente come li' - per questo si
*   limita la camera IN PIXEL e poi si divide, invece di limitare la tile.
*
*   VA CHIAMATA DOPO DisegnaSfondo, ma dal 24 settembre 2026 NON E' PIU' UN
*   VINCOLO: e' solo l'ordine che ha senso. Prima lo era davvero, perche'
*   DisegnaSfondo leggeva TileX per scegliere la colonna di partenza - relitto
*   di Path A - e con TileX diverso da zero montava lo sfondo spostato. Quel
*   relitto e' stato tolto, ed e' quello che permette a RicostruisciMondo di
*   rifare la sequenza a gioco acceso, con la camera dove l'ha lasciata il
*   giocatore.
*   DISTRUGGE: nulla (salva tutto).
CentraCameraSulPlayer:
	MOVEM.L	D0-D1,-(SP)
	; ----- orizzontale -----
	MOVE.W	Player+bob_WorldX,D0
	SUB.W	#CENTER_X,D0
	BPL.S	.x_pos
	MOVEQ	#0,D0					; player piu' a sinistra del centro
.x_pos:
	CMP.W	#SCROLL_CAMERA_PX,D0
	BLE.S	.x_ok
	MOVE.W	#SCROLL_CAMERA_PX,D0	; oltre il bordo destro del mondo
.x_ok:
	MOVE.W	D0,D1
	AND.W	#15,D1
	MOVE.W	D1,PixelOffX
	LSR.W	#4,D0
	MOVE.W	D0,TileX
	; ----- verticale -----
	MOVE.W	Player+bob_WorldY,D0
	SUB.W	#CENTER_Y,D0
	BPL.S	.y_pos
	MOVEQ	#0,D0
.y_pos:
	CMP.W	#TILEYMAX*16,D0
	BLE.S	.y_ok
	MOVE.W	#TILEYMAX*16,D0
.y_ok:
	MOVE.W	D0,D1
	AND.W	#15,D1
	MOVE.W	D1,PixelOffY
	LSR.W	#4,D0
	MOVE.W	D0,TileY
	MOVEM.L	(SP)+,D0-D1
	RTS

* ControllaPassaggio - i bordi VERTICALI della mappa sono PORTE
*   Dal 26 settembre 2026 guarda tutti e due i bordi e la destinazione la legge
*   da MappaLink: -1 vuol dire che quel bordo resta un muro.
*
*   COME SI RICONOSCE "SUPERARE IL BORDO". Non come posizione: non ci si arriva
*   mai. AggPosizioneGlobalePlayer fissa il player fra 0 e PLAYER_MAX_X
*   (= MAPPA_COLS*16-BOB_COLL_W = colonna 71 col corpo su 71 e 72), quindi
*   bob_WorldX non esce da quell'intervallo per costruzione. Si riconosce come
*   INTENTO: fermo contro il limite E ancora premuto in quella direzione.
*
*   COSA FOTOGRAFA, e perche' non basta rileggerlo dopo: fra questo istante e
*   il nero passano FADE_LIVELLI quadri, e in quei quadri il gioco continua a
*   girare - il player cammina e cade. Lo stato che deve attraversare la porta
*   (Y, velocita', frazione, appoggio) e' quello di ADESSO, non quello che si
*   trovera' fra sedici quadri.
*
*   VA CHIAMATA SUBITO DOPO AggPosizioneGlobalePlayer, cioe' dopo il clamp e
*   prima che camera e bordi lavorino sulla posizione.
*   DISTRUGGE: D0-D2/A0 - **e non "nulla" come diceva prima**: adesso indicizza
*   una tabella e i registri servono. Sono salvati, ma il commento va letto
*   come contratto e non come rassicurazione.
ControllaPassaggio:
	TST.B	TransFase
	BNE.S	.niente					; una transizione e' gia' in corso
	TST.W	IntentX
	BNE.S	.spinge
.niente:
	RTS
.spinge:
	MOVEM.L	D0-D3/A0,-(SP)

	; ----- ORIZZONTALE: si riconosce dall'INTENTO ------------------------
	; L'ordine (orizzontale prima, verticale dopo) non e' indifferente: in un
	; angolo il player puo' soddisfare due bordi nello stesso quadro. Tenere
	; davanti l'orizzontale conserva alla lettera il comportamento delle due
	; porte che c'erano prima che i bordi verticali esistessero.
	MOVEQ	#VERSO_DX,D2
	MOVE.W	IntentX,D0
	BEQ.S	.vert					; non spinge di lato: guarda i verticali
	BPL.S	.destra
	MOVEQ	#VERSO_SX,D2
	TST.W	Player+bob_WorldX
	BEQ.S	.trova					; contro il bordo sinistro
	BRA.S	.vert
.destra:
	CMP.W	#PLAYER_MAX_X,Player+bob_WorldX
	BGE.S	.trova

	; ----- VERTICALE: si riconosce dalla VELOCITA', non dall'intento ------
	; `IntentY` non e' un tasto: lo produce la fisica. "Spingere in giu'" non
	; esiste, si CADE, quindi l'intento non distingue niente.
	; Il SEGNO della velocita' serve soprattutto all'ARRIVO, ed e' lui a
	; rendere simmetrici i due bordi: chi entra dal bordo basso salendo ci si
	; trova sopra per un quadro, e senza il segno la porta di sotto
	; riscatterebbe subito rimandandolo da dove e' venuto.
	; FINESTRA DI UN QUADRO, sul bordo basso, e va saputa: appena il player
	; viene fissato a PLAYER_MAX_Y, il quadro dopo `.y_blocked` in
	; AggPosizioneGlobalePlayer lo dichiara `Grounded` e gli azzera `VelY` -
	; a mezz'aria, perche' sotto la riga 23 non c'e' niente su cui stare.
	; Quindi l'unico quadro in cui "e' in fondo E sta cadendo" e' quello in cui
	; ci arriva, ed e' esattamente quello che serve.
.vert:
	; I due salti a `.esce` qui sotto sono LUNGHI (.W) e non corti: con
	; l'arrivo dei bordi verticali la routine e' cresciuta e
	; `tools/misura-salti.py` li ha misurati a +132 e +120 byte, cioe' il primo
	; oltre i 127 di uno spiazzamento corto. Costano due byte l'uno e non
	; dipendono da quanto cresce ancora il blocco qui sotto.
	MOVE.W	Player+bob_VelY,D0
	BEQ.W	.esce					; ne' sale ne' scende: nessun bordo verticale
	BPL.S	.giu
	MOVEQ	#VERSO_SU,D2
	TST.W	Player+bob_WorldY
	BEQ.S	.trova					; testa al bordo alto, e sta salendo
	BRA.W	.esce
.giu:
	MOVEQ	#VERSO_GIU,D2
	CMP.W	#PLAYER_MAX_Y,Player+bob_WorldY
	BLT.S	.esce
.trova:
	; MappaLink[mappa][verso], VERSI_N word per blocco. I due versi verticali
	; ci sono in tabella ma nessuno li scatta ancora: li accendera' la consegna
	; dei bordi alto e basso, e fino ad allora valgono -1 come qualunque muro.
	MOVE.W	MappaCorrente,D0
	MULU.W	#VERSI_N*2,D0			; byte di tabella per blocco
	MOVE.W	D2,D1
	ADD.W	D1,D1					; il verso in byte
	ADD.W	D1,D0
	LEA		MappaLink,A0
	MOVE.W	(A0,D0.W),D0
	BMI.S	.esce					; -1: quel bordo e' un muro

	MOVE.W	D0,TransDest
	MOVE.W	D2,TransVerso
	; Si fotografano ENTRAMBE le coordinate: quale delle due sopravvive lo
	; decide il verso, e deciderlo qui vorrebbe dire ripetere quella scelta in
	; due posti.
	MOVE.W	Player+bob_WorldX,TransX
	MOVE.W	Player+bob_WorldY,TransY
	MOVE.W	Player+bob_VelY,TransVelY
	MOVE.W	Player+bob_FracY,TransFracY
	MOVE.W	Player+bob_Grounded,TransSuolo

	IFNE	FADE_PASSAGGIO
	; Non si attraversa niente QUI: si accende la dissolvenza, e il passaggio
	; vero avviene quando lo schermo e' nero, dentro AggiornaTransizione.
	MOVE.W	#FADE_LIVELLI-1,TransLivello
	CLR.B	TransRitmo
	MOVE.B	#1,TransFase
	ENDC
	IFEQ	FADE_PASSAGGIO
	IFNE	TENDA_PASSAGGIO
	BSR.W	MondoNascondi
	ENDC
	BSR.W	EseguiPassaggio
	IFNE	TENDA_PASSAGGIO
	BSR.W	MondoMostra
	ENDC
	ENDC
.esce:
	MOVEM.L	(SP)+,D0-D3/A0
	RTS

* EseguiPassaggio - si attraversa: mappa nuova, player al bordo opposto
*   Gira quando lo schermo e' nero (o subito, con FADE_PASSAGGIO a 0).
*   1. MappaPtr passa alla mappa di destinazione;
*   2. la X e' quella SPECCHIATA (si esce a destra, si entra a sinistra) e la Y
*      e' quella fotografata allo scatto;
*   3. **velocita', frazione e appoggio si rimettono**: un salto prosegue
*      attraverso la porta e atterra di la';
*   4. la casella d'arrivo si VALIDA. Tenere la Y non garantisce che la
*      colonna di bordo della mappa nuova sia libera a quella quota, e uno
*      spawn dentro un muro in questo progetto e' gia' costato due volte
*      ("player bloccato", "nemico murato"). Se nessuna quota e' libera il
*      passaggio si ANNULLA e si torna alla mappa di prima: meglio una porta
*      che non si apre di un player murato.
*   5. il falo' si ricerca nella mappa nuova, poi si ricostruisce il mondo.
*
*   COSA NON FA ANCORA: i nemici. EnemyInitTable ha coordinate scritte a mano
*   che appartengono alla mappa 0, e nessuno le rifa' qui. Dopo una porta i
*   nemici restano dove erano. E' il buco noto, e si chiude con una TILE_NEMICO
*   piu' una scansione, come si e' fatto per la partenza e per il falo'.
*   Richiede A6 = $DFF000 (lo vuole RicostruisciMondo).
*   DISTRUGGE: nulla (salva tutto).
EseguiPassaggio:
	MOVEM.L	D0-D3/A0,-(SP)

	; ----- 1. la mappa nuova, tenendo da parte quella di prima -----------
	MOVE.W	MappaCorrente,D3		; per poter tornare indietro
	MOVE.W	TransDest,D0
	BSR.W	ImpostaBlocco

	; ----- 2. dove si entra: l'asse ATTRAVERSATO si specchia, l'altro si
	;          conserva. Una regola sola per tutti e quattro i versi.
	MOVE.W	TransX,D0
	MOVE.W	TransY,D1
	MOVE.W	TransVerso,D2
	CMP.W	#VERSO_SX,D2
	BNE.S	.nosx
	MOVE.W	#PLAYER_MAX_X,D0		; uscito a sinistra -> entra dal bordo destro
	BRA.S	.cercaY
.nosx:
	CMP.W	#VERSO_DX,D2
	BNE.S	.nodx
	MOVEQ	#0,D0					; uscito a destra -> entra dal bordo sinistro
	BRA.S	.cercaY
.nodx:
	CMP.W	#VERSO_SU,D2
	BNE.S	.nosu
	MOVE.W	#PLAYER_MAX_Y,D1		; uscito in alto -> entra dal bordo basso
	BRA.S	.cercaX
.nosu:
	MOVEQ	#0,D1					; VERSO_GIU: caduto giu' -> entra dal bordo alto

	; ----- 3. la casella d'arrivo si VALIDA, cercando sull'asse che si
	;          CONSERVA: la coordinata specchiata e' il bordo, e spostarla
	;          vorrebbe dire entrare in mezzo alla mappa invece che dal bordo.
.cercaX:
	BSR.W	CercaXLibera
	BMI.S	.rinuncia
	BRA.S	.mettiamo
.cercaY:
	BSR.W	CercaYLibera
	BMI.S	.rinuncia
.mettiamo:
	MOVE.W	D0,Player+bob_WorldX
	MOVE.W	D1,Player+bob_WorldY
	MOVE.W	TransVelY,Player+bob_VelY
	MOVE.W	TransFracY,Player+bob_FracY
	MOVE.W	TransSuolo,Player+bob_Grounded

	; ----- 4. il mondo nuovo ---------------------------------------------
	BSR.W	TrovaFalo				; la TILE_LUCE della mappa nuova
	BSR.W	RicostruisciMondo
	MOVEM.L	(SP)+,D0-D3/A0
	RTS

.rinuncia:
	; Nessuna quota libera sulla colonna di bordo: si rimette la mappa di prima
	; e non si sposta niente. La dissolvenza finisce il suo giro e riaccende sul
	; mondo di partenza, che a schermo si legge come "la porta non si e' aperta".
	MOVE.W	D3,D0
	BSR.W	ImpostaBlocco
	MOVEM.L	(SP)+,D0-D3/A0
	RTS

* ImpostaBlocco - il blocco corrente, indice e puntatore nello stesso posto
*   D0.W = indice del blocco. DISTRUGGE: nulla.
*
*   `MappaCorrente` (l'indice) e `MappaPtr` (il puntatore) sono lo STESSO fatto
*   detto in due modi: il puntatore esiste solo perche' le cinque routine che
*   leggono la mappa lo vogliono pronto - IsTileBlocked lo rilegge a ogni sonda
*   del box, e un LSL piu' una LEA per sonda si pagherebbero. Due variabili per
*   un fatto solo divergono: qui c'e' l'UNICO posto che le scrive, e chi cambia
*   blocco passa da qui o sbaglia.
*   Per lo stesso motivo `MappaPtr` NASCE A ZERO e non a MAPPA1: il nome della
*   prima mappa sta scritto in un posto solo, `MappaBase`, e al boot ci arriva
*   questa routine leggendo `MappaCorrente`.
ImpostaBlocco:
	MOVEM.L	D0/A0,-(SP)
	MOVE.W	D0,MappaCorrente
	LSL.W	#2,D0					; una voce di MappaBase e' un long
	LEA		MappaBase,A0
	MOVE.L	(A0,D0.W),MappaPtr
	MOVEM.L	(SP)+,D0/A0
	RTS

* CercaYLibera - la quota piu' vicina a D1 in cui il box del player non collide
*   Input:  D0 = X d'arrivo (non cambia), D1 = Y desiderata
*   Output: D1 = Y buona, oppure NEGATIVA se non ce n'e' nessuna (BMI)
*   Prova prima la quota chiesta, poi si allontana a passi di 16 px alternando
*   SOPRA e SOTTO: la piu' vicina vince, e a pari distanza vince quella sopra,
*   perche' un player spinto in alto da un pavimento e' piu' naturale di uno
*   tirato in basso da un soffitto.
*   Il passo e' 16 px, la tile: dentro una tile non c'e' niente da cercare.
*   DISTRUGGE: D1 (e' l'uscita). Salva il resto, **A1 compreso**: IsBoxBlocked
*   se lo porta via passando da IsTileBlocked, e se non lo salvassi qui la
*   catena EseguiPassaggio -> AggiornaTransizione direbbe "distrugge nulla"
*   raccontando una bugia.
CercaYLibera:
	MOVEM.L	D0/D2-D4/A1,-(SP)
	MOVE.W	D1,D3					; D3 = la quota chiesta
	MOVEQ	#0,D4					; D4 = distanza
.giro:
	MOVE.W	D3,D1
	SUB.W	D4,D1
	BMI.S	.sotto					; sopra il bordo alto: salta
	BSR.W	IsBoxBlocked
	BEQ.S	.trovata
.sotto:
	TST.W	D4
	BEQ.S	.avanti					; distanza 0: sopra e sotto sono la stessa
	MOVE.W	D3,D1
	ADD.W	D4,D1
	CMP.W	#PLAYER_MAX_Y,D1
	BGT.S	.avanti					; sotto il bordo basso: salta
	BSR.W	IsBoxBlocked
	BEQ.S	.trovata
.avanti:
	ADDQ.W	#8,D4
	ADDQ.W	#8,D4					; passo 16: ADDQ arriva a 8
	CMP.W	#PLAYER_MAX_Y,D4
	BLE.S	.giro
	MOVE.W	#-1,D1					; nessuna quota libera
.trovata:
	MOVEM.L	(SP)+,D0/D2-D4/A1
	; LA TST NON E' DECORATIVA. Il chiamante decide con un BMI, cioe' legge il
	; flag N: sull'uscita POSITIVA ci si arriva da un `BEQ` dopo IsBoxBlocked,
	; che lascia N a un valore suo, e su quel valore il BMI avrebbe annullato
	; il passaggio a caso - un difetto che si presenta come "a volte la porta
	; non si apre" e non porta a IsBoxBlocked nemmeno per sbaglio. MOVEM non
	; tocca il CCR, quindi la TST va QUI, dopo il ripristino, e D1 non e' fra i
	; registri ripristinati proprio perche' e' l'uscita.
	TST.W	D1
	RTS

* CercaXLibera - la colonna piu' vicina a D0 in cui il box del player non collide
*   La gemella di CercaYLibera per i bordi ALTO e BASSO: la' si attraversa in
*   verticale, quindi la coordinata che si conserva e la' che va spostata se la
*   casella e' occupata. Stessa forma, stessi passi da 16 px, stessa regola del
*   "a pari distanza vince quello prima" - qui vuol dire a sinistra.
*   Input:  D0 = X desiderata, D1 = Y d'arrivo (non cambia)
*   Output: D0 = X buona, oppure NEGATIVA se non ce n'e' nessuna (BMI)
*   DIPENDENZA DICHIARATA: il ciclo tiene la Y in D1 ATTRAVERSO le chiamate a
*   IsBoxBlocked, quindi si appoggia al fatto che quella non se la porti via.
*   E' vero - AggPosizioneGlobalePlayer usa D1 subito dopo averla chiamata - ma
*   e' un contratto di un'altra routine, non una proprieta' di questa: se un
*   giorno IsBoxBlocked comincia a usare D1 come appunto, qui la ricerca si
*   mette a sondare quote a caso senza dare errore. La gemella CercaYLibera non
*   ha questo appoggio perche' ricarica la sua coordinata da D3 a ogni sonda.
*   DISTRUGGE: D0 (e' l'uscita). Salva il resto, A1 compreso, per la stessa
*   ragione scritta su CercaYLibera.
CercaXLibera:
	MOVEM.L	D1-D4/A1,-(SP)
	MOVE.W	D0,D3					; D3 = la colonna chiesta
	MOVEQ	#0,D4					; D4 = distanza
.giro:
	MOVE.W	D3,D0
	SUB.W	D4,D0
	BMI.S	.destra					; oltre il bordo sinistro: salta
	BSR.W	IsBoxBlocked
	BEQ.S	.trovata
.destra:
	TST.W	D4
	BEQ.S	.avanti					; distanza 0: sinistra e destra coincidono
	MOVE.W	D3,D0
	ADD.W	D4,D0
	CMP.W	#PLAYER_MAX_X,D0
	BGT.S	.avanti					; oltre il bordo destro: salta
	BSR.W	IsBoxBlocked
	BEQ.S	.trovata
.avanti:
	ADDQ.W	#8,D4
	ADDQ.W	#8,D4					; passo 16: ADDQ arriva a 8
	CMP.W	#PLAYER_MAX_X,D4
	BLE.S	.giro
	MOVE.W	#-1,D0					; nessuna colonna libera
.trovata:
	MOVEM.L	(SP)+,D1-D4/A1
	; La TST come sulla gemella: il chiamante decide con un BMI e l'uscita
	; positiva arriva da un BEQ dopo IsBoxBlocked, che lascia N a un valore suo.
	TST.W	D0
	RTS

* MondoNascondi / MondoMostra - la tenda sul campo di gioco
*   Spengono e riaccendono i SOLI piani della fascia di gioco, scrivendo il
*   dato della copperlist (CL_Bplcon0) e non il registro. Scriverlo con la CPU
*   varrebbe fino al quadro dopo e basta: il copper riscrive BPLCON0 a ogni
*   giro, ed e' la stessa lezione che BPLCON1 ha gia' insegnato a questo
*   progetto.
*
*   QUELLO CHE RESTA A VIDEO, e non e' un dettaglio: il PANNELLO. La sua
*   fascia ha un BPLCON0 suo, piu' in basso nella copperlist, che questa
*   coppia non tocca - quindi durante il passaggio strumenti, punteggio e
*   scritta restano al loro posto, e si spegne solo il mondo. Spegnere BPLEN
*   in DMACON sarebbe stato una riga sola e avrebbe portato via anche quelli.
*
*   Il campo di gioco senza piani mostra la voce 0, cioe' la tinta del cielo
*   che il copper scrive comunque: non nero, ma lo stesso colore su cui e'
*   disegnata la parallasse.
*   DISTRUGGE: nulla.
MondoNascondi:
	MOVE.W	#BPLCON0_ZERO,CL_Bplcon0+2
	RTS

MondoMostra:
	MOVE.W	#BPLCON0_GIOCO,CL_Bplcon0+2
	RTS

* RicostruisciMondo - il pezzo RIPETIBILE della sequenza di boot
*   NON e' la stessa sequenza dello START, e il 24 settembre 2026 qui c'era
*   scritto che lo era. Il blocco misurato al boot contiene QUATTRO chiamate in
*   piu', e ognuna resta fuori da qui per un motivo che si puo' controllare:
*     DisegnaPannello          PannelloBuf si costruisce una volta e i suoi
*                              puntatori nella copperlist non si toccano piu'.
*     InitParallasseSprite     mette i canali sulla posa 0 perche' il display
*                              non parta su puntatori mai scritti. Al passaggio
*                              sono gia' scritti.
*     AggiornaParallasseSprite la rifa' il ciclo principale a ogni quadro.
*     PathBInit                pezza i segnaposto di CL_Ddf e CL_BplMod: e' la
*                              geometria di Path B, non cambia mai.
*   Piu' il `MOVE.L ...,CurrentDarkDraw`, che ha UN solo punto di scrittura in
*   tutto il sorgente (il boot) e da li' non si muove.
*   **Quindi i numeri RQ del boot e del passaggio NON misurano lo stesso
*   insieme**: il passaggio fa strettamente MENO lavoro. Chi confronta i due
*   numeri come se fossero la stessa cosa attribuisce al passaggio una
*   differenza che sta altrove.
*
*   MISURATO (voce RQ del monitor, tasto P): **41 quadri al boot** (che e'
*   sempre di GIORNO, NightMode nasce a 0) e **44 quadri al primo passaggio
*   vero**, 0,88 secondi di gioco fermo. Il sospetto per la differenza e'
*   PathBBuildDark, che di giorno riempie e torna mentre di notte scandisce
*   tutte le 1752 celle della mappa e punzona un cerchio per ogni TILE_LUCE:
*   si separa in un tasto, passando la porta di giorno e poi di notte (N).
*
*   Finche' la destinazione e' la STESSA mappa non serve nessuna tenda - i due
*   buffer vengono riscritti con lo stesso identico contenuto, e a schermo si
*   vede solo un fermo. **Il giorno che la destinazione cambia la tenda diventa
*   obbligatoria**, altrimenti si guarda il mondo nuovo che si disegna una tile
*   alla volta.
*
*   Il passaggio si MISURA da solo: le stesse MisuraRicAvvia/Chiudi del boot
*   avvolgono la sequenza, quindi dopo la prima porta RQ e RV non sono piu' il
*   numero dell'avvio ma quello della transizione vera, col gioco acceso.
*   Conseguenza da sapere: il quadro del passaggio dura decine di giri di
*   raster, quindi FineLavoro lo conta come quadro perso e DR sale. **Dopo una
*   porta si preme R prima di rimisurare.** R azzera DR, WO e i primi
*   PROF_SLOTS valori, NON RQ e RV: per questo il numero del passaggio
*   sopravvive alla misura del caso peggiore.
*
*   Richiede A6 = $DFF000.
*   DISTRUGGE: nulla (salva tutto).
RicostruisciMondo:
	; Si salva TUTTO e non solo quello che serve qui: sotto ci sono
	; DisegnaSfondo (che si porta via anche D7, perche' la sua MOVEM ne salva
	; solo sei), PathBBuildMaster e PathBBuildDark. Una routine che ne chiama
	; tre e dichiara "distrugge nulla" deve coprire anche quello che
	; distruggono loro, se no il commento e' una bugia che costa un pomeriggio.
	MOVEM.L	D0-D7/A0-A5,-(SP)
	IFNE	PROFILING
	BSR.W	MisuraRicAvvia
	ENDC

	; ----- QUI NON SI TOCCA IL PLAYER -----------------------------------
	; Fino al 26 settembre 2026 questa routine chiamava TrovaPartenza e azzerava
	; ScrllX/Y, IntentX/Y, bob_VelY, bob_FracY e bob_Grounded. Adesso **dove sta
	; il player lo decide CHI CHIAMA**, e sono due con esigenze opposte:
	;   il boot   - InitPlayer ha gia' chiamato TrovaPartenza in coda a se
	;               stesso, quindi la posizione c'e' e le variabili di moto
	;               sono gli zeri con cui nasce la BSS;
	;   la porta  - EseguiPassaggio mette X specchiata e Y conservata, e
	;               RIMETTE velocita' e slancio, perche' un salto deve
	;               proseguire attraverso la porta e atterrare di la'.
	; Azzerare qui vorrebbe dire cancellare proprio quello che la porta ha
	; appena deciso. La routine e' diventata quello che il nome dice: ricostruisce
	; IL MONDO, non lo stato del gioco.

	; ----- il mondo ----------------------------------------------------
	BSR.W	DisegnaSfondo
	BSR.W	CentraCameraSulPlayer
	LEA		SFONDOGRANDE,A0
	LEA		PathBMaster,A1
	BSR.W	PathBBuildMaster		; copia pulita per il restore dei BOB
	LEA		SFONDOGRANDE,A0
	LEA		SFONDOGRANDE_B,A1
	BSR.W	PathBBuildMaster		; stessa mappa nel secondo buffer
	BSR.W	PathBBuildDark			; darkplane statico, in coordinate mondo

	; ----- 4. i rettangoli sporchi dei due buffer ----------------------
	; Parlano del mondo di PRIMA. Ripristinarli non sporcherebbe niente - il
	; master e' appena stato rifatto, quindi la sorgente e' giusta - ma sarebbe
	; lavoro su coordinate che non vogliono piu' dire niente, e il primo quadro
	; dopo la porta e' gia' il piu' caro di tutti. Si svuotano.
	LEA		DirtySetA,A0
	CLR.W	dirty_Count(A0)
	LEA		DirtySetB,A0
	CLR.W	dirty_Count(A0)

	IFNE	PROFILING
	BSR.W	MisuraRicChiudi
	ENDC
	MOVEM.L	(SP)+,D0-D7/A0-A5
	RTS
