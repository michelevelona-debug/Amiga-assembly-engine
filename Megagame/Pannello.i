; Pannello.i - Strumenti del pannello, AspettaBlitter, scritta scorrevole
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* DisegnaPunteggio - le cinque cifre nel riquadro del pannello
*   Due lavori, in quest'ordine: il numero MOSTRATO insegue quello vero di
*   PUNTEGGIO_PASSO per quadro, e il pannello si riscrive solo se il mostrato e'
*   cambiato. PannelloBuf e' fisso, quindi a rotella ferma la routine e' un
*   confronto e un RTS.
*   Il passo si fa SEMPRE a long: una ADDI.W su un contatore a long somma solo
*   la word bassa, il riporto non passa, e la rotella si inchioda su 99999.
*   L'inseguimento va anche all'INDIETRO, se no un obiettivo piu' basso di quello
*   mostrato lo fa salire all'infinito. E non scavalca: se il passo coprirebbe
*   piu' della distanza, ci si mette sopra.
*   IL ROTOLAMENTO: il contatore non conta punti, conta FOTOGRAMMI, e un punto
*   vale ROTELLA_PASSI. Da quell'unico numero escono sia la cifra sia il
*   fotogramma, senza stato per cifra.
*   IL RIPORTO e' la regola della rotella vera: la cifra k gira solo finche'
*   tutte quelle alla sua destra leggono 9. Da 199 a 200 girano le ultime tre
*   insieme e atterrano nello stesso istante.
*   Niente blitter: una cifra e' 8 px e cade su un byte, quindi basta MOVE.B.
*   Le cifre escono dalla DIVU dalla meno significativa, quindi si riempie da
*   destra: la posizione parte da PUNTEGGIO_CIFRE-1 e scende.
*   DISTRUGGE: nulla (salva tutto).
DisegnaPunteggio:
	MOVEM.L	D0-D2/D4-D7/A0-A3,-(SP)

	; ----- 1. l'obiettivo, saturato una volta sola e portato in SCALA -----
	; La scala e' ROTELLA_PASSI: il contatore conta i FOTOGRAMMI, non i punti,
	; e un punto ne vale quattro. Da un solo numero escono sia la cifra
	; (valore/PASSI) sia il fotogramma (valore mod PASSI). Le posizioni di
	; riposo sono i multipli di ROTELLA_PASSI, quindi quando la rotella e'
	; ferma tutte le cifre stanno per forza sul fotogramma pieno: non c'e'
	; nessuno stato che possa restare appeso a meta' giro.
	MOVE.L	Punteggio,D0
	CMP.L	#PUNTEGGIO_MAX,D0
	BLS.S	.obiettivo
	MOVE.L	#PUNTEGGIO_MAX,D0			; oltre le cifre che ci sono, si satura
.obiettivo:
	LSL.L	#2,D0						; * ROTELLA_PASSI (4, potenza di due)

	; ----- 2. il numero mostrato ci si avvicina di un passo -----
	MOVE.L	PunteggioMostrato,D1
	CMP.L	D0,D1
	BEQ.S	.mostra						; gia' arrivato: niente da muovere
	BCS.S	.sale						; mostrato < obiettivo
	MOVE.L	D1,D2						; scende: distanza = mostrato-obiettivo
	SUB.L	D0,D2
	CMP.L	#PUNTEGGIO_PASSO,D2
	BLS.S	.arriva
	SUB.L	#PUNTEGGIO_PASSO,D1
	BRA.S	.mostra
.sale:
	MOVE.L	D0,D2						; distanza = obiettivo-mostrato
	SUB.L	D1,D2
	CMP.L	#PUNTEGGIO_PASSO,D2
	BLS.S	.arriva
	ADD.L	#PUNTEGGIO_PASSO,D1
	BRA.S	.mostra
.arriva:
	MOVE.L	D0,D1						; un passo coprirebbe tutto: ci si mette sopra
.mostra:
	MOVE.L	D1,PunteggioMostrato

	; ----- 3. si tocca il pannello solo se cambia qualcosa -----
	CMP.L	PunteggioDisegnato,D1
	BEQ.W	.fine
	MOVE.L	D1,PunteggioDisegnato

	; La FASE del rotolamento e' la stessa per tutte le cifre che girano, quindi
	; si calcola una volta sola qui fuori. E' gia' convertita in BYTE, cosi'
	; dentro il ciclo e' una somma e basta.
	; ROTELLA_PASSI e' 4, cioe' una potenza di due: la fase e' un AND e il
	; valore intero uno shift. Se un giorno i passi non fossero piu' una
	; potenza di due, queste due righe vanno rifatte con una divisione.
	MOVE.L	D1,D0
	AND.W	#ROTELLA_PASSI-1,D0			; D0 = fase 0..ROTELLA_PASSI-1
	MULU	#ROTELLA_CELL_W/8,D0		; -> byte di scostamento nella striscia
	LSR.L	#2,D1						; D1 = valore intero (scala / ROTELLA_PASSI)
	MOVEQ	#1,D2						; le unita' girano SEMPRE

	MOVEQ	#PUNTEGGIO_CIFRE-1,D7		; posizione, da destra verso sinistra
