; PathB.i - Scroll hardware, rettangoli sporchi, master, darkplane
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

; Scroll hardware AGA (Path B). ScrollHW.i e' il modulo definitivo.
; ProtoScroll.i era il banco di prova del passo 1: l'interruttore
; PROTO_SCROLL e' stato tolto il 22 agosto 2026 (valeva 0 da quando Path B
; e' diventato l'architettura), e con lui l'include. Il file resta sul disco.
	include	"ScrollHW.i"

; SCROLL_FETCH_BYTES e DISPLAY_FETCH_BYTES sono lo stesso numero: la seconda
; e' definita come la prima in testa a Gioco.s. Qui non c'e' piu' niente da
; verificare, e prima c'era una guardia.

; Tabella dei colori del gradiente cielo: UNA VOCE PER RIGA RASTER VISIBILE.
; La copperlist vera la genera BuildSkyCopper al boot. CieloCopper.i, che era
; la lista statica gia' srotolata, non serve piu' ed e' stato sostituito da
; questa tabella.
; E' un file GENERATO da tools/gen-cielo.py a partire dall'arte vera a 260
; voci, che sta in tools/CieloGrad-arte-260.src. Non modificarlo a mano: si
; rigenera. Il perche' della riduzione offline sta nell'intestazione di
; BuildSkyCopper, e la posizione dell'orizzonte si sposta da gen-cielo.py.
; Va incluso DOPO la definizione di SKY_STEPS, perche' in fondo c'e' la
; guardia che verifica che la tabella sia ancora 1:1 con le righe raster.
	include	"CieloGrad.i"

