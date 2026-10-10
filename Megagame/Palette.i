; Palette.i - Palette AGA, notte, dissolvenza, transizioni
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


* LoadAGAPalette256
*   Carica una palette AGA a 256 colori dal buffer title_pal (256 long
*   $00RRGGBB) nei registri COLOR00..COLOR31, attraverso le 8 banche di
*   BPLCON3. Per ogni banca esegue due pass:
*     - LOCT=0: scrive i nibble ALTI di ogni componente RGB
*     - LOCT=1: scrive i nibble BASSI
*   Al termine ripristina BPLCON3 = $0c00 (banca 0, LOCT=0).
LoadAGAPalette256:
	MOVEM.L	D0-D5/A0-A2/A6,-(SP)
	LEA		$DFF000,A6
	LEA		title_pal,A0			; sorgente: 256 long $00RRGGBB
	MOVE.W	#0,D4					; bank index 0..7
	MOVEQ	#8-1,D5
.bank_loop:
	MOVE.L	A0,A2					; salva inizio banca per il low pass

	; ----- HIGH NIBBLES PASS (LOCT=0) -----
	MOVE.W	D4,D0
	LSL.W	#5,D0
	LSL.W	#8,D0					; D0 = bank << 13
	OR.W	#BPLCON3_LOCT0,D0				; LOCT=0, BRDRBLNK=1
	MOVE.W	D0,$106(A6)				; BPLCON3
	LEA		$180(A6),A1				; COLOR00
	MOVEQ	#32-1,D1
.hi_loop:
	MOVE.L	(A0)+,D2				; D2 = $00RRGGBB
	MOVE.L	D2,D3
	LSR.L	#4,D3
	AND.W	#$000F,D3				; B high
	MOVE.L	D2,D0
	LSR.L	#8,D0
	AND.W	#$00F0,D0				; G high << 4
	OR.W	D0,D3
	MOVE.L	D2,D0
	LSR.L	#8,D0
	LSR.L	#4,D0					; shift totale 12 (immediato max 8)
	AND.W	#$0F00,D0				; R high << 8
	OR.W	D0,D3
	MOVE.W	D3,(A1)+				; COLORn
	DBRA	D1,.hi_loop

	; ----- LOW NIBBLES PASS (LOCT=1) -----
	MOVE.L	A2,A0					; rewind A0 a inizio banca
	MOVE.W	D4,D0
	LSL.W	#5,D0
	LSL.W	#8,D0
	OR.W	#BPLCON3_LOCT1,D0				; LOCT=1, BRDRBLNK=1
	MOVE.W	D0,$106(A6)
	LEA		$180(A6),A1
	MOVEQ	#32-1,D1
.lo_loop:
	MOVE.L	(A0)+,D2
	MOVE.W	D2,D3
	AND.W	#$000F,D3				; B low
	MOVE.W	D2,D0
	LSR.W	#4,D0
	AND.W	#$00F0,D0				; G low << 4
	OR.W	D0,D3
	MOVE.L	D2,D0
	LSR.L	#8,D0
	AND.W	#$0F00,D0				; R low << 8
	OR.W	D0,D3
	MOVE.W	D3,(A1)+
	DBRA	D1,.lo_loop

	ADDQ.W	#1,D4
	DBRA	D5,.bank_loop

	MOVE.W	#BPLCON3_BRDRBLNK,$106(A6)	; ripristina BPLCON3 (banca 0, LOCT=0, bordo NERO)
	MOVEM.L	(SP)+,D0-D5/A0-A2/A6
	RTS
