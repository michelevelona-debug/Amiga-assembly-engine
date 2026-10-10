; CostTitolo.i - Costanti: schermata del titolo e droide
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


; TITLE SCREEN - misure del file grafica/title.raw
; Stavano in title.i, generato da png2amiga.py, ed e' stato tolto: di otto
; EQU ne serviva UNA (TITLE_PLANE_SIZE), i valori erano letterali invece che
; derivati (la stessa forma che su Pietra e' arrivata sbagliata dal
; convertitore, bit invece di byte), e meta' file era un esempio d'uso che
; non corrisponde al codice. Ora seguono il pattern degli altri asset:
; si dichiarano le misure VERE del file e il resto si deriva.
; VINCOLO: title.raw deve essere TITLE_PLANE_SIZE*TITLE_PIANI byte. Qui il
; numero di piani e la geometria sono dichiarati, il file no: se lo riesporti
; diverso, ShowTitle legge oltre la fine e nessuno se ne accorge.
TITLE_W				EQU		320				; px, larghezza del file
TITLE_H				EQU		256				; righe del file
TITLE_PIANI			EQU		8				; bitplane, layout SEQUENTIAL
TITLE_BYTES_PER_ROW	EQU		TITLE_W/8
TITLE_PLANE_SIZE	EQU		TITLE_BYTES_PER_ROW*TITLE_H	; byte per bitplane

; PROVA A COSTANTI NOTE sui piani della title. Riempie title_bpl con valori
; noti PRIMA di mostrarlo, cosi' si separa "percorso di display rotto" da
; "contenuto o palette sbagliati". Da rimettere a 0 quando hai finito.
;   0 = normale, si vede l'arte
;   1 = tutti i piani a ZERO      -> schermo piatto del colore 0
;   2 = solo il piano 0 acceso    -> schermo piatto del colore 1
;   3 = una banda per piano       -> 8 bande da 32 righe, indici 1,2,4..128
TITLE_TEST_FILL		EQU		0

; ============================================================================
; IL DROIDE CHE FLUTTUA SOPRA L'ARMATURA
;
; Un BOB a 8 piani disegnato dentro la schermata del titolo. Le cinque pose
; fanno pulsare i due getti di reazione e lampeggiare le due luci rosse.
;
; PERCHE' UN BOB E NON UNO SPRITE, che sarebbe stato piu' semplice: il titolo
; usa TUTTE E 256 le voci di palette (contate sui pixel di title.raw, non sulla
; palette). Uno sprite attaccato pretende un blocco allineato di 16 voci tutto
; suo, e per averlo bisognerebbe sovrascrivere 16 colori del titolo, cioe'
; guastare l'immagine. Un BOB si disegna dentro gli stessi otto piani e usa i
; colori che il titolo ha GIA': costa zero voci.
;
; LA GEOMETRIA E' QUELLA DI DisegnaBOB, non una nuova: slot da (larghezza/16+1)
; word - il +1 e' lo sconfinamento dello shift - fotogrammi affiancati, piani
; contigui. La scrive tools/genera-droide.py, che stampa questi stessi numeri.
;
; LA MASCHERA E' UN FILE, non l'OR dei piani. BuildBobMask ricava la maschera
; dai piani, e quel trucco impone che nessun pixel dell'arte valga 0. La voce 0
; di title.pal e' $f2f9fb, il bianco piu' acceso che il titolo possiede:
; escluderlo vorrebbe dire rinunciarci proprio sui riflessi e sul nucleo della
; fiamma. Con la maschera scritta a parte l'indice 0 torna disponibile e un
; buco per distrazione non puo' capitare. Costa 720 byte.
DROIDE_LARGH		EQU		32
DROIDE_ALT			EQU		24				; il disegno e' 1,34:1, non quadrato
DROIDE_POSE			EQU		5
DROIDE_PIANI		EQU		TITLE_PIANI		; sta dentro i piani del titolo
DROIDE_SLOT_W		EQU		DROIDE_LARGH/16+1	; 3 word: due di arte, una per lo shift
DROIDE_SLOT			EQU		DROIDE_SLOT_W*2		; byte per cella
DROIDE_PITCH		EQU		DROIDE_SLOT*DROIDE_POSE		; byte per riga dello sheet
DROIDE_PIANO		EQU		DROIDE_PITCH*DROIDE_ALT		; byte per piano
DROIDE_LEN_ATTESA	EQU		DROIDE_PIANO*DROIDE_PIANI	; guardia sul .raw
DROIDE_MASK_ATTESA	EQU		DROIDE_PIANO				; la maschera e' 1 piano
; BLTSIZE e i moduli, derivati come fa DisegnaBOB
DROIDE_BLTSIZE		EQU		(DROIDE_ALT<<6)|DROIDE_SLOT_W
DROIDE_MOD_ARTE		EQU		DROIDE_PITCH-DROIDE_SLOT		; salto nello sheet
DROIDE_MOD_DEST		EQU		TITLE_BYTES_PER_ROW-DROIDE_SLOT	; salto nel titolo

; DOVE FLUTTUA. L'armatura sta al centro, x 145..172 y 155..215; il logo
; finisce verso y 120. Il droide vive in quei 35 righe di mezzo: HOME e'
; l'angolo in alto a sinistra a meta' corsa, e le ampiezze sono scelte perche'
; il fondo del droide (Y+DROIDE_ALT) resti sopra la testa dell'armatura anche
; nel punto piu' basso dell'oscillazione.
DROIDE_HOME_X		EQU		142				; centro 158 = centro dell'armatura
DROIDE_HOME_Y		EQU		124
DROIDE_AMPI_X		EQU		10
DROIDE_AMPI_Y		EQU		5
; Il percorso e' un otto: la stessa tabella di seno letta a due velocita'
; diverse. Con PASSO 3 e gli scorrimenti qui sotto, la Y compie un giro in
; ~3,4 s e la X in ~6,8 s: fluttua, non oscilla.
DROIDE_FASE_PASSO	EQU		3
DROIDE_FASE_SH_Y	EQU		3
DROIDE_FASE_SH_X	EQU		4
SENO_VOCI			EQU		64				; voci della tabella, potenza di 2
SENO_SCALA			EQU		8				; il valore e' seno*256 -> ASR #8
; Quanti quadri dura una posa. Cinque pose a 6 quadri fanno un giro in mezzo
; secondo: piu' veloce diventa nervoso, piu' lento sembra un semaforo.
DROIDE_RITMO		EQU		6
