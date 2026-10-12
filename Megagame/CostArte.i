; CostArte.i - costanti dei fogli di tile e l'interruttore del caricamento.
; Incluso da Gioco.s: contiene solo EQU, non emette un byte.
;
; PERCHE' E' LA PRIMA INCLUDE E NON STA IN CostDisplay.i. Devpac valuta una EQU
; dove la incontra, e `FOGLIO_DA_FILE` lo usa `Avvio.i`, che deve stare prima
; di `Startup2.i` per essere il punto d'ingresso del programma. Qualunque posto
; piu' in basso lo renderebbe un simbolo non definito.

; LA FORMA DEL FOGLIO DELLE TILE. Stavano in Variabili.i, accanto a TileFlags;
; sono salite qui il 11 ottobre 2026 perche' le usa anche Arte.i, che e'
; incluso prima - e Devpac valuta una EQU dove la incontra.
; Due numeri che descrivono un FILE, quindi protetti da una guardia: con
; l'incbin era GUARDIA_TILES_RAW al tempo di assemblaggio, senza incbin e'
; CaricaFogli che confronta la lunghezza letta con FOGLIO_BYTE.
; E NON SI CHIAMANO TILE_*: quel prefisso e' RISERVATO AI MARCATORI (ogni EQU
; TILE_* con valore 0..319 diventa un marcatore per tools/mappa.py).
FOGLIO_TILE_COLS	EQU		20		; tile per riga nel foglio
FOGLIO_TILE_RIGHE	EQU		16		; righe di tile nel foglio
FOGLIO_TILE_N		EQU		FOGLIO_TILE_COLS*FOGLIO_TILE_RIGHE
FOGLIO_TILE_BYTE	EQU		16*2*5		; una tile: 16 righe x 1 word x 5 piani
FOGLIO_BYTE		EQU		FOGLIO_TILE_N*FOGLIO_TILE_BYTE	; 51200

; L'INTERRUTTORE DEL CARICAMENTO DEI FOGLI (regola 13).
;   0  i fogli entrano con un `incbin`, come fino al 11 ottobre 2026. UNO solo,
;      quello di indice 0: senza lettura da file non c'e' modo di averne due
;      senza pagarli tutti in chip. Il gioco funziona, ma il cambio di foglio
;      al passaggio di mappa non avviene.
;   1  i fogli si LEGGONO da grafica/<nome>.raw all'avvio, prima che Startup2
;      prenda il ferro, in un'area in fast; al passaggio quello che serve
;      viene copiato nell'unico buffer in chip.
; Serve un interruttore perche' il caricamento tocca l'avvio e dipende da dove
; stanno i file a runtime: se sul ferro va storto si torna a 0 con un numero,
; senza rimettere mano al codice.
FOGLIO_DA_FILE		EQU		1
