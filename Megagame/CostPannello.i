; CostPannello.i - Costanti: strumenti del pannello
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

; ROTELLA DEL PUNTEGGIO - grafica/rotella_punteggio.raw
; Striscia 320x16 a 2 piani SEPARATI, com'esce dall'editor: prima tutto il
; piano 0, poi tutto il piano 1. Una riga e' larga quanto la STRISCIA, non
; quanto un fotogramma.
; Griglia di fotogrammi 8x8 su due righe:
;   riga 0: dieci cifre, ognuna col suo rotolamento verso la successiva.
;           Il fotogramma 0 di ogni cifra e' la cifra FERMA: la cifra N sta
;           alla colonna N*ROTELLA_PASSI.
;   riga 1: quattro fotogrammi di rotazione veloce, disegnati ma MAI USATI.
;           Il 7 settembre 2026 Michele ha deciso che il rotolamento cosi'
;           com'e' gli piace e che in questo gioco la rotazione veloce non
;           serve. L'arte resta nella striscia: e' gia' disegnata, sta in fast
;           RAM e toglierla vorrebbe dire rigenerare il .raw per 1280 byte.
ROTELLA_W			EQU		8			; lato di un fotogramma (px)
ROTELLA_H			EQU		8
ROTELLA_PIANI		EQU		2
ROTELLA_CIFRE		EQU		10
ROTELLA_PASSI		EQU		4			; fotogrammi da una cifra alla successiva
ROTELLA_VELOCI		EQU		4			; fotogrammi di rotazione veloce nella
					; riga 1. Descrive l'arte e basta: nessuna EQU ci discende
					; e nessuna routine la legge, perche' quella rotazione non
					; si usa.