.cifra:
	DIVU	#10,D1
	SWAP	D1							; alto = quoziente, basso = resto
	MOVE.W	D1,D6						; D6 = cifra 0..9
	CLR.W	D1
	SWAP	D1							; D1 = quoziente per il giro dopo

	; --- il riporto: questa cifra gira solo se TUTTE quelle alla sua destra
	;     leggono 9. D2 e' quel flag, e vale gia' per la cifra corrente: si
	;     USA prima e si aggiorna dopo, se no le unita' non girerebbero mai.
	;     D4 e' libero fin qui: lo carica il ciclo delle righe piu' sotto.
	MOVE.W	D0,D4						; scostamento del fotogramma...
	TST.W	D2
	BNE.S	.gira
	MOVEQ	#0,D4						; ...ma questa cifra e' ferma
	BRA.S	.indice
.gira:
	CMP.W	#9,D6
	BEQ.S	.indice						; e' 9: anche quella dopo puo' girare
	CLR.W	D2							; non e' 9: da qui in poi nessuno gira
.indice:
	; sorgente: prima cella della cifra, che sta alla colonna
	; cifra*ROTELLA_PASSI, cioe' a cifra*PASSI*CELL_W/8 byte dall'inizio riga,
	; piu' il fotogramma del rotolamento.
	MULU	#ROTELLA_PASSI*ROTELLA_CELL_W/8,D6
	ADD.W	D4,D6
	LEA		RotellaSheet,A0
	ADDA.W	D6,A0

	; destinazione: riga PUNTEGGIO_Y, byte PUNTEGGIO_X/8 piu' la posizione
	LEA		PannelloBuf,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS+PUNTEGGIO_Y*PANNELLO_BUF_PITCH+PUNTEGGIO_X/8,A1
	ADDA.W	D7,A1

	MOVEQ	#ROTELLA_PIANI_PAN-1,D5
.piano:
	MOVEA.L	A0,A2
	MOVEA.L	A1,A3
	MOVEQ	#ROTELLA_H-1,D4
.riga:
	MOVE.B	(A2),(A3)
	ADDA.W	#ROTELLA_ROWB,A2
	ADDA.W	#PANNELLO_BUF_PITCH,A3
	DBRA	D4,.riga
	ADDA.L	#ROTELLA_PLANE_SZ,A0		; piano successivo, sorgente
	ADDA.L	#PANNELLO_BUF_PLANE,A1		; piano successivo, destinazione
	DBRA	D5,.piano

	DBRA	D7,.cifra
.fine:
	MOVEM.L	(SP)+,D0-D2/D4-D7/A0-A3
	RTS

* DisegnaIndicatori - le due barre nei riquadri di sinistra
*   In alto l'ENERGIA, in basso la VITA del player. La vita si legge da
*   bob_PF della sua struct e non da una copia: due numeri che dicono la stessa
*   cosa sono due numeri che possono scollarsi.
*   Il livello si RICAVA dal valore, non si conta:
*       livello = valore * (INDIC_LIVELLI-1) / massimo
*   Cambiando PLAYER_PF_MAX o ENERGIA_MAX la barra si ritara da sola. Il
*   risultato si satura sull'ultimo livello: un valore fuori scala non deve
*   poter indirizzare fuori dalla griglia.
*   Si ridisegna solo quando cambia il LIVELLO, non il valore: fra un livello e
*   l'altro ci sono due punti ferita, e riscrivere il pannello per un valore che
*   mostra la stessa barra e' lavoro buttato.
*   IL COLORE non sta nell'arte. L'arte ha una coppia di indici (13 e 14) e il
*   colore vero lo mettono due blocchi di copper, uno per riquadro, che questa
*   routine riscrive quando il livello cambia fascia. Costa quattro word per
*   barra invece di sei voci di palette, che il pannello non ha.
*   Niente blitter, per lo stesso motivo delle cifre del punteggio: la barra e'
*   larga 40 px allineati al byte, quindi sono 5 MOVE.B per riga.
*   DISTRUGGE: nulla (salva tutto).
DisegnaIndicatori:
	MOVEM.L	D0-D7/A0-A4,-(SP)
	LEA		IndicTab,A4
	MOVEQ	#INDIC_QUANTI-1,D7
.indicatore:

	; ----- 1. il livello OBIETTIVO, ricavato dal valore -----
	MOVEA.L	ind_Valore(A4),A0
	MOVE.W	(A0),D0
	MULU	#INDIC_LIVELLI-1,D0
	DIVU	ind_Massimo(A4),D0
	AND.L	#$FFFF,D0					; DIVU lascia il resto nella word alta
	CMP.W	#INDIC_LIVELLI-1,D0
	BLS.S	.in_scala
	MOVEQ	#INDIC_LIVELLI-1,D0			; un valore fuori scala non deve poter
.in_scala:									; indirizzare fuori dalla griglia

	; ----- 2. l'animazione avanza di un fotogramma -----
	MOVE.W	ind_Fase(A4),D1
	CMP.W	#INDIC_FASI_FERMA,D1
	BCC.S	.in_movimento				; fase oltre le colonne di riposo = transizione

	; ----- a riposo: o parte una transizione, o girano le bolle -----
	CMP.W	ind_Livello(A4),D0
	BEQ.S	.bolle						; obiettivo raggiunto: respira e basta
	BCS.S	.parte_giu
	MOVEQ	#INDIC_FASE_SU,D1			; sale
	BRA.S	.parte
.parte_giu:
	MOVEQ	#INDIC_FASE_GIU,D1			; scende
.parte:
	MOVE.W	D1,ind_Fase(A4)
	MOVE.W	#INDIC_RITMO,ind_Ritmo(A4)
	BRA.W	.disegna

