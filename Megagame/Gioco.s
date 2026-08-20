*****************************************************************************
*				   MEGA GAME												*
*																			*
*   Inserire effetti sonori e grafiche										*
*	Aggiungere nemici e logica di combattimento								*
*   Aggiungre effetti grafici (es. acqua, luci) 							*
*   Inserire logica di gioco (PF, punti, interfaccia grafica e game over)	*
*   Sviluppo intro 															*
*   Ottimizzazioni varie (es. AI nemici, routine di disegno)				*
*   Aggiungere tutta la mappa di gioco (ora c'e' solo una schermata)		*	
*																			*
*****************************************************************************

	SECTION	MegaGame,CODE

;=====================================================================
; SCROLL HARDWARE (quello che i commenti chiamavano "Path B")
;
; Non esistono piu' GestisciShiftPixel, CopiaVideo e AggiornaTiles: la mappa
; viene disegnata TUTTA all'init dentro SFONDOGRANDE, che e' il buffer
; VISUALIZZATO, e lo scroll e' solo aritmetica sui BPLxPT piu' BPLCON1
; (vedi ScrollHW.i). I BOB non lasciano scie: PathBRestoreAll ripristina
; dal master i rettangoli sporchi del frame precedente.
;
; L'interruttore PATH_B e' stato tolto il 19 agosto 2026: valeva 1 e non
; esisteva piu' nessun ramo alternativo. Il vecchio blocco descriveva lo
; stato del "passo 2", superato da un pezzo.
;=====================================================================

; SWITCH_PIANI: quali piani ausiliari sono ATTIVI a video.
;   0 = nessuno (darkplane e parallasse su buffer vuoto, come al passo 2)
;   1 = solo darkplane
;   2 = solo parallasse
;   3 = entrambi
; Il passo 2b li ha riattivati insieme e il costo e' esploso (WORST da 193
; a 392): con due variabili in gioco non si capisce quale. Questo permette
; di misurarli UNO ALLA VOLTA. Le loro routine girano comunque sempre,
; quindi il costo di calcolo resta nella misura in ogni caso: cambia solo
; chi finisce a video, e quindi quanto lavora il DMA display.
SWITCH_PIANI      EQU     3

	include	"title.i"			; Costanti title screen (TITLE_WIDTH, ...)

*****************************************************************************
	include	"Startup2.i"		; Startup completo AGA + VBR + cache clear
*****************************************************************************
; Con DMASET decidiamo quali canali DMA aprire e quali chiudere

			;5432109876543210
DMASET	EQU	%1000001111100000	; bltr, copper, bitplane, SPRITE ON
;DMASET	EQU	%1000001111100000	; con SPRITE DMA

*****************************************************************************
* COSTANTI
*****************************************************************************
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

; Dimensioni REALI del file, quelle che si leggono con un ls: Omino32.raw e
; Nemico32.raw sono 61440 byte = 384x256 px a 5 piani, cioe' 12288 byte per
; piano. Servono in fase di ASSEMBLAGGIO, dove la struct non esiste ancora:
; dimensionano OMINO_MASK/NEMICO_MASK con ds.b e vanno passate a BuildBobMask.
; La catena BOB_WORDS -> BOB_BLIT_W -> BOB_SLOT_BYTES -> OMINO_PITCH ->
; OMINO_ROWS che portava qui e' stata tolta il 19 agosto 2026: ripeteva in
; aritmetica di EQU le stesse cinque operazioni che DisegnaBOB fa a runtime
; leggendo la struct, quindi la stessa formula viveva in due posti.
OMINO_SHEET_W    	EQU     384				; px, larghezza del file
OMINO_SHEET_H    	EQU     256				; righe del file
PLANE_SIZE       	EQU     (OMINO_SHEET_W/8)*OMINO_SHEET_H	; byte per bitplane

; GUARDIA: le dimensioni dichiarate del file e quelle che discendono dai frame
; devono coincidere. Se cambi BOB_W, BOB_H, OMINO_FRAMES o OMINO_DIR senza
; rifare l'arte (o viceversa), l'assemblaggio si ferma qui invece di produrre
; un gioco che legge i frame agli offset sbagliati. E' la stessa rete gia'
; messa sulla pietra, ed e' il difetto che ha morso piu' volte questo progetto:
; un valore aggiornato e il file no.
OMINO_PITCH_DERIVATO	EQU	(BOB_W/16+1)*2*OMINO_FRAMES		; byte per riga
OMINO_ROWS_DERIVATE		EQU	BOB_H*OMINO_DIR					; righe
ERRORE_OMINO_SHEET_NON_COERENTE	EQU	(OMINO_PITCH_DERIVATO-OMINO_SHEET_W/8)+(OMINO_ROWS_DERIVATE-OMINO_SHEET_H)
	IFNE	ERRORE_OMINO_SHEET_NON_COERENTE
GUARDIA_OMINO_SHEET		EQU	1/0
	ENDC

; Volume di COLLISIONE, deliberatamente separato dalla grafica: la grafica e'
; 32x32 ma il box resta 16x16, cosi' il livello e gli spawn tarati sul box
; piccolo continuano a valere. IsBoxBlocked sonda a passo <=15 px + il bordo,
; quindi funziona per qualunque valore senza saltare tile in mezzo.
; NB: portandoli a BOB_W/BOB_H il nemico 1 (288,48) rientra nel muro di
; tile(18,4) e va rispostato.

BOB_COLL_W       	EQU     BOB_W
BOB_COLL_H       	EQU     BOB_H
; ===================== DIMENSIONI DELLA MAPPA =====================
; Le uniche due manopole del livello. Allargare la mappa vuol dire cambiare
; MAPPA_COLS e aggiungere una colonna a ogni dc.w di MAPPA: tutto il resto
; (pitch del buffer, modulo dello scroll, limiti del player, TILEXMAX,
; dimensione dei buffer) si ricalcola da solo.
; Stanno QUI e non piu' in mezzo alle costanti di gioco perche' SFONDO_PITCH
; ne dipende, e un EQU non puo' riferirsi a un simbolo definito dopo.
MAPPA_COLS 			EQU		25
MAPPA_ROWS			EQU		22

; Origine del mondo dentro il buffer. Definita qui sopra a SFONDO_PITCH
; perche' BG_ORIGIN_X entra nel calcolo del pitch; l'offset composto
; BG_ORIGIN_OFS invece sta piu' giu', perche' dal pitch dipende.
;   X=2 Y=16 : replica esatta di Path A (quello provato)
;   X=0 Y=0  : nessun margine, il mondo parte dall'angolo del buffer
BG_ORIGIN_X			EQU		0				; in BYTE. A 0 la mappa comincia dove
BG_ORIGIN_Y			EQU		0				; comincia la finestra: nessuno sfasamento
; Path B: il world buffer E' quello visualizzato. Pitch 56 = 48 byte di
; mappa (384 px) + 8 di guardia a sinistra per il prefetch del display.
; La mappa vera comincia all'offset DELTA_MAPPAVERA.
; NB: la guardia e' definita QUI e non presa da SCROLL_GUARD_BYTES di
; ScrollHW.i, perche' quel file viene incluso in coda mentre serve gia'
; a DisegnaSfondo, molto piu' su. I due valori devono restare uguali.
DELTA_MAPPAVERA		EQU		8

; Byte che il display fetcha per riga. Deve coincidere con SCROLL_FETCH_BYTES
; di ScrollHW.i, che pero' e' incluso DOPO e qui serve gia' per il pitch.
; Piu' sotto, dopo l'include, c'e' un controllo che ferma l'assemblaggio se i
; due valori divergono.
DISPLAY_FETCH_BYTES	EQU		56

; A che byte della riga punta il display per i piani 7-8 (parallasse).
; NON e' un dettaglio: davanti al puntatore serve una GUARDIA che ospiti
;   - la prima word del blit, che e' contaminata (16 px), e
;   - l'arretramento massimo del display dovuto a BPLCON1 (63 px).
; A +8 la guardia era di soli 64 px: non ci stavano entrambe, ed e' da li' che
; venivano prima la striscia sporca e poi gli 8 px vuoti a sinistra.
; A +16 la guardia e' di 128 px e ci stanno con margine.
PAR_PTR_OFS			EQU		16

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
; Il pitch deve contenere: guardia + origine del mondo + una riga intera di
; mappa, arrotondato al multiplo di 8 richiesto da FMODE=3. Era scritto a
; mano (64): con 56 l'ultima colonna sforava nella riga successiva, e con
; una mappa oltre le 27 colonne anche 64 sarebbe silenziosamente
; insufficiente. Ora si adegua da solo a MAPPA_COLS.
; La riga deve bastare a DUE cose, e si prende la maggiore:
;   - la mappa vera, con la sua guardia a sinistra
;   - la guardia del parallasse piu' i byte che il display fetcha
SFONDO_ROW_MAPPA	EQU		DELTA_MAPPAVERA+BG_ORIGIN_X+MAPPA_COLS*2
SFONDO_ROW_PARAL	EQU		PAR_PTR_OFS+DISPLAY_FETCH_BYTES
	IFGE	SFONDO_ROW_MAPPA-SFONDO_ROW_PARAL
SFONDO_ROW_NEED		EQU		SFONDO_ROW_MAPPA
	ENDC
	IFLT	SFONDO_ROW_MAPPA-SFONDO_ROW_PARAL
SFONDO_ROW_NEED		EQU		SFONDO_ROW_PARAL
	ENDC
SFONDO_PITCH		EQU		((SFONDO_ROW_NEED+7)/8)*8
; I piani 6/7/8 (darkplane e parallasse) DEVONO avere lo stesso pitch dei
; piani 1-5: BPL1MOD e BPL2MOD sono condivisi fra piani dispari (1,3,5,7)
; e pari (2,4,6,8), quindi un pitch diverso farebbe slittare ogni riga.
AUX_PITCH			EQU		SFONDO_PITCH
; Dove finiscono i BOB: in Path B sul world buffer visualizzato.
DEST_PITCH			EQU		SFONDO_PITCH
DEST_PLANE_SZ		EQU		SFONDO_PLANE_SIZE
; Limiti del buffer darkplane, che in Path B e' grande come la mappa e
; non come lo schermo. Erano 11 e 256 scritti a mano.
DARK_MAX_WORDX		EQU		(AUX_PITCH/2)-LIGHT_MASK_W-1
DARK_MAX_ROWS		EQU		SFONDO_HEIGHT
; ORIGINE DEL MONDO nel buffer, sui due assi SEPARATAMENTE.
;
; In Path A CopiaVideo leggeva da SFONDOGRANDE+16*SFONDO_PITCH+2, cioe'
; 16 righe e 16 px (una word) di margine. Ma quei due margini servivano
; al TREADMILL (spazio per lo shift e per AddRigaAlto), e non e' detto
; che le coordinate mondo della LOGICA li includano: sfondo e BOB usano
; la stessa origine, quindi restano allineati fra loro qualunque valore
; si metta qui — cambia solo il rapporto con la griglia delle tile che
; la collisione usa.
;
; TARATURA: prova le combinazioni e guarda il player rispetto alla tile
; su cui appoggia. Ogni unita' di BG_ORIGIN_X vale 8 px, ogni unita' di
; BG_ORIGIN_Y vale una riga.
;   X=2 Y=16 : replica esatta di Path A (quello provato)
;   X=0 Y=0  : nessun margine, il mondo parte dall'angolo del buffer
;   X=0 Y=16 : solo verticale
;   X=2 Y=0  : solo orizzontale
BG_ORIGIN_OFS		EQU		BG_ORIGIN_Y*SFONDO_PITCH+BG_ORIGIN_X
BPSF_PITCH			EQU		48

;---------------------------------------------------------------------
; ALTEZZA DI SFONDOGRANDE
;
; In Path B il buffer contiene TUTTA la mappa e non si sposta mai: sono i
; puntatori dei bitplane a muoversi dentro di lui. Quindi l'altezza non e'
; piu' una manopola di prestazioni ma un fatto geometrico:
;
;   BUFFER_ROWS = MAPPA_ROWS + 1 tile di margine sopra (vedi BG_ORIGIN_OFS)
;   SFONDO_HEIGHT = BUFFER_ROWS * 16
;
; STORIA, perche' i commenti vecchi dicevano un'altra cosa: in Path A il
; buffer era grande quanto l'area visibile piu' due margini
; (BG_MARGIN_TOP_ROWS / BG_MARGIN_BOT_ROWS), e abbassare il margine di sotto
; era LA leva per accorciare gli shift del treadmill, che muovevano tutto il
; buffer a ogni pixel di scroll. Quelle due EQU sono state tolte il 19 agosto
; 2026 perche' non le leggeva piu' nessuno: il treadmill non esiste piu'.
;---------------------------------------------------------------------
; Il taglio era servito a far stare due cose nel blank, quando si correva col
; pennello. Adesso NON e' piu' un vincolo di tempo:
;   - il doppio buffer del mondo toglie la scadenza sui BOB: si pubblica solo
;     a disegno finito, quindi il pennello non vede mai un buffer a meta';
;   - pubblicando la parallasse insieme a BPLCON1 dentro ScrollPathBApply,
;     contenuto e compensazione entrano in vigore nello stesso quadro e SW
;     smette di contare.
; Quindi si riprendono le 32 righe di schermo tagliate. Resta solo il vincolo
; geometrico: BG_VIS_ROWS multiplo di 16, altrimenti TILEYMAX arrotonda per
; difetto e la camera scende oltre il fondo mappa.
CUT_BOTTOM_ROWS		EQU		80				; righe in fondo NON disegnate
											; (documentazione estesa piu' sotto)
BG_VIS_ROWS			EQU		256-CUT_BOTTOM_ROWS		; altezza dell'area di gioco

BUFFER_ROWS			EQU		MAPPA_ROWS+1	; tutta la mappa + 1 tile di margine
											; sopra (vedi BG_ORIGIN_OFS)
SFONDO_HEIGHT		EQU		BUFFER_ROWS*16	; altezza SFONDOGRANDE in righe
SFONDO_PLANE_SIZE 	EQU		SFONDO_PITCH*SFONDO_HEIGHT	; byte/plane

; ---- Parallasse: 1 layer su 2 bitplane = 4 colori (valore 0..3 per pixel) ----
;
; UNICI due valori da toccare: SRC_W e SRC_H, che devono descrivere il file
; caricato dall'incbin "parallasse.raw". Tutto il resto e' derivato: prima
; STRIP_W e STRIP_PITCH erano scritti a mano (976 e 122) e non seguivano
; SRC_W, quindi cambiare la larghezza dell'arte produceva uno skew diagonale
; silenzioso. Se cambi SRC_W, non c'e' piu' niente altro da aggiornare.
;
; VINCOLI: SRC_W multiplo di 16 (la sorgente si indirizza a word); il file
; deve essere planare a piani CONTIGUI, cioe' 2 * SRC_H righe consecutive da
; SRC_PITCH byte.
PARALLAX_SRC_W		EQU		640				; <<< LARGHEZZA REALE di parallasse.raw in px
PARALLAX_SRC_H		EQU		256				; altezza arte: deve essere >= BG_VIS_ROWS
PARALLAX_SRC_PITCH	EQU		PARALLAX_SRC_W/8		; byte per riga, per piano

; La striscia e' l'arte piu' una replica della sua testa, cosi' una blittata
; che parte in fondo continua a leggere dati validi invece di sfondare.
; La replica deve valere almeno una blittata intera: WRAP_W = BLIT_W word.
;
; ALTEZZA: la striscia contiene solo le righe che vengono davvero blittate,
; cioe' BG_VIS_ROWS. Le righe sotto il taglio non si vedono, costruirle
; sarebbe lavoro al boot e chip RAM sprecata. Cosi' il costo della striscia
; segue CUT_BOTTOM_ROWS da solo.
; ATTENZIONE: vale finche' la parallasse NON scorre in verticale (la blittata
; parte sempre dalla riga 0 della striscia). Se un giorno le si desse uno
; scroll Y, la striscia dovra' tornare alta PARALLAX_SRC_H.
; VINCOLO: PARALLAX_SRC_H >= BG_VIS_ROWS (l'arte deve coprire l'area visibile).
; 24 word = i 48 byte che il display fetcha per riga (40 di finestra + 8 di
; prefetch FMODE=3), piu' 1 word di guardia per lo shift = 25.
; Con 21 il blit copriva solo 40 byte: appena BPLCON1 introduceva un ritardo,
; il bordo sinistro pescava nel blocco di prefetch mai scritto -> i primi ~64
; px si riempivano di spazzatura e della word di guardia.
; La larghezza del blit deve coprire ESATTAMENTE i byte che il display fetcha
; per riga (SCROLL_FETCH_BYTES), piu' 1 word di guardia per lo shift.
; Era 25 quando il fetch era di 48 byte; allargando DDF a 56 byte restavano
; scoperti gli ultimi 8 byte = 64 px, che comparivano come margine a destra.
; ScrollHW.i e' incluso dopo, quindi qui il valore va tenuto allineato a mano:
; PARALLAX_BLIT_W = SCROLL_FETCH_BYTES/2 + 1 = 56/2 + 1 = 29
; Larghezza del blit di parallasse, in word. Copre TUTTA la riga del buffer
; (AUX_PITCH = 64 byte = 32 word), non solo la parte che il display "dovrebbe"
; leggere.
; MOTIVO: con ritardo BPLCON1 grande il display ARRETRA oltre il puntatore.
; Il primo pixel visibile e' buffer_pixel(64 + Pf - D) e con Pf~48 a D=63
; diventa il pixel 49, cioe' il byte 6 — che era proprio la word di GUARDIA,
; l'unica che il blitter riempie di spazzatura. Da qui la striscia sporca a
; sinistra, presente solo per D>=48 cioe' CameraX da 1 a 16, e assente da
; fermo (D=0) e a scroll avviato (D<48). Scrivendo tutta la riga, qualunque
; arretramento trova dati validi.
PARALLAX_BLIT_W         EQU     AUX_PITCH/2
PARALLAX_WRAP_W         EQU     PARALLAX_BLIT_W*16      ; 512 px = una blittata
PARALLAX_STRIP_W        EQU     PARALLAX_SRC_W+PARALLAX_WRAP_W		; 1152
PARALLAX_STRIP_PITCH    EQU     PARALLAX_STRIP_W/8      ; 144
PARALLAX_STRIP_ROWS     EQU     BG_VIS_ROWS             ; righe effettivamente blittate
PARALLAX_STRIP_PLANE_SZ EQU     PARALLAX_STRIP_PITCH*PARALLAX_STRIP_ROWS	; un piano della striscia
; Da quale riga dell'arte comincia la striscia. La striscia e' alta
; PARALLAX_STRIP_ROWS (= BG_VIS_ROWS = 176) mentre l'arte ne ha SRC_H (256):
; con ROW0=0 si prendono le PRIME 176 righe e le ultime 80 restano fuori.
; Se il fondale ha cielo vuoto in cima, alzare ROW0 fa scendere l'arte e
; riempie il margine superiore. Range utile: 0 .. SRC_H-STRIP_ROWS = 0..80.
; MISURATO su parallasse.raw (40960 byte = 2 piani x 256 x 80, layout corretto):
; il contenuto sta nelle righe 11..255, con le PRIME 11 righe completamente
; vuote su entrambi i piani e nessuna riga vuota in fondo o in mezzo.
; Partendo da 0 quelle 11 righe finivano in cima allo schermo come margine.
; Con ROW0=11 la striscia prende le righe 11..186 dell'arte: il margine
; superiore si chiude e il fondale resta continuo fino in basso.
; Range utile 0..80 (= SRC_H - STRIP_ROWS): alzarlo ancora fa scorrere
; l'inquadratura verso il basso, la densita' dell'arte e' uniforme (16-30%)
; quindi e' solo una scelta estetica.
; NOTA STORICA: qui c'era PARALLAX_ORIGIN_ADJ, che cercava di sottrarre dal
; l'offset la distanza in pixel fra il puntatore dei piani 7-8 e il primo pixel
; visibile. Provata a 64 e poi a 57, lasciava sempre una striscia sporca larga
; qualche pixel sul bordo sinistro, perche' quel numero non si riusciva a
; misurare in modo affidabile e sbagliarlo mandava l'offset NEGATIVO: il mod
; lo riportava a ~633 e i primi pixel mostravano il bordo DESTRO dell'arte.
;
; Non serve conoscere quella distanza. Chiamandola Pf, lo schermo x=0 mostra
; sempre il pixel (offset + Pf - D) dell'arte. Ponendo offset = (CameraX>>1) +
; D + MARGINE, la D si annulla da sola e resta (CameraX>>1) + MARGINE + Pf:
; il fondale scorre ESATTAMENTE a meta' velocita' qualunque sia Pf, e l'unico
; effetto di Pf e' QUALE colonna dell'arte si vede per prima — cioe' una
; scelta di inquadratura, non un difetto.
; Cosi' l'offset resta fra 16 e ~119, non e' mai negativo e non wrappa mai:
; la giunzione fra arte e replica non entra piu' nella finestra.
;
; Il margine serve solo a tenere R = (offset-1)>>4 non negativo, cioe' a non
; far leggere al blitter la word prima dell'inizio della striscia.
; Alzandolo si scorre l'inquadratura verso destra dentro l'arte: servono al
; massimo le colonne (MARGINE + Pf + 375), che con MARGINE 16 e Pf fino a 128
; fanno 519 su 640 disponibili.
; Di quante word arretra la SORGENTE, ora che la destinazione parte dalla word
; 0 invece che dalla word 3. Sono 3, non 4: la word che finisce a byte 8 deve
; restare la stessa di prima. Con 4 l'inquadratura slittava di 16 px.
PAR_GUARD_WORDS         EQU     PAR_PTR_OFS/2-1

; Margine a sinistra dell'offset. Deve tenere (R - PAR_GUARD_WORDS) >= 0,
; altrimenti il blit leggerebbe prima dell'inizio della striscia: serve
; offset >= PAR_GUARD_WORDS*16 + 1 = 49. Con 80 c'e' un giro di margine.
; Alzandolo si scorre l'inquadratura verso destra dentro l'arte.
PARALLAX_LEFT_MARGIN    EQU     128
PARALLAX_SRC_ROW0       EQU     11
PARALLAX_SRC_HEAD       EQU     PARALLAX_SRC_PITCH*PARALLAX_SRC_ROW0	; righe saltate PRIMA
; ATTENZIONE: lo SKIP fra un piano e l'altro NON dipende da ROW0. HEAD viene
; applicato una volta sola prima del loop, quindi dopo aver copiato
; STRIP_ROWS righe bisogna avanzare di (SRC_H - STRIP_ROWS) righe per trovarsi
; alla STESSA riga relativa del piano successivo. Sottraendo anche ROW0 il
; secondo piano ripartiva dalla riga 0: due piani sfasati di ROW0 righe, cioe'
; i quattro colori del fondale mescolati.
PARALLAX_SRC_SKIP       EQU     PARALLAX_SRC_PITCH*(PARALLAX_SRC_H-PARALLAX_STRIP_ROWS)	; coda non copiata

; PROVA DI MICHELE: il blitter lascia dati sporchi nella prima colonna quando
; fa lo shift fine. A 1 l'offset viene arrotondato a multipli di 16, quindi
; ASH vale sempre 0 e il blit NON shifta: non c'e' nulla da far entrare da
; sinistra e la prima word non puo' essere sporca.
;   la striscia SPARISCE -> confermato, e' il primo word del blit shiftato.
;                           Si risolve spostando la guardia piu' a sinistra,
;                           non rinunciando allo shift fine.
;   la striscia RESTA     -> non e' il blit, e il difetto e' altrove.
; PREZZO durante la prova: la parallasse si muove a scatti di 16 px invece che
; fluida. E' brutta ma serve solo a rispondere alla domanda.
PARALLAX_NO_FINE        EQU     0

; PROVA SUCCESSIVA: a 1 i piani 7-8 vengono puntati su PathBVuoto invece che
; sul buffer di parallasse, cioe' la parallasse e' SPENTA. Serve a capire da
; quali piani venga davvero la striscia sporca a sinistra, come si era fatto
; col darkplane.
;   la striscia SPARISCE -> viene dai piani 7-8, cioe' dal percorso parallasse
;   la striscia RESTA    -> viene dai piani 1-5 del mondo, e il sospetto sono
;                           gli 8 byte di guardia a inizio riga (DELTA_MAPPAVERA)
;                           che DisegnaSfondo non tocca mai
PAR_DISABLE             EQU     0

; PROVA A MOTIVO REGOLARE: a 1 la striscia viene riempita con un motivo a
; BANDE VERTICALI da 8 px ($FF00 ripetuto), invece che con l'arte.
;
; Il riempimento uniforme precedente aveva un limite: con tutti i pixel uguali
; una colonna sbagliata e' indistinguibile da una giusta, quindi diceva solo
; che il display non legge fuori dal buffer. Con le bande il motivo E' un
; righello: sullo schermo devono comparire bande di 8 px perfettamente
; regolari per tutta la larghezza.
;   bande regolari ovunque -> il percorso e' sano fin dentro il contenuto, e
;     l'artefatto viene da quello che ci scrive BuildParallaxStrip
;   una banda di larghezza SBAGLIATA sul bordo sinistro -> li' il display
;     legge una colonna della striscia fuori sequenza, e la larghezza della
;     banda anomala dice di quanto
PAR_TEST_FILL           EQU     0
PAR_TEST_PATTERN        EQU     $FF00FF00
; PAR_TEST_MODE: 1 = bande VERTICALI da 8 px (motivo uguale su tutte le righe)
;                2 = strisce ORIZZONTALI da 1 riga, alternate piene e vuote
; Le bande verticali hanno un punto cieco: essendo identiche riga per riga,
; NON mostrerebbero un errore di RIGA. Le strisce orizzontali fanno l'opposto:
; se una parte dello schermo legge da una riga sbagliata, li' le strisce vanno
; in controfase e si vede subito.
PAR_TEST_MODE           EQU     2
;
; Era 64 — il blocco di prefetch teorico — ma il valore VERO misurato e' 57.
; Come si e' visto: correlando parallasse.raw con lo screenshot, le colonne
; 0..6 dello schermo avevano accordo 82-89% contro il 93-96% dalla 7 in poi,
; con un taglio verticale netto a x=7 e una scheggia isolata a x=6.
; Meccanica: con ADJ=64 e prefetch reale 57, la finestra parte dal pixel
; (P-7) dell'arte, che a camera quasi ferma diventa NEGATIVO e wrappa a 633.
; Cosi' i primi pixel mostravano le colonne 633..639 — il bordo DESTRO
; dell'immagine, che non e' continuo col bordo sinistro — e poi la cucitura.
; Compariva solo con P < 7, cioe' CameraX < 14: all'estremo sinistro della
; mappa, ed e' per questo che si vedeva solo all'innesco dello scroll.
; Con ADJ = 57 la finestra parte esattamente dal pixel P dell'arte. L'offset
; passa ancora per la zona di replica (a camera ferma vale 583 e la finestra
; cade in strip 640..975, cioe' tutta nella replica), ma NON attraversa piu'
; la giunzione fra arte e replica: quella cade esattamente a schermo x=0, con
; nulla alla sua sinistra. Servono al massimo le colonne 0..375 dell'arte
; (P max 40 piu' 336 di finestra), e la replica ne copre 464: sempre coperta.
;
; TARATURA: se restasse una scheggia larga k px sul bordo sinistro, il valore
; giusto e' 57-k. La larghezza del residuo E' l'errore.

; --- gradiente cielo generato al boot -------------------------------------
; Un cambio colore per riga visibile. Ogni passo sono 10 word:
;   WAIT(riga)  +  BPLCON3 LOCT=1 + COLOR00 basso  +  BPLCON3 LOCT=0 + COLOR00 alto
; piu' 2 word in coda per lasciare BPLCON3 a LOCT=0 (stato di riposo).
SKY_STEPS               EQU     BG_VIS_ROWS
SKY_WORDS_PER_STEP      EQU     10
SKY_COPPER_WORDS        EQU     SKY_STEPS*SKY_WORDS_PER_STEP+2

; ============================================================
; Pannello.i - generato da png2amiga.py
; ============================================================
PANNELLO_HEIGHT			EQU     80
PANNELLO_BITPLANES		EQU     4
PANNELLO_BYTES_PER_ROW	EQU     40
; Era il letterale 3200, cioe' 40*80 gia' fatto a mano: lo stesso genere di
; numero scritto una volta e poi mai piu' ricontrollato che su Pietra.raw
; era arrivato sbagliato (bit invece di byte). Ora discende dalle due misure.
PANNELLO_PLANE_SIZE		EQU     PANNELLO_BYTES_PER_ROW*PANNELLO_HEIGHT

; --- collocazione e buffer di visualizzazione ---
; Il pannello sta nella fascia CUT_BOTTOM_ROWS, cioe' subito sotto l'area di
; gioco: dalla riga raster $2C+BG_VIS_ROWS in giu'. Con CUT_BOTTOM_ROWS=80 e
; PANNELLO_HEIGHT=80 la fascia viene riempita esattamente.
PANNELLO_TOP_RASTER		EQU		$2C+BG_VIS_ROWS
; Righe di separazione fra area di gioco e arte del pannello, a bitplane SPENTI.
; NON sono estetica: servono a due cose che non stanno da nessun'altra parte.
; 1) LA PALETTE. Il pannello usa i colori 0-15, che nell'area di gioco sono
;    quelli delle tile, quindi va ricaricata al confine. A 24 bit sono 16 MOVE
;    per i nibble alti piu' 16 per i bassi piu' 3 BPLCON3 = 35 MOVE = 70 cc.
;    Sulla prima riga del pannello ci sono solo 64 cc prima della parte
;    visibile, e 18 se ne vanno in puntatori e BPLCON0: non ci sta.
; 2) LA CORSA COL DMA sui puntatori. Su una riga senza bitplane attivi non c'e'
;    auto-incremento, quindi i puntatori scritti restano dove li mettiamo e la
;    compensazione non serve piu'.
; Costano due righe di raster, non due righe di pannello: la fascia si allunga.
PANNELLO_SEP_ROWS		EQU		2
PANNELLO_ART_RASTER		EQU		PANNELLO_TOP_RASTER+PANNELLO_SEP_ROWS
PANNELLO_BOT_RASTER		EQU		PANNELLO_ART_RASTER+PANNELLO_HEIGHT

; Il buffer di visualizzazione ha lo STESSO pitch del mondo, non 40 byte: cosi'
; il display usa gli stessi BPLxMOD e la stessa geometria DDF/DIW, e al confine
; bastano i puntatori e il numero di piani.
; L'arte viene blittata a DELTA_MAPPAVERA byte dall'inizio di ogni riga, cioe'
; dove comincia la mappa: il pannello si vede esattamente come si vedrebbe il
; mondo a CameraX=0.
PANNELLO_BUF_PITCH		EQU		SFONDO_PITCH
PANNELLO_BUF_PLANE		EQU		PANNELLO_BUF_PITCH*PANNELLO_HEIGHT