ROTELLA_RIGHE		EQU		2			; righe di celle nella striscia
; Da qui in giu' e' tutto derivato: la striscia e' fatta cosi' perche' i
; fotogrammi sono quelli, non viceversa.
ROTELLA_CELL_W		EQU		ROTELLA_W*2		; 8 di arte + 8 di stacco per lo shift
ROTELLA_COLONNE		EQU		ROTELLA_CIFRE*ROTELLA_PASSI
ROTELLA_STRIP_W		EQU		ROTELLA_COLONNE*ROTELLA_CELL_W
ROTELLA_STRIP_H		EQU		ROTELLA_RIGHE*ROTELLA_H
ROTELLA_ROWB		EQU		ROTELLA_STRIP_W/8				; byte per riga PER PIANO
ROTELLA_PLANE_SZ	EQU		ROTELLA_ROWB*ROTELLA_STRIP_H 	; byte per piano
ROTELLA_PIANI_PAN	EQU		4
ROTELLA_SHEET_SZ	EQU		ROTELLA_PLANE_SZ*ROTELLA_PIANI_PAN
; Riquadro del punteggio dentro l'arte del pannello, MISURATO sui pixel di
; Pannello.raw: l'interno pieno (indice 15) e' x 70..113, y 23..30, cioe'
; 44x8. Le cinque cifre da 8 px ci stanno centrate con 2 px di margine.
; Sono coordinate relative all'ANGOLO DEL PANNELLO, non allo schermo.
PUNTEGGIO_CIFRE		EQU		5
PUNTEGGIO_BOX_X		EQU		70			; primo px pieno del riquadro
PUNTEGGIO_BOX_W		EQU		44
PUNTEGGIO_Y			EQU		23
PUNTEGGIO_X			EQU		PUNTEGGIO_BOX_X+(PUNTEGGIO_BOX_W-PUNTEGGIO_CIFRE*ROTELLA_W)/2
; ATTENZIONE: questo conto DEVE dare un multiplo di 8. E' il fatto che ogni
; cifra cada su un byte intero a permettere di scriverla con una MOVE.B invece
; che col blitter, che qui vorrebbe maschera, shift e un minterm a tre canali.
; Oggi da' 72 e torna. Cambiando la larghezza del riquadro o il numero di cifre
; puo' non tornare piu': in quel caso non si aggiusta la routine, si sposta il
; RIQUADRO nell'arte finche' il conto non torna.
; Lo stacco fra una cifra e l'altra sta nell'ARTE e non nel passo: l'ultima
; colonna di ogni cella e' vuota. Le colonne 0 e 7 di ogni cifra non hanno mai
; un pixel di tratto - solo fondo - quindi spegnerne una non tocca i numeri.
; Un passo di 9 px darebbe lo stesso stacco ma manderebbe le cifre 2, 3, 4 e 5
; fuori dal confine di byte, e servirebbe uno shifter software.
; Il massimo che ci sta nelle cifre che si vedono. Non e' un tetto scelto a
; gusto: e' PUNTEGGIO_CIFRE nove di fila. Regge anche il vincolo della DIVU in
; DisegnaPunteggio, che vuole il quoziente in 16 bit: 99999/10 = 9999, ci sta.
; Con una cifra in piu' il primo giro di DIVU sborderebbe e quella routine
; andrebbe rifatta a long. Se cambi PUNTEGGIO_CIFRE, cambia anche questo.
PUNTEGGIO_MAX		EQU		99999
; Punti per nemico abbattuto. Il colpo che non uccide non da' punti.
PUNTI_NEMICO		EQU		100
; Di quanti FOTOGRAMMI il numero mostrato si avvicina a quello vero a ogni
; frame. Non sono punti: il contatore della rotella e' in scala ROTELLA_PASSI,
; quindi un punto vale 4 passi. E' un parametro, non un interruttore.
;   velocita' = PUNTEGGIO_PASSO * 50 / ROTELLA_PASSI punti al secondo
;   con 1 -> 12,5 punti/s, e si vedono tutti e quattro i fotogrammi
;   con 2 -> 25 punti/s, se ne vedono due su quattro
;   con 4 -> 50 punti/s ma la fase e' sempre 0: si torna allo scatto netto
; Sopra 1 il rotolamento perde fotogrammi, e con 3 li mostra pure fuori ordine
; (0,3,2,1). QUINDI QUESTO VALORE RESTA 1: la velocita' non si alza di qui.
; L'altra strada - la rotazione veloce della riga 1 dello sheet - e' stata
; guardata e SCARTATA il 7 settembre 2026: il rotolamento a 12,5 punti al
; secondo e' quello che si vuole vedere in questo gioco.
; A 0 il punteggio non arriverebbe mai: non metterlo a 0.
PUNTEGGIO_PASSO		EQU		1

