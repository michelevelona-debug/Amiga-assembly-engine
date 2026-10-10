; Titolo.i - Schermata del titolo e droide
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

	IFNE	TITLE_TEST_FILL
* TitleTestFill - prova a costanti note sui piani della schermata del titolo
*   Serve a separare due cose che a schermo si somigliano: un percorso di
*   DISPLAY rotto (puntatori, DDF, FMODE, passo fra i piani) da un CONTENUTO
*   o una PALETTE sbagliati. Con valori noti nei piani, quello che esce e'
*   prevedibile, e se non esce quello il difetto e' nel percorso.
*   Come leggere il risultato:
*     modo 1  schermo di UN SOLO colore, piatto      -> il fetch e' sano
*             qualunque cosa diversa da piatto       -> percorso di display
*     modo 2  schermo di un solo colore, DIVERSO dal modo 1
*                                                    -> i piani si separano
*     modo 3  otto bande orizzontali NETTE da 32 righe, ognuna di un colore
*                                                    -> passo fra i piani ok
*             bande sfalsate, oblique o mescolate    -> TITLE_PLANE_SIZE o
*                                                       i BPLxMOD sono sbagliati
*   Gira una volta, prima che il DMA display si accenda.
TitleTestFill:
	MOVEM.L	D0-D3/A0-A1,-(SP)

	; --- tutti i piani a zero: e' la base di tutti e tre i modi ---
	LEA		title_bpl,A0
	MOVE.W	#TITLE_PLANE_SIZE*TITLE_PIANI/4-1,D0
.azzera:
	CLR.L	(A0)+
	DBRA	D0,.azzera

	IFEQ	TITLE_TEST_FILL-2
	; --- modo 2: solo il piano 0, tutto acceso ---
	LEA		title_bpl,A0
	MOVE.W	#TITLE_PLANE_SIZE/4-1,D0
.piano0:
	MOVE.L	#$FFFFFFFF,(A0)+
	DBRA	D0,.piano0
	ENDC

	IFEQ	TITLE_TEST_FILL-3
	; --- modo 3: il piano n acceso solo nelle righe n*32 .. n*32+31 ---
	LEA		title_bpl,A0
	MOVEQ	#0,D1					; D1 = numero del piano
.banda:
	MOVE.L	D1,D2
	MULU	#TITLE_PLANE_SIZE,D2	; inizio del piano n
	MOVEA.L	A0,A1
	ADDA.L	D2,A1
	MOVE.L	D1,D2
	MULU	#32*TITLE_BYTES_PER_ROW,D2	; + la banda n dentro quel piano
	ADDA.L	D2,A1
	MOVE.W	#(32*TITLE_BYTES_PER_ROW)/4-1,D3
.riempi:
	MOVE.L	#$FFFFFFFF,(A1)+
	DBRA	D3,.riempi
	ADDQ.W	#1,D1
	CMP.W	#TITLE_PIANI,D1
	BLT.S	.banda
	ENDC

	MOVEM.L	(SP)+,D0-D3/A0-A1
	RTS
	ENDC

