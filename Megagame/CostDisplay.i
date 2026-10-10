; CostDisplay.i - Costanti: DMA, mappa, scroll, display, fade, alba, sfondo, cielo, alberi
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

; ---- I BIT DI DMACON, per nome ----
; Startup2 spegne TUTTI i DMA (`MOVE.W #$7FFF,$96`, riga 304), quindi da li' in
; avanti ogni canale va riacceso di proposito. Scrivere quei bit in binario
; nasconde proprio la domanda che conta, cioe' QUALE canale manca.
; ATTENZIONE, e' costato un blocco: se si scrive BLTSIZE con BLITEN SPENTO il
; blitter mette BBUSY e non lo toglie mai, perche' non ottiene i cicli DMA per
; finire. AspettaBlitter allora gira all'infinito e il programma si pianta
; senza dare nessun errore. Chi accende una scena che usa il blitter DEVE
; accendere anche DMA_BLITTER.
DMA_SET		EQU		$8000		; bit 15: i bit a 1 si ACCENDONO (a 0 si spengono)
DMA_MASTER	EQU		$0200		; DMAEN, il rubinetto generale
DMA_BPL		EQU		$0100		; BPLEN
DMA_COPPER	EQU		$0080		; COPEN
DMA_BLITTER	EQU		$0040		; BLITEN
DMA_SPRITE	EQU		$0020		; SPREN

; Il DMA del GIOCO: tutto acceso, sprite compresi (ci vive la parallasse).
	;5432109876543210
DMASET	EQU	DMA_SET|DMA_MASTER|DMA_BPL|DMA_COPPER|DMA_BLITTER|DMA_SPRITE

; Il DMA del TITOLO. Gli sprite restano SPENTI di proposito: la
; TitleCopperList non scrive gli SPRxPT, quindi accenderli mostrerebbe quello
; che i puntatori si portano dietro. Il blitter invece serve, ed e' l'unica
; differenza rispetto a quello che c'era prima del droide.
TIT_DMASET	EQU	DMA_SET|DMA_MASTER|DMA_BPL|DMA_COPPER|DMA_BLITTER

