; ============================================================================
; Mappe.i - GENERATO da tools/mappe.py, NON si modifica a mano.
; La fonte e' risorse/mappe.txt. Per cambiare un collegamento si tocca quello e
; si rilancia `py tools\mappe.py`: qui dentro una modifica a mano sopravvive
; fino alla prossima generazione e poi sparisce senza dire niente.
;
; I quattro versi seguono le EQU VERSO_* di Gioco.s, in quest'ordine:
;   sinistra, destra, sopra, sotto
; Un -1 vuol dire "quel bordo e' un muro".
;
; LA RECIPROCITA' E' STATA CONTROLLATA da chi ha generato questo file: per ogni
; collegamento A -> B esiste il ritorno B -> A sul verso opposto. Non e' un
; invariante che l'assemblatore possa verificare, ed e' il motivo per cui
; questa tabella non si scrive a mano.
;
; I FOGLI DI TILE dichiarati nella fonte, nell'ordine (l'indice e' la
; posizione): 0=Tiles1, 1=Tiles2
; Ogni foglio vuole la sua TileFlags in Variabili.i, e la guardia
; GUARDIA_TAB_FOGLIO_FLAGS confronta il conto con FOGLI_N.
; ============================================================================

	cnop	0,2
MAPPA1:
	incbin	"grafica/mappa1.raw"
MAPPA1_FINE:
	IFNE	(MAPPA1_FINE-MAPPA1)-MAPPA_ATTESA
GUARDIA_MAPPA1_RAW	EQU		1/0
	ENDC
	cnop	0,2
MAPPA2:
	incbin	"grafica/mappa2.raw"
MAPPA2_FINE:
	IFNE	(MAPPA2_FINE-MAPPA2)-MAPPA_ATTESA
GUARDIA_MAPPA2_RAW	EQU		1/0
	ENDC
	cnop	0,2
MAPPA3:
	incbin	"grafica/mappa3.raw"
MAPPA3_FINE:
	IFNE	(MAPPA3_FINE-MAPPA3)-MAPPA_ATTESA
GUARDIA_MAPPA3_RAW	EQU		1/0
	ENDC
	cnop	0,2
MAPPA4:
	incbin	"grafica/mappa4.raw"
MAPPA4_FINE:
	IFNE	(MAPPA4_FINE-MAPPA4)-MAPPA_ATTESA
GUARDIA_MAPPA4_RAW	EQU		1/0
	ENDC
	cnop	0,4
MappaBase:
	dc.l	MAPPA1			; 0 = mappa1
	dc.l	MAPPA2			; 1 = mappa2
	dc.l	MAPPA3			; 2 = mappa3
	dc.l	MAPPA4			; 3 = mappa4
MappaBaseFine:
	IFNE	(MappaBaseFine-MappaBase)/4-MAPPE_N
GUARDIA_MAPPA_BASE	EQU		1/0
	ENDC

; Una voce per blocco, VERSI_N word: l'indice del vicino o -1.
	cnop	0,2
MappaLink:
	dc.w	  3,  1, -1, -1	; mappa1
	dc.w	  0,  2, -1, -1	; mappa2
	dc.w	  1,  3, -1, -1	; mappa3
	dc.w	  2,  0, -1, -1	; mappa4
MappaLinkFine:
	IFNE	(MappaLinkFine-MappaLink)/(VERSI_N*2)-MAPPE_N
GUARDIA_MAPPA_LINK	EQU		1/0
	ENDC

; Il FOGLIO DI TILE di ogni blocco: una word per blocco, l'indice nella lista
; dei fogli qui sopra. Lo legge ImpostaBlocco, che da li' ricava la TileFlags
; del foglio passando per TabFoglioFlags.
	cnop	0,2
MappaFoglio:
	dc.w	  0			; mappa1 -> Tiles1
	dc.w	  0			; mappa2 -> Tiles1
	dc.w	  0			; mappa3 -> Tiles1
	dc.w	  0			; mappa4 -> Tiles1
MappaFoglioFine:
	IFNE	(MappaFoglioFine-MappaFoglio)/2-MAPPE_N
GUARDIA_MAPPA_FOGLIO	EQU		1/0
	ENDC

; I NOMI DEI FILE DEI FOGLI, come li apre CaricaFogli (Arte.i) a runtime. Sono
; percorsi RELATIVI alla cartella da cui parte il gioco: i .raw devono stare
; in <li'>/grafica/, che non e' la stessa cosa della cartella grafica/ del
; sorgente. Ce li porta  py tools\porta-su-dh0.py .
	cnop	0,4
FogliNomi:
	dc.l	FoglioNome0
	dc.l	FoglioNome1
FogliNomiFine:
	IFNE	(FogliNomiFine-FogliNomi)/4-FOGLI_N
GUARDIA_FOGLI_NOMI	EQU		1/0
	ENDC
FoglioNome0:	dc.b	"grafica/Tiles1.raw",0
FoglioNome1:	dc.b	"grafica/Tiles2.raw",0
	even
