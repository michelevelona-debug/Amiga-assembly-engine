; Luce.i - Falo', partenza dalla mappa, cerchio di luce
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* InitFalo - il falo' come BOB
*   Stesso schema di InitPietra. La geometria dello sheet la deriva DisegnaBOB
*   da larghezza, altezza, fotogrammi e bande: qui si dichiarano solo quelli.
*   bob_IsMoving = ANIM_ESTERNA perche' la sequenza del falo' non e' un giro
*   in avanti: e' un'accensione a ritroso seguita da un ciclo piu' corto, e
*   la decide AnimaFalo. Con 0 DisegnaBOB azzererebbe il fotogramma a ogni
*   disegno; con 1 lo farebbe avanzare per conto suo.
InitFalo:
	MOVEM.L	A0,-(SP)
	LEA		BobFalo,A0
	MOVE.W	#0,bob_Active(A0)		; lo accende AnimaFalo, e solo di notte
	MOVE.L	#FaloSheet,bob_Gfx(A0)
	MOVE.L	#FALO_MASK,bob_Mask(A0)
	MOVE.W	#FALO_W,bob_Larghezza(A0)
	MOVE.W	#FALO_H,bob_Altezza(A0)
	MOVE.W	#FALO_FRAMES,bob_Frames(A0)
	MOVE.W	#1,bob_Bande(A0)		; una banda sola: nessuna direzione
	MOVE.W	#ANIM_ESTERNA,bob_IsMoving(A0)
	MOVE.W	#FALO_INTRO_IDX,bob_AnimFrame(A0)
	MOVE.W	#0,bob_Direzione(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_Damage(A0)		; non fa male: e' scenografia
	MOVE.W	#0,bob_X(A0)			; li ricalcola DisegnaBOBs dalla camera
	MOVE.W	#0,bob_Y(A0)
	MOVEM.L	(SP)+,A0
	BRA.W	TrovaFalo				; la posizione la decide la mappa

* TrovaFalo - mette il falo' dove la mappa ha la tile TILE_LUCE
*   Il cerchio di luce e il fuoco devono stare nello stesso posto. La luce la
*   disegna PathBBuildDark cercando TILE_LUCE nella mappa: qui si cerca la
*   stessa tile, cosi' la posizione ha UNA fonte sola ed e' la mappa.
*   Si prende la PRIMA tile trovata, scandendo per righe. Se ne metti piu' di
*   una, PathBBuildDark accende un cerchio per ognuna ma il fuoco resta sulla
*   prima: per averne due servono due bob.
*   L'angolo alto-sinistro del bob va sull'angolo della tile, cosi' il centro
*   del bob 16x16 cade esattamente dove DisegnaCerchioLuceBlitter mette il
*   centro del cerchio, che e' (colonna*16+8, riga*16+8).
*   Se nella mappa non c'e' nessuna TILE_LUCE, bob_WorldX resta NEGATIVA e
*   DisegnaBOB la scarta con il cull che ha gia' ("X mondo negativa -> fuori
*   dal buffer"): niente fuoco, esattamente come niente luce.
*   Girava una volta al boot, quando la mappa era una sola. **Dal 26 settembre
*   2026 la richiama anche EseguiPassaggio**: la TILE_LUCE della mappa nuova sta
*   altrove, e senza questa chiamata il falo' resterebbe alle coordinate di
*   quella di prima. Legge MappaPtr, quindi non ha bisogno di sapere quale.
*   DISTRUGGE: nulla (salva tutto).
TrovaFalo:
	MOVEM.L	D2-D3/A0-A1,-(SP)
	LEA		BobFalo,A1
	MOVE.W	#-1,bob_WorldX(A1)		; "non trovata", finche' non si dimostra
	MOVE.W	#0,bob_WorldY(A1)
	MOVEA.L	MappaPtr,A0			; la mappa viva
	MOVEQ	#0,D2					; D2 = riga
.riga:
	MOVEQ	#0,D3					; D3 = colonna