* COSTANTI
; ---- BOB e spritesheet (OMINO / NEMICO) ----
; Un frame e' BOB_W x BOB_H px. Lo slot orizzontale nello sheet e' PIU' LARGO
; dell'arte: con uno shift di 1..15 px il blit di BOB_W px si spalma su
; una word in piu', e quella word deve essere NERA. Da qui i 16 px di
; stacco fra un frame e l'altro. Non e' il padding a proteggere il rendering
; (la maschera e' il selettore del cookie cut), ma con lo slot pieno ogni
; lettura resta dentro il proprio frame e la riga divide esatta.
; Queste quattro descrivono l'ASSET e sono la sorgente da cui le Init
; riempiono bob_Larghezza / bob_Altezza / bob_Frames / bob_Bande.
BOB_W            	EQU     32				; larghezza frame (px)
BOB_H            	EQU     32				; altezza frame (px)
OMINO_FRAMES     	EQU     8				; frame di animazione per direzione
OMINO_DIR	      	EQU     8				; bande verticali (vedi DirectionDeltas)

; Dimensioni REALI del file: Omino32.raw e Nemico32.raw sono 61440 byte,
; cioe' 384x256 px a 5 piani = 12288 byte per piano. Servono in fase di
; ASSEMBLAGGIO, dove la struct non esiste ancora: dimensionano OMINO_MASK e
; NEMICO_MASK con ds.b e vanno passate a BuildBobMask.
; NON sono due numeri da tenere allineati a mano con la geometria: SONO la
; geometria. Una riga di sheet porta un frame per ogni fotogramma, e un frame
; occupa (larghezza/16+1) word, perche' la word in piu' e' lo stacco su cui si
; spalma lo shift orizzontale. L'altezza e' una banda per direzione. Cambia
; BOB_W, BOB_H, OMINO_FRAMES o OMINO_DIR e queste seguono da sole: prima
; erano dichiarate a parte e una guardia verificava che le due strade si
; incontrassero, adesso la strada e' una.
OMINO_SHEET_W      EQU     (BOB_W/16+1)*2*OMINO_FRAMES*8	; px, larghezza del file
OMINO_SHEET_H      EQU     BOB_H*OMINO_DIR					; righe del file
PLANE_SIZE       	EQU     (OMINO_SHEET_W/8)*OMINO_SHEET_H	; byte per bitplane

; Volume di COLLISIONE, deliberatamente separato dalla grafica: la grafica e'
; 32x32 ma il box resta 16x16, cosi' il livello e gli spawn tarati sul box
; piccolo continuano a valere. IsBoxBlocked sonda a passo <=15 px + il bordo,
; quindi funziona per qualunque valore senza saltare tile in mezzo.
; NB: portandoli a BOB_W/BOB_H il nemico 1 (288,48) rientra nel muro di
; tile(18,4) e va rispostato.

BOB_COLL_W       	EQU     BOB_W
BOB_COLL_H       	EQU     BOB_H
; ===================== DIMENSIONI DELLA MAPPA =====================
; Le uniche due manopole del livello, e descrivono un FILE: la mappa non e'
; piu' un blocco dc.w qui dentro ma grafica/mappa1.raw, una word per tile,
; prodotto da tools/mappa.py a partire da risorse/mappa1.txt. Questi due
; numeri li STAMPA quello strumento a ogni conversione: si ricopiano da li',
; e se sbagliano la guardia GUARDIA_MAPPA_RAW ferma l'assemblaggio invece di
; far leggere oltre la fine del file.
; Tutto il resto (pitch del buffer, modulo dello scroll, limiti del player,
; TILEXMAX, dimensione dei buffer) si ricalcola da solo.
; Stanno QUI e non piu' in mezzo alle costanti di gioco perche' SFONDO_PITCH
; ne dipende, e un EQU non puo' riferirsi a un simbolo definito dopo.
MAPPA_COLS 			EQU		73
MAPPA_ROWS			EQU		24

; Origine del mondo dentro il buffer. Definita qui sopra a SFONDO_PITCH
; perche' BG_ORIGIN_X entra nel calcolo del pitch; l'offset composto
; BG_ORIGIN_OFS invece sta piu' giu', perche' dal pitch dipende.
;   X=2 Y=16 : replica esatta di Path A (quello provato)
;   X=0 Y=0  : nessun margine, il mondo parte dall'angolo del buffer
BG_ORIGIN_X			EQU		0				; in BYTE. A 0 la mappa comincia dove
BG_ORIGIN_Y			EQU		0				; comincia la finestra: nessuno sfasamento
; Path B: il world buffer E' quello visualizzato. Il pitch sono i byte di mappa
; piu' 8 di guardia a sinistra per il prefetch del display; la mappa vera
; comincia a DELTA_MAPPAVERA. La guardia e' definita QUI e non presa da
; SCROLL_GUARD_BYTES di ScrollHW.i, incluso in coda mentre serve gia' a
; DisegnaSfondo: i due valori devono restare uguali.
;
; INTERRUTTORE: LARGHEZZA DEL PRELIEVO BITPLANE, in BIT (16, 32 o 64).
; Da questo numero discende TUTTA la geometria dello scroll - guardia, DDFSTRT,
; numero di fetch, byte per riga, BPLMOD, gli shift dentro ScrollHWCalc - e con
; essa quanti canali sprite restano vivi. Non c'e' un secondo posto da aggiornare.
;   64 bit: BPLxPT allineati a 8, passo 64 px, BPLCON1 0..63, DDFSTRT $18, 0 canali
;   32 bit: allineati a 4, passo 32 px, BPLCON1 0..31, DDFSTRT $28, 5 canali
;   16 bit: allineati a 2, passo 16 px, BPLCON1 0..15, DDFSTRT $30, 7 canali
; I canali sono tutti e tre MISURATI, non dedotti.
;
; IL VINCOLO CHE DECIDE: a 16 bit un blocco di fetch e' 8 color clock, cioe' 8
; slot DMA, e ogni bitplane ne vuole uno. In lores il massimo sono SEI bitplane:
; e' il limite OCS, ed e' la ragione per cui AGA ha inventato FMODE. Con otto
; piani accesi a 16 bit l'immagine non viene, e non e' un difetto dello scroll.
; Larghezza del prelievo bitplane, in BIT. Valori ammessi: 16, 32, 64.
SCROLL_FETCH_BIT		EQU		16

	IFEQ	SCROLL_FETCH_BIT-64
SCROLL_FMODE_BPL	EQU		$0003			; BPL32+BPAGEM: fetch a 64 bit
SCROLL_BYTES_FETCH	EQU		8				; byte per fetch e per piano
SCROLL_PASSO_CC		EQU		32				; color clock fra un fetch e l'altro
SCROLL_BLOCCO_SH	EQU		6				; log2 del blocco in px (64)
SCROLL_BYTES_SH		EQU		3				; log2 dei byte per fetch (8)
	ENDC
	IFEQ	SCROLL_FETCH_BIT-32
SCROLL_FMODE_BPL	EQU		$0001			; BPL32: fetch a 32 bit
SCROLL_BYTES_FETCH	EQU		4
SCROLL_PASSO_CC		EQU		16
SCROLL_BLOCCO_SH	EQU		5				; log2 del blocco in px (32)
SCROLL_BYTES_SH		EQU		2				; log2 dei byte per fetch (4)
	ENDC
	IFEQ	SCROLL_FETCH_BIT-16
SCROLL_FMODE_BPL	EQU		$0000			; nessun bit: fetch a 16 bit, come OCS
SCROLL_BYTES_FETCH	EQU		2
SCROLL_PASSO_CC		EQU		8
SCROLL_BLOCCO_SH	EQU		4				; log2 del blocco in px (16)
SCROLL_BYTES_SH		EQU		1				; log2 dei byte per fetch (2)
	ENDC
; Un valore fuori dai tre lascerebbe SCROLL_BYTES_FETCH indefinito, e
; l'assemblatore direbbe "simbolo sconosciuto" invece che "manopola sbagliata".
	IFNE	(SCROLL_FETCH_BIT-16)*(SCROLL_FETCH_BIT-32)*(SCROLL_FETCH_BIT-64)
ERRORE_SCROLL_FETCH_BIT_NON_AMMESSO		EQU		1/0
	ENDC

; Il blocco di fetch in PIXEL lores: 8 px per byte.
SCROLL_BLOCCO_PX	EQU		SCROLL_BYTES_FETCH*8

; INTERRUTTORE: SPRITE LARGHI (bit 2-3 di FMODE)
; 0 = sprite da 16 px, il comportamento OCS. 1 = sprite da 64 px.
; I bit 2 (SPR32) e 3 (SPAGEM) di FMODE fanno prelevare 64 bit per accesso
; invece di 16: lo sprite diventa largo 64 px USANDO GLI STESSI DUE SLOT DMA
; per riga. Se e' vero, cinque canali coprono 5*64 = 320 px, cioe' tutta la
; larghezza dello schermo, e i conti sui canali per livello di parallasse
; (3 / 7 / 13 con sprite da 16 px) si dividono per quattro.
; NON tocca i bit 0-1, quelli dei bitplane: la geometria dello scroll appena
; tarata resta identica pixel per pixel. E' l'unica ragione per cui questa
; prova si puo' fare senza rimettere in discussione niente.
; DA PROVARE SUL FERRO, non in WinUAE: FMODE e' il registro che ha gia' reso
; illeggibile la title screen sulla macchina vera mentre nell'emulatore era
; perfetta (23 agosto). Un "funziona" dell'emulatore qui non vale.
; IL FORMATO DEI DATI, chiuso il 5 settembre: ogni accesso DMA sprite e' largo
; quanto dice FMODE, e SPRPOS e SPRCTL sono la PRIMA word di DUE accessi
; distinti. A 64 bit il blocco di controllo occupa quindi 16 byte (SPRPOS al
; byte 0, SPRCTL al byte 8) e ogni riga 16 (8 di piano A, 8 di piano B).
; Con SPAGEM ogni sprite deve anche partire a un indirizzo multiplo di 8.
SPRITE64			EQU		1

	IFEQ	SPRITE64
SCROLL_SPR_BITS		EQU		$0000
	ENDC
	IFNE	SPRITE64
SCROLL_SPR_BITS		EQU		$000C			; SPR32 + SPAGEM
	ENDC

; Il valore che finisce davvero in FMODE: i bit dei bitplane dall'interruttore
; della geometria, quelli degli sprite dal loro. Un posto solo.
SCROLL_FMODE_VAL	EQU		SCROLL_FMODE_BPL|SCROLL_SPR_BITS

; LA PARALLASSE VIVE SUGLI SPRITE, e non e' piu' un interruttore.
; Sei sprite larghi 64 px che si spostano, sei bitplane, blitter libero. Fino
; al 5 settembre c'era `PARALLASSE_SPRITE` con la posizione 0 che rimetteva i
; due bitplane e i due blit; e' stato tolto insieme al codice vecchio, perche'
; un interruttore con una sola posizione valida e' solo un modo di far credere
; che la strada di ritorno esista ancora. Se serve, sta nella cronologia.
; MISURATO il 5 settembre: a DDFSTRT $30 sopravvivono SETTE canali sprite, e
; sei bastano a coprire lo schermo per qualunque scostamento (6*64 = 384 px
; contro i 320 + 63 di arretramento). Il settimo resta libero per il gioco.
; Il quadro e' passato da 289 righe a 120, DR 000.
; IL VINCOLO CHE RESTA: sei canali esistono solo col prelievo a 16 bit, e sei
; bitplane sono il massimo che quel prelievo regge in lores. Quindi il gioco
; IMPONE SCROLL_FETCH_BIT 16, e la guardia lo dice all'assemblatore invece di
; lasciarlo scoprire a schermo.
	IFNE	SCROLL_FETCH_BIT-16
ERRORE_LA_PARALLASSE_A_SPRITE_VUOLE_FETCH_16	EQU		1/0
	ENDC

; La guardia a sinistra e' esattamente il prefetch, cioe' UN blocco di fetch:
; il puntatore del display deve stare un blocco prima del primo pixel visibile,
; perche' quei dati BPLCON1 li ritarda dentro la finestra. Era 8 scritto a mano.
DELTA_MAPPAVERA		EQU		SCROLL_BYTES_FETCH

; Byte che il display fetcha per riga. Deve coincidere con SCROLL_FETCH_BYTES
; di ScrollHW.i, che pero' e' incluso DOPO e qui serve gia' per il pitch.
; Piu' sotto, dopo l'include, c'e' un controllo che ferma l'assemblaggio se i
; due valori divergono.
; Byte che il display fetcha per riga e per piano. NON e' un numero scritto a
; mano: discende dalla finestra di fetch, esattamente come in ScrollHW.i, che
; adesso legge queste invece di ridefinirle. Prima erano due catene separate
; che finivano sullo stesso numero, con una guardia in mezzo a controllare che
; ci finissero davvero - e la copia esisteva solo perche' ScrollHW.i viene
; incluso DOPO, e il pitch serviva prima.
; Il passo di fetch e ogni quanti byte porta dipendono da FMODE: vedi
; l'interruttore SCROLL_FETCH_BIT qui sopra. $38 e' il DDFSTRT SENZA prefetch,
; cioe' (DIWSTRT_H-$11)/2; il prefetch e' un blocco intero, e una unita' di
; DDFSTRT vale 2 px lores, da cui il /2.
SCROLL_DDFSTRT		EQU		$38-(SCROLL_BLOCCO_PX/2)
SCROLL_DDFSTOP		EQU		$d8				; allargato di un blocco per la finestra piu' larga
SCROLL_FETCHES		EQU		((SCROLL_DDFSTOP-SCROLL_DDFSTRT)/SCROLL_PASSO_CC)+1
SCROLL_FETCH_BYTES	EQU		SCROLL_FETCHES*SCROLL_BYTES_FETCH
; (DDFSTOP-DDFSTRT) DEVE essere multiplo del passo di fetch, altrimenti il
; fetch va fuori sincrono e l'immagine diventa illeggibile. Con 64 bit il passo
; e' 32, con 32 bit e' 16, con 16 bit e' 8: la guardia vale per tutti e tre.
	IFNE	(SCROLL_DDFSTOP-SCROLL_DDFSTRT)-((SCROLL_DDFSTOP-SCROLL_DDFSTRT)/SCROLL_PASSO_CC)*SCROLL_PASSO_CC
ERRORE_DDF_NON_MULTIPLO_DEL_PASSO	EQU	1/0
	ENDC
DISPLAY_FETCH_BYTES	EQU		SCROLL_FETCH_BYTES

; A che byte della riga punta il display per i piani 7-8 (parallasse).
; NON e' un dettaglio: davanti al puntatore serve una GUARDIA che ospiti
;   - la prima word del blit, che e' contaminata (16 px), e
;   - l'arretramento massimo del display dovuto a BPLCON1 (63 px).
; A +8 la guardia era di soli 64 px: non ci stavano entrambe, ed e' da li' che
; venivano prima la striscia sporca e poi gli 8 px vuoti a sinistra.
; A +16 la guardia e' di 128 px e ci stanno con margine.
; Finestra di display orizzontale. Sta QUI, prima di tutto il resto, perche'
; da lei discendono sia la larghezza del pannello sia la corsa della camera,
; e quindi il pitch del mondo. Devpac valuta le EQU dove le incontra: se sta
; piu' in basso, il calcolo del pitch legge un simbolo non ancora definito.
; ne discende: il pannello copre esattamente la finestra, non un numero suo.
DIW_H_START			EQU		$81
DIW_H_STOP			EQU		$C1				; +256 = 449, quindi finestra
	; 129..449 = 320 px
DIW_WIDTH			EQU		(DIW_H_STOP+256)-DIW_H_START	; px visibili

; Quello che il DISPLAY pretende dalla riga, ed e' un vincolo che esiste anche
; senza parallasse: la guardia di prefetch, piu' la corsa della camera dentro
; la riga, piu' i byte che il display fetcha. Finora questo numero non era
; scritto da nessuna parte: era COPERTO PER CASO da PAR_PTR_OFS+fetch, cioe'
; dalla guardia della parallasse, che valeva di piu'. Tolta quella, il vincolo
; vero va detto.
SCROLL_CAMERA_PX	EQU		MAPPA_COLS*16-DIW_WIDTH		; px di corsa della camera
SCROLL_OFS_MAX		EQU		((SCROLL_CAMERA_PX+SCROLL_BLOCCO_PX-1)/SCROLL_BLOCCO_PX)*SCROLL_BYTES_FETCH

; SCORTA, dichiarata perche' non e' derivata da niente. Il conto qui sopra da'
; 56 e basterebbe ESATTAMENTE, senza un byte di margine, e il pitch scenderebbe
; da 64 a 56 - circa 13 KB di chip in meno e blit piu' corti. Non si fa
; insieme alla rimozione della vecchia parallasse: cambia la memoria del mondo
; e potenzialmente l'immagine, quindi e' una modifica a se', da guardare a
; schermo per conto suo. Il commento storico qui sotto dice che "con 56
; l'ultima colonna sforava": era un'altra geometria, ma e' un motivo in piu'
; per misurare invece di dedurre. Portare questa a 0 e' tutto il lavoro.
SFONDO_ROW_SCORTA	EQU		8

; BPLCON3: i due valori usati ovunque, con LOCT a 0 o 1.
; Il bit 5 e' BRDRBLNK: acceso, l'area FUORI dalla finestra DIW viene forzata a
; NERO invece di mostrare COLOR00. Serve a mascherare i pixel sporchi ai bordi:
; si stringe la finestra di qualche pixel per lato e quello che resta fuori
; diventa una cornice nera. Il copper NON potrebbe farlo cambiando COLOR00,
; perche' quel colore vale solo dove TUTTI i bitplane sono a zero, mentre i
; pixel sporchi hanno i bit della parallasse accesi.
; NB: i commenti nel sorgente dicevano gia' "BRDRBLNK=1" ma il bit era ZERO.
BPLCON3_BRDRBLNK	EQU		$20
BPLCON3_LOCT0		EQU		$0C00|BPLCON3_BRDRBLNK
BPLCON3_LOCT1		EQU		$0E00|BPLCON3_BRDRBLNK

; ============================================================================
; LO STATO DI DISPLAY DELLE DUE SCENE
;
; Il programma mostra due schermate con geometrie diverse: il TITOLO (8 piani,
; prelievo a 64 bit, DDF $28..$a8) e il GIOCO (6 piani, prelievo a 16 bit,
; DDF da ScrollHW.i). Ogni valore stava scritto DUE VOLTE - una nel blocco di
; MOVE che la CPU esegue e una nella copperlist della scena - e le due copie si
; sono gia' scollate due volte: BPLCON4 restava a $0011 dall'epoca del falo'
; sprite, e FMODE mancava del tutto dal blocco CPU di ShowTitle mentre la
; copperlist lo scriveva. Nessuno dei due errori poteva essere visto
; dall'assemblatore.
;
; Da qui in avanti il valore e' UNO SOLO e lo leggono tutti e due. Il blocco
; CPU serve ancora, e non e' ridondanza: fra l'accensione del DMA bitplane e
; la prima passata del copper c'e' una finestra in cui vale quello che ha
; lasciato chi c'era prima.
;
; CHI SCRIVE COSA, perche' le due scene NON sono simmetriche:
;   titolo - la copperlist scrive tutto, e ImpostaDisplayTitolo ripete gli
;            stessi dodici valori come cintura prima di accendere il DMA;
;   gioco  - la copperlist scrive FMODE, BPLCON0/1/2, i moduli, DDF e DIW;
;            BPLCON3 e BPLCON4 NON ci sono di proposito (il blocco PALETTE
;            gestisce BPLCON3 con LOCT alternato), quindi quei due li scrive
;            solo la CPU. ImpostaDisplayGioco e' percio' corta di dodici
;            valori: non e' una dimenticanza, e' dove passa il confine.
; ============================================================================
; BPLCON0 della FASCIA DI GIOCO, e il suo gemello a zero piani. Stanno qui
; perche' li leggono in DUE posti: la copperlist (CL_Bplcon0) e le due righe
; della tenda (MondoNascondi/MondoMostra). Scritti in binario nei due posti
; sarebbero la solita coppia che diverge in silenzio.
; Sei piani: i due della parallasse sono passati agli sprite il 5 settembre,
; e il prelievo a 16 bit che apre i sette canali ne regge sei in lores.
BPLCON0_GIOCO	EQU		%0110001000000001	; BPU=6, COLOR (color burst) + ECSENA
BPLCON0_ZERO	EQU		%0000001000000001	; BPU=0: nessun piano, resta il resto
	; I due valori devono differire SOLO per il numero di piani: se un domani
	; qualcuno tocca un altro bit di BPLCON0_GIOCO, la tenda lo spegnerebbe
	; senza rimetterlo, e il difetto uscirebbe alla prima porta. La differenza
	; deve valere esattamente BPU=6, e la sottrazione basta a dirlo perche' il
	; campo BPU dello zero e' zero: niente XOR e niente complemento, che in
	; questo sorgente non sono mai stati assemblati ne' da vasm ne' da Devpac.
	IFNE	BPLCON0_GIOCO-BPLCON0_ZERO-(6<<12)
GUARDIA_BPLCON0_TENDA	EQU		1/0
	ENDC

; LA TENDA SUL PASSAGGIO FRA BLOCCHI. 0 = come prima, 1 = il campo di gioco
; resta spento per i ~44 quadri di RicostruisciMondo.
; Oggi va lasciata a 0, e il motivo e' che la porta rimanda alla STESSA mappa:
; i due buffer vengono riscritti con contenuto identico, quindi a schermo si
; vede solo un fermo, mentre la tenda farebbe comparire un secondo di cielo
; piatto che prima non c'era. **Il giorno che la destinazione cambia va messa
; a 1**, se no si guarda il mondo nuovo che si disegna una tile alla volta.
; All'AVVIO la tenda non serve e non va chiamata: li' il mondo non e' ancora a
; video - c'e' l'ultimo fotogramma dell'alba - e spegnere i piani vorrebbe dire
; buttare via proprio la cosa che lo rende gradevole.
TENDA_PASSAGGIO	EQU		0

; I QUATTRO VERSI di un passaggio. Sono l'ORDINE delle word in MappaLink, e
; stanno qui e non nel file generato perche' sono un fatto del motore: chi
; genera Mappe.i li LEGGE da queste righe, cosi' cambiando l'ordine qui la
; tabella lo segue invece di contraddirlo in silenzio.
; I valori devono restare 0..VERSI_N-1 consecutivi: tools/mappe.py lo verifica
; e si rifiuta di generare se non lo sono.
VERSO_SX		EQU		0		; bordo sinistro -> si entra da destra
VERSO_DX		EQU		1		; bordo destro   -> si entra da sinistra
VERSO_SU		EQU		2		; bordo alto     -> si entra dal basso
VERSO_GIU		EQU		3		; bordo basso    -> si entra dall'alto
VERSI_N			EQU		4
	IFNE	VERSI_N-4
GUARDIA_VERSI_N	EQU		1/0		; l'aritmetica di ControllaPassaggio ne vuole 4
	ENDC

; Le voci del BANCO 1, cioe' i colori 32..63: lo sfondo NOTTURNO, che e' il
; banco 0 dimezzato e lo sceglie il bit 5 dell'indice, cioe' il darkplane.
; **Dal 25 settembre 2026 questo banco lo scrive il COPPER**, non la CPU al
; boot. Il perche' non e' eleganza: di notte ogni pixel del mondo pesca qui, e
; un banco che vive solo nei registri non si puo' far sfumare senza che la CPU
; scriva BPLCON3 e 32 registri di colore mentre il copper riscrive BPLCON3 per
; conto suo. E' la corsa che COLOR00 ha gia' fatto pagare un pomeriggio.
NOTTE_VOCI              EQU     32

; ============================================================================
; LA DISSOLVENZA SUL PASSAGGIO
; Al bordo: fade out della palette fino al nero pieno, fermo sul nero per la
; ricostruzione del mondo, fade in. Il PANNELLO non sfuma: ha una palette sua
; in Pannello.cop, su una fascia raster diversa, e non toccarla e' gratis.
;
; LE VOCI CHE SFUMANO sono 76, e sono tutte quelle che il COPPER scrive:
;   32  banco 0, il mondo di giorno     (GamePalHi / GamePalLo)
;   32  banco 1, il mondo di notte      (NotteHi / NotteLo)
;   12  banco 2, le tinte degli alberi  (AlberiPalHi / AlberiPalLo)
; Le dodici degli alberi sono le sei tinte vere ripetute su due coppie di
; canali: la tabella sotto le elenca nell'ordine in cui le scrive la
; copperlist, non nell'ordine in cui esistono.
FADE_VOCI_MONDO		EQU		32
FADE_VOCI_ALBERI	EQU		12
FADE_VOCI			EQU		FADE_VOCI_MONDO+NOTTE_VOCI+FADE_VOCI_ALBERI
FADE_BLOCCHI		EQU		6		; i sei spazi di copperlist da riscrivere

; Livelli di luminosita': 0 = nero pieno, FADE_LIVELLI-1 = palette piena.
; Il costo e' tutto in tabella (FADE_VOCI*2 word per livello) e il tempo di una
; dissolvenza e' FADE_LIVELLI*FADE_RITMO quadri per verso.
FADE_LIVELLI		EQU		16
FADE_RITMO			EQU		1		; quadri per livello
	IFLT	FADE_LIVELLI-2
GUARDIA_FADE_LIVELLI	EQU		1/0	; con un livello solo non c'e' dissolvenza
	ENDC
	IFLT	FADE_RITMO-1
GUARDIA_FADE_RITMO		EQU		1/0
	ENDC

; 0 = la porta resta quella di prima (ricostruzione secca, eventualmente dietro
; TENDA_PASSAGGIO); 1 = la porta passa dalla dissolvenza.
; NOTA: con la dissolvenza accesa **TENDA_PASSAGGIO non serve piu'** - lo
; schermo e' nero perche' lo e' la palette, non perche' i piani sono spenti.
; Restano due meccanismi per lo stesso lavoro: se la dissolvenza convince, la
; tenda va togliesta.
FADE_PASSAGGIO		EQU		1
; ============================================================================

TIT_FMODE		EQU		$0003			; BPL32+BPAGEM: prelievo bitplane a 64 bit
TIT_BPLCON0		EQU		%0000001000010001	; BPU3=1 (8 piani) + COLOR + ECSENA
TIT_BPLCON1		EQU		$0000
TIT_BPLCON2		EQU		$0024			; PF2P=4, PF1P=4
TIT_BPLCON3		EQU		BPLCON3_BRDRBLNK	; banco 0, LOCT=0, bordo nero
TIT_BPLCON4		EQU		$0000			; sprite alle voci 16..31 (OCS standard)
TIT_BPLMOD		EQU		$0000			; layout sequenziale: nessun modulo
TIT_DDFSTRT		EQU		$0028			; 5 prelievi da 64 px = 320 px
TIT_DDFSTOP		EQU		$00a8
; La finestra del titolo e' SUA e non passa da DIW_H_START, che e' tarato sui
; vincoli del gioco (guardia della parallasse e ritardo BPLCON1). Sostituendola
; una volta per sbaglio la finestra era diventata di 289 px invece di 320.
TIT_DIWSTRT		EQU		$2c81
TIT_DIWSTOP		EQU		$2cc1
; Il valore DEL GIOCO per BPLCON4: ESPRM=OSPRM=$4, cioe' gli sprite leggono le
; voci 64..79, che e' dove InitParallasseSprite mette le tinte degli alberi.
GIOCO_BPLCON4	EQU		$0044

; ============================================================================
; L'ALBA - prima videata dell'intro. Il codice sta in Intro.i.
;
; L'immagine non si muove mai: si muove la PALETTE, e la scrive il copper in
; cima al quadro. La geometria di display e' quella del titolo (le TIT_* qui
; sopra), quindi il passaggio titolo -> intro non tocca un registro.
;
; Le prime ALBA_VOCI_ARCO voci sono l'arco luminoso e si animano; le altre
; sono il disco scuro del pianeta e lo spazio, che si vedono dal primo quadro
; e non cambiano mai. L'ordine non e' un caso: lo impone il generatore, cosi'
; "questa voce si anima?" a runtime non serve nemmeno chiederselo.
; ============================================================================
ALBA_LARG			EQU		320
ALBA_ALT			EQU		256
ALBA_PIANI			EQU		8			; come il titolo: 256 colori
ALBA_BYTES_RIGA		EQU		ALBA_LARG/8
ALBA_PLANE_SIZE		EQU		ALBA_BYTES_RIGA*ALBA_ALT
ALBA_LEN_ATTESA		EQU		ALBA_PLANE_SIZE*ALBA_PIANI	; guardia sul .raw
ALBA_VOCI			EQU		1<<ALBA_PIANI
ALBA_VOCI_ARCO		EQU		180			; quante voci sono l'arco (le prime)

