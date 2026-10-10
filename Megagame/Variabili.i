; Variabili.i - Variabili CPU (sezione DATI)
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


; ---- Il droide della schermata del titolo ----
; Sta qui e non in chip per il criterio del progetto: **conta chi legge**. Il
; blitter legge l'arte (Droide/DroideMask, che infatti stanno in ChipStuff) e
; il buffer di lavoro; questi sono numeri che tocca solo la CPU.
DroideX:		dc.w	0		; angolo alto-sinistra, coordinate schermo
DroideY:		dc.w	0
; La posizione del quadro PRECEDENTE, cioe' il rettangolo da ripulire. Vale
; -1 finche' non si e' disegnato niente: al primo giro non c'e' scia da
; togliere, e ripulire un rettangolo mai sporcato copierebbe comunque 24 righe
; per otto piani da un punto qualsiasi.
DroidePrecX:	dc.w	-1
DroidePrecY:	dc.w	0
DroideFase:		dc.w	0		; accumulatore del percorso, vedi DROIDE_FASE_*
DroidePosa:		dc.w	0		; 0..DROIDE_POSE-1
DroideCont:		dc.w	0		; quadri passati sulla posa corrente

; ---- L'alba dell'intro (il codice sta in Intro.i) ----
; Un numero solo: a che punto e' l'alba. Sopra ALBA_QUADRI-1 si ferma e resta
; sul giorno pieno, cosi' chi tiene premuto il tasto non blocca l'immagine su
; una posa intermedia.
AlbaQuadro:		dc.w	0
	EVEN
; Tabella di seno, SENO_VOCI voci, valore = seno*256 (quindi -256..+256).
; Si usa cosi': MULS ampiezza, poi ASR #SENO_SCALA. Le voci sono una potenza di
; due perche' l'indice si prende con un AND invece che con una divisione, che
; sul 68000 costa 140 cicli e qui non servirebbe a niente.
TabSeno:
	dc.w	0,25,50,74,98,121,142,162
	dc.w	181,198,213,226,237,245,251,255
	dc.w	256,255,251,245,237,226,213,198
	dc.w	181,162,142,121,98,74,50,25
	dc.w	0,-25,-50,-74,-98,-121,-142,-162
	dc.w	-181,-198,-213,-226,-237,-245,-251,-255
	dc.w	-256,-255,-251,-245,-237,-226,-213,-198
	dc.w	-181,-162,-142,-121,-98,-74,-50,-25
TabSenoFine:
	IFNE	(TabSenoFine-TabSeno)/2-SENO_VOCI
ERRORE_TABSENO_VOCI_DIVERSE_DALLA_EQU	EQU		1/0
	ENDC

; ---- Variabili del profiling harness (vedi EQU PROFILING in testa) ----
; Sempre presenti anche con PROFILING=0: 8 byte, e cosi' restano
; ispezionabili dal debugger senza ricompilare con guardie condizionali.
; Righe consumate da QUESTO frame. NON e' limitata a RASTER_LINES-1: sui
; frame misurati davvero FineLavoro la riscrive con la durata ricostruita
; dai wrap, e un frame che ha sforato vale di piu' di un giro di raster.
; E' proprio quel confronto a contare i frame persi.
FrameLines:		dc.w	0       ; righe consumate da QUESTO frame
WorstReset:		dc.w	0       ; scrivici 1 (debugger) per azzerare i worst
ProfShow:		dc.b	0       ; 1 = numeri a schermo + misura congelata (tasto P)
ProfPanRipara:	dc.b	0       ; 1 = P appena spento, il pannello va ricucito
ProfKeyPrev:	dc.b	0       ; stato precedente del tasto P (edge detect)
ResetKeyPrev:	dc.b	0       ; stato precedente del tasto R (edge detect)
AutoKeyPrev:	dc.b	0       ; stato precedente del tasto 6 (edge detect)
AutoScrollOn:	dc.b	0       ; 1 = la camera cammina da sola (tasto 6)
	EVEN
AutoScrollCnt:	dc.w	0       ; contatore quadri dello scroll automatico

; Profilo per fase. Indici = PH_xxx (vedi le EQU in testa al file).
;   ProfRaw   = riga di inizio di ogni fase in questo frame, normalizzata
;               rispetto al sync (0 = riga VBL_SYNC_LINE)
;   ProfWorst = peggior COSTO di ogni fase, sticky. E' l'array da guardare.
; NB: la somma dei ProfWorst non e' il worst totale — i picchi delle singole
; fasi non cadono nello stesso frame.
PathBCamX:      dc.w	0       ; camera EFFETTIVA usata dal display in Path B
PathBCamY:      dc.w    0       ;   (la scrive ScrollPathB, la legge MostraProfilo)
; --- doppio buffer del mondo ---
; Al boot si visualizza A e si disegna in B. Scambiati in coda al blocco.
WorldShow:		dc.l	SFONDOGRANDE     ; buffer attualmente a video
WorldDraw:		dc.l	SFONDOGRANDE_B   ; buffer in cui si sta disegnando

; Valori calcolati presto da ScrollPathBCalc e applicati in coda da Apply.
WorldPtrOfs:	dc.l	0                ; offset camera nel buffer, da ScrollHWCalc
WorldBplCon1:	dc.w	0                ; valore BPLCON1 dello stesso frame

; --- rettangoli sporchi: UN SET PER BUFFER ---
; Ogni buffer va ripulito da cio' che ci si e' disegnato l'ultima volta che
; toccava a lui, cioe' DUE blocchi fa: quindi servono due liste, scambiate
; insieme ai buffer. Si memorizza l'OFFSET dall'inizio del buffer e non
; l'indirizzo assoluto, cosi' il ripristino e' master+ofs -> buffer+ofs e non
; dipende da quale dei due si sta usando.
        RSRESET
dirty_Count		rs.w	1
dirty_Pad		rs.w	1                ; allineamento per il campo long
dirty_Ofs		rs.l	PATHB_DIRTY_MAX
dirty_Rows		rs.w	PATHB_DIRTY_MAX
; LARGHEZZA PER VOCE. Prima il restore usava BOB_BLIT_W fisso per tutti i
; rettangoli: andava bene finche' ogni BOB era largo 32 px, ma la pietra e'
; larga 16 e verrebbe ripulita su una larghezza sbagliata (scia a destra, o
; sfondo adiacente riscritto). Ora ogni voce porta la propria larghezza.
dirty_Width		rs.w	PATHB_DIRTY_MAX
DIRTY_SET_SIZE	rs.b	0

