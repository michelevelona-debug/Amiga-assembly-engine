; Input.i - Joystick e tastiera
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* LEGGI JOYSTICK
LeggiJoystick:
	movem.l D0-D3/A0-A1,-(SP)

	MOVE.W	#0,ScrllX	; inizializzo lo spostamento orizzontale
	MOVE.W	#0,ScrllY	; inizializzo lo spostamento verticale
	MOVE.W	#0,UpNow	; azzero lo stato del tasto salto per questo frame

	IFNE	PROFILING
; --- scroll automatico (tasto 6): carico IDENTICO a ogni prova ---------------
; Scrive arrow_rx/arrow_sx, cioe' entra dove entrerebbe la tastiera: tutto
; quello che sta a valle non si accorge della differenza.
; Il periodo NON puo' essere corto: RettangoloScrollNelCentro azzera ScrllX
; finche' bob_X non e' ESATTAMENTE CENTER_X, quindi il player prima deve
; camminare fino al centro e solo dopo la camera comincia a scorrere. Con 64
; quadri per verso il tempo finiva prima di arrivarci e lo scroll non partiva
; mai. 2^8 = 256 quadri, circa 5 secondi per lato.
AUTOSCROLL_BIT		EQU		8
	TST.B	AutoScrollOn
	BEQ.S	.auto_fine
	ADDQ.W	#1,AutoScrollCnt
	MOVE.W	AutoScrollCnt,D3
	BTST	#AUTOSCROLL_BIT,D3
	SNE		arrow_rx
	SEQ		arrow_sx
.auto_fine:
	ENDC
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
; Le flag arrow_* sono settate da ProcessaFrecce alla pressione
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

; CALCOLO DIREZIONE DEL PLAYER da ScrllX/ScrllY
; Indice nella tabella = (ScrllY+1)*3 + (ScrllX+1)
;            ScrllX:   -1     0     +1
;   ScrllY=-1:    NW(5)  N(6)  NE(7)
;   ScrllY= 0:     W(4)  --    E(0)
;   ScrllY=+1:    SW(3)  S(2)  SE(1)
; Se siamo fermi (centro tabella) la direzione corrente NON viene
; modificata: il player conserva l'ultima direzione di movimento
; (utile per scegliere il giusto sprite "idle" facing).
	LEA		Player,A0
	MOVE.w	ScrllY,D0
	MOVE.w	ScrllX,D1

	; bob_IsMoving vuole 1 oppure 0, NON "un valore diverso da zero".
	; Da quando ANIM_ESTERNA (-1) e' la terza posizione, un valore NEGATIVO
	; vuol dire "il fotogramma lo decide qualcun altro, non toccarlo".
	; ScrllX e ScrllY valgono -1, 0 o +1, cioe' $FFFF, 0 o 1: il vecchio
	; MOVE+OR scriveva $FFFF appena una delle due era -1, e l'animazione si
	; inchiodava in TUTTE le direzioni con una componente negativa - N, NE,
	; NW, W, SW. Restavano vive solo E, SE e S.
	; Qui si normalizza: qualcosa di diverso da zero -> 1.
	MOVE.W	D0,D2
	OR.W	D1,D2
	BEQ.S	.imFermo
	MOVEQ	#1,D2
.imFermo:
	MOVE.W	D2,bob_IsMoving(A0)

	ADDQ.w	#1,D0			; d0 = ScrllY+1 (0..2)
	MULU.w	#3,D0			; d0 = (ScrllY+1)*3 (0,3,6)
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
; LeggiTastiera
;   Legge UN keycode dalla CIA-A (se disponibile),
;   decodifica e aggiorna ScrollX / ScrollY.
;   Registri modificati: d0, d1  (salvati/ripristinati)
LeggiTastiera:
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
	bsr	 ProcessaFrecce

.no_key:
	movem.l (SP)+,D0-D1
	rts

; ProcessaFrecce
;   Input : d0.b = keycode decodificato
;			  bit7 = 0 pressione, 1 rilascio
;			  bit6-0 = codice tasto
;   Output: aggiorna arrow_*
;			non scrive ScrollX, ScrollY che vengono scritti
;			da LeggiJoystick
;   Registri modificati: d2 (salvato/ripristinato)
ProcessaFrecce:
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
	bra.w	.done

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
	; il darkplane statico va ridisegnato: e' l'unico momento in cui serve
	MOVEM.L	D0-D7/A0-A2,-(SP)
	LEA		$DFF000,A6
	BSR.W	PathBBuildDark
	MOVEM.L	(SP)+,D0-D7/A0-A2
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
	bne.s	.k_quadrante
	; D1 = 1 (premuto) o 0 (rilasciato); toggle solo sul fronte di pressione
	tst.b	D1
	beq.s	.g_release				; rilasciato -> aggiorna prev e basta
	tst.b	GravKeyPrev
	bne.s	.g_release				; era gia' premuto -> no edge
	; Edge press: inverti gravita' (platform <-> 8 direzioni)
	eori.w	#1,GravityOn
	clr.w	Player+bob_VelY				; reset stato fisica (rilevante al rientro in platform)
	clr.w	Player+bob_FracY
	clr.w	UpPrev
	clr.w	Player+bob_Grounded
.g_release:
	move.b	D1,GravKeyPrev

; --- tasti di prova degli strumenti del pannello ---
; Nel gioco non c'e' ancora chi comanda schermo, spie e lancetta: finche' non
; c'e', si guardano da qui. Quando arriveranno i veri clienti questi tre
; blocchi si tolgono, non si tengono "per sicurezza".
.k_quadrante:
	cmp.b	#RAWKEY_Q,D2
	bne.s	.k_schermo
	tst.b	D1
	beq.s	.q_release
	tst.b	QuadKeyPrev
	bne.s	.q_release
	; Edge press: la posizione dopo (ovest, nord, est, sud-sud-est)
	addq.w	#1,QuadranteObiettivo
	and.w	#3,QuadranteObiettivo
