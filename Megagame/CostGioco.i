; CostGioco.i - Costanti: pietra, player, fisica, tasti, luce, falo', suoni
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

; pietra.i - generato da png2amiga.py
; ATTENZIONE: PIETRA_PLANE_SIZE generato dallo script valeva 4096, che sono i
; BIT di un piano (512 byte x 8), non i byte. Il file vero e' 2560 byte =
; 5 piani x 512, quindi il valore corretto e' 512. Lasciarlo a 4096 faceva
; avanzare il puntatore di piano di 8 volte troppo e leggere fuori dal file.
; VERIFICATO decodificando Pietra.raw: 256x16 px, 5 bitplane contigui,
; 8 frame da 32 px di slot, arte nei primi 16 px di ogni slot, padding
; destro completamente vuoto (stessa convenzione di Omino32/Nemico32),
; UNA sola banda (nessuna direzione), indici di palette usati 24/25/27
; (grigi $0777/$0888/$0aaa della rampa 20-31 in Tiles.cop).
; --- Descrizione dell'ASSET: e' da qui che InitPietra riempie la struct ---
; L'arte occupa i primi 16 px dello slot; il resto e' lo stacco che serve
; allo shift orizzontale, esattamente come per BOB_W nello sheet dell'omino.
; PIETRA_H e l'altezza del FOTOGRAMMA: coincide con l'altezza del file solo
; perche' lo sheet ha una banda sola, e questo e' un caso, non una regola.
PIETRA_W			EQU		16				; larghezza arte (px)
PIETRA_H			EQU		16				; altezza arte (px)
PIETRA_FRAMES		EQU		8				; frame di animazione (potenza di 2)
PIETRA_BANDE		EQU		1				; una sola banda: nessuna direzione

; Le misure REALI del file non sono numeri da tenere allineati a mano con
; l'asset: DISCENDONO dall'asset. Una riga di sheet porta un frame per ogni
; fotogramma e un frame occupa (larghezza/16+1) word, perche' la word in piu'
; e' lo stacco su cui si spalma lo shift. L'altezza e' una banda per ogni
; direzione. Prima erano dichiarate a parte e una guardia verificava che le
; due strade si incontrassero; adesso la strada e' una.
PIETRA_SHEET_W        EQU     (PIETRA_W/16+1)*2*PIETRA_FRAMES*8	; px, larghezza del file
PIETRA_SHEET_H        EQU     PIETRA_H*PIETRA_BANDE				; righe del file
PIETRA_BYTES_PER_ROW  EQU     PIETRA_SHEET_W/8			; 32 byte per riga
PIETRA_PLANE_SIZE     EQU     PIETRA_BYTES_PER_ROW*PIETRA_SHEET_H	; 512 byte/piano

; MAPPA_COLS / MAPPA_ROWS sono definite PIU' SU (prima di SFONDO_PITCH, che
; ora ne discende). Qui restano solo le costanti che dipendono da loro.
BUFFER_COLS			EQU		MAPPA_COLS		; Path B: il buffer contiene TUTTA la mappa
; Finestra orizzontale di display. I VALORI VERI, letti dalle EQU e non da
; questo commento: DIW_H_START $81 = 129, DIW_H_STOP $C1, DIW_WIDTH 320 px,
; VIS_COLS 20. Se qui sotto leggi altri numeri, e' questo commento a essere
; vecchio: li stampa tools/valori.py, che valuta anche i rami condizionali.
; IL VINCOLO A SINISTRA: quando la finestra apre, il dato del primo pixel deve
; essere gia' arrivato. Arriva a DDFSTRT*2 + LATENZA + D, con D il ritardo
; BPLCON1, che copre 0..SCROLL_BLOCCO_PX-1. Nella configurazione di oggi
; (prelievo a 16 bit) DDFSTRT vale 96 px e D arriva a 15, quindi con la
; finestra a 129 la latenza di pipeline ha 18 px di spazio.
; ATTENZIONE: la LATENZA di 48 px misurata col monitor apparteneva alla
; configurazione a 64 bit, dove il prelievo e' largo un blocco intero e la
; pipeline e' piu' lunga. NON e' un numero valido qui, e per il prelievo a 16
; bit una misura non c'e': quello che si sa e' che a schermo funziona.
; IL VINCOLO A DESTRA: la finestra deve stare dentro il dato prelevato, cioe'
; DDFSTRT*2 + SCROLL_FETCHES*SCROLL_BLOCCO_PX.
; SINTOMO da riconoscere: px vuoti sul bordo sinistro che compaiono solo a
; ritardo BPLCON1 grande, cioe' in certe posizioni di camera e non in altre.