.bolle:
	; Le bolle hanno un ritmo tutto loro, piu' lento delle transizioni, e non si
	; fermano mai: sono il segno che la barra e' viva anche col valore fermo.
	; Il contatore qui va a zero e sotto, quindi si guarda il SEGNO e non lo
	; zero: quando entra in questo ramo per la prima volta il ritmo vale ancora
	; quello lasciato dalla transizione, e a zero deve scattare subito.
	SUBQ.W	#1,ind_Ritmo(A4)
	BPL.W	.disegna					; il fotogramma dura ancora
	MOVE.W	#INDIC_RITMO_BOLLE,ind_Ritmo(A4)
	ADDQ.W	#1,D1
	CMP.W	#INDIC_FASI_FERMA,D1
	BCS.S	.bolle_ok
	MOVEQ	#0,D1						; il ciclo si richiude
.bolle_ok:
	MOVE.W	D1,ind_Fase(A4)
	BRA.W	.disegna

.in_movimento:
	SUBQ.W	#1,ind_Ritmo(A4)
	BNE.W	.disegna					; questo fotogramma dura ancora
	MOVE.W	#INDIC_RITMO,ind_Ritmo(A4)
	ADDQ.W	#1,D1
	; finita la sequenza? allora si ATTERRA sul livello di arrivo e si torna
	; alla posa ferma. La salita finisce dove comincia la discesa, la discesa
	; finisce dove finiscono le colonne: due confronti, tutti e due derivati.
	CMP.W	#INDIC_FASE_GIU,D1
	BEQ.S	.atterra_su
	CMP.W	#INDIC_FOTOGRAMMI,D1
	BEQ.S	.atterra_giu
	MOVE.W	D1,ind_Fase(A4)
	BRA.S	.disegna
.atterra_su:
	ADDQ.W	#1,ind_Livello(A4)
	CLR.W	ind_Fase(A4)
	MOVE.W	#INDIC_RITMO_BOLLE,ind_Ritmo(A4)
	BRA.S	.disegna
.atterra_giu:
	SUBQ.W	#1,ind_Livello(A4)
	CLR.W	ind_Fase(A4)
	MOVE.W	#INDIC_RITMO_BOLLE,ind_Ritmo(A4)

	; ----- 3. si tocca il pannello solo se cambia il FOTOGRAMMA -----
.disegna:
	MOVE.W	ind_Livello(A4),D2
	MULU	#INDIC_FOTOGRAMMI,D2
	ADD.W	ind_Fase(A4),D2				; D2 = fotogramma, livello e fase insieme
	CMP.W	ind_Disegnato(A4),D2
	BEQ.W	.prossimo
	MOVE.W	D2,ind_Disegnato(A4)

	; il colore dipende dal LIVELLO, non dalla fase: durante una transizione
	; la barra tiene la tinta del livello da cui parte e la cambia atterrando.
	MOVE.W	ind_Livello(A4),D3
	LSL.W	#2,D3						; due word per livello
	LEA		IndicRampa,A2
	MOVE.W	0(A2,D3.W),D4				; tinta scura
	MOVE.W	2(A2,D3.W),D5				; tinta viva
	MOVEA.L	ind_CopHi(A4),A2
	MOVE.W	D4,2(A2)
	MOVE.W	D5,6(A2)
	MOVEA.L	ind_CopLo(A4),A2
	MOVE.W	D4,2(A2)
	MOVE.W	D5,6(A2)

	; sorgente: riga = livello, colonna = fase
	MOVE.W	ind_Livello(A4),D0
	MULU	#INDIC_H*INDIC_ROWB,D0
	MOVE.W	ind_Fase(A4),D1
	MULU	#INDIC_CELL_W/8,D1
	ADD.L	D1,D0
	LEA		IndicSheet,A0
	ADDA.L	D0,A0
	; destinazione: riga ind_Y del pannello, byte INDIC_X/8
	MOVE.W	ind_Y(A4),D1
	MULU	#PANNELLO_BUF_PITCH,D1
	LEA		PannelloBuf,A1
	ADDA.L	D1,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS+INDIC_X/8,A1
	BSR.W	DisegnaBarra

.prossimo:
	LEA		ind_Length(A4),A4
	DBRA	D7,.indicatore
	MOVEM.L	(SP)+,D0-D7/A0-A4
	RTS

* DisegnaBarra - copia un fotogramma dell'indicatore dentro il pannello
*   IN:  A0 = primo byte del fotogramma nello sheet (piano 0)
*        A1 = primo byte della destinazione in PannelloBuf (piano 0)
*   Quattro piani, INDIC_H righe, INDIC_BYTE_W byte per riga.
*   DISTRUGGE: D4, D5, D6, A0-A3. Li salva DisegnaIndicatori.
DisegnaBarra:
	MOVEQ	#INDIC_PIANI_PAN-1,D5
.piano:
	MOVEA.L	A0,A2
	MOVEA.L	A1,A3
	MOVEQ	#INDIC_H-1,D4
.riga:
	MOVEQ	#INDIC_BYTE_W-1,D6
.byte:
	MOVE.B	(A2)+,(A3)+
	DBRA	D6,.byte
	ADDA.W	#INDIC_ROWB-INDIC_BYTE_W,A2			; riga successiva nella striscia
	ADDA.W	#PANNELLO_BUF_PITCH-INDIC_BYTE_W,A3	; riga successiva nel pannello
	DBRA	D4,.riga
	ADDA.L	#INDIC_PLANE_SZ,A0					; piano successivo, sorgente
	ADDA.L	#PANNELLO_BUF_PLANE,A1				; piano successivo, destinazione
	DBRA	D5,.piano
	RTS