; INDICATORI DI SINISTRA - grafica/indicatore.raw
; Griglia 9 colonne x 11 righe di celle 48x8, arte 40x8 nei primi 40 px della
; cella. Le RIGHE sono gli 11 livelli di riempimento (0, 4, 8 ... 40 px). Le
; COLONNE sono un'animazione a riposo: la punta gonfia in avanti (1,2,3) e poi
; rientra (4..8), con le scintille che scorrono. Oggi si usa solo la colonna 0,
; che e' la posa ferma ed e' l'unica presente a TUTTI gli undici livelli: alla
; riga 0 mancano le 4..8 (sotto lo zero non si rientra) e alla riga 10 mancano
; le 1..3 (oltre il pieno non si gonfia).
INDIC_W				EQU		40			; larghezza dell'arte (px)
INDIC_H				EQU		8
INDIC_PIANI			EQU		2			; piani dell'arte, come esce dall'editor
INDIC_LIVELLI		EQU		11			; righe della griglia: livelli 0..10
INDIC_CELL_W		EQU		48			; passo orizzontale di una cella (px)
; Le colonne di una riga non sono animazioni qualsiasi: sono la posa a riposo
; e le due TRANSIZIONI che partono dal livello di quella riga.
;   colonne 0..2     ferma, con le bolle che salgono: un ciclo che gira sempre
;   colonne 3..7     la barra che SALE verso il livello successivo
;   colonne 8..12    la barra che SCENDE verso il livello precedente
; E' anche la spiegazione dei due buchi nella griglia: alla riga 10 mancano le
; colonne della salita perche' dal pieno non si sale, e alla riga 0 quelle
; della discesa perche' dal vuoto non si scende. La macchina a stati non le
; chiede mai, ed e' un invariante da verificare quando la si tocca.
INDIC_FASI_FERMA	EQU		3						; colonne 0..2, le bolle
INDIC_FASI_SU		EQU		5						; colonne 3..7
INDIC_FASI_GIU		EQU		5						; colonne 8..12
INDIC_FASE_SU		EQU		INDIC_FASI_FERMA		; prima colonna della salita
INDIC_FASE_GIU		EQU		INDIC_FASE_SU+INDIC_FASI_SU	; prima colonna della discesa
INDIC_FOTOGRAMMI	EQU		INDIC_FASE_GIU+INDIC_FASI_GIU	; colonne di una riga
; Quanti frame dura un fotogramma. Un livello costa INDIC_RITMO*INDIC_FASI_SU+1
; frame a salire e altrettanti a scendere - il +1 e' il frame in cui la
; transizione parte. Con 3 sono 16 frame (0,32 s) per livello nei due versi, e
; la barra si riempie da zero in poco piu' di 3 secondi.
; Le bolle vanno per conto loro e piu' adagio: sono una cosa che respira, non
; una transizione. Con 8 il ciclo delle tre bolle dura mezzo secondo.
; Nessuno dei due va messo a 0: l'animazione non avanzerebbe mai.
INDIC_RITMO			EQU		3
INDIC_RITMO_BOLLE	EQU		8
; Da qui in giu' e' tutto derivato dalla griglia.
INDIC_BYTE_W		EQU		INDIC_W/8			; 5 byte: l'arte e' larga un numero
	; intero di byte, ed e' il motivo
	; per cui la disegna la CPU
INDIC_STRIP_W		EQU		INDIC_FOTOGRAMMI*INDIC_CELL_W
INDIC_ROWB			EQU		INDIC_STRIP_W/8		; byte per riga PER PIANO
INDIC_PLANE_SZ		EQU		INDIC_ROWB*INDIC_H*INDIC_LIVELLI
INDIC_PIANI_PAN		EQU		4
INDIC_SHEET_SZ		EQU		INDIC_PLANE_SZ*INDIC_PIANI_PAN

; Posizione dei due riquadri, MISURATA sui pixel di Pannello.raw dopo che i
; buchi sono stati portati a x 24..63: 40 px esatti e allineati al byte, che e'
; quello che permette di scrivere con la CPU invece che col blitter.
; Sono coordinate relative all'ANGOLO DEL PANNELLO, non allo schermo.
INDIC_X				EQU		24			; primo px del buco (multiplo di 8)
INDIC_ALTO_Y		EQU		14			; riquadro in alto: energia
INDIC_BASSO_Y		EQU		32			; riquadro in basso: vita del player
; INDIC_BASSO_RASTER sta piu' in basso, sotto PANNELLO_ART_RASTER da cui
; discende: Devpac valuta le EQU dove le incontra e non tollera un riferimento
; in avanti.

; Fondo scala dei due valori. Il livello mostrato si ricava, non si conta:
;   livello = valore * (INDIC_LIVELLI-1) / massimo
; Cambiando un massimo la barra si ritara da sola.
PLAYER_PF_MAX		EQU		20			; punti ferita del player a inizio partita
ENERGIA_MAX			EQU		20			; stessa scala, per ora: l'energia non ha
	; ancora un uso nel gioco

; --- scontro al contatto (vedi Combattimento) ---
; I nemici hanno danno e recupero nella loro EnemyInitTable, il player no:
; sono questi due. Il recupero e' in frame, quindi a 50 Hz.
PLAYER_DANNO		EQU		1			; quanto toglie a un nemico toccandolo
PLAYER_INVULN_MAX	EQU		50			; un secondo di respiro dopo un colpo preso.
	; Se fosse 0 il contatto toglierebbe un
	; punto ferita a OGNI frame.

; Pannello.i - generato da png2amiga.py
PANNELLO_HEIGHT			EQU     80
PANNELLO_BITPLANES		EQU     4