; FINESTRA ORIZZONTALE. Valori trovati SUL FERRO, non da un modello: sono gli
; stessi della schermata del titolo, e con BRDRBLNK acceso danno bordi neri
; stretti e nessuna colonna sporca a sinistra all'innesco dello scroll.
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
; DERIVATA dalla finestra, non piu' cablata: e' la larghezza visibile in tile.
; Non dice quanto si DISEGNA (il mondo e' disegnato tutto e il fetch porta 448
; px per riga): dice alla logica quanto si VEDE, e da qui dipendono TILEXMAX,
; CENTER_X e il cull dei BOB. Se non combacia con la finestra vera, la camera
; scorre oltre il bordo mappa e il cull sbaglia.
VIS_COLS			EQU		(DIW_H_STOP+256-DIW_H_START)/16

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
; Storia dei valori: si era partiti da -8 interi (apice 28 px, poco piu' di una
; tile), poi -14 (91 px). Poi -1792 (7,0 px/quadro), e dal 24 settembre 2026
; -1920 (7,5) per un salto piu' alto e un po' piu' lungo.
;
; LA TARATURA NON SI FA CON LA FORMULA. `apice = v^2/(2g)` e' il caso continuo e
; qui SBAGLIA: a 1792 da' 73 px mentre il salto vero ne fa 77, perche' la somma
; discreta dei passi non e' l'integrale. I numeri qui sotto vengono da una
; simulazione con la STESSA aritmetica del 68000 - word, 8.8, `ASR.W #8` che
; arrotonda verso il basso anche sui negativi - sullo stesso codice di
; AggiornaFisicaPlayer. Il commento vecchio diceva "70 px in 21 frame": era la
; formula, non il salto.
;
;   g    v      px/qd |  apice        salita  volo  |  lunghezza (1 px/qd)
;   86  1792    7,00  |  77 px (4,8 t)  20 qd  43 qd |  43 px (2,7 tile)  <- prima
;   86  1856    7,25  |  82 px (5,1 t)  20 qd  45 qd |  45 px (2,8 tile)
;   86  1920    7,50  |  88 px (5,5 t)  22 qd  46 qd |  46 px (2,9 tile)  <- ADESSO
;   86  1984    7,75  |  94 px (5,9 t)  23 qd  48 qd |  48 px (3,0 tile)
;   86  2048    8,00  | 100 px (6,2 t)  23 qd  49 qd |  49 px (3,1 tile)
;   80  1792    7,00  |  82 px (5,1 t)  21 qd  46 qd |  46 px (2,9 tile)
;   80  1920    7,50  |  94 px (5,9 t)  23 qd  49 qd |  49 px (3,1 tile)
;   72  1792    7,00  |  91 px (5,7 t)  24 qd  51 qd |  51 px (3,2 tile)
;
; **LUNGHEZZA E ALTEZZA NON SONO INDIPENDENTI**, e va saputo prima di chiedere
; un salto "piu' lungo ma non piu' alto": la lunghezza e' il TEMPO DI VOLO per
; la velocita' orizzontale, e con questi due soli parametri l'apice cresce come
; v^2 mentre il volo cresce come v. Allungare di poco vuol dire alzare di
; parecchio. L'unico modo di appiattire l'arco e' una terza manopola che qui
; non c'e': una velocita' orizzontale IN ARIA diversa da quella a terra
; (oggi sono la stessa cosa, `bob_Speed` = 1 px/quadro).
GRAVITA_88		EQU		80		; 0,312 px/quadro^2 in 8.8
MAX_FALL_88		EQU		8*256	; 8 px/quadro di caduta massima (invariata)
JUMP_VEL_88		EQU		-1920	; 7,5 px/quadro verso l'alto (negativa = su)
; PRIMO TETTO: il movimento verticale si applica in UN passo solo, e
; IsBoxBlocked sonda la posizione di ARRIVO. Uno spostamento di 16 px o piu'
; scavalca un soffitto o un pavimento spesso una tile senza vederlo. Vale per
; la salita e per la caduta, quindi la guardia e' doppia.
	IFGT	(-JUMP_VEL_88)-15*256
