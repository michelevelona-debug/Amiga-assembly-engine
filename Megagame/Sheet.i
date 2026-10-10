; Sheet.i - Fogli costruiti al boot: falo', rotella, indicatori
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* BuildFaloSheet - dalla striscia a 2 piani allo spritesheet a 5 piani
*   Gira UNA VOLTA al boot. L'indice di colore del falo' vale FALO_PAL_BASE+v
*   con v = 1..3 preso dall'arte, cioe' in binario %011vv. Da questo esce
*   tutta la conversione, senza percorrere i pixel uno per uno:
*     piano 0 = piano 0 dell'arte      (bit 0 dell'indice)
*     piano 1 = piano 1 dell'arte      (bit 1)
*     piano 2 = sagoma = p0 OR p1      (bit 2, acceso su ogni pixel non vuoto)
*     piano 3 = sagoma                 (bit 3)
*     piano 4 = sempre spento          (bit 4)
*   Lo stacco fra i frame resta nero su tutti i piani, quindi la maschera che
*   BuildBobMask ricava come OR dei cinque piani esce gia' giusta.
*   DISTRUGGE: nulla (salva tutto).
BuildFaloSheet:
	MOVEM.L	D0-D2/A0-A1,-(SP)
	LEA		falo_strip,A0
	LEA		FaloSheet,A1
	MOVE.W	#FALO_PLANE_SZ/4-1,D0	; il piano si percorre a long
.espandi:
	MOVE.L	(A0),D1					; piano 0 dell'arte
	MOVE.L	FALO_PLANE_SZ(A0),D2	; piano 1 dell'arte
	MOVE.L	D1,(A1)
	MOVE.L	D2,FALO_PLANE_SZ(A1)
	OR.L	D2,D1					; D1 = sagoma
	MOVE.L	D1,2*FALO_PLANE_SZ(A1)
	MOVE.L	D1,3*FALO_PLANE_SZ(A1)
	CLR.L	4*FALO_PLANE_SZ(A1)
	ADDQ.L	#4,A0
	ADDQ.L	#4,A1
	DBRA	D0,.espandi

	; ----- la maschera si fa QUI, e non e' un vezzo di ordine -----
	; Gli altri sheet arrivano da un incbin e ci sono gia' quando gira
	; BuildBobMasks. Questo no: prima di questa routine FaloSheet e' una BSS
	; azzerata, e una maschera presa li' sarebbe l'OR di cinque piani vuoti,
	; cioe' tutta zero. Con la maschera a zero il cookie-cut vale D = C, il
	; fondo resta com'e' e il bob non si vede: nessun artefatto, nessun
	; errore, semplicemente niente. E' successo davvero.
	LEA		FaloSheet,A1
	LEA		FALO_MASK,A0
	MOVE.L	#FALO_PLANE_SZ,D2
	BSR.W	BuildBobMask

	MOVEM.L	(SP)+,D0-D2/A0-A1
	RTS
* BuildRotellaSheet - dalla striscia a 2 piani allo spritesheet a 5 piani
*   L'indice di palette non e' base+v come per il falo': il fondo va sul nero
*   che il riquadro del punteggio ha gia' (15) e le tre tinte sulle voci
*   liberate (4, 5, 6). In binario 1111, 0100, 0101, 0110, e da li' escono
*   quattro operazioni logiche sui due piani dell'arte:
*     piano 0 = NOT p0
*     piano 1 = NOT (p0 EOR p1)
*     piano 2 = sempre acceso
*     piano 3 = NOT (p0 OR p1)
*   Lo stacco vuoto fra i fotogrammi diventa indice 15, cioe' nero: quando
*   una cifra scorre di 8 px si porta dietro il nero del riquadro.
*   Cambiando quei quattro indici vanno riscritte queste quattro operazioni:
*   non si derivano da una EQU, sono la mappa stessa.
BuildRotellaSheet:
	MOVEM.L	D0-D3/A0-A1,-(SP)
	LEA		rotella_strip,A0
	LEA		RotellaSheet,A1
	MOVE.W	#ROTELLA_PLANE_SZ/4-1,D0	; il piano si percorre a long
.espandi:
	MOVE.L	(A0),D1						; p0 dell'arte
	MOVE.L	ROTELLA_PLANE_SZ(A0),D2		; p1 dell'arte
	MOVE.L	D1,D3
	EOR.L	D2,D3
	NOT.L	D3							; XNOR
	MOVE.L	D3,1*ROTELLA_PLANE_SZ(A1)	; piano 1
	MOVE.L	D1,D3
	OR.L	D2,D3
	NOT.L	D3							; NOT sagoma
	MOVE.L	D3,3*ROTELLA_PLANE_SZ(A1)	; piano 3
	NOT.L	D1
	MOVE.L	D1,(A1)						; piano 0
	MOVE.L	#-1,2*ROTELLA_PLANE_SZ(A1)	; piano 2: sempre acceso
	ADDQ.L	#4,A0
	ADDQ.L	#4,A1
	DBRA	D0,.espandi
	MOVEM.L	(SP)+,D0-D3/A0-A1
	RTS