; I LIVELLI DELLA RAMPA. Misurato: la voce che viaggia di piu' copre 87 L*,
; quindi il gradino vale 87/ALBA_LIVELLI. Con 64 sarebbe 1,36 L*, con 128 e'
; 0,68, sotto la soglia percettiva anche col metro SPAZIALE - che qui e' pure
; troppo severo, perche' questo gradino sta nel TEMPO. Dimezzando i livelli si
; dimezza la tabella: e' la manopola, e va rigenerata l'arte.
ALBA_LIVELLI		EQU		128
ALBA_LIV_SH			EQU		1			; quadri per livello = 2^ALBA_LIV_SH
	IFLT	ALBA_LIV_SH-1
ERRORE_ALBA_LIV_SH_SOTTO_1		EQU		1/0		; LSR immediato: 1..8
	ENDC
	IFGT	ALBA_LIV_SH-8
ERRORE_ALBA_LIV_SH_SOPRA_8		EQU		1/0
	ENDC
ALBA_RAMPA_QUADRI	EQU		ALBA_LIVELLI<<ALBA_LIV_SH	; una rampa intera
ALBA_SPREAD			EQU		192			; scarto fra la prima voce e l'ultima
ALBA_QUADRI			EQU		ALBA_SPREAD+ALBA_RAMPA_QUADRI	; 448 = 8,96 s
ALBA_RAMPA_VOCE		EQU		ALBA_LIVELLI*4				; byte per voce
ALBA_RAMPE_ATTESA	EQU		ALBA_VOCI*ALBA_RAMPA_VOCE	; guardia sul .raw
ALBA_INIZIO_ATTESA	EQU		ALBA_VOCI*2					; guardia sul .raw

