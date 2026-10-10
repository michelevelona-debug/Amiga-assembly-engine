; Sfondo.i - Disegno dello sfondo, copper del cielo, skyline
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


DisegnaSfondo:
	MOVEM.L	D0-D6/A0-A2,-(SP)

	MOVEA.L	MappaPtr,A0			; la mappa VIVA, non un'etichetta fissa
	; QUI C'ERA un `MOVE.W TileX,D0 / ADD.W D0,D0 / ADDA.W D0,A0` che saltava
	; TileX colonne: relitto di Path A, quando il buffer teneva una FINESTRA
	; sulla mappa. In Path B il buffer tiene la mappa INTERA e si parte sempre
	; dalla colonna 0, quindi quella somma valeva zero a ogni avvio - ma
	; obbligava chiunque chiamasse questa routine ad azzerare prima TileX, e
	; quel vincolo era scritto solo in un commento. Tolto il 24 settembre 2026
	; per poter ricostruire il mondo a gioco acceso (vedi RicostruisciMondo):
	; e' un no-op dimostrabile, perche' al boot TileX vale 0.
	MOVE.L	#SFONDOGRANDE+DELTA_MAPPAVERA+BG_ORIGIN_OFS,PuntaSfondoGr	; guardia + origine
	MOVEQ	#BUFFER_COLS-1,D1	; d1 = numero colonne
	; BUFFER_ROWS ora include la riga di margine, che NON contiene tile:
	; il loop deve fermarsi alle righe vere della mappa, altrimenti legge
	; oltre la fine di MAPPA.
	MOVEQ	#MAPPA_ROWS-1,D2
.CicloTile:
	MOVEQ	#0,D3				; Pulisci d3
	MOVE.W	(A0)+,D3			; d3 = numero della tile da stampare

	MOVE.L	D3,D5
	DIVU	#20,D5
	MOVE.W	D5,D6
	MULU	#16*40,D6
	SWAP	D5
	MOVE.W	D5,D7
	MULU	#2,D7
	MOVE.L	D6,A2
	ADD.L	D7,A2

	ADD.L	#TILES,A2			; TROVA LA TILE DESIDERATA

	MOVE.L	PuntaSfondoGr,A1	; destinazione in a1
	ADDQ.L	#2,PuntaSfondoGr 	; avanziamo di 16 bit (PROSSIMA TILE)

	MOVEQ	#5-1,D4