* BuildIndicSheet - dalla striscia a 2 piani allo spritesheet a 4 piani
*   Stessa idea di BuildRotellaSheet, mappa diversa. I quattro valori dell'arte
*   vanno sulle voci del PANNELLO cosi':
*     0 fondo        -> 15  %1111   il nero che il riquadro ha gia'
*     1 traccia      ->  2  %0010
*     2 barra scura  -> 13  %1101
*     3 barra viva   -> 14  %1110
*   e da quei quattro indici escono tre operazioni logiche sui due piani
*   dell'arte (il piano 3 e' uguale al 2):
*     piano 0 = NOT p0
*     piano 1 = (NOT p1) OR p0
*     piano 2 = (NOT p0) OR p1
*     piano 3 = piano 2
*   Cambiando quegli indici vanno riscritte queste operazioni: non si derivano
*   da una EQU, sono la mappa stessa.
*   La barra vera e propria (13 e 14) la ricolora il copper a ogni livello:
*   qui si decide solo QUALI voci di palette usare, non che colore hanno.
*   DISTRUGGE: nulla (salva tutto).
BuildIndicSheet:
	MOVEM.L	D0-D3/A0-A1,-(SP)
	LEA		indicatore_strip,A0
	LEA		IndicSheet,A1
	MOVE.W	#INDIC_PLANE_SZ/4-1,D0		; il piano si percorre a long
.espandi:
	MOVE.L	(A0),D1						; p0 dell'arte
	MOVE.L	INDIC_PLANE_SZ(A0),D2		; p1 dell'arte

	MOVE.L	D1,D3
	NOT.L	D3
	MOVE.L	D3,(A1)						; piano 0 = NOT p0

	MOVE.L	D2,D3
	NOT.L	D3
	OR.L	D1,D3
	MOVE.L	D3,1*INDIC_PLANE_SZ(A1)		; piano 1 = (NOT p1) OR p0

	MOVE.L	D1,D3
	NOT.L	D3
	OR.L	D2,D3
	MOVE.L	D3,2*INDIC_PLANE_SZ(A1)		; piano 2 = (NOT p0) OR p1
	MOVE.L	D3,3*INDIC_PLANE_SZ(A1)		; piano 3 = piano 2

	ADDQ.L	#4,A0
	ADDQ.L	#4,A1
	DBRA	D0,.espandi
	MOVEM.L	(SP)+,D0-D3/A0-A1
	RTS

* ComponiSheets - monta i fogli dei tre strumenti, una riga di tabella l'uno
ComponiSheets:
	MOVEM.L	D7/A4,-(SP)
	LEA		StrumentiTab,A4
	MOVEQ	#STRUM_QUANTI-1,D7
.uno:
	BSR.W	ComponiSheet
	LEA		shd_Length(A4),A4
	DBRA	D7,.uno
	MOVEM.L	(SP)+,D7/A4
	RTS

* ComponiSheet - dalla striscia a 2 piani al foglio a 4 piani, con lo SFONDO
*                del pannello sotto ai pixel trasparenti
*   IN:  A4 = riga di StrumentiTab
*   Due passate e non una perche' in una sola servivano piu' registri di quanti
*   ce ne sono. Gira al boot, quindi conta il numero di registri, non i cicli.
*   PASSATA 1, le tinte. Dai due piani dell'arte escono le tre maschere:
*       m1 = p0 AND NOT p1    m2 = p1 AND NOT p0    m3 = p0 AND p1
*   e quali accendono un piano lo dice la MAPPA: dodici long, tre per piano,
*   tutti a uno o tutti a zero, generati dalla macro MAPPA_TINTE dai tre indici
*   di palette. Cambiando un indice si rifa' da sola.
*       piano = (m1 AND M1) OR (m2 AND M2) OR (m3 AND M3)
*   PASSATA 2, lo sfondo:
*       piano = piano OR (sfondo AND NOT (p0 OR p1))
*   Lo sfondo viene da 'pannello', l'arte incbinata, che e' la fonte di verita':
*   ri-esportando il pannello gli strumenti si ricompongono da soli al boot.
*   Tutte le colonne di una riga mostrano LO STESSO posto del pannello (sono
*   fotogrammi alternativi), quindi lo sfondo dipende solo dalla riga.
*   La passata 1 va a long, e lo garantisce GUARDIA_STRUM_LONG; la 2 va a byte
*   perche' la cella e' larga 2 o 5.
*   DISTRUGGE: nulla (salva tutto).
ComponiSheet:
	MOVEM.L	D0-D7/A0-A5,-(SP)

	; --- misure, tutte derivate dalla griglia della striscia ---
	MOVE.W	shd_Colonne(A4),D6
	MULU	shd_CellB(A4),D6			; D6 = byte per riga della striscia
	MOVE.W	shd_CellH(A4),D7
	MULU	shd_Righe(A4),D7
	MULU	D6,D7						; D7 = byte di UN piano
	MOVE.W	shd_CellH(A4),D3
	MULU	D6,D3						; D3 = byte di UNA riga di celle

	; ===== passata 1: le tinte ==========================================
	MOVEA.L	shd_Arte(A4),A0
	MOVEA.L	shd_Sheet(A4),A1
	MOVEA.L	shd_Mappa(A4),A3
	MOVEQ	#PANNELLO_BITPLANES-1,D5
