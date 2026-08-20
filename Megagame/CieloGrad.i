; =====================================================================
; CieloGrad.i - tabella colori del gradiente cielo
;
; GENERATO da tools/gen-cielo.py: NON modificare a mano, si rigenera.
;   python3 tools/gen-cielo.py tools/CieloGrad-arte-260.src > CieloGrad.i
; (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
; La sorgente e' tools/CieloGrad-arte-260.src, l'arte a 260 voci: 212 righe
; estratte da CieloCopper.i piu' 48 di sfumatura al nero aggiunte per
; chiudere il cielo sopra il pannello senza cucitura.
;
; UNA VOCE PER RIGA RASTER. Il copper scrive un colore per riga e le
; righe visibili sono BG_VIS_ROWS: tenere 260 voci per un display da
; 176 significava buttarne via 84 a runtime. Il vecchio conto
; i*260/176 le buttava TRONCANDO, e troncando saltava voci intere -
; l'indice avanza di 1,477 per riga, quindi ogni tanto due gradini
; dell'arte finivano compressi in una riga sola. Qui le 84 voci non
; sono scartate ma FUSE: si interpola fra le due voci adiacenti.
;
; LA COMPOSIZIONE NON CAMBIA. L'orizzonte (la voce piu' luminosa
; dell'arte) resta a riga 144 come prima, perche' col vecchio conto
; 143*260/176 dava 211 e 144*260/176 dava 212. Cambiare la ripartizione
; RIDISEGNA il cielo invece di lisciarlo: si fa da gen-cielo.py, dove
; c'e' la tabella del costo in altezza.
;
; MISURATO, in L* (la scala dove 1 e' la soglia percettiva):
;                          arte 0..143      sfumatura 144..175
;   dL* massimo              0,87              3,73
;   righe sopra soglia       0 su 143          32 su 32
;   prima era                4 righe, dL* 1,12 32 righe, dL* 4,99
;
; Quindi: nell'ARTE le bande spariscono del tutto. Nella SFUMATURA no,
; e non e' un difetto di questo file: 96 unita' di L* in 32 righe fanno
; 3,01 a riga contro una soglia di 1, e per stare sotto servirebbero ~96
; righe raster prese all'arte. E' un prezzo in composizione, non in
; codice, quindi la scelta non e' mia.
;
; Salto massimo in RGB grezzo: 9 livelli su 255 (prima: 11).
;
; Ogni voce sono le DUE word che il copper scrive su COLOR00: la prima
; con BPLCON3 LOCT=0 (nibble alti), la seconda con LOCT=1 (nibble
; bassi) - e' il colore AGA a 24 bit spezzato come vuole l'hardware.
; =====================================================================
; La prima riga raster e' $2C. NON e' una EQU qui: c'era, non la
; leggeva nessuno, e il valore vive gia' cablato in BuildSkyCopper
; (ADD.W #$2C), in DIWSTRT e in PANNELLO_TOP_RASTER. Una quarta copia
; mai letta non aiutava; unificare le altre tre e' un lavoro a parte.
SKY_SRC_ROWS    EQU     176             ; voci = righe raster visibili (1:1)

SkyGradient:
        dc.w    $087a,$07f8,$087a,$09f8,$087a,$0bf8,$088a,$0c08 ; righe   0..  3
        dc.w    $088a,$0f08,$098a,$0008,$098a,$0308,$098a,$0418 ; righe   4..  7
        dc.w    $098a,$0617,$098a,$0817,$098a,$0a17,$098a,$0b27 ; righe   8.. 11
        dc.w    $098a,$0e27,$098a,$0f27,$0a8a,$0227,$0a8a,$0337 ; righe  12.. 15
        dc.w    $0a8a,$0537,$0a8a,$0737,$0a8a,$0937,$0a8a,$0b47 ; righe  16.. 19
        dc.w    $0a8a,$0d47,$0a8a,$0f47,$0b8a,$0046,$0b8a,$0356 ; righe  20.. 23
        dc.w    $0b8a,$0456,$0b8a,$0656,$0b8a,$0856,$0b8a,$0a66 ; righe  24.. 27
        dc.w    $0b8a,$0c66,$0b8a,$0d66,$0b8a,$0e65,$0b8a,$0f55 ; righe  28.. 31
        dc.w    $0c8a,$0054,$0c8a,$0154,$0c8a,$0153,$0c8a,$0243 ; righe  32.. 35
        dc.w    $0c8a,$0342,$0c8a,$0441,$0c8a,$0531,$0c8a,$0630 ; righe  36.. 39
        dc.w    $0c8a,$0630,$0c8a,$0730,$0c89,$082f,$0c89,$082f ; righe  40.. 43
        dc.w    $0c89,$092e,$0c89,$0a1e,$0c89,$0b1d,$0c89,$0c1c ; righe  44.. 47
        dc.w    $0c89,$0d1c,$0c89,$0d0b,$0c89,$0e0b,$0c89,$0f0a ; righe  48.. 51
        dc.w    $0d79,$00fa,$0d79,$01f9,$0d79,$02f9,$0d79,$02f8 ; righe  52.. 55
        dc.w    $0d79,$03e7,$0d79,$04e7,$0d79,$05f7,$0d79,$06f7 ; righe  56.. 59
        dc.w    $0d89,$0807,$0d89,$0816,$0d89,$0916,$0d89,$0b26 ; righe  60.. 63
        dc.w    $0d89,$0c26,$0d89,$0d36,$0d89,$0e46,$0d89,$0f56 ; righe  64.. 67
        dc.w    $0e89,$0056,$0e89,$0265,$0e89,$0365,$0e89,$0475 ; righe  68.. 71
        dc.w    $0e89,$0585,$0e89,$0695,$0e89,$0795,$0e89,$09a4 ; righe  72.. 75
        dc.w    $0e89,$0aa4,$0e89,$0bb4,$0e89,$0cc4,$0e89,$0dd4 ; righe  76.. 79
        dc.w    $0e89,$0ed4,$0f89,$00e4,$0f89,$01e4,$0f89,$01f3 ; righe  80.. 83
        dc.w    $0f99,$0303,$0f99,$0403,$0f99,$0513,$0f99,$0523 ; righe  84.. 87
        dc.w    $0f99,$0533,$0f99,$0543,$0f99,$0653,$0f99,$0663 ; righe  88.. 91
        dc.w    $0f99,$0673,$0f99,$0683,$0f99,$06a2,$0f99,$06a2 ; righe  92.. 95
        dc.w    $0f99,$06c2,$0f99,$07c2,$0f99,$07e2,$0f99,$07e2 ; righe  96.. 99
        dc.w    $0fa9,$0702,$0fa9,$0702,$0fa9,$0722,$0fa9,$0722 ; righe 100..103
        dc.w    $0fa9,$0832,$0fa9,$0852,$0fa9,$0852,$0fa9,$0872 ; righe 104..107
        dc.w    $0fa9,$0871,$0fa9,$0891,$0fa9,$0891,$0fa9,$09b1 ; righe 108..111
        dc.w    $0fa9,$09b1,$0fa9,$09d1,$0fa9,$09d1,$0fa9,$09f2 ; righe 112..115
        dc.w    $0fb9,$0923,$0fb9,$0955,$0fb9,$0977,$0fb9,$0aa9 ; righe 116..119
        dc.w    $0fb9,$0aca,$0fb9,$0afc,$0fc9,$0a1d,$0fc9,$0a4e ; righe 120..123
        dc.w    $0fca,$0a70,$0fca,$0a92,$0fca,$0ac4,$0fca,$0ae5 ; righe 124..127
        dc.w    $0fda,$0a17,$0fda,$0b38,$0fda,$0b6a,$0fda,$0b9b ; righe 128..131
        dc.w    $0fda,$0bbe,$0fda,$0bdf,$0feb,$0b01,$0feb,$0b22 ; righe 132..135
        dc.w    $0feb,$0b54,$0feb,$0b75,$0feb,$0ca7,$0feb,$0cd8 ; righe 136..139
        dc.w    $0feb,$0cfb,$0ffb,$0c2c,$0ffb,$0c5e,$0ffb,$0c7f ; righe 140..143  <-- orizzonte
        dc.w    $0ffb,$0409,$0eeb,$0c83,$0eea,$040d,$0dda,$0d87 ; righe 144..147
        dc.w    $0dda,$0401,$0cc9,$0d9b,$0cc9,$0515,$0bb8,$0d9f ; righe 148..151
        dc.w    $0bb8,$0629,$0aa8,$0da3,$0aa7,$062d,$0997,$0ea7 ; righe 152..155
        dc.w    $0997,$0621,$0886,$0ebb,$0886,$0645,$0776,$0ec0 ; righe 156..159
        dc.w    $0775,$064a,$0665,$0ec4,$0664,$064e,$0554,$0fd8 ; righe 160..163
        dc.w    $0554,$0642,$0443,$0fdc,$0443,$0766,$0333,$0fe0 ; righe 164..167
        dc.w    $0332,$086a,$0222,$0fe4,$0221,$086e,$0211,$00f8 ; righe 168..171
        dc.w    $0111,$0882,$0100,$00fc,$0000,$0886,$0000,$0000 ; righe 172..175

; La tabella e' 1:1 con le righe raster: SKY_SRC_ROWS DEVE valere quanto
; SKY_STEPS, altrimenti BuildSkyCopper torna a ricampionare per indice e
; le bande tornano IN SILENZIO. Se cambi CUT_BOTTOM_ROWS, rigenera questo
; file con il nuovo RIGHE. FAIL viene ignorata dall'assemblatore, quindi
; si usa la divisione per zero: il messaggio e' brutto ma il nome del
; simbolo dice cosa fare. SKY_STEPS e' definita in Gioco.s, che include
; questo file piu' sotto.
ERRORE_CIELOGRAD_DA_RIGENERARE  EQU     SKY_SRC_ROWS-SKY_STEPS
        IFNE    ERRORE_CIELOGRAD_DA_RIGENERARE
GUARDIA_CIELOGRAD       EQU     1/0
        ENDC