; ScrollPathB - lo scroll del gioco, versione hardware
; Sostituisce GestisciShiftPixel + CopiaVideo + AggiornaTiles con
; aritmetica sui puntatori. Il costo per frame passa da centinaia di
; righe raster a una manciata di istruzioni.
; La camera in pixel si ricava da quella a tile che il gioco gia'
; mantiene: CameraX = TileX*16 + PixelOffX, idem per Y. Non serve
; toccare ControllaBordi, RettangoloScrollNelCentro o CalcolaInseguimentoCameraY:
; continuano a lavorare come prima, e qui si legge solo il risultato.
ScrollPathB:
	MOVEM.L	D0-D5/A0-A2,-(SP)

	MOVE.W	TileX,D0
	LSL.W	#4,D0
	ADD.W	PixelOffX,D0			; D0 = CameraX in pixel
	MOVE.W	TileY,D1
	LSL.W	#4,D1
	ADD.W	PixelOffY,D1			; D1 = CameraY in pixel

	; La camera EFFETTIVA (dopo l'eventuale freeze) va condivisa: se
	; MostraProfilo rileggesse TileX/PixelOffX scriverebbe i numeri in una
	; posizione che si muove mentre il display sta fermo, e si sovrappongono.
	MOVE.W	D0,PathBCamX
	MOVE.W	D1,PathBCamY

	; Il RITARDO di BPLCON1 serve a darkplane e parallasse per compensare.
	; BPLCON1 ritarda TUTTI i piani, ma quei due vivono in coordinate
	; SCHERMO e non devono scorrere: senza compensazione tremerebbero a ogni
	; pixel di scroll fine.
	; QUI C'ERA UNA COPIA della formula, col 64 cablato, e il commento accanto
	; diceva pure "la stessa di ScrollHWCalc" - cioe' denunciava da solo la
	; duplicazione. Passando al fetch a 32 bit ScrollHWCalc e' andato al blocco
	; da 32 px mentre questa copia continuava a calcolare quello da 64: la
	; parallasse compensava di un valore che il display non applicava, e
	; scattava di 32 px a ogni confine. Adesso il ritardo lo scrive
	; ScrollHWCalc, che e' l'unico posto dove viene calcolato.
	LEA		SFONDOGRANDE,A0			; qui serve solo come base per il calcolo
	BSR.W	ScrollHWCalc			; -> D2 offset, D3 BPLCON1, PathBDelay

	; Col doppio buffer il calcolo resta QUI (la parallasse ha bisogno di
	; PathBDelay), ma l'APPLICAZIONE va in coda al blocco: si pubblica il
	; buffer solo quando e' finito. Quindi si mettono da parte i due valori.
	MOVE.L	D2,WorldPtrOfs			; D2 e' gia' un OFFSET puro, non un indirizzo
	MOVE.W	D3,WorldBplCon1

	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

* ScrollPathBApply - pubblica il buffer appena disegnato
* Da chiamare in CODA al blocco di lavoro, quando il disegno e' finito.
* Scrive i puntatori dei piani 1-5 su WorldDraw, il piano 6 sul darkplane con
* lo STESSO offset (deve scorrere insieme, non un frame avanti) e BPLCON1.
* Poi scambia WorldDraw/WorldShow e i due set di rettangoli sporchi.
* Il blocco di lavoro scavalca il confine del quadro, quindi questa scrittura
* cade dopo che il copper ha gia' riletto la copperlist: vale dal quadro
* successivo. E anche se il blocco finisse cosi' presto da arrivare in tempo
* per il quadro subito dopo, andrebbe bene lo stesso — il disegno e' concluso.
* E' sicura in entrambi i casi: e' la proprieta' che rende inutile la corsa
* col pennello.
ScrollPathBApply:
	MOVEM.L	D0-D5/A0-A2,-(SP)
	MOVE.L	WorldPtrOfs,D2
	MOVE.W	WorldBplCon1,D3

	MOVEA.L	WorldDraw,A0			; il buffer appena finito diventa quello a video
	LEA		BitPlaneTiles,A1
	LEA		CL_BplCon1,A2
	MOVEQ	#5,D4					; i 5 piani dello sfondo
	MOVE.L	#SFONDO_PLANE_SIZE,D5
	BSR.W	ScrollHWApply

	; Il darkplane e' in coordinate MONDO come i piani 1-5 e usa lo STESSO
	; offset. Va pubblicato QUI insieme a loro: applicandolo presto scorrerebbe
	; un frame avanti rispetto alla mappa.
	LEA		PathBDarkPlane,A0
	ADDA.L	D2,A0
	LEA		BitPlaneTiles+5*8,A1	; sesta coppia di MOVE = BPL6PT
	MOVE.L	A0,D0
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)

	; Qui stava la pubblicazione della parallasse (SwapParBuffers), che doveva
	; entrare in vigore nello stesso quadro del BPLCON1 scritto due righe sopra.
	; Con la parallasse sugli sprite non c'e' piu' niente da pubblicare: gli
	; sprite non sono doppio-bufferizzati e non passano da BPLCON1.

	; --- scambio dei buffer e dei rispettivi set di rettangoli sporchi ---
	MOVE.L	WorldShow,D0
	MOVE.L	WorldDraw,D1
	MOVE.L	D1,WorldShow
	MOVE.L	D0,WorldDraw
	MOVE.L	CurDirty,D0
	CMP.L	#DirtySetA,D0
	BEQ.S	.toB
	MOVE.L	#DirtySetA,CurDirty
	BRA.S	.fatto
.toB:
	MOVE.L	#DirtySetB,CurDirty
.fatto:
	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

