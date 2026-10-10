; AssetCPU.i - Asset letti solo dalla CPU
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


	cnop	0,4
; Palette AGA del title screen (256 colori, formato $00RRGGBB long).
; Caricata via CPU in LoadAGAPalette256 prima di mostrare la title.
title_pal:
	incbin	"grafica/title.pal"

; ---- Le due tabelle dell'alba. Qui e non in chip: le legge SOLO la CPU. ----
; Il copper legge il blocco AlbaCopper, che sta in ChipStuff; queste sono la
; sorgente da cui la CPU lo riempie, e nessun DMA le tocca mai.
	cnop	0,4
; Per ogni voce, ALBA_LIVELLI colori gia' impacchettati nelle DUE word che il
; copper scrive su un COLORxx: prima i nibble alti, poi i bassi. Impacchettarli
; qui invece che a runtime e' quello che riduce il lavoro per voce a due MOVE.
AlbaRampe:
	incbin	"grafica/alba_rampe.raw"
AlbaRampeFine:
	IFNE	(AlbaRampeFine-AlbaRampe)-ALBA_RAMPE_ATTESA
ERRORE_ALBA_RAMPE_TAGLIA_DIVERSA	EQU		1/0
	ENDC

	cnop	0,2
; Per ogni voce, il quadro in cui comincia la sua rampa. Le voci piu' luminose
; partono per prime, ed e' cosi' che la luce CRESCE invece di accendersi tutta
; insieme. Il ritardo segue la luminosita' e non la posizione apposta: il
; dithering mescola voci vicine di COLORE, quindi voci che si mescolano devono
; essere vicine di FASE, se no la mescolanza sfarfalla.
AlbaInizio:
	incbin	"grafica/alba_inizio.raw"
AlbaInizioFine:
	IFNE	(AlbaInizioFine-AlbaInizio)-ALBA_INIZIO_ATTESA
ERRORE_ALBA_INIZIO_TAGLIA_DIVERSA	EQU		1/0
	ENDC

	cnop	0,4
; Striscia dell'arte del falo', COSI' COME ESCE DALL'EDITOR: 512x16, 2 piani
; separati (1024 byte l'uno). BuildFaloSheet la espande a 5 piani al boot.
falo_strip:
	incbin	"grafica/falo_16x16_3col.raw"
falo_strip_fine:

	cnop	0,4
; Striscia della rotella, COSI' COME ESCE DALL'EDITOR: 640x16, 2 piani
; separati (1280 byte l'uno). BuildRotellaSheet la espande a 4 piani al boot.
; Si chiama rotella_strip e NON punteggio: "Punteggio" e' la variabile del
; conteggio, e due simboli che differiscono solo per una maiuscola sono una
; trappola - per l'assemblatore se gira con -nocase, e per chi legge sempre.
rotella_strip:
	incbin	"grafica/rotella_punteggio.raw"

	cnop	0,4
; Striscia dei due indicatori di sinistra, COSI' COME ESCE DALL'EDITOR:
; 432x88, 2 piani separati (4752 byte l'uno). BuildIndicSheet la espande a 4
; piani al boot. La versione con lo stacco fra i fotogrammi (indicatore_sep)
; NON serve: lo stacco esiste per lo shift del blitter, e qui la barra cade su
; byte interi e la scrive la CPU.
indicatore_strip:
	incbin	"grafica/indicatore.raw"

; Le tre strisce degli strumenti, COSI' COME LE SCRIVE tools/genera-strumenti.py.
; Valore 0 = trasparente: ComponiSheet ci mette sotto lo sfondo del pannello.
; Le guardie confrontano la dimensione VERA del file con quella che discende
; dalla griglia: e' l'unico modo di accorgersi di una ri-generazione con misure
; diverse, che se no si leggerebbe oltre la fine senza un errore.
	cnop	0,4
schermo_strip:
	incbin	"grafica/schermo.raw"
schermo_strip_fine:
	IFNE	(schermo_strip_fine-schermo_strip)-SCHERMO_PLANE_SZ*2
GUARDIA_SCHERMO_RAW	EQU		1/0
	ENDC

	cnop	0,4
spia_strip:
	incbin	"grafica/spia.raw"
spia_strip_fine:
	IFNE	(spia_strip_fine-spia_strip)-SPIA_PLANE_SZ*2
GUARDIA_SPIA_RAW	EQU		1/0
	ENDC

	cnop	0,4
spia_rossa_strip:
	incbin	"grafica/spia_rossa.raw"
spia_rossa_strip_fine:
	IFNE	(spia_rossa_strip_fine-spia_rossa_strip)-ROSSA_PLANE_SZ*2
GUARDIA_SPIA_ROSSA_RAW	EQU		1/0
	ENDC

	cnop	0,4
quadrante_strip:
	incbin	"grafica/quadrante.raw"
quadrante_strip_fine:
	IFNE	(quadrante_strip_fine-quadrante_strip)-QUAD_PLANE_SZ*2
GUARDIA_QUADRANTE_RAW	EQU		1/0
	ENDC
