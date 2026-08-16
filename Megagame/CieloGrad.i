; =====================================================================
; CieloGrad.i - tabella colori del gradiente cielo
;
; 212 voci estratte da CieloCopper.i (righe raster 44..255)
; piu' 48 voci di SFUMATURA AL NERO in coda, cosi' il cielo si chiude sul
; nero e il pannello sotto non ha una cucitura visibile.
;
; Ogni voce sono le DUE word che il copper scrive su COLOR00: la prima con
; BPLCON3 LOCT=0 (nibble alti), la seconda con LOCT=1 (nibble bassi) - e' il
; colore AGA a 24 bit spezzato come vuole l'hardware.
;
; La copperlist NON e' statica: BuildSkyCopper la genera al boot ricampionando
; questa tabella su BG_VIS_ROWS righe, quindi il gradiente E' SEMPRE INTERO,
; sfumatura finale compresa, qualunque sia CUT_BOTTOM_ROWS.
; Per cambiare la lunghezza della sfumatura si rigenera la tabella: e' un dato,
; non codice.
; =====================================================================
SKY_SRC_FIRST   EQU     $2C             ; prima riga raster dell'arte originale
SKY_SRC_ROWS    EQU     260             ; voci totali (arte + sfumatura)
SKY_FADE_ROWS   EQU     48              ; di cui sfumatura finale al nero