; IL BLOCCO COPPER. Per banco: una MOVE su BPLCON3 e ALBA_COP_SLOT MOVE sui
; COLORxx, due volte - i nibble alti e i bassi, che e' come si scrive una
; palette AGA a 24 bit. Tutto derivato, niente scritto a mano.
ALBA_COP_SLOT		EQU		32							; COLOR00..COLOR31
ALBA_COP_BANCHI		EQU		ALBA_VOCI/ALBA_COP_SLOT		; 8
ALBA_COP_MOVE		EQU		(1+ALBA_COP_SLOT)*2			; MOVE per banco = 66
ALBA_COP_BANCO		EQU		ALBA_COP_MOVE*4				; byte per banco = 264
ALBA_COP_WORDS		EQU		ALBA_COP_BANCHI*ALBA_COP_MOVE*2	; 1056
; Distanza fra la word dei nibble ALTI di una voce e quella dei BASSI: una
; MOVE di BPLCON3 piu' i 32 COLOR della prima passata.
ALBA_COP_LO_OFS		EQU		(1+ALBA_COP_SLOT)*4			; 132
; Quanto saltare a fine banco per arrivare al primo valore del banco dopo.
ALBA_COP_SALTO		EQU		ALBA_COP_BANCO-ALBA_COP_SLOT*4	; 136
; Il pitch deve contenere: guardia + origine del mondo + una riga intera di
; mappa, arrotondato al multiplo di 8 richiesto da FMODE=3. Era scritto a
; mano (64): con 56 l'ultima colonna sforava nella riga successiva, e con
; una mappa oltre le 27 colonne anche 64 sarebbe silenziosamente
; insufficiente. Ora si adegua da solo a MAPPA_COLS.
; La riga deve bastare a DUE cose, e si prende la maggiore:
;   - la mappa vera, con la sua guardia a sinistra
;   - quello che il display fetcha davvero (guardia + corsa camera + fetch)
SFONDO_ROW_MAPPA	EQU		DELTA_MAPPAVERA+BG_ORIGIN_X+MAPPA_COLS*2
SFONDO_ROW_FETCH	EQU		DELTA_MAPPAVERA+SCROLL_OFS_MAX+DISPLAY_FETCH_BYTES+SFONDO_ROW_SCORTA
	IFGE	SFONDO_ROW_MAPPA-SFONDO_ROW_FETCH