GUARDIA_SALTO_TUNNEL	EQU		1/0
	ENDC
	IFGT	MAX_FALL_88-15*256
GUARDIA_CADUTA_TUNNEL	EQU		1/0
	ENDC
CAM_STEP_Y		EQU		8		; passo scroll verticale camera (px/frame, DEVE dividere 16: 1/2/4/8)
CAM_DEADZONE_Y	EQU		8		; tolleranza verticale camera (>= CAM_STEP_Y per evitare oscillazione)
; SECONDO TETTO DEL SALTO, e sta QUI e non accanto a JUMP_VEL_88 perche' Devpac
; valuta una IFxx dove la incontra e CAM_STEP_Y e' definita due righe sopra.
; La camera insegue a CAM_STEP_Y px per quadro: se il player sale piu' in fretta
; le scappa, si arrampica verso il bordo alto dello schermo e a -BOB_H
; DisegnaBOB lo culla, cioe' sparisce a meta' salto. Oggi 7,5 contro 8: il
; margine e' mezzo pixel per quadro, quindi alzando ancora il salto va alzato
; anche il passo della camera.
	IFGT	(-JUMP_VEL_88)-CAM_STEP_Y*256
GUARDIA_SALTO_CAMERA	EQU		1/0
	ENDC

; Costanti tasti freccia (identici ai rawkey Intuition)
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
RAWKEY_6			EQU 	$06			; rawkey del tasto 6 (scroll automatico del profilo)
RAWKEY_Q			EQU 	$10			; rawkey del tasto Q (posizione della lancetta)
RAWKEY_S			EQU 	$21			; rawkey del tasto S (cosa mostra lo schermo)
RAWKEY_L			EQU 	$28			; rawkey del tasto L (quante spie accese)
RAWKEY_A			EQU 	$20			; rawkey del tasto A (lettera nel quadrato)

KEY_RELEASE_BIT 	EQU 	7	   		; bit 7 del keycode decodificato
; Passo di animazione di DEFAULT, copiato in bob_AnimDelay dalle Init. Non e'
; piu' la legge per tutti: ogni bob puo' avere il suo.
ANIM_DELAY			EQU 	3
; Terza posizione di bob_IsMoving: il fotogramma lo decide il proprietario
; del bob e DisegnaBOB non lo tocca. Vedi il blocco Animazione in DisegnaBOB.
ANIM_ESTERNA	EQU		-1

; ----- Bullet (proiettile sprite hardware) -----
BULLET_COOLDOWNC	EQU		10			; frame di cooldown tra due spari

; ----- PARABOLA DELLA PIETRA -----
; La pietra e' LANCIATA a 30 gradi, non sparata. Le velocita' sono in VIRGOLA
; FISSA 8.8 (256 = un pixel per quadro) perche' a 30 gradi servono 4,57 px/quadro
; in verticale contro 7,91 in orizzontale: coi soli interi 5 e 8 l'angolo
; diventerebbe 32 gradi e la gittata sbaglierebbe.
; I conti, per rifarli se cambia la gittata:
;   T = 2*vy/g          R = vx*T = 2*vx*vy/g          vy = vx*tan(30)
; TARATURA, il dettaglio che sballa i conti: la pietra NON parte da terra, parte
; dal CENTRO del player, quindi per toccare il suolo deve scendere anche i 16 px
; che la separano dai piedi. La formula da' la gittata da pari a pari e
; sottostima quella vera: i valori qui sotto sono tarati sul volo COMPLETO.
; FORMA: a 30 gradi l'apice sta a circa un settimo della gittata, qui 32 px su
; 256. E' un lancio TESO: allungare la gittata alza l'apice in proporzione ma
; non cambia la forma. Per una campana serve alzare l'ANGOLO.
PIETRA_RAGGIO		EQU		16*16		; 16 word = 256 px di gittata massima
PIETRA_GRAVITA		EQU		42			; 0,164 px/frame^2 in 8.8
PIETRA_VEL_X		EQU		1456		; 5,69 px/frame in 8.8
PIETRA_VEL_Y		EQU		841			; 3,29 px/frame in 8.8, verso l'ALTO
; verifica dell'angolo: vy/vx = 841/1456 = 0,5776 contro tan(30) = 0,5774,
; cioe' 30,01 gradi. Simulato con la stessa aritmetica intera del 68000:
; apice 32 px, suolo (16 px sotto il lancio) al frame 44 a 250 px, tetto della
; gittata piu' in la'. E' la tile a fermarla, come deve essere.
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
RAGGIO_LUCE			EQU		64			; raggio in pixel della luce (vedi TILE_LUCE)

