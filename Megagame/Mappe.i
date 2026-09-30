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
; ============================================================================

MAPPE_N				EQU		2

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
	cnop	0,4
MappaBase:
	dc.l	MAPPA1			; 0 = mappa1
	dc.l	MAPPA2			; 1 = mappa2
MappaBaseFine:
	IFNE	(MappaBaseFine-MappaBase)/4-MAPPE_N
GUARDIA_MAPPA_BASE	EQU		1/0
	ENDC

; Una voce per blocco, VERSI_N word: l'indice del vicino o -1.
	cnop	0,2
MappaLink:
	dc.w	 -1,  1, -1, -1	; mappa1
	dc.w	  0, -1, -1, -1	; mappa2
MappaLinkFine:
	IFNE	(MappaLinkFine-MappaLink)/(VERSI_N*2)-MAPPE_N
GUARDIA_MAPPA_LINK	EQU		1/0
	ENDC
