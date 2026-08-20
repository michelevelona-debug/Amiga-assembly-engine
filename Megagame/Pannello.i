; ============================================================
; Pannello.i - generato da png2amiga.py
; ============================================================
PANNELLO_WIDTH          EQU     320
PANNELLO_HEIGHT         EQU     80
PANNELLO_BITPLANES      EQU     4
PANNELLO_COLORS         EQU     16
PANNELLO_BYTES_PER_ROW  EQU     40
PANNELLO_PLANE_SIZE     EQU     3200       ; byte per singolo bitplane
PANNELLO_TOTAL_SIZE     EQU     12800       ; byte totali di tutto il blocco RAW
PANNELLO__PALETTE_SIZE   EQU     64         ; byte totali della palette

; Layout RAW: SEQUENTIAL
; Formato palette: AGA $00RRGGBB long
;
; Esempio di uso:
;
;     SECTION GfxData,DATA_C   ; CHIP RAM per i bitplane
; Pannello_bpl:
;     INCBIN  "Pannello.raw"
;
;     SECTION GfxPal,DATA      ; palette in RAM normale e' ok
; Pannello_pal:
;     INCBIN  "Pannello.pal"