; ----- Tile SEGNAPOSTO: marcano un punto, non disegnano niente -----
; Lo slot nel foglio resta VUOTO apposta, cosi' nel gioco non si vede niente:
; a leggerle e' il codice, non il display. Vanno da 64 in su perche' da 43 a 63
; TileFlags le dichiara tutte bloccate, e un segnaposto si calpesta.
; Chi ne aggiunge una allunghi TileFlags e la metta qui: tools/mappa.py legge
; OGNI EQU TILE_*, quindi da quel momento si puo' scrivere per nome nella
; mappa (nel .txt "VIA" e "TILE_VIA" valgono tutti e due 64).
TILE_VIA			EQU		64			; dove parte il player (vedi TrovaPartenza)

; Maschera statica del disco di luce per il blit del cerchio (vedi
; BuildLightMask / DisegnaCerchioLuceBlitter). Larga 8 word (128px) + 1 word
; di "spillover" per lo shift orizzontale = 9 word. Alta 128 righe (dy -64..63).
; Bit=1 dentro il cerchio. Costruita una volta al boot riusando LightHalfWidthTable.
LIGHT_MASK_W		EQU		9			; word per riga (8 disco + 1 per lo shift)
LIGHT_MASK_H		EQU		128			; righe
LIGHT_MASK_BANDA	EQU		LIGHT_MASK_W*2	; 18 byte per riga

; Limiti del buffer darkplane, che in Path B e' grande come la mappa e non
; come lo schermo. Stanno QUI e non fra le EQU dello sfondo perche'
; DARK_MAX_WORDX ha bisogno di LIGHT_MASK_W (due righe sopra) e DARK_MAX_ROWS
; di SFONDO_HEIGHT: Devpac non accetta riferimenti in avanti in una EQU.
; Limiti del buffer darkplane, che in Path B e' grande come la mappa e
; non come lo schermo. Erano 11 e 256 scritti a mano.
; I limiti sono relativi a CurrentDarkDraw, che punta gia' oltre la guardia
; (PathBDarkPlane + DELTA_MAPPAVERA + BG_ORIGIN_OFS): la riga utile e' quindi
; lunga AUX_PITCH-DELTA_MAPPAVERA-BG_ORIGIN_X byte, non AUX_PITCH.
; Ultima word in cui la maschera (LIGHT_MASK_W word) ci sta per intero.
; Prima era calcolata su AUX_PITCH intero e ignorava la guardia: con la
; sorgente di luce all'estremo destro il blit sarebbe finito 6 byte dentro
; la riga successiva. Nella mappa attuale il caso non si presenta.
DARK_ROW_BYTES		EQU		AUX_PITCH-DELTA_MAPPAVERA-BG_ORIGIN_X
DARK_MAX_WORDX		EQU		(DARK_ROW_BYTES/2)-LIGHT_MASK_W
DARK_MAX_X			EQU		DARK_ROW_BYTES*8-1
DARK_MAX_ROWS		EQU		SFONDO_HEIGHT

; DARK_PAD_ROWS e DARK_ROWS stavano qui: righe di padding sotto le 256 visibili
; del dark plane, contro l'over-fetch in fondo. Servivano solo a dimensionare
; PathBVuoto, che non c'e' piu'. Il darkplane vero e' alto SFONDO_HEIGHT (368
; righe) come i piani del mondo, quindi quel margine ce l'ha gia'.

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
; PAR_PLANE_BANDA (la banda fra i due piani della parallasse) e' sparita col
; suo unico cliente, i buffer PARALLASSE_A/B.