SFONDO_ROW_NEED		EQU		SFONDO_ROW_MAPPA
	ENDC
	IFLT	SFONDO_ROW_MAPPA-SFONDO_ROW_FETCH
SFONDO_ROW_NEED		EQU		SFONDO_ROW_FETCH
	ENDC
SFONDO_PITCH		EQU		((SFONDO_ROW_NEED+7)/8)*8
; I piani 6/7/8 (darkplane e parallasse) DEVONO avere lo stesso pitch dei
; piani 1-5: BPL1MOD e BPL2MOD sono condivisi fra piani dispari (1,3,5,7)
; e pari (2,4,6,8), quindi un pitch diverso farebbe slittare ogni riga.
AUX_PITCH			EQU		SFONDO_PITCH
; DEST_PITCH/DEST_PLANE_SZ e il blocco DARK_* stavano qui. Sono stati spostati
; piu' in basso, dopo i simboli da cui dipendono: Devpac valuta le EQU in UNA
; passata e su un riferimento in avanti da "absolute expression must evaluate",
; mentre vasm lo risolve in silenzio. Il sorgente deve andare bene a entrambi.
; Vedi tools/controlla-forward.py, che rifa' questo controllo su tutto il file.
; ORIGINE DEL MONDO nel buffer, sui due assi SEPARATAMENTE.
; In Path A CopiaVideo leggeva da SFONDOGRANDE+16*SFONDO_PITCH+2, cioe'
; 16 righe e 16 px (una word) di margine. Ma quei due margini servivano
; al TREADMILL (spazio per lo shift e per AddRigaAlto), e non e' detto
; che le coordinate mondo della LOGICA li includano: sfondo e BOB usano
; la stessa origine, quindi restano allineati fra loro qualunque valore
; si metta qui — cambia solo il rapporto con la griglia delle tile che
; la collisione usa.
; TARATURA: prova le combinazioni e guarda il player rispetto alla tile
; su cui appoggia. Ogni unita' di BG_ORIGIN_X vale 8 px, ogni unita' di
; BG_ORIGIN_Y vale una riga.
;   X=2 Y=16 : replica esatta di Path A (quello provato)
;   X=0 Y=0  : nessun margine, il mondo parte dall'angolo del buffer
;   X=0 Y=16 : solo verticale
;   X=2 Y=0  : solo orizzontale
BG_ORIGIN_OFS		EQU		BG_ORIGIN_Y*SFONDO_PITCH+BG_ORIGIN_X
BPSF_PITCH			EQU		48