DirtySetA:		ds.b	DIRTY_SET_SIZE
DirtySetB:		ds.b	DIRTY_SET_SIZE
CurDirty:       dc.l	DirtySetB        ; set del buffer in cui si disegna (B al boot)
PathBDelay:		dc.w	0       ; ritardo BPLCON1 del frame, lo scrive ScrollHWCalc: darkplane e
                                ;   parallasse lo usano per compensare

; Appunti di lavoro della misura della ricostruzione. Stanno QUI, PRIMA di
; ProfRaw, e non in coda alle due voci nuove: in coda finirebbero dentro il
; blocco consecutivo il giorno che qualcuno alza PROF_VALUES, e il profiler
; stamperebbe un TOD al posto di una misura.
MisuraRicTOD0:  dc.w    0       ; TOD del CIA-A all'inizio della sequenza
MisuraRicRiga:  dc.w    0       ; ultima riga raster campionata
MisuraRicAttiva: dc.b   0       ; 1 fra Avvia e Chiudi: fuori, Passa non fa niente
        even

ProfRaw:		ds.w    PROF_SLOTS
ProfWorst:		ds.w    PROF_SLOTS

; ATTENZIONE ALL'ORDINE: questi due DEVONO restare subito dopo ProfWorst.
; MostraProfilo li stampa con lo stesso loop, leggendo PROF_SLOTS+2 word
; consecutive a partire da ProfWorst.
WorstLines:     dc.w    0       ; peggior caso mai visto - high-water, sticky
                                ;   <-- QUESTO e' il numero che conta:
                                ;   margine residuo = 312 - WorstLines
DropCount:      dc.w    0       ; frame persi dall'ultimo reset

