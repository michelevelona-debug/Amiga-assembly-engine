; ============================================================
; title.i - generato da png2amiga.py
; ============================================================
TITLE_WIDTH          EQU     320
TITLE_HEIGHT         EQU     256
TITLE_BITPLANES      EQU     8
TITLE_COLORS         EQU     256
TITLE_BYTES_PER_ROW  EQU     40
TITLE_PLANE_SIZE     EQU     10240       ; byte per singolo bitplane
TITLE_TOTAL_SIZE     EQU     81920       ; byte totali di tutto il blocco RAW
TITLE_PALETTE_SIZE   EQU     1024         ; byte totali della palette

; Layout RAW: SEQUENTIAL
; Formato palette: AGA $00RRGGBB long;
; Esempio di uso:
;
;     SECTION GfxData,DATA_C   ; CHIP RAM per i bitplane
; title_bpl:
;     INCBIN  "title.raw"
;
;     SECTION GfxPal,DATA      ; palette in RAM normale e' ok
; title_pal:
;     INCBIN  "title.pal"