* ImpostaDisplayTitolo / ImpostaDisplayGioco
*   Lo stato di display di una scena, in un posto solo. IN: A6 = $DFF000.
*
* Il blocco della CPU non e' ridondante rispetto alla copperlist: il DMA
* bitplane si accende PRIMA che COP1LC punti alla lista, quindi fra
* l'accensione e la prima passata del copper il prelievo gira con quello che
* ha lasciato la scena precedente. E' esattamente il buco in cui era caduto
* FMODE, che dal blocco CPU mancava.
*
* I valori sono le EQU TIT_* e GIOCO_*, le stesse che leggono le copperlist:
* qui non c'e' un solo numero scritto a mano, ed e' il punto della modifica.
* NESSUN VALORE E' CAMBIATO: sono le stesse dodici MOVE di prima, nello stesso
* ordine, con i letterali sostituiti dalle EQU che valgono lo stesso.
*
* ImpostaDisplayGioco ne scrive TRE e non e' una dimenticanza: la copperlist
* del gioco scrive gia' FMODE, BPLCON0/1/2, i moduli, DDF e DIW a ogni quadro,
* mentre BPLCON3 e BPLCON4 ne stanno fuori di proposito (li governa il blocco
* PALETTE con LOCT alternato). Scriverli anche qui creerebbe la seconda copia
* che questa modifica sta togliendo.
ImpostaDisplayTitolo:
	MOVE.W	#TIT_FMODE,$1FC(A6)		; PRIMA di tutto: decide la larghezza del prelievo
	MOVE.W	#TIT_BPLCON0,$100(A6)	; 8 bitplane + COLOR + ECSENA
	MOVE.W	#TIT_BPLCON1,$102(A6)
	MOVE.W	#TIT_BPLCON2,$104(A6)
	MOVE.W	#TIT_BPLCON3,$106(A6)	; banco 0, LOCT=0, bordo nero
	MOVE.W	#TIT_BPLCON4,$10c(A6)
	MOVE.W	#TIT_BPLMOD,$108(A6)	; BPL1MOD: layout sequenziale
	MOVE.W	#TIT_BPLMOD,$10a(A6)	; BPL2MOD
	; ($a8-$28)/32 = 4 -> cinque prelievi per riga, 5*64 px = 320 px
	MOVE.W	#TIT_DDFSTRT,$92(A6)
	MOVE.W	#TIT_DDFSTOP,$94(A6)
	MOVE.W	#TIT_DIWSTRT,$8e(A6)
	MOVE.W	#TIT_DIWSTOP,$90(A6)
	RTS

ImpostaDisplayGioco:
	MOVE.W	#SCROLL_FMODE_VAL,$1fc(A6)	; prelievo del GIOCO, vedi SCROLL_FETCH_BIT
	MOVE.W	#BPLCON3_LOCT0,$106(A6)
	MOVE.W	#GIOCO_BPLCON4,$10c(A6)		; sprite alle voci 64..79
	RTS

* ============================================================================
* IL DROIDE DELLA SCHERMATA DEL TITOLO
*
* Quattro routine: una di avvio, una per quadro, e due di servizio che fanno
* il lavoro del blitter. La geometria e le ragioni stanno nelle EQU DROIDE_*
* in testa al file.
*
* IL CICLO DI UN QUADRO e' lo stesso dei BOB del gioco, ridotto a un oggetto
* solo: si ripulisce il rettangolo di IERI dal master, si calcola dove sta
* oggi, si disegna. Il ripristino viene PRIMA del calcolo apposta: la posizione
* nuova puo' sovrapporsi alla vecchia, e pulire dopo aver disegnato
* cancellerebbe un pezzo del droide appena messo giu'.
*
* QUANDO GIRA, rispetto al pennello: AspettaVBL torna alla riga VBL_SYNC_LINE
* (220), il droide vive fra le righe di display 119 e 153, cioe' raster 163..197.
* Il pennello e' quindi GIA' passato sopra di lui quando si comincia a
* disegnare, e ha 116 righe di margine prima di ripassarci. Non c'e' corsa.
* ============================================================================

* DroideInit - stato di partenza e copia del titolo nel buffer di lavoro
*   Da chiamare PRIMA di puntare i bitplane, che devono guardare TitoloBuf.
DroideInit:
	MOVEM.L	D0/A0-A1,-(SP)
	LEA		title_bpl,A0			; il master, l'incbin intatto
	LEA		TitoloBuf,A1			; la copia che va a video
	MOVE.W	#TITLE_PLANE_SIZE*TITLE_PIANI/4-1,D0
.copia:
	MOVE.L	(A0)+,(A1)+
	DBRA	D0,.copia
	CLR.W	DroideFase
	CLR.W	DroidePosa
	CLR.W	DroideCont
	MOVE.W	#-1,DroidePrecX			; al primo giro non c'e' scia da togliere
	MOVEM.L	(SP)+,D0/A0-A1
	RTS