; PROVA: colore di fondo della fascia pannello, scritto dal copper.
; A $0F0F (magenta acceso) serve a capire se il copper ARRIVA al blocco:
;   fascia MAGENTA -> il copper esegue il blocco e la finestra copre la zona,
;                     quindi il difetto e' nel bitmap o nei puntatori
;   fascia NERA    -> il copper non ci arriva, oppure la finestra verticale
;                     non copre quelle righe: si guarda DIWSTOP e il WAIT
; Valore definitivo: $0000 (nero).
; PROVA: a 1 il pannello viene riempito con costanti invece che con l'arte.
; Byte dall'inizio della riga a cui viene messa l'arte dentro PannelloBuf.
; MISURATO con la prova a costanti: riempiendo da DELTA_MAPPAVERA restavano
; 61 px a sinistra col solo piano 0, cioe' circa 8 byte non coperti. La
; finestra parte dal BYTE 0 della riga, non dal byte 8 come nel mondo (dove il
; puntatore include l'offset di camera). Quindi qui l'arte va all'inizio.
; Se restasse una striscia a sinistra, la sua larghezza in px diviso 8 e'
; esattamente quanto va aggiunto a questo valore.
PANNELLO_ART_BYTE_OFS	EQU		0

; Posizione orizzontale del WAIT che precede la scrittura dei puntatori del
; pannello. E' il valore piu' delicato del blocco, e va spiegato.
; MISURATO: invertendo l'ordine di scrittura dei quattro puntatori, i piani
; che sparivano si sono invertiti anche loro. Quindi e' una CORSA col DMA e a
; perdere sono sempre i PRIMI scritti: prendono un incremento di 8 byte, che
; a schermo sono i 64 px mancanti.
; PERCHE': DDFSTOP e' $d8 = 216 e con 8 bitplane in FMODE=3 l'ultimo blocco ha
; 8 accessi, circa 16 cc, quindi finisce verso 232. La linea PAL ne ha 227:
; il fetch della riga precedente SFORA di ~5 cc dentro la riga del pannello.
; La finestra tranquilla va quindi da cc 5 a DDFSTRT (24): 19 cc, cioe' 9 MOVE.
; Servono esattamente 9 MOVE: BPLCON0 piu' i quattro puntatori.
; TARATURA: se mancano ancora dei piani, ALZARE questo valore di 2 alla volta
; (il fetch precedente finisce piu' tardi del previsto); se invece si rompe
; tutto, ABBASSARLO (le scritture non fanno in tempo prima di DDFSTRT).
PANNELLO_PTR_WAIT_H		EQU		$E0

; COMPENSAZIONE DELLA CORSA COL DMA.
; MISURATO due volte, e la seconda con l'ordine invertito che ha spostato il
; difetto sugli altri piani: i primi PANNELLO_PTR_RACE_N puntatori scritti dal
; copper prendono un incremento di PANNELLO_PTR_RACE_ADJ byte, perche' il DMA
; bitplane della riga precedente non ha ancora finito. A schermo sono i 64 px
; in cui quei piani mancano.
; Non riesco a spostare le scritture in una finestra sicura senza bloccare la
; macchina, quindi si compensa: ai primi N puntatori si sottrae in partenza
; esattamente quello che il DMA aggiungera'.
; TARATURA: se restano px con piani mancanti a DESTRA, alzare RACE_N; se
; compaiono a SINISTRA, abbassarlo. A 0 la compensazione e' disattivata.
PANNELLO_PTR_RACE_N		EQU		0	; non serve piu': le righe di separazione non fanno fetch
PANNELLO_PTR_RACE_ADJ	EQU		8

; PROVA a costanti invece dell'arte: vedi DisegnaPannello. A 0 disegna l'arte.
PANNELLO_TEST_FILL		EQU		0	; 1 = costanti al posto dell'arte (diagnostica)

PANNELLO_TEST_COLOR		EQU		$0000	; nero: il gradiente cielo finisce sopra

; ============================================================
; pietra.i - generato da png2amiga.py
; ============================================================
; ATTENZIONE: PIETRA_PLANE_SIZE generato dallo script valeva 4096, che sono i
; BIT di un piano (512 byte x 8), non i byte. Il file vero e' 2560 byte =
; 5 piani x 512, quindi il valore corretto e' 512. Lasciarlo a 4096 faceva
; avanzare il puntatore di piano di 8 volte troppo e leggere fuori dal file.
; VERIFICATO decodificando Pietra.raw: 256x16 px, 5 bitplane contigui,
; 8 frame da 32 px di slot, arte nei primi 16 px di ogni slot, padding
; destro completamente vuoto (stessa convenzione di Omino32/Nemico32),
; UNA sola banda (nessuna direzione), indici di palette usati 24/25/27
; (grigi $0777/$0888/$0aaa della rampa 20-31 in Tiles.cop).
; Dimensioni REALI del file, come per lo sheet dell'omino: Pietra.raw e'
; 2560 byte = 256x16 px a 5 piani, cioe' 512 byte per piano.
PIETRA_SHEET_W        EQU     256				; px, larghezza del file
PIETRA_SHEET_H        EQU     16				; righe del file
PIETRA_BYTES_PER_ROW  EQU     PIETRA_SHEET_W/8			; 32 byte per riga
PIETRA_PLANE_SIZE     EQU     PIETRA_BYTES_PER_ROW*PIETRA_SHEET_H	; 512 byte/piano

; --- Descrizione dell'ASSET: e' da qui che InitPietra riempie la struct ---
; L'arte occupa i primi 16 px dello slot; il resto e' lo stacco che serve
; allo shift orizzontale, esattamente come per BOB_W nello sheet dell'omino.
; PIETRA_H era scritta come alias di PIETRA_HEIGHT: coincidono solo perche'
; lo sheet ha UNA banda, quindi altezza del file e altezza del fotogramma
; sono lo stesso numero per caso, non per regola. Ora sono separate.
PIETRA_W			EQU		16				; larghezza arte (px)
PIETRA_H			EQU		16				; altezza arte (px)
PIETRA_FRAMES		EQU		8				; frame di animazione (potenza di 2)
PIETRA_BANDE		EQU		1				; una sola banda: nessuna direzione

; GUARDIA: stessa rete dell'omino. La precedente confrontava SOLO il pitch;
; le righe no, quindi un PIETRA_BANDE sbagliato sarebbe passato liscio e i
; frame sarebbero finiti a offset buoni su una sheet alta il doppio.
PIETRA_PITCH_DERIVATO	EQU	(PIETRA_W/16+1)*2*PIETRA_FRAMES		; byte per riga
PIETRA_ROWS_DERIVATE	EQU	PIETRA_H*PIETRA_BANDE				; righe
ERRORE_PIETRA_SHEET_NON_COERENTE	EQU	(PIETRA_PITCH_DERIVATO-PIETRA_BYTES_PER_ROW)+(PIETRA_ROWS_DERIVATE-PIETRA_SHEET_H)
	IFNE	ERRORE_PIETRA_SHEET_NON_COERENTE
GUARDIA_PIETRA_SHEET	EQU	1/0
	ENDC


; MAPPA_COLS / MAPPA_ROWS sono definite PIU' SU (prima di SFONDO_PITCH, che
; ora ne discende). Qui restano solo le costanti che dipendono da loro.
BUFFER_COLS			EQU		MAPPA_COLS		; Path B: il buffer contiene TUTTA la mappa
; BUFFER_ROWS e' definita in testa al file, nel blocco "ALTEZZA DI
; SFONDOGRANDE": vale MAPPA_ROWS+1, cioe' tutta la mappa piu' il margine.
; Finestra orizzontale di display. Allargata di 8 px per lato ($81/$C1 ->
; $79/$C9) per coprire le due strisce in cui si vedeva COLOR00 al posto del
; playfield. La DIW passa da 320 a 336 px = 21 tile, e con essa VIS_COLS.
; PREZZO: la camera scorre 16 px in meno (da 80 a 64), cioe' una tile.
; NB: allargando la vista CameraX max scende, quindi il puntatore di display
; avanza al massimo di un blocco invece di due e SFONDO_PITCH resta 64.
; PROVA: la finestra e' spostata a DESTRA di 16 px (start $79->$89, stop
; $C9->$D9), lasciando la larghezza invariata a 336. Il fetch NON cambia
; (DDFSTRT $18, DDFSTOP $d8), quindi cambia solo la distanza fra inizio fetch
; e inizio finestra.
; Misurato che i primi 7 px di ogni riga mostrano la parallasse sfasata di UNA
; RIGA: e' il residuo dell'ultimo fetch della riga precedente.
;   la striscia SPARISCE o si stringe -> e' ancorata al FETCH, e si sistema
;     con la geometria DDF/DIW
;   la striscia RESTA identica a sinistra -> e' ancorata alla FINESTRA, e
;     allora l'unica via e' mascherare quei pixel
; Valori originali: START $79, STOP $C9.
; ANTICIPO DEL FETCH. DDFSTRT e' gia' al minimo hardware ($18 = pixel 48),
; quindi l'unico modo di dare piu' respiro al pipeline e' far cominciare la
; finestra piu' tardi:
;     anticipo = DIW_H_START - 48,  e serve che superi il ritardo BPLCON1 max
; Con FMODE=3 il puntatore si muove a blocchi di 64 px, quindi BPLCON1 deve
; coprire 0..63. A $79 l'anticipo era 73 px, cioe' solo 10 px oltre il ritardo
; massimo — e proprio a ritardo grande comparivano 7 px sporchi a sinistra.
; A $89 l'anticipo sale a 89 px, 26 oltre il massimo.
; La larghezza resta 336: si sposta anche lo STOP della stessa quantita'.
; POSIZIONE DELLA FINESTRA. Il dato del primo pixel arriva a
;     DDFSTRT*2 + LATENZA + D
; dove LATENZA e' il ritardo di pipeline con FMODE=3 e D il ritardo BPLCON1.
; Se la finestra apre PRIMA, i primi pixel non hanno ancora dati e restano
; vuoti — ed e' proprio quello che si vedeva: nessuna banda a riposo (D=0) e
; 6 px vuoti a ritardo massimo (D=63).
; LATENZA misurata da li': 6 = 48 + LATENZA + 63 - 137  ->  LATENZA = 32 px.
; Serve quindi DIW_H_START >= 48+32+63 = 143.
; A destra il vincolo opposto: la finestra deve finire entro il dato
; disponibile, cioe' DDFSTRT*2 + 7*64 = 496. Con 336 px di larghezza il valore
; deve stare fra 143 e 160: $97 = 151 lascia 8 px di margine a sinistra e 9 a
; destra, il compromesso piu' centrato.
; VALORE INCHIODATO DA UNA MISURA, non piu' stimato. Col monitor acceso si e'
; letto DL=62 (ritardo BPLCON1) e PO=191 (offset parallasse) nello STESSO
; istante in cui la banda vuota misurava 7 px. Da li':
;     banda = D - (DIW_H_START - DDFSTRT*2 - LATENZA)
;     7 = 62 - (151 - 48 - LATENZA)   ->   LATENZA = 48 px
; Verificato all'indietro su tutte le misure precedenti: i ritardi che ne
; risultano (47, 49, 32) sono posizioni di camera plausibili.
;
; Perche' la banda sia SEMPRE nulla serve DIW >= 48 + 48 + 63 = 159.
; A destra la finestra deve stare dentro il dato fetchato, 48 + 7*64 = 496,
; quindi DIW <= 496 - 336 = 160.
; La finestra utile e' 159..160: si prende 160, che azzera la banda anche al
; ritardo massimo e fa finire il display esattamente sull'ultimo pixel
; disponibile.
; NB: e' un incastro ESATTO, senza margine a destra. Se il bordo destro
; mostrasse problemi, la slack si ottiene solo restringendo la finestra
; (VIS_COLS 21 -> 20 libera 16 px da distribuire fra i due lati).

; FINESTRA ORIZZONTALE. Valori trovati SUL FERRO, non da un modello: sono gli
; stessi della schermata del titolo, e con BRDRBLNK acceso danno bordi neri
; stretti e nessuna colonna sporca a sinistra all'innesco dello scroll.
;
; Storia, per non ripetere il giro: avevo costruito un modello
;     banda = ritardoBPLCON1 - (DIW_H_START - DDFSTRT*2 - LATENZA)
; tarato su una misura col monitor (DL=62, PO=191, banda 7 px -> LATENZA 48).
; Tornava su tutte le misure passate ma ha PREDETTO MALE questo caso: dava
; fino a 30 px di banda a $81, e invece $81 e' pulito. Era un modello adattato
; ai dati, non verificato. Se il difetto tornasse, ripartire da una misura
; nuova col monitor, non da quella formula.
; Riga raster in cui apre la finestra. Gli sprite ci si agganciano: VSTART
; e HSTART si misurano da qui, non da valori cablati.
DIW_V_START			EQU		$2C
DIW_H_START			EQU		$81
DIW_H_STOP			EQU		$C1				; +256 = 449, quindi finestra 129..449 = 320 px
; DERIVATA dalla finestra, non piu' cablata: e' la larghezza visibile in tile.
; Non dice quanto si DISEGNA (il mondo e' disegnato tutto e il fetch porta 448
; px per riga): dice alla logica quanto si VEDE, e da qui dipendono TILEXMAX,
; CENTER_X e il cull dei BOB. Se non combacia con la finestra vera, la camera
; scorre oltre il bordo mappa e il cull sbaglia.
VIS_COLS			EQU		(DIW_H_STOP+256-DIW_H_START)/16

; GUARDIA: l'arte del pannello deve essere larga esattamente quanto la
; finestra visibile. Piu' stretta lascia una striscia di COLOR00 a destra,
; piu' larga fa leggere oltre la riga. Sta QUI e non nel blocco del pannello
; perche' DIW_H_START/STOP sono definite piu' su ma VIS_COLS le riassume.
ERRORE_PANNELLO_LARGO_DIVERSO_DALLA_FINESTRA	EQU	PANNELLO_BYTES_PER_ROW*8-(DIW_H_STOP+256-DIW_H_START)
	IFNE	ERRORE_PANNELLO_LARGO_DIVERSO_DALLA_FINESTRA
GUARDIA_PANNELLO_LARGHEZZA	EQU	1/0
	ENDC

; TILEXMAX / TILEYMAX = numero massimo che TileX/TileY puo' raggiungere.
; Il buffer carica MAPPA[TileY..TileY+BUFFER_ROWS-1][TileX..TileX+BUFFER_COLS-1],
; quindi TileX+BUFFER_COLS-1 <= MAPPA_COLS-1  =>  TileX <= MAPPA_COLS-BUFFER_COLS.
; Con mappa 18x24 e buffer 18x22 => TILEXMAX=2, TILEYMAX=0 (no scroll Y di tile).
; Per abilitare lo scroll Y di tile: estendi MAPPA a >=20 righe e aggiorna MAPPA_ROWS.

; Path B: il buffer contiene tutta la mappa, quindi il limite non e' piu'
; il buffer ma quanto se ne vede a schermo.
TILEXMAX			EQU		MAPPA_COLS-VIS_COLS
TILEYMAX			EQU		MAPPA_ROWS-(BG_VIS_ROWS/16)
; Limiti in coordinate MONDO: il bordo VERO della mappa. Il player si ferma
; quando il suo box tocca il confine, non prima. C'era un -32 cablato che lo
; bloccava due tile prima: a fermarlo dove serve ci pensano gia' IsBoxBlocked
; (tile) e IsOverlapEnemies (nemici), controllati subito dopo questo clamp.
PLAYER_MAX_X    	EQU		(MAPPA_COLS*16)-BOB_COLL_W
PLAYER_MAX_Y    	EQU		(MAPPA_ROWS*16)-BOB_COLL_H
PLAYER_SPAWN_X  	EQU		48					; spawn in coordinate MONDO: tile (3,3), libera
PLAYER_SPAWN_Y  	EQU		48

; --- Fisica platform (visto di lato) ---
; La verticale del player e' in VIRGOLA FISSA 8.8 (256 = un pixel per frame),
; come la parabola della pietra. Serviva per poter chiedere due cose insieme:
; un salto PIU' BASSO e PIU' LENTO. A gravita' intera non si puo': con
; accelerazione fissa l'apice vale v^2/(2g) e la durata v/g, quindi abbassando
; l'apice si accorcia per forza anche il tempo. Con la gravita' frazionaria i
; due parametri tornano indipendenti.
;
; Storia dei valori, per riferimento: si era partiti da -8 interi (apice 28 px,
; poco piu' di una tile), poi -14 (91 px, cinque tile, 14 frame di salita).
; Ora 70 px in 21 frame: 2,5 volte l'altezza originale e salita piu' lenta.
;
; TARATURA: apice = JUMP_VEL^2/(2*GRAVITA_88), salita = JUMP_VEL/GRAVITA_88
; frame. Simulato con la stessa aritmetica del 68000, gravita' a parita' di
; JUMP_VEL=1792 (7,0 px/frame):
;   gravita 80 -> 75 px in 23 frame       gravita 86 -> 70 px in 21 frame
;   gravita 84 -> 72 px in 22 frame       gravita 88 -> 68 px in 21 frame
; Le tile sono 16 px: a 70 px se ne scavalcano 4 con 6 px di margine.
GRAVITA_88		EQU		86		; 0,336 px/frame^2 in 8.8
MAX_FALL_88		EQU		8*256	; 8 px/frame di caduta massima (invariata)
JUMP_VEL_88		EQU		-1792	; 7,0 px/frame verso l'alto (negativa = su)
CAM_STEP_Y		EQU		8		; passo scroll verticale camera (px/frame, DEVE dividere 16: 1/2/4/8)
CAM_DEADZONE_Y	EQU		8		; tolleranza verticale camera (>= CAM_STEP_Y per evitare oscillazione)

;------------------------------------------------------------
; Costanti tasti freccia (identici ai rawkey Intuition)
;------------------------------------------------------------
RAWKEY_UP			EQU 	$4C
RAWKEY_DOWN			EQU 	$4D
RAWKEY_RIGHT		EQU 	$4E
RAWKEY_LEFT		 	EQU 	$4F
RAWKEY_SPACE		EQU 	$40
RAWKEY_N			EQU 	$36			; rawkey del tasto N (toggle giorno/notte)
RAWKEY_M			EQU 	$37			; rawkey del tasto M (toggle musica)
RAWKEY_G			EQU 	$24			; rawkey del tasto G (toggle gravita' / 8-direzioni)
RAWKEY_P			EQU 	$19			; rawkey del tasto P (mostra/nascondi i numeri del profilo)
RAWKEY_R			EQU 	$13			; rawkey del tasto R (azzera gli high-water del profilo)

KEY_RELEASE_BIT 	EQU 	7	   		; bit 7 del keycode decodificato
; Passo di animazione di DEFAULT, copiato in bob_AnimDelay dalle Init. Non e'
; piu' la legge per tutti: ogni bob puo' avere il suo.
ANIM_DELAY			EQU 	3

; ----- Bullet (proiettile sprite hardware) -----
BULLET_COOLDOWNC	EQU		10			; frame di cooldown tra due spari

; ----- PARABOLA DELLA PIETRA -----
; La pietra e' LANCIATA, non sparata: parte a 30 gradi sull'orizzontale e
; cade. Le velocita' sono in VIRGOLA FISSA 8.8 (256 = un pixel per frame),
; perche' a 30 gradi servono 4,57 px/frame in verticale contro 7,91 in
; orizzontale, e senza parte frazionaria quel rapporto non si esprime: coi
; soli interi 5 e 8 l'angolo diventerebbe 32 gradi e la gittata sbaglierebbe.
;
; I conti, per poterli rifare se cambi la gittata:
;   tempo di volo T = 2*vy/g          (sale e riscende alla stessa quota)
;   gittata       R = vx*T = 2*vx*vy/g
;   a 30 gradi    vy = vx*tan(30) = vx*0,5774
;   da cui        R = 2*vx^2*0,5774/g
;
; TARATURA — il dettaglio che sballa i conti se lo si dimentica: la pietra NON
; parte da terra, parte dal CENTRO del player, quindi per toccare il suolo deve
; scendere anche i 16 px che la separano dai piedi. La formula qui sopra da' la
; gittata "da pari a pari" e sottostima quella vera: i valori sotto sono tarati
; sul volo COMPLETO, quello che finisce 16 px piu' in basso di dove e' partito.
; Tarando sulla formula pura, a 8 word la pietra atterrava a 147 invece di 128 e
; il tetto la tagliava mentre scendeva — una sparizione a mezz'aria che sembra
; un difetto di disegno.
;
; NOTA SULLA FORMA: a 30 gradi l'apice sta sempre a circa un settimo della
; gittata, qui 32 px su 256. E' un lancio TESO, non una campana: allungare la
; gittata alza l'apice in proporzione ma non cambia la forma. Per una campana
; serve alzare l'ANGOLO — a 45 gradi l'apice sarebbe un quarto della gittata.
PIETRA_RAGGIO		EQU		16*16		; 16 word = 256 px di gittata massima
PIETRA_GRAVITA		EQU		42			; 0,164 px/frame^2 in 8.8
PIETRA_VEL_X		EQU		1456		; 5,69 px/frame in 8.8
PIETRA_VEL_Y		EQU		841			; 3,29 px/frame in 8.8, verso l'ALTO
; verifica dell'angolo: vy/vx = 841/1456 = 0,5776 contro tan(30) = 0,5774,
; cioe' 30,01 gradi. Simulato con la stessa aritmetica intera del 68000:
; apice 32 px, suolo (16 px sotto il lancio) al frame 44 a 250 px, tetto della
; gittata piu' in la'. E' la tile a fermarla, come deve essere.
;
; RALLENTATA su richiesta: velocita' da 7,91 a 5,69 px/frame (0,72x) e gravita'
; abbassata in proporzione per tenere la stessa gittata di 16 word. Il volo
; passa da 32 a 44 frame, cioe' da 0,64 a 0,88 secondi. La FORMA dell'arco non
; cambia: a 30 gradi dipende solo dall'angolo, non dalla velocita'.

; GUARDIA: l'arco che sale e torna alla QUOTA DI PARTENZA deve gia' stare
; dentro la gittata. Se non ci sta, la pietra viene tagliata dal tetto mentre
; e' ancora in aria e sembra sparita per un difetto di disegno.
PIETRA_VOLO_FRAMES	EQU		(2*PIETRA_VEL_Y)/PIETRA_GRAVITA		; frame per tornare a quota
PIETRA_GITTATA		EQU		(PIETRA_VEL_X*PIETRA_VOLO_FRAMES)/256	; px percorsi
	IFGT	PIETRA_GITTATA-PIETRA_RAGGIO
GUARDIA_PIETRA_GITTATA	EQU	1/0
	ENDC
BULLET_DAMAGE		EQU		2			; danno inflitto al nemico
; Distanza massima fra il CENTRO del proiettile e quello del nemico perche' il
; colpo conti. Prima era il letterale 10 ripetuto due volte dentro il ciclo di
; collisione, e i centri erano cablati a +8, cioe' il centro di un bob 16x16:
; ora i centri vengono da bob_Larghezza/bob_Altezza e questa e' l'unica
; manopola. NB: il centro del nemico si e' spostato da +8 a +16 (il suo centro
; VERO a 32x32), quindi la zona utile del colpo e' cambiata: se il tiro
; sembra troppo facile o troppo severo, e' questo il numero da toccare.
BULLET_HIT_DIST		EQU		10			; px fra i centri perche' il colpo conti

; PROVA: a 1 la pietra e' sempre accesa e inchiodata a meta' schermo,
; ignorando lo stato reale del proiettile. Serve a validare il percorso
; di DISEGNO (blit, maschera, rettangolo sporco, restore) separatamente dalla
; traiettoria: se la pietra si vede, il difetto e' nella logica; se non si
; vede, e' nel disegno. Validata cosi' il 19 agosto 2026.
BULLET_DEBUG		EQU		0

; Posizione fissa della prova con BULLET_DEBUG (coordinate SCHERMO).
BULLET_DEBUG_X		EQU		160
BULLET_DEBUG_Y		EQU		80

; ----- Illuminazione (EHB) -----
TILE_LUCE			EQU		50			; numero tile = sorgente di luce
RAGGIO_LUCE			EQU		64			; raggio in pixel della luce (tile 19)

; Maschera statica del disco di luce per il blit del cerchio (vedi
; BuildLightMask / DisegnaCerchioLuceBlitter). Larga 8 word (128px) + 1 word
; di "spillover" per lo shift orizzontale = 9 word. Alta 128 righe (dy -64..63).
; Bit=1 dentro il cerchio. Costruita una volta al boot riusando LightHalfWidthTable.
LIGHT_MASK_W		EQU		9			; word per riga (8 disco + 1 per lo shift)
LIGHT_MASK_H		EQU		128			; righe
LIGHT_MASK_BANDA	EQU		LIGHT_MASK_W*2	; 18 byte per riga

; Righe di "padding" extra sotto le 256 visibili nel dark plane: assorbono
; un eventuale over-fetch di 1+ righe in fondo, evitando che la DMA legga
; nel buffer adiacente (contenuto diverso tra A e B -> sfarfallio in basso).
;DARK_PAD_ROWS		EQU		16
DARK_PAD_ROWS		EQU		0
DARK_ROWS			EQU		256+DARK_PAD_ROWS

; Righe di "padding" tra un piano e l'altro di BPSFONDO. Con FMODE=3 (fetch
; AGA a 64 bit) il prefetch in fondo allo schermo legge righe oltre 255 di
; ciascun piano. Con i 5 piani contigui (passo = 40*256), il piano N pesca
; nei dati del piano N+1 -> mosaico "a trattini" sull'ultima riga, visibile
; solo dove la luce notturna lo illumina (assente in OCS perche' senza
; FMODE non c'e' prefetch). Distanziando i piani con BG_PAD_ROWS righe
; blank (mai scritte da CopiaVideo/BOB, restano a 0 = colore 0 del bordo),
; il prefetch legge righe nere consistenti invece dei dati del piano dopo.
; 16 righe coprono anche eventuali BOB sul fondo che debordano oltre 255.
BG_PAD_ROWS			EQU		16
BG_PLANE_BANDA		EQU		BPSF_PITCH*(256+BG_PAD_ROWS)	; 13056 byte = passo di piano BPSFONDO (pitch 48)

; Passo di piano dei buffer PARALLASSE (piani 7-8). NON e' BG_PLANE_BANDA:
; quelli usano AUX_PITCH, che in Path A vale BPSF_PITCH (48) ma in Path B
; vale SFONDO_PITCH (64). Con BG_PLANE_BANDA il copper puntava il piano 8
; a +13056 mentre il blitter lo scriveva a +17408: 4352 byte = 68 righe di
; disallineamento, e il secondo piano mostrava una copia sfasata del primo.
; Allocazione, scrittura e copper devono usare TUTTI questa costante.
PAR_PLANE_BANDA	EQU		AUX_PITCH*(256+BG_PAD_ROWS)

; Numero di righe in fondo allo schermo da NON disegnare (border invisibile).
;
; STORIA: era un cerotto (=12) contro lo sfarfallio AGA sulle ultime ~12
; scanline. Causa vera individuata: il fill del dark plane su CPU (~2.5ms di
; MOVE.L) ritardava i blit dei BOB, che finivano mentre il pennello era gia'
; sul fondo schermo -> contesa DMA blitter/bitplane -> sfarfallio. Spostato il
; fill sul blitter (vedi UpdateDarkPlane STEP 1), tutto finisce ~2ms prima e
; la contesa sparisce. Quindi ora dovrebbe bastare 0 (schermo pieno 256 righe).
;
; >>> Se reimpostando 0 lo sfarfallio NON torna, lascialo a 0 (recuperi 12px).
; >>> Se dovesse tornare un filo, alza al minimo che lo elimina (prova 4, 8...).
;
; Muove insieme: BLTSIZE in CopiaVideo, cull cerchio in DisegnaCerchioLuce,
; DIWSTOP nella copperlist di gioco, e l'altezza di SFONDOGRANDE.
;
; >>> L'EQU e' DEFINITA IN TESTA AL FILE (blocco "ALTEZZA DI SFONDOGRANDE"),
; >>> perche' BUFFER_ROWS/SFONDO_HEIGHT/SFONDO_PLANE_SIZE derivano da lei e
; >>> vanno risolte prima. Qui resta solo la documentazione del perche'.

FaloAnimSpeed		EQU		5			; ogni N frame avanza animazione
ENEMY_COUNT			EQU		4			; numero massimo di nemici
; Quanti bob percorre il ciclo di disegno: i nemici, il player, la pietra.
; Vive qui e non nella SECTION Entities perche' le EQU vanno definite prima
; dell'uso, e DisegnaBOBs sta molto piu' su nel file.
BOB_TOTALI			EQU		ENEMY_COUNT+2

; PT Player: modalita' standard (VBLANK_MUSIC=0, default).
; Timer A gestisce il tick musicale automaticamente via interrupt CIA-B.
; Timer B gestisce il DMA delay automaticamente.
; Gli SFX funzionano sempre, anche a musica spenta.

; ----- Sound effects (PT Player _mt_playfx) -----
; sfx_per: period Paula. Valori indicativi:
;   124  -> ~28.8 kHz (sample HQ)
;   214  -> ~16.6 kHz
;   280  -> ~12.7 kHz (default tutti gli SFX qui)
;   428  -> ~8.3  kHz (C-3 PT standard)
; sfx_vol: 0..64 (64 = max). Indipendente dal master volume musica.
; sfx_cha: -1 = scelta automatica del canale meno usato.
; sfx_pri: 1..127. Priorita' piu' alta vince se il canale e' occupato.
SFX_PER_DEFAULT			EQU		280
SFX_VOL_DEFAULT			EQU		64
SFX_PRI_SPARO			EQU		64
SFX_PRI_PASSO			EQU		40			; il piu' basso: un passo non deve mai
											; rubare il canale a un colpo
SFX_PRI_HITENEMY		EQU		90
SFX_PRI_HITPLAYER		EQU		100
SFX_PRI_DEATH			EQU		110

; Period per i tre suoni veri (gli altri due sono ancora segnaposto da 16 byte).
; SE IL SUONO ESCE ACUTO O GRAVE, il numero da toccare e' questo: dipende dalla
; frequenza a cui hai esportato il .raw, non dal file.
;   period = 3546895 / frequenza     (clock PAL)
;    8000 Hz -> 443     16000 Hz -> 222
;   11025 Hz -> 322     22050 Hz -> 161
;   12500 Hz -> 284     28000 Hz -> 127
SFX_PER_PASSO			EQU		SFX_PER_DEFAULT
SFX_PER_NEMICO_COLPITO	EQU		SFX_PER_DEFAULT
SFX_PER_NEMICO_MORTO	EQU		SFX_PER_DEFAULT