* CopiaCellaPannello - una cella di un foglio dentro PannelloBuf
*   IN:  A0 = primo byte della cella nel foglio (piano 0)
*        A1 = primo byte della destinazione in PannelloBuf (piano 0)
*        D0 = byte per riga della cella
*        D1 = righe della cella
*        D2 = byte per riga del FOGLIO (il passo fra una riga e la successiva)
*        D3 = byte di un piano del foglio
*   E' DisegnaBarra con le misure fuori invece che dentro: i tre strumenti
*   hanno celle di larghezza diversa (2 e 5 byte) ma lo stesso identico ciclo.
*   DISTRUGGE: nulla (salva tutto).
CopiaCellaPannello:
	MOVEM.L	D0-D7/A0-A3,-(SP)
	MOVE.W	D2,D5
	SUB.W	D0,D5						; foglio: byte da saltare a fine riga
	MOVE.W	#PANNELLO_BUF_PITCH,D6
	SUB.W	D0,D6						; pannello: byte da saltare a fine riga
	SUBQ.W	#1,D0						; contatori a base zero per DBRA
	SUBQ.W	#1,D1
	MOVEQ	#PANNELLO_BITPLANES-1,D7
.piano:
	MOVEA.L	A0,A2
	MOVEA.L	A1,A3
	MOVE.W	D1,D4
.riga:
	MOVE.W	D0,D2
.byte:
	MOVE.B	(A2)+,(A3)+
	DBRA	D2,.byte
	ADDA.W	D5,A2
	ADDA.W	D6,A3
	DBRA	D4,.riga
	ADDA.L	D3,A0						; piano successivo, sorgente
	ADDA.L	#PANNELLO_BUF_PLANE,A1		; piano successivo, destinazione
	DBRA	D7,.piano
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