; ALTEZZA DI SFONDOGRANDE
; In Path B il buffer contiene TUTTA la mappa e non si sposta mai: sono i
; puntatori dei bitplane a muoversi dentro di lui. L'altezza non e' quindi una
; manopola di prestazioni ma un fatto geometrico:
;   BUFFER_ROWS = MAPPA_ROWS + 1 tile di margine sopra (vedi BG_ORIGIN_OFS)
;   SFONDO_HEIGHT = BUFFER_ROWS * 16
; Non c'e' piu' nessun vincolo di tempo sull'altezza: il doppio buffer del mondo
; toglie la scadenza sui BOB (si pubblica solo a disegno finito) e la parallasse
; entra in vigore insieme a BPLCON1 dentro ScrollPathBApply.
; Resta il solo vincolo geometrico: BG_VIS_ROWS multiplo di 16, altrimenti
; TILEYMAX arrotonda per difetto e la camera scende oltre il fondo mappa.
CUT_BOTTOM_ROWS		EQU		80				; righe in fondo NON disegnate
	; (documentazione estesa piu' sotto)
BG_VIS_ROWS			EQU		256-CUT_BOTTOM_ROWS		; altezza dell'area di gioco

BUFFER_ROWS			EQU		MAPPA_ROWS+1	; tutta la mappa + 1 tile di margine
	; sopra (vedi BG_ORIGIN_OFS)
SFONDO_HEIGHT		EQU		BUFFER_ROWS*16	; altezza SFONDOGRANDE in righe
SFONDO_PLANE_SIZE 	EQU		SFONDO_PITCH*SFONDO_HEIGHT	; byte/plane
; Dove finiscono i BOB: in Path B sul world buffer visualizzato. Stanno QUI e
; non piu' su, perche' DEST_PLANE_SZ ha bisogno di SFONDO_PLANE_SIZE.
DEST_PITCH			EQU		SFONDO_PITCH
DEST_PLANE_SZ		EQU		SFONDO_PLANE_SIZE

; COME SI COPIA O SI RIEMPIE UN PIANO INTERO, e perche' non "come si vede".
; BLTSIZE ha SEI bit di larghezza: 64 word, 128 byte, e non uno di piu'.
; Finche' il pitch stava sotto i 128 byte si poteva scrivere
; (SFONDO_HEIGHT<<6)|(SFONDO_PITCH/2) e funzionava; con la mappa larga 73 tile
; il pitch e' 160, la larghezza diventa 80 word e il bit di troppo SBORDA NEL
; CAMPO ALTEZZA: il blitter copierebbe 16 word per 401 righe invece di 80 per
; 400, cioe' un quinto di ogni riga, senza nessun errore da nessuna parte.
; Il piano pero' e' CONTIGUO e i due blit che lo toccano (PathBBuildMaster e il
; fill di PathBBuildDark) hanno BLTAMOD e BLTDMOD a zero: la FORMA non conta,
; conta il numero di word. Quindi si lavora a strisce della larghezza massima.
; La divisione e' esatta per costruzione: il pitch e' multiplo di 8 e l'altezza
; di 16, quindi il piano e' multiplo di 128 byte. Le due guardie lo dicono
; comunque, perche' un giorno potrebbe non esserlo piu'.
COPIA_PIANO_W		EQU		64						; word: il massimo di BLTSIZE
COPIA_PIANO_H		EQU		SFONDO_PLANE_SIZE/(COPIA_PIANO_W*2)
; larghezza 64 si scrive 0 nel campo a 6 bit: e' la codifica del chipset
COPIA_PIANO_BLT		EQU		(COPIA_PIANO_H<<6)|(COPIA_PIANO_W&63)
	IFNE	SFONDO_PLANE_SIZE-COPIA_PIANO_H*COPIA_PIANO_W*2
GUARDIA_COPIA_PIANO	EQU		1/0
	ENDC
	IFGT	COPIA_PIANO_H-1024
GUARDIA_COPIA_ALTEZZA	EQU	1/0
	ENDC

; IL PIANO DEVE STARE IN UNA WORD SENZA SEGNO, e non e' un vezzo: DisegnaBOB
; costruisce l'offset dentro il piano con MULU.W #SFONDO_PITCH seguita da
; ADD.W (blocco "Calcolo destinazione e shift"), cioe' in 16 bit. Oggi il
; conto peggiore vale 64000 su 65535 e sembra un margine largo: non lo e'.
; BASTA UNA RIGA DI TILE IN PIU' nella mappa - SFONDO_HEIGHT passa a 416,
; il piano a 66560 - perche' l'offset riparta da zero IN SILENZIO e i BOB
; finiscano disegnati nell'angolo alto del buffer. Questa guardia trasforma
; quel giorno in un errore di assemblaggio invece che in una serata persa.
	IFGT	SFONDO_PLANE_SIZE-65535
GUARDIA_PIANO_IN_WORD	EQU	1/0
	ENDC

; QUI STAVA tutta la macchina della parallasse a bitplane: la striscia con la
; sua replica (PARALLAX_STRIP_*), la larghezza del blit, la guardia a sinistra,
; il margine, e i tre interruttori di prova PAR_DISABLE / PAR_TEST_FILL /
; PAR_TEST_MODE. Sono ~120 righe di EQU e di commenti tolte il 5 settembre col
; passaggio agli sprite. Le lezioni che valevano oltre quel codice (la striscia
; sporca a sinistra, l'offset che wrappava, il perche' del blit a riga intera)
; sono in claude/architettura.md e claude/decisioni.md, non qui.

SKYLINE_C1_RGB          EQU     $182838         ; corpo del ramo, il piu' scuro
SKYLINE_C2_RGB          EQU     $2a3a52         ; mezzatinta
SKYLINE_C3_RGB          EQU     $46608c         ; bordo illuminato del ramo
; Le stesse tre tinte spezzate come le vuole il chipset AGA: nibble ALTI con
; BPLCON3 LOCT=0, nibble BASSI con LOCT=1. Servono alla parallasse sugli
; sprite, che le scrive dal copper invece di prenderle dai banchi di palette.
; Stessa forma delle FALO_C*_HI/LO: si derivano dal valore a 24 bit, non si
; ricopiano a mano.
SKYLINE_C1_HI   EQU     ((((SKYLINE_C1_RGB>>20)&15)<<8)|(((SKYLINE_C1_RGB>>12)&15)<<4)|((SKYLINE_C1_RGB>>4)&15))
SKYLINE_C1_LO   EQU     ((((SKYLINE_C1_RGB>>16)&15)<<8)|(((SKYLINE_C1_RGB>>8)&15)<<4)|(SKYLINE_C1_RGB&15))
SKYLINE_C2_HI   EQU     ((((SKYLINE_C2_RGB>>20)&15)<<8)|(((SKYLINE_C2_RGB>>12)&15)<<4)|((SKYLINE_C2_RGB>>4)&15))
SKYLINE_C2_LO   EQU     ((((SKYLINE_C2_RGB>>16)&15)<<8)|(((SKYLINE_C2_RGB>>8)&15)<<4)|(SKYLINE_C2_RGB&15))
SKYLINE_C3_HI   EQU     ((((SKYLINE_C3_RGB>>20)&15)<<8)|(((SKYLINE_C3_RGB>>12)&15)<<4)|((SKYLINE_C3_RGB>>4)&15))
SKYLINE_C3_LO   EQU     ((((SKYLINE_C3_RGB>>16)&15)<<8)|(((SKYLINE_C3_RGB>>8)&15)<<4)|(SKYLINE_C3_RGB&15))
; SKYLINE_MIX_n: quanto la tinta n segue il colore del CIELO di quella riga, in
; ottavi:  tinta_n(riga) = (SKYLINE_Cn_RGB*(8-mix) + cielo(riga)*mix) / 8
; Mix 0 = la tinta non si muove e il copper NON la scrive: costo zero.
; SONO TUTTI A ZERO, ED E' UNA SCELTA MISURATA. L'arte non e' uno skyline
; lontano nonostante i nomi: sono alberi in PRIMO PIANO, presenti su tutte le
; righe visibili. Un primo piano deve STAGLIARSI sul cielo, non fondersi: col mix
; i rami si scioglievano, e all'orizzonte, dove il cielo e' chiaro, sparivano.
; LEZIONE: la misura che avevo portato a sostegno era il dL* fra righe adiacenti,
; ed era la grandezza SBAGLIATA. Per una sagoma conta il CONTRASTO COL FONDO, che
; il mix distrugge per costruzione. Prima di misurare, decidere quale grandezza
; risponde alla domanda.
; SE UN GIORNO SERVE: su un layer davvero lontano il meccanismo torna buono. Qui
; l'unica variante che reggeva era 0/0/6, cioe' muovere solo il valore 3 (il
; bordo illuminato) lasciando neri i corpi: una luce di taglio che segue il
; tramonto.
SKYLINE_MIX_1           EQU     0               ; corpo del ramo
SKYLINE_MIX_2           EQU     0               ; mezzatinta
SKYLINE_MIX_3           EQU     0               ; bordo illuminato

; Quante tinte il copper riscrive a ogni riga. NON e' una manopola: si DERIVA
; dai mix, perche' una tinta con mix 0 e' identica alla costante gia' scritta
; da InitPalette8BPL e riscriverla ogni riga sarebbe lavoro per niente.
; (mix+7)/8 vale 0 per mix=0 e 1 per mix da 1 a 8.
SKYLINE_MOBILE_1        EQU     (SKYLINE_MIX_1+7)/8
SKYLINE_MOBILE_2        EQU     (SKYLINE_MIX_2+7)/8
SKYLINE_MOBILE_3        EQU     (SKYLINE_MIX_3+7)/8
SKYLINE_TINTE_MOBILI    EQU     SKYLINE_MOBILE_1+SKYLINE_MOBILE_2+SKYLINE_MOBILE_3
; VINCOLO DI TEMPO, da rileggere PRIMA di alzare un mix: il colore deve essere
; scritto prima del primo pixel visibile, che con DIW_H_START $81 cade al color
; clock 64 (129 pixel lores / 2). Ogni MOVE del copper costa 2 cc, quindi il
; blocco vale 8 cc con zero tinte mobili, 16 con una, 24 con due, 32 con tre,
; piu' la contesa col DMA bitplane che parte a DDFSTRT = $18 = 24.
; Il cielo si scrive per PRIMO apposta: uno sforamento colpirebbe solo le tinte
; e si vedrebbe come banda di colore sul bordo SINISTRO della parallasse, mai
; sul cielo. Se non entrasse, la leva e' spostare il WAIT a fine della riga
; PRECEDENTE (H=$DC), come fa gia' il blocco del pannello, cosi' le scritture
; cadono nel blank orizzontale invece che sotto il fetch.

SKY_STEPS               EQU     BG_VIS_ROWS
SKY_WORDS_PER_STEP      EQU     10+8*SKYLINE_TINTE_MOBILI
SKY_COPPER_WORDS        EQU     SKY_STEPS*SKY_WORDS_PER_STEP+2

; INTERRUTTORE: IL CIELO E' UN GRADIENTE O UNA TINTA SOLA
; 1 = il gradiente riga per riga (SkyCopper).
; 0 = una tinta sola, scritta una volta nella palette. Il copper non tocca
;     piu' COLOR00 nell'area di gioco.
; QUANTO COSTA IL GRADIENTE, contato sul sorgente e non a occhio: SKY_STEPS
; (176) passi da SKY_WORDS_PER_STEP (10, perche' i tre SKYLINE_MIX_* sono a
; zero) fanno 1760 word lette dal copper dentro l'area di gioco, cioe' 22
; color clock per riga - un WAIT da 6 e quattro MOVE da 4. Sono 3872 cc, il
; TETTO e' ~17 righe raster su 313: tetto e non costo, perche' il copper toglie
; al blitter solo i cicli che il blitter avrebbe usato davvero.
; La tinta fissa e' quella su cui e' disegnata l'arte della parallasse, ed e'
; la voce 0 dell'anteprima .iff che scrivono i generatori: quel colore adesso
; sta QUI e loro lo LEGGONO, invece di averne una copia per uno.
CIELO_GRADIENTE         EQU     0
CIELO_FISSO_RGB         EQU     $7090c0
CIELO_FISSO_HI  EQU     ((((CIELO_FISSO_RGB>>20)&15)<<8)|(((CIELO_FISSO_RGB>>12)&15)<<4)|((CIELO_FISSO_RGB>>4)&15))
CIELO_FISSO_LO  EQU     ((((CIELO_FISSO_RGB>>16)&15)<<8)|(((CIELO_FISSO_RGB>>8)&15)<<4)|(CIELO_FISSO_RGB&15))
; ---- LE DUE RAMPE DEGLI ALBERI ----
; Uno sprite Amiga ha TRE colori per pixel, e fino al 7 settembre gli alberi ne
; usavano UNO: il valore del pixel portava la profondita' (1 = vicino, 3 =
; lontano) mentre la profondita' e' gia' decisa da QUALE CANALE ospita l'albero.
; Due terzi della palette sprite stavano fermi.
; Adesso il valore porta l'OMBREGGIATURA - 1 ombra, 2 corpo, 3 luce - e la
; profondita' la fa la coppia: coppie 0 e 1 (canali 0..3) i vicini, coppie 2 e 3
; (canali 4..6) i lontani. Costo: zero canali, zero piani, zero chip, zero
; righe raster. Sono le stesse dodici voci che la copperlist scriveva gia'.
;
; ATTENZIONE, VINCOLO PORTANTE: questa divisione vale solo finche' i canali
; 0..3 ospitano vicini e i 4..6 lontani. Se un albero cambiasse canale uscirebbe
; con la rampa sbagliata, e a schermo si vedrebbe un vicino color nebbia.
; Lo controlla tools/genera-alberi-sprite.py, che si rifiuta di generare se la
; mappa canale->livello non e' 1,1,1,1,3,3,3.
;
; Le sei tinte sono DERIVATE, non scelte: il CORPO e' la tinta di sempre, la
; LUCE e' il corpo mescolato al cielo (e' di li' che viene la luce), l'OMBRA e'
; il corpo scalato verso il nero. Cambiando SKYLINE_C1_RGB o SKYLINE_C3_RGB si
; muove tutta la rampa, e non c'e' un secondo posto da aggiornare.
; I DUE LATI NON SONO SIMMETRICI: l'ombra e' piu' marcata della luce, perche' su
; un cielo chiaro scurire AUMENTA il contrasto della sagoma mentre schiarire lo
; riduce. Vedi la nota di SKYLINE_MIX qui sopra: e' lo stesso errore.
ALB_LUCE_MIX		EQU		42			; centesimi di cielo dentro la luce
ALB_OMBRA_VIC		EQU		62			; centesimi del corpo che restano in ombra
ALB_OMBRA_LON		EQU		69			; i lontani sono gia' chiari: meno buio