; Il pannello e' largo QUANTO LA FINESTRA. Prima erano 40 byte scritti a mano
; e una guardia controllava che 40*8 facesse 320: adesso i 40 byte escono
; dalla finestra e non c'e' piu' un secondo numero che possa divergere.
PANNELLO_BYTES_PER_ROW	EQU		DIW_WIDTH/8
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

; Riga raster della prima riga del riquadro BASSO degli indicatori: e' li' che
; il copper cambia il colore della barra, cosi' i due riquadri possono mostrare
; fasce diverse nello stesso quadro. Sta qui e non con le altre INDIC_* perche'
; discende da PANNELLO_ART_RASTER, e Devpac valuta le EQU dove le incontra.
INDIC_BASSO_RASTER		EQU		PANNELLO_ART_RASTER+INDIC_BASSO_Y

; Il buffer di visualizzazione ha lo STESSO pitch del mondo, non 40 byte: cosi'
; il display usa gli stessi BPLxMOD e la stessa geometria DDF/DIW, e al confine
; bastano i puntatori e il numero di piani.
; L'arte viene blittata a DELTA_MAPPAVERA byte dall'inizio di ogni riga, cioe'
; dove comincia la mappa: il pannello si vede esattamente come si vedrebbe il
; mondo a CameraX=0.
PANNELLO_BUF_PITCH		EQU		SFONDO_PITCH
PANNELLO_BUF_PLANE		EQU		PANNELLO_BUF_PITCH*PANNELLO_HEIGHT

; Byte dall'inizio della riga a cui va messa l'arte dentro PannelloBuf.
; Il puntatore del pannello sta al byte 0 della riga e BPLCON1 vale 0 nella sua
; fascia: il pannello non scorre. Conta quindi una cosa sola, QUALE byte del
; buffer finisce a x=0. L'arte va messa esattamente li'; a OFS si vede spostata
; a destra di (OFS-V)*8 px.
; QUESTO VALORE NON E' DERIVATO, E' MISURATO A SCHERMO, uno per posizione
; dell'interruttore:  64 bit -> 0,  32 bit -> 4,  16 bit -> 2.
; I tre non stanno su nessuna retta, e nemmeno il prefetch in byte (8, 4, 2) li
; spiega: a 32 e a 16 il valore coincide col prefetch, a 64 no. Una formula che
; ne indovina due su tre ha gia' mandato il pannello 32 px fuori posto: finche'
; la legge non si conosce, tre valori misurati valgono di piu'. Chi la trova
; sostituisca i tre rami.
; DIAGNOSI: lo scarto in px diviso 8 e' quanto togliere (pannello a destra) o
; aggiungere (a sinistra). La striscia di spazzatura a sinistra dell'arte e' un
; sintomo, non un secondo difetto: quel buffer nessuno lo azzera.
	IFEQ	SCROLL_FETCH_BIT-64
PANNELLO_ART_BYTE_OFS	EQU		0
	ENDC
	IFEQ	SCROLL_FETCH_BIT-32
PANNELLO_ART_BYTE_OFS	EQU		4
	ENDC
	IFEQ	SCROLL_FETCH_BIT-16
PANNELLO_ART_BYTE_OFS	EQU		2
	ENDC

; PROVA a costanti invece dell'arte: vedi DisegnaPannello. A 0 disegna l'arte.
PANNELLO_TEST_FILL		EQU		0	; 1 = costanti al posto dell'arte (diagnostica)