.p1_piano:
	MOVEA.L	A0,A5						; l'arte si rilegge per ogni piano
	MOVE.L	D7,D4
	LSR.L	#2,D4
	SUBQ.L	#1,D4						; long del piano
.p1_long:
	MOVE.L	(A5),D0						; p0
	MOVE.L	0(A5,D7.L),D1				; p1
	MOVE.L	D0,D2
	AND.L	D1,D2						; D2 = m3 = p0 AND p1
	EOR.L	D2,D0						; D0 = m1 = p0 AND NOT p1
	EOR.L	D2,D1						; D1 = m2 = p1 AND NOT p0
	AND.L	(A3),D0
	AND.L	4(A3),D1
	AND.L	8(A3),D2
	OR.L	D1,D0
	OR.L	D2,D0
	MOVE.L	D0,(A1)+
	ADDQ.L	#4,A5
	SUBQ.L	#1,D4
	BPL.S	.p1_long
	LEA		12(A3),A3					; i tre long della mappa del piano dopo
	DBRA	D5,.p1_piano

	; ===== passata 2: lo sfondo sotto ai pixel trasparenti ==============
	MOVEQ	#0,D5						; indice della riga di celle
.p2_riga:
	; dove sta, nel pannello, lo sfondo di questa riga di celle
	MOVEA.L	shd_Pos(A4),A2
	MOVE.W	shd_PosPasso(A4),D0
	MULU	D5,D0
	ADDA.W	D0,A2						; A2 -> la coppia (byte x, riga y)
	MOVE.W	2(A2),D0
	MULU	#PANNELLO_BYTES_PER_ROW,D0
	ADD.W	(A2),D0
	LEA		pannello,A2
	ADDA.L	D0,A2						; A2 = sfondo, piano 0, prima riga

	; dove comincia questa riga di celle nell'arte e nel foglio
	MOVE.W	D5,D0
	MULU	D3,D0
	MOVEA.L	shd_Arte(A4),A5
	ADDA.L	D0,A5
	MOVEA.L	shd_Sheet(A4),A1
	ADDA.L	D0,A1

	MOVEQ	#PANNELLO_BITPLANES-1,D4
.p2_piano:
	MOVEA.L	A2,A0						; sfondo, riga di pixel corrente
	MOVE.W	shd_CellH(A4),D6
	SUBQ.W	#1,D6
.p2_rigapx:
	MOVE.W	shd_Colonne(A4),D1
	SUBQ.W	#1,D1
.p2_colonna:
	MOVEA.L	A0,A3						; ogni colonna rilegge la STESSA riga
	MOVE.W	shd_CellB(A4),D2
	SUBQ.W	#1,D2
.p2_byte:
	MOVE.B	(A5)+,D0					; p0
	OR.B	-1(A5,D7.L),D0				; OR p1 = la sagoma dell'arte
	NOT.B	D0
	AND.B	(A3)+,D0					; sfondo dove l'arte e' trasparente
	OR.B	D0,(A1)+
	DBRA	D2,.p2_byte
	DBRA	D1,.p2_colonna
	ADDA.W	#PANNELLO_BYTES_PER_ROW,A0	; riga successiva dello sfondo
	DBRA	D6,.p2_rigapx
	; piano successivo: l'arte torna indietro, il foglio va avanti di un piano
	SUBA.L	D3,A5
	ADDA.L	D7,A1
	SUBA.L	D3,A1
	ADDA.L	#PANNELLO_PLANE_SIZE,A2
	DBRA	D4,.p2_piano

	ADDQ.W	#1,D5
	CMP.W	shd_Righe(A4),D5
	BCS.W	.p2_riga

	MOVEM.L	(SP)+,D0-D7/A0-A5
	RTS