CIELO_R		EQU		(CIELO_FISSO_RGB>>16)&255
CIELO_G		EQU		(CIELO_FISSO_RGB>>8)&255
CIELO_B		EQU		CIELO_FISSO_RGB&255
ALB_V_R		EQU		(SKYLINE_C1_RGB>>16)&255
ALB_V_G		EQU		(SKYLINE_C1_RGB>>8)&255
ALB_V_B		EQU		SKYLINE_C1_RGB&255
ALB_L_R		EQU		(SKYLINE_C3_RGB>>16)&255
ALB_L_G		EQU		(SKYLINE_C3_RGB>>8)&255
ALB_L_B		EQU		SKYLINE_C3_RGB&255

ALBERI_V_CORPO_RGB	EQU		SKYLINE_C1_RGB
ALBERI_V_OMBRA_RGB	EQU		(((ALB_V_R*ALB_OMBRA_VIC/100)<<16)|((ALB_V_G*ALB_OMBRA_VIC/100)<<8)|(ALB_V_B*ALB_OMBRA_VIC/100))
ALBERI_V_LUCE_RGB	EQU		((((ALB_V_R*(100-ALB_LUCE_MIX)+CIELO_R*ALB_LUCE_MIX)/100)<<16)|(((ALB_V_G*(100-ALB_LUCE_MIX)+CIELO_G*ALB_LUCE_MIX)/100)<<8)|((ALB_V_B*(100-ALB_LUCE_MIX)+CIELO_B*ALB_LUCE_MIX)/100))
ALBERI_L_CORPO_RGB	EQU		SKYLINE_C3_RGB
ALBERI_L_OMBRA_RGB	EQU		(((ALB_L_R*ALB_OMBRA_LON/100)<<16)|((ALB_L_G*ALB_OMBRA_LON/100)<<8)|(ALB_L_B*ALB_OMBRA_LON/100))
ALBERI_L_LUCE_RGB	EQU		((((ALB_L_R*(100-ALB_LUCE_MIX)+CIELO_R*ALB_LUCE_MIX)/100)<<16)|(((ALB_L_G*(100-ALB_LUCE_MIX)+CIELO_G*ALB_LUCE_MIX)/100)<<8)|((ALB_L_B*(100-ALB_LUCE_MIX)+CIELO_B*ALB_LUCE_MIX)/100))