.q_release:
	move.b	D1,QuadKeyPrev

.k_schermo:
	cmp.b	#RAWKEY_S,D2
	bne.s	.k_spie
	tst.b	D1
	beq.s	.s_release
	tst.b	SchermoKeyPrev
	bne.s	.s_release
	; Edge press: neve, poi le cinque immagini, poi di nuovo neve
	addq.w	#1,SchermoModo
	cmp.w	#SCHERMO_IMMAGINI,SchermoModo
	bls.s	.s_release
	clr.w	SchermoModo
.s_release:
	move.b	D1,SchermoKeyPrev

.k_spie:
	cmp.b	#RAWKEY_L,D2
	bne.s	.k_lettera
	tst.b	D1
	beq.s	.l_release
	tst.b	SpieKeyPrev
	bne.s	.l_release
	; Edge press: una spia in piu' a ogni pressione, poi si ricomincia da zero.
	; D0 lo usa il ciclo che ha letto la tastiera: si salva.
	move.l	D0,-(sp)
	move.w	SpieAccese,D0
	cmp.w	#(1<<SPIE_TOT)-1,D0
	bne.s	.l_avanti
	moveq	#0,D0
	bra.s	.l_scrivi
.l_avanti:
	add.w	D0,D0
	or.w	#1,D0
.l_scrivi:
	move.w	D0,SpieAccese
	move.l	(sp)+,D0
.l_release:
	move.b	D1,SpieKeyPrev

.k_lettera:
	cmp.b	#RAWKEY_A,D2
	bne.s	.k_prof
	tst.b	D1
	beq.s	.a_release
	tst.b	LetteraKeyPrev
	bne.s	.a_release
	; Edge press: A, B, C ... Z, spazio, e si ricomincia. Lo spazio e' il glifo
	; vuoto, quindi e' anche il modo di SPEGNERE il quadrato: non serve un flag
	; a parte. D0 lo usa il ciclo che ha letto la tastiera: si salva.
	move.l	D0,-(sp)
	move.w	LetteraDestra,D0
	cmp.w	#'A',D0
	bcs.s	.a_riparte				; sotto la A (lo spazio) -> si riaccende
	cmp.w	#'Z',D0
	bcc.s	.a_spegne				; alla Z -> spazio
	addq.w	#1,D0
	bra.s	.a_scrive
.a_riparte:
	move.w	#'A',D0
	bra.s	.a_scrive
.a_spegne:
	move.w	#' ',D0
.a_scrive:
	move.w	D0,LetteraDestra
	move.l	(sp)+,D0
.a_release:
	move.b	D1,LetteraKeyPrev

; La label sta FUORI dal condizionale: .k_lettera ci salta sempre, anche
; quando l'harness e' escluso dalla build.
.k_prof:
	IFNE	PROFILING
	cmp.b	#RAWKEY_P,D2
	bne.s	.k_reset
	; D1 = 1 (premuto) o 0 (rilasciato); toggle solo sul fronte di pressione
	tst.b	D1
	beq.s	.p_release
	tst.b	ProfKeyPrev
	bne.s	.p_release
	; Edge press: mostra/nascondi i numeri del profilo.
	; Mentre sono mostrati la misura e' CONGELATA (vedi FineLavoro), cosi'
	; i valori che leggi restano quelli accumulati giocando e non vengono
	; sporcati dal costo del disegno dei numeri stesso.
	eori.b	#1,ProfShow
	; Spegnendo P il blocco del monitor va tolto dal pannello. Qui si alza solo
	; un flag: il ripristino e' un blit, vuole A6 e un punto sicuro del quadro,
	; e il gestore della tastiera non e' ne' l'uno ne' l'altro.
	tst.b	ProfShow
	bne.s	.p_release
	move.b	#1,ProfPanRipara
.p_release:
	move.b	D1,ProfKeyPrev

.k_reset:
	cmp.b	#RAWKEY_R,D2
	bne.s	.k_auto
	; Azzera WorstLines, DropCount e tutto ProfWorst. Serve perche' gli
	; high-water sono STICKY: un solo frame anomalo (avvio, cambio scena,
	; un hiccup qualsiasi) resta appiccicato per sempre e falsa la lettura.
	; Uso: premi R, gioca il caso che vuoi misurare, poi premi P e leggi.
	tst.b	D1
	beq.s	.r_release
	tst.b	ResetKeyPrev
	bne.s	.r_release
	move.w	#1,WorstReset
.r_release:
	move.b	D1,ResetKeyPrev

; Tasto 6: la camera cammina da sola, avanti e indietro. Serve perche' due
; misure fatte giocando a mano NON si confrontano: il 2 settembre WO 338 contro
; WO 108 raccontavano quanto si era giocato, non la configurazione. E quando la
; prova deforma l'immagine, giocare non e' nemmeno possibile.
; Vive dentro IFNE PROFILING come il resto dell'harness: in una build senza
; profiler non esiste.
.k_auto:
	cmp.b	#RAWKEY_6,D2
	bne.s	.done
	tst.b	D1
	beq.s	.a6_release
	tst.b	AutoKeyPrev
	bne.s	.a6_release
	eori.b	#1,AutoScrollOn
.a6_release:
	move.b	D1,AutoKeyPrev
	ENDC
.done:

	movem.l	(SP)+,D1-D2
	rts