SkyGradient:
        dc.w    $087a,$07f8,$087a,$08f8,$087a,$0af8,$087a,$0bf8    ; voci 0..3
        dc.w    $088a,$0c08,$088a,$0d08,$088a,$0f08,$098a,$0008    ; voci 4..7
        dc.w    $098a,$0108,$098a,$0308,$098a,$0418,$098a,$0517    ; voci 8..11
        dc.w    $098a,$0617,$098a,$0817,$098a,$0917,$098a,$0a17    ; voci 12..15
        dc.w    $098a,$0b27,$098a,$0d27,$098a,$0e27,$098a,$0f27    ; voci 16..19
        dc.w    $0a8a,$0127,$0a8a,$0227,$0a8a,$0337,$0a8a,$0437    ; voci 20..23
        dc.w    $0a8a,$0637,$0a8a,$0737,$0a8a,$0837,$0a8a,$0a37    ; voci 24..27
        dc.w    $0a8a,$0b47,$0a8a,$0c47,$0a8a,$0d47,$0a8a,$0f47    ; voci 28..31
        dc.w    $0b8a,$0046,$0b8a,$0146,$0b8a,$0356,$0b8a,$0456    ; voci 32..35
        dc.w    $0b8a,$0556,$0b8a,$0656,$0b8a,$0856,$0b8a,$0956    ; voci 36..39
        dc.w    $0b8a,$0a66,$0b8a,$0b66,$0b8a,$0d66,$0b8a,$0d66    ; voci 40..43
        dc.w    $0b8a,$0e65,$0b8a,$0f55,$0b8a,$0f55,$0c8a,$0054    ; voci 44..47
        dc.w    $0c8a,$0054,$0c8a,$0154,$0c8a,$0153,$0c8a,$0243    ; voci 48..51
        dc.w    $0c8a,$0243,$0c8a,$0342,$0c8a,$0342,$0c8a,$0441    ; voci 52..55
        dc.w    $0c8a,$0531,$0c8a,$0531,$0c8a,$0630,$0c8a,$0630    ; voci 56..59
        dc.w    $0c8a,$0730,$0c89,$072f,$0c89,$082f,$0c89,$082f    ; voci 60..63
        dc.w    $0c89,$092e,$0c89,$092e,$0c89,$0a1e,$0c89,$0b1d    ; voci 64..67
        dc.w    $0c89,$0b1d,$0c89,$0c1c,$0c89,$0c1c,$0c89,$0d1c    ; voci 68..71
        dc.w    $0c89,$0d0b,$0c89,$0e0b,$0c89,$0e0b,$0c89,$0f0a    ; voci 72..75
        dc.w    $0c89,$0f0a,$0d79,$00fa,$0d79,$01f9,$0d79,$01f9    ; voci 76..79
        dc.w    $0d79,$02f9,$0d79,$02f8,$0d79,$03e8,$0d79,$03e7    ; voci 80..83
        dc.w    $0d79,$04e7,$0d79,$04e7,$0d79,$05f7,$0d79,$06f7    ; voci 84..87
        dc.w    $0d89,$0707,$0d89,$0807,$0d89,$0816,$0d89,$0916    ; voci 88..91
        dc.w    $0d89,$0a16,$0d89,$0b26,$0d89,$0c26,$0d89,$0c36    ; voci 92..95
        dc.w    $0d89,$0d36,$0d89,$0e46,$0d89,$0f46,$0d89,$0f56    ; voci 96..99
        dc.w    $0e89,$0056,$0e89,$0155,$0e89,$0265,$0e89,$0365    ; voci 100..103
        dc.w    $0e89,$0375,$0e89,$0475,$0e89,$0585,$0e89,$0685    ; voci 104..107
        dc.w    $0e89,$0695,$0e89,$0795,$0e89,$08a5,$0e89,$09a4    ; voci 108..111
        dc.w    $0e89,$0aa4,$0e89,$0ab4,$0e89,$0bb4,$0e89,$0cc4    ; voci 112..115
        dc.w    $0e89,$0dc4,$0e89,$0dd4,$0e89,$0ed4,$0e89,$0fe4    ; voci 116..119
        dc.w    $0f89,$00e4,$0f89,$01e4,$0f89,$01f3,$0f89,$02f3    ; voci 120..123
        dc.w    $0f99,$0303,$0f99,$0403,$0f99,$0513,$0f99,$0513    ; voci 124..127
        dc.w    $0f99,$0523,$0f99,$0533,$0f99,$0533,$0f99,$0543    ; voci 128..131
        dc.w    $0f99,$0653,$0f99,$0653,$0f99,$0663,$0f99,$0673    ; voci 132..135
        dc.w    $0f99,$0673,$0f99,$0683,$0f99,$0692,$0f99,$06a2    ; voci 136..139
        dc.w    $0f99,$06a2,$0f99,$06b2,$0f99,$06c2,$0f99,$07c2    ; voci 140..143
        dc.w    $0f99,$07d2,$0f99,$07e2,$0f99,$07e2,$0f99,$07f2    ; voci 144..147
        dc.w    $0fa9,$0702,$0fa9,$0702,$0fa9,$0712,$0fa9,$0722    ; voci 148..151
        dc.w    $0fa9,$0722,$0fa9,$0832,$0fa9,$0842,$0fa9,$0852    ; voci 152..155
        dc.w    $0fa9,$0852,$0fa9,$0862,$0fa9,$0872,$0fa9,$0871    ; voci 156..159
        dc.w    $0fa9,$0881,$0fa9,$0891,$0fa9,$0891,$0fa9,$08a1    ; voci 160..163
        dc.w    $0fa9,$09b1,$0fa9,$09b1,$0fa9,$09c1,$0fa9,$09d1    ; voci 164..167
        dc.w    $0fa9,$09d1,$0fa9,$09e1,$0fb9,$0902,$0fb9,$0923    ; voci 168..171
        dc.w    $0fb9,$0944,$0fb9,$0956,$0fb9,$0977,$0fb9,$0998    ; voci 172..175
        dc.w    $0fb9,$0aa9,$0fb9,$0aca,$0fb9,$0aeb,$0fc9,$0a0c    ; voci 176..179
        dc.w    $0fc9,$0a1d,$0fc9,$0a3e,$0fc9,$0a5f,$0fca,$0a70    ; voci 180..183
        dc.w    $0fca,$0a82,$0fca,$0aa3,$0fca,$0ac4,$0fca,$0ad5    ; voci 184..187
        dc.w    $0fca,$0af6,$0fda,$0a17,$0fda,$0b38,$0fda,$0b49    ; voci 188..191
        dc.w    $0fda,$0b6a,$0fda,$0b8b,$0fda,$0bac,$0fda,$0bbe    ; voci 192..195
        dc.w    $0fda,$0bdf,$0fdb,$0bf0,$0feb,$0b11,$0feb,$0b22    ; voci 196..199
        dc.w    $0feb,$0b43,$0feb,$0b64,$0feb,$0b75,$0feb,$0b96    ; voci 200..203
        dc.w    $0feb,$0cb7,$0feb,$0cd8,$0feb,$0cea,$0ffb,$0c0b    ; voci 204..207
        dc.w    $0ffb,$0c2c,$0ffb,$0c4d,$0ffb,$0c5e,$0ffb,$0c7f    ; voci 208..211
        dc.w    $0ffb,$072b,$0feb,$02d7,$0eeb,$0c83,$0eea,$072f    ; voci 212..215
        dc.w    $0eda,$02db,$0dda,$0d87,$0dda,$0733,$0dc9,$02ef    ; voci 216..219
        dc.w    $0cc9,$0d9b,$0cc9,$0847,$0cb9,$02e3,$0bb8,$0d9f    ; voci 220..223
        dc.w    $0bb8,$084b,$0ba8,$03f7,$0aa8,$0da3,$0aa7,$085f    ; voci 224..227
        dc.w    $0aa7,$030b,$0997,$0ea7,$0997,$0853,$0996,$030f    ; voci 228..231
        dc.w    $0886,$0ebb,$0886,$0967,$0886,$0313,$0776,$0ec0    ; voci 232..235
        dc.w    $0775,$096c,$0775,$0418,$0665,$0ec4,$0665,$0970    ; voci 236..239
        dc.w    $0664,$042c,$0554,$0fd8,$0554,$0974,$0554,$0420    ; voci 240..243
        dc.w    $0443,$0fdc,$0443,$0a88,$0443,$0434,$0333,$0fe0    ; voci 244..247
        dc.w    $0332,$0a9c,$0332,$0538,$0222,$0fe4,$0222,$0a90    ; voci 248..251
        dc.w    $0221,$054c,$0211,$00f8,$0111,$0aa4,$0111,$0550    ; voci 252..255
        dc.w    $0100,$00fc,$0000,$0ba8,$0000,$0554,$0000,$0000    ; voci 256..259