; Frame fra un passo e il successivo mentre il player cammina. A 50 fps 12
; frame sono circa un quarto di secondo, cioe' un'andatura di camminata.
; passo.raw dura circa 8 frame al period corrente, quindi non si accavalla.
PASSO_INTERVALLO		EQU		12
;=====================================================================
; PROFILING HARNESS — margine con high-water mark + frame persi
;
; Come si legge la barra (dall'alto in basso):
;   BLU     = lavoro reale di QUESTO frame
;   ROSSO   = margine gia' bruciato in passato (high-water, sticky)
;   BIANCO  = margine RESIDUO -> e' il budget che ti resta
;   SCHERMO TUTTO ROSSO per un frame = FRAME PERSO
;
; La fascia bianca si assottiglia da sola man mano che il gioco incontra
; situazioni piu' pesanti. Dopo 2-3 minuti di gioco vario si stabilizza:
; quel valore e' il tuo margine reale. Riferimento: 1 riga raster = 227
; cicli di colore, il BOB 32x32 costa ~6 righe in piu' del 16x16.
;=====================================================================
PROTO_SCROLL    EQU     0       ; 1 = parte il PROTOTIPO dello scroll hardware
                                ;     (Path B passo 1) al posto del gioco.
                                ;     Rimetti 0 e torna tutto come prima.
PROFILING       EQU     1       ; 0 = harness completamente fuori dalla build
; PROF_COLORS: TUTTA la strumentazione che scrive COLOR00 — sia le barre di
; PROFMARK a ogni marca di fase, sia le tre fasce di fine frame (rosso pieno =
; frame perso, rosso scuro = margine bruciato, bianco = margine residuo).
; Erano gattate solo le prime: le fasce restavano accese e si vedevano come
; una riga orizzontale colorata a tutta larghezza dello schermo.
; Servono
; solo a leggere il costo delle fasi a occhio sul bordo schermo; la MISURA sta
; nel latch di ProfRaw e funziona lo stesso. Spente: il gioco si vede pulito.
PROF_COLORS     EQU     0
; PROF_KILL_SKY: a 1 esclude il gradiente cielo dalla copperlist, perche' il
; gradiente riscrive COLOR00 riga per riga e coprirebbe le fasce dell'harness.
; A 0 il cielo torna e il gioco si vede come deve: la MISURA non ne risente,
; perche' i tempi stanno nel latch di ProfRaw e si leggono dal monitor P.
; Serve rialzarlo a 1 solo se torni a leggere il costo dalle fasce a bordo
; schermo invece che dai numeri.
PROF_KILL_SKY   EQU     0

; Riga su cui sincronizza AspettaVBL. UNICA fonte di verita': AspettaVBL
; costruisce da qui il valore di confronto, FineLavoro la usa come origine
; della misura. NON duplicare il numero altrove: se le due si scollano, la
; misura e' sfasata di quella differenza e non te ne accorgi.
; Il lavoro del frame comincia appena il display finisce, cioe' alla riga
; ($2C + BG_VIS_ROWS). Era cablato a $108 = 264, che buttava 44 righe di blank;
; poi a $0DC = 220, giusto ma solo per BG_VIS_ROWS=176. Ora DERIVA, cosi'
; cambiando CUT_BOTTOM_ROWS il sync si sposta da solo — altrimenti alzando il
; CUT si guadagnerebbe blank senza usarlo, o peggio si partirebbe dentro il
; display.
VBL_SYNC_LINE   EQU     $2C+BG_VIS_ROWS
RASTER_LINES    EQU     313     ; PAL (NTSC = 262)

; NB: non serve piu' una soglia euristica per i frame persi. FineLavoro
; conta i wrap del raster e ricostruisce la durata REALE del frame, quindi
; il rilevamento e' diventato un confronto diretto: durata >= RASTER_LINES.
; Questo permette anche di misurare i frame che sforano, che sono proprio
; quelli dove stanno i costi peggiori.

;---------------------------------------------------------------------
; PROFILO PER FASE — dove vanno le righe
;
; Ogni confine del main loop scrive COLOR00 col colore della fase che
; INIZIA e latcha la riga raster. Risultato: lo schermo diventa una
; striscia di bande colorate, e l'altezza di ogni banda E' il costo di
; quella fase. Triage visivo immediato, senza debugger.
;
; I numeri precisi stanno in ProfWorst (peggior costo per fase, sticky):
; leggibile dal debugger come array di word, indice = PH_xxx.
; ATTENZIONE: la somma dei ProfWorst NON e' il worst totale — i picchi
; delle singole fasi non avvengono nello stesso frame.
;
; Overhead dell'harness completo: ~40 cicli per marker (11 marker) piu'
; il loop di normalizzazione in FineLavoro = circa 4-5 righe raster in
; totale. Sottraile mentalmente dai valori.
;---------------------------------------------------------------------
; Gli indici DEVONO essere in ordine temporale: il costo della fase i si
; ricava come ProfRaw[i+1] - ProfRaw[i] (l'ultima usa FrameLines come fine).
PH_VBLEND       EQU     0       ; GestisciMusica + SwapBuffers (subito dopo il sync)
PH_INPUT        EQU     1       ; input + fisica + camera + bordi
PH_SCROLL       EQU     2       ; GestisciShiftPixel  (treadmill)
PH_TILES        EQU     4       ; AggiornaTiles       (AddColonna/AddRiga)
PH_DARK         EQU     5       ; UpdateDarkPlane
PH_FALO         EQU     6       ; AnimaFalo
; ATTENZIONE: l'indice della fase DEVE seguire l'ordine CRONOLOGICO delle
; PROFMARK nel main loop. Il profiler calcola la durata di una fase come
; distanza dal marker SUCCESSIVO nell'array: se un latch arriva fuori ordine
; la differenza va negativa, la logica di wrap ci somma un frame intero e il
; totale si gonfia di ~313 righe (WO falsato e DR che sale anche da fermo).
; PH_PARALLAX e' passata da 6 a 9 quando AggiornaParallax e' stata spostata
; dopo il disegno dei BOB.
PH_COPIAVIDEO   EQU     7       ; (CopiaVideo non esiste piu': fase a costo zero)
PH_ENTITIES     EQU     8       ; screenpos + nemici + combattimento + proiettile
PH_BOB          EQU     9       ; restore + DisegnaBOB*
PH_PARALLAX     EQU     3       ; AggiornaParallax (DOPO i BOB, vedi main loop)
PH_BLTDRAIN     EQU     10      ; AspettaBlitter (attesa pura: se e' grossa, il
                                ;   blitter e' il collo di bottiglia, non la CPU)
PROF_SLOTS      EQU     11

;---------------------------------------------------------------------
; PROFMARK <indice fase>,<colore>
;   Marca l'inizio di una fase: colora COLOR00 e latcha la riga raster.
;   Salva la riga ASSOLUTA (0..312): la normalizzazione rispetto al sync
;   la fa FineLavoro, cosi' la macro resta senza salti e senza label
;   (niente \@, massima compatibilita' fra assemblatori).
;   Indirizzamento assoluto e non A6: funziona anche dove A6 non e' caricato.
;   Distrugge: nulla.
;---------------------------------------------------------------------
PROFMARK        MACRO
        IFNE    PROFILING
        move.l  d0,-(sp)
        IFNE    PROF_COLORS
        move.w  #\2,$DFF180             ; COLOR00 = colore di questa fase
        ENDC
        move.l  $DFF004,d0              ; VPOSR+VHPOSR come long = atomico
        lsr.l   #8,d0
        and.w   #$01FF,d0
        move.w  d0,ProfRaw+(\1*2)
        move.l  (sp)+,d0
        ENDC
        ENDM

WaitDisk 		EQU 30 ; 50-150 al salvataggio (secondo i casi)
START:

*****************************************************************************
* TITLE SCREEN
*   Setup AGA + PT Player, avvia musica, mostra title.raw, attende SPACE
*   o tasto fire del joystick. Poi ferma la musica e procede col gioco.
*****************************************************************************
	LEA		$DFF000,A6
	MOVE.W	#$3,$1fc(A6)			; FMODE = $03 (AGA fetch 64-bit)
	MOVE.W	#BPLCON3_LOCT0,$106(A6)			; BPLCON3 default
	MOVE.W	#$0000,$10c(A6)			; BPLCON4 default

	; ----- PT Player: installa interrupt CIA-B -----
	SUBA.L	A0,A0					; VectorBase = 0 (68000)
	MOVEQ	#1,D0					; PAL flag = 1
	JSR		_mt_install
	MOVE.W	#$E000,$DFF09A			; abilita INT level 6 (EXTER) + master enable
	MOVE.W	#$8200,$96(A6)			; DMACON: master DMA on (per audio Paula)

	; Riserva 3 canali alla musica: gli SFX (sfx_cha=-1) potranno usare
	; solo il 4o canale. Evita che uno sparo "buchi" un canale musicale.
	MOVE.B	#3,_mt_MusicChannels

	; ----- Carica modulo e avvia musica -----
	LEA		ANTIRIAD_MOD,A0
	SUBA.L	A1,A1					; campioni embedded
	MOVEQ	#0,D0					; SongPos = 0
	JSR		_mt_init
	MOVE.B	#1,_mt_Enable			; play

	; ----- Mostra title screen e attende input -----
	BSR.W	ShowTitle				; setup 8 BPL AGA + palette + copper
	BSR.W	WaitTitleInput			; busy-loop fino a SPACE o fire

	; ----- Click: ferma la musica della title -----
	MOVE.B	#0,_mt_Enable
	; _mt_Enable=0 mette in pausa il PT Player, ma Paula continua a
	; ripetere in loop l'ultimo sample caricato (= ultima nota infinita).
	; Azzero i 4 volumi audio: in pausa il PT Player non li sovrascrive,
	; quando la musica viene riattivata (tasto M) il player ricarica
	; automaticamente i volumi al primo tick.
	MOVE.W	#0,$a8(A6)				; AUD0VOL = 0
	MOVE.W	#0,$b8(A6)				; AUD1VOL = 0
	MOVE.W	#0,$c8(A6)				; AUD2VOL = 0
	MOVE.W	#0,$d8(A6)				; AUD3VOL = 0

	; ----- Spegne BPL+COP DMA prima di riconfigurare per il gioco -----
	; (audio DMA preservato per il restart musica successivo)
	MOVE.W	#$0180,$96(A6)			; CLR BPLEN+COPEN

*****************************************************************************
*	PUNTIAMO I BITPLANES DELLE TILES
*****************************************************************************

	MOVE.L	#SFONDOGRANDE,D0		; Path B visualizza direttamente il world buffer
	MOVE.L	#PathBDarkPlane,D2		; darkplane di Path B (i doppi buffer vecchi non ci sono piu')

	BSR.W	AggiornaCopperBPL 		; aggiorna i puntatori bitplane nella copperlist

	BSR.W	AggiornaCopperSPR 		; aggiorna anche i puntatori sprite nella copperlist

	; Piani 7-8 (parallasse): ora DOPPIO BUFFER, puntatori dal display corrente
    MOVE.L  CurrentParDisplay,D0
    BSR.W   AggiornaCopperParallasse
	; ----- Banchi palette 1..7 (colori 32..255) per gli 8 bitplane.
	; Copper DMA ancora spento: BPLCON3 e' tutto nostro, niente race.
	BSR.W	InitPalette8BPL

	LEA		$dff000,A6
	MOVE.W	#DMASET,$96(A6)			; DMACON - abilita dma
	MOVE.L	#CopperList,$80(A6)		; Puntiamo la nostra COP
	MOVE.W	D0,$88(A6)				; Facciamo partire la COP

	; Ripristina FMODE/BPLCON3/BPLCON4 per il gioco (la title li aveva
	; impostati ma per sicurezza li riscriviamo, in caso siano cambiati).
	MOVE.W	#$3,$1fc(A6)			; FMODE = $03 (fetch 64-bit AGA)
	MOVE.W	#BPLCON3_LOCT0,$106(A6)	; BPLCON3 default
	MOVE.W	#$0011,$10c(A6)			; BPLCON4: BPLAM=0, ESPRM=$1, OSPRM=$1 (entrambi sprite a COLOR17-19 arancione)
;	MOVE.W	#$1000,$10c(A6)			; BPLCON4: ESPRM=$10 (SPR0 falo' a COLOR17-19 arancione), OSPRM/BPLAM=$00
	; ----- DEBUG: scrivi SPR0PT direttamente nei registri custom -----
	; In caso la copperlist non riesca ad aggiornare i puntatori sprite,
	; settiamo manualmente SPR0PT su FuocoFrame_0 e SPR1..7 su EmptySprite.
	MOVE.L	#FuocoFrame_0,$120(A6)	; SPR0PT (scrittura long su $120 = high+low)
	MOVE.L	#EmptySprite,$124(A6)	; SPR1PT
	MOVE.L	#EmptySprite,$128(A6)	; SPR2PT
	MOVE.L	#EmptySprite,$12c(A6)	; SPR3PT
	MOVE.L	#EmptySprite,$130(A6)	; SPR4PT
	MOVE.L	#EmptySprite,$134(A6)	; SPR5PT
	MOVE.L	#EmptySprite,$138(A6)	; SPR6PT
	MOVE.L	#EmptySprite,$13c(A6)	; SPR7PT

	BSR.W   InitPlayer				; <-- INIZIALIZZA IL PLAYER
	BSR.W   InitEnemies				; <-- INIZIALIZZA I NEMICI
	BSR.W	InitPietra				; <-- INIZIALIZZA IL PROIETTILE (BOB pietra)
	BSR.W	BuildBobMasks			; Genera le maschere di OMINO/NEMICO/PIETRA al boot
	IFEQ	PROFILING*PROF_KILL_SKY
	BSR.W	BuildSkyCopper			; genera il gradiente cielo su BG_VIS_ROWS righe
	ENDC							; (con PROF_KILL_SKY=1 lo spazio non e' riservato)

	; ----- Musica: resta in pausa dopo il click sulla title.
	; L'utente la riattiva con M (toggle MusicOn -> _mt_Enable via GestisciMusica).
	; MusicOn=0/MusicOnPrev=0 -> nessun cambio rilevato, _mt_Enable resta 0.
	MOVE.B	#0,MusicOn
	MOVE.B	#0,MusicOnPrev

	BSR.W	DisegnaSfondo			; Routine che disegna lo sfondo

	; Pre-render su entrambi i buffer per evitare il primo frame nero
	BSR.W	BuildParallaxStrip			; costruisce la striscia di parallasse 
										; (una tantum: e' statica)
										; riempi ENTRAMBI i buffer parallasse col frame
										; iniziale (A6 = $DFF000 qui)
    MOVE.W  #-1,par_old					; forza il primo blit
	BSR.W	DisegnaPannello				; costruisce il pannello 
    BSR.W   AggiornaParallax			; riempie il Draw (B), dirty 2->1
    BSR.W   SwapParBuffers              ; Draw ora = A
    BSR.W   AggiornaParallax               ; offset invariato, dirty 1->0, riempie A
    BSR.W   SwapParBuffers               ; torna a Display=A
	; (al primo giro del loop il display è B, e disegnamo su A — entrambi pronti)

	BSR.W	PathBInit				; DDFSTRT/BPLxMOD + piani 6-8 su buffer vuoto
	LEA		SFONDOGRANDE,A0
	LEA		PathBMaster,A1
	BSR.W	PathBBuildMaster		; copia pulita per il restore dei BOB
	; Col doppio buffer la mappa deve stare in ENTRAMBI: il secondo buffer non
	; viene mai ridisegnato da zero, si ripulisce solo per rettangoli.
	LEA		SFONDOGRANDE,A0
	LEA		SFONDOGRANDE_B,A1
	BSR.W	PathBBuildMaster		; stessa mappa nel secondo buffer del mondo
	; DisegnaCerchioLuceBlitter scrive dove punta CurrentDarkDraw: in Path B
	; e' sempre il buffer statico, che non fa piu' doppio buffering.
	; Stessa origine dello sfondo: il darkplane deve stare allineato con lui,
	; e il suo BPL6PT usa lo stesso offset dei piani 1-5.
	MOVE.L	#PathBDarkPlane+DELTA_MAPPAVERA+BG_ORIGIN_OFS,CurrentDarkDraw
	BSR.W	PathBBuildDark			; darkplane statico, una volta sola
	BSR.W	BuildLightMask			; costruisce una volta la maschera del disco di luce

	IFNE	PROTO_SCROLL
	; --- PROTOTIPO SCROLL HARDWARE (Path B, passo 1) --------------
	; Salta il gioco: usa startup, copperlist, palette e input appena
	; inizializzati, ma sostituisce il rendering con la griglia di test.
	BSR.W	ProtoScrollMain
	BRA.W	GameCleanup
	ENDC
.mainloop:
*****************************************************************************
	PROFMARK PH_INPUT,$0404			; viola scuro
	; NB: LeggiTastiera deve stare QUI, prima di tutto. Provata dopo la parallasse
	; per togliere le sue righe dall'overhead che ritarda la pubblicazione del
	; buffer: i BOB partono piu' tardi di quanto lei costa e si corrompono.
	; Il tempo va tolto altrove, non da qui.
	BSR.W	LeggiTastiera			; Routine che legge la tastiera
	BSR.W	LeggiJoystick			; Routine che legge il Joystick	
	BSR.W	RettangoloScrollNelCentro		; Se bob NON al centro, azzera ScrllX/Y
	BSR.W	AggiornaFisicaPlayer		; gravita' + salto -> IntentY
	BSR.W	AggPosizioneGlobalePlayer	; Aggiorna bob_WorldX/Y (Fase 2)
	BSR.W	CalcolaInseguimentoCameraY	; camera insegue il player in verticale -> ScrllY
	BSR.W	ControllaBordi			; Controllo dei bordi
	PROFMARK PH_SCROLL,$0F80		; arancione
	BSR.W	ScrollPathB				; scroll hardware: solo puntatori + BPLCON1


	; La parallasse va DOPO i BOB, non prima. Il suo blit e' 8800 word (~77
	; scanline di blitter) e gira in background: mettendolo prima, ogni blit di
	; BOB si accodava dietro di lui e il disegno dei BOB finiva verso la riga 94,
	; quando il pennello era gia' passato -> BOB tagliati in una fascia FISSA
	; dello schermo. Misurato col monitor: PA 001 (solo il tempo di programmare)
	; contro BO 082 per un lavoro che di blitter ne vale 46: la differenza era
	; pura attesa in coda.
	; La parallasse puo' permettersi di finire tardi: e' doppio-bufferizzata e
	; viene pubblicata da SwapParBuffers a fine frame.
	PROFMARK PH_PARALLAX,$00F0		; verde
	BSR.W 	AggiornaParallax			; aggiorna il piano 7-8 (parallasse) in base a ScrllX

	; Il blit della parallasse parte QUI, subito dopo ScrollPathB che ha appena
	; scritto BPLCON1: contenuto e ritardo appartengono cosi' allo STESSO frame.
	; Poi si aspetta il blitter e si pubblica subito, mentre il pennello e'
	; ancora nel blank: il copper rilegge la copperlist all'inizio del quadro e
	; trova gia' i puntatori nuovi. Prima lo swap stava dopo AspettaVBL e
	; pubblicava il buffer del giro PRECEDENTE, compensato per il ritardo di un
	; frame prima: da li' il flash quando il ritardo salta da 0 a 63 al primo
	; pixel di scroll.
	; I BOB partono dopo, ma con CUT_BOTTOM_ROWS=96 finiscono verso la riga 27,
	; molto prima che il display cominci alla 44.
	BSR.W	AspettaBlitter			; il buffer parallasse dev'essere completo
	; NB: qui NON si pubblica. Lo swap sta in ScrollPathBApply insieme a BPLCON1
	; e ai puntatori del mondo: contenuto e compensazione devono diventare
	; effettivi nello STESSO quadro, altrimenti la parallasse mostra un frame
	; compensato per un ritardo che non e' ancora in vigore.
	PROFMARK PH_TILES,$0FF0			; giallo
	PROFMARK PH_DARK,$000F			; blu acceso
	; In Path B il darkplane e' STATICO: disegnato una volta in coordinate
	; mondo da PathBBuildDark e ricostruito solo al toggle di NightMode.
	; Qui non serve fare nulla: il costo per frame e' zero.
	; NOTA: il dark plane e' gia' double-buffered correttamente.
	; UpdateDarkPlane scrive SOLO CurrentDarkDraw (mai il buffer in display);
	; SwapBuffers alterna A/B e aggiorna BPL5PT. Nessuna copia extra serve qui:
	; copiare in CurrentDarkDisplay = scrivere nel piano EHB mentre il pennello
	; lo legge -> tearing visibile sul bordo del cerchio (lo "sfarfallio in basso").

	PROFMARK PH_FALO,$0088			; ciano scuro
	BSR.W	AnimaFalo				; anima sprite falò e lo posiziona su tile 19
	PROFMARK PH_COPIAVIDEO,$0F0F	; magenta
	PROFMARK PH_ENTITIES,$0808		; viola medio
	BSR.W	AggiornaPlayerScreenPos	; Calcola bob_X/Y dalle coord. mondo 
	BSR.W	AggiornaNemici			; AI dei nemici (movimento)
	BSR.W	Combattimento			; gestisce collisioni player-nemici (vita)
	BSR.W	Proiettile				; gestione fire + proiettile (move, collisione)
	BSR.W	SuonoPassi				; passi del player: gira dopo la fisica, cosi'
								;  legge un bob_Grounded gia' aggiornato
;	BSR.S 	SxMouse
	PROFMARK PH_BOB,$00FF			; ciano acceso
	BSR.W	PathBRestoreAll			; ripulisce lo sfondo dietro ai BOB del frame scorso
	BSR.W	DisegnaBOBs				; nemici + player + pietra, in un ciclo solo
; --- Sincronizzazione e swap ---
	PROFMARK PH_BLTDRAIN,$0FF8		; giallo pallido = attesa pura del blitter
									; (era $0840, indistinguibile dal rosso
									;  scuro $0800 dell'high-water)
	BSR.W	AspettaBlitter

	; Il disegno e' finito e il blitter ha drenato: ORA si pubblica il buffer e
	; si scambia con l'altro. Prima di qui il pennello non ha mai visto un
	; buffer a meta'.
	BSR.W	ScrollPathBApply

	IFNE	PROFILING
	BSR.W	FineLavoro			; misura margine + high-water + frame persi
								; (scrive lui ROSSO/BIANCO: niente $0FFF qui,
								;  sarebbe sovrascritto subito)
	TST.B	ProfShow			; premi P per mostrare/nascondere i numeri
	BEQ.S	.noprof
	BSR.W	MostraProfilo		; DOPO la misura: non entra in FrameLines
.noprof:
	ENDC
	BSR.W	AspettaVBL
	PROFMARK PH_VBLEND,$0008		; BLU = inizio lavoro (musica + swap)
 	BSR.W	GestisciMusica			; start/stop + tick PT Player (chiama _mt_music ogni VBL)
	; Ora SwapParBuffers torna: scrive BPL7PT/BPL8PT sul parallasse vero,
	; che ha finalmente il pitch giusto. Il darkplane invece ha il suo
	; doppio buffer dentro SwapBuffers, che in Path B non gira: lo scambio
	; lo fa PathBSwapDark qui sotto.
	; NB: PathBSwapDark non serve piu'. Il darkplane e' statico e non fa
	; doppio buffering: il suo BPL6PT lo aggiorna ScrollPathB insieme ai
	; puntatori dei piani 1-5, perche' ora scorre come loro.

	BTST.B	#6,$bfe001				; tasto sx del mouse premuto?
	BNE.W	.mainloop

; Label GLOBALE e non locale: il salto dal prototipo e' un forward
; reference e il linker non risolveva ".cleanup" nello scope di START.
; Sicuro da mettere qui: fra questa label e l'RTS non ci sono label
; locali, quindi nessuno scope cambia sotto i piedi al codice esistente.
GameCleanup:
	; ----- Cleanup PT Player prima di tornare all'OS -----
	LEA		$DFF000,A6
	JSR		_mt_end					; ferma replay + azzera canali audio
	JSR		_mt_remove				; rimuove handler CIA-B, ripristina timer
	RTS
*****************************************************************************
* ASPETTA VBL
*****************************************************************************
AspettaVBL:
	MOVEM.L D0-D2,-(SP)

	MOVE.L  #$1ff00,D1
	MOVE.L  #(VBL_SYNC_LINE<<8),D2	  ; linea VBL_SYNC_LINE ($108 = 264)
									  ; NON scrivere il numero a mano: FineLavoro
									  ; misura a partire da questa stessa EQU.
.wait:
	MOVE.L  $dff004,D0		  ; VPOSR
	AND.L   D1,D0
	CMP.L   D2,D0
	BNE.S   .wait
	movem.l (SP)+,D0-D2
	RTS
*****************************************************************************
* AGGIORNA I BPL POINTER NELLA COPPERLIST
* INPUT:  D0 = indirizzo del primo bitplane
* OUTPUT: 5 BPL pointer aggiornati a partire da BitPlaneTiles
* DISTRUGGE: D0, A1 (e usa internamente D1)
*****************************************************************************
AggiornaCopperBPL:
	MOVEM.L D1/A1,-(SP)
	LEA	 BitPlaneTiles,A1

	; --- Primi 5 plane: standard BPSFONDO ---
	MOVEQ   #5-1,D1
.loop:
	MOVE.W	D0,6(A1)			; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)			; word alta
	SWAP	D0
	ADD.L	#BG_PLANE_BANDA,D0	; prossimo bitplane (passo con padding anti over-fetch FMODE=3)
	ADDQ.W	#8,A1				; prossimi 4 dc.w nella copperlist
	DBRA	D1,.loop

	; --- 6° plane: DARK plane (gestito separatamente) ---
	; A1 punta ora a $f4,0,$f6,0 (BPL5PT entry)
	MOVE.W	D2,6(A1)			; BPL5PTL word bassa
	SWAP	D2
	MOVE.W	D2,2(A1)			; BPL5PTH word alta
	
	MOVEM.L	(SP)+,D1/A1
	RTS 
*****************************************************************************
* AGGIORNA I BPL POINTER NELLA COPPERLIST PER IL PARALLASSE
* INPUT:  D0 = indirizzo del buffer parallasse da mostrare
* OUTPUT: 2 BPL pointer aggiornati a partire da BitplaneParall
* DISTRUGGE: D0, A1 (e usa internamente D1)
*****************************************************************************
AggiornaCopperParallasse:               ; D0 = base buffer parallasse da mostrare
    MOVEM.L D0-D1/A1,-(SP)
    LEA     BitplaneParall,A1
    ; Il blit di AggiornaParallax scrive la guardia a word 3 (byte 6-7) e il
    ; contenuto da byte 8. Il display ha un prefetch di 8 byte, quindi
    ; puntando base+8 fetcha i byte 8..55: esattamente il contenuto scritto,
    ; guardia esclusa. Serve pero' che il blit sia largo BLIT_W=25 word, cioe'
    ; copra tutti e 48 i byte fetchati: con 21 restavano scoperti gli ultimi
    ; 8 byte (troncatura a destra), e togliendo il +8 si scopriva il prefetch
    ; a sinistra. Le due cose vanno insieme.
    IFNE    PAR_DISABLE
    MOVE.L  #PathBVuoto,D0               ; prova: parallasse spenta, piani 7-8 vuoti
    ENDC
    ADD.L   #PAR_PTR_OFS,D0
    MOVEQ   #2-1,D1
.setpar:
    MOVE.W  D0,6(A1)
    SWAP    D0
    MOVE.W  D0,2(A1)
    SWAP    D0
    IFEQ    PAR_DISABLE
    ADD.L   #PAR_PLANE_BANDA,D0         ; piano 8 (NON BG_PLANE_BANDA: vedi la EQU)
    ENDC
    ADDQ.W  #8,A1
    DBRA    D1,.setpar
    MOVEM.L (SP)+,D0-D1/A1
    RTS
*****************************************************************************
* SWAP DEI BUFFER PER IL PARALLASSE
*****************************************************************************
SwapParBuffers:
    MOVEM.L D0-D1,-(SP)
        ; Diagnostica SW: quante righe DOPO il sync viene pubblicato il buffer.
        ; Sticky come WorstLines (si azzera col tasto R), perche' mentre scrolli
        ; non si fa in tempo a leggere il monitor.
        ; Soglia: deve restare sotto RASTER_LINES-VBL_SYNC_LINE, altrimenti la
        ; pubblicazione cade dopo che il copper ha riletto la copperlist e la
        ; parallasse torna in ritardo di un frame.
        BSR.W   LeggiRiga               ; (richiede A6 = $DFF000, gia' valido qui)
        SUB.W   #VBL_SYNC_LINE,D0
        BPL.S   .swNoWrap
        ADD.W   #RASTER_LINES,D0        ; il frame e' girato
.swNoWrap:
        CMP.W   ProfSwapRaster,D0
        BLS.S   .swDone
        MOVE.W  D0,ProfSwapRaster       ; high-water
.swDone:
    MOVE.L  CurrentParDisplay,D0
    MOVE.L  CurrentParDraw,D1
    MOVE.L  D1,CurrentParDisplay
    MOVE.L  D0,CurrentParDraw
    MOVE.L  CurrentParDisplay,D0
    BSR.W   AggiornaCopperParallasse     ; BPL7/8PT sul buffer appena mostrato
    MOVEM.L (SP)+,D0-D1
    RTS

*****************************************************************************
* GestisciMusica
*   Chiamata ogni frame nel main loop.
*   In modalita' standard Timer-A gestisce il tick automaticamente:
*   qui ci limitiamo a propagare MusicOn -> _mt_Enable.
*   - MusicOn=1 -> _mt_Enable=1: Timer-A chiama il player automaticamente.
*   - MusicOn=0 -> _mt_Enable=0: Timer-A chiama solo mt_sfxonly (SFX ok).
*****************************************************************************
GestisciMusica:
	MOVEM.L	D0/A6,-(SP)

	MOVE.B	MusicOn,D0
	CMP.B	MusicOnPrev,D0
	BEQ.S	.done
	MOVE.B	D0,MusicOnPrev
	MOVE.B	D0,_mt_Enable		; 1 = play, 0 = pausa (SFX restano attivi)

.done:
	MOVEM.L	(SP)+,D0/A6
	RTS

*****************************************************************************
* AggiornaCopperSPR
*   Aggiorna gli sprite pointer nella copperlist (entry "Sprites").
*   - SPR0 -> frame corrente del falò (FuocoFrame_N, secondo FaloAnimFrame)
*   - SPR1..SPR7 -> EmptySprite (= disattivati)
* DISTRUGGE: D0/D1/A0/A1 (preserva tramite stack)
*****************************************************************************
AggiornaCopperSPR:
	MOVEM.L D0-D1/A0-A1,-(SP)

	; --- SPR0: punta al frame corrente del falò ---
	LEA		FaloFrameTable,A0
	MOVE.W	FaloAnimFrame,D0
	ANDI.W	#7,D0					; sicurezza: 0..7
	LSL.W	#2,D0					; *4 (long per entry)
	MOVE.L	(A0,D0.W),D0			; D0 = indirizzo FuocoFrame_N
	LEA		Sprites,A1
	; SPR0PT: i registri sono (reg_high, val_high, reg_low, val_low)
	; A1+2 = val_high (parte alta), A1+6 = val_low (parte bassa)
	MOVE.W	D0,6(A1)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)				; word alta

	; --- SPR1..SPR7: tutti puntano a EmptySprite ---
	MOVE.L	#EmptySprite,D0
	LEA		Sprites+8,A1			; SPR1PT entry
	MOVEQ	#7-1,D1					; 7 sprite da disattivare
.loop:
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	SWAP	D0
	ADDQ.W	#8,A1					; prossima entry sprite nella copperlist
	DBRA	D1,.loop

	MOVEM.L	(SP)+,D0-D1/A0-A1
	RTS 

*****************************************************************************
* FaloFrameTable
*   Indirizzi dei 6 frame del falò (per indicizzazione veloce).
*****************************************************************************
FaloFrameTable:
	dc.l	FuocoFrame_0
	dc.l	FuocoFrame_1
	dc.l	FuocoFrame_2
	dc.l	FuocoFrame_3
	dc.l	FuocoFrame_4
	dc.l	FuocoFrame_5
	dc.l	FuocoFrame_0			; padding per ANDI #7 sicurezza
	dc.l	FuocoFrame_0

	IFNE	PROFILING
;---------------------------------------------------------------------
; LeggiRiga -> d0.w = riga raster corrente (0..312)
; $DFF004 letto come LONG = VPOSR+VHPOSR in un colpo -> atomico, niente
; race sul bit V8 (che sta in VPOSR bit 0 = bit 16 del long).
; Richiede A6 = $DFF000.  Distrugge solo D0.
;---------------------------------------------------------------------
LeggiRiga:
        move.l  $04(A6),d0
        lsr.l   #8,d0
        and.w   #$01FF,d0
        rts

;---------------------------------------------------------------------
; FineLavoro — da chiamare subito dopo AspettaBlitter, PRIMA di AspettaVBL.
;
; Misura quante righe raster ha consumato il lavoro di questo frame,
; tiene il peggior caso mai visto (high-water) e rileva i frame persi.
;
; RILEVAMENTO FRAME PERSO — perche' non serve l'interrupt VERTB:
;   Il lavoro parte sempre alla riga VBL_SYNC_LINE (264), subito dopo
;   AspettaVBL. Da lì il raster sale a 312, wrappa a 0 e continua.
;   Quindi FrameLines = (riga_attuale - 264) mod 313, cioe' 0..312 dove
;   312 = frame interamente consumato.
;   Se il lavoro sfora il frame, il contatore wrappa e FrameLines ricade
;   nella finestra 0..48. Ma un lavoro davvero durato 1..48 righe e'
;   fisicamente impossibile per questo gioco (solo CopiaVideo su 5 piani
;   ne costa molte di piu'). Quindi FrameLines < 49 non e' un frame
;   veloce: e' un frame che ha sforato.
;   LIMITE: uno sforo superiore a 361 righe torna in finestra "plausibile"
;   e non viene contato — ma in quel caso la barra e' TUTTA blu e si vede
;   a occhio, quindi non e' un buco cieco.
;
; Richiede A6 = $DFF000.  Preserva tutti i registri.
;---------------------------------------------------------------------
FineLavoro:
        movem.l d0-d5/a0-a1,-(sp)

        ; --- 1. righe consumate da questo frame ---------------------
        bsr.s   LeggiRiga
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .nowrap
        add.w   #RASTER_LINES,d0
.nowrap:
        move.w  d0,FrameLines
        move.w  d0,d4                   ; d4 = fine del frame, serve sotto

        ; --- reset degli high-water su richiesta (tasto R) ----------
        ; Sta PRIMA dell'uscita per ProfShow: cosi' puoi azzerare anche
        ; mentre stai guardando i numeri, e riparti pulito.
        tst.w   WorstReset
        beq.s   .noreset
        clr.w   WorstReset
        clr.w   WorstLines
        clr.w   DropCount
        clr.w   ProfSwapRaster
        lea     ProfWorst,a0
        moveq   #PROF_SLOTS-1,d2
.pclr:  clr.w   (a0)+
        dbra    d2,.pclr
.noreset:

        ; Se i numeri sono a schermo la misura e' CONGELATA per intero:
        ; disegnarli costa ~90 righe, che falserebbero proprio i valori che
        ; stai leggendo e farebbero scattare il rilevatore di frame persi.
        ; Fondo nero, cosi' le cifre (colore 31) restano leggibili.
        tst.b   ProfShow
        beq.s   .measure
        move.w  #$0000,$180(A6)
        bra     .out
.measure:

        ; --- 2. profilo per fase + durata REALE del frame -----------
        ; Un solo passaggio: normalizza il latch rispetto al sync, calcola il
        ; costo della fase che si chiude qui (distanza dal latch precedente)
        ; e aggiorna il suo high-water.
        ;
        ; I latch sono monotoni crescenti finche' il frame sta dentro un giro
        ; di raster. Un delta NEGATIVO significa che il raster ha wrappato:
        ; il costo vero di quella fase e' delta+RASTER_LINES, e il frame dura
        ; un giro in piu'. Contando i wrap si ricostruisce la durata reale
        ; anche quando il frame sfora -- ed e' proprio il caso che interessa,
        ; perche' e' li' che stanno i costi peggiori.
        ;
        ; LIMITE: una singola fase che da sola superi RASTER_LINES non viene
        ; vista (il suo delta tornerebbe positivo ma sbagliato). Con lo scroll
        ; a ~243 righe siamo sotto, ma se un giorno una fase si avvicina a 313
        ; questo numero va preso con le pinze.
        moveq   #0,d5                   ; d5 = quanti wrap in questo frame
        lea     ProfRaw,a0
        lea     ProfWorst,a1

        ; Primo latch: va solo normalizzato, non chiude nessuna fase (il costo
        ; di una fase e' la distanza FINO al marker successivo).
        move.w  (a0),d0
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .pnw0
        add.w   #RASTER_LINES,d0
.pnw0:
        move.w  d0,(a0)+
        move.w  d0,d1                   ; d1 = latch precedente

        moveq   #PROF_SLOTS-2,d2        ; i PROF_SLOTS-1 latch rimanenti
.pnorm:
        move.w  (a0),d0
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .pnw
        add.w   #RASTER_LINES,d0
.pnw:
        move.w  d0,(a0)+                ; riscrive normalizzata (comoda al debugger)
        move.w  d0,d3
        sub.w   d1,d3                   ; costo della fase che si chiude qui
        bpl.s   .pok
        addq.w  #1,d5                   ; il raster ha wrappato qui
        add.w   #RASTER_LINES,d3        ; ...quindi il costo vero e' questo
.pok:
        cmp.w   (a1),d3
        bls.s   .pnext
        move.w  d3,(a1)                 ; nuovo peggior costo per questa fase
.pnext:
        addq.w  #2,a1
        move.w  d0,d1                   ; questo latch diventa il riferimento
        dbra    d2,.pnorm

        ; L'ultima fase si chiude sulla fine del lavoro
        move.w  d4,d3
        sub.w   d1,d3
        bpl.s   .plok
        addq.w  #1,d5
        add.w   #RASTER_LINES,d3
.plok:
        cmp.w   (a1),d3
        bls.s   .ptot
        move.w  d3,(a1)

.ptot:  ; --- 3. durata reale = righe dal sync + un giro per ogni wrap
        move.w  d5,d3
        mulu.w  #RASTER_LINES,d3
        add.w   d4,d3                   ; d3 = durata VERA del frame
        move.w  d3,FrameLines           ; sovrascrive con il valore ricostruito
        move.w  d3,d4

        ; L'high-water del totale si aggiorna SEMPRE, anche quando il frame
        ; sfora: ora la durata e' un numero vero e non piu' spazzatura.
        cmp.w   WorstLines,d4
        bls.s   .nowl
        move.w  d4,WorstLines
.nowl:
        ; --- 5. frame perso? ---------------------------------------
        ; Ora e' un confronto diretto: il lavoro e' durato piu' di un frame.
        cmp.w   #RASTER_LINES,d4
        blo.s   .frameok
        addq.w  #1,DropCount
        IFNE    PROF_COLORS
        move.w  #$0F00,$180(A6)         ; ROSSO PIENO = frame perso
        ENDC
        bra     .out

.frameok:
        ; --- 6. fascia ROSSA fino al peggior caso, poi BIANCO -------
        ; Lo spin si ferma comunque prima della riga di sync: se WorstLines
        ; e' oltre un frame intero (succede scrollando) la fascia bianca non
        ; compare proprio, ed e' l'informazione giusta -- margine zero.
        move.w  WorstLines,d1
        cmp.w   #RASTER_LINES-1,d1
        blo.s   .spinok
        move.w  #RASTER_LINES-1,d1
.spinok:
        IFNE    PROF_COLORS
        move.w  #$0800,$180(A6)         ; rosso scuro = margine bruciato
        ENDC
.wait:  move.l  $04(A6),d0              ; LeggiRiga inline: in uno spin loop
        lsr.l   #8,d0                   ; il bsr/rts e' ~30 cicli buttati
        and.w   #$01FF,d0
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .nw2
        add.w   #RASTER_LINES,d0
.nw2:   cmp.w   d1,d0
        blo.s   .wait                   ; confronto in "righe dal sync", non
                                        ; uguaglianza di riga: se un interrupt
                                        ; ci fa saltare la riga esatta non
                                        ; restiamo appesi per un frame intero
        IFNE    PROF_COLORS
        move.w  #$0FFF,$180(A6)         ; BIANCO = margine RESIDUO
        ENDC
.out:
        movem.l (sp)+,d0-d5/a0-a1
        rts
	ENDC

*****************************************************************************
* LEGGI JOYSTICK 
*****************************************************************************
LeggiJoystick:
	movem.l D0-D3/A0-A1,-(SP)

	MOVE.W	#0,ScrllX	; inizializzo lo spostamento orizzontale
	MOVE.W	#0,ScrllY	; inizializzo lo spostamento verticale
	MOVE.W	#0,UpNow	; azzero lo stato del tasto salto per questo frame
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

;------------------------------------------------------------
; CALCOLO DIREZIONE DEL PLAYER da ScrllX/ScrllY
;
; Indice nella tabella = (ScrllY+1)*3 + (ScrllX+1)
;
;            ScrllX:   -1     0     +1
;   ScrllY=-1:    NW(5)  N(6)  NE(7)
;   ScrllY= 0:     W(4)  --    E(0)
;   ScrllY=+1:    SW(3)  S(2)  SE(1)
;
; Se siamo fermi (centro tabella) la direzione corrente NON viene
; modificata: il player conserva l'ultima direzione di movimento
; (utile per scegliere il giusto sprite "idle" facing).
;------------------------------------------------------------
	LEA		Player,A0
	MOVE.w	ScrllY,D0
	MOVE.W  D0,bob_IsMoving(A0)
	ADDQ.w	#1,D0			; d0 = ScrllY+1 (0..2)
	MULU.w	#3,D0			; d0 = (ScrllY+1)*3 (0,3,6)
	MOVE.w	ScrllX,D1
	OR.W  	D1,bob_IsMoving(A0)
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
;------------------------------------------------------------
; LeggiTastiera
;   Legge UN keycode dalla CIA-A (se disponibile),
;   decodifica e aggiorna ScrollX / ScrollY.
;   Registri modificati: d0, d1  (salvati/ripristinati)
;------------------------------------------------------------
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

;------------------------------------------------------------
; ProcessaFrecce
;   Input : d0.b = keycode decodificato
;			  bit7 = 0 pressione, 1 rilascio
;			  bit6-0 = codice tasto
;   Output: aggiorna arrow_*
;			non scrive ScrollX, ScrollY che vengono scritti 
;			da LeggiJoystick
;   Registri modificati: d2 (salvato/ripristinato)
;------------------------------------------------------------
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
	bne.s	.k_prof
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

; La label sta FUORI dal condizionale: .k_gravity ci salta sempre, anche
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
.p_release:
	move.b	D1,ProfKeyPrev

.k_reset:
	cmp.b	#RAWKEY_R,D2
	bne.s	.done
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
	ENDC
.done:

	movem.l	(SP)+,D1-D2
	rts
*****************************************************************************
* 		ROUTINE DI CONTROLLO DEI BORDI
* TILE BOUNDARY - SHIFT BUFFER
*****************************************************************************
ControllaBordi:
	MOVEM.L D0-D2,-(SP)
 
;==========================================================================
; PRE-Check per simmetria con .AzzeroXMin/.AzzeroYMin
;==========================================================================
 
; --- Y axis pre-Check ---
	MOVE.W  ScrllY,D0
	BEQ.S   .PreCheckYFatto		  ; ScrllY=0, niente da bloccare
	BMI.S   .PreCheckYMin		   ; ScrllY<0: check upper boundary
; ScrllY>0: check lower boundary
	MOVE.W  TileY,D0
	CMP.W   #TILEYMAX,D0
	BLT.S   .PreCheckYFatto		  ; TileY<TILEYMAX, OK
	MOVE.W  PixelOffY,D0
	BNE.S   .PreCheckYFatto		  ; PixelOffY!=0 (ciclo in corso), OK
	CLR.W   ScrllY				  ; al fondo + PixelOffY=0 + premuto giu': BLOCK
	BRA.S   .PreCheckYFatto
.PreCheckYMin:
	MOVE.W  TileY,D0
	BGT.S   .PreCheckYFatto		  ; TileY>0, OK
	MOVE.W  PixelOffY,D0
	BNE.S   .PreCheckYFatto		  ; PixelOffY!=0 (ciclo in corso), OK
	CLR.W   ScrllY				  ; in cima + PixelOffY=0 + premuto su': BLOCK
.PreCheckYFatto:
 
; --- X axis pre-Check (simmetrico) ---
	MOVE.W  ScrllX,D0
	BEQ.S   .PreCheckXFatto
	BMI.S   .PreCheckXMin
	MOVE.W  TileX,D0
	CMP.W   #TILEXMAX,D0
	BLT.S   .PreCheckXFatto
	MOVE.W  PixelOffX,D0
	BNE.S   .PreCheckXFatto
	CLR.W   ScrllX
	BRA.S   .PreCheckXFatto
.PreCheckXMin:
	MOVE.W  TileX,D0
	BGT.S   .PreCheckXFatto
	MOVE.W  PixelOffX,D0
	BNE.S   .PreCheckXFatto
	CLR.W   ScrllX
.PreCheckXFatto:
 
	MOVE.W  PixelOffX,D0
	MOVE.W  PixelOffY,D1
	ADD.W   ScrllX,D0
	ADD.W   ScrllY,D1
 
	CMP.W   #16,D0
	BLT.S   .ControlloXMin
	MOVE.W  TileX,D2
	CMP.W   #TILEXMAX,D2
	BGE.S   .AzzeroXMax
	SUB.W   #16,D0
	ADD.W   #1,TileX
	BRA.S   .ControlloY
.AzzeroXMax:
	MOVE.W  #0,ScrllX
	MOVEQ   #15,D0
	BRA.S   .ControlloY
.ControlloXMin:
	TST.W   D0
	BGE.S   .ControlloY
	MOVE.W  TileX,D2
	CMP.W   #0,D2			  ; era #1 → corretto a #0
	BLE.S   .AzzeroXMin
	ADD.W   #16,D0
	SUB.W   #1,TileX
	BRA.S   .ControlloY
.AzzeroXMin:
	MOVE.W  #0,ScrllX
	MOVEQ   #0,D0
.ControlloY:
	CMP.W   #16,D1
	BLT.S   .ControlloYMin
	MOVE.W  TileY,D2
	CMP.W   #TILEYMAX,D2		; coerente con check X: #TILEXMAX
	BGE.S   .AzzeroYMax
	SUB.W   #16,D1
	ADD.W   #1,TileY
	BRA.S   .FineControlli
.AzzeroYMax:
	MOVE.W  #0,ScrllY
	MOVEQ   #16-CAM_STEP_Y,D1	; 15 se step=1, 8 se step=8
	BRA.S   .FineControlli
.ControlloYMin:
	TST.W   D1
	BGE.S   .FineControlli
	MOVE.W  TileY,D2
	CMP.W   #0,D2
	BLE.S   .AzzeroYMin
	ADD.W   #16,D1
	SUB.W   #1,TileY
	BRA.S   .FineControlli
.AzzeroYMin:
	MOVE.W  #0,ScrllY
	MOVEQ   #0,D1
.FineControlli:
	; La camera non deve MAI superare TILE*MAX*16 ---
	; I check qui sopra bloccano lo scroll solo quando PixelOff vale 0. Basta
	; arrivare al tile di bordo con un offset residuo — succede cambiando il
	; passo verticale a meta' tile, cioe' premendo G — e la camera prosegue
	; fino a TILEYMAX*16+15, poi si assesta 8 px oltre il limite valido.
	; Questo chiude sia il transitorio sia il regime: al tile di bordo
	; l'offset e' per definizione 0, perche' la finestra finisce esattamente
	; sul bordo della mappa.
	MOVE.W	TileX,D2
	CMP.W	#TILEXMAX,D2
	BLT.S	.setXok
	MOVE.W	#TILEXMAX,TileX
	MOVEQ	#0,D0
.setXok:
	MOVE.W	TileY,D2
	CMP.W	#TILEYMAX,D2
	BLT.S	.setYok
	MOVE.W	#TILEYMAX,TileY
	MOVEQ	#0,D1	
.setYok:
	MOVE.W  D0,PixelOffX
	MOVE.W  D1,PixelOffY
	MOVEM.L (SP)+,D0-D2
	RTS
 
*****************************************************************************
* 		ROUTINE DI COMPOSIZIONE DELLO SFONDO
*
* Riempio il buffer di SFONDO_PITCH*SFONDO_HEIGHT con il rettangolo in alto a sinistra 
* della mappa.
* 
*****************************************************************************
DisegnaSfondo:
	MOVEM.L	D0-D6/A0-A2,-(SP)

	LEA		MAPPA,A0			; Salvo in A0 il punt. alla mappa
	MOVE.W	TileX,D0			; colonna di partenza
	ADD.W	D0,D0				; *2 perché ogni tile è una word
	ADDA.W	D0,A0				; salta le colonne a sinistra
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
;	BSR.W	AspettaBlitter
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
	DBRA	D2,.CicloTile
.FineMappa:

	MOVEM.L	(SP)+,D0-D6/A0-A2

	RTS

*****************************************************************************
* BuildSkyCopper - genera il gradiente cielo dentro la copperlist
*
* Riempie SkyCopper con SKY_STEPS passi, uno per riga visibile, ricampionando
* la tabella SkyGradient (SKY_SRC_ROWS voci) sulle BG_VIS_ROWS righe di
* display. Cosi' il gradiente e' sempre INTERO qualunque sia CUT_BOTTOM_ROWS:
* prima era una lista statica tarata su 212 righe e con il taglio se ne
* vedeva solo la parte alta.
*
* Ogni passo emesso:
*   $rr01,$fffe        WAIT sulla riga rr
*   $0106,$0e00        BPLCON3 LOCT=1
*   $0180,<basso>      COLOR00 nibble bassi
*   $0106,$0c00        BPLCON3 LOCT=0
*   $0180,<alto>       COLOR00 nibble alti
* e in coda $0106,$0c00 per lasciare LOCT=0.
*
* OGGI IL RICAMPIONAMENTO E' L'IDENTITA' e non e' un caso: SkyGradient ha
* esattamente SKY_STEPS voci, una per riga raster, perche' il copper scrive un
* colore per riga e piu' di cosi' non se ne possono mostrare. La tabella
* d'arte, che di voci ne ha 260, viene ridotta OFFLINE da tools/gen-cielo.py
* interpolando; farlo qui con la DIVU significava troncare, e troncando si
* saltavano voci intere (l'indice avanzava di 1,477 per riga). Da li' venivano
* le bande nella meta' alta del cielo.
*
* Il conto resta al suo posto lo stesso, per due motivi: se un domani
* BG_VIS_ROWS cambia senza rigenerare la tabella il cielo esce comunque intero
* invece di leggere fuori tabella, e la guardia in fondo a CieloGrad.i lo fa
* notare all'assemblaggio. L'indice e' i*SKY_SRC_ROWS/SKY_STEPS: il quoziente
* della DIVU deve stare in 16 bit, e con i<SKY_STEPS il quoziente e' sempre
* < SKY_SRC_ROWS, quindi non trabocca mai per costruzione.
* Gira una volta al boot, quindi il costo non conta.
*****************************************************************************
	IFEQ	PROFILING*PROF_KILL_SKY
BuildSkyCopper:
	MOVEM.L	D0-D4/A0-A1,-(SP)
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

	; --- WAIT sulla riga $2C + D0 ---
	MOVE.W	D0,D2
	ADD.W	#$2C,D2
	LSL.W	#8,D2
	OR.W	#$0001,D2               ; posizione orizzontale 0, bit0=1 = WAIT
	MOVE.W	D2,(A1)+
	MOVE.W	#$FFFE,(A1)+

	; --- LOCT=1, nibble bassi ---
	MOVE.W	#$0106,(A1)+
	MOVE.W	#BPLCON3_LOCT1,(A1)+
	MOVE.W	#$0180,(A1)+
	MOVE.W	2(A0),(A1)+             ; seconda word della voce = basso
	; --- LOCT=0, nibble alti ---
	MOVE.W	#$0106,(A1)+
	MOVE.W	#BPLCON3_LOCT0,(A1)+
	MOVE.W	#$0180,(A1)+
	MOVE.W	(A0),(A1)+              ; prima word della voce = alto

	ADDQ.W	#1,D0
	CMP.W	#SKY_STEPS,D0
	BLT.S	.skyrow

	MOVE.W	#$0106,(A1)+            ; lascia BPLCON3 a LOCT=0
	MOVE.W	#BPLCON3_LOCT0,(A1)+
	MOVEM.L	(SP)+,D0-D4/A0-A1
	RTS
	ENDC

*****************************************************************************
* 		ROUTINE DI COMPOSIZIONE DELLO PIANO DI PARALLASSE
*****************************************************************************
BuildParallaxStrip:
    MOVEM.L D0-D3/A0-A2,-(SP)
    LEA     parallasse,A0       ; sorgente: 2 piani contigui, SRC_W x SRC_H, pitch SRC_PITCH
    ADDA.L  #PARALLAX_SRC_HEAD,A0   ; parte da PARALLAX_SRC_ROW0
    LEA     PARALLAX_STRIP,A1        ; dest:     2 piani contigui, STRIP_W x STRIP_ROWS
    MOVEQ   #2-1,D3                  ; 2 piani
.plane:
    MOVE.W  #PARALLAX_STRIP_ROWS-1,D0   ; solo le righe che finiscono a schermo
.row:
    MOVEA.L A0,A2                    ; A2 = inizio riga arte (per la replica)
    MOVE.W  #PARALLAX_SRC_PITCH/2-1,D1   ; una riga d'arte, in word
.copyart:
    MOVE.W  (A0)+,(A1)+
    DBRA    D1,.copyart
    MOVE.W  #PARALLAX_WRAP_W/16-1,D2     ; la replica, in word (i primi WRAP_W px)
.copywrap:
    MOVE.W  (A2)+,(A1)+
    DBRA    D2,.copywrap
    DBRA    D0,.row                  ; A0 gia' avanzato = riga successiva
    ; le righe d'arte sotto il taglio non servono: saltale per arrivare
    ; all'inizio del piano successivo. A CUT_BOTTOM_ROWS=0 lo skip e' 0.
    ADDA.L  #PARALLAX_SRC_SKIP,A0
    DBRA    D3,.plane

    IFNE    PAR_TEST_FILL
    ; Prova: sovrascrive TUTTA la striscia col motivo a bande, entrambi i piani.
    ; Le bande fanno da righello: qualunque irregolarita' nella loro larghezza
    ; e' il punto in cui il display legge fuori sequenza. Gira una volta al boot.
    IFEQ    PAR_TEST_MODE-1
    LEA     PARALLAX_STRIP,A1
    MOVE.L  #(2*PARALLAX_STRIP_PLANE_SZ)/4-1,D0
.fillall:
    MOVE.L  #PAR_TEST_PATTERN,(A1)+
    SUBQ.L  #1,D0
    BPL.S   .fillall
    ENDC

    IFEQ    PAR_TEST_MODE-2
    ; strisce orizzontali: una riga piena, una vuota, su entrambi i piani
    LEA     PARALLAX_STRIP,A1
    MOVEQ   #2-1,D3
.hplane:
    MOVE.W  #PARALLAX_STRIP_ROWS-1,D0
.hrow:
    ; NB: a WORD, non a long: PARALLAX_STRIP_PITCH e' 138, che non e'
    ; divisibile per 4 — un loop a long lascerebbe 2 byte per riga e
    ; falserebbe proprio la prova. 138/2 = 69 word esatte.
    MOVEQ   #0,D2
    BTST    #0,D0
    BEQ.S   .hvuota
    MOVE.W  #$FFFF,D2
.hvuota:
    MOVE.W  #PARALLAX_STRIP_PITCH/2-1,D1
.hfill:
    MOVE.W  D2,(A1)+
    DBRA    D1,.hfill
    DBRA    D0,.hrow
    DBRA    D3,.hplane
    ENDC
    ENDC

    MOVEM.L (SP)+,D0-D3/A0-A2
    RTS
*****************************************************************************
* 		ROUTINE DI AGGIORNAMENTO DEL PARALLASSE
*****************************************************************************
AggiornaParallax:
    MOVEM.L D0-D5/A1-A2,-(SP)

    ; ----- offset = (CameraX >> 1) mod 640 -----
    MOVE.W  TileX,D0
    LSL.W   #4,D0                    ; TileX*16
    ADD.W   PixelOffX,D0             ; D0 = CameraX
    LSR.W   #1,D0                    ; >>1  <-- il FATTORE 1/2 e' qui
    ; Compensazione di BPLCON1. Lo shifter software gestisce gia' offset
    ; arbitrari, quindi basta sommarci il ritardo.
    ;
    ; ATTENZIONE: il commento precedente diceva l'esatto contrario, ed era
    ; FALSO. Simulato su tutta la corsa della camera (CameraX 0..80):
    ;   compensazione PIENA        -> offset cambia 40 volte su 80 passi,
    ;                                 0 posizioni sbagliate
    ;   arrotondata a 2 px         -> offset cambia 80 volte su 80 passi,
    ;                                 39 posizioni sbagliate
    ; La ragione: P = CameraX>>1 cresce di 1 ogni DUE pixel mentre D cala di
    ; 1 ogni pixel, quindi la somma P+D cambia ogni due. Arrotondando D a
    ; pari si rompe quella cadenza e la somma cambia a ogni pixel.
    ; L'arrotondamento costava dunque il DOPPIO dei blit E sbagliava la
    ; posizione: a CameraX=1 mandava l'offset sotto zero e il wrap portava
    ; la colonna 639 dell'arte — il bordo opposto — sul lato sinistro dello
    ; schermo per un frame.
    ; L'arrotondamento a 2 px era l'alternativa numero 2 dell'interruttore
    ; TIPO_COMPENSAZIONE, tolto il 19 agosto 2026: la misura qui sopra lo
    ; aveva gia' bocciato (doppio dei blit E posizione sbagliata), quindi
    ; non era un'opzione ma un errore che aspettava di essere riacceso.
    MOVE.W  PathBDelay,D1
    ADD.W   D1,D0
    ; NIENTE sottrazione del prefetch e NIENTE mod 640: vedi il commento su
    ; PARALLAX_LEFT_MARGIN. L'offset resta piccolo e sempre positivo, quindi
    ; la finestra non attraversa mai la giunzione fra arte e replica — che era
    ; la vera causa della striscia sporca sul bordo sinistro.
    ADD.W   #PARALLAX_LEFT_MARGIN,D0    ; D0 = offset, sempre >= 16
    IFNE    PARALLAX_NO_FINE
    AND.W   #$FFF0,D0                   ; prova: niente shift fine, ASH = 0
    ENDC

	CMP.W   par_old,D0
    BEQ.S   .par_checkdirty              ; offset invariato -> forse serve ancora l'altro buffer
    MOVE.W  D0,par_old
    MOVE.W  #2,par_dirty                 ; offset cambiato -> ENTRAMBI i buffer da rifare
.par_checkdirty:
    TST.W   par_dirty
    BEQ     .done
    SUBQ.W  #1,par_dirty

; ----- parola di guardia: R = (offset-1)>>4 con segno, ASH = (-offset) AND 15 -----
    MOVE.W  D0,D5
    NEG.W   D5
    AND.W   #15,D5                   ; D5 = ASH = (-offset) AND 15

    MOVE.W  D0,D1
    SUBQ.W  #1,D1                    ; offset-1  (= -1 se offset=0)
    ASR.W   #4,D1                    ; R con segno (-1 se offset=0)
    EXT.L   D1
    ADD.L   D1,D1                    ; R*2 (long, gestisce il negativo)

    ; La destinazione parte da BYTE 0, non piu' da byte 6: si scrive l'intera
    ; riga. Di conseguenza la sorgente arretra di 4 word (PAR_GUARD_WORDS),
    ; perche' la word che finisce a byte 8 deve restare quella di prima.
    SUB.L   #PAR_GUARD_WORDS*2,D1
    LEA     PARALLAX_STRIP,A2
    ADDA.L  D1,A2                    ; sorgente: strip + (R-4)*2
	MOVE.L  CurrentParDraw,A1            ; dest = buffer di dietro, riga intera
    MOVEQ   #2-1,D4
.plane:
    BSR.W   AspettaBlitter
    MOVE.W  D5,D3
    LSL.W   #8,D3
    LSL.W   #4,D3                    ; ASH<<12
    OR.W    #$09F0,D3                ; USEA+USED, minterm D=A
    MOVE.W  D3,$40(A6)               ; BLTCON0
    MOVE.W  #$0000,$42(A6)           ; BLTCON1 (ascendente)
    MOVE.L  #$FFFFFFFF,$44(A6)       ; BLTAFWM/BLTALWM = $FFFF/$FFFF (nessuna maschera)
    MOVE.W  #PARALLAX_STRIP_PITCH-(PARALLAX_BLIT_W*2),$64(A6)  ; BLTAMOD = 80
    MOVE.W  #AUX_PITCH-(PARALLAX_BLIT_W*2),$66(A6)             ; BLTDMOD
    MOVE.L  A2,$50(A6)               ; BLTAPT
    MOVE.L  A1,$54(A6)               ; BLTDPT
    MOVE.W  #(BG_VIS_ROWS<<6)+PARALLAX_BLIT_W,$58(A6)   ; BG_VIS_ROWS righe x BLIT_W word
  
    ADD.L   #PARALLAX_STRIP_PLANE_SZ,A2
    ADD.L   #PAR_PLANE_BANDA,A1
    DBRA    D4,.plane
.done:
    MOVEM.L (SP)+,D0-D5/A1-A2
    RTS
*****************************************************************************
* 		ROUTINE DI DISEGNO DEL PANNELLO 
*****************************************************************************
DisegnaPannello:
	; Copia i 4 piani dell'arte dentro PannelloBuf, che ha il pitch del MONDO.
	; L'arte finisce a DELTA_MAPPAVERA byte dall'inizio di ogni riga, cioe' dove
	; comincia la mappa nel world buffer: cosi' il pannello appare esattamente
	; come apparirebbe il mondo a CameraX=0, e il display non va ritarato.
	; Il resto della riga resta a zero: e' fuori dalla finestra visibile.
	MOVEM.L	D0-D4/A0-A2,-(SP)

	LEA		PannelloBuf,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS,A1		; l'arte parte dove parte la mappa
	LEA		pannello,A2				; sorgente: 4 piani contigui, 40 byte per riga

	MOVEQ	#PANNELLO_BITPLANES-1,D4
	IFNE	PANNELLO_TEST_FILL
	; PROVA: invece dell'arte scrive costanti note, un valore per piano.
	; piano 0 = $FFFF, piano 1 = $0000, piano 2 = $FFFF, piano 3 = $0000
	; -> indice colore 1+4 = 5 su TUTTA la fascia, cioe' un colore solo e piatto.
	;   fascia UNIFORME del colore 5 -> buffer, puntatori e display sono sani, e
	;     il difetto sta nel blit dell'arte o nel file .raw
	;   fascia di ALTRO colore uniforme -> arrivano solo alcuni piani: si guarda
	;     quali bit mancano e si risale al puntatore sbagliato
	;   fascia NON uniforme -> il percorso di display e' rotto a monte
	LEA		PannelloBuf,A1
	ADDA.W	#PANNELLO_ART_BYTE_OFS,A1
	MOVEQ	#PANNELLO_BITPLANES-1,D4
.FillPianoPannello:
	MOVE.L	A1,A0
	MOVEQ	#0,D2
	; TUTTI i piani pieni: la fascia deve venire di UN SOLO colore, l'indice 15.
	; Qualunque zona di colore diverso dice esattamente quali piani NON arrivano
	; li': i bit accesi dell'indice sono i piani presenti. Nero = nessun piano.
	MOVE.W	#$FFFF,D2
.FillValore:
	MOVE.W	#PANNELLO_HEIGHT-1,D0
.FillRigaPannello:
	MOVE.W	#PANNELLO_BYTES_PER_ROW/2-1,D1
.FillWordPannello:
	MOVE.W	D2,(A0)+
	DBRA	D1,.FillWordPannello
	ADDA.W	#PANNELLO_BUF_PITCH-PANNELLO_BYTES_PER_ROW,A0
	DBRA	D0,.FillRigaPannello
	ADDA.L	#PANNELLO_BUF_PLANE,A1
	DBRA	D4,.FillPianoPannello
	ENDC

	IFEQ	PANNELLO_TEST_FILL
.BlittaLoopPannello:
	BSR.W	AspettaBlitter
	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM: nessuna maschera
	MOVE.L	#$09F00000,$40(A6)		; BLTCON0/1: USEA+USED, minterm $F0 (D = A)
	MOVE.W	#0,$64(A6)				; BLTAMOD: sorgente contigua
	MOVE.W	#PANNELLO_BUF_PITCH-PANNELLO_BYTES_PER_ROW,$66(A6)	; BLTDMOD
	MOVE.L	A2,$50(A6)				; BLTAPT
	MOVE.L	A1,$54(A6)				; BLTDPT
	MOVE.W	#(PANNELLO_HEIGHT<<6)|(PANNELLO_BYTES_PER_ROW/2),$58(A6)	; BLTSIZE
	ADD.L	#PANNELLO_BUF_PLANE,A1	; piano successivo nella destinazione
	ADD.L	#PANNELLO_PLANE_SIZE,A2	; piano successivo nella sorgente
	DBRA	D4,.BlittaLoopPannello
	ENDC

	; --- puntatori del pannello nella copperlist, una volta sola: e' fisso ---
	LEA		PannelloBuf,A1
	LEA		BitplanePannello,A2
	MOVEQ	#PANNELLO_BITPLANES-1,D4
	MOVEQ	#PANNELLO_PTR_RACE_N,D3	; quanti puntatori vanno compensati
.PuntaLoopPannello:
	MOVE.L	A1,D0
	; i primi RACE_N prenderanno un incremento dal DMA: glielo tolgo prima
	SUBQ.W	#1,D3
	BMI.S	.PuntaSenzaComp
	SUB.L	#PANNELLO_PTR_RACE_ADJ,D0
.PuntaSenzaComp:
	MOVE.W	D0,6(A2)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A2)				; word alta
	ADDA.L	#PANNELLO_BUF_PLANE,A1
	ADDQ.W	#8,A2
	DBRA	D4,.PuntaLoopPannello

	MOVEM.L	(SP)+,D0-D4/A0-A2
	RTS
*****************************************************************************
* InitPlayer - inizializza la struttura Player con i valori iniziali
*****************************************************************************
InitPlayer:
	MOVEM.L	A0,-(SP)

	LEA	 	Player,A0
	MOVE.W	#1,bob_Speed(A0)			; velocità default
	MOVE.W	#2,bob_Direzione(A0)		; 0 = guarda a sud
	MOVE.W	#0,bob_AnimFrame(A0)		; primo frame
	MOVE.L	#OMINO,bob_Gfx(A0)			; puntatore allo spritesheet
	MOVE.L	#OMINO_MASK,bob_Mask(A0)	; maschera per-frame dello stesso sheet
	MOVE.W	#BOB_W,bob_Larghezza(A0)
	MOVE.W	#BOB_H,bob_Altezza(A0)
	; geometria dello sheet: bastano fotogrammi e bande, il resto lo deriva
	; DisegnaBOB. I valori derivati coincidono con le vecchie EQU:
	; blitW 3, slot 6, pitch 48, banda 1536, piano 12288 = PLANE_SIZE
	MOVE.W	#OMINO_FRAMES,bob_Frames(A0)
	MOVE.W	#OMINO_DIR,bob_Bande(A0)
	MOVE.W	#ANIM_DELAY,bob_AnimDelay(A0)
		MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVE.W	#1,bob_Active(A0)
	MOVE.W	#PLAYER_SPAWN_X,bob_WorldX(A0)	; spawn: unica sorgente di verita'
	MOVE.W	#PLAYER_SPAWN_Y,bob_WorldY(A0)
	MOVE.W	#0,bob_AI(A0)
		; --- Hit Points ---
	MOVE.W	#20,bob_PF(A0)				; punti ferita iniziali
	MOVE.W	#1,bob_Damage(A0)			; player danno 1 (non utilizzato per ora, scontro)
	MOVE.W	#0,bob_Invuln(A0)			; vulnerabile all'inizio

	; --- stato per-entita' che prima erano variabili globali ---
	MOVE.W	#0,bob_VelY(A0)				; fermo in verticale
	MOVE.W	#0,bob_FracY(A0)
	MOVE.W	#0,bob_Grounded(A0)			; nasce in aria e cade sul primo tile
	MOVE.W	#0,bob_GroundedPrev(A0)		; nessun fronte al primo frame
	; La X di riferimento dei passi parte dallo spawn e non da zero: partendo
	; da zero il primo confronto vedrebbe uno spostamento di 48 px inesistente
	; e farebbe suonare un passo all'avvio.
	MOVE.W	#PLAYER_SPAWN_X,bob_PrevX(A0)
	MOVE.W	#1,bob_PassoTimer(A0)		; a 1 il primo passo parte appena cammina
	MOVE.W	#1,bob_UltimaDirX(A0)		; guarda a destra
	MOVE.W	#0,bob_Cooldown(A0)			; puo' sparare subito

	MOVEM.L	(SP)+,A0
	RTS

*****************************************************************************
* InitEnemies
*   Inizializza l'array Enemies con ENEMY_COUNT nemici, posizionati a
*   coordinate mondo predefinite.
*   bob_Active = 1 -> nemico attivo (da renderizzare)
*   bob_Active = 0 -> slot vuoto (skippato dal rendering)
*****************************************************************************
InitEnemies:
	MOVEM.L	D0/A0/A1,-(SP)

	LEA		Enemies,A0
	LEA		EnemyInitTable,A1
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; A0 = struct del nemico corrente
	; A1 = puntatore alla riga della tabella init 
	;			(8 word: WorldX, WorldY, Direzione, Active, AI, PF,
	;					 Damage, InvulnMax)
	MOVE.W	(A1)+,bob_WorldX(A0)			; posizione mondo X
	MOVE.W	(A1)+,bob_WorldY(A0)			; posizione mondo Y
	MOVE.W	(A1)+,bob_Direzione(A0)
	MOVE.W	(A1)+,bob_Active(A0)
	MOVE.W	(A1)+,bob_AI(A0)
	MOVE.W	(A1)+,bob_PF(A0)				; punti ferita iniziali
	MOVE.W	(A1)+,bob_Damage(A0)			; danno inflitto
	MOVE.W	(A1)+,bob_InvulnMax(A0)			; frame di invuln dopo hit
	MOVE.W	#0,bob_Invuln(A0)				; vulnerabile all'inizio
	MOVE.W	#1,bob_Speed(A0)
	MOVE.W	#0,bob_X(A0)
	MOVE.W	#0,bob_Y(A0)
	MOVE.W	#0,bob_AnimFrame(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#0,bob_IsMoving(A0)
	MOVE.L	#NEMICO,bob_Gfx(A0)				; spritesheet del nemico
	MOVE.L	#NEMICO_MASK,bob_Mask(A0)		; maschera per-frame del nemico
	MOVE.W	#BOB_W,bob_Larghezza(A0)
	MOVE.W	#BOB_H,bob_Altezza(A0)
	; geometria dello sheet: il nemico ha lo STESSO layout dell'omino
	MOVE.W	#OMINO_FRAMES,bob_Frames(A0)
	MOVE.W	#OMINO_DIR,bob_Bande(A0)
	MOVE.W	#ANIM_DELAY,bob_AnimDelay(A0)
	; bob_X, bob_Y verranno calcolati al rendering da World - Camera

	LEA		bob_Length(A0),A0				; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0/A0/A1
	RTS

*****************************************************************************
* InitPietra - inizializza il BOB del proiettile
*   La pietra usa la STESSA struct e le STESSE routine di disegno di player e
*   nemici: cambia solo la geometria, che ora vive nella struct invece che
*   nelle EQU globali. Sheet 256x16 a 5 piani, 8 frame da 16 px di arte in
*   slot da 32, UNA sola banda (nessuna direzione).
*   Nasce spento: lo accende, lo posiziona e lo muove Proiettile.
*****************************************************************************
InitPietra:
	MOVEM.L	A0,-(SP)

	LEA	 	BobPietra,A0
	MOVE.W	#0,bob_Active(A0)			; spento finche' non si spara
	MOVE.L	#PIETRA,bob_Gfx(A0)			; sheet della pietra
	MOVE.L	#PIETRA_MASK,bob_Mask(A0)	; maschera costruita da BuildBobMasks
	MOVE.W	#PIETRA_W,bob_Larghezza(A0)
	MOVE.W	#PIETRA_H,bob_Altezza(A0)
	; geometria dello sheet: e' QUESTO che permette di riusare DisegnaBOB.
	; Derivati a runtime: blitW 2, slot 4, pitch 32, piano 512 = PIETRA_PLANE_SIZE
	MOVE.W	#PIETRA_FRAMES,bob_Frames(A0)
	MOVE.W	#PIETRA_BANDE,bob_Bande(A0)
	; passo dell'animazione: alza o abbassa QUI per far girare la pietra
	; piu' o meno in fretta, senza toccare omino e nemici
	MOVE.W	#ANIM_DELAY,bob_AnimDelay(A0)
	; danno inflitto: era la EQU BULLET_DAMAGE letta direttamente dalla logica,
	; ora e' il campo che gia' esisteva. bob_Speed NON si usa: la pietra si
	; muove per velocita' (bob_VelX/Y), non per ottante x scalare.
	MOVE.W	#BULLET_DAMAGE,bob_Damage(A0)
	MOVE.W	#0,bob_TTL(A0)
	MOVE.W	#0,bob_VelX(A0)
	MOVE.W	#0,bob_VelY(A0)
	MOVE.W	#0,bob_FracX(A0)
	MOVE.W	#0,bob_FracY(A0)
	; stato di animazione: la pietra ruota sempre mentre vola
	MOVE.W	#0,bob_Direzione(A0)		; resta 0: lo sheet ha una banda sola
	MOVE.W	#0,bob_AnimFrame(A0)
	MOVE.W	#0,bob_FrameCont(A0)
	MOVE.W	#1,bob_IsMoving(A0)			; 1 = DisegnaBOB fa avanzare i frame
	MOVE.W	#0,bob_X(A0)
	MOVE.W	#0,bob_Y(A0)
	MOVE.W	#0,bob_WorldX(A0)
	MOVE.W	#0,bob_WorldY(A0)

	MOVEM.L	(SP)+,A0
	RTS

*****************************************************************************
* BuildBobMasks / BuildBobMask
*   Genera la maschera per-frame di uno spritesheet come OR dei suoi 5
*   bitplane: dove almeno un piano ha un bit, li' c'e' il BOB.
*   Da chiamare UNA SOLA VOLTA al boot (i dati sono statici).
*
*   La maschera esce gia' corretta anche nel margine dello shift: la word
*   di stacco fra un frame e l'altro e' nera su tutti i piani, quindi l'OR
*   la lascia a zero. E' il padding da 16 px nello sheet a garantirlo.
*
*   BuildBobMask:  IN A1 = sheet (plane 0), A0 = destinazione maschera,
*                     D2.l = byte di UN bitplane di QUESTO sheet.
*   La dimensione del piano era la EQU globale PLANE_SIZE, cioe' quella
*   dell'omino: andava bene finche' tutti gli sheet erano fatti uguali. La
*   pietra ha un piano da PIETRA_PLANE_SIZE byte, quindi ora e' un parametro.
*****************************************************************************
BuildBobMasks:
	MOVEM.L	D2/A0-A1,-(SP)
	LEA		OMINO,A1
	LEA		OMINO_MASK,A0
	MOVE.L	#PLANE_SIZE,D2
	BSR.S	BuildBobMask
	LEA		NEMICO,A1
	LEA		NEMICO_MASK,A0
	MOVE.L	#PLANE_SIZE,D2
	BSR.S	BuildBobMask
	LEA		PIETRA,A1
	LEA		PIETRA_MASK,A0
	MOVE.L	#PIETRA_PLANE_SIZE,D2
	BSR.S	BuildBobMask
	MOVEM.L	(SP)+,D2/A0-A1
	RTS

BuildBobMask:
	MOVEM.L	D0-D2/A0-A5,-(SP)

	; i cinque piani sono contigui: ognuno dista D2 byte dal precedente.
	; Con un valore in registro non si puo' piu' usare il displacement della
	; LEA (d16), che accetta solo una costante.
	MOVEA.L	A1,A2
	ADDA.L	D2,A2						; A2 = plane 1
	MOVEA.L	A2,A3
	ADDA.L	D2,A3						; A3 = plane 2
	MOVEA.L	A3,A4
	ADDA.L	D2,A4						; A4 = plane 3
	MOVEA.L	A4,A5
	ADDA.L	D2,A5						; A5 = plane 4

	; Loop a long: (byte del piano)/4 iterazioni
	MOVE.L	D2,D0
	LSR.L	#2,D0
	SUBQ.W	#1,D0
.loop:
	MOVE.L	(A1)+,D1
	OR.L	(A2)+,D1
	OR.L	(A3)+,D1
	OR.L	(A4)+,D1
	OR.L	(A5)+,D1
	MOVE.L	D1,(A0)+
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D2/A0-A5
	RTS
 
*****************************************************************************
* RettangoloScrollNelCentro
*   Decide se la camera deve scrollare in questo frame.
*   Regola: la camera scrolla solo se il player e' al centro dello schermo
*           (bob_X==CENTER_X per X, bob_Y==CENTER_Y per Y, indipendenti).
*   Se il player NON e' al centro su un asse, ScrllX/Y di quell'asse
*   viene azzerato -> camera ferma su quell'asse fino a che il player
*   non torna al centro.
*
*   Nota: bob_X/Y devono essere stati calcolati prima (AggiornaPlayerScreenPos),
*         altrimenti usiamo la posizione del frame precedente, che e' OK
*         perche' la transizione e' incrementale (1 pixel per frame).
*****************************************************************************
; Centro dello SCHERMO per il BOB, derivato invece che cablato: dipende dalla
; finestra visibile e dalla dimensione del BOB, ed entrambe sono cambiate.
; CENTER_X restava giusto per caso (144 = (320-32)/2), CENTER_Y no: 120 era
; (256-16)/2, cioe' tarato su uno schermo alto 256 righe e un BOB 16x16.
; Con BG_VIS_ROWS=176 e BOB_H=32 il valore corretto e' 72: erano 48 px di
; errore sul punto in cui la camera decide di seguire il player.
CENTER_X        EQU     (VIS_COLS*16-BOB_W)/2   ; = 144
CENTER_Y        EQU     (BG_VIS_ROWS-BOB_H)/2   ; = 72 (era 120)

RettangoloScrollNelCentro:
	MOVEM.L	D0/A0,-(SP)
	LEA		Player,A0

	; Asse X: se bob_X != CENTER_X, azzera ScrllX
	MOVE.W	bob_X(A0),D0
	CMP.W	#CENTER_X,D0
	BEQ.S	.x_centered
	CLR.W	ScrllX
.x_centered:

	; Asse Y: se bob_Y != CENTER_Y, azzera ScrllY
	MOVE.W	bob_Y(A0),D0
	CMP.W	#CENTER_Y,D0
	BEQ.S	.y_centered
	CLR.W	ScrllY
.y_centered:

	MOVEM.L	(SP)+,D0/A0
	RTS

*****************************************************************************
* IsTileBlocked
*   Controlla se la tile a (worldX, worldY) e' bloccata.
*   Input:  D0 = worldX (pixel)
*           D1 = worldY (pixel)
*   Output: D2.b = TileFlags della tile (0 = libera, !=0 = bloccata)
*           Z flag aggiornato (BEQ = libera, BNE = bloccata)
*   Modifica: D0, D1, D2
*
*   Tile fuori dai bounds della mappa sono considerate bloccate.
*****************************************************************************
IsTileBlocked:
	; Se worldX o worldY < 0 -> bloccato (fuori mappa)
	TST.W	D0
	BMI.S	.blocked
	TST.W	D1
	BMI.S	.blocked

	; tileX = worldX / 16, tileY = worldY / 16
	LSR.W	#4,D0					; D0 = tileX
	LSR.W	#4,D1					; D1 = tileY

	; Bounds check su mappa
	CMP.W	#MAPPA_COLS,D0
	BGE.S	.blocked
	CMP.W	#MAPPA_ROWS,D1
	BGE.S	.blocked

	; Calcolo offset nella mappa: (tileY * MAPPA_COLS + tileX) * 2  (word)
	MULU.W	#MAPPA_COLS,D1
	ADD.W	D0,D1
	ADD.W	D1,D1					; *2 perche' dc.w (word per ogni tile)

	; Recupero il numero di tile
	LEA		MAPPA,A1
	MOVE.W	(A1,D1.W),D2			; D2 = numero della tile

	; Lookup nel TileFlags (indicizzato come byte)
	LEA		TileFlags,A1
	MOVE.B	(A1,D2.W),D2			; D2.b = flag (0 = libera)
	; Z aggiornato dal MOVE
	RTS

.blocked:
	MOVEQ	#TF_BLOCK,D2			; non zero
	RTS

*****************************************************************************
* IsBoxBlocked
*   Il box (BOB_COLL_W x BOB_COLL_H) a (worldX, worldY) tocca tile bloccate?
*   Input:  D0 = worldX (bordo sinistro), D1 = worldY (bordo alto)
*   Output: Z flag (BEQ = libero, BNE = collide), D0/D1 preservati
*
*   NON bastano i 4 angoli: su un box piu' largo di una tile due angoli
*   opposti possono essere liberi mentre la tile IN MEZZO e' un muro, e il
*   BOB ci passa attraverso. Qui si sonda una griglia a passo 16 px (la
*   dimensione della tile) piu' sempre il bordo opposto, cosi' nessuna
*   colonna o riga di tile toccata dal box puo' sfuggire.
*   A 16x16 degenera nei soliti 4 angoli: stesso costo di prima.
*
*   NIENTE COMPENSAZIONE: il BOB e' disegnato alla SUA posizione mondo (X,Y),
*   cioe' sulle stesse tile che qui vengono controllate.
*****************************************************************************
IsBoxBlocked:
	MOVEM.L	D4-D7,-(SP)
	MOVE.W	D0,D6					; X base
	MOVE.W	D1,D7					; Y base
	MOVEQ	#0,D5					; dy
.loopY:
	MOVEQ	#0,D4					; dx
.loopX:
	MOVE.W	D6,D0
	ADD.W	D4,D0
	MOVE.W	D7,D1
	ADD.W	D5,D1
	BSR.W	IsTileBlocked			; tocca solo D0/D1/D2/A1
	TST.B	D2
	BNE.S	.fine					; una sonda bloccata basta
	CMP.W	#BOB_COLL_W-1,D4
	BEQ.S	.nextY					; era gia' il bordo destro
	ADD.W	#16,D4
	CMP.W	#BOB_COLL_W-1,D4
	BLS.S	.loopX
	MOVE.W	#BOB_COLL_W-1,D4		; ultima sonda = bordo destro
	BRA.S	.loopX
.nextY:
	CMP.W	#BOB_COLL_H-1,D5
	BEQ.S	.fine					; era gia' il bordo basso
	ADD.W	#16,D5
	CMP.W	#BOB_COLL_H-1,D5
	BLS.S	.loopY
	MOVE.W	#BOB_COLL_H-1,D5		; ultima sonda = bordo basso
	BRA.S	.loopY
.fine:
	MOVE.W	D6,D0					; ripristino gli input
	MOVE.W	D7,D1
	MOVEM.L	(SP)+,D4-D7
	TST.B	D2						; riapplico Z
	RTS
*****************************************************************************
* IsOverlapEnemies
*   Controlla se un BOB 16x16 a posizione (D0, D1) si sovrappone con
*   uno qualunque dei nemici attivi.
*
*   Due BOB 16x16 a (Xa, Ya) e (Xb, Yb) si sovrappongono se:
*     |Xa - Xb| < 16 AND |Ya - Yb| < 16
*   equivalente a:
*     (Xa - Xb) >= -15 AND (Xa - Xb) <= 15
*     (Ya - Yb) >= -15 AND (Ya - Yb) <= 15
*
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*           A2 = puntatore opzionale a un BOB DA ESCLUDERE (puo' essere 0)
*           [usato se un nemico controlla rispetto agli altri nemici, per
*            non confrontarsi con se stesso]
*   OUTPUT: Z=1 se NESSUN overlap (libero), Z=0 se overlap rilevato
*           D0/D1 preservati
*           D2 = 0 se libero, !=0 se overlap (per coerenza con IsBoxBlocked)
*           Tutti gli altri registri preservati.
*****************************************************************************
IsOverlapEnemies:
	MOVEM.L	D3-D5/A0,-(SP)

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D5
	MOVEQ	#0,D2					; default: nessun overlap
.loop:
	; Skip se nemico non attivo
	TST.W	bob_Active(A0)
	BEQ.S	.next
	; Skip se questo nemico e' quello da escludere
	CMPA.L	A2,A0
	BEQ.S	.next

	; Test sovrapposizione X: |D0 - bob_WorldX(A0)| < 16
	MOVE.W	D0,D3
	SUB.W	bob_WorldX(A0),D3		; D3 = D0 - enemyX
	; D3 in range [-15, 15] ?
	CMP.W	#-(BOB_COLL_W-1),D3
	BLT.S	.next					; troppo a sinistra -> non sovrappone
	CMP.W	#BOB_COLL_W,D3
	BGE.S	.next					; troppo a destra -> non sovrappone

	; Test sovrapposizione Y
	MOVE.W	D1,D4
	SUB.W	bob_WorldY(A0),D4		; D4 = D1 - enemyY
	CMP.W	#-(BOB_COLL_H-1),D4
	BLT.S	.next
	CMP.W	#BOB_COLL_H,D4
	BGE.S	.next

	; Sia X che Y sovrapposti -> COLLISIONE
	MOVEQ	#1,D2					; segnala overlap
	BRA.S	.done					; esci dal loop appena trovo

.next:
	LEA		bob_Length(A0),A0		; prossimo nemico
	DBRA	D5,.loop

.done:
	MOVEM.L	(SP)+,D3-D5/A0
	TST.B	D2						; setta Z in base al risultato
	RTS

*****************************************************************************
* IsOverlapPlayer
*   Controlla se un BOB 16x16 a posizione (D0, D1) si sovrappone con
*   il Player.
*   Usato dai nemici per evitare di camminare sul player.
*
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*   OUTPUT: Z=1 se NO overlap, Z=0 se overlap
*           D2 = 0 libero, !=0 overlap
*           D0/D1 preservati
*****************************************************************************
IsOverlapPlayer:
	MOVEM.L	D3-D4,-(SP)
	MOVEQ	#0,D2					; default libero

	; Test X
	MOVE.W	D0,D3
	SUB.W	Player+bob_WorldX,D3
	CMP.W	#-(BOB_COLL_W-1),D3
	BLT.S	.done
	CMP.W	#BOB_COLL_W,D3
	BGE.S	.done

	; Test Y
	MOVE.W	D1,D4
	SUB.W	Player+bob_WorldY,D4
	CMP.W	#-(BOB_COLL_H-1),D4
	BLT.S	.done
	CMP.W	#BOB_COLL_H,D4
	BGE.S	.done

	MOVEQ	#1,D2					; overlap
.done:
	MOVEM.L	(SP)+,D3-D4
	TST.B	D2
	RTS

*****************************************************************************
* IsEnemyBlocked
*   Controlla se un nemico puo' muoversi a (D0, D1):
*   - tile bloccata?
*   - sovrapposizione col player?
*   - sovrapposizione con un ALTRO nemico (escluso A2 = se stesso)?
*
*   INPUT:  D0 = WorldX candidata, D1 = WorldY candidata
*           A2 = puntatore al nemico stesso (per escluderlo da IsOverlapEnemies)
*   OUTPUT: Z=1 libero, Z=0 bloccato
*           D2 = 0 libero, !=0 bloccato
*           D0/D1 preservati
*****************************************************************************
IsEnemyBlocked:
	BSR.W	IsBoxBlocked			; tile?
	BNE.S	.blocked
	BSR.W	IsOverlapPlayer			; player?
	BNE.S	.blocked
	BSR.W	IsOverlapEnemies		; altri nemici (A2 escluso)?
	BNE.S	.blocked
	; libero
	MOVEQ	#0,D2
	RTS
.blocked:
	MOVEQ	#1,D2
	RTS

*****************************************************************************
* AggiornaNemici
*   Per ogni nemico attivo, aggiorna la sua posizione in base a bob_AI:
*     0 = fermo
*     1 = ronda su/giù
*     2 = ronda dx/sx
*     3 = caccia il player
*****************************************************************************
AggiornaNemici:
	MOVEM.L	D0/A0,-(SP)

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; Skip nemico inattivo
	TST.W	bob_Active(A0)
	BEQ.S	.next

	; Switch su bob_AI
	MOVE.W	bob_AI(A0),D1
	BEQ.S	.next					; AI=0 -> fermo
	CMP.W	#1,D1
	BEQ.S	.do_patrol
	CMP.W	#2,D1
	BEQ.S	.do_hunt
	BRA.S	.next					; AI sconosciuta -> skip

.do_patrol:
	BSR.W	AI_Patrol
	BRA.S	.next
.do_hunt:
	BSR.W	AI_Hunt

.next:
	LEA		bob_Length(A0),A0		; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0/A0
	RTS

*****************************************************************************
* LoadAGAPalette256
*   Carica una palette AGA a 256 colori dal buffer title_pal (256 long
*   $00RRGGBB) nei registri COLOR00..COLOR31, attraverso le 8 banche di
*   BPLCON3. Per ogni banca esegue due pass:
*     - LOCT=0: scrive i nibble ALTI di ogni componente RGB
*     - LOCT=1: scrive i nibble BASSI
*   Al termine ripristina BPLCON3 = $0c00 (banca 0, LOCT=0).
*****************************************************************************
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
*   8 bitplane: niente EHB, lookup diretto a 8 bit = 256 entry.
*     bit 0-4 = sfondo (0..31)   bit 5 = dark plane
*     bit 6-7 = PARALLASSE, valore 0..3 (0 = trasparente, 1/2/3 = 3 tinte)
*   Priorita' del pixel: sfondo (se != 0) COPRE lo skyline, che COPRE il cielo.
*   Scrive UNA VOLTA a init i banchi 1..7 (il banco 0 lo carica gia' la
*   copperlist a ogni frame). Schema:
*     banco 1 (32..63)   = meta' del banco 0        (sfondo notturno)
*     banco 2 (64..95)   = [C1, sfondo 1..31]       (parallasse=1, giorno)
*     banco 3 (96..127)  = meta' del banco 2        (parallasse=1, notte)
*     banco 4 (128..159) = [C2, sfondo 1..31]       (parallasse=2, giorno)
*     banco 5 (160..191) = meta' del banco 4        (parallasse=2, notte)
*     banco 6 (192..223) = [C3, sfondo 1..31]       (parallasse=3, giorno)
*     banco 7 (224..255) = meta' del banco 6        (parallasse=3, notte)
*   In ogni banco "giorno" le entry 1..31 = colori di sfondo, quindi lo sfondo
*   non-zero vince sempre; solo l'entry 0 (cielo visibile) mostra la tinta.
*   Sorgente dei 32 colori base: i blocchi copper GamePalHi/GamePalLo.
*   CHIAMARE CON IL COPPER DMA SPENTO (scrive BPLCON3 a piu' riprese).
*****************************************************************************
; Le 3 tinte dello skyline (valori 1/2/3 dei 2 bitplane di parallasse).
; Regolale a gusto: p.es. base scura, cresta, foschia chiara.
SKYLINE_C1_RGB	EQU	$182838			; parallasse valore 1
SKYLINE_C2_RGB	EQU	$2a3a52			; parallasse valore 2
SKYLINE_C3_RGB	EQU	$46608c			; parallasse valore 3

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
	LEA		GamePalBk,A0
	MOVEQ	#1,D4
	BSR.W	WriteAGABank32

	; ----- banchi 2..7: 3 tinte skyline, ognuna giorno + notte -----
	MOVE.L	#SKYLINE_C1_RGB,D3
	MOVEQ	#2,D5					; banco giorno 2 (notte = 3)
	BSR.W	.pair
	MOVE.L	#SKYLINE_C2_RGB,D3
	MOVEQ	#4,D5					; banco 4 (notte = 5)
	BSR.W	.pair
	MOVE.L	#SKYLINE_C3_RGB,D3
	MOVEQ	#6,D5					; banco 6 (notte = 7)
	BSR.W	.pair

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

.pair:								; IN: D3 = tinta skyline, D5 = banco giorno.
									; Costruisce [tinta, sfondo 1..31] -> banco D5,
									; e la sua meta' -> banco D5+1 (notturno).
									; WriteAGABank32 preserva D4-D7/A3-A6.
	LEA		GamePal24,A0
	LEA		GamePalBk,A1
	MOVE.L	D3,(A1)+				; entry 0 = tinta skyline (cielo visibile)
	ADDQ.L	#4,A0					; salta lo sfondo colore 0
	MOVEQ	#31-1,D7
.pcopy:
	MOVE.L	(A0)+,(A1)+				; entry 1..31 = colori sfondo (occlusione)
	DBRA	D7,.pcopy
	MOVE.L	D5,D4
	BSR.W	WriteAGABank32			; banco giorno

	LEA		GamePalBk,A0			; dimezza in-place -> banco notturno
	MOVEQ	#32-1,D7
.phalf:
	MOVE.L	(A0),D0
	LSR.L	#1,D0
	AND.L	#$007F7F7F,D0
	MOVE.L	D0,(A0)+
	DBRA	D7,.phalf
	LEA		GamePalBk,A0
	MOVE.L	D5,D4
	ADDQ.W	#1,D4					; banco notturno = giorno + 1
	BSR.W	WriteAGABank32
	RTS

*****************************************************************************
* WriteAGABank32
*   Scrive 32 colori AGA nel banco D4 (0..7). A0 = 32 long $00RRGGBB.
*   Stessa meccanica hi/lo di LoadAGAPalette256, parametrizzata sul banco.
*   DISTRUGGE: D0-D3/A0-A2 (preserva D4). Richiede A6 = $DFF000.
*****************************************************************************
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


*****************************************************************************
* ShowTitle
*   1) Patcha i puntatori BPL1..8PT della TitleCopperList su title_bpl.
*   2) Carica la palette AGA 256 colori via CPU da title_pal.
*   3) Punta il copper a TitleCopperList e abilita BPL+COPPER DMA.
*****************************************************************************
ShowTitle:
	MOVEM.L	D0-D1/A1/A6,-(SP)
	LEA		$DFF000,A6

	; --- Setup display via CPU (ridondante con la copperlist ma garantisce
	;     valori corretti gia' al primo frame, anche se il copper non parte). ---
	MOVE.W	#$0211,$100(A6)			; BPLCON0: BPU3=1 (=8 BPL) + COLOR + ECSENA (no UHRES)
	MOVE.W	#$0000,$102(A6)			; BPLCON1
	MOVE.W	#$0024,$104(A6)			; BPLCON2: PF2P=4, PF1P=4 (come gioco)
	MOVE.W	#BPLCON3_BRDRBLNK,$106(A6)	; BPLCON3: banca 0, LOCT=0, bordo NERO
	MOVE.W	#$0000,$10c(A6)			; BPLCON4
	MOVE.W	#$0000,$108(A6)			; BPL1MOD (sequential layout)
	MOVE.W	#$0000,$10a(A6)			; BPL2MOD
	; AGA 8 BPL lores FMODE=3: DDFSTRT/STOP allineati al fetch interval di 32cc.
	; ($A8 - $28) / 32 = 4 -> esattamente 5 fetch per riga, 5*64px = 320px.
	MOVE.W	#$0028,$92(A6)			; DDFSTRT
	MOVE.W	#$00a8,$94(A6)			; DDFSTOP (5 fetch FMODE=3 allineati)
	MOVE.W	#$2c81,$8e(A6)			; DIWSTRT
	MOVE.W	#$2cc1,$90(A6)			; DIWSTOP

	; --- Setup BPL pointers via CPU (8 plane SEQUENTIAL, 10240 byte/plane) ---
	MOVE.L	#title_bpl,$E0(A6)								; BPL1PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE,$E4(A6)				; BPL2PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*2,$E8(A6)			; BPL3PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*3,$EC(A6)			; BPL4PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*4,$F0(A6)			; BPL5PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*5,$F4(A6)			; BPL6PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*6,$F8(A6)			; BPL7PT
	MOVE.L	#title_bpl+TITLE_PLANE_SIZE*7,$FC(A6)			; BPL8PT

	; --- Patch BPL pointers anche nella TitleCopperList (per i frame
	;     successivi al primo: il copper li resetta a ogni vertical blank). ---
	LEA		TitleBPL_0,A1
	MOVE.L	#title_bpl,D0
	MOVEQ	#8-1,D1
.bpl_loop:
	MOVE.W	D0,6(A1)				; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)				; word alta
	SWAP	D0
	ADD.L	#TITLE_PLANE_SIZE,D0	; prossimo plane (sequential)
	ADDQ.L	#8,A1
	DBRA	D1,.bpl_loop

	; --- Carica palette AGA 256 colori via CPU ---
	BSR.W	LoadAGAPalette256

	; --- Ordine identico al setup del gioco: DMA on, COP1LC, strobe ---
 	MOVE.W	#$8380,$96(A6)				; SET + DMAEN + BPLEN + COPEN
	MOVE.L	#TitleCopperList,$80(A6)	; COP1LCH
	MOVE.W	D0,$88(A6)					; COPJMP1 strobe

	MOVEM.L	(SP)+,D0-D1/A1/A6
	RTS

*****************************************************************************
* WaitTitleInput
*   Attende che venga premuto SPACE o il tasto fire del joystick (port 1).
*   Aspetta poi il rilascio di entrambi prima di tornare, in modo che il
*   gioco non veda subito un evento di sparo o un edge "spurio".
*****************************************************************************
WaitTitleInput:
	MOVEM.L	D0,-(SP)
.wait_press:
	BSR.W	AspettaVBL
	BSR.W	LeggiTastiera				; aggiorna key_space
	TST.B	key_space
	BNE.S	.pressed
	MOVE.B	$bfe001,D0					; CIA-A PRA: bit 7 = fire joy1 (active low)
	NOT.B	D0
	AND.B	#$80,D0
	BEQ.S	.wait_press					; D0=0 -> fire NON premuto
.pressed:
.wait_release:
	BSR.W	AspettaVBL
	BSR.W	LeggiTastiera
	TST.B	key_space
	BNE.S	.wait_release
	MOVE.B	$bfe001,D0
	NOT.B	D0
	AND.B	#$80,D0
	BNE.S	.wait_release				; D0!=0 -> fire ANCORA premuto

	; Reset stato fire per il gioco
	MOVE.W	#0,FirePrev
	MOVE.B	#0,key_space
	MOVEM.L	(SP)+,D0
	RTS

*****************************************************************************
* PlaySfx
*   Suona un sound effect via PT Player.
*   INPUT:  A0 = puntatore SfxStructure (sfx_ptr/len/per/vol/cha/pri)
*   OUTPUT: nessuno (lo status del canale ritornato da _mt_playfx e' ignorato)
*   Preserva tutti i registri. Non richiede A6 settato dal chiamante.
*****************************************************************************
PlaySfx:
	MOVEM.L	D0-D7/A0-A6,-(SP)
	LEA		$DFF000,A6
	JSR		_mt_playfx			; A0 = SfxStructure
	MOVEM.L	(SP)+,D0-D7/A0-A6
	RTS

*****************************************************************************
* SuonoPassi
*   Decide se far sentire un passo in questo frame.
*
*   Regola voluta: si sente mentre il player CAMMINA, non mentre salta e non
*   da fermo. Unica eccezione l'ATTERRAGGIO, che suona anche se il player
*   arriva a terra senza spostarsi di lato.
*
*   "Cammina" = a terra E con la X MONDO cambiata rispetto al frame scorso.
*
*   Prima si guardava ScrllX, ed era sbagliato: ScrllX e' lo scroll della
*   CAMERA, e RettangoloScrollNelCentro lo azzera ogni volta che il player non
*   e' al centro dello schermo. Risultato, camminando senza far scorrere lo
*   sfondo non si sentiva nulla. bob_WorldX invece e' il player, non la
*   telecamera: cambia se e solo se ha camminato davvero, quindi resta zitto
*   anche contro un muro o al bordo mappa, dove il movimento viene rifiutato.
*
*   In 8 direzioni (GravityOn=0) il salto non esiste e bob_Grounded resta a
*   zero, quindi li' il requisito "a terra" si salta e basta il movimento.
*****************************************************************************
SuonoPassi:
	MOVEM.L	D0-D1/A0,-(SP)

	; ----- atterraggio: fronte di salita di bob_Grounded -----
	MOVE.W	Player+bob_Grounded,D0
	MOVE.W	Player+bob_GroundedPrev,D1
	MOVE.W	D0,Player+bob_GroundedPrev			; sempre aggiornato, anche senza fronte
	TST.W	D0
	BEQ.S	.non_a_terra			; ora e' in aria
	TST.W	D1
	BEQ.S	.suona					; era in aria e ora no: ATTERRATO
.non_a_terra:

	; ----- passi mentre cammina -----
	TST.W	GravityOn
	BEQ.S	.controlla_moto			; 8 direzioni: niente salto, niente requisito
	TST.W	Player+bob_Grounded
	BEQ.S	.fermo					; in aria: silenzio
.controlla_moto:
	; si e' spostato in orizzontale rispetto al frame scorso?
	MOVE.W	Player+bob_WorldX,D0
	CMP.W	Player+bob_PrevX,D0
	BEQ.S	.fermo					; stessa X: silenzio

	SUBQ.W	#1,Player+bob_PassoTimer
	BGT.S	.fine					; non e' ancora ora
.suona:
	MOVE.W	#PASSO_INTERVALLO,Player+bob_PassoTimer
	LEA		SfxPasso,A0
	BSR.W	PlaySfx
	BRA.S	.fine

.fermo:
	; Fermo o in aria: si riarma a 1 cosi' il passo successivo parte subito
	; quando riprende a camminare, invece di far aspettare mezzo intervallo.
	MOVE.W	#1,Player+bob_PassoTimer
.fine:
	; La X di riferimento si aggiorna QUI e non nel ramo che suona: l'uscita e'
	; una sola, quindi cosi' e' aggiornata su OGNI percorso. Aggiornandola solo
	; quando suona, un frame di sosta lascerebbe un valore vecchio e il
	; confronto successivo farebbe scattare un passo falso.
	MOVE.W	Player+bob_WorldX,Player+bob_PrevX
	MOVEM.L	(SP)+,D0-D1/A0
	RTS

*****************************************************************************
* Proiettile
*   Gestisce il proiettile (1 alla volta): fuoco, lancio, parabola,
*   atterraggio e collisione coi nemici.
*   (l'intestazione diceva ancora "ProcessBullet", nome che non esiste piu')
*****************************************************************************
Proiettile:
	MOVEM.L	D0-D5/A0-A2,-(SP)

	; A2 e non A1: IsTileBlocked usa A1 come appoggio e la distrugge, e qui
	; sotto la chiamiamo per sapere se la pietra ha toccato terra.
	LEA		BobPietra,A2			; A2 = il proiettile per tutta la routine

	IFNE	BULLET_DEBUG
	; PROVA: pietra sempre accesa e inchiodata a schermo fisso.
	MOVE.W	TileX,D0
	LSL.W	#4,D0
	ADD.W	PixelOffX,D0
	ADD.W	#BULLET_DEBUG_X,D0
	MOVE.W	D0,bob_WorldX(A2)
	MOVE.W	TileY,D0
	LSL.W	#4,D0
	ADD.W	PixelOffY,D0
	ADD.W	#BULLET_DEBUG_Y,D0
	MOVE.W	D0,bob_WorldY(A2)
	MOVE.W	#1,bob_Active(A2)
	BRA.W	.esci
	ENDC

	; Ricorda l'ultima direzione ORIZZONTALE del player. La pietra si lancia
	; sempre di lato: se il player guarda in su o in giu' l'ottante non da'
	; nessun verso, e senza memoria il tiro partirebbe sempre a destra.
	LEA		Player,A0
	MOVE.W	bob_Direzione(A0),D0
	AND.W	#7,D0
	LSL.W	#2,D0
	LEA		DirectionDeltas,A0
	MOVE.W	(A0,D0.W),D0			; dx dell'ottante: -1, 0 oppure +1
	BEQ.S	.dir_invariata			; N o S: nessuna orizzontale, tieni l'ultima
	MOVE.W	D0,Player+bob_UltimaDirX
.dir_invariata:

	; Decrementa cooldown se > 0. Il cooldown vive nel PLAYER e non nella
	; pietra: e' stato di CHI SPARA, non del proiettile. Se stesse in
	; BobPietra si azzererebbe insieme al sasso e si potrebbe sparare a
	; raffica ricaricando ad ogni impatto.
	MOVE.W	Player+bob_Cooldown,D0
	BEQ.S	.cooldown_done
	SUBQ.W	#1,D0
	MOVE.W	D0,Player+bob_Cooldown
.cooldown_done:

	; ----- Stato fire corrente -----
	MOVE.B	$bfe001,D0
	NOT.B	D0
	AND.B	#$80,D0
	BEQ.S	.no_joy_fire
	MOVEQ	#1,D1
	BRA.S	.fire_check_space
.no_joy_fire:
	MOVEQ	#0,D1
.fire_check_space:
	TST.B	key_space
	BEQ.S	.fire_done
	MOVEQ	#1,D1
.fire_done:

	; ----- Il proiettile e' vivo? Lo dice la sua struct, non piu' una
	; ----- variabile parallela.
	TST.W	bob_Active(A2)
	BNE.W	.update_bullet

	; Non attivo: edge detection + cooldown
	TST.W	D1
	BEQ.W	.save_fire
	TST.W	FirePrev
	BNE.W	.save_fire
	TST.W	Player+bob_Cooldown
	BNE.W	.save_fire

	; --- SPAWN! ---
	; Il proiettile nasce col proprio CENTRO sul centro del player. I due
	; mezzi-fotogrammi vengono da bob_Larghezza/bob_Altezza invece che da un
	; +8 cablato, che era il centro di un bob 16x16 e non e' mai stato
	; aggiornato quando i bob sono passati a 32x32.
	LEA		Player,A0
	MOVE.W	bob_WorldX(A0),D2
	MOVE.W	bob_Larghezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro X del player
	MOVE.W	bob_Larghezza(A2),D3
	LSR.W	#1,D3
	SUB.W	D3,D2					; meno mezzo proiettile
	MOVE.W	D2,bob_WorldX(A2)
	MOVE.W	bob_WorldY(A0),D2
	MOVE.W	bob_Altezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro Y del player
	MOVE.W	bob_Altezza(A2),D3
	LSR.W	#1,D3
	SUB.W	D3,D2
	MOVE.W	D2,bob_WorldY(A2)

	; Velocita' iniziale del lancio: 30 gradi sull'orizzontale, verso l'ultima
	; direzione orizzontale valida. La verticale e' NEGATIVA perche' la Y
	; cresce verso il basso, quindi "su" e' meno.
	MOVE.W	#PIETRA_VEL_X,D2
	MULS.W	Player+bob_UltimaDirX,D2			; +vx a destra, -vx a sinistra
	MOVE.W	D2,bob_VelX(A2)
	MOVE.W	#-PIETRA_VEL_Y,bob_VelY(A2)
	CLR.W	bob_FracX(A2)			; la frazione riparte da zero a ogni lancio
	CLR.W	bob_FracY(A2)

	MOVE.W	#1,bob_Active(A2)
	MOVE.W	#PIETRA_RAGGIO,bob_TTL(A2)	; gittata residua, in PIXEL
	MOVE.W	#BULLET_COOLDOWNC,Player+bob_Cooldown
	LEA		SfxSparo,A0
	BSR.W	PlaySfx
	BRA.W	.save_fire

.update_bullet:
	; ----- PARABOLA -----
	; L'orizzontale resta costante, la verticale accelera verso il basso: e'
	; tutta qui la differenza fra un lancio e il vecchio tiro rettilineo.
	ADD.W	#PIETRA_GRAVITA,bob_VelY(A2)

	; X: si somma la velocita' alla frazione accumulata, si portano nel mondo
	; i pixel INTERI che ne escono e si tiene il resto per il frame dopo.
	; L'ASR ha segno, quindi funziona anche andando a sinistra: con frazione 0
	; e velocita' -1365 si ottengono -6 px e una frazione di 171/256, che
	; sommati fanno esattamente -5,33.
	MOVE.W	bob_FracX(A2),D2
	ADD.W	bob_VelX(A2),D2
	MOVE.W	D2,D3
	ASR.W	#8,D3					; pixel interi, con segno
	ADD.W	D3,bob_WorldX(A2)
	AND.W	#$00FF,D2				; resta solo la frazione
	MOVE.W	D2,bob_FracX(A2)

	; La gittata si consuma in PIXEL, non in frame: bob_TTL dice quanti ne
	; restano dei PIETRA_RAGGIO di partenza. Contare i pixel fa valere il
	; tetto alla lettera, qualunque cosa facciano parabola e terreno.
	TST.W	D3
	BPL.S	.dx_positivo
	NEG.W	D3						; verso sinistra: conta il valore assoluto
.dx_positivo:
	SUB.W	D3,bob_TTL(A2)
	BGT.S	.muovi_y
	CLR.W	bob_Active(A2)			; gittata esaurita
	BRA.W	.save_fire
.muovi_y:
	; Y: stessa aritmetica della X
	MOVE.W	bob_FracY(A2),D2
	ADD.W	bob_VelY(A2),D2
	MOVE.W	D2,D3
	ASR.W	#8,D3
	ADD.W	D3,bob_WorldY(A2)
	AND.W	#$00FF,D2
	MOVE.W	D2,bob_FracY(A2)

.check_bullet_bounds:
	; Gli stessi limiti che usa il cull di DisegnaBOB: cosi' il proiettile non
	; resta vivo nella logica dopo essere sparito dal disegno.
	MOVE.W	bob_WorldX(A2),D2
	BMI.S	.bullet_off
	MOVE.W	#MAPPA_COLS*16,D3
	SUB.W	bob_Larghezza(A2),D3
	CMP.W	D3,D2
	BGT.S	.bullet_off
	MOVE.W	bob_WorldY(A2),D2
	BMI.S	.bullet_off
	MOVE.W	#MAPPA_ROWS*16,D3
	SUB.W	bob_Altezza(A2),D3
	CMP.W	D3,D2
	BGT.S	.bullet_off
	BRA.S	.check_atterraggio
.bullet_off:
	CLR.W	bob_Active(A2)
	BRA.W	.save_fire

.check_atterraggio:
	; ----- ATTERRAGGIO -----
	; Si sonda la tile sotto il CENTRO della pietra: essendo 16x16 come una
	; tile, un solo campione basta, e ferma anche il tiro che va a sbattere di
	; lato contro un muro invece che a terra.
	MOVE.W	bob_WorldX(A2),D0
	MOVE.W	bob_Larghezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D0					; centro X
	MOVE.W	bob_WorldY(A2),D1
	MOVE.W	bob_Altezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D1					; centro Y
	BSR.W	IsTileBlocked			; NB: distrugge D0/D1/D2 e A1
	TST.B	D2						; 0 = tile libera (come fa IsBoxBlocked:
	BEQ.S	.check_bullet_collision	;  si ricontrolla D2 invece di fidarsi
	CLR.W	bob_Active(A2)			;  del flag Z attraverso la BSR)
	BRA.W	.save_fire

.check_bullet_collision:
	; Centro del proiettile, calcolato una volta sola per tutto il ciclo.
	MOVE.W	bob_WorldX(A2),D4
	MOVE.W	bob_Larghezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D4					; D4 = centro X del proiettile
	MOVE.W	bob_WorldY(A2),D5
	MOVE.W	bob_Altezza(A2),D2
	LSR.W	#1,D2
	ADD.W	D2,D5					; D5 = centro Y del proiettile

	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.coll_loop:
	TST.W	bob_Active(A0)
	BEQ.S	.coll_next

	; Distanza fra i due CENTRI, entrambi derivati dalle dimensioni vere.
	MOVE.W	bob_WorldX(A0),D2
	MOVE.W	bob_Larghezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro X del nemico
	SUB.W	D4,D2
	BPL.S	.coll_absx
	NEG.W	D2
.coll_absx:
	CMP.W	#BULLET_HIT_DIST,D2
	BGE.S	.coll_next

	MOVE.W	bob_WorldY(A0),D2
	MOVE.W	bob_Altezza(A0),D3
	LSR.W	#1,D3
	ADD.W	D3,D2					; centro Y del nemico
	SUB.W	D5,D2
	BPL.S	.coll_absy
	NEG.W	D2
.coll_absy:
	CMP.W	#BULLET_HIT_DIST,D2
	BGE.S	.coll_next

	; HIT!
	MOVE.W	bob_PF(A0),D2
	SUB.W	bob_Damage(A2),D2		; danno del proiettile, dalla SUA struct
	BPL.S	.coll_hit_alive
	MOVEQ	#0,D2
.coll_hit_alive:
	MOVE.W	D2,bob_PF(A0)
	MOVE.W	#2,bob_AI(A0)
	MOVE.W	bob_InvulnMax(A0),bob_Invuln(A0)
	CLR.W	bob_Active(A2)			; il proiettile si consuma nel colpo
	TST.W	bob_PF(A0)
	BNE.S	.sfx_hit_alive
	CLR.W	bob_Active(A0)
	LEA		SfxNemicoMorto,A0
	BSR.W	PlaySfx
	BRA.S	.save_fire
.sfx_hit_alive:
	LEA		SfxNemicoColpito,A0
	BSR.W	PlaySfx
	BRA.S	.save_fire

.coll_next:
	LEA		bob_Length(A0),A0
	DBRA	D0,.coll_loop

.save_fire:
	MOVE.W	D1,FirePrev
.esci:
	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

*****************************************************************************
* ProcessCombat
*   Gestisce gli scontri player <-> nemici.
*   Logica:
*   1. Decrementa Invuln di tutti i BOB (player + nemici)
*   2. Per ogni nemico attivo non invulnerabile e player non invulnerabile:
*      - se in collisione (AABB):
*        - player.PF -= nemico.Damage
*        - nemico.PF -= player.Damage
*        - entrambi Invuln = 50
*        - se PF <= 0: morte (Active=0 per nemico; flag per player)
*****************************************************************************
Combattimento:
	MOVEM.L	D0-D5/A0/A1,-(SP)

	; --- Decrementa Invuln del player ---
	LEA		Player,A1
	MOVE.W	bob_Invuln(A1),D2
	BEQ.S	.player_inv_done
	SUBQ.W	#1,D2
	MOVE.W	D2,bob_Invuln(A1)
.player_inv_done:

	; --- Loop nemici ---
	LEA		Enemies,A0
	MOVEQ	#ENEMY_COUNT-1,D0
.loop:
	; Skip nemico non attivo
	TST.W	bob_Active(A0)
	BEQ.W	.next

	; Decrementa Invuln del nemico
	MOVE.W	bob_Invuln(A0),D2
	BEQ.S	.check_collision
	SUBQ.W	#1,D2
	MOVE.W	D2,bob_Invuln(A0)
	BRA.W	.next						; se era invulnerabile, no collision check

.check_collision:
	; Test overlap player-nemico (AABB, soglia 17 = anche contatto tangente)
	; IsOverlapEnemies usa soglia 16 = i BOB possono essere adiacenti (dx=16 esatto)
	; Combattimento usa 17 per scattare anche quando si toccano sui bordi.
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	bob_WorldX(A1),D1
	BPL.S	.absx_ok
	NEG.W	D1
.absx_ok:
	CMP.W	#17,D1
	BGE.W	.next						; no overlap X

	MOVE.W	bob_WorldY(A0),D1
	SUB.W	bob_WorldY(A1),D1
	BPL.S	.absy_ok
	NEG.W	D1
.absy_ok:
	CMP.W	#17,D1
	BGE.W	.next						; no overlap Y

	; --- COLLISIONE GEOMETRICA! ---
	; Ognuno infligge danno solo se sta GUARDANDO il bersaglio.
	; "Guardare" = octante del vettore verso il bersaglio entro ±1 da bob_Direzione.

	; --- 1) Player colpisce nemico se guarda verso nemico ---
	MOVE.W	bob_WorldX(A0),D4
	SUB.W	bob_WorldX(A1),D4			; D4 = dx (nemico.X - player.X)
	MOVE.W	bob_WorldY(A0),D5
	SUB.W	bob_WorldY(A1),D5			; D5 = dy (nemico.Y - player.Y)
	BSR.W	DirezioneVerso				; D4 = octante player -> nemico
	MOVE.W	bob_Direzione(A1),D5
	BSR.W	OctantsClose				; D5 = 1 se vicini
	TST.W	D5
	BEQ.S	.player_no_hit
	; Player colpisce nemico
	MOVE.W	bob_Damage(A1),D1			; danno player
	MOVE.W	bob_PF(A0),D2
	SUB.W	D1,D2
	BPL.S	.enemy_alive
	MOVE.W	#0,D2
.enemy_alive:
	MOVE.W	D2,bob_PF(A0)
	MOVE.W	bob_InvulnMax(A0),bob_Invuln(A0)
	; Cambia AI nemico a Hunt (allarme!)
	MOVE.W	#2,bob_AI(A0)
	TST.W	bob_PF(A0)
	BNE.S	.player_no_hit
	MOVE.W	#0,bob_Active(A0)
.player_no_hit:

	; --- 2) Nemico colpisce player se guarda verso player ---
	; Player era invulnerabile? Skip
	TST.W	bob_Invuln(A1)
	BNE.W	.next
	MOVE.W	bob_WorldX(A1),D4
	SUB.W	bob_WorldX(A0),D4			; D4 = dx (player.X - nemico.X)
	MOVE.W	bob_WorldY(A1),D5
	SUB.W	bob_WorldY(A0),D5			; D5 = dy (player.Y - nemico.Y)
	BSR.W	DirezioneVerso				; D4 = octante nemico -> player
	MOVE.W	bob_Direzione(A0),D5
	BSR.W	OctantsClose
	TST.W	D5
	BEQ.W	.next
	; Nemico colpisce player
	MOVE.W	bob_Damage(A0),D1			; danno nemico
	MOVE.W	bob_PF(A1),D2
	SUB.W	D1,D2
	BPL.S	.player_alive
	MOVE.W	#0,D2
.player_alive:
	MOVE.W	D2,bob_PF(A1)
	MOVE.W	bob_InvulnMax(A1),bob_Invuln(A1)
	LEA		SfxHitPlayer,A0
	BSR.W	PlaySfx
.next:
	LEA		bob_Length(A0),A0			; prossimo nemico
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D5/A0/A1
	RTS

*****************************************************************************
* DirezioneVerso
*   Calcola l'octante (direzione 0..7) di un vettore (dx, dy).
*   INPUT:  D4.w = dx, D5.w = dy
*   OUTPUT: D4.w = octante 0..7 secondo la convenzione bob_Direzione:
*           0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
*   Se dx = dy = 0, ritorna 0 (E) come default.
*****************************************************************************
DirezioneVerso:
	MOVEM.L	D0-D3,-(SP)

	; Segni e valori assoluti
	MOVE.W	D4,D0					; D0 = dx
	MOVE.W	D5,D1					; D1 = dy
	; |dx|
	MOVE.W	D0,D2
	BPL.S	.ax_ok
	NEG.W	D2
.ax_ok:
	; |dy|
	MOVE.W	D1,D3
	BPL.S	.ay_ok
	NEG.W	D3
.ay_ok:
	; Default octante 0
	MOVEQ	#0,D4

	; Caso dx==dy==0 -> resta 0
	TST.W	D2
	BNE.S	.check
	TST.W	D3
	BEQ.S	.done
.check:
	; Regole:
	;   |dx| > 2*|dy| -> orizzontale puro (E o W)
	;   |dy| > 2*|dx| -> verticale puro (S o N)
	;   altrimenti -> diagonale

	; Confronto: 2*|dy| < |dx| ?
	MOVE.W	D3,D5
	ADD.W	D5,D5					; D5 = 2*|dy|
	CMP.W	D2,D5
	BGE.S	.not_horiz
	; Orizzontale puro
	TST.W	D0
	BMI.S	.W_dir
	MOVEQ	#0,D4					; E
	BRA.S	.done
.W_dir:
	MOVEQ	#4,D4					; W
	BRA.S	.done
.not_horiz:
	; |dy| > 2*|dx| ?
	MOVE.W	D2,D5
	ADD.W	D5,D5					; D5 = 2*|dx|
	CMP.W	D3,D5
	BGE.S	.diagonal
	; Verticale puro
	TST.W	D1
	BMI.S	.N_dir
	MOVEQ	#2,D4					; S
	BRA.S	.done
.N_dir:
	MOVEQ	#6,D4					; N
	BRA.S	.done
.diagonal:
	; Diagonale: 4 casi su (segno_dx, segno_dy)
	TST.W	D0
	BMI.S	.diag_W
	; dx >= 0
	TST.W	D1
	BMI.S	.NE_dir
	MOVEQ	#1,D4					; SE
	BRA.S	.done
.NE_dir:
	MOVEQ	#7,D4					; NE
	BRA.S	.done
.diag_W:
	; dx < 0
	TST.W	D1
	BMI.S	.NW_dir
	MOVEQ	#3,D4					; SW
	BRA.S	.done
.NW_dir:
	MOVEQ	#5,D4					; NW
.done:
	MOVEM.L	(SP)+,D0-D3
	RTS

*****************************************************************************
* OctantsClose
*   Verifica se due octanti (0..7) sono "vicini" entro ±1 modulo 8.
*   INPUT:  D4.w = octante A, D5.w = octante B (sara' bob_Direzione)
*   OUTPUT: D5.w = 1 se vicini (|A-B| <= 1 modulo 8), 0 altrimenti
*****************************************************************************
OctantsClose:
	MOVEM.L	D0,-(SP)

	; D0 = (A - B) modulo 8
	MOVE.W	D4,D0
	SUB.W	D5,D0
	AND.W	#7,D0					; modulo 8

	; "Close" se D0 == 0, 1, o 7
	MOVEQ	#0,D5					; default = non vicini
	TST.W	D0
	BEQ.S	.close
	CMP.W	#1,D0
	BEQ.S	.close
	CMP.W	#7,D0
	BNE.S	.done
.close:
	MOVEQ	#1,D5
.done:
	MOVEM.L	(SP)+,D0
	RTS

*****************************************************************************
* AnimaFalo
*   Gestisce l'animazione del falò (sprite hardware SPR0):
*   - Avanza FaloAnimFrame ogni FaloAnimSpeed frame
*   - Trova la prima tile 19 nella viewport e calcola posizione schermo
*   - Costruisce SPRPOS/SPRCTL per quel frame
*   - Aggiorna SPR0PT nella copperlist (Sprites entry)
*   Se nessuna tile 19 visibile: SPR0PT -> EmptySprite (invisibile).
*****************************************************************************
AnimaFalo:
	MOVEM.L	D0-D7/A0-A4,-(SP)
	
	; ----- Di giorno (NightMode=0): sprite invisibile, esci subito -----
	TST.B	NightMode
	BNE.S	.is_night
	; Giorno: SPR0 -> EmptySprite
	MOVE.L	#EmptySprite,D0
	LEA		Sprites,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	BRA.W	.done
.is_night:
	; ----- Avanza il frame di animazione ogni FaloAnimSpeed frame -----
	ADDQ.W	#1,FaloAnimDelay
	CMP.W	#FaloAnimSpeed,FaloAnimDelay
	BLT.S	.no_advance
	CLR.W	FaloAnimDelay
	ADDQ.W	#1,FaloAnimFrame
	CMP.W	#6,FaloAnimFrame
	BLT.S	.no_advance
	CLR.W	FaloAnimFrame
.no_advance:

	; ===== DEBUG: posizione fissa basata su tile 19 in MAPPA[15][5] =====
	; Sottraggo TileX/TileY per compensare lo scroll
	; D3 = 5 - TileX, D7 = 15 - TileY
	; (Verificato: lo sprite NON e' la causa dello sfarfallio sulle ultime
	;  ~12 scanline - quello e' contesa DMA blitter/bitplane su AGA FMODE=3.)
	MOVE.W	#5,D3
	SUB.W	TileX,D3				; D3 = col buffer della tile 19
	MOVE.W	#15,D7
	SUB.W	TileY,D7				; D7 = row buffer della tile 19

	; Cull: se fuori dal buffer visibile, sprite invisibile
	TST.W	D3
	BMI.W	.no_falo
	CMP.W	#BUFFER_COLS,D3
	BGE.W	.no_falo
	TST.W	D7
	BMI.W	.no_falo
	CMP.W	#BUFFER_ROWS,D7
	BGE.W	.no_falo

	BRA.W	.found_falo

.no_falo:
	; Sprite invisibile (fuori viewport)
	MOVE.L	#EmptySprite,D0
	LEA		Sprites,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	BRA.W	.done

.found_falo:
	; D3 = col buffer, D7 = row buffer
	; Gli sprite hardware sono posizionati in coordinate SCHERMO, mentre le tile
	; sono disegnate a partire da BG_ORIGIN dentro il buffer. La differenza fra
	; le due va tolta qui: BG_ORIGIN_X e' in byte (x8 per avere i pixel),
	; BG_ORIGIN_Y e' gia' in righe. Con l'origine a zero questi due termini
	; spariscono da soli. Prima erano due -16 cablati, giustificati da un
	; commento che parlava di "sfasamento di 1 tile": era proprio BG_ORIGIN.
	MOVE.W	D3,D0
	LSL.W	#4,D0					; D0 = D3*16
	SUBI.W	#BG_ORIGIN_X*8,D0		; compensa l'origine del mondo (px)
	SUB.W	PixelOffX,D0			; D0 = topleft_x

	MOVE.W	D7,D1
	LSL.W	#4,D1
	SUBI.W	#BG_ORIGIN_Y,D1
	SUB.W	PixelOffY,D1			; D1 = topleft_y

	; ----- Costruisco SPRPOS/SPRCTL -----
	; VSTART_reg = $2C + screen_y
	; VSTOP_reg  = VSTART_reg + 16
	; HSTART_reg = $81 + screen_x  (pixel lores 1-to-1)
	ADDI.W	#DIW_V_START,D1			; D1 = VSTART (agganciato alla finestra)
	MOVE.W	D1,D2
	ADDI.W	#16,D2					; D2 = VSTOP

	ADDI.W	#DIW_H_START,D0			; D0 = HSTART (agganciato alla finestra)

	; ----- Costruisco SPRPOS/SPRCTL -----
	; SPRPOS: bit 15-8 = SV7-SV0 (= VSTART[7:0])
	;         bit 7-0  = SH8-SH1 (= HSTART[8:1])  <- importante!
	; SPRCTL: bit 15-8 = EV7-EV0 (= VSTOP[7:0])
	;         bit 7    = ATT
	;         bit 2    = SV8 (= VSTART[8])
	;         bit 1    = EV8 (= VSTOP[8])
	;         bit 0    = SH0 (= HSTART[0])

	; D3 = SPRPOS (build): (VSTART[7:0] << 8) | (HSTART[8:1])
	MOVE.W	D1,D3
	ANDI.W	#$FF,D3
	LSL.W	#8,D3					; bit 15-8 = VSTART[7:0]
	MOVE.W	D0,D4
	LSR.W	#1,D4					; D4 = HSTART >> 1
	ANDI.W	#$FF,D4
	OR.W	D4,D3					; D3 = SPRPOS

	; D5 = SPRCTL (build): (VSTOP[7:0] << 8) | flags
	MOVE.W	D2,D5
	ANDI.W	#$FF,D5
	LSL.W	#8,D5					; bit 15-8 = VSTOP[7:0]
	BTST	#8,D1
	BEQ.S	.no_v8a
	BSET	#2,D5					; VSTART[8] (SV8)
.no_v8a:
	BTST	#8,D2
	BEQ.S	.no_v8b
	BSET	#1,D5					; VSTOP[8] (EV8)
.no_v8b:
	BTST	#0,D0
	BEQ.S	.no_h0
	BSET	#0,D5					; HSTART[0] (SH0)
.no_h0:

	; ----- Scrivo SPRPOS/SPRCTL in TUTTI i 6 frame -----
	; Cosi' qualunque sia il frame corrente, la posizione e' sempre corretta.
	LEA		FaloFrameTable,A0
	MOVEQ	#6-1,D7					; 6 frame
.write_pos_loop:
	MOVE.L	(A0)+,A2				; A2 = FuocoFrame_N
	MOVE.W	D3,(A2)					; SPRPOS
	MOVE.W	D5,2(A2)				; SPRCTL
	DBRA	D7,.write_pos_loop

	; ----- Aggiorno SPR0PT nella copperlist (Sprites entry) -----
	LEA		FaloFrameTable,A0
	MOVE.W	FaloAnimFrame,D4
	LSL.W	#2,D4
	MOVE.L	(A0,D4.W),D0			; D0 = FuocoFrame_N corrente
	LEA		Sprites,A1
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)

.done:
	MOVEM.L	(SP)+,D0-D7/A0-A4
	RTS

*****************************************************************************
* DisegnaCerchioLuce
*   Disegna un cerchio di "luce" (= bit a 0) sul dark plane corrente.
*   INPUT:
*     D0.w = center X schermo (puo' essere negativo)
*     D1.w = center Y schermo (idem)
*   Raggio = RAGGIO_LUCE.
*
*   Strategia: per ogni riga dy, calcola span [x_left..x_right] e fa
*   AND-NOT con la maschera sul dark plane (= spegne i pixel = luce).
*****************************************************************************
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
	; Cull verticale (le ultime CUT_BOTTOM_ROWS righe restano "scure", fuori dal display utile)
	BMI.W	.skip_row
	CMP.W	#BG_VIS_ROWS,D3
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

	; Cull orizzontale
	TST.W	D1
	BMI.W	.skip_row
	CMP.W	#320,D0
	BGE.W	.skip_row
	; Clip
	TST.W	D0
	BPL.S	.lc_ok
	MOVEQ	#0,D0
.lc_ok:
	CMP.W	#319,D1
	BLE.S	.rc_ok
	MOVE.W	#319,D1
.rc_ok:
	; D0 = x_left clippato, D1 = x_right clippato

	; A1 = base riga sul dark plane
	MOVE.L	CurrentDarkDraw,A1
	MOVE.W	D3,D4
	MULU.W	#BPSF_PITCH,D4
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

*****************************************************************************
* LightHalfWidthTable
*   Tabella di "mezza-larghezza" per cerchio raggio LIGHT_RADIUS=64.
*   Indicizzata da |dy| (0..64).
*   half[dy] = sqrt(64² - dy²)
*****************************************************************************
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
*****************************************************************************
* BuildLightMask  (chiamata UNA volta al boot)
*   Costruisce LightMask: disco di raggio RAGGIO_LUCE, bit=1 dentro, in un
*   buffer di LIGHT_MASK_W word x LIGHT_MASK_H righe. Riusa LightHalfWidthTable.
*   La 9a word di ogni riga resta 0 (spillover per lo shift del blit).
*****************************************************************************
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

*****************************************************************************
* SetBitSpan  - setta a 1 i bit da D3 a D4 (inclusi) nella riga A1.
*   Ordine bit MSB-first: pixel 0 = bit 7 del byte 0. Solo per il boot.
*****************************************************************************
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

*****************************************************************************
* DisegnaCerchioLuceBlitter
*   Disegna il cerchio di luce sul dark plane (= spegne i bit dentro) usando
*   il BLITTER: minterm D = (NOT A) AND C, con A=LightMask, C/D=dark plane.
*   INPUT: D0.w = cx, D1.w = cy  (centro schermo, come DisegnaCerchioLuce).
*
*   - Shift orizzontale sub-word via ASH in BLTCON0.
*   - Clipping verticale: aggiusta riga di partenza maschera + altezza blit.
*   - Clipping orizzontale (bordo sx/dx): FALLBACK alla routine CPU esistente
*     quando word_x e' fuori [0..11] (cerchio a cavallo del bordo laterale).
*****************************************************************************
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
	; A1 = CurrentDarkDraw + vtop*48 + word_x*2
	MOVE.L	CurrentDarkDraw,A1
	MOVE.W	D5,D6
	MULU.W	#AUX_PITCH,D6
	ADDA.W	D6,A1
	MOVE.W	D3,D6
	ADD.W	D6,D6					; word_x*2
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
*****************************************************************************
* AI_Patrol
*   Ronda generica a 8 direzioni: usa DirectionDeltas per calcolare il
*   movimento (dx, dy) in base a bob_Direzione. Quando bloccato, ruota
*   la direzione di 180° (dir XOR 4), che funziona per tutte le 8
*   direzioni: E<->W, SE<->NW, S<->N, SW<->NE.
*   INPUT: A0 = struct nemico
*****************************************************************************
AI_Patrol:
	MOVEM.L	D0-D4/A0-A2,-(SP)
	MOVE.L	A0,A2					; A2 = nemico stesso (per esclusione overlap)

	; Indice nella tabella: bob_Direzione * 4 (4 byte per riga: 2 word)
	MOVE.W	bob_Direzione(A0),D2
	AND.W	#7,D2					; sicurezza:  0..7
	LSL.W	#2,D2					; *4
	LEA		DirectionDeltas,A1
	; Carico dx, dy (segnati) e moltiplico per Speed
	MOVE.W	(A1,D2.W),D3			; D3 = dx (-1, 0, +1)
	MOVE.W	2(A1,D2.W),D4			; D4 = dy (-1, 0, +1)
	MOVE.W	bob_Speed(A0),D1
	MULS.W	D1,D3					; D3 = dx * Speed
	MULS.W	D1,D4					; D4 = dy * Speed

	; Calcolo nuova posizione candidata
	MOVE.W	bob_WorldX(A0),D0
	ADD.W	D3,D0					; D0 = X candidata
	MOVE.W	bob_WorldY(A0),D1
	ADD.W	D4,D1					; D1 = Y candidata

	BSR.W	IsEnemyBlocked
	BNE.S	.flip
	; Movimento accettato
	MOVE.W	D0,bob_WorldX(A0)
	MOVE.W	D1,bob_WorldY(A0)
	MOVE.W	#1,bob_IsMoving(A0)
	BRA.S	.done

.flip:
	; Inverte direzione di 180° (XOR 4 per tutte le 8 direzioni)
	MOVE.W	bob_Direzione(A0),D0
	EORI.W	#4,D0
	AND.W	#7,D0					; sicurezza
	MOVE.W	D0,bob_Direzione(A0)
	MOVE.W	#0,bob_IsMoving(A0)		; questo frame fermo
.done:
	MOVEM.L	(SP)+,D0-D4/A0-A2
	RTS

*****************************************************************************
* AI_Hunt
*   Inseguimento del Player con asse alternato:
*   1) Calcola dx, dy con il Player
*   2) Sceglie l'asse "preferito" (quello con differenza maggiore)
*   3) Tenta movimento sull'asse preferito
*   4) Se bloccato, prova sull'altro asse
*   5) Se entrambi bloccati, fermo
*****************************************************************************
AI_Hunt:
	MOVEM.L	D0-D5/A0/A2,-(SP)
	MOVE.L	A0,A2

	; D3 = dx (player - nemico), D4 = dy
	MOVE.W	Player+bob_WorldX,D3
	SUB.W	bob_WorldX(A0),D3
	MOVE.W	Player+bob_WorldY,D4
	SUB.W	bob_WorldY(A0),D4

	; |dx| in D5, |dy| in D6 ... usiamo solo D5 e ricalcolo |dy| dopo
	MOVE.W	D3,D5
	BPL.S	.absdx_ok
	NEG.W	D5
.absdx_ok:
	MOVE.W	D4,D2					; D2 = |dy|
	BPL.S	.absdy_ok
	NEG.W	D2
.absdy_ok:

	; Se siamo gia' addosso al player (entro 16 px su entrambi assi), non muovere
	; (gia' impedito da IsEnemyBlocked, ma evitiamo movimento inutile)
	; Asse preferito: quello con valore assoluto maggiore
	CMP.W	D5,D2
	BHI.S	.tryY_first				; |dy| > |dx| -> Y prima
	; Altrimenti X prima
	BSR.S	.tryX
	TST.B	D2						; success?
	BEQ.S	.done
	BSR.S	.tryY
	BRA.S	.done

.tryY_first:
	BSR.S	.tryY
	TST.B	D2
	BEQ.S	.done
	BSR.S	.tryX

.done:
	MOVEM.L	(SP)+,D0-D5/A0/A2
	RTS

; ---- subroutine locali per AI_Hunt ----
; .tryX: tenta movimento sull'asse X verso il player
; INPUT: D3 = dx (segno = direzione), A0 = nemico, A2 = nemico stesso
; OUTPUT: D2 = 0 se mosso, !=0 se bloccato
.tryX:
	TST.W	D3
	BEQ.S	.tryX_blocked			; dx = 0, niente da fare
	MOVE.W	bob_WorldX(A0),D0
	MOVE.W	bob_Speed(A0),D1
	TST.W	D3
	BMI.S	.tryX_left
	; dx > 0 -> verso destra (E)
	ADD.W	D1,D0
	MOVE.W	#0,bob_Direzione(A0)
	BRA.S	.tryX_check
.tryX_left:
	; dx < 0 -> verso sinistra (W)
	SUB.W	D1,D0
	MOVE.W	#4,bob_Direzione(A0)
.tryX_check:
	MOVE.W	bob_WorldY(A0),D1
	BSR.W	IsEnemyBlocked
	BNE.S	.tryX_blocked
	MOVE.W	D0,bob_WorldX(A0)
	MOVE.W	#1,bob_IsMoving(A0)
	MOVEQ	#0,D2					; mosso
	RTS
.tryX_blocked:
	MOVEQ	#1,D2					; bloccato
	RTS

; .tryY: tenta movimento sull'asse Y verso il player
.tryY:
	TST.W	D4
	BEQ.S	.tryY_blocked
	MOVE.W	bob_WorldY(A0),D1
	MOVE.W	bob_Speed(A0),D0
	TST.W	D4
	BMI.S	.tryY_up
	; dy > 0 -> verso giù (S)
	ADD.W	D0,D1
	MOVE.W	#2,bob_Direzione(A0)
	BRA.S	.tryY_check
.tryY_up:
	; dy < 0 -> verso su (N)
	SUB.W	D0,D1
	MOVE.W	#6,bob_Direzione(A0)
.tryY_check:
	MOVE.W	bob_WorldX(A0),D0
	BSR.W	IsEnemyBlocked
	BNE.S	.tryY_blocked
	MOVE.W	D1,bob_WorldY(A0)
	MOVE.W	#1,bob_IsMoving(A0)
	MOVEQ	#0,D2
	RTS
.tryY_blocked:
	MOVEQ	#1,D2
	RTS

*****************************************************************************
* AggiornaFisicaPlayer
*   Genera IntentY dalla fisica del platform, al posto dell'input verticale.
*   - Gravita': bob_VelY += GRAVITA_88 ogni frame, con cap a MAX_FALL_88.
*   - Salto: solo sul FRONTE di salita di UpNow (tasto appena premuto) E se il
*     player e' a terra -> bob_VelY = JUMP_VEL_88 (negativa = su), grounded = 0.
*     Cosi' si salta una volta per pressione e solo da terra.
*   - IntentY = i pixel INTERI che escono dall'accumulatore 8.8 (puo' essere 0).
*   bob_Grounded viene aggiornato da AggPosizioneGlobalePlayer in base alle
*   collisioni verticali (giu' bloccato = a terra; su bloccato = testata).
*****************************************************************************
AggiornaFisicaPlayer:
	MOVEM.L	D0-D1,-(SP)
	TST.W	GravityOn
	BEQ.S	.skipGrav			; gravita' OFF (8 direzioni): IntentY viene gia' dall'input (lockstep)
	; --- Gravita' (applicata solo in platform) ---
	MOVE.W	Player+bob_VelY,D0
	ADD.W	#GRAVITA_88,D0
	CMP.W	#MAX_FALL_88,D0
	BLE.S	.noCap
	MOVE.W	#MAX_FALL_88,D0			; set alla velocita' terminale
.noCap:
	MOVE.W	D0,Player+bob_VelY
	; --- Salto: fronte di salita di UpNow + player a terra ---
	TST.W	UpNow
	BEQ.S	.noJump					; tasto su non premuto
	TST.W	UpPrev
	BNE.S	.noJump					; era gia' premuto -> non e' un fronte
	TST.W	Player+bob_Grounded
	BEQ.S	.noJump					; in aria -> niente salto
	MOVE.W	#JUMP_VEL_88,Player+bob_VelY	; SALTO! (sovrascrive la gravita' di questo frame)
	CLR.W	Player+bob_FracY				; lo slancio riparte da un pixel netto
	CLR.W	Player+bob_Grounded
.noJump:
	MOVE.W	UpNow,UpPrev			; memorizza stato per il prossimo fronte
	; IntentY = i PIXEL INTERI che escono dall'accumulatore in questo frame.
	; Con la gravita' frazionaria ci sono frame in cui non ne esce nessuno e
	; IntentY vale 0: AggPosizioneGlobalePlayer lo intercetta con il suo
	; "BEQ .skipY" e salta tutto il blocco Y, quindi il player non viene
	; scambiato per atterrato restando a mezz'aria.
	MOVE.W	Player+bob_FracY,D0
	ADD.W	Player+bob_VelY,D0
	MOVE.W	D0,D1
	ASR.W	#8,D1					; pixel interi, con segno
	MOVE.W	D1,IntentY
	AND.W	#$00FF,D0				; resta la frazione per il frame dopo
	MOVE.W	D0,Player+bob_FracY
.skipGrav:
	MOVEM.L	(SP)+,D0-D1
	RTS
*****************************************************************************
* AggPosizioneGlobalePlayer (Fase 2 + Fase 4)
*   Aggiorna bob_WorldX/Y in base a ScrllX/Y (intent dell'utente).
*   setta il risultato in modo che il BOB (16x16, blittato come 2 word)
*   non esca mai dal bitplane visibile.
*
*   Limiti calcolati per evitare wrap-around del blit:
*     bob_X max = (viewport_width - BOB_width) = 320 - 16 = 304
*     bob_Y max = (viewport_height - BOB_height) = 256 - 16 = 240
*
*   bob_WorldX max = bob_X_max + CameraX_max = 304 + (TILEXMAX*16) = 304 + 32 = 336
*   bob_WorldY max = bob_Y_max + CameraY_max = 240 + (TILEYMAX*16) = 240 + 64 = 304
*****************************************************************************
*****************************************************************************
* AggPosizioneGlobalePlayer (Fase 2 + Fase 4 + Collisioni)
*   Aggiorna bob_WorldX/Y in base a IntentX/IntentY, applicando:
*   1) Collision detection contro le tile bloccate (sliding X poi Y)
*   2) Fissa ai bordi della mappa
*****************************************************************************
AggPosizioneGlobalePlayer:
	MOVEM.L	D0-D2/A2,-(SP)

	;-------------------------------------------------------------
	; ASSE X: tenta di muovere solo X (Y invariato)
	;-------------------------------------------------------------
	MOVE.W	IntentX,D0
	BEQ.S	.skipX					; se intent=0, salta
	ADD.W	Player+bob_WorldX,D0			; D0 = nuova X candidata
	; Fissa ai bordi mappa
	BPL.S	.x_setHi
	MOVEQ	#0,D0					; X<0 -> 0
	BRA.S	.x_check
.x_setHi:
	CMP.W	#PLAYER_MAX_X,D0
	BLE.S	.x_check
	MOVE.W	#PLAYER_MAX_X,D0		; X>max -> max
.x_check:
	; D0 = nuova X candidata, controllo collisioni
	MOVE.W	Player+bob_WorldY,D1			; Y attuale (non ancora cambiato)
	BSR.W	IsBoxBlocked
	BNE.S	.x_blocked				; collide con tile, rifiuta movimento X
	; Controllo collision con i nemici (player NON puo' entrare in un nemico)
	MOVE.L	#0,A2					; A2=0 -> non escludere nessun BOB
	BSR.W	IsOverlapEnemies
	BNE.S	.x_blocked				; overlap con nemico -> rifiuta	
	; Movimento X accettato. 
	CMP.W	Player+bob_WorldX,D0
	BEQ.S	.x_blocked				; non si e' mosso (set) -> azzera ScrllX
	MOVE.W	D0,Player+bob_WorldX
	BRA.S	.skipX
.x_blocked:
	CLR.W	ScrllX					; sincronizza camera: niente scroll su X

.skipX:

	;-------------------------------------------------------------
	; ASSE Y: tenta di muovere solo Y (X eventualmente gia' aggiornata)
	;-------------------------------------------------------------
	MOVE.W	IntentY,D1
	BEQ.S	.skipY
	ADD.W	Player+bob_WorldY,D1			; D1 = nuova Y candidata
	; Fissa ai bordi mappa
	BPL.S	.y_setHi
	MOVEQ	#0,D1
	BRA.S	.y_check
.y_setHi:
	CMP.W	#PLAYER_MAX_Y,D1
	BLE.S	.y_check
	MOVE.W	#PLAYER_MAX_Y,D1
.y_check:
	; D1 = nuova Y candidata, controllo collisioni
	MOVE.W	Player+bob_WorldX,D0			; X attuale (eventualmente gia' aggiornata)
	BSR.W	IsBoxBlocked
	BNE.S	.y_blocked				; collide con tile, rifiuta movimento Y
	; Controllo collision con i nemici
	MOVE.L	#0,A2					; A2=0 -> non escludere nessun BOB
	BSR.W	IsOverlapEnemies
	BNE.S	.y_blocked				; overlap con nemico -> rifiuta	
	CMP.W	Player+bob_WorldY,D1
	BEQ.S	.y_blocked				; non si e' mosso (set) -> azzera ScrllY
	MOVE.W	D1,Player+bob_WorldY
	CLR.W	Player+bob_Grounded			; movimento verticale riuscito -> player in aria
	BRA.S	.skipY
.y_blocked:
	CLR.W	ScrllY					; sincronizza camera: niente scroll su Y
	; --- stato verticale: giu' bloccato = a terra, su bloccato = testata ---
	MOVE.W	IntentY,D0
	BPL.S	.y_land					; IntentY>=0 (scendeva) -> atterrato sul tile
	CLR.W	Player+bob_VelY				; IntentY<0 (saliva) -> testata sul soffitto
	CLR.W	Player+bob_FracY				; con la velocita' si azzera anche la frazione
	BRA.S	.skipY
.y_land:
	MOVE.W	#1,Player+bob_Grounded		; piedi su tile solido -> puo' saltare
	CLR.W	Player+bob_VelY
	CLR.W	Player+bob_FracY
.skipY:

	MOVEM.L	(SP)+,D0-D2/A2
	RTS

*****************************************************************************
* CalcolaInseguimentoCameraY
*   Solo in modalita' platform (GravityOn=1): scroll verticale per inseguire
*   il player. In 8-direzioni (GravityOn=0) NON tocca nulla: ScrllY e' gia'
*   impostato dall'input (lockstep a 1px).
*
*   Passo adattivo (auto-riallineamento):
*   - se PixelOffY e' multiplo di CAM_STEP_Y -> passo pieno CAM_STEP_Y
*   - altrimenti -> passo 1px (nella direzione dell'inseguimento) finche'
*     PixelOffY torna allineato. Serve perche' il refill richiede passi
*     multipli che mantengano PixelOffY allineato; entrando da 8-direzioni
*     (passo 1) PixelOffY puo' essere qualsiasi, e cosi' si riallinea liscio.
*
*   errore = (bob_WorldY - CENTER_Y) - (TileY*16 + PixelOffY)
*   |errore| <= CAM_DEADZONE_Y -> fermo.
*****************************************************************************
CalcolaInseguimentoCameraY:
	MOVEM.L	D0-D2,-(SP)
	TST.W	GravityOn
	BEQ.W	.skip					; 8-direzioni: gestito dall'input (lockstep)
	MOVE.W	TileY,D0
	LSL.W	#4,D0					; TileY*16
	ADD.W	PixelOffY,D0			; D0 = CameraY corrente (px)
	MOVE.W	Player+bob_WorldY,D1
	SUB.W	#CENTER_Y,D1			; D1 = CameraY target
	SUB.W	D0,D1					; D1 = errore (target - corrente)
	CMP.W	#CAM_DEADZONE_Y,D1
	BGT.S	.needDown				; errore > +deadzone -> giu'
	CMP.W	#-CAM_DEADZONE_Y,D1
	BLT.S	.needUp					; errore < -deadzone -> su
	CLR.W	ScrllY					; dentro la dead-zone -> fermo
	BRA.S	.skip
.needDown:
	MOVE.W	PixelOffY,D2
	AND.W	#CAM_STEP_Y-1,D2		; PixelOffY mod CAM_STEP_Y (CAM_STEP_Y e' potenza di 2)
	BNE.S	.down1					; non allineato -> 1px per riallineare
	MOVE.W	#CAM_STEP_Y,ScrllY
	BRA.S	.skip
.down1:
	MOVE.W	#1,ScrllY
	BRA.S	.skip
.needUp:
	MOVE.W	PixelOffY,D2
	AND.W	#CAM_STEP_Y-1,D2
	BNE.S	.up1
	MOVE.W	#-CAM_STEP_Y,ScrllY
	BRA.S	.skip
.up1:
	MOVE.W	#-1,ScrllY
.skip:
	MOVEM.L	(SP)+,D0-D2
	RTS
*****************************************************************************
* AggiornaPlayerScreenPos
*   Calcola bob_X/bob_Y (coordinate schermo del player) come differenza
*   tra bob_WorldX/Y (coordinate mondo) e la posizione della camera.
*
*   CameraX_pixel = TileX * 16 + PixelOffX
*   CameraY_pixel = TileY * 16 + PixelOffY
*
*   bob_X = bob_WorldX - CameraX_pixel
*   bob_Y = bob_WorldY - CameraY_pixel
*
*   In Fase 1 bob_WorldX/Y NON cambiano, quindi bob_X/Y resteranno
*   costanti a (144, 120) come prima -> nessun cambiamento visivo.
*****************************************************************************
AggiornaPlayerScreenPos:
	MOVEM.L	D0-D1/A0,-(SP)
 
	LEA		Player,A0
 
	; Calcola CameraX_pixel = TileX*16 + PixelOffX
	MOVE.W	TileX,D0
	LSL.W	#4,D0					; D0 = TileX * 16
	ADD.W	PixelOffX,D0			; D0 = CameraX_pixel
	; bob_X = bob_WorldX - CameraX
	MOVE.W	Player+bob_WorldX,D1
	SUB.W	D0,D1
	MOVE.W	D1,bob_X(A0)
 
	; Calcola CameraY_pixel = TileY*16 + PixelOffY
	MOVE.W	TileY,D0
	LSL.W	#4,D0					; D0 = TileY * 16
	ADD.W	PixelOffY,D0			; D0 = CameraY_pixel
	; bob_Y = bob_WorldY - CameraY
	MOVE.W	Player+bob_WorldY,D1
	SUB.W	D0,D1
	MOVE.W	D1,bob_Y(A0)
 
	MOVEM.L	(SP)+,D0-D1/A0
	RTS
 
*****************************************************************************
*			  ROUTINE DI COPIA DELLA PARTE VISIBILE SUI BITPLANE
*****************************************************************************
*****************************************************************************
* DisegnaBOB - UNICA routine di rendering di un bob
*   Input: A0 = puntatore alla struct bob_*, con bob_X/bob_Y gia' calcolate
*          dal chiamante come coordinate SCHERMO.
*
*   Fa tutto: cull, clip verticale, animazione, blit sui 5 piani e
*   registrazione del rettangolo sporco. Vale per qualunque bob e qualunque
*   formato di sheet: la geometria viene dalla struct (bob_Larghezza,
*   bob_Altezza, bob_Frames, bob_Bande) e non da EQU cablate.
*
*   Il cull e il clip erano in una DisegnaBOBConClip separata, che aveva un
*   solo chiamante e passava i suoi risultati per variabile: fusi qui dentro
*   sono un blocco in testa alla routine, e bob_Y non viene piu' sovrascritta
*   e ripristinata attorno al blit.
*****************************************************************************
DisegnaBOB:
	MOVEM.L	D0-D7/A0-A3,-(SP)
	; A0 e' gia' settato dal chiamante (NON sovrascritto qui)

	; ================= CULL: il bob e' del tutto fuori? =================
	; Sta PRIMA di tutto, animazione compresa: un bob fuori schermo non
	; avanza i fotogrammi, esattamente come quando il cull era una routine
	; separata e il disegno non veniva nemmeno chiamato.
	; In Path B il bob si disegna alla sua posizione MONDO dentro il world
	; buffer ed e' la finestra di display a ritagliarlo: non serve clip
	; orizzontale, basta non disegnare chi e' del tutto fuori. L'unico
	; vincolo duro e' che la X MONDO resti dentro il buffer, altrimenti il
	; blit scrive prima dell'inizio della riga o oltre la sua fine.
	MOVE.W	bob_X(A0),D1
	TST.W	bob_WorldX(A0)
	BMI.W	.fuori					; X mondo negativa -> fuori dal buffer
	MOVE.W	#MAPPA_COLS*16,D4
	SUB.W	bob_Larghezza(A0),D4	; ultima X mondo ammessa
	CMP.W	bob_WorldX(A0),D4
	BLT.W	.fuori					; oltre il bordo destro della mappa
	MOVE.W	bob_Larghezza(A0),D4
	NEG.W	D4
	CMP.W	D4,D1
	BLE.W	.fuori					; tutto a sinistra della finestra
	CMP.W	#VIS_COLS*16,D1
	BGE.W	.fuori					; tutto a destra della finestra

	MOVE.W	bob_Y(A0),D1
	MOVE.W	bob_Altezza(A0),D4
	NEG.W	D4
	CMP.W	D4,D1
	BLE.W	.fuori					; tutto sopra la finestra
	CMP.W	#BG_VIS_ROWS,D1
	BGE.W	.fuori					; tutto sotto la finestra

	; ================= CLIP verticale =================
	; Di default si blitta il fotogramma intero.
	MOVE.W	#0,BobClipSkipRows
	MOVE.W	bob_Altezza(A0),BobClipNumRows
	TST.W	D1
	BPL.S	.clip_basso
	; bob_Y < 0: salta -bob_Y righe di sheet e disegna dalla cima
	MOVE.W	D1,D4
	NEG.W	D4
	MOVE.W	D4,BobClipSkipRows
	MOVE.W	bob_Altezza(A0),D4
	ADD.W	D1,D4					; altezza + bob_Y = righe da blittare
	MOVE.W	D4,BobClipNumRows
	MOVEQ	#0,D1					; il disegno parte da y=0
	BRA.S	.clip_fatto
.clip_basso:
	MOVE.W	#BG_VIS_ROWS,D4
	SUB.W	bob_Altezza(A0),D4		; ultima Y senza clip
	CMP.W	D4,D1
	BLE.S	.clip_fatto
	MOVE.W	#BG_VIS_ROWS,D4
	SUB.W	D1,D4					; righe ancora visibili
	MOVE.W	D4,BobClipNumRows
.clip_fatto:
	; Y SCHERMO da cui parte il disegno. Prima si sovrascriveva bob_Y e lo si
	; ripristinava dopo il blit, perche' col clip in alto il disegno deve
	; partire da 0: con una variabile a parte la struct non viene piu' toccata.
	MOVE.W	D1,BobDrawY

	; ----------------- Geometria dello sheet, DERIVATA -----------------
	; La struct porta solo bob_Frames e bob_Bande: pitch, slot, word del
	; blit, banda direzione e piano si ricavano da quelli piu' larghezza e
	; altezza del fotogramma, che c'erano gia'. Cosi' la stessa routine
	; disegna sheet di formato diverso senza duplicare nulla e senza tenere
	; in struct valori che sarebbero copie della stessa informazione.
	MOVE.W	bob_Larghezza(A0),D0
	LSR.W	#4,D0
	ADDQ.W	#1,D0					; +1 word: lo shift orizzontale sconfina
	MOVE.W	D0,BobGeoBlitW
	ADD.W	D0,D0					; slot = word del blit * 2 byte
	MOVE.W	D0,BobGeoSlot
	MULU.W	bob_Frames(A0),D0		; riga di sheet = fotogrammi * slot
	MOVE.W	D0,BobGeoPitch
	MULU.W	bob_Altezza(A0),D0		; banda direzione = altezza * riga
	MOVE.L	D0,D1					; D1 = banda, serve fra poche righe
	MULU.W	bob_Bande(A0),D0		; piano = banda * numero di bande
	MOVE.L	D0,BobGeoPlane

	; ----------------- Animazione -----------------
	TST.W	bob_IsMoving(A0)
	BEQ.S	.notmoving
	ADD.W	#1,bob_FrameCont(A0)
	MOVE.W	bob_FrameCont(A0),D0
	CMP.W	bob_AnimDelay(A0),D0	; passo DI QUESTO bob, non piu' uguale per tutti
	BLT.S	.fineAnimazione
	CLR.W	bob_FrameCont(A0)
	; il wrap non e' piu' fisso a 8: la maschera e' bob_Frames-1
	MOVE.W	bob_AnimFrame(A0),D0
	ADDQ.W	#1,D0
	MOVE.W	bob_Frames(A0),D2
	SUBQ.W	#1,D2
	AND.W	D2,D0
	MOVE.W	D0,bob_AnimFrame(A0)
	BRA.S	.fineAnimazione
.notmoving:
	CLR.W	bob_FrameCont(A0)
	CLR.W	bob_AnimFrame(A0)
.fineAnimazione:
	; ----------------- Calcolo offset frame nello spritesheet -----------------
	; Lo slot e' piu' largo dell'arte: la word di stacco fra un frame e
	; l'altro e' quella su cui si spalma lo shift orizzontale.
	; La direzione va MASCHERATA sul numero di bande, non usata cruda: la banda
	; vale altezza*pitch anche quando lo sheet ne ha una sola, e li' coincide
	; con l'INTERO piano. Su uno sheet a banda unica (la pietra: banda 512 =
	; piano 512) una direzione diversa da zero manderebbe il blit a leggere
	; fuori dal piano, dentro la maschera e oltre. Con bob_Bande potenza di 2
	; la maschera vale 0 quando la banda e' unica, quindi la direzione si puo'
	; usare per altri scopi senza rischi.
	MOVE.W	bob_Direzione(A0),D3
	MOVE.W	bob_Bande(A0),D2
	SUBQ.W	#1,D2					; maschera = bande-1 (0 se banda unica)
	AND.W	D2,D3
	MULU.W	D1,D3					; Direzione * banda (D1 dal blocco geometria)
	MOVE.W	bob_AnimFrame(A0),D5
	MULU.W	BobGeoSlot,D5			; AnimFrame * slot (arte + stacco)
	ADD.W	D5,D3					; D3 = offset frame nel plane 0
 
	; ----------------- A2 = sorgente A (spritesheet plane 0) -----------------
	MOVE.L 	bob_Gfx(A0),A2
	ADDA.W	D3,A2
	; Applica clip top: sposta A2 in avanti di SkipRows * 40 byte
	MOVE.W	BobClipSkipRows,D2
	MULU.W	BobGeoPitch,D2			; D2 = skip * pitch sheet (long)
	ADDA.L	D2,A2					; A2 punta alla riga di partenza del frame
 	; ----------------- A3 = maschera PER-FRAME (canale A) -----------------
	; La silhouette del frame, non piu' un quadrato pieno: a 32x32 il quadrato
	; cancellerebbe lo sfondo su tutto il riquadro. Stesso layout dello sheet,
	; quindi stesso offset frame (D3) e stesso pitch. La maschera e' UNA sola
	; per tutti i 5 piani, quindi A3 non avanza nel loop dei piani.
	MOVE.L	bob_Mask(A0),A3
	ADDA.W	D3,A3					; stesso offset frame dell'arte
	MOVE.W	BobClipSkipRows,D2
	MULU.W	BobGeoPitch,D2			; D2 = skip * pitch sheet
	ADDA.L	D2,A3

	; ----------------- Calcolo destinazione e shift -----------------
	; bob_X = posizione X in pixel
	; D7 = shift = bob_X mod 16
	; D6 = byte offset (allineato a word) = (bob_X / 16) * 2
	MOVE.W	bob_X(A0),D6
	; Path B: i BOB si disegnano sul WORLD buffer, quindi la posizione va
	; convertita da coordinate SCHERMO a coordinate MONDO sommando la
	; camera. Senza questo finirebbero sempre nell'angolo alto-sinistro
	; della mappa invece che davanti al giocatore.
	ADD.W	PathBCamX,D6
	MOVE.W	D6,D7
	AND.W	#15,D7					; D7 = shift (0..15)
	LSR.W	#3,D6					; D6 = bob_X / 8 (in byte)
	AND.W	#$FFFE,D6				; D6 allineato a word
 
	; Path B: destinazione = world buffer (che E' quello visualizzato),
	; saltando la guardia del prefetch. Y in coordinate mondo.
	MOVEA.L	WorldDraw,A1			; si disegna nel buffer NON a video
	ADDA.L	#DELTA_MAPPAVERA+BG_ORIGIN_OFS,A1
	MOVE.W	BobDrawY,D0				; Y gia' clippata, non bob_Y grezza
	ADD.W	PathBCamY,D0
	MULU.W	#SFONDO_PITCH,D0
	ADD.W	D6,D0
	ADDA.L	D0,A1
 
	; ----------------- BLTCON0 = (shift << 12) | $0FCA -----------------
	; bit 15-12: ASH (shift sorgente A)
	; bit 11-8:  USEA|USEB|USEC|USED = $F
	; bit  7-0:  LF = $CA (cookie cut: D = (A AND B) OR (C AND NOT B))
	MOVE.W	D7,D5
	LSL.W	#8,D5
	LSL.W	#4,D5					; D5 = shift << 12
	OR.W	#$0FCA,D5				; D5.w = BLTCON0 (cookie cut)
 
	; ----------------- BLTCON1 = BSH << 12 -----------------
	MOVE.W	D7,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; D6.w = BSH << 12 = BLTCON1
 
	; ----------------- BLTSIZE: NumRows righe x 2 word -----------------
	; NumRows = numero righe da blittare (default 16, o ridotto se clip Y)
	; 2 word per riga per gestire lo shift orizzontale.
	MOVE.W	BobClipNumRows,D4
	LSL.W	#6,D4					; D4 = NumRows << 6
	ADD.W	BobGeoBlitW,D4			; word per riga DI QUESTO sheet

	; ----------------- Registri "fissi" del blit settati una sola volta -----------------
	; Questi registri sono uguali per tutti i 5 plane, quindi li settiamo PRIMA
	; del loop dei plane invece che ad ogni iterazione.
	BSR.W	AspettaBlitter			; assicura che il blit precedente sia finito

	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM = $FFFF/$FFFF
	MOVE.W	D5,$40(A6)				; BLTCON0 (con ASH = shift sulla MASCHERA = A)
	MOVE.W	D6,$42(A6)				; BLTCON1 (BSH = shift sul BOB = B)
	; I moduli dipendono dallo slot e dal pitch DI QUESTO sheet: con le EQU
	; cablate la routine funzionava solo per sheet fatti come Omino/Nemico.
	; D5/D6 sono gia' stati versati nell'hardware qui sopra, D2/D3 sono liberi.
	MOVE.W	BobGeoSlot,D3
	MOVE.W	#DEST_PITCH,D2
	SUB.W	D3,D2
	MOVE.W	D2,$60(A6)				; BLTCMOD (sfondo = dest)
	MOVE.W	D2,$66(A6)				; BLTDMOD (destinazione)
	MOVE.W	BobGeoPitch,D2
	SUB.W	D3,D2
	MOVE.W	D2,$62(A6)				; BLTBMOD (BOB nello sheet)
	MOVE.W	D2,$64(A6)				; BLTAMOD (maschera per-frame)
 
	; ----------------- Loop sui 5 bitplane -----------------
	; L'incremento per passare al plane successivo e' SEMPRE plane_size = 10240 byte.
	; Il valore di A1/A2 nei registri CPU NON viene modificato dal blitter
	; (il blitter modifica BLTAPT/BLTBPT/BLTCPT/BLTDPT, registri propri).
	; annota il rettangolo: il frame prossimo PathBRestoreAll lo ripulira'.
	; Va fatto ORA, con A1 ancora sul piano 1 e prima che il loop lo faccia
	; avanzare.
	MOVE.W	BobClipNumRows,D4
	MOVE.W	BobGeoBlitW,D5			; D5 = larghezza del rettangolo (word)
	BSR.W	PathBRegistraDirty
	MOVE.W	BobClipNumRows,D4
	LSL.W	#6,D4
	ADD.W	BobGeoBlitW,D4			; ricostruisce BLTSIZE, che D4 conteneva
	MOVEQ	#5-1,D0
.BlittaLoopBob:
	BSR.W	AspettaBlitter			; aspetta che il blit del plane precedente finisca
	MOVE.L	A1,$48(A6)				; BLTCPT (sfondo)
	MOVE.L	A2,$4C(A6)				; BLTBPT = BOB sorgente
	MOVE.L	A3,$50(A6)				; BLTAPT = MASCHERA
	MOVE.L	A1,$54(A6)				; BLTDPT (destinazione)

	MOVE.W	D4,$58(A6)				; BLTSIZE -> avvia blit
 

	ADDA.L	BobGeoPlane,A2			; prossimo plane sorgente BOB (B)
	ADD.L	#DEST_PLANE_SZ,A1		; prossimo plane di destinazione

	; A3 (MASCHERA = A) NON avanza: e' una sola per tutti i plane
 
	DBRA	D0,.BlittaLoopBob

.fuori:
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
*****************************************************************************
* DisegnaBOBs - UNICA routine di disegno di tutti i bob
*
*   Sostituisce DisegnaBOBPlayer, DisegnaBOBEnemy e DisegnaBOBPietra, che
*   facevano la stessa identica cosa e differivano solo per come
*   raggiungevano la struct: prendere un bob, calcolare
*   bob_X/bob_Y = World - Camera, passarlo a cull, clip e blit.
*
*   I bob sono contigui sotto BobArray (vedi SECTION Entities): un solo ciclo
*   li percorre, e l'ordine in memoria E' lo z-order.
*
*   Il player ci passa come tutti gli altri, cull compreso. Non cambia nulla:
*   PLAYER_MAX_X = MAPPA_COLS*16-BOB_COLL_W = 368 coincide con la soglia di
*   cull (MAPPA_COLS*16 - bob_Larghezza), che scarta solo se MAGGIORE; e in Y
*   la camera lo tiene fra 0 e BG_VIS_ROWS-BOB_H = 144, cioe' esattamente il
*   limite oltre il quale scatterebbe il clip. Nessuna posizione raggiungibile
*   dal player viene cullata o clippata.
*****************************************************************************
DisegnaBOBs:
	MOVEM.L	D0-D4/A0,-(SP)

	; camera in pixel, calcolata UNA volta per tutti i bob
	MOVE.W	TileX,D2
	LSL.W	#4,D2					; D2 = TileX*16
	ADD.W	PixelOffX,D2			; D2 = CameraX in pixel
	MOVE.W	TileY,D3
	LSL.W	#4,D3					; D3 = TileY*16
	ADD.W	PixelOffY,D3			; D3 = CameraY in pixel

	LEA		BobArray,A0
	MOVEQ	#BOB_TOTALI-1,D0
.loop:
	TST.W	bob_Active(A0)
	BEQ.S	.next					; slot spento: nemico morto, proiettile a riposo

	; bob_X/bob_Y (schermo) SEMPRE aggiornati, anche se poi il bob viene
	; cullato: altre routine li leggono (es. la camera legge Player+bob_X).
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	D2,D1
	MOVE.W	D1,bob_X(A0)
	MOVE.W	bob_WorldY(A0),D4
	SUB.W	D3,D4
	MOVE.W	D4,bob_Y(A0)

	BSR.W	DisegnaBOB				; cull, clip, blit e rettangolo sporco
.next:
	LEA		bob_Length(A0),A0		; prossimo bob
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D4/A0
	RTS

*****************************************************************************
* Routine che aspetta il blitter
*****************************************************************************
AspettaBlitter:
	BTST	#6,2(a6)		; dmaconr - waitblit
.bltw:
	BTST	#6,2(a6)		; dmaconr - waitblit
	BNE.S	.bltw
	RTS
;=====================================================================
; Modulo di stampa testo (font 16x20). Generico e riutilizzabile:
; monitor, punteggio, messaggi. Vedi Testo.i per l'API.
;=====================================================================
	include	"Testo.i"

;=====================================================================
; Scroll hardware AGA (Path B). ScrollHW.i e' il modulo definitivo;
; ProtoScroll.i e' solo il banco di prova del passo 1 ed esce dalla
; build insieme a PROTO_SCROLL=0.
;=====================================================================
	include	"ScrollHW.i"

; DISPLAY_FETCH_BYTES e' dichiarato in testa perche' serve al pitch, che si
; calcola prima di questo include. Qui che SCROLL_FETCH_BYTES esiste, si
; verifica che i due non siano divergenti: se lo fossero, il puntatore del
; parallasse finirebbe nel posto sbagliato e tornerebbe la striscia a sinistra.
	IFNE	SCROLL_FETCH_BYTES-DISPLAY_FETCH_BYTES
;	FAIL	"DISPLAY_FETCH_BYTES non coincide con SCROLL_FETCH_BYTES"
	ENDC

; Tabella dei colori del gradiente cielo: UNA VOCE PER RIGA RASTER VISIBILE.
; La copperlist vera la genera BuildSkyCopper al boot. CieloCopper.i, che era
; la lista statica gia' srotolata, non serve piu' ed e' stato sostituito da
; questa tabella.
;
; E' un file GENERATO da tools/gen-cielo.py a partire dall'arte vera a 260
; voci, che sta in tools/CieloGrad-arte-260.src. Non modificarlo a mano: si
; rigenera. Il perche' della riduzione offline sta nell'intestazione di
; BuildSkyCopper, e la posizione dell'orizzonte si sposta da gen-cielo.py.
;
; Va incluso DOPO la definizione di SKY_STEPS, perche' in fondo c'e' la
; guardia che verifica che la tabella sia ancora 1:1 con le righe raster.
	include	"CieloGrad.i"

;=====================================================================
; ScrollPathB - lo scroll del gioco, versione hardware
;
; Sostituisce GestisciShiftPixel + CopiaVideo + AggiornaTiles con
; aritmetica sui puntatori. Il costo per frame passa da centinaia di
; righe raster a una manciata di istruzioni.
;
; La camera in pixel si ricava da quella a tile che il gioco gia'
; mantiene: CameraX = TileX*16 + PixelOffX, idem per Y. Non serve
; toccare ControllaBordi, RettangoloScrollNelCentro o CalcolaInseguimentoCameraY:
; continuano a lavorare come prima, e qui si legge solo il risultato.
;=====================================================================
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
	; SCHERMO e non devono scorrere: senza compensazione tremerebbero di
	; 0-63 px a ogni pixel di scroll fine.
	; D = ceil(CameraX/64)*64 - CameraX, la stessa di ScrollHWCalc.
	MOVE.W	D0,D2
	ADD.W	#63,D2
	LSR.W	#6,D2
	LSL.W	#6,D2
	SUB.W	D0,D2
	MOVE.W	D2,PathBDelay

	LEA		SFONDOGRANDE,A0			; qui serve solo come base per il calcolo
	BSR.W	ScrollHWCalc			; -> D2 offset, D3 BPLCON1

	; Col doppio buffer il calcolo resta QUI (la parallasse ha bisogno di
	; PathBDelay), ma l'APPLICAZIONE va in coda al blocco: si pubblica il
	; buffer solo quando e' finito. Quindi si mettono da parte i due valori.
	MOVE.L	D2,WorldPtrOfs			; D2 e' gia' un OFFSET puro, non un indirizzo
	MOVE.W	D3,WorldBplCon1

	MOVEM.L	(SP)+,D0-D5/A0-A2
	RTS

*****************************************************************************
* ScrollPathBApply - pubblica il buffer appena disegnato
*
* Da chiamare in CODA al blocco di lavoro, quando il disegno e' finito.
* Scrive i puntatori dei piani 1-5 su WorldDraw, il piano 6 sul darkplane con
* lo STESSO offset (deve scorrere insieme, non un frame avanti) e BPLCON1.
* Poi scambia WorldDraw/WorldShow e i due set di rettangoli sporchi.
*
* Il blocco di lavoro scavalca il confine del quadro, quindi questa scrittura
* cade dopo che il copper ha gia' riletto la copperlist: vale dal quadro
* successivo. E anche se il blocco finisse cosi' presto da arrivare in tempo
* per il quadro subito dopo, andrebbe bene lo stesso — il disegno e' concluso.
* E' sicura in entrambi i casi: e' la proprieta' che rende inutile la corsa
* col pennello.
*****************************************************************************
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

	; La parallasse si pubblica QUI, non presto: il suo contenuto e' compensato
	; per il ritardo BPLCON1 che stiamo scrivendo due righe sopra, quindi i due
	; devono entrare in vigore nello stesso quadro. Pubblicandoli in momenti
	; diversi si sfasano di un frame ed e' il vecchio flash all'innesco.
	; Con tutto pubblicato insieme, SW smette di essere un vincolo.
	IFNE	SWITCH_PIANI&2
	BSR.W	SwapParBuffers
	ENDC

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

;=====================================================================
; RESTORE DEI BOB (passo 3b)
;
; Senza CopiaVideo nessuno ripulisce piu' lo sfondo dietro ai BOB, che
; quindi lasciano scie. La soluzione: un BUFFER MASTER con la mappa
; pulita, copiato una volta all'init, da cui si ripristina il rettangolo
; di ogni BOB prima di ridisegnarlo.
;
; Costa UN blit di restore per piano contro i DUE del save/restore
; classico (salva-prima, ripristina-dopo), e non serve memoria per i
; salvataggi: il master c'e' gia'.
;
; Ogni BOB registra il proprio rettangolo mentre lo disegna; il frame
; dopo, PathBRestoreAll li ripulisce tutti e svuota la lista. I
; rettangoli sono sempre larghi 2 word, perche' e' quanto blittano sia
; i BOB (16 px + shift) sia le barre vita.
;=====================================================================
PATHB_DIRTY_MAX EQU     16              ; 5 BOB + 5 barre, con margine

;---------------------------------------------------------------------
; PathBRegistraDirty - annota un rettangolo da ripulire al prossimo frame
; IN: A1 = indirizzo nel world buffer (piano 1), D4.w = righe,
;     D5.w = larghezza in WORD (era la costante BOB_BLIT_W)
; Preserva tutto. Se la lista e' piena il rettangolo viene ignorato:
; meglio una scia occasionale che scrivere fuori dall'array.
;---------------------------------------------------------------------
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

;---------------------------------------------------------------------
; PathBRestoreAll - ripristina dal master tutti i rettangoli sporchi
; IN: A6 = $DFF000
;---------------------------------------------------------------------
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

;---------------------------------------------------------------------
; PathBBuildMaster - copia il world pulito nel master (una volta, init)
; Va chiamata DOPO DisegnaSfondo e PRIMA che qualcuno disegni BOB.
;---------------------------------------------------------------------
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
	MOVE.L	A0,$50(A6)
	MOVE.L	A1,$54(A6)
	; un piano = SFONDO_HEIGHT righe x (SFONDO_PITCH/2) word
	MOVE.W	#(SFONDO_HEIGHT<<6)|(SFONDO_PITCH/2),$58(A6)
	ADD.L	#SFONDO_PLANE_SIZE,A0
	ADD.L	#SFONDO_PLANE_SIZE,A1
	DBRA	D0,.plane
	BSR.W	AspettaBlitter
	MOVEM.L	(SP)+,D0/A0-A1
	RTS

;=====================================================================
; DARKPLANE STATICO
;
; Le luci sono tutte FISSE: la scansione cerca TILE_LUCE nella mappa e
; non esiste nessuna luce che segua il player. Quindi il darkplane
; dipende SOLO dalla camera, e ricalcolarlo ogni frame era lavoro
; buttato: 18 cerchi da 15 righe raster ciascuno, 302 righe per frame.
;
; Ora si disegna UNA VOLTA in coordinate MONDO, con lo stesso layout dei
; piani 1-5 (pitch SFONDO_PITCH, guardia a sinistra), e scorre con loro
; muovendo BPL6PT. Il costo per frame diventa ZERO.
;
; Va ricostruito solo quando NightMode cambia (tasto N).
;
; Spariscono di conseguenza: il fill per frame, il doppio buffer, e la
; compensazione di BPLCON1 -- il darkplane ora e' in coordinate mondo
; come i piani 1-5, quindi lo shift lo riguarda esattamente come loro.
;=====================================================================
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
	MOVE.W	#(SFONDO_HEIGHT<<6)|(SFONDO_PITCH/2),$58(A6)
	BSR.W	AspettaBlitter

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
	LEA		MAPPA,A0
	ADDA.W	D2,A0					; A0 = &MAPPA[D7][0]
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

;---------------------------------------------------------------------
; PathBInit - preparazione una tantum, dopo DisegnaSfondo
;
; Piani 6/7/8 su un buffer vuoto con lo STESSO pitch del world: i
; moduli BPL1MOD/BPL2MOD sono condivisi fra piani pari e dispari, e
; darkplane e parallasse hanno ancora pitch 48. Restano accesi perche'
; la contesa DMA a 8 piani deve essere quella vera, e le loro routine
; continuano a girare perche' il loro costo deve entrare nella misura.
;---------------------------------------------------------------------
PathBInit:
	MOVEM.L	D0-D1/A0-A1,-(SP)

	LEA		CL_Ddf,A1
	MOVE.W	#SCROLL_DDFSTRT,2(A1)
	MOVE.W	#SCROLL_DDFSTOP,6(A1)
	LEA		CL_BplMod,A1
	MOVE.W	#SCROLL_BPLMOD,2(A1)	; BPL1MOD
	MOVE.W	#SCROLL_BPLMOD,6(A1)	; BPL2MOD

	; Dirotta su PathBVuoto i piani ausiliari spenti da SWITCH_PIANI.
	MOVE.L	#PathBVuoto,D0
	IFEQ	SWITCH_PIANI&1
	LEA		BitPlaneTiles+5*8,A1	; 6o piano = darkplane
	BSR.S	.ptr
	ENDC
	IFEQ	SWITCH_PIANI&2
	LEA		BitplaneParall,A1		; 7o
	BSR.S	.ptr
	LEA		BitplaneParall+8,A1		; 8o
	BSR.S	.ptr
	ENDC

	MOVEM.L	(SP)+,D0-D1/A0-A1
	RTS

.ptr:	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	SWAP	D0
	RTS

	IFNE	PROTO_SCROLL
	include	"ProtoScroll.i"
	ENDC

	IFNE	PROFILING
;---------------------------------------------------------------------
; MostraProfilo - stampa i numeri del profilo NELL'AREA DI GIOCO
;
; Serve per leggere ProfWorst senza debugger: l'indirizzo delle variabili
; non e' prevedibile (il loader Amiga riloca le sezioni a ogni avvio),
; quindi il modo piu' semplice e' che sia il gioco stesso a scriverli.
;
; Premi P per mostrarli/nasconderli. Mentre sono mostrati la misura e'
; CONGELATA, cosi' i valori restano quelli accumulati giocando.
;
; Ogni voce e' "XXnnn": 2 lettere di etichetta + 3 cifre = 5 caratteri
; da 8 px = 40 px. Quattro voci per riga occupano 160 px dei 320: col
; vecchio font 16x20 erano 80 px a voce e riempivano la riga esatta.
; Volendo sfruttare tutta la larghezza, PROF_COLS puo' salire a 8.
;   VB VBLEND     IN INPUT      SC SCROLL    TI TILES
;   DK DARK       FA FALO       PA PARALLAX  CV COPIAVIDEO
;   EN ENTITIES   BO BOB        BL BLTDRAIN  WO WORST (totale)
;   DR DROP (frame persi)
;
; POSIZIONE: dentro l'area di gioco. NON sotto: DIWSTOP e' gia' tagliato
; da CUT_BOTTOM_ROWS, quindi il display si ferma a BG_VIS_ROWS e tutto
; cio' che sta sotto e' nel buffer ma invisibile.
; CopiaVideo ridisegna lo sfondo ogni frame, ma MostraProfilo gira DOPO
; (ultima a scrivere prima dello swap), quindi i numeri restano sopra.
;
; Scrive la stessa forma su TUTTI E 5 i piani: colore 31 su fondo 0,
; leggibile su qualunque sfondo e senza dover pulire prima.
;---------------------------------------------------------------------
PROF_VALUES     EQU     PROF_SLOTS+6    ; 11 fasi + WorstLines + DropCount + DDFSTRT + swap + ritardo + offset
PROF_COLS       EQU     4               ; voci per riga (4 x 80px = 320)
PROF_ROWS_N     EQU     (PROF_VALUES+PROF_COLS-1)/PROF_COLS
; Il testo va posizionato in coordinate DISPLAY. In Path B tutto cio' che
; viene disegnato passa per BG_ORIGIN_OFS, che lo sposta di BG_ORIGIN_Y
; righe piu' in basso rispetto a dove comincia il display (che parte da
; SFONDOGRANDE puro, senza origine). Senza compensare, l'ultima riga di
; testo finisce sotto il bordo visibile: col font 16x20 se ne vedeva
; ancora la cima, a 8x8 spariva del tutto (era il "DR" che mancava).
; NB: BG_ORIGIN_Y vale 0 da quando il mondo parte dall'angolo del buffer,
; quindi oggi questa compensazione non sposta nulla; resta nella formula
; perche' torni giusta se un giorno l'origine venisse rimessa a un valore.
PROF_TEXT_Y     EQU     BG_VIS_ROWS-(PROF_ROWS_N*(FONT_H+1))-2-BG_ORIGIN_Y

MostraProfilo:
        MOVEM.L D0-D7/A0-A4,-(SP)

        ; Path B: il buffer visualizzato e' SFONDOGRANDE, non CurrentDraw.
        ; I numeri vanno scritti alla posizione della CAMERA, altrimenti
        ; scorrono via col mondo. X arrotondata a word per l'allineamento.
        ; NB: restano impressi sul world buffer (non c'e' piu' CopiaVideo a
        ; ripulire), quindi muovendosi si sovrappongono. Va bene per leggere
        ; un numero, non per giocarci.
        MOVEA.L WorldDraw,A4            ; il monitor va nel buffer in disegno
        ADDA.L  #DELTA_MAPPAVERA+BG_ORIGIN_OFS,A4
        MOVE.W  PathBCamY,D0                    ; la camera che usa il DISPLAY
        ADD.W   #PROF_TEXT_Y,D0
        MULU.W  #SFONDO_PITCH,D0
        ADDA.L  D0,A4
        MOVE.W  PathBCamX,D0
        LSR.W   #4,D0                           ; -> word
        ADD.W   D0,D0
        ADDA.W  D0,A4
        MOVE.W  #SFONDO_PITCH,D0
        MOVE.L  #SFONDO_PLANE_SIZE,D2
;        BRA.S	.parametri

.parametri:
        MOVE.W  #5,D1                           ; replica sui 5 piani

        ; DDFSTRT non e' leggibile dal registro: lo prendo dalla copperlist,
        ; che e' la fonte di verita' di cio' che il copper scrive ogni frame.
        MOVE.W  CL_Ddf+2,ProfDdf
        MOVE.W  PathBDelay,ProfDelay
        MOVE.W  par_old,ProfParOfs


        LEA     ProfLabels,A3
        LEA     ProfWorst,A2                    ; WorstLines/DropCount/DDF seguono
        MOVEA.L A4,A1
        MOVEQ   #0,D6                           ; colonna corrente
        MOVEQ   #PROF_VALUES-1,D7
.valore:
        MOVEQ   #0,D3                           ; etichetta, 1a lettera
        MOVE.B  (A3)+,D3
        BSR.W   TestoChar
        ADDA.W  #FONT_CW,A1
        MOVEQ   #0,D3                           ; etichetta, 2a lettera
        MOVE.B  (A3)+,D3
        BSR.W   TestoChar
        ADDA.W  #FONT_CW,A1

        MOVE.W  (A2)+,D3                        ; il valore
        MOVEQ   #3,D4                           ; 3 cifre
        BSR.W   TestoNumero
        ADDA.W  #3*FONT_CW,A1

        ADDQ.W  #1,D6
        CMP.W   #PROF_COLS,D6
        BLT.S   .prossimo
        MOVEQ   #0,D6                           ; a capo
        ; il salto di riga deve usare il pitch REALE del buffer (D0), non
        ; una costante: in Path B vale 56 e non 48, e con 48 ogni riga di
        ; testo finiva 8 byte piu' avanti = 64 px a destra della precedente
        MOVE.W  D0,D5
        MULU.W  #FONT_H,D5
        ADDA.L  D5,A4
        MOVEA.L A4,A1
.prossimo:
        DBRA    D7,.valore

        MOVEM.L (SP)+,D0-D7/A0-A4
        RTS

; Etichette a 2 lettere, nello stesso ordine di ProfWorst + i due extra.
; Maiuscole per leggibilita' a 8x8; il font Metal ha anche le minuscole.
ProfLabels:
        dc.b    'VBINSCPATIDKFACVENBOBLWODRDFSWDLPO'
        even
	ENDC

*****************************************************************************

        SECTION DATI,DATA       ; variabili CPU-only -> fast RAM

; ---- Variabili del profiling harness (vedi EQU PROFILING in testa) ----
; Sempre presenti anche con PROFILING=0: 8 byte, e cosi' restano
; ispezionabili dal debugger senza ricompilare con guardie condizionali.
FrameLines:		dc.w	0       ; righe consumate da QUESTO frame (0..312)
WorstReset:		dc.w	0       ; scrivici 1 (debugger) per azzerare i worst
ProfShow:		dc.b	0       ; 1 = numeri a schermo + misura congelata (tasto P)
ProfKeyPrev:	dc.b	0       ; stato precedente del tasto P (edge detect)
ResetKeyPrev:	dc.b	0       ; stato precedente del tasto R (edge detect)
                ds.b	1       ; padding: riallinea a word quel che segue

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
PathBDelay:		dc.w	0       ; ritardo BPLCON1 del frame: darkplane e
                                ;   parallasse lo usano per compensare

	IFNE	PROTO_SCROLL
ProtoCamX:		dc.w	0       ; posizione camera del prototipo, in pixel
ProtoTuneD:		dc.w	0       ; modo taratura: il ritardo BPLCON1 sotto test
ProtoCamY:		dc.w	0
	ENDC

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

; DL = PathBDelay, cioe' il ritardo BPLCON1 di questo frame (0..63).
; PO = offset della parallasse dentro la striscia.
; Servono a leggere la scena INSIEME ai numeri che la producono: la striscia
; vuota a sinistra compare solo a ritardo grande, e senza sapere quanto vale
; DL nel momento dello screenshot ogni misura e' ambigua.
; DEVONO restare consecutive dopo ProfSwapRaster: MostraProfilo legge word di
; seguito a partire da ProfWorst.
ProfDelay:      dc.w    0       ; DL: ritardo BPLCON1 del frame
ProfParOfs:     dc.w    0       ; PO: offset della parallasse


; Palette AGA del title screen (256 colori, format $00RRGGBB long).
; Caricata via CPU in LoadAGAPalette256 prima di mostrare la title.
title_pal:
	incbin	"title.pal"

CurrentParDisplay:  
	dc.l    PARALLASSE_A
CurrentParDraw:     
	dc.l    PARALLASSE_B
; Dark plane (6° bitplane EHB). Il valore iniziale non conta: PathBInit lo
; riscrive prima di qualunque lettura.
CurrentDarkDraw:
	dc.l	0

*****************************************************************************
* TileFlags
*   Tabella delle proprieta' delle tile, indicizzata dal numero di tile.
*   bit 0 (TF_BLOCK) = 1 -> tile bloccata (non calpestabile)
*   In futuro si possono aggiungere altri flag (TF_DAMAGE, TF_WATER, ecc).
*
*   Per ora: tile 1 = libera, tutte le altre bloccate.
*   Estendi se aggiungi nuove tile alla mappa.
*****************************************************************************
TF_BLOCK        EQU     1

TileFlags:
;   tile:   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15
	dc.b	0,	0,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	0,	0,	0,	0
;   tile:  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30  31
	dc.b	0,	0,	0,	0,	0,	0,	0,	0,	0,	1,	1,	0,	0,	0,	0,	0
;   tile:  32  33  34  35  36  37  38  39  40  41  42  43  44  45  46  47
	dc.b	1,	1,	1,	1,	1,	0,	0,	0,	0,	0,	0,	1,	1,	1,	1,	1
;   tile:  48  49  50  51  52  53  54  55  56  57  58  59  60  61  62  63
	dc.b	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1,	1

	even	; padding per allineamento word
*****************************************************************************
* Disegno la mappa con le tiles 
*****************************************************************************

MAPPA:
;			  0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24;	 
	dc.w	 32,33,34,35,36,32,33,34,35,36,32,33,34, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;0
	dc.w	  2, 3, 0, 0, 0, 0, 0, 0, 0,17,18, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;1
	dc.w	  4, 5, 0, 0, 0, 0, 0, 0, 0,19,20, 0, 0, 0, 0, 0,12,13,14, 0, 0, 0, 0, 0, 0	;2
	dc.w	  6, 7, 0, 0, 0, 0, 0, 0, 0,21,22, 0, 0, 0, 0, 0,32,33,34, 0, 0, 0, 0, 0, 0	;3
	dc.w	  8, 9, 0, 0, 0, 0, 0, 0, 0,23,24, 0,12,13,14,15, 0, 0, 0, 0, 0, 0, 0, 0, 0	;4
	dc.w	 10,11, 0, 0, 0, 0, 0, 0, 0,25,26,27,32,33,34,35, 0, 0, 0, 0, 0, 0, 0, 0, 0	;5
	dc.w	  2, 3,12,13,14,15,16, 0, 0, 0,28,29, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;6
	dc.w	  4, 5,32,33,34,35,36, 0, 0, 0,30,31, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;7
	dc.w	  6, 7, 0, 0, 0, 0, 0, 0, 0, 0,37,38, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;8
	dc.w	  8, 9, 0, 0, 0, 0, 0, 0, 0, 0,39,40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;9
	dc.w	 10,11,12,13,14,15,16,12,13,14,41,42,16,12,13,14,15,16,12,13,14,15,16, 0, 0	;10
	dc.w	 35,36,32,33,34,35,36,32,33,34,35,36,32,33,34,35,36,32,32,33,34,35,36, 0, 0	;11
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;12
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;13
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;14
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;15
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;16
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;17
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;18
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;19
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;20
	dc.w	  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0	;21
	
*****************************************************************************
* VARIABILI
*****************************************************************************
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

	EVEN
; ----- Falò sprite hardware -----
FaloAnimFrame:	dc.w	0			; frame corrente (0..5)
FaloAnimDelay:	dc.w	0			; contatore frame per animazione (incrementa ogni VBL)

	EVEN

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

;------------------------------------------------------------
; Tabella di lookup direzione: 9 byte indicizzati da
; (ScrllY+1)*3 + (ScrllX+1).
; Ordine direzioni: 0=E, 1=SE, 2=S, 3=SW, 4=W, 5=NW, 6=N, 7=NE
; Valore 255 = nessun movimento (centro tabella).
;------------------------------------------------------------
DirLookupTable:
	dc.b	5, 6, 7			; ScrllY=-1: NW, N, NE
	dc.b	4, 255, 0		; ScrllY= 0: W, fermo, E
	dc.b	3, 2, 1			; ScrllY=+1: SW, S, SE
	even

PuntaSfondoGr:
	dc.l	SFONDOGRANDE

par_old:    
	dc.w    -1      ; offset del frame precedente (-1 = forza il primo blit)
par_dirty:  
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

; L'allineamento dei due campi long dipende da bob_Length: se qualcuno aggiunge
; una word sola la struttura diventa dispari di 4 e ogni bob dal secondo in poi
; legge i puntatori disallineati. La guardia lo fa notare all'assemblaggio
; invece che con un rallentamento silenzioso (FAIL viene ignorata, quindi si
; usa la divisione per zero).
ERRORE_BOB_LENGTH_NON_MULTIPLO_DI_4	EQU	bob_Length-((bob_Length/4)*4)
	IFNE	ERRORE_BOB_LENGTH_NON_MULTIPLO_DI_4
GUARDIA_BOB_LENGTH	EQU	1/0
	ENDC

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
*****************************************************************************
* DirectionDeltas
*   Tabella di delta (dx, dy) per ogni direzione, in unità di "Speed".
*   I valori sono normalizzati a -1, 0, +1 e poi moltiplicati per bob_Speed.
*   Indicizzata da bob_Direzione (0..7).
*****************************************************************************
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

*****************************************************************************
*
* 		COPPER
*
*****************************************************************************	
		
	Section	ChipStuff,data_c

; ============================================================================
; TITLE COPPERLIST - 8 bitplane AGA, lores 320x256, palette caricata via CPU.
; I puntatori BPL1..8PT (etichette TitleBPL_*) vengono patchati a runtime
; in ShowTitle a partire da title_bpl (10240 byte per plane, layout SEQUENTIAL).
; ============================================================================
	cnop	0,4
TitleCopperList:
	; Forza FMODE = $03 (BPL32+BPAGEM) all'inizio del frame, in caso qualcuno
	; (PT Player IRQ, OS, ecc.) lo abbia resettato. FMODE va impostato PRIMA
	; di abilitare BPL DMA per garantire il fetch a 64-bit allineato.
	dc.w	$01fc,$0003			; FMODE = BPL32 + BPAGEM (64-bit fetch)
	dc.w	$0100,%0000001000010001 	; BPLCON0: BPU3=1 (8 BPL) + COLOR + ECSENA (no UHRES)
	dc.w	$0102,$0000			; BPLCON1
	dc.w	$0104,$0024			; BPLCON2: PF2P=4, PF1P=4 (come gioco)
	; BRDRBLNK acceso anche qui: senza, l'area fuori dalla finestra mostra
	; COLOR00 e il titolo appare dentro una cornice chiara.
	dc.w	$0106,BPLCON3_BRDRBLNK	; BPLCON3: banca 0, LOCT=0, bordo NERO
	dc.w	$010c,$0000			; BPLCON4 = 0 (sprite a colori OCS standard 16-31)
	dc.w	$0108,$0000			; BPL1MOD (sequential layout)
	dc.w	$010a,$0000			; BPL2MOD
	dc.w	$0092,$0028			; DDFSTRT lores 8 BPL AGA FMODE=3
	dc.w	$0094,$00a8			; DDFSTOP (5 fetch FMODE=3 allineati)
; La schermata del titolo ha una geometria PROPRIA: DDFSTRT $28 / DDFSTOP $a8,
; cioe' 5 fetch = 320 px, e non ha ne' parallasse ne' scroll fine. Non deve
; quindi usare DIW_H_START, che e' tarato sui vincoli del GIOCO (guardia del
; parallasse e ritardo BPLCON1). Quando ho introdotto quella EQU l'avevo
; sostituita anche qui per sbaglio, e siccome il DIWSTOP sotto e' cablato la
; finestra del titolo diventava 160..449 = 289 px invece di 320.
	dc.w	$008e,$2c81				; DIWSTRT (valore proprio del titolo)
	dc.w	$0090,$2cc1			; DIWSTOP
TitleBPL_0:	dc.w	$00e0,$0000,$00e2,$0000	; BPL1PT (high, low)
TitleBPL_1:	dc.w	$00e4,$0000,$00e6,$0000	; BPL2PT
TitleBPL_2:	dc.w	$00e8,$0000,$00ea,$0000	; BPL3PT
TitleBPL_3:	dc.w	$00ec,$0000,$00ee,$0000	; BPL4PT
TitleBPL_4:	dc.w	$00f0,$0000,$00f2,$0000	; BPL5PT
TitleBPL_5:	dc.w	$00f4,$0000,$00f6,$0000	; BPL6PT
TitleBPL_6:	dc.w	$00f8,$0000,$00fa,$0000	; BPL7PT
TitleBPL_7:	dc.w	$00fc,$0000,$00fe,$0000	; BPL8PT
	; Past line 255 + wait V=300, poi spegne i bitplane
	dc.w	$FFDF,$FFFE
	dc.w	$2C01,$FF00
	dc.w	$0100,%0000001000000001			; BPLCON0 = 0 BPL + ECSENA
	dc.w	$FFFF,$FFFE			; FINE COPPERLIST

CopperList:
	; Il gioco gira a 8 bitplane lores con fetch AGA a 64 bit (FMODE=$0003):
	; piani 1-5 = sfondo, 6 = dark plane, 7-8 = parallasse (4 colori).
	; lasciare piu' banda DMA a blitter/CPU. Il "fetch-ahead" a 64 bit in fondo
	; allo schermo legge oltre i piani: per renderlo innocuo i 5 piani di
	; BPSFONDO sono distanziati da BG_PLANE_BANDA (con righe di padding vuote
	; tra un piano e l'altro), cosi' il prefetch pesca righe blank invece dei
	; dati del piano successivo. Vedi BG_PLANE_BANDA / BG_PAD_ROWS.
	dc.w	$01fc,$0003			; FMODE = BPL32 + BPAGEM (fetch 64-bit AGA)
	dc.w	$0100,%0000001000010001		; BPLCON0: 8 bitplane (BPU3=1, lookup 256 colori), color burst + ECSENA
									; (via anche il bit 7 UHRES che ci trascinavamo). L'EHB non c'entra:
									; il dimezzamento notturno lo fanno i colori 32..63, e i piani 7-8
									; portano il parallasse a 4 colori (vedi InitPalette8BPL).
				  ;5432109876543210	
; bit 15		HiRes
; bit 14-12		Numero di Bitplanes
; bit 11		HAM
; bit 10 		Dual Playfield
; bit 9			Color burst
; bit 8			GENLOCK AUDIO
; bit 7			UHRES (NON e' EHB! L'EHB non ha un bit: scatta solo con BPU=6)
; bit 6-4		non utilizzati
; bit 3			Light Pen
; bit 2			LACE
; bit 1			External Resync
; bit 0 		non utilizzato (ECSENA per AGA palette)

CL_BplCon1:
	dc.w	$102,0			; BplCon1 (patchato per frame dallo scroll hardware)
	dc.w	$104,$0024		; BPLCON2 = PF2P=4, PF1P=4 (sprite 0-3 davanti al playfield)
							; bit 5-3 = PF2P, bit 2-0 = PF1P (4 = primi 4 sprite davanti)
	; Nota: BPLCON3 e BPLCON4 NON sono qui perche' la PALETTE section piu' avanti
	; gia' imposta BPLCON3 (con LOCT alternato) e nessuno modifica BPLCON4 a runtime.
	; Settarli qui rompe la palette degli sprite hardware (es. falo' diventa verde).
CL_BplMod:
	dc.w	$108,BPSF_PITCH-40	; BPL1MOD = 48-40 = 8 (pitch 48, mostra 20 word/riga)
	dc.w	$10A,BPSF_PITCH-40	; BPL2MOD = 48-40 = 8
CL_Ddf:
	dc.w 	$0092,$0038,$0094,$00b8 ; DdfStrt - DdfStop (5 fetch FMODE=3 allineati)
	dc.w	$008e,($2C<<8)|DIW_H_START,$0090,((($2C+BG_VIS_ROWS)&$FF)<<8)|DIW_H_STOP	; DiwStrt - DiwStop
	; DIWSTOP verticale arriva a PANNELLO_BOT_RASTER, non piu' a fine area di
	; gioco: la fascia del pannello deve stare DENTRO la finestra, altrimenti
	; sarebbe bordo e non si vedrebbe.
	; Il V8 di DIWSTOP e' implicito come complemento di V7, e con 300 il byte
	; basso vale $2C che ha V7=0: il complemento mette V8=1 e il conto torna.
	dc.w	$008e,($2C<<8)|DIW_H_START,$0090,((PANNELLO_BOT_RASTER&$FF)<<8)|DIW_H_STOP	; DiwStrt - DiwStop

BitPlaneTiles:
	dc.w 	$e0,$0000,$e2,$0000	;primo   bitplane - BPL0PT
	dc.w 	$e4,$0000,$e6,$0000	;secondo bitplane - BPL1PT
	dc.w 	$e8,$0000,$ea,$0000	;terzo   bitplane - BPL2PT
	dc.w 	$ec,$0000,$ee,$0000	;quarto  bitplane - BPL3PT
	dc.w 	$f0,$0000,$f2,$0000	;quinto  bitplane - BPL4PT
	dc.w 	$f4,$0000,$f6,$0000	;sesto   bitplane - BPL5PT (EHB dark mask)

BitplaneParall:
	dc.w 	$f8,$0000,$fa,$0000	;settimo bitplane - BPL6PT (parallasse bit BASSO)
	dc.w 	$fc,$0000,$fe,$0000	;ottavo  bitplane - BPL7PT (parallasse bit ALTO)

Sprites:
	dc.w	$120,0,$122,0			; SPR0PT (InitSprites scrive l'indirizzo)
	dc.w	$124,0,$126,0			; SPR1PT
	dc.w	$128,0,$12a,0			; SPR2PT
	dc.w	$12c,0,$12e,0			; SPR3PT
	dc.w	$130,0,$132,0			; SPR4PT
	dc.w	$134,0,$136,0			; SPR5PT
	dc.w	$138,0,$13a,0			; SPR6PT
	dc.w	$13c,0,$13e,0			; SPR7PT

; ============================================================================
; PALETTE AGA (24-bit, 32 colori)
; Strutturata come due blocchi consecutivi nella copperlist:
;   - Blocco 1: BPLCON3 con LOCT=0, scrive nibble ALTI di ogni canale RGB
;   - Blocco 2: BPLCON3 con LOCT=1, scrive nibble BASSI di ogni canale RGB
;
; Conversione OCS->AGA per ognuno dei 32 colori:
;   colore OCS $0RGB -> 24-bit $0RRGGBB con R duplicato in RR, ecc.
;   es. $0fff -> $0FFFFFF (R=$FF, G=$FF, B=$FF)
;   In questo caso i 4 bit alti = i 4 bit bassi = il valore originale.
;   Quindi entrambe le passate scrivono lo stesso valore di nibble.
;
; BPLCON3 = $0a0c0:
;   bit 9   = LOCT (0 = nibble alti, 1 = nibble bassi)
;   bit 13-15 = PALBANK (0 = banca 0)
;   bit 10  = BRDRBLNK (1 = bordo blank)
;   bit 6   = SPRES (0 = sprite a hires)
;   bit 5-4 = riservati 0
;   bit 0-3 = utilizzati per setting vari (qui = $0)
; Valore $0c00 = LOCT=0, banca 0, bordo blank
; Valore $0e00 = LOCT=1, banca 0, bordo blank
; ============================================================================
PALETTE:
	; AGA BPLCON4:
	;   bit 15-8 = BPLAM (XOR sul bitplane color index, 8 bit)
	;   bit 7-4  = ESPRM (XOR sprite EVEN, 4 bit alti)
	;   bit 3-0  = OSPRM (XOR sprite ODD,  4 bit alti)
	; Servono sprite a COLOR17-19 (arancione): ESPRM=$1, OSPRM=$1.
	; BPLAM=$00 lascia il bitplane invariato.
	dc.w	$010c,$0011			; BPLCON4: BPLAM=0, ESPRM=$1, OSPRM=$1
	; AGA single-PF: BPLCON4 bit 7-0 sono CONDIVISI tra OSPRM (sprite ODD) e
	; BPLAM (bitplane). Quindi non si puo' avere sprite ODD a COLOR16-31
	; E bitplane normale contemporaneamente.
	; Compromesso scelto:
	;   ESPRM=$10 -> sprite EVEN (SPR0 falo') a COLOR17-19 (arancione)
	;   OSPRM=$00 -> sprite ODD (SPR1 proiettile) resta a COLOR1-3 (verdino)
	;   BPLAM=$00 -> bitplane normale (tile colors OK)
;	dc.w	$010c,$1000			; BPLCON4 = ESPRM=$10, OSPRM=$00

	; ----- Blocco 1: nibble ALTI (LOCT=0) -----
	dc.w	$0106,BPLCON3_LOCT0		; BPLCON3 = LOCT=0
GamePalHi:
	; COLOR00: durante il profiling diventa un NO-OP copper ($1fe), altrimenti
	; il copper lo riporterebbe a nero in cima a ogni frame cancellando la
	; fascia BLU scritta dalla CPU nel blanking precedente.
	IFNE	PROFILING*PROF_KILL_SKY
	dc.w	$01fe,$0000			; NO-OP: COLOR00 riservato alle fasce
	ENDC
	IFEQ	PROFILING*PROF_KILL_SKY
	dc.w	$0180,$0000			; COLOR00 = nero (sfondo di gioco)
	ENDC
	dc.w 	$0182,$0fff,$0184,$0040,$0186,$0070	
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0850	
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	dc.w 	$0198,$000f,$019a,$070f,$019c,$0c0e,$019e,$0c08
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca	
	dc.w 	$01a8,$0000,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff
	; ----- Blocco 2: nibble BASSI (LOCT=1) -----
	dc.w	$0106,BPLCON3_LOCT1		; BPLCON3 = LOCT=1
GamePalLo:
	IFNE	PROFILING*PROF_KILL_SKY
	dc.w	$01fe,$0000			; NO-OP (vedi GamePalHi)
	ENDC
	IFEQ	PROFILING*PROF_KILL_SKY
	dc.w	$0180,$0000
	ENDC
	dc.w 	$0182,$0fff,$0184,$0040,$0186,$0070
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	dc.w 	$0198,$000f,$019a,$070f,$019c,$0c0e,$019e,$0c08
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca
	dc.w 	$01a8,$0000,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff

	; Ripristino BPLCON3 a default LOCT=0 (per il prossimo frame)
	dc.w	$0106,BPLCON3_LOCT0

; Gradiente cielo: e' parte della copperlist perche' cambia COLOR00 riga per
; riga, in sincrono col pennello.
;
; VERIFICATO sul contenuto di CieloCopper.i: scrive SOLO due registri, BPLCON3
; ($106, per alternare LOCT fra nibble alti e bassi) e COLOR00 ($180). NON
; tocca i puntatori bitplane, quindi non interferisce con lo scroll hardware
; che riscrive BPL1PT..BPL6PT a ogni frame. Il vecchio commento qui diceva che
; scriveva a BPL1PT..BPL5PT: era falso.
; Copre esattamente le righe visibili, da $2c a $2c+BG_VIS_ROWS-1, perche' la
; lista e' generata su misura. Lascia BPLCON3 a LOCT=0 in coda.
;
; Va ESCLUSO solo se si vuole leggere il costo delle fasi dalle fasce colorate
; a bordo schermo (PROF_KILL_SKY=1): riscrivendo COLOR00 su ogni riga le
; coprirebbe nell'area di gioco. La misura numerica del monitor P non ne
; risente in nessun caso.
	IFEQ	PROFILING*PROF_KILL_SKY
	; Il gradiente NON e' piu' un include statico: BuildSkyCopper riempie questo
	; spazio al boot ricampionando SkyGradient su BG_VIS_ROWS righe, cosi' resta
	; interamente visibile qualunque sia CUT_BOTTOM_ROWS. Lo spazio sta QUI, in
	; linea nella copperlist, per non cambiare nulla di dove vive la lista.
SkyCopper:
	ds.w	SKY_COPPER_WORDS
	ENDC

; Spegne il DMA bitplane in fondo allo schermo. Senza questo, WinUAE
; (e hardware reale in overscan) continua a fetchare oltre BPSFONDO
; (che ha pitch 40) trovando SFONDOGRANDE (pitch 48): legge "a mosaico"
; pezzi di righe diverse -> riga parziale/sfarfallante in fondo, visibile
; soprattutto dove la luce notturna la illumina.
;
; IMPORTANTE: lo spegnimento va fatto a FINE scanline 299 (dopo che la
; riga 255 e' gia' stata prelevata e mostrata: il DIW orizzontale finisce
; a H=$C1, e DDFSTOP e' a $b8) ma PRIMA che inizi il fetch della scanline
; 300. Se invece si aspetta l'INIZIO di V=300 (H=$00), il fetch della
; scanline 300 (DDFSTART=$38) parte prima che il copper - che ha priorita'
; DMA inferiore al bitplane - riesca a scrivere BPLCON0=0: la quantita' di
; over-fetch che trapela dipende dalla contesa di bus (sprite/blitter) e
; varia da frame a frame -> sfarfallio. Spegnendo a V=299/H=$E0 il fetch
; della riga di over-fetch non avviene MAI (race-proof).
;
; Il copper VP e' 8 bit: per V>=256 serve il "trick" past-line-255
; (WAIT $FFDF,$FFFE) che fa scattare il flip-flop interno V8.
	; ---------------------------------------------------------------
	; CONFINE AREA DI GIOCO / PANNELLO
	; A PANNELLO_TOP_RASTER si passa dal mondo (8 piani, buffer che scorre) al
	; pannello (4 piani, buffer fisso). I moduli NON si toccano: il buffer del
	; pannello ha lo stesso pitch del mondo apposta, cosi' la geometria del
	; fetch resta identica e non c'e' niente da ritarare.
	; ---------------------------------------------------------------
	; Il WAIT e' sulla riga PRECEDENTE, a H=$DC, non su quella del pannello a H=0.
	; Motivo: dopo il WAIT ci sono 11 MOVE e ogni MOVE del copper costa 2 color
	; clock, quindi 22 in tutto. Aspettando (riga 220, H=0) le ultime scritture
	; cadevano verso il cc 22, mentre il DMA bitplane di quella riga parte a
	; DDFSTRT = $18 = 24: i piani senza puntatore nuovo continuavano a leggere il
	; buffer del MONDO e restavano sfasati per tutto il frame — e a schermo si
	; vedevano i colori delle tile mescolati al pannello.
	; Aspettando a fine riga 219 le scritture cadono nell'orizzontale blank e
	; arrivano tutte prima del fetch. I PUNTATORI stanno per primi, cosi' sono i
	; primi a essere aggiornati; BPLCON0 e COLOR00 possono permettersi di seguire.
	; WAIT dentro la finestra tranquilla della riga DEL PANNELLO: dopo che il
	; fetch della riga precedente ha finito di sforare, e prima di DDFSTRT.
	; Vedi il commento su PANNELLO_PTR_WAIT_H per il perche' del valore.
	dc.w	((PANNELLO_TOP_RASTER&$FF)<<8)|$02|$01,$FFFE	; WAIT righe di separazione
	; BPLCON0 per PRIMO: deve valere prima che parta il fetch, e costa un MOVE
	; solo. Poi i quattro puntatori, in ordine naturale. BPLCON1 e COLOR00 vanno
	; in coda: a loro basta arrivare prima della parte VISIBILE della riga, che
	; comincia molto piu' tardi, quindi possono cadere anche dopo DDFSTRT.
	; --- righe di separazione: bitplane spenti, e qui si carica la palette ---
	dc.w	$0100,%0000001000000001 		; BPLCON0: 0 bitplane
	; La palette del pannello e' lo stesso file INCLUSO DUE VOLTE: una con LOCT=0
	; per i nibble alti e una con LOCT=1 per i bassi. Scrivendo lo stesso valore
	; in entrambi si ottiene l'espansione 12->24 bit ($F diventa $FF), che e' la
	; convenzione con cui e' fatta anche la palette del gioco.
	dc.w	$0106,BPLCON3_LOCT0
	include	"Pannello.cop"
	dc.w	$0106,BPLCON3_LOCT1
	include	"Pannello.cop"
	dc.w	$0106,BPLCON3_LOCT0

	; --- inizio dell'arte: puntatori e 4 bitplane ---
	dc.w	((PANNELLO_ART_RASTER&$FF)<<8)|$02|$01,$FFFE	; WAIT inizio arte
BitplanePannello:
	dc.w	$00e0,0,$00e2,0		; BPL1PT (riempiti da DisegnaPannello, una volta al boot)
	dc.w	$00e4,0,$00e6,0		; BPL2PT
	dc.w	$00e8,0,$00ea,0		; BPL3PT
	dc.w	$00ec,0,$00ee,0		; BPL4PT
	dc.w	$0100,%0100001000000001 ; BPLCON0: 4 bitplane (BPU=4), COLOR, ECSENA
	dc.w	$0102,$0000			; BPLCON1: niente scorrimento fine qui


	dc.w	$FFDF,$FFFE		; past end of line 255 (arma V8)
	dc.w	(((PANNELLO_BOT_RASTER-256)&$FF)<<8)|$E0|$01,$FFFE	; WAIT fine fascia pannello
	dc.w	$0100,%0000001000000001		; BPLCON0: 0 bitplane, Color burst, ECSENA

	dc.w	$FFFF,$FFFE		; FINE DELLA COPPERLIST
 

*****************************************************************************
* Qui sono memorizzate le tiles dello sfondo e tutti gli oggetti che ci si 
* muovono sopra: OMINO, NEMICO, ecc. Tutti i dati sono in formato bitplane
*****************************************************************************
	
TILES:
	incbin	"Tiles.raw"	

OMINO:
	incbin	"Omino32.raw"	

NEMICO:
	incbin	"Nemico32.raw"	

PIETRA:
	incbin	"Pietra.raw"	

*****************************************************************************

	SECTION	PLANEVUOTO,BSS_C

	IFNE	PROTO_SCROLL
; --- Buffer del prototipo scroll (Path B passo 1) --------------------
; Pitch 56 = 48 + 8 byte di guardia a sinistra, richiesti dal prefetch
; di un blocco FMODE=3. La mappa vera comincia all'offset 8 di ogni riga.
; 5 piani x 56 x 352 = 98560 byte. ProtoVuoto tiene i piani 6/7/8 accesi
; (contesa DMA realistica) senza sporcare la lettura della griglia.
	cnop	0,8
ProtoBuffer:
	ds.b	5*PROTO_PLANE_SIZE
	cnop	0,8
ProtoVuoto:
	ds.b	PROTO_PLANE_SIZE
	ENDC

	cnop	0,8
; Piano vuoto col pitch dei piani 1-5: ci puntano i piani ausiliari
; disattivati da SWITCH_PIANI.
PathBVuoto:
	ds.b	AUX_PITCH*DARK_ROWS
	cnop	0,8
; Copia pulita della mappa, sorgente del restore dietro ai BOB.
PathBMaster:
	ds.b	5*SFONDO_PLANE_SIZE
	cnop	0,8
; Darkplane STATICO: stesso layout dei piani 1-5, disegnato una volta in
; coordinate mondo e fatto scorrere con loro. Sostituisce DARKPLANE_A/B.
PathBDarkPlane:
	ds.b	SFONDO_PLANE_SIZE

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
; DOPPIO BUFFER DEL MONDO. Si disegna in WorldDraw e si visualizza WorldShow,
; scambiati in coda al blocco di lavoro da ScrollPathBApply. Serve perche' il
; blocco SCAVALCA il confine del quadro: senza secondo buffer il pennello puo'
; raggiungere un BOB ancora in corso di disegno e mostrarlo tagliato.
SFONDOGRANDE:
	ds.b	5*SFONDO_PLANE_SIZE	; 5 plane * SFONDO_PITCH * SFONDO_HEIGHT

	cnop	0,8
SFONDOGRANDE_B:
	ds.b	5*SFONDO_PLANE_SIZE	; secondo buffer del mondo, stesso layout di SFONDOGRANDE

	; I due buffer di parallasse sono puntati da BPL7PT/BPL8PT: con FMODE=3 il
	; puntatore deve essere allineato a 8 byte. Finora reggeva per ACCUMULO,
	; perche' 5*SFONDO_PLANE_SIZE e 2*PAR_PLANE_BANDA sono entrambi multipli di
	; 8 — ma bastava cambiare SFONDO_HEIGHT, il pitch o PAR_PLANE_BANDA per
	; romperlo IN SILENZIO. Meglio dichiararlo che sperarci.
	cnop	0,8
PannelloBuf:
	ds.b	4*PANNELLO_BUF_PLANE	; 4 piani, pitch del mondo, PANNELLO_HEIGHT righe

	cnop	0,8
PARALLASSE_A:
    ds.b    2*PAR_PLANE_BANDA
	cnop	0,8
PARALLASSE_B:
    ds.b    2*PAR_PLANE_BANDA
	cnop	0,8
PARALLAX_STRIP:
    ds.b    2*PARALLAX_STRIP_PLANE_SZ    ; 2 piani paddati, ~61 KB chip
    cnop    0,8
	cnop	0,8
	cnop	0,8
; Maschera del disco di luce (bit=1 dentro). Sorgente A del blitter in
; DisegnaCerchioLuceBlitter. In chip RAM (la DMA del blitter la legge).
; Costruita una volta al boot da BuildLightMask.
LightMask:
	ds.b	LIGHT_MASK_BANDA*LIGHT_MASK_H	; 18 byte * 128 righe = 2304 byte

; Maschera dell'OMINO: 1 bitplane (10240 byte = 40*256) calcolata al boot
; come OR dei 5 bitplane dello spritesheet originale.
; Il blitter la usa come canale B per il cookie-cut nei BOB.
OMINO_MASK:
	ds.b	PLANE_SIZE			; 1 plane mask (stesso pitch di OMINO)

; Maschera del NEMICO: i nemici usano lo stesso DisegnaBOB ma un altro sheet,
; quindi serve la loro silhouette, non quella dell'omino.
NEMICO_MASK:
	ds.b	PLANE_SIZE			; 1 plane mask (stesso pitch di NEMICO)

; Maschera della PIETRA (il proiettile). Sheet piu' piccolo degli altri due,
; quindi la sua maschera e' grande quanto UN piano DI QUESTO sheet, non
; quanto PLANE_SIZE: e' il motivo per cui BuildBobMask ora prende la
; dimensione del piano come parametro invece di leggerla da una EQU globale.
PIETRA_MASK:
	ds.b	PIETRA_PLANE_SIZE	; 1 plane mask (stesso pitch di PIETRA)

*****************************************************************************

	SECTION	SpritesData,data_c
	cnop	0,8				; allineamento sprite
;----------------------------------------------------------------------------
; MOD ProTracker - DEVE essere in chip RAM (data_c) per Paula DMA
;----------------------------------------------------------------------------
	cnop	0,4
ANTIRIAD_MOD:
	incbin	"antiriad.amiga.mod"

;----------------------------------------------------------------------------
; Title screen image: 8 bitplane AGA, 320x256, sequential layout.
; DEVE essere in CHIP RAM per la display DMA.
;----------------------------------------------------------------------------
	cnop	0,8					; allineamento AGA FMODE=3
title_bpl:
	incbin	"title.raw"

;----------------------------------------------------------------------------
; Parallasse  : 2 bitplane AGA, 640x256, sequential layout.
; DEVE essere in CHIP RAM per la display DMA.
;----------------------------------------------------------------------------
	cnop	0,8					; allineamento AGA FMODE=3
parallasse:
	incbin	"parallasse.raw"

;----------------------------------------------------------------------------
; Pannello  : 4 bitplane AGA, 320x80, sequential layout.
; DEVE essere in CHIP RAM per la display DMA.
;----------------------------------------------------------------------------
	cnop	0,8					; allineamento AGA FMODE=3
pannello:
	incbin	"pannello.raw"

;----------------------------------------------------------------------------
; Sound effects samples (8-bit signed PCM raw mono).
; DEVONO essere in CHIP RAM per il DMA audio Paula.
; Lunghezza calcolata a compile-time da (End-Start)/2 nelle SfxStructure,
; quindi puoi sostituire i .raw con sample di lunghezza diversa senza
; toccare il sorgente: basta che il file abbia un numero pari di byte.
;----------------------------------------------------------------------------
	cnop	0,4
SparoSample:
	incbin	"Sparo.raw"
SparoSampleEnd:
SPARO_LEN		EQU	(SparoSampleEnd-SparoSample)/2

	cnop	0,4
PassoSample:
	incbin	"passo.raw"
PassoSampleEnd:
PASSO_LEN		EQU	(PassoSampleEnd-PassoSample)/2

	cnop	0,4
NemicoColpitoSample:
	incbin	"nemico_colpito.raw"
NemicoColpitoSampleEnd:
NEMICO_COLPITO_LEN	EQU	(NemicoColpitoSampleEnd-NemicoColpitoSample)/2

	cnop	0,4
HitPlayerSample:
	incbin	"HitPlayer.raw"
HitPlayerSampleEnd:
HITPLAYER_LEN	EQU	(HitPlayerSampleEnd-HitPlayerSample)/2

	cnop	0,4
NemicoMortoSample:
	incbin	"nemico_morto.raw"
NemicoMortoSampleEnd:
NEMICO_MORTO_LEN	EQU	(NemicoMortoSampleEnd-NemicoMortoSample)/2

	cnop	0,8
; ============================================================================
; Sprite hardware FUOCO - 6 frame di animazione
; Ogni frame e' una struttura sprite indipendente:
;   - 2 word header (SPRPOS, SPRCTL) settati a runtime
;   - 16 righe x 2 word interleaved (plane0, plane1) = 32 word = 64 byte dati
;   - 2 word terminator (0, 0)
; Totale per frame: 2 + 32 + 2 = 36 word = 72 byte
;
; A runtime, SPR0PT puntera' a uno dei FuocoFrame_X in base a FaloAnimFrame.
; ============================================================================
FuocoFrame_0:
	dc.w	$0000,$0000				; SPRPOS, SPRCTL (runtime)
	incbin	"Fuoco_Data.raw",0,64	; offset 0, 64 byte (frame 0)
	dc.w	0,0						; terminator

	cnop	0,4
FuocoFrame_1:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",64,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_2:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",128,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_3:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",192,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_4:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",256,64
	dc.w	0,0

	cnop	0,4
FuocoFrame_5:
	dc.w	$0000,$0000
	incbin	"Fuoco_Data.raw",320,64
	dc.w	0,0

	cnop	0,8
; Sprite vuoto per disattivare gli sprite non usati (SPR1..SPR7)
EmptySprite:
	dc.w	0,0				; SPRPOS, SPRCTL
	dc.w	0,0				; terminator

*****************************************************************************

	SECTION	Entities,BSS

	cnop	0,4				; base allineata a 4: bob_Length e' multiplo di 4,
							; quindi i campi long restano allineati per OGNI bob
; I bob stanno TUTTI in memoria contigua sotto BobArray: tre ds.b consecutivi
; nella stessa sezione lo sono per costruzione. Cosi' un solo ciclo li percorre
; con LEA bob_Length(A0),A0 e non serve nessuna tabella di puntatori.
; Player ed Enemies restano ETICHETTE VERE, quindi Player+bob_WorldX e
; LEA Enemies,A0 continuano a funzionare identici in tutto il resto del file.
; L'ORDINE DI DICHIARAZIONE E' L'ORDINE DI DISEGNO, cioe' lo z-order:
; i nemici sotto, sopra di loro il player, la pietra sopra a tutti.
; Aggiungere un bob (il falo', le parti del pannello) = un ds.b in piu' qui
; e BOB_TOTALI alzato di uno. Nessun codice da toccare.
BobArray:
Enemies:
	ds.b	bob_Length*ENEMY_COUNT	; array dei nemici
Player:
	ds.b	bob_Length		  		; struct del player
BobPietra:
	ds.b	bob_Length				; il proiettile: stessa struct di tutti gli altri

*****************************************************************************

;----------------------------------------------------------------------------
; PT PLAYER di Frank Wille (rinominato ptplayer.i per evitare la
; compilazione automatica dell'extension vscode-amiga-assembly).
;
; IMPORTANTE: ptplayer.i NON dichiara una propria SECTION code, quindi
; eredita la SECTION corrente. Bisogna riportare la SECTION corrente in
; CODE prima dell'include, altrimenti il codice del player finisce
; in BSS e crasha appena chiamato.
;----------------------------------------------------------------------------
	SECTION	PTPlayerCode,CODE

	include	"ptplayer.i"

	end

*****************************************************************************