.BlittaLoopSfondo:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)	; BLTAFWM e BLTALWM
	; BLTAFWM = $ffff - passa tutto
	; BLTALWM = $ffff = passa tutto
	MOVE.L	#$09F00000,$40(A6)	; BLTCON0/1 - copia normale
	MOVE.W	#38,$64(A6)			; BLTAMOD
	MOVE.W	#SFONDO_PITCH-2,$66(A6)	; BLTDMOD (era 46 hardcoded = pitch 48 - 2)
	MOVE.L	A2,$50(A6)			; BLTAPT
	MOVE.L	A1,$54(A6)			; BLTDPT
	MOVE.W	#(16*64)+1,$58(A6)	; BLTSIZE
	ADD.L	#256*40,A2				; prossimo plane sorgente
	ADD.L	#SFONDO_PLANE_SIZE,A1	; prossimo plane destinazione
	DBRA	D4,.BlittaLoopSfondo
	DBRA	D1,.CicloTile
	; Avanza PuntaSfondoGr alla riga di tile successiva.
	; Era a fine riga di tile corrente (= +BUFFER_COLS*2 byte dall'inizio).
	; Deve andare a 16 righe sotto, colonna 0 dell'inizio.
	; delta = 16*pitch - BUFFER_COLS*2
	ADD.L	#16*SFONDO_PITCH-BUFFER_COLS*2,PuntaSfondoGr	; ANDIAMO A CAPO
	MOVEQ	#BUFFER_COLS-1,D1		; resetto il contatore delle colonne
	ADD.W	#(MAPPA_COLS-BUFFER_COLS)*2,A0
	IFNE	PROFILING
	; un campione per riga di tile: MAPPA_ROWS campioni, e fra due campioni
	; c'e' 1/24 del lavoro, quindi il pennello non puo' girare due volte
	; senza che se ne accorga. Preserva tutto, DBRA compreso.
	BSR.W	MisuraRicPassa
	ENDC
	DBRA	D2,.CicloTile
.FineMappa:

	MOVEM.L	(SP)+,D0-D6/A0-A2

	RTS

* BuildSkyCopper - genera il gradiente cielo dentro la copperlist
* Riempie SkyCopper con SKY_STEPS passi, uno per riga visibile, ricampionando
* SkyGradient sulle BG_VIS_ROWS righe: cosi' il gradiente resta INTERO qualunque
* sia CUT_BOTTOM_ROWS.
* Ogni passo: WAIT riga / BPLCON3 LOCT=1 / COLOR00 bassi / BPLCON3 LOCT=0 /
* COLOR00 alti; in coda un BPLCON3 per lasciare LOCT=0.
* IL RICAMPIONAMENTO E' L'IDENTITA', e non per caso: SkyGradient ha esattamente
* SKY_STEPS voci, una per riga, perche' il copper scrive un colore per riga.
* La tabella d'arte, che di voci ne ha 260, viene ridotta OFFLINE da
* tools/gen-cielo.py interpolando; farlo qui con la DIVU troncava e saltava voci
* intere, da cui le bande nella meta' alta del cielo.
* Il conto resta lo stesso: se BG_VIS_ROWS cambia senza rigenerare la tabella il
* cielo esce comunque intero invece di leggere fuori, e la guardia in fondo a
* CieloGrad.i lo segnala. L'indice e' i*SKY_SRC_ROWS/SKY_STEPS e non trabocca
* mai per costruzione. Gira una volta al boot: il costo non conta.
; Posizione dei bit BANK dentro BPLCON3: scelgono quale gruppo di 32 registri
; colore risponde a $180..$1BE. STA FUORI dal condizionale del cielo: e' una
; costante del chipset, e la usa anche la palette degli sprite. Dentro l'IFEQ
; sparirebbe insieme al gradiente portandosi via una cosa che non c'entra.
BPLCON3_BANK_SHIFT      EQU     13
; NOTTE_VOCI stava qui. E' salita accanto a TENDA_PASSAGGIO perche' da lei
; discende FADE_VOCI, che serve a ControllaPassaggio - e quello sta PRIMA di
; questa riga. Devpac valuta una EQU dove la incontra: definirla qui voleva
; dire un riferimento in avanti e un errore solo sull'Amiga.
	IFNE	CIELO_GRADIENTE
	IFEQ	PROFILING*PROF_KILL_SKY
; Una voce di SkylineTinte: base a 24 bit, peso del mix col cielo, bit BANK.
SKYLINE_OFS_BASE        EQU     0
SKYLINE_OFS_MIX         EQU     4
SKYLINE_OFS_BANCO       EQU     6
SKYLINE_TINTA_LEN       EQU     8

BuildSkyCopper:
	MOVEM.L	D0-D7/A0-A3,-(SP)
	LEA	SkyCopper,A1
	MOVEQ	#0,D0                   ; D0 = indice riga visibile
.skyrow:
	; --- indice nella tabella = D0 * SKY_SRC_ROWS / SKY_STEPS ---
	MOVE.W	D0,D1
	MULU	#SKY_SRC_ROWS,D1
	DIVU	#SKY_STEPS,D1
	AND.L	#$0000FFFF,D1           ; solo il quoziente
	LSL.W	#2,D1                   ; 4 byte per voce
	LEA	SkyGradient,A0
	ADDA.W	D1,A0

	; --- il colore del cielo di questa riga, a 24 bit, in D5 ---
	BSR.W	.leggicielo

	; --- WAIT sulla riga $2C + D0 ---
	MOVE.W	D0,D2
	ADD.W	#$2C,D2
	LSL.W	#8,D2
	OR.W	#$0001,D2               ; posizione orizzontale 0, bit0=1 = WAIT
	MOVE.W	D2,(A1)+
	MOVE.W	#$FFFE,(A1)+

	; --- IL CIELO PER PRIMO, banco 0 ---
	; L'ordine non e' estetico: se il blocco sforasse il color clock 64 il
	; danno cadrebbe sulle tinte e non sul cielo, e si vedrebbe subito dove.
	MOVE.L	D5,D4
	MOVEQ	#0,D1                   ; BANK = 0
	BSR.W	.emitcolore

	IFNE	SKYLINE_TINTE_MOBILI
	; --- poi le tinte della parallasse che hanno un mix diverso da zero ---
	; La tabella contiene SOLO quelle: le altre restano la costante scritta
	; da InitPalette8BPL e non costano una word.
	LEA	SkylineTinte,A2
	MOVEQ	#SKYLINE_TINTE_MOBILI-1,D7
.skytinta:
	BSR.W	.mixtinta               ; D4 = mix fra base e cielo di questa riga
	MOVE.W	SKYLINE_OFS_BANCO(A2),D1
	BSR.W	.emitcolore
	LEA	SKYLINE_TINTA_LEN(A2),A2
	DBRA	D7,.skytinta
	ENDC

	ADDQ.W	#1,D0
	CMP.W	#SKY_STEPS,D0
	BLT.W	.skyrow

	MOVE.W	#$0106,(A1)+            ; lascia BPLCON3 a BANK=0 / LOCT=0
	MOVE.W	#BPLCON3_LOCT0,(A1)+
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS

; .leggicielo - ricostruisce il colore a 24 bit di una voce di SkyGradient
;   IN:  A0 = voce (word 0 = nibble alti $0RGB, word 1 = nibble bassi $0rgb)
;   OUT: D5.l = $00RRGGBB
;   USA: D1, D2, D4, D6
.leggicielo:
	MOVE.W	(A0),D1                 ; nibble alti
	MOVE.W	2(A0),D2                ; nibble bassi
	MOVEQ	#0,D5
	; R
	MOVE.W	D1,D6
	LSR.W	#8,D6
	AND.W	#$000F,D6
	LSL.W	#4,D6
	MOVE.W	D2,D4
	LSR.W	#8,D4
	AND.W	#$000F,D4
	OR.W	D4,D6
	MOVE.W	D6,D5
	LSL.L	#8,D5
	; G
	MOVE.W	D1,D6
	LSR.W	#4,D6
	AND.W	#$000F,D6
	LSL.W	#4,D6
	MOVE.W	D2,D4
	LSR.W	#4,D4
	AND.W	#$000F,D4
	OR.W	D4,D6
	OR.W	D6,D5
	LSL.L	#8,D5
	; B
	MOVE.W	D1,D6
	AND.W	#$000F,D6
	LSL.W	#4,D6
	MOVE.W	D2,D4
	AND.W	#$000F,D4
	OR.W	D4,D6
	OR.W	D6,D5
	RTS

; .emitcolore - emette gli 8 word (4 MOVE) che scrivono un colore a 24 bit
;   IN:  D1.w = bit BANK di BPLCON3 gia' shiftati, D4.l = colore,
;        A1 = destinazione nella copperlist
;   OUT: A1 avanzata di 8 word
;   USA: D2, D6
; Bassi prima degli alti, come nella versione a solo cielo: nella voce di
; SkyGradient gli alti stanno per primi ma il copper li scrive per ultimi.
.emitcolore:
	MOVE.W	#$0106,(A1)+
	MOVE.W	D1,D2
	OR.W	#BPLCON3_LOCT1,D2       ; BANK | LOCT=1 | PF2OF | BRDRBLNK
	MOVE.W	D2,(A1)+
	MOVE.W	#$0180,(A1)+
	BSR.W	.nibblebassi
	MOVE.W	D6,(A1)+
	MOVE.W	#$0106,(A1)+
	MOVE.W	D1,D2
	OR.W	#BPLCON3_LOCT0,D2       ; BANK | LOCT=0 | PF2OF | BRDRBLNK
	MOVE.W	D2,(A1)+
	MOVE.W	#$0180,(A1)+
	BSR.W	.nibblealti
	MOVE.W	D6,(A1)+
	RTS

; .nibblealti / .nibblebassi - da $00RRGGBB alle due meta' che vuole l'AGA
;   IN: D4.l = $00RRGGBB   OUT: D6.w = $0RGB oppure $0rgb   USA: D2
.nibblealti:
	MOVE.L	D4,D6
	LSR.L	#4,D6
	AND.W	#$000F,D6               ; B alto
	MOVE.L	D4,D2
	LSR.L	#8,D2
	AND.W	#$00F0,D2               ; G alto << 4
	OR.W	D2,D6
	MOVE.L	D4,D2
	LSR.L	#8,D2
	LSR.L	#4,D2                   ; shift totale 12 (l'immediato arriva a 8)
	AND.W	#$0F00,D2               ; R alto << 8
	OR.W	D2,D6
	RTS

.nibblebassi:
	MOVE.W	D4,D6
	AND.W	#$000F,D6               ; B basso
	MOVE.W	D4,D2
	LSR.W	#4,D2
	AND.W	#$00F0,D2               ; G basso << 4
	OR.W	D2,D6
	MOVE.L	D4,D2
	LSR.L	#8,D2
	AND.W	#$0F00,D2               ; R basso << 8
	OR.W	D2,D6
	RTS

	IFNE	SKYLINE_TINTE_MOBILI
; .mixtinta - tinta = (base*(8-mix) + cielo*mix) / 8, canale per canale
;   IN:  A2 = voce di SkylineTinte, D5.l = cielo della riga
;   OUT: D4.l = $00RRGGBB
;   USA: D1, D2, D6, A3
.mixtinta:
	MOVEA.W	SKYLINE_OFS_MIX(A2),A3  ; A3 = mix, 0..8
	MOVEQ	#0,D4
	; R
	MOVE.L	SKYLINE_OFS_BASE(A2),D1
	LSR.L	#8,D1
	LSR.L	#8,D1
	AND.W	#$00FF,D1
	MOVE.L	D5,D2
	LSR.L	#8,D2
	LSR.L	#8,D2
	AND.W	#$00FF,D2
	BSR.W	.mixcanale
	MOVE.W	D1,D4
	LSL.L	#8,D4
	; G
	MOVE.L	SKYLINE_OFS_BASE(A2),D1
	LSR.L	#8,D1
	AND.W	#$00FF,D1
	MOVE.L	D5,D2
	LSR.L	#8,D2
	AND.W	#$00FF,D2
	BSR.W	.mixcanale
	OR.W	D1,D4
	LSL.L	#8,D4
	; B
	MOVE.L	SKYLINE_OFS_BASE(A2),D1
	AND.W	#$00FF,D1
	MOVE.L	D5,D2
	AND.W	#$00FF,D2
	BSR.W	.mixcanale
	OR.W	D1,D4
	RTS

; .mixcanale - un canale: D1 = (D1*(8-mix) + D2*mix) / 8
;   Il massimo e' 255*8 = 2040: la somma sta larga in un long.
;   IN/OUT: D1.w   IN: D2.w = cielo, A3 = mix   USA: D2, D6
.mixcanale:
	MOVE.W	A3,D6
	MULU	D6,D2                   ; cielo * mix
	MOVEQ	#8,D6
	SUB.W	A3,D6                   ; 8 - mix
	MULU	D6,D1                   ; base * (8-mix)
	ADD.L	D2,D1
	LSR.L	#3,D1                   ; / 8
	RTS

; Le tinte MOBILI: base a 24 bit, peso del mix col cielo, bit BANK del banco
; che le ospita. Una tinta col mix a zero non entra nella tabella, cosi' la
; lunghezza e' SKYLINE_TINTE_MOBILI voci per costruzione e il ciclo le percorre
; tutte senza sapere quali sono. I banchi dispari 3/5/7 sono i notturni e il
; copper non li tocca.
SkylineTinte:
	IFNE	SKYLINE_MIX_1
	dc.l	SKYLINE_C1_RGB
	dc.w	SKYLINE_MIX_1
	dc.w	2<<BPLCON3_BANK_SHIFT
	ENDC
	IFNE	SKYLINE_MIX_2
	dc.l	SKYLINE_C2_RGB
	dc.w	SKYLINE_MIX_2
	dc.w	4<<BPLCON3_BANK_SHIFT
	ENDC
	IFNE	SKYLINE_MIX_3
	dc.l	SKYLINE_C3_RGB
	dc.w	SKYLINE_MIX_3
	dc.w	6<<BPLCON3_BANK_SHIFT
	ENDC
	ENDC
	ENDC
	ENDC							; chiude IFNE CIELO_GRADIENTE