; LA PARALLASSE E' FATTA DI ALBERI, UNO PER SPRITE
; Ogni albero e' uno sprite a se': la sua Y non cambia MAI (si muove solo in
; X), quindi l'assegnazione albero->canale si calcola una volta al boot e non
; si tocca piu'. Ogni quadro si riscrive soltanto HSTART, due byte per albero.
; IL VINCOLO E' UNO SOLO: il numero di canali e' il massimo numero di alberi
; che condividono una riga. Qui tutti si appoggiano al fondo dell'area di
; gioco, quindi condividono tutti le righe basse e SETTE E' IL TETTO ESATTO -
; sette canali, sette alberi, non uno di piu'. Per averne altri bisognerebbe
; staccarne qualcuno dal fondo.
; IL PERIODO E' 384 = DIW_WIDTH + 64, e non e' estetica:
;     x_liv  = (x_albero - offset_del_livello) mod ALBERI_PERIODO
;     HSTART = DIW_H_START - 64 + x_liv
; tiene HSTART fra 65 e 449, sempre dentro i 9 bit del registro. A 65 l'albero
; finisce appena fuori a sinistra, a 449 comincia dove la finestra chiude:
; esce e rientra da solo, senza un ramo "se e' fuori schermo".
; Arte e tabella le genera tools/genera-alberi-sprite.py, che stampa anche i
; valori qui sotto. La guardia sulla lunghezza del file li tiene in pari.
ALBERI_N			EQU		7
ALBERI_LEN_ATTESA	EQU		80960		; guardia: la lunghezza del .raw
ALBERI_PERIODO		EQU		DIW_WIDTH+64
ALBERI_VOCE			EQU		12				; per albero: offset della posa 0
	; come LONG (l'arte supera i 32 KB e una word con segno
	; non ci arriva), poi passo, x, livello e fase, a word.
ALBERI_OFS_POSA0	EQU		0
ALBERI_OFS_PASSO	EQU		4
ALBERI_OFS_X		EQU		6
ALBERI_OFS_LIV		EQU		8
ALBERI_OFS_FASE		EQU		10
; Le due velocita', in bit di scorrimento a destra su CameraX.
ALBERI_SH_VICINO	EQU		1				; meta' della camera
ALBERI_SH_LONTANO	EQU		2				; un quarto

; ---- IL VENTO ----
; Il vento e' DISEGNATO, non calcolato: ogni albero ha VENTO_POSE disegni
; completi, uno per grado di flessione, e oscillare vuol dire cambiare il
; PUNTATORE del canale. La curva e' quella di una trave incastrata - zero alla
; base, massima in cima - quindi l'albero si piega e il fusto resta piantato.
; Il primo tentativo faceva un'altra cosa: tagliava l'albero in tre sprite
; impilati e spostava in X la cima e il mezzo. Costava un quinto della memoria
; e a schermo era brutto - tre segmenti rigidi che scorrono uno sull'altro,
; con due scalini nei punti di taglio. Un albero non si spezza in tre.
; Il prezzo e' la chip RAM: 79,1 KB contro i 15,8 di una posa sola. Ci sta
; dentro i 129,7 KB liberati togliendo la vecchia parallasse, con una
; cinquantina di KB di margine.
VENTO_POSE			EQU		5				; disegni per albero
VENTO_CICLO			EQU		16				; passi del ciclo, potenza di 2
VENTO_LENTO			EQU		3				; un passo ogni 8 quadri: il giro
	; dura 16<<3 = 128 quadri, 2,56 s a 50 Hz. E' LA MANOPOLA
	; della velocita': ogni unita' in piu' dimezza. Le fasi
	; degli alberi sono diverse, quindi non vanno all'unisono.
	; VentoCiclo NON percorre le pose a passo costante: e' un
	; seno campionato, cioe' la cadenza di un pendolo - lento
	; agli estremi, svelto in mezzo. Con un ciclo lineare la
	; cima avanza di due pixel a intervalli uguali, e piu' si
	; rallenta piu' quei due pixel si leggono come uno scatto;
	; col seno la posa estrema si ripete tre volte di fila,
	; l'albero sta fermo dove un pendolo sarebbe fermo, e il
	; movimento sta dove l'occhio se lo aspetta.
	IFNE	VENTO_CICLO&(VENTO_CICLO-1)
ERRORE_VENTO_CICLO_NON_POTENZA_DI_DUE	EQU		1/0
	ENDC