* AnimaDroide - un quadro. IN: A6 = $DFF000
AnimaDroide:
	MOVEM.L	D0-D5/A0-A3,-(SP)

	MOVE.W	DroidePrecX,D0			; -1 = non ha ancora disegnato niente
	BMI.S	.nienteDaPulire
	MOVE.W	DroidePrecY,D1
	BSR.W	DroideRipristina
.nienteDaPulire:

	; ---- il percorso: la STESSA tabella letta a due velocita' ----
	; Y avanza il doppio di X (uno scorrimento di differenza), quindi il
	; tragitto e' un otto e non un segmento: fluttua invece di oscillare.
	MOVE.W	DroideFase,D0
	ADD.W	#DROIDE_FASE_PASSO,D0
	MOVE.W	D0,DroideFase
	LEA		TabSeno,A0

	MOVE.W	D0,D1
	LSR.W	#DROIDE_FASE_SH_X,D1
	AND.W	#SENO_VOCI-1,D1			; l'indice con un AND: le voci sono 2^n
	ADD.W	D1,D1
	MOVE.W	(A0,D1.W),D1
	MULS	#DROIDE_AMPI_X,D1		; MULS.W da un risultato LONG
	ASR.L	#SENO_SCALA,D1			; la tabella e' seno*256
	ADD.W	#DROIDE_HOME_X,D1
	MOVE.W	D1,DroideX

	MOVE.W	D0,D2
	LSR.W	#DROIDE_FASE_SH_Y,D2
	AND.W	#SENO_VOCI-1,D2
	ADD.W	D2,D2
	MOVE.W	(A0,D2.W),D2
	MULS	#DROIDE_AMPI_Y,D2
	ASR.L	#SENO_SCALA,D2
	ADD.W	#DROIDE_HOME_Y,D2
	MOVE.W	D2,DroideY

	; ---- la posa ----
	ADDQ.W	#1,DroideCont
	CMP.W	#DROIDE_RITMO,DroideCont
	BLT.S	.stessaPosa
	CLR.W	DroideCont
	ADDQ.W	#1,DroidePosa
	CMP.W	#DROIDE_POSE,DroidePosa
	BLT.S	.stessaPosa
	CLR.W	DroidePosa
.stessaPosa:

	MOVE.W	DroideX,D0
	MOVE.W	DroideY,D1
	BSR.W	DroideDisegna
	MOVE.W	D0,DroidePrecX			; il rettangolo da ripulire al giro dopo
	MOVE.W	D1,DroidePrecY

	MOVEM.L	(SP)+,D0-D5/A0-A3
	RTS

* DroideGeometria - da X,Y all'offset nel piano e allo shift
*   IN:  D0.w = X (px), D1.w = Y (righe)
*   OUT: D2.l = byte dall'inizio di un piano, D3.w = shift orizzontale 0..15
*   Sporca D2/D3/D4, non tocca D0/D1.
DroideGeometria:
	MOVE.W	D0,D3
	AND.W	#15,D3					; shift = X mod 16
	MOVE.W	D1,D2
	MULU.W	#TITLE_BYTES_PER_ROW,D2	; D2.l = riga * pitch del titolo
	MOVE.W	D0,D4
	LSR.W	#4,D4					; word
	ADD.W	D4,D4					; -> byte, sempre pari
	EXT.L	D4
	ADD.L	D4,D2
	RTS

* DroideRipristina - rimette dal master il rettangolo dove stava il droide
*   IN: D0.w = X, D1.w = Y, A6 = $DFF000
*   Il rettangolo e' largo DROIDE_SLOT_W word, cioe' UNA IN PIU' dell'arte:
*   deve coprire anche i pixel che lo shift ha spinto oltre le due word.
DroideRipristina:
	MOVEM.L	D0-D4/A0-A1,-(SP)
	BSR.W	DroideGeometria			; D2 = offset (lo shift qui non serve)
	LEA		title_bpl,A0
	ADDA.L	D2,A0
	LEA		TitoloBuf,A1
	ADDA.L	D2,A1
	BSR.W	AspettaBlitter
	MOVE.W	#$09F0,$40(A6)			; BLTCON0: D = A, copia semplice
	MOVE.W	#$0000,$42(A6)			; BLTCON1: nessuno shift
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM aperte
	MOVE.W	#DROIDE_MOD_DEST,$64(A6)	; BLTAMOD
	MOVE.W	#DROIDE_MOD_DEST,$66(A6)	; BLTDMOD
	MOVEQ	#DROIDE_PIANI-1,D0