.col:
	CMP.W	#TILE_LUCE,(A0)+
	BEQ.S	.trovata
	ADDQ.W	#1,D3
	CMP.W	#MAPPA_COLS,D3
	BLT.S	.col
	ADDQ.W	#1,D2
	CMP.W	#MAPPA_ROWS,D2
	BLT.S	.riga
	BRA.S	.fine
.trovata:
	LSL.W	#4,D3					; colonna -> pixel
	MOVE.W	D3,bob_WorldX(A1)
	LSL.W	#4,D2					; riga -> pixel
	MOVE.W	D2,bob_WorldY(A1)
.fine:
	MOVEM.L	(SP)+,D2-D3/A0-A1
	RTS

* TrovaPartenza - mette il player dove la mappa ha la tile TILE_VIA
*   Stessa idea di TrovaFalo qui sopra, e per la stessa ragione: la posizione
*   di un'entita' sta NELLA MAPPA, cosi' spostare il punto di partenza vuol
*   dire spostare una casella di risorse/mappa1.txt e non ricalcolare un EQU in
*   pixel. Si prende la PRIMA tile trovata, scandendo per righe.
*   SE NELLA MAPPA NON C'E' NESSUNA TILE_VIA il player resta dove l'ha messo
*   InitPlayer, cioe' su PLAYER_SPAWN_X/Y, e il gioco parte lo stesso. Non
*   sono due fonti di verita' in conflitto: la mappa vince sempre quando la
*   tile c'e', e quando non c'e' lo dice tools/mappa.py al momento della
*   conversione, che e' dove accorgersene costa niente.
*   bob_PrevX segue la X: e' il riferimento con cui SuonoPassi misura lo
*   spostamento, e lasciandola allo spawn di ripiego il primo quadro sentirebbe
*   un passo che nessuno ha fatto (lo dice gia' il commento in InitPlayer).
*   Gira una volta al boot: la mappa non cambia.
*   DISTRUGGE: nulla (salva tutto).
TrovaPartenza:
	MOVEM.L	D2-D3/A0-A1,-(SP)
	LEA		Player,A1
	MOVEA.L	MappaPtr,A0			; la mappa viva
	MOVEQ	#0,D2					; D2 = riga
.riga:
	MOVEQ	#0,D3					; D3 = colonna
.col:
	CMP.W	#TILE_VIA,(A0)+
	BEQ.S	.trovata
	ADDQ.W	#1,D3
	CMP.W	#MAPPA_COLS,D3
	BLT.S	.col
	ADDQ.W	#1,D2
	CMP.W	#MAPPA_ROWS,D2
	BLT.S	.riga
	BRA.S	.fine
.trovata:
	LSL.W	#4,D3					; colonna -> pixel
	MOVE.W	D3,bob_WorldX(A1)
	MOVE.W	D3,bob_PrevX(A1)		; se no, un passo fantasma al primo quadro
	LSL.W	#4,D2					; riga -> pixel
	MOVE.W	D2,bob_WorldY(A1)
.fine:
	MOVEM.L	(SP)+,D2-D3/A0-A1
	RTS

* AnimaFalo
*   Fa avanzare il fotogramma del falo' e lo accende solo di notte.
*   NON tocca piu' niente di grafico: posizione, cull, clip, blit e rettangolo
*   sporco sono di DisegnaBOBs come per ogni altro bob. Prima questa routine
*   costruiva SPRPOS/SPRCTL e scriveva SPR0PT nella copperlist.
*   La sequenza va A RITROSO: l'arte ha la fiamma piena al frame 1 e la brace
*   al frame FALO_FRAMES. Si parte da FALO_INTRO_IDX e si scende; quando si
*   passa sotto zero si rientra da FALO_LOOP_IDX, che e' la fiamma a regime.
*   Non serve nessun flag "intro finita": il valore iniziale e quello di
*   rientro sono semplicemente due numeri diversi.
*   DISTRUGGE: nulla (salva tutto).
AnimaFalo:
	MOVEM.L	D0/A0,-(SP)
	LEA		BobFalo,A0

	; ----- di giorno il falo' non c'e' -----
	TST.B	NightMode
	BNE.S	.notte
	MOVE.W	#0,bob_Active(A0)
	BRA.S	.fine
.notte:
	MOVE.W	#1,bob_Active(A0)

	; ----- avanza il fotogramma ogni FaloAnimSpeed frame -----
	ADDQ.W	#1,FaloAnimDelay
	CMP.W	#FaloAnimSpeed,FaloAnimDelay
	BLT.S	.fine
	CLR.W	FaloAnimDelay
	MOVE.W	bob_AnimFrame(A0),D0
	SUBQ.W	#1,D0
	BPL.S	.scritto
	MOVE.W	#FALO_LOOP_IDX,D0
.scritto:
	MOVE.W	D0,bob_AnimFrame(A0)
.fine:
	MOVEM.L	(SP)+,D0/A0
	RTS

* DisegnaCerchioLuce
*   Disegna un cerchio di "luce" (= bit a 0) sul dark plane corrente.
*   INPUT:
*     D0.w = center X schermo (puo' essere negativo)
*     D1.w = center Y schermo (idem)
*   Raggio = RAGGIO_LUCE.
*   Strategia: per ogni riga dy, calcola span [x_left..x_right] e fa
*   AND-NOT con la maschera sul dark plane (= spegne i pixel = luce).
DisegnaCerchioLuce:
	MOVEM.L	D0-D7/A0-A3,-(SP)

	; Salvo cx, cy in registri "stabili" usando A2, A3 (.w)
	MOVE.W	D0,A2					; A2 = cx
	MOVE.W	D1,A3					; A3 = cy

	; Loop esterno: dy da -RAGGIO_LUCE a +RAGGIO_LUCE
	; Uso D7 come dy (preservato attraverso il loop interno con la stack)
	MOVE.W	#-RAGGIO_LUCE,D7
.dy_loop:
	; Salvo D7 (dy) sullo stack durante il loop interno
	MOVE.W	D7,-(SP)

	; y_riga = cy + dy
	MOVE.W	A3,D3
	ADD.W	D7,D3					; D3 = y_riga
	; Cull verticale contro l'ALTEZZA DEL BUFFER, non contro l'altezza dello
	; schermo: qui cx/cy arrivano in coordinate MONDO da PathBBuildDark e il
	; darkplane di Path B copre tutta la mappa. Con BG_VIS_ROWS (176) una
	; sorgente di luce sotto quella riga perdeva silenziosamente meta' cerchio.
	BMI.W	.skip_row
	CMP.W	#DARK_MAX_ROWS,D3
	BGE.W	.skip_row

	; half = LightHalfWidthTable[|dy|]
	MOVE.W	D7,D4
	BPL.S	.abs_ok
	NEG.W	D4
.abs_ok:
	LEA		LightHalfWidthTable,A0
	MOVE.B	(A0,D4.W),D5
	EXT.W	D5						; D5 = half
	TST.W	D5
	BEQ.W	.skip_row				; half=0

	; x_left = cx - half, x_right = cx + half - 1
	MOVE.W	A2,D0
	SUB.W	D5,D0					; D0 = x_left
	MOVE.W	A2,D1
	ADD.W	D5,D1
	SUBQ.W	#1,D1					; D1 = x_right

	; Cull e clip orizzontali contro la LARGHEZZA DELLA RIGA DEL BUFFER
	; (DARK_MAX_X, oggi 511), non contro i 320 dello schermo: si lavora in
	; coordinate mondo su righe da DARK_ROW_BYTES byte.
	TST.W	D1
	BMI.W	.skip_row
	CMP.W	#DARK_MAX_X,D0
	BGT.W	.skip_row
	; Clip
	TST.W	D0
	BPL.S	.lc_ok
	MOVEQ	#0,D0
.lc_ok:
	CMP.W	#DARK_MAX_X,D1
	BLE.S	.rc_ok
	MOVE.W	#DARK_MAX_X,D1
.rc_ok:
	; D0 = x_left clippato, D1 = x_right clippato

	; A1 = base riga sul dark plane. Il passo e' AUX_PITCH (il pitch VERO del
	; buffer di Path B): con BPSF_PITCH, rimasto da Path A, ogni riga finiva
	; 24 byte piu' indietro del dovuto e il cerchio usciva sbilenco.
	MOVE.L	CurrentDarkDraw,A1
	MOVE.W	D3,D4
	MULU.W	#AUX_PITCH,D4
	ADDA.L	D4,A1

	; byte_left = D0 >> 3, byte_right = D1 >> 3
	; bit_left = D0 & 7, bit_right = D1 & 7
	MOVE.W	D0,D2					; D2 = byte_left
	LSR.W	#3,D2
	MOVE.W	D1,D3					; D3 = byte_right
	LSR.W	#3,D3
	MOVE.W	D0,D4
	ANDI.W	#7,D4					; D4 = bit_left
	MOVE.W	D1,D5
	ANDI.W	#7,D5					; D5 = bit_right

	; A1 += byte_left
	ADDA.W	D2,A1

	; Costruisco maschere PER LATO:
	; left_mask  = $FF >> bit_left   (bit da spegnere nel byte sinistro)
	; right_mask = $FF << (7 - bit_right), poi & $FF
	MOVE.W	#$FF,D6
	LSR.W	D4,D6					; D6 = left_mask
	MOVEQ	#7,D0
	SUB.W	D5,D0					; D0 = 7 - bit_right
	MOVE.W	#$FF,D5
	LSL.W	D0,D5
	ANDI.W	#$FF,D5					; D5 = right_mask

	; Confronto byte_left vs byte_right
	CMP.W	D2,D3
	BNE.S	.multi_byte

	; SINGLE BYTE: mask = left_mask AND right_mask
	AND.B	D5,D6					; D6 = mask combinata
	NOT.B	D6
	AND.B	D6,(A1)
	BRA.S	.skip_row

.multi_byte:
	; Primo byte: AND con NOT left_mask
	MOVE.B	D6,D0
	NOT.B	D0
	AND.B	D0,(A1)+
	; Byte intermedi: tutti a 0
	MOVE.W	D3,D0
	SUB.W	D2,D0					; D0 = byte_right - byte_left
	SUBQ.W	#1,D0					; D0 = numero intermedi (= byte_right - byte_left - 1)
	BLE.S	.middle_done			; <=0: nessun intermedio
	SUBQ.W	#1,D0
	BMI.S	.middle_done
.middle_loop:
	CLR.B	(A1)+
	DBRA	D0,.middle_loop
.middle_done:
	; Ultimo byte: AND con NOT right_mask
	MOVE.B	D5,D0
	NOT.B	D0
	AND.B	D0,(A1)

.skip_row:
	; Ripristina dy dallo stack
	MOVE.W	(SP)+,D7
	ADDQ.W	#1,D7
	CMP.W	#RAGGIO_LUCE+1,D7
	BLT.W	.dy_loop

	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

* LightHalfWidthTable
*   Tabella di "mezza-larghezza" per cerchio raggio LIGHT_RADIUS=64.
*   Indicizzata da |dy| (0..64).
*   half[dy] = sqrt(64² - dy²)
LightHalfWidthTable:
	dc.b	64,63,63,63,63,63,63,63		; dy  0.. 7
	dc.b	63,63,63,63,62,62,62,62		; dy  8..15
	dc.b	61,61,61,61,60,60,60,59		; dy 16..23
	dc.b	59,58,58,58,57,57,56,55		; dy 24..31
	dc.b	55,54,54,53,52,52,51,50		; dy 32..39
	dc.b	49,49,48,47,46,45,44,43		; dy 40..47
	dc.b	42,41,39,38,37,35,34,32		; dy 48..55
	dc.b	30,29,27,24,22,19,15,11		; dy 56..63
	dc.b	 0							; dy 64

	EVEN
* BuildLightMask  (chiamata UNA volta al boot)
*   Costruisce LightMask: disco di raggio RAGGIO_LUCE, bit=1 dentro, in un
*   buffer di LIGHT_MASK_W word x LIGHT_MASK_H righe. Riusa LightHalfWidthTable.
*   La 9a word di ogni riga resta 0 (spillover per lo shift del blit).
BuildLightMask:
	MOVEM.L	D0-D4/A0-A1,-(SP)
	LEA		LightMask,A1			; A1 = riga corrente della maschera
	MOVEQ	#0,D0					; D0 = r (0..LIGHT_MASK_H-1)
.row:
	MOVE.W	D0,D1
	SUB.W	#64,D1					; dy = r - 64
	TST.W	D1						; |dy|
	BPL.S	.pos
	NEG.W	D1
.pos:
	LEA		LightHalfWidthTable,A0
	MOVE.B	(A0,D1.W),D2
	EXT.W	D2						; D2 = half
	TST.W	D2
	BEQ.S	.next					; half=0 -> riga vuota (resta 0)
	MOVE.W	#64,D3
	SUB.W	D2,D3					; D3 = x_left  = 64 - half
	MOVE.W	#64,D4
	ADD.W	D2,D4
	SUBQ.W	#1,D4					; D4 = x_right = 64 + half - 1
	BSR.S	SetBitSpan				; setta bit [D3..D4] nella riga A1
.next:
	LEA		LIGHT_MASK_BANDA(A1),A1	; prossima riga
	ADDQ.W	#1,D0
	CMP.W	#LIGHT_MASK_H,D0
	BLT.S	.row
	MOVEM.L	(SP)+,D0-D4/A0-A1
	RTS

* SetBitSpan  - setta a 1 i bit da D3 a D4 (inclusi) nella riga A1.
*   Ordine bit MSB-first: pixel 0 = bit 7 del byte 0. Solo per il boot.
SetBitSpan:
	MOVEM.L	D3/D5/D6/A2,-(SP)
.sb:
	MOVE.W	D3,D5
	LSR.W	#3,D5					; byte index = x>>3
	MOVE.W	D3,D6
	ANDI.W	#7,D6
	EORI.W	#7,D6					; bit = 7-(x&7)  (MSB = pixel 0)
	LEA		(A1,D5.W),A2
	BSET	D6,(A2)
	ADDQ.W	#1,D3
	CMP.W	D4,D3
	BLE.S	.sb
	MOVEM.L	(SP)+,D3/D5/D6/A2
	RTS

* DisegnaCerchioLuceBlitter
*   Disegna il cerchio di luce sul dark plane (= spegne i bit dentro) usando
*   il BLITTER: minterm D = (NOT A) AND C, con A=LightMask, C/D=dark plane.
*   INPUT: D0.w = cx, D1.w = cy  (centro schermo, come DisegnaCerchioLuce).
*   - Shift orizzontale sub-word via ASH in BLTCON0.
*   - Clipping verticale: aggiusta riga di partenza maschera + altezza blit.
*   - Clipping orizzontale (bordo sx/dx): FALLBACK alla routine CPU esistente
*     quando word_x e' fuori [0..11] (cerchio a cavallo del bordo laterale).
DisegnaCerchioLuceBlitter:
	MOVEM.L	D0-D7/A0-A1,-(SP)

	; left_px = cx - 64 ; word_x = left_px>>4 (signed) ; shift = left_px & 15
	MOVE.W	D0,D2
	SUB.W	#RAGGIO_LUCE,D2			; D2 = left_px (signed)
	MOVE.W	D2,D3
	ASR.W	#4,D3					; D3 = word_x (signed)
	ANDI.W	#15,D2					; D2 = shift (0..15)

	; fallback CPU se il cerchio tocca i bordi sx/dx
	TST.W	D3
	BMI.W	.cpu_fallback			; word_x < 0
	CMP.W	#DARK_MAX_WORDX,D3
	BGT.W	.cpu_fallback			; le 9 word della maschera non entrano
	; nel buffer: passa al fallback CPU

	; ----- clipping verticale -----
	MOVE.W	D1,D5
	SUB.W	#RAGGIO_LUCE,D5			; D5 = top_row = cy - 64 (signed)
	MOVEQ	#0,D6					; D6 = rows_skip
	TST.W	D5
	BPL.S	.vt_ok
	MOVE.W	D5,D6
	NEG.W	D6						; rows_skip = -top_row
	MOVEQ	#0,D5					; vtop = 0
.vt_ok:
	MOVE.W	D1,D7
	ADD.W	#RAGGIO_LUCE,D7			; D7 = cy + 64 = bottom (esclusivo)
	CMP.W	#DARK_MAX_ROWS,D7
	BLE.S	.vb_ok
	MOVE.W	#DARK_MAX_ROWS,D7		; altezza del buffer darkplane
.vb_ok:
	MOVE.W	D7,D4
	SUB.W	D5,D4					; D4 = height = vbot - vtop
	BLE.W	.exit					; <=0: cerchio fuori in verticale

	BSR.W	AspettaBlitter

	; A0 = LightMask + rows_skip*PASSO
	MULU.W	#LIGHT_MASK_BANDA,D6
	LEA		LightMask,A0
	ADDA.W	D6,A0
	; A1 = CurrentDarkDraw + vtop*AUX_PITCH + word_x*2
	MOVE.L	CurrentDarkDraw,A1
	MOVE.W	D5,D6
	MULU.W	#AUX_PITCH,D6
	; ADDA.L e non ADDA.W. La MULU scrive un prodotto a 32 BIT; ADDA.W ne
	; prenderebbe solo la word bassa ESTENDENDONE IL SEGNO, quindi da vtop 205
	; in su (205*160 = 32800) il puntatore va ALL'INDIETRO di decine di KB.
	; Dove finisce: PathBDarkPlane ha PathBMaster subito prima, quindi si
	; scrive nella copia pulita della mappa, e da li' PathBRestoreAll ripesca
	; la spazzatura e la spalma nel mondo a ogni passaggio di un BOB.
	; Con il pitch a 64 non poteva succedere (336*64 = 21504): e' un difetto
	; che la mappa larga ha ACCESO, non uno nuovo. Le due TILE_LUCE di oggi
	; stanno a riga 17 e 21, cioe' vtop 216 e 280: le sbagliava tutte e due.
	ADDA.L	D6,A1
	MOVE.W	D3,D6
	ADD.W	D6,D6					; word_x*2, al piu' 140: qui la word basta
	ADDA.W	D6,A1

	MOVE.L	A0,$50(A6)				; BLTAPT = maschera
	MOVE.L	A1,$48(A6)				; BLTCPT = dark plane (lettura)
	MOVE.L	A1,$54(A6)				; BLTDPT = dark plane (scrittura)

	; BLTCON0 = (shift<<12) | USEA|USEC|USED | LF=$0A (D = ~A & C)
	MOVE.W	D2,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; shift << 12
	ORI.W	#$0B0A,D6
	MOVE.W	D6,$40(A6)				; BLTCON0
	MOVE.W	#0,$42(A6)				; BLTCON1 = 0
	MOVE.L	#$FFFFFFFF,$44(A6)		; BLTAFWM/BLTALWM = $FFFF
	MOVE.W	#0,$64(A6)				; BLTAMOD = 0 (maschera 9 word, blit 9 word)
	MOVE.W	#AUX_PITCH-LIGHT_MASK_W*2,$60(A6)	; BLTCMOD
	MOVE.W	#AUX_PITCH-LIGHT_MASK_W*2,$66(A6)	; BLTDMOD

	MOVE.W	D4,D6					; height
	LSL.W	#6,D6
	ORI.W	#LIGHT_MASK_W,D6		; | 9 word
	MOVE.W	D6,$58(A6)				; BLTSIZE -> avvia
	BRA.S	.exit

.cpu_fallback:
	; cx (D0) e cy (D1) sono ancora intatti -> uso la routine CPU collaudata.
	; Attendo un eventuale blit cerchio precedente: la CPU scrive direttamente.
	BSR.W	AspettaBlitter
	BSR.W	DisegnaCerchioLuce

.exit:
	MOVEM.L	(SP)+,D0-D7/A0-A1
	RTS