; Dove stanno le due word di controllo dentro uno sprite a 64 bit: SPRPOS al
; byte 0, SPRCTL al byte 8 (vedi claude/convenzioni.md). Di SPRPOS si riscrive
; solo il byte BASSO - l'alto e' VSTART, che il generatore ha gia' messo e che
; non cambia mai.
ALBERO_OFS_HSTART	EQU		1				; byte basso di SPRPOS
ALBERO_OFS_CTL		EQU		9				; byte basso di SPRCTL

; STRUMENTI DEL PANNELLO - schermo, spie, quadrante
; Tre strisce a 2 piani con la stessa convenzione: il valore 0 e' TRASPARENTE e
; al montaggio si tiene il pixel del PANNELLO che sta sotto. Serve perche' questi
; tre buchi non stanno sulla griglia dei byte e, a differenza dei riquadri delle
; barre e del punteggio, non basta spostarli:
;   - nelle quattro spie non esiste nessun quadrato 8x8 allineato al byte tutto
;     nero: un cerchio da 13 px ne inscriverebbe uno da 9,2 solo se centrato, e
;     nessuno dei quattro ha il centro dove servirebbe;
;   - nel quadrante il rettangolo nero allineato piu' grande e' 24x28 dentro un
;     buco da 42x37: la lancetta resterebbe un moncone, raggio 10 contro 21.
; MISURE PRESE SUI PIXEL di grafica/Pannello.raw (componenti connesse di indice
; 15), non sulle note in scala 336:
;     schermo    x141..184 y23..44   44x22   rettangolo
;     quadrante  x215..256 y10..46   42x37   cerchio
;     spie       x264..276 e x282..294 y40..48
;                x255..267 e x273..285 y48..58     tredici px di diametro
; A RUNTIME non cambia niente: la cella si scrive con MOVE.B di byte pieni,
; niente maschera, shift o blitter. La composizione con lo sfondo si paga una
; volta sola al boot, in ComponiSheet.
; L'arte la genera tools/genera-strumenti.py, che TAGLIA ogni tinta sulla
; maschera del buco letta da Pannello.raw e conta i pixel fuori: nessuna tinta
; puo' finire sopra la carrozzeria.

; --- le tinte: quali voci di palette usano gli strumenti ------------------
; Schermo e quadrante stanno su righe raster che si sovrappongono a quelle
; della rotella del punteggio, quindi non possono avere voci loro: si prendono
; gli stessi tre grigi. Le spie stanno tutte SOTTO il riquadro basso degli
; indicatori, e da li' in giu' le tre voci degli indicatori non le usa piu'
; nessuno: il copper le ridipinge di giallo (vedi la banda in CopperList).
STRUM_TINTA1		EQU		4			; $334  grigio scuro
STRUM_TINTA2		EQU		5			; $99a  grigio medio
STRUM_TINTA3		EQU		6			; $eee  quasi bianco
SPIA_TINTA1			EQU		2			; le tre voci degli indicatori, che da
SPIA_TINTA2			EQU		13			; SPIA_RASTER in giu' diventano gialle
SPIA_TINTA3			EQU		14
; I gialli non sono misurati su niente: sono scelti qui. Cambiandoli cambia
; solo la banda copper, l'arte non li conosce.
SPIA_COL1			EQU		$0631		; ambra scura
SPIA_COL2			EQU		$0ea2		; ambra
SPIA_COL3			EQU		$0fe6		; giallo vivo

; --- schermo centrale -----------------------------------------------------
; Riga 0 della griglia: gli 8 fotogrammi della neve. Riga 1: le 5 immagini
; degli eventi, per ora segnaposto numerati, e 3 celle libere.
SCHERMO_W			EQU		40			; px dell'arte, che qui e' anche la cella
SCHERMO_H			EQU		16
SCHERMO_NEVE		EQU		8			; colonne usate della riga 0
SCHERMO_IMMAGINI	EQU		5			; colonne usate della riga 1
SCHERMO_COLONNE		EQU		8
SCHERMO_RIGHE		EQU		2
SCHERMO_X			EQU		144			; multiplo di 8, e il blocco 40x16 sta
SCHERMO_Y			EQU		26			; tutto dentro il buco x141..184 y23..44
; Frame che dura un fotogramma. A 1 la neve cambia a ogni quadro. NON metterlo
; a 0: il contatore non scatterebbe mai.
SCHERMO_RITMO		EQU		2
SCHERMO_BYTE_W		EQU		SCHERMO_W/8
SCHERMO_ROWB		EQU		SCHERMO_COLONNE*SCHERMO_BYTE_W
SCHERMO_PLANE_SZ	EQU		SCHERMO_ROWB*SCHERMO_H*SCHERMO_RIGHE
SCHERMO_SHEET_SZ	EQU		SCHERMO_PLANE_SZ*PANNELLO_BITPLANES