ALB_V_OMBRA_HI	EQU		((((ALBERI_V_OMBRA_RGB>>20)&15)<<8)|(((ALBERI_V_OMBRA_RGB>>12)&15)<<4)|((ALBERI_V_OMBRA_RGB>>4)&15))
ALB_V_OMBRA_LO	EQU		((((ALBERI_V_OMBRA_RGB>>16)&15)<<8)|(((ALBERI_V_OMBRA_RGB>>8)&15)<<4)|(ALBERI_V_OMBRA_RGB&15))
ALB_V_CORPO_HI	EQU		((((ALBERI_V_CORPO_RGB>>20)&15)<<8)|(((ALBERI_V_CORPO_RGB>>12)&15)<<4)|((ALBERI_V_CORPO_RGB>>4)&15))
ALB_V_CORPO_LO	EQU		((((ALBERI_V_CORPO_RGB>>16)&15)<<8)|(((ALBERI_V_CORPO_RGB>>8)&15)<<4)|(ALBERI_V_CORPO_RGB&15))
ALB_V_LUCE_HI	EQU		((((ALBERI_V_LUCE_RGB>>20)&15)<<8)|(((ALBERI_V_LUCE_RGB>>12)&15)<<4)|((ALBERI_V_LUCE_RGB>>4)&15))
ALB_V_LUCE_LO	EQU		((((ALBERI_V_LUCE_RGB>>16)&15)<<8)|(((ALBERI_V_LUCE_RGB>>8)&15)<<4)|(ALBERI_V_LUCE_RGB&15))
ALB_L_OMBRA_HI	EQU		((((ALBERI_L_OMBRA_RGB>>20)&15)<<8)|(((ALBERI_L_OMBRA_RGB>>12)&15)<<4)|((ALBERI_L_OMBRA_RGB>>4)&15))
ALB_L_OMBRA_LO	EQU		((((ALBERI_L_OMBRA_RGB>>16)&15)<<8)|(((ALBERI_L_OMBRA_RGB>>8)&15)<<4)|(ALBERI_L_OMBRA_RGB&15))
ALB_L_CORPO_HI	EQU		((((ALBERI_L_CORPO_RGB>>20)&15)<<8)|(((ALBERI_L_CORPO_RGB>>12)&15)<<4)|((ALBERI_L_CORPO_RGB>>4)&15))
ALB_L_CORPO_LO	EQU		((((ALBERI_L_CORPO_RGB>>16)&15)<<8)|(((ALBERI_L_CORPO_RGB>>8)&15)<<4)|(ALBERI_L_CORPO_RGB&15))
ALB_L_LUCE_HI	EQU		((((ALBERI_L_LUCE_RGB>>20)&15)<<8)|(((ALBERI_L_LUCE_RGB>>12)&15)<<4)|((ALBERI_L_LUCE_RGB>>4)&15))
ALB_L_LUCE_LO	EQU		((((ALBERI_L_LUCE_RGB>>16)&15)<<8)|(((ALBERI_L_LUCE_RGB>>8)&15)<<4)|(ALBERI_L_LUCE_RGB&15))

