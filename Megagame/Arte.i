; Arte.i - lettura dei fogli di tile da file, all'avvio.
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.
;
; QUANDO GIRA: prima di `MAINCODE`, chiamato da `Avvio.i`. Il perche' sta la'.
; In due parole: dentro il gioco c'e' Forbid + Disable e gli INTENA a zero, e
; una Read() li' dentro aspetta un interrupt che non puo' arrivare.
;
; COSA LEGGE: i fogli dichiarati in risorse/mappe.txt, i cui nomi arrivano in
; `FogliNomi` (generata da tools/mappe.py). I nomi non sono scritti qui: una
; seconda copia divergerebbe al primo rinominamento.
;
; DOVE LI METTE: `FogliArte`, in SECTION LavoroCPU (BSS, niente `_C`), quindi
; in FAST RAM finche' ce n'e'. NON in chip: in chip ci va UN foglio solo, e
; `AssicuraFoglioTile` ce lo copia quando serve. Su una macchina senza fast
; AmigaOS mette anche questa roba in chip, e sono FOGLI_N x FOGLIO_BYTE: e' il
; prezzo dichiarato di avere piu' di un foglio.
;
; SE QUALCOSA NON VA si stampa e si torna con D0 != 0, e `Avvio.i` esce SENZA
; aver preso l'hardware. E' l'unico momento in cui un errore si puo' ancora
; raccontare: dopo HEAVYINIT non c'e' piu' ne' schermo di sistema ne' DOS.

; CON L'INTERRUTTORE A ZERO QUESTO MODULO NON ESISTE, e non e' pignoleria:
; CaricaFogli nomina FogliArte e FogliNomi, che con FOGLIO_DA_FILE = 0 non
; vengono riservati. Lasciando il codice dentro, l'assemblatore avrebbe dei
; simboli non definiti in una routine che nessuno chiama.
	IFNE	FOGLIO_DA_FILE

; MODE_OLDFILE di dos.library: apri un file che esiste gia', in lettura.
; Sta qui e non in un Cost*.i perche' e' una costante di AmigaOS usata in UN
; punto solo; la regola dei Cost*.i esiste per le EQU che attraversano i
; moduli, e questa non attraversa niente.
MODO_LETTURA		EQU		1005

CaricaFogli:
	MOVEM.L	D1-D7/A0-A6,-(SP)
	MOVEQ	#0,D0					; fin qui e' andata

	MOVE.L	4.w,A6					; ExecBase
	LEA		.nomedos(PC),A1
	JSR		-$198(A6)				; OldOpenLibrary - come fa Startup2
	TST.L	D0
	BEQ.W	.senzados
	MOVE.L	D0,D7					; D7 = DosBase, serve fino in fondo

	LEA		FogliNomi,A5			; i nomi, uno per foglio
	LEA		FogliArte,A4			; dove vanno i byte
	MOVEQ	#FOGLI_N-1,D6
.giro:
	MOVEA.L	(A5)+,A3				; A3 = il nome di questo foglio

	MOVEA.L	D7,A6
	MOVE.L	A3,D1
	MOVE.L	#MODO_LETTURA,D2
	JSR		-30(A6)					; Open
	MOVE.L	D0,D5					; D5 = handle
	BEQ.W	.nonapro

	MOVEA.L	D7,A6
	MOVE.L	D5,D1
	MOVE.L	A4,D2
	MOVE.L	#FOGLIO_BYTE,D3
	JSR		-42(A6)					; Read
	MOVE.L	D0,D4					; D4 = byte letti

	MOVEA.L	D7,A6
	MOVE.L	D5,D1
	JSR		-36(A6)					; Close

	; LA GUARDIA CHE L'INCBIN FACEVA DA SOLO. Con `incbin` era
	; GUARDIA_TILES_RAW a legare la lunghezza del file alla forma dichiarata,
	; e lo faceva al tempo di assemblaggio. Senza incbin quel controllo non
	; esiste piu': se non lo si rifa' qui, un foglio corto fa leggere a
	; DisegnaSfondo byte che non sono suoi, in silenzio.
	CMP.L	#FOGLIO_BYTE,D4
	BNE.W	.nonlungo

	ADD.L	#FOGLIO_BYTE,A4			; il prossimo foglio va dopo questo.
									; ADD e non LEA d(A4),A4: lo spostamento
									; di una LEA e' a 16 bit e FOGLIO_BYTE non
									; ci sta.
	DBRA	D6,.giro

	MOVEQ	#0,D0					; tutti dentro
	BRA.S	.chiudi

.nonapro:
	LEA		.manca(PC),A0
	BSR.W	.dillo
	MOVEA.L	A3,A0
	BSR.W	.dillo
	LEA		.acapo(PC),A0
	BSR.W	.dillo
	MOVEQ	#1,D0
	BRA.S	.chiudi

.nonlungo:
	LEA		.corto(PC),A0
	BSR.W	.dillo
	MOVEA.L	A3,A0
	BSR.W	.dillo
	LEA		.acapo(PC),A0
	BSR.W	.dillo
	MOVEQ	#2,D0

.chiudi:
	MOVE.L	D0,D5					; l'esito deve sopravvivere a CloseLibrary
	MOVE.L	4.w,A6
	MOVEA.L	D7,A1
	JSR		-$19E(A6)				; CloseLibrary
	MOVE.L	D5,D0
	BRA.S	.fine

.senzados:
	; Senza dos.library non c'e' nemmeno come dirlo: si torna l'errore e basta.
	; Da CLI o da Workbench non puo' succedere, ma un ramo muto e' meglio di un
	; ramo che chiama una libreria che non ha aperto.
	MOVEQ	#3,D0

.fine:
	MOVEM.L	(SP)+,D1-D7/A0-A6
	TST.W	D0						; chi chiama guarda Z
	RTS

* .dillo - scrive sulla finestra del CLI la stringa a zero puntata da A0.
*   IN: A0 = stringa, D7 = DosBase. DISTRUGGE: D0-D1/A6.
*   La lunghezza la conta qui perche' Write la vuole: dos.library non ha una
*   funzione che scriva una stringa a zero.
.dillo:
	MOVEM.L	D2-D3/A0-A2,-(SP)
	MOVEA.L	A0,A2					; A2 = la stringa
	MOVEQ	#-1,D3
.conta:
	ADDQ.L	#1,D3
	TST.B	(A0)+
	BNE.S	.conta
	TST.L	D3
	BEQ.S	.nulla
	MOVEA.L	D7,A6
	JSR		-60(A6)					; Output
	MOVE.L	D0,D1
	BEQ.S	.nulla					; nessuna finestra: non c'e' dove scrivere
	MOVE.L	A2,D2
	MOVEA.L	D7,A6
	JSR		-48(A6)					; Write
.nulla:
	MOVEM.L	(SP)+,D2-D3/A0-A2
	RTS

; I messaggi non ripetono la lunghezza attesa: sarebbe un numero ricopiato da
; FOGLIO_BYTE, cioe' la seconda copia che la regola 5 vieta.
.nomedos:	dc.b	"dos.library",0
.manca:		dc.b	"MegaGame: non riesco ad aprire ",0
.corto:		dc.b	"MegaGame: lunghezza sbagliata in ",0
.acapo:		dc.b	10,0
	even

	ENDC