.piano:
	BSR.W	AspettaBlitter
	MOVE.L	A0,$50(A6)				; BLTAPT = master
	MOVE.L	A1,$54(A6)				; BLTDPT = copia di lavoro
	MOVE.W	#DROIDE_BLTSIZE,$58(A6)	; avvia
	ADDA.L	#TITLE_PLANE_SIZE,A0
	ADDA.L	#TITLE_PLANE_SIZE,A1
	DBRA	D0,.piano
	MOVEM.L	(SP)+,D0-D4/A0-A1
	RTS

* DroideDisegna - cookie cut delle otto piani con la maschera
*   IN: D0.w = X, D1.w = Y, A6 = $DFF000
*   A = maschera (una sola, non avanza fra i piani), B = arte, C = sfondo.
*   Minterm $CA = (A AND B) OR (NOT A AND C): dove la maschera e' 1 passa
*   l'arte, dove e' 0 resta il titolo.
DroideDisegna:
	MOVEM.L	D0-D5/A0-A3,-(SP)
	BSR.W	DroideGeometria			; D2 = offset, D3 = shift

	MOVE.W	DroidePosa,D4
	MULU.W	#DROIDE_SLOT,D4			; la cella della posa dentro la riga
	LEA		Droide,A2
	ADDA.L	D4,A2					; arte, primo piano
	LEA		DroideMask,A3
	ADDA.L	D4,A3					; maschera, unica per tutti i piani
	LEA		TitoloBuf,A1
	ADDA.L	D2,A1					; sfondo e destinazione, primo piano

	MOVE.W	D3,D5
	LSL.W	#8,D5
	LSL.W	#4,D5					; shift << 12
	MOVE.W	D5,D4					; BLTCON1 = BSH << 12 (shift sull'arte)
	OR.W	#$0FCA,D5				; BLTCON0 = ASH<<12 | USEA-D | cookie cut

	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM aperte: la word di
									; riempimento in coda alla cella fa gia'
									; entrare zeri nella prima word della riga
									; dopo, che e' il motivo per cui c'e'
	MOVE.W	D5,$40(A6)				; BLTCON0
	MOVE.W	D4,$42(A6)				; BLTCON1
	MOVE.W	#DROIDE_MOD_ARTE,$64(A6)	; BLTAMOD = maschera
	MOVE.W	#DROIDE_MOD_ARTE,$62(A6)	; BLTBMOD = arte
	MOVE.W	#DROIDE_MOD_DEST,$60(A6)	; BLTCMOD = sfondo
	MOVE.W	#DROIDE_MOD_DEST,$66(A6)	; BLTDMOD = destinazione

	MOVEQ	#DROIDE_PIANI-1,D0
.piano:
	BSR.W	AspettaBlitter
	MOVE.L	A3,$50(A6)				; BLTAPT = maschera (la stessa ogni piano)
	MOVE.L	A2,$4C(A6)				; BLTBPT = arte di QUESTO piano
	MOVE.L	A1,$48(A6)				; BLTCPT = sfondo
	MOVE.L	A1,$54(A6)				; BLTDPT = destinazione
	MOVE.W	#DROIDE_BLTSIZE,$58(A6)	; avvia
	ADDA.L	#DROIDE_PIANO,A2
	ADDA.L	#TITLE_PLANE_SIZE,A1
	DBRA	D0,.piano
	MOVEM.L	(SP)+,D0-D5/A0-A3
	RTS

* ShowTitle
*   1) Imposta lo stato di display del titolo.
*   2) Copia title_bpl in TitoloBuf (DroideInit) e patcha i puntatori
*      BPL1..8PT, quelli della CPU e quelli della TitleCopperList, su
*      TITOLOBUF: a video va la copia di lavoro, non l'incbin, perche' il
*      droide ci disegna sopra e il master serve intatto per il ripristino.
*   3) Carica la palette AGA 256 colori via CPU da title_pal.
*   4) Punta il copper a TitleCopperList e abilita BPL+COPPER DMA.
ShowTitle:
	MOVEM.L	D0-D1/A1/A6,-(SP)
	IFNE	TITLE_TEST_FILL
	BSR.W	TitleTestFill
	ENDC
	LEA		$DFF000,A6

	BSR.W	ImpostaDisplayTitolo

	; Copia il titolo nel buffer di lavoro. DEVE stare qui, prima che i
	; puntatori guardino TitoloBuf: il DMA non deve mai leggere un buffer
	; ancora vuoto. Da qui in poi title_bpl e' il MASTER e non va a video.
	BSR.W	DroideInit

	; --- Setup BPL pointers via CPU (8 plane SEQUENTIAL, 10240 byte/plane) ---
	MOVE.L	#TitoloBuf,$E0(A6)								; BPL1PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE,$E4(A6)				; BPL2PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE*2,$E8(A6)			; BPL3PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE*3,$EC(A6)			; BPL4PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE*4,$F0(A6)			; BPL5PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE*5,$F4(A6)			; BPL6PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE*6,$F8(A6)			; BPL7PT
	MOVE.L	#TitoloBuf+TITLE_PLANE_SIZE*7,$FC(A6)			; BPL8PT

	; --- Patch BPL pointers anche nella TitleCopperList (per i frame
	;     successivi al primo: il copper li resetta a ogni vertical blank). ---
	LEA		TitleBPL_0,A1
	MOVE.L	#TitoloBuf,D0
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
	; SET + DMAEN + BPLEN + COPEN + BLITEN. Il BLITTER e' l'aggiunta rispetto
	; al $8380 che c'era qui: senza, AnimaDroide scrive BLTSIZE con BLITEN
	; spento, BBUSY resta alto per sempre e AspettaBlitter gira all'infinito.
	; Il gioco non se ne accorgeva perche' fino al droide nessuno blittava
	; prima di DMASET, che arriva solo DOPO il titolo.
 	MOVE.W	#TIT_DMASET,$96(A6)
	MOVE.L	#TitleCopperList,$80(A6)	; COP1LCH
	MOVE.W	D0,$88(A6)					; COPJMP1 strobe

	MOVEM.L	(SP)+,D0-D1/A1/A6
	RTS