; --- spie in basso a destra -----------------------------------------------
; Le RIGHE della griglia sono le quattro spie, non un'animazione: ognuna ha il
; disco a uno scostamento diverso dentro la cella da 2 byte, perche' nessuno
; dei quattro buchi ha il centro su un multiplo di 8. Lo scostamento lo fa lo
; script, cosi' il montaggio non deve spostare bit. Le COLONNE sono
; l'accensione che sfarfalla: la 0 e' spenta, l'ultima e' accesa a regime.
SPIA_W				EQU		16			; px della cella (il disco e' 8)
SPIA_H				EQU		8
SPIA_FASI			EQU		8			; colonne
SPIA_GIALLE			EQU		4			; righe della griglia gialla, una per spia
SPIA_RITMO			EQU		2			; frame per fotogramma dell'accensione
SPIA_BYTE_W			EQU		SPIA_W/8
SPIA_ROWB			EQU		SPIA_FASI*SPIA_BYTE_W
SPIA_PLANE_SZ		EQU		SPIA_ROWB*SPIA_H*SPIA_GIALLE
SPIA_SHEET_SZ		EQU		SPIA_PLANE_SZ*PANNELLO_BITPLANES
; Prima riga di pannello occupata da una spia: da qui in giu' il copper porta
; al giallo le tre voci degli indicatori.
SPIA_Y0				EQU		40
SPIA_RASTER			EQU		PANNELLO_ART_RASTER+SPIA_Y0
	IFLT	SPIA_RASTER-256
; Il WAIT delle spie nella copperlist presuppone la riga OLTRE la 255: usa
; l'arma del V8 e sottrae 256. Se la fascia del pannello si sposta piu' in su,
; quel WAIT va riscritto nella forma normale.
GUARDIA_SPIA_RASTER	EQU		1/0
	ENDC

; --- la quinta spia, ROSSA, nel cerchio sotto la lancetta -----------------
; Stessa arte delle altre quattro - stessi dischi, stesse fasi - ma in un file
; suo, e il motivo non e' la grafica: e' la PALETTE. Sta sulle stesse righe
; delle due spie gialle in basso (y49..56), quindi non puo' usare le loro tre
; voci. Usa i grigi 4/5/6, che da ROSSA_RASTER in giu' il copper porta al rosso:
; li' sotto non li vuole piu' nessuno, il quadrante finisce a y46 e lo schermo
; a y41. Mappa diversa vuol dire descrittore diverso, e un descrittore legge un
; file solo: da qui il secondo .raw.
; Il disco cade a x224..231, che e' allineato al byte ED e' tutto nero: la
; composizione con lo sfondo serve solo per la meta' destra della cella.
ROSSA_RIGHE			EQU		1
ROSSA_TINTA1		EQU		4			; le tre voci della rotella, che da
ROSSA_TINTA2		EQU		5			; ROSSA_RASTER in giu' diventano rosse
ROSSA_TINTA3		EQU		6
ROSSA_COL1			EQU		$0400		; rosso cupo
ROSSA_COL2			EQU		$0b22		; rosso
ROSSA_COL3			EQU		$0f55		; rosso vivo
ROSSA_X				EQU		224			; multiplo di 8
ROSSA_Y				EQU		49
ROSSA_PLANE_SZ		EQU		SPIA_ROWB*SPIA_H*ROSSA_RIGHE
ROSSA_SHEET_SZ		EQU		ROSSA_PLANE_SZ*PANNELLO_BITPLANES
; Prima riga in cui i grigi diventano rossi. Sta DOPO l'ultima riga del
; quadrante (y46) e prima della prima riga della spia rossa (y49).
ROSSA_Y0			EQU		47
ROSSA_RASTER		EQU		PANNELLO_ART_RASTER+ROSSA_Y0
	IFLT	ROSSA_RASTER-256
GUARDIA_ROSSA_RASTER	EQU		1/0
	ENDC
; Quante spie ci sono in tutto: e' il numero di righe di SpieTab, il numero di
; bit utili di SpieAccese e il giro di DisegnaSpie. Non e' un numero a parte.
SPIE_TOT			EQU		SPIA_GIALLE+ROSSA_RIGHE

; --- la lettera nel quadrato all'estrema destra ---------------------------
; Un carattere del font, disegnato solo quando cambia. Il buco e' x282..294
; y23..30 e NON contiene nessun quadrato 8x8 allineato al byte: l'unica
; posizione del glifo tutta nera e' x285..292, che sta a cavallo di due byte.
; Quindi la cella e' larga 2 byte (x280..295) e il glifo ci sta dentro spostato
; di LETTERA_OFS px. Qui lo spostamento lo fa il codice e non uno script,
; perche' il glifo lo si sceglie a runtime.
LETTERA_X			EQU		280			; primo byte della cella (multiplo di 8)
LETTERA_Y			EQU		23
LETTERA_OFS			EQU		5			; px del glifo dentro la cella
LETTERA_TINTA		EQU		6			; $eee: qui i grigi sono ancora grigi
	IFGT	LETTERA_OFS-8
; Il glifo si porta in posizione con una LSL.W: oltre gli 8 px servirebbe un
; verso di scorrimento diverso.
GUARDIA_LETTERA_OFS	EQU		1/0
	ENDC

; --- quadrante grande a destra --------------------------------------------
; La cella e' il buco INTERO, non il rettangolo nero: fuori dal cerchio l'arte
; e' trasparente e il montaggio ci rimette lo sfondo del pannello.
; Le colonne sono i 16 angoli da 22,5 gradi, numerati come una bussola: 0 e'
; nord e si gira in senso orario. Le righe sono la lancetta pulita piu' le tre
; fasi dello sbuffo di vapore.
QUAD_W				EQU		40			; px, cioe' il buco x216..255
QUAD_H				EQU		37			;                   y10..46
QUAD_ANGOLI			EQU		16			; colonne, 360/16 = 22,5 gradi
QUAD_RIGHE			EQU		4			; 0 = pulita, 1..3 = lo sbuffo
QUAD_SBUFFI			EQU		QUAD_RIGHE-1
QUAD_X				EQU		216			; multiplo di 8
QUAD_Y				EQU		10
; Frame per passo di rotazione. Le fasi dello sbuffo entrano una per frame
; dentro il passo, quindi tenerlo uguale a QUAD_SBUFFI le mostra tutte e tre.
QUAD_RITMO			EQU		3
QUAD_BYTE_W			EQU		QUAD_W/8
QUAD_ROWB			EQU		QUAD_ANGOLI*QUAD_BYTE_W
QUAD_PLANE_SZ		EQU		QUAD_ROWB*QUAD_H*QUAD_RIGHE
QUAD_SHEET_SZ		EQU		QUAD_PLANE_SZ*PANNELLO_BITPLANES
; Le quattro posizioni di riposo, come indici di bussola.
QUAD_POS_NORD		EQU		0
QUAD_POS_EST		EQU		4
QUAD_POS_SSE		EQU		7
QUAD_POS_OVEST		EQU		12

	IFNE	(SCHERMO_PLANE_SZ&3)|(SPIA_PLANE_SZ&3)|(QUAD_PLANE_SZ&3)|(ROSSA_PLANE_SZ&3)
; ComponiSheet percorre il piano a long: la sua dimensione deve essere un
; multiplo di 4. Discende dalla griglia, quindi qui si controlla la griglia.
GUARDIA_STRUM_LONG	EQU		1/0
	ENDC