; Numero di righe in fondo allo schermo da NON disegnare (border invisibile).
; STORIA: era un cerotto (=12) contro lo sfarfallio AGA sulle ultime ~12
; scanline. Causa vera individuata: il fill del dark plane su CPU (~2.5ms di
; MOVE.L) ritardava i blit dei BOB, che finivano mentre il pennello era gia'
; sul fondo schermo -> contesa DMA blitter/bitplane -> sfarfallio. Spostato il
; fill sul blitter (vedi UpdateDarkPlane STEP 1), tutto finisce ~2ms prima e
; la contesa sparisce. Quindi ora dovrebbe bastare 0 (schermo pieno 256 righe).
; >>> Se reimpostando 0 lo sfarfallio NON torna, lascialo a 0 (recuperi 12px).
; >>> Se dovesse tornare un filo, alza al minimo che lo elimina (prova 4, 8...).
; Muove insieme: BLTSIZE in CopiaVideo, cull cerchio in DisegnaCerchioLuce,
; DIWSTOP nella copperlist di gioco, e l'altezza di SFONDOGRANDE.
; >>> L'EQU e' DEFINITA IN TESTA AL FILE (blocco "ALTEZZA DI SFONDOGRANDE"),
; >>> perche' BUFFER_ROWS/SFONDO_HEIGHT/SFONDO_PLANE_SIZE derivano da lei e
; >>> vanno risolte prima. Qui resta solo la documentazione del perche'.

; FALO' - striscia 512x16 a 2 piani, da grafica/falo_16x16_3col.raw
; L'arte e' 16 frame di 16x16, ma nella striscia ogni frame occupa 32 px:
; i 16 di destra sono vuoti. Il .raw e' la conversione DIRETTA del PNG
; (verificata pixel per pixel), quindi ha il layout dell'immagine e non
; quello dello sprite:
;   - i piani sono SEPARATI: prima tutto il piano 0, poi tutto il piano 1
;   - una riga e' larga quanto la STRISCIA (64 byte), non quanto un frame
; Lo sprite hardware vuole l'opposto: per ogni riga una word di piano 0 e
; una di piano 1, di seguito. La conversione la fa BuildFaloSheet al boot,
; cosi' la fonte di verita' resta il file che esce dal tuo editor: ridisegni
; il PNG, riesporti il .raw, e non c'e' nessun passo intermedio da ricordare.
FALO_FRAMES			EQU		16
FALO_W				EQU		16			; pixel davvero usati per frame
FALO_H				EQU		16
FALO_PIANI			EQU		2

; La cella di un frame nella striscia NON e' un numero a parte: e' lo slot che
; DisegnaBOB si aspetta. Per un'arte da 16 px lo slot e' 2 word, cioe' 32 px:
; 16 di arte e 16 di stacco, che e' dove si spalma lo shift orizzontale. Il
; PNG e' esportato cosi', e derivandolo qui il pitch della striscia e quello
; che DisegnaBOB calcola a runtime non possono piu' divergere. Prima erano due
; strade separate con una guardia in mezzo.
FALO_BLITW			EQU		FALO_W/16+1		; word per riga che il blit legge
FALO_SLOT			EQU		FALO_BLITW*2	; byte di uno slot (arte + stacco)
FALO_CELL_W			EQU		FALO_SLOT*8		; passo orizzontale di un frame (px)
FALO_STRIP_W		EQU		FALO_CELL_W*FALO_FRAMES
FALO_ROWB			EQU		FALO_STRIP_W/8	; byte per riga PER PIANO
FALO_PLANE_SZ		EQU		FALO_ROWB*FALO_H	; distanza fra piano 0 e piano 1
FALO_CELL_B			EQU		FALO_CELL_W/8	; byte di un frame dentro una riga

; Due vincoli del codice, non del formato, quindi non c'e' niente da derivare:
; BuildFaloSheet copia UNA word per riga e per piano, quindi l'arte deve essere
; larga 16 px; e DisegnaBOB fa il wrap del fotogramma con un AND, quindi
; FALO_FRAMES deve essere una potenza di due. Se cambi l'arte, cambia anche il
; codice che la legge.