* WaitTitleInput
*   Attende che venga premuto SPACE o il tasto fire del joystick (port 1).
*   Aspetta poi il rilascio di entrambi prima di tornare, in modo che il
*   gioco non veda subito un evento di sparo o un edge "spurio".
WaitTitleInput:
	MOVEM.L	D0/A6,-(SP)
	LEA		$DFF000,A6					; AnimaDroide vuole A6 sul chipset
.wait_press:
	BSR.W	AspettaVBL
	BSR.W	AnimaDroide					; il droide fluttua finche' si aspetta
	BSR.W	LeggiTastiera				; aggiorna key_space
	TST.B	key_space
	BNE.S	.pressed
	MOVE.B	$bfe001,D0					; CIA-A PRA: bit 7 = fire joy1 (active low)
	NOT.B	D0
	AND.B	#$80,D0
	BEQ.S	.wait_press					; D0=0 -> fire NON premuto
.pressed:
.wait_release:
	BSR.W	AspettaVBL
	BSR.W	AnimaDroide					; anche col tasto premuto: fermarlo
										; qui lo farebbe scattare al rilascio
	BSR.W	LeggiTastiera
	TST.B	key_space
	BNE.S	.wait_release
	MOVE.B	$bfe001,D0
	NOT.B	D0
	AND.B	#$80,D0
	BNE.S	.wait_release				; D0!=0 -> fire ANCORA premuto

	; Reset stato fire per il gioco
	MOVE.W	#0,FirePrev
	MOVE.B	#0,key_space
	MOVEM.L	(SP)+,D0/A6					; A6 e' entrato nella lista quando il
										; droide ha avuto bisogno del chipset
	RTS