; DF = DDFSTRT come lo scrive davvero il copper. NON si puo' leggere il
; registro (e' write-only), quindi si legge il valore dentro la copperlist,
; che e' esattamente cio' che il chip riceve a ogni frame.
; Atteso $18 = 24 se PathBInit ha patchato il prefetch anticipato;
; se resta $38 = 56 la patch non e' arrivata e la finestra parte 8 byte
; prima del dovuto (= 64 px di sfasamento a sinistra).
; DEVE restare subito dopo DropCount: MostraProfilo legge PROF_VALUES word
; consecutive a partire da ProfWorst.
ProfDdf:        dc.w    0       ; DDFSTRT letto dalla copperlist

; SW = riga raster in cui SwapParBuffers pubblica BPL7/8PT nella copperlist.
; Serve a sapere se arriva PRIMA o DOPO che il copper abbia letto quelle entry
; (le legge nelle primissime righe del quadro, la copperlist comincia li').
; Se SW e' alto (dentro il display) il puntatore vale dal frame DOPO, mentre
; BPLCON1 — scritto da ScrollPathB nel blank — vale da subito: e' quello
; sfasamento a produrre il frame corrotto quando il ritardo cambia di scatto.
; DEVE restare subito dopo ProfDdf: MostraProfilo legge word consecutive.
ProfSwapRaster: dc.w    0       ; SW: righe dopo il sync alla pubblicazione (high-water)

; DL = PathBDelay, cioe' il ritardo BPLCON1 di questo frame (0..blocco-1:
; 0..63 col fetch a 64 bit, 0..31 a 32. Lo scrive ScrollHWCalc).
; PO = offset della parallasse dentro la striscia.
; Servono a leggere la scena INSIEME ai numeri che la producono: la striscia
; vuota a sinistra compare solo a ritardo grande, e senza sapere quanto vale
; DL nel momento dello screenshot ogni misura e' ambigua.
; DEVONO restare consecutive dopo ProfSwapRaster: MostraProfilo legge word di
; seguito a partire da ProfWorst.
ProfDelay:      dc.w    0       ; DL: ritardo BPLCON1 del frame
ProfParOfs:     dc.w    0       ; PO: offset della parallasse

; RQ e RV = quanto costa RICOSTRUIRE IL MONDO, in quadri, misurato per due
; strade indipendenti. Ultime due del blocco consecutivo che legge
; MostraProfilo: chi ne aggiunge altre le mette QUI SOTTO e alza PROF_VALUES.
ProfRicTOD:     dc.w    0       ; RQ: quadri contati dal TOD del CIA-A
ProfRicVPOS:    dc.w    0       ; RV: quadri contati dai giri del pennello
ProfMappa:      dc.w    0       ; MP: il blocco corrente (MappaCorrente)
ProfFineBlocco:                 ; <-- IL BLOCCO FINISCE QUI, e adesso lo dice
                                ;     una guardia invece di un commento.

; L'invariante "MostraProfilo legge PROF_VALUES word consecutive a partire da
; ProfWorst" era affidato a quattro commenti sparsi. Adesso e' un errore di
; assemblaggio: chi aggiunge una voce senza alzare PROF_VALUES, o chi infila
; una variabile di lavoro in mezzo al blocco, non arriva a schermo.
	IFNE	(ProfFineBlocco-ProfWorst)/2-PROF_VALUES
GUARDIA_PROF_BLOCCO EQU 1/0
	ENDC

; Dark plane (6° bitplane EHB). Il valore iniziale non conta: PathBInit lo
; riscrive prima di qualunque lettura.
CurrentDarkDraw:
	dc.l	0

* TileFlags
*   Tabella delle proprieta' delle tile, indicizzata dal numero di tile.
*   bit 0 (TF_BLOCK) = 1 -> tile bloccata (non calpestabile)
*   In futuro si possono aggiungere altri flag (TF_DAMAGE, TF_WATER, ecc).
*   Per ora: tile 1 = libera, tutte le altre bloccate.
*   NON si estende piu' a mano quando la mappa cresce: e' LUNGA QUANTO IL
*   FOGLIO DELLE TILE, e mappa.py rifiuta un numero fuori da 0..FOGLIO_TILE_N-1.
*   Cosi' IsTileBlocked non puo' piu' leggere oltre la fine, che e' il difetto
*   che si e' ripresentato tre volte (tile 43, poi 51..77, poi 78..92) e che
*   ogni volta faceva leggere come flag il byte che segue la tabella - il
*   padding, e poi i dati dell'incbin della mappa.
TF_BLOCK        EQU     1

; La forma del foglio delle tile. FOGLIO_TILE_COLS e' la DIVU #20 di DisegnaSfondo:
; se un giorno il foglio cambia forma cambiano tutte e due, e la guardia accanto
; all'incbin di Tiles.raw (GUARDIA_TILES_RAW) confronta questi numeri con la
; lunghezza VERA del file. Stanno qui e non accanto all'incbin perche' Devpac
; valuta una EQU dove la incontra e TileFlags le usa subito sotto.
; E NON SI CHIAMANO TILE_*: quel prefisso e' RISERVATO AI MARCATORI. Prende
; come segnaposto OGNI EQU TILE_* con valore 0..319 (vedi segnaposto() in
; tools/mappa.py), quindi una costante chiamata TILE_RIGHE si sarebbe
; trasformata nel marcatore della tile 16 - che nella mappa di oggi compare 27
; volte. Provato e visto: vanno chiamate FOGLIO_*.
FOGLIO_TILE_COLS    EQU     20              ; tile per riga nel foglio
FOGLIO_TILE_RIGHE   EQU     16              ; righe di tile nel foglio
FOGLIO_TILE_N       EQU     FOGLIO_TILE_COLS*FOGLIO_TILE_RIGHE
FOGLIO_TILE_BYTE    EQU     16*2*5          ; una tile: 16 righe x 1 word x 5 piani

TileFlags:
;   tile:   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
	dc.b	0,	0,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	0,	0,	0,	0
;   tile:  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30  31
	dc.b	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;   tile:  32  33  34  35  36  37  38  39  40  41  42  43  44  45  46  47
	dc.b	1,	1,	1,	1,	1,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
;   tile:  48  49  50  51  52  53  54  55  56  57  58  59  60  61  62  63
	dc.b	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0
; QUI C'ERA SCRITTO che da 64 in su stavano i SEGNAPOSTO e che erano tutti
; calpestabili perche' ci si entra sopra. NON E' PIU' VERO dal 22 settembre
; 2026: la mappa usa 64..92 come arte normale, e il 64 stesso compare due
; volte, una come partenza a (27,17) e una come tile della torre a (62,17).
; TrovaPartenza prende la prima in ordine di lettura, quindi il gioco parte
; giusto, ma LA FASCIA DEI MARCATORI NON ESISTE PIU': un marcatore nuovo va
; messo dove l'arte non arrivera' mai, non in coda a quella che c'e'.
;   tile:  64  65  66  67  68  69  70  71  72  73  74  75  76  77  78  79
	dc.b	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	1,	1
; 80..92 sono il pezzo di mappa del 22 settembre (il blocco 3x5 in cima alle
; colonne 41..43). Tutte a zero perche' nessuno ha ancora deciso quali sono
; muro: come le 51..63, si alzano una alla volta guardando la sagoma.
;   tile:  80  81  82  83  84  85  86  87  88  89  90  91  92  93  94  95
	dc.b	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1
; 96..111 scritte in chiaro il 3 ottobre 2026. NON cambia niente per
; IsTileBlocked - stavano gia' nel dcb.b qui sotto, a zero, e la tabella e' lunga
; quanto il foglio da sempre. Sono qui perche' mappa2, mappa3 e mappa4 usano
; 93..104 e un valore si alza solo se lo si vede: dentro il dcb.b non c'e' una
; riga da modificare. Tutte a zero, cioe' CALPESTABILI, che e' la posizione da
; cui si parte - si alzano una alla volta guardando la sagoma, come le 51..63 e
; le 80..92. Chi sono le piu' frequenti NON si scrive qui: invecchia a ogni
; modifica delle mappe, e un commento vecchio in questo sorgente e' gia' costato
; giorni. Lo dice `py tools\mappa.py --mappa N`, che per ogni mappa stampa
; quante volte compare ogni tile.
;   tile:  96  97  98  99 100 101 102 103 104 105 106 107 108 109 110 111
	dc.b	1,	1,	1,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	0,	1
; 112..127 scritte in chiaro il 4 ottobre 2026, stesso motivo delle 96..111:
; mappa2 arriva alla 119 e mappa3 alla 118. Tutte a zero, cioe' calpestabili.
;   tile: 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127
	dc.b	1,	1,	1,	1,	1,	1,	1,	1,	0,	0,	0,	0,	0,	0,	0,	0
; E il resto del foglio, libero finche' non lo si disegna. Non e' spreco di 192
; byte di fast: e' la CHIUSURA DELLA CLASSE. Con la tabella lunga quanto il
; foglio, disegnare una tile nuova non puo' piu' far leggere IsTileBlocked
; oltre la fine, e non c'e' piu' niente da ricordarsi di allungare.
	dcb.b	FOGLIO_TILE_N-128,0
TileFlagsFine:
	IFNE	(TileFlagsFine-TileFlags)-FOGLIO_TILE_N
GUARDIA_TILEFLAGS	EQU		1/0
	ENDC

	even	; padding per allineamento word

* LA MAPPA, che e' un FILE e non piu' un blocco dc.w.
* La fonte e' risorse/mappa1.txt (un numero per tile, si modifica a mano);
* tools/mappa.py ne fa questo .raw, l'anteprima montata con le tile vere e la
* sagoma delle collisioni. Il formato e' banale: MAPPA_ROWS righe da
* MAPPA_COLS word, big-endian, in ordine di lettura.
* LA GUARDIA NON E' UN ORNAMENTO: MAPPA_COLS e MAPPA_ROWS sono due numeri
* ricopiati a mano che descrivono un file, ed e' esattamente il caso che la
* regola 5 del progetto vuole protetto. Se il .raw non ha la dimensione che
* discende da quei due numeri, GUARDIA_MAPPA_RAW ferma l'assemblaggio; senza,
* si leggerebbe oltre la fine in silenzio.
* DAL 26 SETTEMBRE 2026 LE MAPPE SONO PIU' DI UNA, e tutte con la STESSA
* geometria: MAPPA_COLS x MAPPA_ROWS. Non e' una comodita', e' un vincolo -
* da quei due numeri discendono il pitch del world buffer, SCROLL_OFS_MAX,
* PLAYER_MAX_X/Y e la dimensione dei tre buffer. Una mappa di forma diversa
* vorrebbe un altro buffer, non un altro file. La guardia per file lo impone.
MAPPA_ATTESA		EQU		MAPPA_COLS*MAPPA_ROWS*2

* L'ELENCO DEI BLOCCHI E I LORO COLLEGAMENTI SONO GENERATI, non scritti qui.
* La fonte e' `risorse/mappe.txt`, dove si scrivono per NOME, e il generatore e'
* `tools/mappe.py`. Il motivo non e' l'eleganza: i collegamenti portano dentro
* un invariante che nessun assemblatore puo' controllare - **se la destra di A
* e' B, la sinistra di B deve essere A** - e con i sedici blocchi che serviranno
* a coprire il rettangolone dell'originale sono sessantaquattro numeri. Il
* generatore si rifiuta di scrivere Mappe.i se la reciprocita' non torna, e
* controlla anche che ogni .raw esista e sia della misura giusta.
* Da Mappe.i arrivano: MAPPE_N, gli incbin MAPPAn con la loro guardia,
* MappaBase (i puntatori) e MappaLink (VERSI_N word per blocco).
* Dopo ogni modifica alla griglia:  py tools\mappe.py  e poi  py tools\porte.py
	include	"Mappe.i"

* LA MAPPA VIVA. E' l'unico posto che dice quale mappa si sta giocando: le
* cinque routine che leggono le tile (DisegnaSfondo, IsTileBlocked, TrovaFalo,
* TrovaPartenza, PathBBuildDark) partono da qui e non da un'etichetta fissa.
; Il puntatore che leggono le cinque routine della mappa. Nasce a ZERO e non a
; MAPPA1: il nome della prima mappa sta scritto in un posto solo, MappaBase, e
; qui ci arriva ImpostaBlocco al boot leggendo MappaCorrente. Se qualcuno legge
; la mappa prima di quella chiamata legge l'indirizzo 0 e si vede subito, che e'
; meglio di due nomi da tenere in pari a mano.
MappaPtr:		dc.l	0
; Il blocco da cui si parte. E' l'unica fonte: MappaPtr ne discende.
MappaCorrente:	dc.w	0


* VARIABILI
ScrllX:			dc.w	0		; Movimento orizzontale +-1
ScrllY:			dc.w	0		; Movimento verticale +-1
TileX:			dc.w	0
TileY:			dc.w	0
PixelOffX:		dc.w	0
PixelOffY:		dc.w	0
IntentX:		dc.w	0
IntentY:		dc.w	0

; --- Stato fisica platform ---
UpNow:			dc.w	0		; tasto SU/salto premuto in questo frame
UpPrev:			dc.w	0		; stato del tasto SU nel frame precedente (per il fronte)
GravityOn:		dc.w	1		; 1 = platform (gravita'), 0 = movimento 8 direzioni (toggle col tasto G)

; Risultato del clip verticale, calcolato in testa a DisegnaBOB e consumato
; piu' sotto nella stessa chiamata. NON le setta piu' nessun chiamante: prima
; erano l'interfaccia fra la routine di clip e quella di blit, che ora sono
; la stessa routine.
;   BobClipSkipRows: righe di sheet da saltare (clip in alto)
;   BobClipNumRows:  righe da blittare
;   BobDrawY:        Y SCHERMO da cui parte il disegno (0 se clippato in alto)
BobClipSkipRows:	dc.w	0
BobClipNumRows:		dc.w	16
BobDrawY:			dc.w	0

; Geometria dello sheet RICAVATA in testa a DisegnaBOB da bob_Larghezza,
; bob_Altezza, bob_Frames e bob_Bande. Sono appunti di lavoro validi solo
; per la durata di UNA chiamata, non stato del bob: stanno qui e non nella
; struct proprio perche' sono valori derivati, e la struct deve contenere
; una sola volta l'informazione. Le tre moltiplicazioni che li producono
; costano in tutto meno di una riga raster per frame.
BobGeoBlitW:	dc.w	0		; word lette/scritte dal blit per riga
BobGeoSlot:		dc.w	0		; byte di uno slot frame (arte + stacco)
BobGeoPitch:	dc.w	0		; byte per riga dello sheet
BobGeoPlane:	dc.l	0		; byte di un bitplane dello sheet

arrow_up:	dc.b 	0
arrow_dn:	dc.b 	0
arrow_sx:	dc.b 	0
arrow_rx:	dc.b 	0
key_space:	dc.b 	0			; 1 se SPACE premuta, 0 altrimenti
NightMode:	dc.b 	0			; 0 = giorno, 1 = notte (toggle col tasto N)
NightKeyPrev:	dc.b 	0			; stato precedente del tasto N (per edge detect)
MusicOn:		dc.b	0			; 0 = music off, 1 = music on (toggle col tasto M)
MusicKeyPrev:	dc.b	0			; stato precedente del tasto M (per edge detect)
MusicOnPrev:	dc.b	0			; ultimo valore "applicato" di MusicOn
GravKeyPrev:	dc.b	0			; stato precedente del tasto G (per edge detect)
QuadKeyPrev:	dc.b	0			; stato precedente del tasto Q (per edge detect)
SchermoKeyPrev:	dc.b	0			; stato precedente del tasto S (per edge detect)
SpieKeyPrev:	dc.b	0			; stato precedente del tasto L (per edge detect)
LetteraKeyPrev:	dc.b	0			; stato precedente del tasto A (per edge detect)

	EVEN
FaloAnimDelay:	dc.w	0			; contatore frame per animazione (incrementa ogni VBL)

	cnop	0,8

; ----- Stato proiettile -----
; Stato di CHI SPARA, non del proiettile: il proiettile vive tutto dentro
; BobPietra (bob_Active, bob_WorldX/Y, bob_Direzione, bob_TTL, bob_Speed,
; bob_Damage) e non ha piu' variabili proprie.
; Stato dell'INPUT, non di un'entita': resta qui.
FirePrev:		dc.w	0		; stato fire al frame precedente (per edge-detect)

	EVEN
; ----- SfxStructure per i 4 effetti sonori (passate a _mt_playfx) -----
; Layout (vedi ptplayer.i):
;   dc.l sfx_ptr   ; puntatore campione in CHIP RAM (etichetta in SpritesData)
;   dc.w sfx_len   ; lunghezza in WORD (= byte/2)
;   dc.w sfx_per   ; period Paula (vedi costanti SFX_PER_*)
;   dc.w sfx_vol   ; volume 0..64
;   dc.b sfx_cha   ; canale 0..3, oppure -1 = auto
;   dc.b sfx_pri   ; priorita' 1..127
SfxSparo:
	dc.l	SparoSample
	dc.w	SPARO_LEN			; (SparoSampleEnd-SparoSample)/2
	dc.w	SFX_PER_DEFAULT
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_SPARO

SfxPasso:
	dc.l	PassoSample
	dc.w	PASSO_LEN			; (PassoSampleEnd-PassoSample)/2
	dc.w	SFX_PER_PASSO
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_PASSO

SfxNemicoColpito:
	dc.l	NemicoColpitoSample
	dc.w	NEMICO_COLPITO_LEN
	dc.w	SFX_PER_NEMICO_COLPITO
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_HITENEMY

SfxHitPlayer:
	dc.l	HitPlayerSample
	dc.w	HITPLAYER_LEN 		; (HitPlayerSampleEnd-HitPlayerSample)/2
	dc.w	SFX_PER_DEFAULT
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_HITPLAYER

SfxNemicoMorto:
	dc.l	NemicoMortoSample
	dc.w	NEMICO_MORTO_LEN
	dc.w	SFX_PER_NEMICO_MORTO
	dc.w	SFX_VOL_DEFAULT
	dc.b	-1
	dc.b	SFX_PRI_DEATH

; Tabella di lookup direzione: 9 byte indicizzati da
; (ScrllY+1)*3 + (ScrllX+1).
; Ordine direzioni: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
; Valore 255 = nessun movimento (centro tabella).
DirLookupTable:
	dc.b	5, 6, 7			; ScrllY=-1: NW, N, NE
	dc.b	4, 255, 0		; ScrllY= 0: W, fermo, E
	dc.b	3, 2, 1			; ScrllY=+1: SW, S, SE
	even

PuntaSfondoGr:
	dc.l	SFONDOGRANDE

; L'offset della parallasse, per la voce PO del profiler. Prima era par_old,
; che serviva anche a saltare il blit quando l'offset non cambiava; di blit
; non ce ne sono piu', quindi resta solo il numero da guardare.
ParSprOfs:
	dc.w    0
; Il tempo del vento: avanza di uno a quadro, e VENTO_LENTO lo rallenta.
VentoT:
	dc.w    0
; bob
	rsreset
bob_X			rs.w	1		; coordinata X
bob_Y 			rs.w	1		; coordinata Y
bob_Speed 		rs.W	1		; velocità da 1 a 3
bob_Direzione	rs.W	1		; 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
bob_AnimFrame	rs.W	1		; 0..7: frame di animazione
bob_Stato		rs.W	1		; campo per lo stato del bob
; I due campi LONG stanno qui e non piu' in fondo: con bob_Stato davanti
; cadono a offset 12 e 16, cioe' allineati a 4 come l'inizio dell'array.
; Su 68020 un accesso .L a indirizzo pari ma non multiplo di 4 costa un ciclo
; di bus in piu'; e' poco, ma qui non costa niente ottenerlo.
bob_Gfx			rs.L	1		; puntatore alla grafica
bob_Mask		rs.L	1		; maschera per-frame di QUESTO sheet (canale A)
bob_Larghezza	rs.W	1		; larghezza del bob
bob_Altezza		rs.W	1		; larghezza del bob
bob_FrameCont	rs.W	1		; conteggio frame per cambio
bob_IsMoving	rs.W	1
bob_Active		rs.W	1		; 1=attivo (da renderizzare/aggiornare), 0=morto/inesistente
bob_AI 			rs.w	1		; 0=fermo; 1=fa la ronda; 2=in cacccia
bob_WorldX		rs.w	1		; coordinata X nel mondo (in pixel)
bob_WorldY		rs.w	1		; coordinata Y nel mondo (in pixel)
bob_PF			rs.w	1		; punti ferita correnti (0 = morto)
bob_Damage		rs.w	1		; danno che infligge al contatto
bob_Invuln		rs.w	1		; frame restanti di invulnerabilita' (0 = vulnerabile)
bob_InvulnMax	rs.w	1		; frame di invulnerabilita' impostati dopo un hit
; ---- GEOMETRIA DELLO SHEET ------------------------------------------------
; Prima DisegnaBOB aveva cablate le EQU OMINO_PITCH / BOB_SLOT_BYTES /
; PLANE_SIZE / OMINO_DIR_BANDA / BOB_BLIT_W: era generica sulla STRUTTURA ma
; non sulla GEOMETRIA, quindi disegnava solo sheet fatti come Omino32.
; Qui stanno SOLO i due numeri che non si possono dedurre da nient'altro:
; quanti fotogrammi ha una banda, e quante bande ha lo sheet. Tutto il resto
; DisegnaBOB se lo ricava da bob_Larghezza/bob_Altezza che c'erano gia':
;   blitW      = larghezza/16 + 1
;   slotBytes  = blitW * 2
;   sheetPitch = bob_Frames * slotBytes
;   dirBanda   = altezza * sheetPitch
;   planeSize  = dirBanda * bob_Bande
bob_Frames		rs.w	1		; fotogrammi per banda (potenza di 2: il wrap e' un AND)
bob_Bande		rs.w	1		; bande di direzione (1 = sheet senza direzioni)
; Ogni quanti frame avanza l'animazione. Era la EQU globale ANIM_DELAY, uguale
; per tutti: la prova che non bastava e' che il falo' ha sempre avuto la sua
; FaloAnimSpeed a parte, perche' non poteva usare lo stesso passo dell'omino.
bob_AnimDelay	rs.w	1		; frame fra un fotogramma e il successivo
; --- moto a velocita', in VIRGOLA FISSA 8.8 (256 = un pixel per frame) ---
; Serve alla parabola della pietra: una traiettoria curva non si puo' scrivere
; con un ottante e una velocita' scalare, perche' la verticale accelera mentre
; l'orizzontale resta costante. bob_Frac* accumula la parte sotto il pixel e la
; riversa in bob_World* quando arriva a uno intero. Chi non li usa li lascia a
; zero e non paga niente.
bob_VelX		rs.w	1		; velocita' orizzontale 8.8 (con segno)
bob_VelY		rs.w	1		; velocita' verticale 8.8 (negativa = su)
bob_FracX		rs.w	1		; frazione di pixel accumulata in X
bob_FracY		rs.w	1		; frazione di pixel accumulata in Y
; --- stato per-entita' che prima viveva in variabili globali del player ---
; Erano le variabili globali PlayerGrounded, GroundedPrev, PassoPrevX,
; PassoTimer, UltimaDirX e Bullet_Cooldown, piu' PlayerVelY e PlayerFracY che
; duplicavano bob_VelY e bob_FracY, campi gia' esistenti.
; Sono finiti qui applicando la regola: se una SECONDA entita'
; avesse bisogno dello stesso comportamento servirebbe una seconda copia della
; variabile, quindi e' stato dell'entita' e non del mondo. Oggi li riempie solo
; il player; il giorno che un nemico dovra' cadere, camminare rumorosamente o
; sparare, eredita tutto senza una riga di codice nuova.
bob_Grounded	rs.w	1		; 1 = piedi su tile solida (puo' saltare)
bob_GroundedPrev rs.w	1		; bob_Grounded al frame scorso: il fronte 0->1
	; e' l'atterraggio
bob_PrevX		rs.w	1		; bob_WorldX al frame scorso: il confronto dice
	; se si e' mosso DAVVERO
bob_PassoTimer	rs.w	1		; frame che mancano al prossimo passo
bob_UltimaDirX	rs.w	1		; ultima direzione orizzontale (+1 destra, -1 sx)
bob_Cooldown	rs.w	1		; frame che mancano prima di poter sparare
; Vita residua. Per la pietra sono i PIXEL di gittata che restano, non i
; frame: e' cosi' che si fa valere il tetto di PIETRA_RAGGIO. Per gli altri bob
; resta a zero e nessuno lo guarda.
bob_TTL			rs.w	1
bob_Length		rs.B	0		; dimensione della struttura

; VINCOLO: bob_Length deve restare multiplo di 4. I bob stanno in memoria
; contigua e il ciclo avanza di bob_Length per volta: se la struttura diventa
; dispari di 4, dal secondo bob in poi bob_Gfx e bob_Mask cadono disallineati.
; Aggiungendo campi si aggiungono in coppia, o si mette una word di riempimento.

EnemyInitTable:
;       WorldX, WorldY, Direzione, Active, AI, PF, Damage, InvulnMax
	dc.w	64,		208,	2,		1,		0,	3,	1,	30
	; nemico 0: basso a sinistra, fermo, recupero 30 frame
	dc.w	288,	16,		3,		1,		0,	8,	3,	60
	; nemico 1: alto a destra, fermo, recupero 60 frame (lento, e' un TANK)
	dc.w	96,		208,	2,		1,		1,	4,	2,	40
	; nemico 2: ronda Y, recupero 40 frame
	dc.w	304,	224,	4,		1,		1,	5,	2,	50
	; nemico 3: ronda X, recupero 50 frame
* DirectionDeltas
*   Tabella di delta (dx, dy) per ogni direzione, in unità di "Speed".
*   I valori sono normalizzati a -1, 0, +1 e poi moltiplicati per bob_Speed.
*   Indicizzata da bob_Direzione (0..7).
DirectionDeltas:
;       dx,  dy
	dc.w	 1,  0	; 0 = E
	dc.w	 1,  1	; 1 = SE
	dc.w	 0,  1	; 2 = S
	dc.w	-1,  1	; 3 = SW
	dc.w	-1,  0	; 4 = W
	dc.w	-1, -1	; 5 = NW
	dc.w	 0, -1	; 6 = N
	dc.w	 1, -1	; 7 = NE

	EVEN
; ----- Punteggio -----
; Tre valori, e sono tre cose diverse. Tenerli separati e' quello che permette
; alla rotella di salire a passi senza riscrivere il pannello a vuoto.
;   Punteggio           quello VERO, in punti. Lo alza il gioco, di colpo.
;   PunteggioMostrato   quello che la rotella sta mostrando, in SCALA
;                       ROTELLA_PASSI: conta fotogrammi, non punti, e un punto
;                       ne vale quattro. Insegue Punteggio*ROTELLA_PASSI di
;                       PUNTEGGIO_PASSO per frame. Parte da 0 perche' e' un
;                       numero che si vede davvero, non un segnaposto.
;   PunteggioDisegnato  l'ultimo valore SCRITTO nei bitplane, anche lui in
;                       scala. In scala e NON in punti: durante il rotolamento
;                       i punti stanno fermi per quattro frame mentre il
;                       fotogramma cambia, e confrontando i punti non si
;                       ridisegnerebbe niente. Parte da -1, che nessun
;                       punteggio puo' valere, cosi' il primo frame disegna di
;                       sicuro invece di credere che lo zero sia gia' a
;                       schermo.
Punteggio:			dc.l	0
PunteggioMostrato:	dc.l	0
PunteggioDisegnato:	dc.l	-1		; -1 = "mai disegnato", forza il primo giro

; ----- Indicatori di sinistra -----
; L'ENERGIA e' stato del MONDO, non di un'entita': ce n'e' una sola e nessuna
; seconda entita' potrebbe averne un'altra. Quindi globale, non in bob_*.
; Oggi non la muove nessuno: serve per il futuro, e intanto la barra la mostra.
; La VITA invece non ha una variabile sua: e' bob_PF del player, e leggerla di
; li' e' l'unico modo di non avere due numeri che possono scollarsi.
Energia:			dc.w	ENERGIA_MAX

	cnop	0,4
; Tabella degli indicatori: una riga per barra. Tutto quello che distingue una
; barra dall'altra sta QUI, e la routine e' una sola - la stessa scelta fatta
; per DisegnaBOBs. Aggiungere un terzo indicatore (il quadrante, le spie) e'
; una riga in piu' e nessun codice da toccare.
; ind_Livello / ind_Fase / ind_Ritmo sono stato PER BARRA: due barre ne vogliono
; due copie, quindi stanno nella riga e non fra le variabili globali.
; ind_Disegnato e' il fotogramma gia' scritto nei bitplane - livello e fase
; insieme, perche' durante una transizione il livello sta fermo mentre la fase
; cambia e confrontare il solo livello non ridisegnerebbe niente. Parte da -1,
; che nessun fotogramma puo' valere, cosi' il primo frame disegna di sicuro.
; I livelli partono da 0 anche se i valori partono pieni: al boot le due barre
; si riempiono da sole con la loro animazione di salita.
			rsreset
ind_Valore		rs.l	1		; puntatore alla word col valore corrente
ind_CopHi		rs.l	1		; blocco copper del colore, passata LOCT0
ind_CopLo		rs.l	1		;                            passata LOCT1
ind_Massimo		rs.w	1		; fondo scala del valore
ind_Y			rs.w	1		; riga del pannello a cui comincia il riquadro
ind_Livello		rs.w	1		; livello mostrato adesso, 0..INDIC_LIVELLI-1
ind_Fase		rs.w	1		; 0 = ferma, 1..3 sale, 4..8 scende
ind_Ritmo		rs.w	1		; frame che restano a questo fotogramma
ind_Disegnato	rs.w	1		; fotogramma gia' a schermo (-1 = nessuno)
ind_Length		rs.b	0

IndicTab:
	dc.l	Energia					; in ALTO: energia
	dc.l	IndicAltoHi
	dc.l	IndicAltoLo
	dc.w	ENERGIA_MAX
	dc.w	INDIC_ALTO_Y
	dc.w	0,0,0,-1

	dc.l	Player+bob_PF			; in BASSO: vita del player, letta dalla
	dc.l	IndicBassoHi			;   sua struct e non da una copia
	dc.l	IndicBassoLo
	dc.w	PLAYER_PF_MAX
	dc.w	INDIC_BASSO_Y
	dc.w	0,0,0,-1
IndicTabFine:
INDIC_QUANTI	EQU		(IndicTabFine-IndicTab)/ind_Length

	EVEN
; Rampa di colore della barra, una coppia (scura, viva) per livello.
; NON e' una scelta fatta qui: sono i colori MISURATI su
; risorse/grafica/indicatore_anteprima.png, che e' l'anteprima colorata
; dell'arte. Tre fasce, come le ha disegnate l'anteprima:
;   livelli 0..3   rosso    $c8203c / $ff6e82
;   livelli 4..6   arancio  $ee6a00 / $ffb870
;   livelli 7..10  giallo   $e4a800 / $ffe478
; La tabella ha una riga per livello e non tre righe con delle soglie: cosi'
; cambiare una fascia e' cambiare una riga, e non c'e' nessun confronto da
; tenere allineato al numero dei livelli.
IndicRampa:
	dc.w	$0c23,$0f68		; livello  0
	dc.w	$0c23,$0f68		; livello  1
	dc.w	$0c23,$0f68		; livello  2
	dc.w	$0c23,$0f68		; livello  3
	dc.w	$0e60,$0fb7		; livello  4
	dc.w	$0e60,$0fb7		; livello  5
	dc.w	$0e60,$0fb7		; livello  6
	dc.w	$0ea0,$0fe7		; livello  7
	dc.w	$0ea0,$0fe7		; livello  8
	dc.w	$0ea0,$0fe7		; livello  9
	dc.w	$0ea0,$0fe7		; livello 10
IndicRampaFine:

; STRUMENTI: schermo, spie, quadrante
; Le tre variabili di comando. Nel gioco non le scrive ancora nessuno: per
; provarle ci sono tre tasti, Q (lancetta), S (schermo), L (spie).
SchermoModo:		dc.w	0		; 0 = neve, 1..SCHERMO_IMMAGINI = immagine
SchermoFase:		dc.w	0
SchermoRitmo:		dc.w	0
SchermoDisegnato:	dc.w	-1		; nessun fotogramma puo' valere -1: il primo
	; quadro disegna di sicuro
SpieAccese:			dc.w	0		; un bit per spia, SPIE_TOT bit utili
LetteraDestra:		dc.w	'A'		; il carattere nel quadrato a destra
LetteraDisegnata:	dc.w	-1		; nessun codice puo' valere -1
ScrittaCar:			dc.w	0		; caratteri del messaggio (0 = nessuno)
ScrittaFine:		dc.w	0		; ScrittaCar*8: dove lo scorrimento si chiude
ScrittaOffset:		dc.w	0		; px gia' scorsi
QuadranteObiettivo:	dc.w	0		; indice in QuadPosizioni, 0..3
QuadranteAngolo:	dc.w	QUAD_POS_OVEST	; da dove parte, e non e' un numero
	; a caso: e' la posizione 0, quindi al
	; boot la lancetta sta gia' ferma li'
QuadranteRitmo:		dc.w	0
QuadranteDisegnato:	dc.w	-1

; Le quattro posizioni di riposo, nell'ordine in cui le gira il tasto Q.
QuadPosizioni:
	dc.w	QUAD_POS_OVEST
	dc.w	QUAD_POS_NORD
	dc.w	QUAD_POS_EST
	dc.w	QUAD_POS_SSE

; Tabella delle quattro spie. I due campi X e Y sono i PRIMI due e in
; quest'ordine perche' li legge anche ComponiSheet, che da li' prende il pezzo
; di pannello da mettere sotto alla cella: una sola copia delle posizioni.
; Le posizioni sono MISURATE sui buchi di Pannello.raw e le stampa
; tools/genera-strumenti.py a ogni giro, insieme al controllo che nessun pixel
; acceso finisca fuori dal nero.
			rsreset
spi_X			rs.w	1		; byte x nel pannello
spi_Y			rs.w	1		; riga y nel pannello
spi_Bit			rs.w	1		; maschera del bit di SpieAccese
spi_Fase		rs.w	1		; 0 = spenta, SPIA_FASI-1 = accesa a regime
spi_Ritmo		rs.w	1		; frame che restano a questo fotogramma
spi_Disegnato	rs.w	1		; fotogramma gia' nei bitplane (-1 = nessuno)
spi_Cella		rs.l	1		; primo byte della SUA cella (fase 0) nel SUO foglio
spi_PianoSz		rs.l	1		; byte di un piano di quel foglio
spi_Length		rs.b	0

; Le quattro gialle e la rossa stanno in due fogli diversi, montati con due
; mappe diverse, e la tabella e' una sola: la riga porta il foglio con se'.
; DisegnaSpie non sa niente di colori.
	cnop	0,4
SpieTab:
	dc.w	264/8,40,1,0,0,-1		; gialla, in alto a sinistra
	dc.l	SpiaSheet+0*SPIA_H*SPIA_ROWB,SPIA_PLANE_SZ
	dc.w	280/8,40,2,0,0,-1		; gialla, in alto a destra
	dc.l	SpiaSheet+1*SPIA_H*SPIA_ROWB,SPIA_PLANE_SZ
	dc.w	256/8,49,4,0,0,-1		; gialla, in basso a sinistra
	dc.l	SpiaSheet+2*SPIA_H*SPIA_ROWB,SPIA_PLANE_SZ
	dc.w	272/8,49,8,0,0,-1		; gialla, in basso a destra
	dc.l	SpiaSheet+3*SPIA_H*SPIA_ROWB,SPIA_PLANE_SZ
	dc.w	ROSSA_X/8,ROSSA_Y,16,0,0,-1	; ROSSA, nel cerchio sotto la lancetta
	dc.l	SpiaRossaSheet,ROSSA_PLANE_SZ
SpieTabFine:
	IFNE	(SpieTabFine-SpieTab)/spi_Length-SPIE_TOT
; Le righe della tabella sono le spie, e le spie sono le righe delle due
; griglie messe insieme. Se divergono, ComponiSheet monta lo sfondo sbagliato.
GUARDIA_SPIE_QUANTE	EQU		1/0
	ENDC

; MAPPA_TINTE - i dodici long che dicono a ComponiSheet quali tinte accendono
; quale piano. NON e' una tabella scritta a mano: esce dai tre INDICI di
; palette, un bit alla volta, quindi cambiando un indice si rifa' da sola.
;   \1 \2 \3 = indice di palette dei valori 1, 2 e 3 dell'arte
; Per ogni piano tre long: tutti uno se quel valore accende il piano, zero se no.
MAPPA_TINTE	MACRO
	dc.l	-((\1>>0)&1),-((\2>>0)&1),-((\3>>0)&1)
	dc.l	-((\1>>1)&1),-((\2>>1)&1),-((\3>>1)&1)
	dc.l	-((\1>>2)&1),-((\2>>2)&1),-((\3>>2)&1)
	dc.l	-((\1>>3)&1),-((\2>>3)&1),-((\3>>3)&1)
	ENDM

MappaGrigi:
	MAPPA_TINTE	STRUM_TINTA1,STRUM_TINTA2,STRUM_TINTA3
MappaGialli:
	MAPPA_TINTE	SPIA_TINTA1,SPIA_TINTA2,SPIA_TINTA3
MappaRossa:
	MAPPA_TINTE	ROSSA_TINTA1,ROSSA_TINTA2,ROSSA_TINTA3

; Posizioni fisse: schermo e quadrante hanno una sola cella nel pannello, la
; stessa per tutte le righe della griglia, quindi shd_PosPasso e' 0.
SchermoPos:
	dc.w	SCHERMO_X/8,SCHERMO_Y
QuadPos:
	dc.w	QUAD_X/8,QUAD_Y

; Tabella dei fogli da montare al boot: una riga per strumento, e la routine e'
; una sola. Stessa scelta di IndicTab e di DisegnaBOBs.
			rsreset
shd_Arte		rs.l	1		; striscia a 2 piani, come esce dall'editor
shd_Sheet		rs.l	1		; foglio a 4 piani da riempire
shd_Mappa		rs.l	1		; i dodici long di MAPPA_TINTE
shd_Pos			rs.l	1		; posizioni nel pannello, una per RIGA di celle
shd_PosPasso	rs.w	1		; byte fra una posizione e la successiva
shd_CellB		rs.w	1		; byte di una cella
shd_CellH		rs.w	1		; righe di una cella
shd_Colonne		rs.w	1
shd_Righe		rs.w	1
shd_Length		rs.b	0

StrumentiTab:
	dc.l	schermo_strip
	dc.l	SchermoSheet
	dc.l	MappaGrigi
	dc.l	SchermoPos
	dc.w	0
	dc.w	SCHERMO_BYTE_W
	dc.w	SCHERMO_H
	dc.w	SCHERMO_COLONNE
	dc.w	SCHERMO_RIGHE

	dc.l	spia_strip
	dc.l	SpiaSheet
	dc.l	MappaGialli
	dc.l	SpieTab					; le posizioni stanno nella tabella delle
	dc.w	spi_Length				;   spie, non in una seconda copia
	dc.w	SPIA_BYTE_W
	dc.w	SPIA_H
	dc.w	SPIA_FASI
	dc.w	SPIA_GIALLE

	dc.l	spia_rossa_strip
	dc.l	SpiaRossaSheet
	dc.l	MappaRossa
	dc.l	SpieTab+SPIA_GIALLE*spi_Length	; l'ultima riga della stessa tabella
	dc.w	0
	dc.w	SPIA_BYTE_W
	dc.w	SPIA_H
	dc.w	SPIA_FASI
	dc.w	ROSSA_RIGHE

	dc.l	quadrante_strip
	dc.l	QuadSheet
	dc.l	MappaGrigi
	dc.l	QuadPos
	dc.w	0
	dc.w	QUAD_BYTE_W
	dc.w	QUAD_H
	dc.w	QUAD_ANGOLI
	dc.w	QUAD_RIGHE
StrumentiTabFine:
STRUM_QUANTI	EQU		(StrumentiTabFine-StrumentiTab)/shd_Length

; I piani della destinazione che la scritta riscrive: quelli in cui la tinta ha
; il bit a ZERO. Dove ce l'ha a 1, il fondo nero e la lettera accendono lo
; stesso pixel e il pannello e' gia' giusto da DisegnaPannello.
	cnop	0,4
ScrittaPianiTab:
	IFEQ	(SCRITTA_TINTA>>0)&1
	dc.l	0*PANNELLO_BUF_PLANE
	ENDC
	IFEQ	(SCRITTA_TINTA>>1)&1
	dc.l	1*PANNELLO_BUF_PLANE
	ENDC
	IFEQ	(SCRITTA_TINTA>>2)&1
	dc.l	2*PANNELLO_BUF_PLANE
	ENDC
	IFEQ	(SCRITTA_TINTA>>3)&1
	dc.l	3*PANNELLO_BUF_PLANE
	ENDC
ScrittaPianiFine:
	IFNE	(ScrittaPianiFine-ScrittaPianiTab)/4-SCRITTA_PIANI_N
; La tabella e il conto di SCRITTA_PIANI_N escono tutti e due da SCRITTA_TINTA:
; se non tornano, una delle due strade e' sbagliata.
GUARDIA_SCRITTA_PIANI	EQU		1/0
	ENDC

; Il messaggio che scorre. Cambiarlo qui, oppure chiamare ImpostaScritta con
; A0 su un'altra stringa: piu' lungo di SCRITTA_MAX_CAR viene tagliato.
ScrittaMessaggio:
	dc.b	'THE SACRED ARMOUR OF ANTIRIAD - AMIGA 1200 AGA - PORTING BY Mike e Zack             ',0
	EVEN