* InitPalette8BPL
*   Lookup diretto a 8 bit sui sei piani: bit 0-4 sfondo (0..31), bit 5 dark
*   plane. Scrive UNA VOLTA a init il banco 1 (32..63) come META' del banco 0,
*   che e' lo sfondo notturno; il banco 0 lo carica la copperlist a ogni quadro.
*   I banchi 2..7 non ci sono piu': servivano a dare le tinte alla parallasse
*   quando stava nei bitplane, ed erano 192 voci. Adesso la parallasse e' sugli
*   sprite e le sue tinte sono dodici voci scritte dalla copperlist a 64..79.
*   Sorgente dei 32 colori base: i blocchi copper GamePalHi/GamePalLo.
*   CHIAMARE CON IL COPPER DMA SPENTO (scrive BPLCON3 a piu' riprese).
; Le tinte dello skyline (SKYLINE_C1/C2/C3_RGB) stanno nel blocco EQU del cielo,
; in testa al file: le legge anche BuildSkyCopper, che sta piu' su di qui.

InitPalette8BPL:
	MOVEM.L	D0-D7/A0-A2/A6,-(SP)
	LEA		$DFF000,A6

	; ----- ricostruisce i 32 colori base come long $00RRGGBB -----
	LEA		GamePalHi+2,A0			; +2 salta il numero di registro
	LEA		GamePalLo+2,A1
	LEA		GamePal24,A2
	MOVEQ	#32-1,D7
.mk24:
	MOVE.W	(A0),D0					; $0RGB (nibble alti)
	BSR.W	.spread					; D2 = $000R0G0B
	MOVE.L	D2,D3
	LSL.L	#4,D3					; nibble alti al loro posto
	MOVE.W	(A1),D0					; $0rgb (nibble bassi)
	BSR.W	.spread
	OR.L	D2,D3					; D3 = $00RRGGBB
	MOVE.L	D3,(A2)+
	ADDQ.L	#4,A0
	ADDQ.L	#4,A1
	DBRA	D7,.mk24

	; ----- banco 1 = meta' del banco 0 (sfondo notturno) -----
	LEA		GamePal24,A0
	LEA		GamePalBk,A1
	MOVEQ	#32-1,D7
.half1:
	MOVE.L	(A0)+,D0
	LSR.L	#1,D0
	AND.L	#$007F7F7F,D0
	MOVE.L	D0,(A1)+
	DBRA	D7,.half1
	; Qui stava `LEA GamePalBk,A0 / MOVEQ #1,D4 / BSR.W WriteAGABank32`, cioe'
	; il banco 1 scritto UNA VOLTA nei registri dalla CPU. Adesso lo riempie
	; nella copperlist BuildNotteCopper e lo riscrive il copper a ogni quadro:
	; il motivo sta su NOTTE_VOCI. GamePalBk resta la sorgente a 24 bit.
	BSR.W	BuildNotteCopper

	; I banchi 2..7 (colori 64..255) portavano le tre tinte della parallasse
	; combinate con lo sfondo: 192 voci per ottenere che la parallasse stesse
	; DIETRO alle tile. Con sei bitplane l'indice arriva a 63 e nessun pixel
	; puo' piu' selezionarle; la stessa cosa la fa BPLCON2, che costa un
	; registro invece di 192 voci. Le voci 64..79 le scrive il copper a ogni
	; quadro per gli sprite della parallasse.

	MOVE.W	#BPLCON3_LOCT0,$106(A6)			; BPLCON3 a riposo (banca 0, LOCT=0, BRDRBLNK)
	MOVEM.L	(SP)+,D0-D7/A0-A2/A6
	RTS

.spread:							; D0 = word $0RGB -> D2 = long $000R0G0B
	MOVEQ	#0,D2
	MOVE.W	D0,D2
	AND.W	#$0F00,D2
	LSL.L	#8,D2					; R -> bit 19-16
	MOVE.W	D0,D1
	AND.W	#$00F0,D1
	LSL.W	#4,D1					; G -> bit 11-8
	OR.W	D1,D2
	MOVE.W	D0,D1
	AND.W	#$000F,D1				; B -> bit 3-0
	OR.W	D1,D2
	RTS

* BuildNotteCopper - riempie il blocco copper del BANCO 1 (colori 32..63)
*   Scrive nei due spazi `NotteHi` e `NotteLo` della copperlist 32 coppie
*   (numero di registro, valore): i registri $0180..$01BE, i valori i nibble
*   alti e bassi delle voci di `GamePalBk`, che e' il banco 0 dimezzato.
*   Le due coppie di BPLCON3 che scelgono banco e LOCT sono letterali nella
*   lista e non passano da qui.
*
*   VA CHIAMATA COL COPPER SPENTO o comunque prima che la lista vada a video:
*   `ds.w` lascia zeri, e uno zero in una copperlist e' un MOVE su BLTDDAT -
*   innocuo, ma per un quadro il banco 1 sarebbe tutto nero. Al boot gira
*   dentro InitPalette8BPL, che sta nel blocco dove COPEN e' ancora spento.
*
*   L'estrazione dei nibble e' la stessa di LoadAGAPalette256 e di
*   WriteAGABank32, riga per riga: non e' una terza variante da controllare.
*   DISTRUGGE: nulla (salva tutto).
BuildNotteCopper:
	MOVEM.L	D0-D3/D7/A0-A2,-(SP)
	LEA		GamePalBk,A0			; 32 long $00RRGGBB, gia' dimezzati
	LEA		NotteHi,A1
	LEA		NotteLo,A2
	MOVE.W	#$0180,D3				; COLOR00 del banco: con BANK=1 e' la voce 32
	MOVEQ	#NOTTE_VOCI-1,D7
.voce:
	MOVE.L	(A0)+,D0				; D0 = $00RRGGBB
	MOVE.W	D3,(A1)+				; il registro, passata ALTA
	MOVE.W	D3,(A2)+				; e passata BASSA

	; ----- nibble ALTI: $0RGB preso dai bit 23-20, 15-12, 7-4 -----
	MOVE.L	D0,D2
	LSR.L	#4,D2
	AND.W	#$000F,D2				; B alto
	MOVE.L	D0,D1
	LSR.L	#8,D1
	AND.W	#$00F0,D1				; G alto, gia' in posizione 7-4
	OR.W	D1,D2
	MOVE.L	D0,D1
	LSR.L	#8,D1
	LSR.L	#4,D1					; shift totale 12: l'immediato arriva a 8
	AND.W	#$0F00,D1				; R alto in posizione 11-8
	OR.W	D1,D2
	MOVE.W	D2,(A1)+

	; ----- nibble BASSI: dai bit 19-16, 11-8, 3-0 -----
	MOVE.W	D0,D2
	AND.W	#$000F,D2				; B basso
	MOVE.W	D0,D1
	LSR.W	#4,D1
	AND.W	#$00F0,D1				; G basso
	OR.W	D1,D2
	MOVE.L	D0,D1
	LSR.L	#8,D1
	AND.W	#$0F00,D1				; R basso
	OR.W	D1,D2
	MOVE.W	D2,(A2)+

	ADDQ.W	#2,D3					; prossimo registro di colore
	DBRA	D7,.voce
	MOVEM.L	(SP)+,D0-D3/D7/A0-A2
	RTS

* BuildFadeTab - i livelli della dissolvenza, una volta al boot
*   Prima raccoglie in FadePal24 le 76 voci che il copper scrive - giorno,
*   notte, alberi - poi per ogni livello le scala e le spezza in nibble alti e
*   bassi. Il livello FADE_LIVELLI-1 riproduce la palette ESATTA (x15/15), non
*   una sua approssimazione: la dissolvenza in entrata finisce sui colori veri.
*   Il livello 0 e' nero pieno perche' la scala passa per zero.
*
*   VA CHIAMATA DOPO InitPalette8BPL, che e' chi riempie GamePal24 e GamePalBk.
*   DISTRUGGE: nulla (salva tutto).
BuildFadeTab:
	MOVEM.L	D0-D7/A0-A2,-(SP)

	; ----- 1. la sorgente: giorno, notte, alberi, in quest'ordine ----------
	LEA		FadePal24,A1
	LEA		GamePal24,A0
	MOVEQ	#FADE_VOCI_MONDO-1,D7
.cg:
	MOVE.L	(A0)+,(A1)+
	DBRA	D7,.cg
	LEA		GamePalBk,A0
	MOVEQ	#NOTTE_VOCI-1,D7
.cn:
	MOVE.L	(A0)+,(A1)+
	DBRA	D7,.cn
	LEA		AlberiPal24,A0
	MOVEQ	#FADE_VOCI_ALBERI-1,D7
.ca:
	MOVE.L	(A0)+,(A1)+
	DBRA	D7,.ca

	; ----- 2. un blocco di nibble alti + bassi per livello -----------------
	LEA		FadeTab,A1				; A1 = nibble ALTI del livello corrente
	MOVEQ	#0,D5					; D5 = livello
.livello:
	MOVEA.L	A1,A2
	ADDA.W	#FADE_VOCI*2,A2			; A2 = nibble BASSI dello stesso livello
	LEA		FadePal24,A0
	MOVEQ	#FADE_VOCI-1,D7
.voce:
	MOVE.L	(A0)+,D0				; D0 = $00RRGGBB a piena luce

	; Le tre componenti scalate a livello/(FADE_LIVELLI-1). La MULU scrive
	; tutti e 32 i bit, quindi si porta via da sola la word alta sporca che
	; l'estrazione di B lascia in giro: e' il motivo per cui non serve
	; ripulirla a mano.
	MOVE.L	D0,D1
	LSR.L	#8,D1
	LSR.L	#8,D1
	AND.W	#$00FF,D1				; R
	MULU.W	D5,D1
	DIVU.W	#FADE_LIVELLI-1,D1
	AND.W	#$00FF,D1				; il quoziente: il resto sta nella word alta

	MOVE.L	D0,D2
	LSR.L	#8,D2
	AND.W	#$00FF,D2				; G
	MULU.W	D5,D2
	DIVU.W	#FADE_LIVELLI-1,D2
	AND.W	#$00FF,D2

	MOVE.L	D0,D3
	AND.W	#$00FF,D3				; B
	MULU.W	D5,D3
	DIVU.W	#FADE_LIVELLI-1,D3
	AND.W	#$00FF,D3

	; nibble ALTI: $0RGB coi bit 7-4 di ogni componente
	MOVE.W	D1,D4
	LSR.W	#4,D4
	LSL.W	#8,D4					; R in 11-8
	MOVE.W	D2,D6
	AND.W	#$00F0,D6				; G e' gia' in 7-4
	OR.W	D6,D4
	MOVE.W	D3,D6
	LSR.W	#4,D6					; B in 3-0
	OR.W	D6,D4
	MOVE.W	D4,(A1)+

	; nibble BASSI: gli stessi con i bit 3-0
	MOVE.W	D1,D4
	AND.W	#$000F,D4
	LSL.W	#8,D4
	MOVE.W	D2,D6
	AND.W	#$000F,D6
	LSL.W	#4,D6
	OR.W	D6,D4
	MOVE.W	D3,D6
	AND.W	#$000F,D6
	OR.W	D6,D4
	MOVE.W	D4,(A2)+

	DBRA	D7,.voce
	MOVEA.L	A2,A1					; il livello dopo comincia dove finisce questo
	ADDQ.W	#1,D5
	CMP.W	#FADE_LIVELLI,D5
	BLT.W	.livello
	MOVEM.L	(SP)+,D0-D7/A0-A2
	RTS

* FadeApplica - scrive nella copperlist il livello D0.W
*   Sei passeggiate, una per blocco: coppie da 4 byte col valore a +2. Sono
*   FADE_VOCI*2 = 152 word, circa 1300 cicli, 0,02 quadri: non si misura.
*   Si scrive il DATO della copperlist e non $180(A6), per la stessa ragione di
*   BPLCON1 e BPLCON0 - un registro che il copper riscrive a ogni quadro, se lo
*   tocca la CPU, vale fino al quadro dopo e non oltre.
*   VA CHIAMATA dopo AspettaVBL: li' il copper ha gia' letto il blocco per
*   questo quadro e il nuovo valore vale dal prossimo, quindi non si vede mai
*   mezza palette.
*   DISTRUGGE: nulla (salva tutto).
FadeApplica:
	MOVEM.L	D0-D3/A0-A3,-(SP)
	MULU.W	#FADE_VOCI*4,D0			; byte per livello
	LEA		FadeTab,A0
	ADDA.L	D0,A0					; A0 = base del livello
	LEA		FadeDest,A1
	MOVEQ	#FADE_BLOCCHI-1,D3
.blocco:
	MOVEA.L	(A1)+,A2				; dove scrivere, nella copperlist
	MOVE.W	(A1)+,D1				; offset in WORD dentro il livello
	ADD.W	D1,D1					; -> byte
	MOVEA.L	A0,A3
	ADDA.W	D1,A3					; A3 = sorgente dentro il livello
	MOVE.W	(A1)+,D2				; quante voci
	SUBQ.W	#1,D2
.voce:
	MOVE.W	(A3)+,2(A2)				; il VALORE: +2 salta il numero di registro
	ADDQ.L	#4,A2
	DBRA	D2,.voce
	DBRA	D3,.blocco
	MOVEM.L	(SP)+,D0-D3/A0-A3
	RTS

* AggiornaTransizione - la macchina a stati della porta
*   Da chiamare UNA volta per quadro, dopo AspettaVBL. Quando TransFase e' 0
*   costa una TST e un RTS.
*
*   Fase 1 spegne un livello per volta fino al nero. Arrivata al nero fa il
*   lavoro - RicostruisciMondo, 44 quadri - e passa alla fase 3, che riaccende.
*   **Il lavoro sta DENTRO la fase, non fra due fasi**: cosi' il quadro nero e'
*   gia' a video quando comincia, e nessuno vede il mondo che si ridisegna.
*
*   Il livello 0 viene applicato DUE volte: una in coda allo spegnimento e una
*   subito prima del lavoro. Non e' una sbavatura, e' quello che garantisce che
*   il nero sia sullo schermo e non solo in tabella quando il blitter parte.
*
*   IL GIOCO NON SI FERMA durante le fasi 1 e 3, ed e' una semplificazione
*   dichiarata: il player continua a camminare e i nemici a muoversi mentre lo
*   schermo si spegne. Nessuno lo vede, e ControllaPassaggio non riscatta
*   perche' guarda TransFase. **Servira' un fermo il giorno che lo stato di
*   moto va conservato attraverso la porta**: fra lo scatto e la fase 2 passano
*   FADE_LIVELLI quadri, e in quei quadri la velocita' cambia - quindi il moto
*   andra' FOTOGRAFATO allo scatto, non riletto qui.
*
*   Il monitor del profiler resta leggibile: vive nel pannello, che ha una
*   palette sua e non sfuma.
*   DISTRUGGE: nulla (salva tutto). Richiede A6 = $DFF000 (lo vuole
*   RicostruisciMondo).
AggiornaTransizione:
	; L'uscita a vuoto e' scritta al ROVESCIO di proposito: con un `BEQ.S` alla
	; fine della routine il salto misurava +136 byte, cioe' fuori dai 127 di uno
	; spiazzamento corto. Saltare AVANTI di due istruzioni costa due byte e non
	; dipende da quanto cresce il corpo qui sotto.
	TST.B	TransFase
	BNE.S	.attiva
	RTS
.attiva:
	MOVEM.L	D0,-(SP)
	ADDQ.B	#1,TransRitmo
	CMP.B	#FADE_RITMO,TransRitmo
	BLO.S	.esce					; non e' ancora il quadro del livello dopo
	CLR.B	TransRitmo
	CMP.B	#1,TransFase
	BEQ.S	.spegne
	CMP.B	#3,TransFase
	BEQ.S	.accende
	BRA.S	.esce					; fase sconosciuta: non si inventa niente
.spegne:
	SUBQ.W	#1,TransLivello
	BGE.S	.mostra
	CLR.W	TransLivello			; il nero e' il livello 0, non il -1
	MOVEQ	#0,D0
	BSR.W	FadeApplica				; il nero A VIDEO, prima del lavoro
	BSR.W	EseguiPassaggio			; mappa nuova, player al bordo opposto
	MOVE.B	#3,TransFase
	BRA.S	.esce
.accende:
	ADDQ.W	#1,TransLivello
	CMP.W	#FADE_LIVELLI-1,TransLivello
	BLT.S	.mostra
	MOVE.W	#FADE_LIVELLI-1,TransLivello
	CLR.B	TransFase				; finita: palette piena e porta chiusa
.mostra:
	MOVE.W	TransLivello,D0
	BSR.W	FadeApplica
.esce:
	MOVEM.L	(SP)+,D0
	RTS

; .pair costruiva un banco [tinta skyline, sfondo 1..31] e la sua meta'
; notturna, ed era chiamata tre volte per i banchi 2..7. Rimossa il 5
; settembre insieme ai banchi che riempiva.

* WriteAGABank32
*   SENZA CHIAMANTI dal 25 settembre 2026: il banco 1 era il suo unico cliente
*   e adesso lo scrive il copper (vedi BuildNotteCopper). Resta perche' e' il
*   modo giusto di scrivere un banco dalla CPU e servira' al primo banco che
*   non stia in una lista; chi la trova sappia che oggi non gira.
*   Scrive 32 colori AGA nel banco D4 (0..7). A0 = 32 long $00RRGGBB.
*   Stessa meccanica hi/lo di LoadAGAPalette256, parametrizzata sul banco.
*   DISTRUGGE: D0-D3/A0-A2 (preserva D4). Richiede A6 = $DFF000.
WriteAGABank32:
	MOVE.L	A0,A2					; salva inizio blocco per il low pass

	; ----- HIGH NIBBLES PASS (LOCT=0) -----
	MOVE.W	D4,D0
	LSL.W	#5,D0
	LSL.W	#8,D0					; D0 = bank << 13
	OR.W	#BPLCON3_LOCT0,D0				; LOCT=0, BRDRBLNK=1
	MOVE.W	D0,$106(A6)				; BPLCON3
	LEA		$180(A6),A1				; COLOR00
	MOVEQ	#32-1,D1
.hi_loop:
	MOVE.L	(A0)+,D2				; D2 = $00RRGGBB
	MOVE.L	D2,D3
	LSR.L	#4,D3
	AND.W	#$000F,D3				; B high
	MOVE.L	D2,D0
	LSR.L	#8,D0
	AND.W	#$00F0,D0				; G high << 4
	OR.W	D0,D3
	MOVE.L	D2,D0
	LSR.L	#8,D0
	LSR.L	#4,D0					; shift totale 12 (immediato max 8)
	AND.W	#$0F00,D0				; R high << 8
	OR.W	D0,D3
	MOVE.W	D3,(A1)+				; COLORn
	DBRA	D1,.hi_loop

	; ----- LOW NIBBLES PASS (LOCT=1) -----
	MOVE.L	A2,A0					; rewind A0 a inizio blocco
	MOVE.W	D4,D0
	LSL.W	#5,D0
	LSL.W	#8,D0
	OR.W	#BPLCON3_LOCT1,D0				; LOCT=1, BRDRBLNK=1
	MOVE.W	D0,$106(A6)
	LEA		$180(A6),A1
	MOVEQ	#32-1,D1
.lo_loop:
	MOVE.L	(A0)+,D2
	MOVE.W	D2,D3
	AND.W	#$000F,D3				; B low
	MOVE.W	D2,D0
	LSR.W	#4,D0
	AND.W	#$00F0,D0				; G low << 4
	OR.W	D0,D3
	MOVE.L	D2,D0
	LSR.L	#8,D0
	AND.W	#$0F00,D0				; R low << 8
	OR.W	D0,D3
	MOVE.W	D3,(A1)+
	DBRA	D1,.lo_loop
	RTS

	EVEN
GamePal24:
	ds.l	32						; 32 colori base ricostruiti a init
GamePalBk:
	ds.l	32						; scratch per costruire ogni banco

; ----- LA DISSOLVENZA: sorgenti e tabella dei livelli ------------------------
; FadePal24 e' la palette PIENA a 24 bit nell'ordine in cui la scrive il fade:
; 32 voci di giorno, 32 di notte, 12 di alberi. La riempie BuildFadeTab da
; GamePal24, GamePalBk e AlberiPal24, cioe' si DERIVA dalle stesse fonti che
; usano la copperlist e InitPalette8BPL. Ritoccare un colore domani non chiede
; di ricordarsi della dissolvenza.
FadePal24:
	ds.l	FADE_VOCI
; Per ogni livello: FADE_VOCI word di nibble ALTI e poi FADE_VOCI word di
; nibble BASSI. Un livello e' FADE_VOCI*4 byte, la tabella FADE_LIVELLI volte
; tanto - con 16 livelli e 76 voci sono 4864 byte di memoria pubblica.
FadeTab:
	ds.w	FADE_LIVELLI*FADE_VOCI*2

; Le dodici tinte degli alberi a 24 bit, NELL'ORDINE in cui le scrive la
; copperlist: due coppie di canali vicini e due lontane, cioe' le sei tinte
; vere ripetute. I valori non sono ricopiati, sono le stesse EQU di
; AlberiPalHi/AlberiPalLo.
AlberiPal24:
	dc.l	ALBERI_V_OMBRA_RGB,ALBERI_V_CORPO_RGB,ALBERI_V_LUCE_RGB
	dc.l	ALBERI_V_OMBRA_RGB,ALBERI_V_CORPO_RGB,ALBERI_V_LUCE_RGB
	dc.l	ALBERI_L_OMBRA_RGB,ALBERI_L_CORPO_RGB,ALBERI_L_LUCE_RGB
	dc.l	ALBERI_L_OMBRA_RGB,ALBERI_L_CORPO_RGB,ALBERI_L_LUCE_RGB
AlberiPal24Fine:
	IFNE	(AlberiPal24Fine-AlberiPal24)/4-FADE_VOCI_ALBERI
GUARDIA_ALBERI_24	EQU		1/0
	ENDC

; Dove va scritto ogni pezzo di un livello: indirizzo nella copperlist, offset
; in WORD dentro il livello, quante voci. I sei blocchi coprono esattamente le
; FADE_VOCI*2 word di un livello, e l'ordine e' alti-alti-alti / bassi-bassi-bassi
; perche' e' cosi' che la tabella e' disposta.
FadeDest:
	dc.l	GamePalHi
	dc.w	0,FADE_VOCI_MONDO
	dc.l	NotteHi
	dc.w	FADE_VOCI_MONDO,NOTTE_VOCI
	dc.l	AlberiPalHi
	dc.w	FADE_VOCI_MONDO+NOTTE_VOCI,FADE_VOCI_ALBERI
	dc.l	GamePalLo
	dc.w	FADE_VOCI,FADE_VOCI_MONDO
	dc.l	NotteLo
	dc.w	FADE_VOCI+FADE_VOCI_MONDO,NOTTE_VOCI
	dc.l	AlberiPalLo
	dc.w	FADE_VOCI+FADE_VOCI_MONDO+NOTTE_VOCI,FADE_VOCI_ALBERI
FadeDestFine:
	IFNE	(FadeDestFine-FadeDest)/8-FADE_BLOCCHI
GUARDIA_FADE_DEST	EQU		1/0
	ENDC

; Lo stato della transizione. Descrive un sottosistema unico - non esiste una
; seconda porta che si apra insieme a questa - quindi resta globale e non va
; nella struct bob_*.
TransFase:		dc.b	0			; 0 niente, 1 spegne, 2 lavoro, 3 accende
TransRitmo:		dc.b	0			; quadri contati dentro il livello corrente
		even
TransLivello:	dc.w	FADE_LIVELLI-1	; livello corrente: si parte da palette piena
; Il passaggio deciso allo scatto e lo stato di moto FOTOGRAFATO in quel
; momento. Non si rileggono dal player alla fase 2: fra lo scatto e il nero
; passano FADE_LIVELLI quadri e in quelli il gioco continua a girare.
TransDest:		dc.w	0			; il blocco di destinazione
TransVerso:		dc.w	0			; VERSO_SX / DX / SU / GIU: il bordo attraversato
; ENTRAMBE le coordinate, sempre. Quale sopravvive lo decide il verso, in un
; posto solo (EseguiPassaggio): fotografarne una sola vorrebbe dire ripetere
; quella scelta anche qui.
TransX:			dc.w	0
TransY:			dc.w	0
TransVelY:		dc.w	0			; il salto e la caduta proseguono di la'
TransFracY:		dc.w	0
TransSuolo:		dc.w	0