; RESTORE DEI BOB (passo 3b)
; Senza CopiaVideo nessuno ripulisce piu' lo sfondo dietro ai BOB, che
; quindi lasciano scie. La soluzione: un BUFFER MASTER con la mappa
; pulita, copiato una volta all'init, da cui si ripristina il rettangolo
; di ogni BOB prima di ridisegnarlo.
; Costa UN blit di restore per piano contro i DUE del save/restore
; classico (salva-prima, ripristina-dopo), e non serve memoria per i
; salvataggi: il master c'e' gia'.
; Ogni BOB registra il proprio rettangolo mentre lo disegna; il frame
; dopo, PathBRestoreAll li ripulisce tutti e svuota la lista. I
; rettangoli NON hanno piu' larghezza fissa: ogni voce porta la propria
; (dirty_Width), perche' i bob hanno geometrie diverse (omino/nemico 32 px,
; pietra 16). Le barre vita, che erano l'altro cliente a 2 word, non
; esistono piu' nel codice.
; Quanti rettangoli entrano nel set. DERIVATO dai clienti veri, non ricopiato:
; un bob per ciascuno (BOB_TOTALI, oggi 7 col falo'), piu' un margine di 8.
; L'UNO in piu' era del testo del profiler, che dall'8 settembre registrava il
; proprio blocco come un bob; **dal 23 settembre il monitor sta nel pannello e
; non registra piu' niente**, quindi quel posto adesso e' margine e non un
; cliente. Resta nella formula perche' togliendolo il valore scenderebbe a 15 e
; non si comprerebbe nulla. Se il set si riempie il rettangolo in piu' viene
; ignorato (vedi .pieno): una scia, non una scrittura fuori array.
PATHB_DIRTY_MAX EQU     BOB_TOTALI+1+8

; PathBRegistraDirty - annota un rettangolo da ripulire al prossimo frame
; IN: A1 = indirizzo nel world buffer (piano 1), D4.w = righe,
;     D5.w = larghezza in WORD (era la costante BOB_BLIT_W)
; Preserva tutto. Se la lista e' piena il rettangolo viene ignorato:
; meglio una scia occasionale che scrivere fuori dall'array.
PathBRegistraDirty:
	MOVEM.L	D0-D1/A0-A2,-(SP)
	MOVEA.L	CurDirty,A2				; set del buffer in cui stiamo disegnando
	MOVE.W	dirty_Count(A2),D0
	CMP.W	#PATHB_DIRTY_MAX,D0
	BGE.S	.pieno
	; si memorizza l'OFFSET dall'inizio del buffer, non l'indirizzo assoluto
	MOVE.L	A1,D1
	SUB.L	WorldDraw,D1
	LEA		dirty_Ofs(A2),A0
	MOVE.W	D0,-(SP)
	ADD.W	D0,D0
	ADD.W	D0,D0					; *4 = posizione nella lista di long
	ADDA.W	D0,A0
	MOVE.L	D1,(A0)
	MOVE.W	(SP)+,D0
	ADD.W	D0,D0					; *2 = posizione nelle liste di word
	LEA		dirty_Rows(A2),A0
	ADDA.W	D0,A0
	MOVE.W	D4,(A0)
	LEA		dirty_Width(A2),A0		; ogni voce porta la propria larghezza
	ADDA.W	D0,A0
	MOVE.W	D5,(A0)
	ADDQ.W	#1,dirty_Count(A2)
.pieno:
	MOVEM.L	(SP)+,D0-D1/A0-A2
	RTS

; PathBRestoreAll - ripristina dal master tutti i rettangoli sporchi
; IN: A6 = $DFF000
PathBRestoreAll:
	MOVEM.L	D0-D5/A0-A4,-(SP)
	MOVEA.L	CurDirty,A2
	MOVE.W	dirty_Count(A2),D0
	BEQ.W	.fine
	SUBQ.W	#1,D0

	BSR.W	AspettaBlitter
	MOVE.W	#$09F0,$40(A6)			; BLTCON0: D = A (copia semplice)
	MOVE.W	#$0000,$42(A6)			; BLTCON1
	MOVE.L	#$ffffffff,$44(A6)		; maschere aperte
	; I moduli NON si possono piu' settare una volta sola fuori dal ciclo:
	; dipendono dalla larghezza del singolo rettangolo, che ora varia.

	; A2 tiene ancora il set corrente: da qui si ricavano le tre liste.
	; A3/A4 PRIMA di A2, perche' l'ultima LEA sovrascrive la base.
	LEA		dirty_Rows(A2),A3
	LEA		dirty_Width(A2),A4
	LEA		dirty_Ofs(A2),A2		; da qui A2 scorre la lista degli offset
.rect:
	MOVE.L	(A2)+,D2				; D2 = offset dall'inizio del buffer
	MOVE.W	(A4)+,D5				; larghezza in word DI QUESTO rettangolo
	MOVE.W	(A3)+,D4				; righe
	BEQ.S	.next					; rettangolo vuoto: salta

	; con l'offset non serve piu' risalire dall'indirizzo assoluto:
	; destinazione = buffer in disegno + offset, sorgente = master + offset
	MOVEA.L	WorldDraw,A1
	ADDA.L	D2,A1
	ADD.L	#PathBMaster,D2
	MOVEA.L	D2,A0

	; modulo = pitch del mondo meno i byte davvero blittati per riga
	MOVE.W	D5,D2
	ADD.W	D2,D2					; D2 = larghezza in BYTE
	NEG.W	D2
	ADD.W	#SFONDO_PITCH,D2		; D2 = SFONDO_PITCH - larghezza in byte
	BSR.W	AspettaBlitter
	MOVE.W	D2,$64(A6)				; BLTAMOD (master)
	MOVE.W	D2,$66(A6)				; BLTDMOD (world)

	LSL.W	#6,D4
	ADD.W	D5,D4					; BLTSIZE = righe<<6 | larghezza in word

	MOVEQ	#5-1,D3
.plane:
	BSR.W	AspettaBlitter
	MOVE.L	A0,$50(A6)				; BLTAPT = master
	MOVE.L	A1,$54(A6)				; BLTDPT = world
	MOVE.W	D4,$58(A6)				; BLTSIZE -> avvia
	ADD.L	#SFONDO_PLANE_SIZE,A0
	ADD.L	#SFONDO_PLANE_SIZE,A1
	DBRA	D3,.plane
.next:
	DBRA	D0,.rect
	MOVEA.L	CurDirty,A2				; A2 e' stato avanzato: ricarica la base
	CLR.W	dirty_Count(A2)
.fine:
	MOVEM.L	(SP)+,D0-D5/A0-A4
	RTS

; PathBBuildMaster - copia il world pulito nel master (una volta, init)
; Va chiamata DOPO DisegnaSfondo e PRIMA che qualcuno disegni BOB.
; Copia 5 piani da A0 ad A1 col blitter. A0/A1 sono INPUT: serve sia per il
; master sia per inizializzare il secondo buffer del mondo.
PathBBuildMaster:
	MOVEM.L	D0/A0-A1,-(SP)
	BSR.W	AspettaBlitter
	MOVE.W	#$09F0,$40(A6)
	MOVE.W	#$0000,$42(A6)
	MOVE.L	#$ffffffff,$44(A6)
	MOVE.W	#0,$64(A6)				; nessun modulo: piano contiguo
	MOVE.W	#0,$66(A6)
	MOVEQ	#5-1,D0
.plane:
	BSR.W	AspettaBlitter
	IFNE	PROFILING
	; qui il piano precedente e' FINITO: un campione ogni 64000 byte copiati,
	; che sono circa 0,9 quadri. E' l'intervallo piu' lungo di tutta la
	; sequenza, ed e' anche il punto in cui RV puo' perdere un giro se il DMA
	; bitplane e' acceso: per questo c'e' RQ a controllarlo.
	BSR.W	MisuraRicPassa
	ENDC
	MOVE.L	A0,$50(A6)
	MOVE.L	A1,$54(A6)
	; un piano intero a strisce da 64 word: vedi COPIA_PIANO_* in testa al
	; file. NON (SFONDO_HEIGHT<<6)|(SFONDO_PITCH/2): con pitch oltre 128 byte
	; la larghezza sborda nel campo altezza.
	MOVE.W	#COPIA_PIANO_BLT,$58(A6)
	ADD.L	#SFONDO_PLANE_SIZE,A0
	ADD.L	#SFONDO_PLANE_SIZE,A1
	DBRA	D0,.plane
	BSR.W	AspettaBlitter
	MOVEM.L	(SP)+,D0/A0-A1
	RTS

; DARKPLANE STATICO
; Le luci sono tutte FISSE: la scansione cerca TILE_LUCE nella mappa e
; non esiste nessuna luce che segua il player. Quindi il darkplane
; dipende SOLO dalla camera, e ricalcolarlo ogni frame era lavoro
; buttato: 18 cerchi da 15 righe raster ciascuno, 302 righe per frame.
; Ora si disegna UNA VOLTA in coordinate MONDO, con lo stesso layout dei
; piani 1-5 (pitch SFONDO_PITCH, guardia a sinistra), e scorre con loro
; muovendo BPL6PT. Il costo per frame diventa ZERO.
; Va ricostruito solo quando NightMode cambia (tasto N).
; Spariscono di conseguenza: il fill per frame, il doppio buffer, e la
; compensazione di BPLCON1 -- il darkplane ora e' in coordinate mondo
; come i piani 1-5, quindi lo shift lo riguarda esattamente come loro.
PathBBuildDark:
	MOVEM.L	D0-D7/A0-A2,-(SP)

	; ----- fill: $FF di notte (tutto scuro), $00 di giorno -----------
	MOVE.W	#$0100,D1				; BLTCON0: USED, LF=$00 -> D=0
	TST.B	NightMode
	BEQ.S	.fillcon_ok
	MOVE.W	#$01FF,D1				; notte: LF=$FF -> D=$FFFF
.fillcon_ok:
	BSR.W	AspettaBlitter
	MOVE.W	D1,$40(A6)				; BLTCON0
	MOVE.W	#0,$42(A6)				; BLTCON1
	MOVE.L	#$FFFFFFFF,$44(A6)
	MOVE.W	#0,$66(A6)				; BLTDMOD = 0: riga intera, buffer contiguo
	MOVE.L	#PathBDarkPlane,$54(A6)
	MOVE.W	#COPIA_PIANO_BLT,$58(A6)	; a strisce da 64 word: vedi COPIA_PIANO_*
	BSR.W	AspettaBlitter
	IFNE	PROFILING
	BSR.W	MisuraRicPassa			; il riempimento del darkplane e' finito
	ENDC

	; ----- di giorno non ci sono lampioni: finito -------------------
	TST.B	NightMode
	BEQ.W	.done

	; ----- un cerchio per ogni TILE_LUCE, in coordinate MONDO -------
	; Nessun cull: il buffer copre tutta la mappa, quindi vanno disegnati
	; TUTTI, non solo quelli che si vedono adesso.
	MOVEQ	#0,D7					; D7 = riga mappa
.row:
	MOVEQ	#0,D3					; D3 = colonna mappa
	MOVE.W	D7,D2
	MULU.W	#MAPPA_COLS,D2
	ADD.W	D2,D2
	MOVEA.L	MappaPtr,A0			; la mappa viva
	ADDA.W	D2,A0					; A0 = &mappa[D7][0]
.col:
	MOVE.W	(A0)+,D2
	CMP.W	#TILE_LUCE,D2
	BNE.S	.next

	; centro del cerchio in coordinate mondo, +8 = centro della tile
	MOVE.W	D3,D0
	LSL.W	#4,D0
	ADDQ.W	#8,D0					; D0 = cx mondo
	MOVE.W	D7,D1
	LSL.W	#4,D1
	ADDQ.W	#8,D1					; D1 = cy mondo
	BSR.W	DisegnaCerchioLuceBlitter
.next:
	ADDQ.W	#1,D3
	CMP.W	#MAPPA_COLS,D3
	BLT.S	.col
	ADDQ.W	#1,D7
	CMP.W	#MAPPA_ROWS,D7
	BLT.S	.row
.done:
	BSR.W	AspettaBlitter
	MOVEM.L	(SP)+,D0-D7/A0-A2
	RTS

; PathBInit - preparazione una tantum, dopo DisegnaSfondo
; Sostituisce nella copperlist i segnaposto di CL_Ddf e CL_BplMod con la
; geometria vera di Path B (ScrollHW.i). Tutti e otto i piani puntano a
; buffer reali con lo STESSO pitch (AUX_PITCH = SFONDO_PITCH): BPL1MOD e
; BPL2MOD sono condivisi fra piani dispari e pari, quindi un pitch diverso
; farebbe slittare ogni riga dei piani ausiliari.
PathBInit:
	MOVEM.L	D0-D1/A0-A1,-(SP)

	LEA		CL_Ddf,A1
	MOVE.W	#SCROLL_DDFSTRT,2(A1)
	MOVE.W	#SCROLL_DDFSTOP,6(A1)
	LEA		CL_BplMod,A1
	MOVE.W	#SCROLL_BPLMOD,2(A1)	; BPL1MOD
	MOVE.W	#SCROLL_BPLMOD,6(A1)	; BPL2MOD

	MOVEM.L	(SP)+,D0-D1/A0-A1
	RTS