* DisegnaSchermo - lo schermo centrale
*   SchermoModo a 0 mostra la neve, da 1 a SCHERMO_IMMAGINI mostra l'immagine
*   di quell'evento. Chi glielo mette non c'e' ancora: per adesso lo gira il
*   tasto S.
*   Si ridisegna solo quando cambia il FOTOGRAMMA, e il fotogramma e' un numero
*   solo (riga per colonne piu' colonna) come per le barre: due numeri per dire
*   la stessa cosa sono due numeri che possono scollarsi.
*   DISTRUGGE: nulla (salva tutto).
DisegnaSchermo:
	MOVEM.L	D0-D3/A0-A1,-(SP)
	MOVE.W	SchermoModo,D0
	BNE.S	.immagine

	; --- neve: avanza di un fotogramma ogni SCHERMO_RITMO frame ---
	SUBQ.W	#1,SchermoRitmo
	BPL.S	.neve_pronta
	MOVE.W	#SCHERMO_RITMO-1,SchermoRitmo
	MOVE.W	SchermoFase,D1
	ADDQ.W	#1,D1
	CMP.W	#SCHERMO_NEVE,D1
	BCS.S	.neve_ok
	MOVEQ	#0,D1						; il ciclo si richiude
.neve_ok:
	MOVE.W	D1,SchermoFase
.neve_pronta:
	MOVE.W	SchermoFase,D2				; colonna
	MOVEQ	#0,D3						; riga 0 della griglia
	BRA.S	.disegna

.immagine:
	SUBQ.W	#1,D0
	CMP.W	#SCHERMO_IMMAGINI,D0
	BCS.S	.imm_ok
	MOVEQ	#0,D0						; un modo fuori scala mostra la prima
.imm_ok:
	MOVE.W	D0,D2						; colonna
	MOVEQ	#1,D3						; riga 1 della griglia

.disegna:
	MOVE.W	D3,D0
	MULU	#SCHERMO_COLONNE,D0
	ADD.W	D2,D0						; fotogramma: riga e colonna insieme
	CMP.W	SchermoDisegnato,D0
	BEQ.S	.fine
	MOVE.W	D0,SchermoDisegnato

	MOVE.W	D3,D0
	MULU	#SCHERMO_H*SCHERMO_ROWB,D0	; riga della griglia
	MULU	#SCHERMO_BYTE_W,D2			; colonna
	ADD.L	D2,D0
	LEA		SchermoSheet,A0
	ADDA.L	D0,A0
	LEA		PannelloBuf,A1
	ADDA.L	#PANNELLO_ART_BYTE_OFS+SCHERMO_Y*PANNELLO_BUF_PITCH+SCHERMO_X/8,A1
	MOVEQ	#SCHERMO_BYTE_W,D0
	MOVEQ	#SCHERMO_H,D1
	MOVE.W	#SCHERMO_ROWB,D2
	MOVE.L	#SCHERMO_PLANE_SZ,D3
	BSR.W	CopiaCellaPannello
.fine:
	MOVEM.L	(SP)+,D0-D3/A0-A1
	RTS

* DisegnaSpie - le quattro spie in basso a destra
*   Un bit di SpieAccese per spia. Accesa, la spia percorre le fasi
*   dell'accensione e resta sull'ultima; spenta, torna subito alla fase 0, che
*   e' la cella vuota, cioe' il buco nero come lo ha lasciato il pannello.
*   Le posizioni stanno in SpieTab e non qui, perche' le legge anche
*   ComponiSheet per prendere lo sfondo giusto: una sola copia.
*   DISTRUGGE: nulla (salva tutto).
DisegnaSpie:
	MOVEM.L	D0-D7/A0-A4,-(SP)
	LEA		SpieTab,A4
	MOVEQ	#SPIE_TOT-1,D7
.spia:
	MOVE.W	spi_Fase(A4),D1
	MOVE.W	SpieAccese,D0
	AND.W	spi_Bit(A4),D0
	BNE.S	.accesa
	MOVEQ	#0,D1						; spenta: si spegne subito, non a scalare
	MOVE.W	D1,spi_Fase(A4)
	BRA.S	.disegna
.accesa:
	CMP.W	#SPIA_FASI-1,D1
	BCC.S	.disegna					; a regime: l'ultimo fotogramma resta
	SUBQ.W	#1,spi_Ritmo(A4)
	BPL.S	.disegna
	MOVE.W	#SPIA_RITMO-1,spi_Ritmo(A4)
	ADDQ.W	#1,D1
	MOVE.W	D1,spi_Fase(A4)

.disegna:
	CMP.W	spi_Disegnato(A4),D1
	BEQ.S	.prossima
	MOVE.W	D1,spi_Disegnato(A4)

	; La sorgente non si ricava da un indice: sta nella riga. Le quattro gialle
	; e la rossa vivono in due fogli diversi, montati con mappe diverse, e la
	; riga sa dove comincia la SUA cella e quanto e' grande un piano del SUO
	; foglio. Cosi' il ciclo e' uno solo e non sa niente del colore.
	MOVE.W	D1,D0
	MULU	#SPIA_BYTE_W,D0				; colonna = la fase
	MOVEA.L	spi_Cella(A4),A0
	ADDA.L	D0,A0

	MOVE.W	spi_Y(A4),D0
	MULU	#PANNELLO_BUF_PITCH,D0
	ADD.W	spi_X(A4),D0
	LEA		PannelloBuf,A1
	ADDA.L	D0,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS,A1

	MOVEQ	#SPIA_BYTE_W,D0
	MOVEQ	#SPIA_H,D1
	MOVE.W	#SPIA_ROWB,D2
	MOVE.L	spi_PianoSz(A4),D3
	BSR.W	CopiaCellaPannello
.prossima:
	LEA		spi_Length(A4),A4
	DBRA	D7,.spia
	MOVEM.L	(SP)+,D0-D7/A0-A4
	RTS

* DisegnaQuadrante - la lancetta del quadrante grande
*   QuadranteObiettivo sceglie una delle quattro posizioni (ovest, nord, est,
*   sud-sud-est); QuadPosizioni le traduce in angoli di bussola. La lancetta ci
*   arriva un passo alla volta, dalla parte piu' corta, e durante il movimento
*   mostra la riga con lo sbuffo di vapore invece di quella pulita.
*   La parte piu' corta si trova senza confronti fra angoli: la distanza IN
*   AVANTI e' (arrivo - partenza) AND 15, e se e' oltre mezzo giro conviene
*   andare indietro. Cosi' il giro e' sempre al massimo di otto passi e non
*   c'e' nessun caso speciale allo scavallamento dello zero.
*   DISTRUGGE: nulla (salva tutto).
DisegnaQuadrante:
	MOVEM.L	D0-D3/A0-A1,-(SP)
	MOVE.W	QuadranteObiettivo,D0
	AND.W	#3,D0						; quattro posizioni, e basta
	ADD.W	D0,D0
	LEA		QuadPosizioni,A0
	MOVE.W	0(A0,D0.W),D0				; angolo di arrivo
	MOVE.W	QuadranteAngolo,D1
	CMP.W	D0,D1
	BEQ.S	.ferma

	SUBQ.W	#1,QuadranteRitmo
	BPL.S	.sbuffo						; il fotogramma dura ancora
	MOVE.W	#QUAD_RITMO-1,QuadranteRitmo
	SUB.W	D1,D0
	AND.W	#QUAD_ANGOLI-1,D0			; distanza in avanti, 1..QUAD_ANGOLI-1
	CMP.W	#QUAD_ANGOLI/2,D0
	BHI.S	.indietro
	ADDQ.W	#1,D1
	BRA.S	.passo
.indietro:
	SUBQ.W	#1,D1
.passo:
	AND.W	#QUAD_ANGOLI-1,D1
	MOVE.W	D1,QuadranteAngolo
.sbuffo:
	; lo sbuffo segue il passo: una fase per frame, e con QUAD_RITMO uguale a
	; QUAD_SBUFFI le tre fasi entrano esatte in un passo.
	MOVE.W	#QUAD_RITMO-1,D2
	SUB.W	QuadranteRitmo,D2
	ADDQ.W	#1,D2
	CMP.W	#QUAD_SBUFFI,D2
	BLS.S	.disegna
	MOVEQ	#QUAD_SBUFFI,D2				; ritmi piu' lunghi delle fasi: si tiene
	BRA.S	.disegna					; l'ultima invece di uscire dalla griglia
.ferma:
	CLR.W	QuadranteRitmo				; il primo passo del prossimo giro parte subito
	MOVEQ	#0,D2						; riga 0: la lancetta pulita

.disegna:
	MOVE.W	QuadranteAngolo,D1
	MOVE.W	D2,D0
	MULU	#QUAD_ANGOLI,D0
	ADD.W	D1,D0						; fotogramma: riga e angolo insieme
	CMP.W	QuadranteDisegnato,D0
	BEQ.S	.fine
	MOVE.W	D0,QuadranteDisegnato

	MOVE.W	D2,D0
	MULU	#QUAD_H*QUAD_ROWB,D0		; riga della griglia
	MULU	#QUAD_BYTE_W,D1				; colonna = l'angolo
	ADD.L	D1,D0
	LEA		QuadSheet,A0
	ADDA.L	D0,A0
	LEA		PannelloBuf,A1
	ADDA.L	#PANNELLO_ART_BYTE_OFS+QUAD_Y*PANNELLO_BUF_PITCH+QUAD_X/8,A1
	MOVEQ	#QUAD_BYTE_W,D0
	MOVEQ	#QUAD_H,D1
	MOVE.W	#QUAD_ROWB,D2
	MOVE.L	#QUAD_PLANE_SZ,D3
	BSR.W	CopiaCellaPannello
.fine:
	MOVEM.L	(SP)+,D0-D3/A0-A1
	RTS

* Routine che aspetta il blitter
AspettaBlitter:
	BTST	#6,2(a6)		; dmaconr - waitblit
.bltw:
	BTST	#6,2(a6)		; dmaconr - waitblit
	BNE.S	.bltw
	RTS
; Modulo di stampa testo (font 16x20). Generico e riutilizzabile:
; monitor, punteggio, messaggi. Vedi Testo.i per l'API.
	include	"Testo.i"

; SCRITTA SCORREVOLE sotto il monitor
; Sta QUI e non con le altre EQU degli strumenti perche' discende da FONT_H e
; FONT_GLYPH, definite in Testo.i: Devpac valuta una EQU dove la incontra.
; Il buco misurato sui pixel di Pannello.raw e' x114..212 y54..67; il piu' grande
; rettangolo nero allineato al byte dentro di esso e' x120..207 su y58..67.
; Undici caratteri, 6 px di margine a sinistra e 5 a destra.
; SI SCRIVE A BYTE, NON A WORD: x120/8 = 15, dispari, e il pitch del pannello e'
; pari, quindi ogni riga comincia a un indirizzo dispari e una MOVE.W li' e' un
; address error sul 68000. La finestra allineata alla word (x128..207, dieci
; caratteri) costerebbe il 40% in meno ma lascerebbe 14 px di margine a sinistra:
; le lettere sparirebbero prima del bordo. E' il primo numero da toccare se la
; scritta risultasse cara.
; IL FONDO NON SI RISCRIVE: il riquadro e' indice 15, tutti e quattro i piani
; accesi. Sui piani dove la tinta ha il bit a 1 il pixel resta acceso sia sul
; fondo sia sulla lettera, quindi quei piani sono gia' giusti come li ha lasciati
; DisegnaPannello. Si riscrivono solo i piani dove la tinta ha il bit a 0, col
; NEGATO della sagoma: con la tinta 6 sono due piani su quattro.
SCRITTA_X			EQU		120			; primo byte della finestra
SCRITTA_Y			EQU		59			; il buco nero va da y58 a y67: il glifo
	; e' alto 7 px su 8, quindi centrato qui
SCRITTA_BYTE_W		EQU		11			; caratteri che si vedono in una volta
SCRITTA_H			EQU		FONT_H
SCRITTA_TINTA		EQU		6
SCRITTA_VELOCITA	EQU		1			; px per quadro. A 0 la scritta sta ferma.
SCRITTA_MAX_CAR		EQU		100			; caratteri del messaggio piu' lungo
; Byte ricopiati in fondo a ogni riga per chiudere il giro senza cucitura.
; Non e' un numero a gusto: la lettura piu' avanzata di DisegnaScritta e' un
; long che comincia al decimo byte della finestra, quindi servono
; SCRITTA_BYTE_W+3 byte oltre la fine del messaggio. Uno in piu' per sicurezza.
SCRITTA_CODA		EQU		SCRITTA_BYTE_W+4
SCRITTA_ROWB		EQU		((SCRITTA_MAX_CAR+SCRITTA_CODA+1)/2)*2
SCRITTA_BUF_SZ		EQU		SCRITTA_ROWB*SCRITTA_H
; Prima riga in cui la voce della scritta prende il suo colore. Sta sotto
; l'ultima riga delle spie (y56) e sopra la prima riga del glifo (y59).
SCRITTA_Y0			EQU		57
SCRITTA_RASTER		EQU		PANNELLO_ART_RASTER+SCRITTA_Y0
SCRITTA_COL			EQU		$0cef		; azzurro chiaro, in tinta col pannello
; Quanti piani si riscrivono: quelli in cui la tinta ha il bit a ZERO. Esce dal
; numero della tinta, non da una scelta, ed e' lo stesso conto che decide le
; righe di ScrittaPianiTab: le due strade si controllano a vicenda con
; GUARDIA_SCRITTA_PIANI.
SCRITTA_PIANI_N		EQU		(1-((SCRITTA_TINTA>>0)&1))+(1-((SCRITTA_TINTA>>1)&1))+(1-((SCRITTA_TINTA>>2)&1))+(1-((SCRITTA_TINTA>>3)&1))
	IFEQ	SCRITTA_PIANI_N
; Con una tinta uguale al fondo non ci sarebbe niente da scrivere, e il ciclo
; dei piani girerebbe 65536 volte.
GUARDIA_SCRITTA_TINTA	EQU		1/0
	ENDC
	IFLT	SCRITTA_RASTER-256
GUARDIA_SCRITTA_RASTER	EQU		1/0
	ENDC
	IFLE	SCRITTA_ROWB-(SCRITTA_MAX_CAR+SCRITTA_CODA)
; La riga del buffer deve contenere il messaggio piu' la coda.
GUARDIA_SCRITTA_ROWB	EQU		1/0
	ENDC

* DisegnaLettera - un carattere del font nel quadrato all'estrema destra
*   Lo prende da LetteraDestra (codice ASCII) e ridisegna solo quando cambia,
*   quindi il costo di questa routine e' quasi sempre un confronto.
*   Il glifo NON cade su un byte: l'unica posizione tutta nera dentro il buco
*   e' x285..292, a cavallo di due byte. Quindi la riga del font si porta in
*   una word con una LSL e la si compone col fondo, che si rilegge da
*   'pannello'. Non c'e' un foglio da montare al boot: un carattere per volta
*   costa 64 operazioni su byte, e succede quando cambia la lettera.
*   Per ogni piano: dove la tinta ha il bit a 1 il glifo ACCENDE (OR), dove ce
*   l'ha a 0 SPEGNE (AND col negato). I bit della tinta si consumano uno alla
*   volta con una LSR, cosi' non c'e' nessuna tabella da tenere allineata.
*   Tutto a byte: la cella comincia al byte LETTERA_X/8 = 35, dispari, e una
*   MOVE.W a indirizzo dispari e' un address error sul 68000.
*   DISTRUGGE: nulla (salva tutto).
DisegnaLettera:
	MOVEM.L	D0-D6/A0-A4,-(SP)
	MOVE.W	LetteraDestra,D0
	CMP.W	LetteraDisegnata,D0
	BEQ.W	.fine
	MOVE.W	D0,LetteraDisegnata

	; --- il glifo nel font ---
	SUB.W	#FONT_FIRST,D0
	BCC.S	.sopra
	MOVEQ	#0,D0						; sotto lo spazio -> spazio
.sopra:
	CMP.W	#FONT_CHARS,D0
	BCS.S	.dentro
	MOVEQ	#0,D0						; oltre l'ultimo -> spazio
.dentro:
	MULU	#FONT_GLYPH,D0
	LEA		FontData,A0
	ADDA.W	D0,A0

	; --- fondo e destinazione ---
	LEA		pannello,A1
	ADDA.W	#LETTERA_Y*PANNELLO_BYTES_PER_ROW+LETTERA_X/8,A1
	LEA		PannelloBuf,A2
	ADDA.L	#PANNELLO_ART_BYTE_OFS+LETTERA_Y*PANNELLO_BUF_PITCH+LETTERA_X/8,A2

	MOVEQ	#FONT_H-1,D5
.riga:
	MOVEQ	#0,D1
	MOVE.B	(A0)+,D1					; gli 8 px di questa riga del glifo
	LSL.W	#8-LETTERA_OFS,D1			; portati dove cadono nella cella
	ROL.W	#8,D1						; D1.b = byte sinistro, alto = destro
	MOVEA.L	A1,A3
	MOVEA.L	A2,A4
	MOVEQ	#LETTERA_TINTA,D3			; i bit della tinta, uno per piano
	MOVEQ	#PANNELLO_BITPLANES-1,D4
.piano:
	MOVE.W	D1,D6						; copia della sagoma, si consuma
	LSR.W	#1,D3						; il bit di questo piano finisce in C
	BCC.S	.spegne
	MOVE.B	(A3),D2
	OR.B	D6,D2
	MOVE.B	D2,(A4)
	ROL.W	#8,D6
	MOVE.B	1(A3),D2
	OR.B	D6,D2
	MOVE.B	D2,1(A4)
	BRA.S	.avanti
.spegne:
	NOT.W	D6
	MOVE.B	(A3),D2
	AND.B	D6,D2
	MOVE.B	D2,(A4)
	ROL.W	#8,D6
	MOVE.B	1(A3),D2
	AND.B	D6,D2
	MOVE.B	D2,1(A4)
.avanti:
	ADDA.W	#PANNELLO_PLANE_SIZE,A3
	ADDA.L	#PANNELLO_BUF_PLANE,A4
	DBRA	D4,.piano
	ADDA.W	#PANNELLO_BYTES_PER_ROW,A1
	ADDA.W	#PANNELLO_BUF_PITCH,A2
	DBRA	D5,.riga
.fine:
	MOVEM.L	(SP)+,D0-D6/A0-A4
	RTS

* ImpostaScritta - prepara il messaggio che scorre sotto il monitor
*   IN:  A0 = stringa terminata da zero
*   Costruisce la mappa a 1 piano del messaggio: un byte per carattere, otto
*   righe. La tiene GIA' NEGATA, perche' quello che finisce nei bitplane e' il
*   negato della sagoma: negando qui si toglie una NOT dal ciclo che gira ogni
*   quadro. Lo scorrimento pesca i bit dal byte accanto, e negato o no il conto
*   e' lo stesso, quindi la negazione anticipata non cambia niente.
*   In fondo a ogni riga si ricopiano SCRITTA_CODA byte presi MODULO la
*   lunghezza: cosi' il giro si richiude senza cucitura anche con un messaggio
*   piu' corto della finestra.
*   DISTRUGGE: nulla (salva tutto).
ImpostaScritta:
	MOVEM.L	D0-D5/A0-A3,-(SP)
	LEA		ScrittaBuf,A1
	MOVEQ	#0,D0						; caratteri sistemati finora
.car:
	MOVEQ	#0,D1
	MOVE.B	(A0)+,D1
	BEQ.S	.finita
	CMP.W	#SCRITTA_MAX_CAR,D0
	BCC.S	.finita						; il resto del messaggio non ci sta
	SUB.W	#FONT_FIRST,D1
	BCC.S	.sopra
	MOVEQ	#0,D1
.sopra:
	CMP.W	#FONT_CHARS,D1
	BCS.S	.dentro
	MOVEQ	#0,D1
.dentro:
	MULU	#FONT_GLYPH,D1
	LEA		FontData,A2
	ADDA.W	D1,A2
	MOVEA.L	A1,A3
	MOVEQ	#SCRITTA_H-1,D2
.riga:
	MOVE.B	(A2)+,D3
	NOT.B	D3							; la mappa si tiene negata
	MOVE.B	D3,(A3)
	ADDA.W	#SCRITTA_ROWB,A3
	DBRA	D2,.riga
	ADDQ.L	#1,A1
	ADDQ.W	#1,D0
	BRA.S	.car

.finita:
	MOVE.W	D0,ScrittaCar
	MOVE.W	D0,D1
	LSL.W	#3,D1						; la lunghezza in px, dove il giro si chiude
	MOVE.W	D1,ScrittaFine
	CLR.W	ScrittaOffset
	TST.W	D0
	BEQ.S	.vuota						; messaggio vuoto: niente coda da fare

	LEA		ScrittaBuf,A1
	MOVEQ	#SCRITTA_H-1,D2
.coda_riga:
	MOVEQ	#0,D3						; posizione dentro la coda
	MOVEQ	#0,D4						; posizione nel messaggio, che si richiude
.coda:
	MOVE.W	D0,D5
	ADD.W	D3,D5
	MOVE.B	0(A1,D4.W),0(A1,D5.W)
	ADDQ.W	#1,D4
	CMP.W	D0,D4
	BCS.S	.coda_ok
	MOVEQ	#0,D4
.coda_ok:
	ADDQ.W	#1,D3
	CMP.W	#SCRITTA_CODA,D3
	BCS.S	.coda
	ADDA.W	#SCRITTA_ROWB,A1
	DBRA	D2,.coda_riga
.vuota:
	MOVEM.L	(SP)+,D0-D5/A0-A3
	RTS

* DisegnaScritta - fa scorrere il messaggio di SCRITTA_VELOCITA px
*   L'unica parte mobile del pannello che si ridisegna a OGNI quadro: le altre
*   hanno un "gia' disegnato" da confrontare, questa per definizione cambia
*   sempre. E' anche l'unica che non cade su un byte, ed e' li' che sta il
*   lavoro.
*   Come si prende una riga spostata di n px: si legge un LONG all'indirizzo
*   PARI che contiene i due byte voluti, lo si sposta a sinistra di n, e la word
*   alta e' esattamente la coppia di byte che serve. Cosi' n vale 0..15 e la
*   sorgente resta sempre allineata alla word, che sul 68000 non e' un dettaglio
*   di velocita' ma la differenza fra funzionare e un address error.
*   I due byte poi si scrivono UNO ALLA VOLTA, perche' la destinazione comincia
*   a un byte dispari: vedi il blocco EQU della scritta.
*   Si scrivono solo i piani in cui la tinta ha il bit a 0 (ScrittaPianiTab):
*   sugli altri il fondo nero e la lettera accendono lo stesso pixel, e quello
*   che c'e' gia' e' gia' giusto.
*   DISTRUGGE: nulla (salva tutto).
DisegnaScritta:
	MOVEM.L	D0-D7/A0-A4,-(SP)
	MOVE.W	ScrittaCar,D0
	BEQ.W	.fine						; nessun messaggio impostato

	; --- avanza lo scorrimento, e si richiude ---
	MOVE.W	ScrittaOffset,D0
	ADD.W	#SCRITTA_VELOCITA,D0
	CMP.W	ScrittaFine,D0
	BCS.S	.off_ok
	SUB.W	ScrittaFine,D0
.off_ok:
	MOVE.W	D0,ScrittaOffset
	MOVE.W	D0,D2
	AND.W	#15,D2						; spostamento in bit, 0..15
	LSR.W	#4,D0
	ADD.W	D0,D0						; byte PARI da cui leggere
	LEA		ScrittaBuf,A0
	ADDA.W	D0,A0
	LEA		PannelloBuf,A1
	ADDA.L	#PANNELLO_ART_BYTE_OFS+SCRITTA_Y*PANNELLO_BUF_PITCH+SCRITTA_X/8,A1

	LEA		ScrittaPianiTab,A4
	MOVEQ	#SCRITTA_PIANI_N-1,D7
.piano:
	MOVEA.L	A0,A2
	MOVEA.L	A1,A3
	ADDA.L	(A4)+,A3					; questo piano della destinazione
	MOVEQ	#SCRITTA_H-1,D6
.riga:
	MOVEQ	#SCRITTA_BYTE_W/2-1,D5
.coppia:
	MOVE.L	(A2),D1
	ADDQ.L	#2,A2
	LSL.L	D2,D1
	SWAP	D1							; D1.w = i due byte, gia' spostati
	ROL.W	#8,D1
	MOVE.B	D1,(A3)+					; byte sinistro
	ROL.W	#8,D1
	MOVE.B	D1,(A3)+					; byte destro
	DBRA	D5,.coppia
	IFNE	SCRITTA_BYTE_W&1
	MOVE.L	(A2),D1						; il byte dispari in fondo alla finestra
	LSL.L	D2,D1
	SWAP	D1
	ROL.W	#8,D1
	MOVE.B	D1,(A3)+
	ENDC
	ADDA.W	#SCRITTA_ROWB-(SCRITTA_BYTE_W/2)*2,A2
	ADDA.W	#PANNELLO_BUF_PITCH-SCRITTA_BYTE_W,A3
	DBRA	D6,.riga
	DBRA	D7,.piano
.fine:
	MOVEM.L	(SP)+,D0-D7/A0-A4
	RTS