; ---- I colori: tre voci di palette prese fra quelle LIBERE ----
; Misurato sull'arte a 5 piani che esiste (Tiles, Omino32, Nemico32, Pietra):
; gli indici 9-15, 21-23, 26 e 28-31 non compaiono in NESSUN pixel. Il falo'
; si prende 13, 14, 15, che erano tre viola mai usati.
; La scelta di 12 come base non e' estetica, e' quello che rende la
; conversione quasi gratis: l'indice vale 12+v, cioe' in binario %011vv, e
; quindi il piano 0 e il piano 1 dello sheet sono COPIE dei due piani
; dell'arte, i piani 2 e 3 sono la sagoma (piano0 OR piano1) e il piano 4 e'
; sempre spento. Nessuna mappa di colori da percorrere pixel per pixel.
FALO_PAL_BASE		EQU		12
; Colori a 24 bit, uguali a quelli del PNG. La palette del gioco e' scritta
; in due blocchi copper (nibble alti e bassi): le due word si derivano da qui,
; cosi' il colore compare UNA volta sola nel sorgente.
FALO_C1_RGB			EQU		$fff7c2		; nucleo chiaro   -> indice 13
FALO_C2_RGB			EQU		$ffb347		; mezzatinta      -> indice 14
FALO_C3_RGB			EQU		$b23a1a		; bordo scuro     -> indice 15
; nibble alti e bassi, derivati: il colore non va ricopiato a mano in due posti
FALO_C1_HI	EQU	((((FALO_C1_RGB>>20)&15)<<8)|(((FALO_C1_RGB>>12)&15)<<4)|((FALO_C1_RGB>>4)&15))
FALO_C1_LO	EQU	((((FALO_C1_RGB>>16)&15)<<8)|(((FALO_C1_RGB>>8)&15)<<4)|(FALO_C1_RGB&15))
FALO_C2_HI	EQU	((((FALO_C2_RGB>>20)&15)<<8)|(((FALO_C2_RGB>>12)&15)<<4)|((FALO_C2_RGB>>4)&15))
FALO_C2_LO	EQU	((((FALO_C2_RGB>>16)&15)<<8)|(((FALO_C2_RGB>>8)&15)<<4)|(FALO_C2_RGB&15))
FALO_C3_HI	EQU	((((FALO_C3_RGB>>20)&15)<<8)|(((FALO_C3_RGB>>12)&15)<<4)|((FALO_C3_RGB>>4)&15))
FALO_C3_LO	EQU	((((FALO_C3_RGB>>16)&15)<<8)|(((FALO_C3_RGB>>8)&15)<<4)|(FALO_C3_RGB&15))

; ORDINE DEI FRAME: nel file il frame 1 e' la fiamma piena e il 16 la brace.
; L'animazione li percorre quindi A RITROSO: parte dalla brace e sale, che e'
; l'accensione, poi cicla sui frame di regime. I numeri qui sono quelli
; dell'arte (1..FALO_FRAMES), non gli indici interni.
FALO_INTRO_PRIMO	EQU		16			; da dove parte l'accensione
FALO_LOOP_PRIMO		EQU		10			; da dove riparte il ciclo, per sempre
; Entrambi vanno tenuti in 1..FALO_FRAMES: sono numeri dell'arte.
; indici interni, 0-based
FALO_INTRO_IDX		EQU		FALO_INTRO_PRIMO-1
FALO_LOOP_IDX		EQU		FALO_LOOP_PRIMO-1

; La POSIZIONE del falo' non e' una EQU: viene dalla mappa. La mette TrovaFalo
; cercando TILE_LUCE, che e' la stessa tile su cui PathBBuildDark accende il
; cerchio di luce. Prima erano due cose scollegate - la luce dalla mappa, il
; fuoco da due numeri cablati - e bastava spostare la tile per vedere il
; cerchio da una parte e il falo' dall'altra.

FaloAnimSpeed		EQU		5			; ogni N frame avanza animazione
ENEMY_COUNT			EQU		4			; numero massimo di nemici
; Quanti bob percorre il ciclo di disegno: i nemici, il player, la pietra.
; Vive qui e non nella SECTION Entities perche' le EQU vanno definite prima
; dell'uso, e DisegnaBOBs sta molto piu' su nel file.
BOB_TOTALI			EQU		ENEMY_COUNT+3	; nemici + player + pietra + falo'

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
