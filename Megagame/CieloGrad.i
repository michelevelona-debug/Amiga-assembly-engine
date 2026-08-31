; =====================================================================
; CieloGrad.i - tabella colori del gradiente cielo
;
; GENERATO da tools/gen-cielo.py: NON modificare a mano, si rigenera.
;   python3 tools/gen-cielo.py tools/CieloGrad-arte-260.src > CieloGrad.i
; (dalla cartella Megagame; su Windows 'py' al posto di 'python3')
; La sorgente e' tools/CieloGrad-arte-260.src, l'arte a 260 voci: 212 righe
; estratte da CieloCopper.i piu' 48 di sfumatura al nero in coda.
; LE 48 VOCI DI SFUMATURA NON SONO USATE: RIGHE_ARTE = RIGHE, quindi il
; cielo si chiude sul giallo dell'orizzonte in fondo allo schermo.
; Restano nel .src per non perderle.
;
; UNA VOCE PER RIGA RASTER. Il copper scrive un colore per riga e le
; righe visibili sono BG_VIS_ROWS: tenere 260 voci per un display da
; 176 significava buttarne via 84 a runtime. Il vecchio conto
; i*260/176 le buttava TRONCANDO, e troncando saltava voci intere -
; l'indice avanza di 1,477 per riga, quindi ogni tanto due gradini
; dell'arte finivano compressi in una riga sola. Qui le 84 voci non
; sono scartate ma FUSE: si interpola fra le due voci adiacenti.
;
; NIENTE SFUMATURA: tutte le 176 righe vanno all'arte e il cielo si chiude
; sul giallo dell'orizzonte (l'ultima voce d'arte) in fondo allo schermo,
; a contatto col pannello. Deciso il 22 agosto 2026 per due motivi che
; vanno insieme: la sfumatura al nero era l'UNICO punto del cielo con
; bande sopra soglia, e toglierla restituisce all'arte le righe che si
; prendeva, quindi l'arte si distende su 176 righe invece che su 144 e i
; suoi gradini si diradano ancora.
;
; MISURATO, in L* (la scala dove 1 e' la soglia percettiva):
;                                 ora            prima (arte + sfumatura)
;   dL* massimo                   0,85            0,87 arte / 3,73 sfumatura
;   righe sopra soglia            0 su 175        0 su 143 / 32 su 32
;
; Il cielo non ha piu' nemmeno una riga sopra la soglia percettiva.
;
; UNA RIGA, UN COLORE. Le 175 transizioni cambiano TUTTE il valore di
; COLOR00: non c'e' una sola riga che ripete il colore di quella sopra,
; quindi il copper sfrutta ogni scrittura che l'hardware gli concede.
; Prima erano 160 su 175: la curva avanza di 0,67 livelli per riga in R,
; 0,69 in G e 0,13 in B, e arrotondando riga per riga la frazione si
; perdeva. Ora l'errore viene portato avanti lungo la colonna e, quando
; due righe cadrebbero comunque sullo stesso valore, si arrotonda
; dall'altra parte il canale che stava gia' per cambiare. Lo scostamento
; dalla curva resta sotto 1 livello su 255 (assert nel generatore).
; NB: due righe LONTANE possono ripetere un colore, e va bene: B oscilla.
; I valori distinti sono 174, le transizioni utili 175 su 175.
;
; Salto massimo in RGB grezzo: 3 livelli su 255 (prima: 11).
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
        dc.w    $087a,$07f8,$087a,$08f8,$087a,$0bf8,$088a,$0b08 ; righe   0..  3
        dc.w    $088a,$0d08,$088a,$0f08,$098a,$0108,$098a,$0107 ; righe   4..  7
        dc.w    $098a,$0408,$098a,$0517,$098a,$0617,$098a,$0817 ; righe   8.. 11
        dc.w    $098a,$0a17,$098a,$0a27,$098a,$0d27,$098a,$0e27 ; righe  12.. 15
        dc.w    $0a8a,$0027,$0a8a,$0127,$0a8a,$0337,$0a8a,$0437 ; righe  16.. 19
        dc.w    $0a8a,$0637,$0a8a,$0737,$0a8a,$0937,$0a8a,$0b37 ; righe  20.. 23
        dc.w    $0a8a,$0c47,$0a8a,$0d47,$0b8a,$0047,$0b8a,$0046 ; righe  24.. 27
        dc.w    $0b8a,$0356,$0b8a,$0456,$0b8a,$0556,$0b8a,$0756 ; righe  28.. 31
        dc.w    $0b8a,$0856,$0b8a,$0a66,$0b8a,$0b66,$0b8a,$0d66 ; righe  32.. 35
        dc.w    $0b8a,$0d65,$0b8a,$0f55,$0b8a,$0f56,$0c8a,$0054 ; righe  36.. 39
        dc.w    $0c8a,$0053,$0c8a,$0154,$0c8a,$0253,$0c8a,$0243 ; righe  40.. 43
        dc.w    $0c8a,$0342,$0c8a,$0343,$0c8a,$0531,$0c8a,$0530 ; righe  44.. 47
        dc.w    $0c8a,$0630,$0c8a,$0631,$0c8a,$0730,$0c89,$072f ; righe  48.. 51
        dc.w    $0c89,$082f,$0c89,$092e,$0c89,$092d,$0c89,$0a1d ; righe  52.. 55
        dc.w    $0c89,$0b1d,$0c89,$0c1d,$0c89,$0c1c,$0c89,$0d1b ; righe  56.. 59
        dc.w    $0c89,$0e0b,$0c89,$0e0c,$0c89,$0e0b,$0c89,$0f0a ; righe  60.. 63
        dc.w    $0d79,$00fa,$0d79,$01f9,$0d79,$02f9,$0d79,$02f8 ; righe  64.. 67
        dc.w    $0d79,$03e8,$0d79,$03e7,$0d79,$04e7,$0d79,$05e7 ; righe  68.. 71
        dc.w    $0d79,$06f7,$0d89,$0707,$0d89,$0817,$0d89,$0816 ; righe  72.. 75
        dc.w    $0d89,$0a16,$0d89,$0b16,$0d89,$0c26,$0d89,$0c36 ; righe  76.. 79
        dc.w    $0d89,$0d46,$0d89,$0f46,$0d89,$0f56,$0e89,$0055 ; righe  80.. 83
        dc.w    $0e89,$0155,$0e89,$0365,$0e89,$0375,$0e89,$0475 ; righe  84.. 87
        dc.w    $0e89,$0585,$0e89,$0685,$0e89,$0695,$0e89,$08a5 ; righe  88.. 91
        dc.w    $0e89,$09a5,$0e89,$0aa4,$0e89,$0ab4,$0e89,$0cb4 ; righe  92.. 95
        dc.w    $0e89,$0dc4,$0e89,$0dd4,$0e89,$0ee4,$0e89,$0fe4 ; righe  96.. 99
        dc.w    $0f89,$01e4,$0f89,$01e3,$0f89,$02f3,$0f99,$0303 ; righe 100..103
        dc.w    $0f99,$0413,$0f99,$0513,$0f99,$0512,$0f99,$0533 ; righe 104..107
        dc.w    $0f99,$0543,$0f99,$0643,$0f99,$0653,$0f99,$0663 ; righe 108..111
        dc.w    $0f99,$0673,$0f99,$0674,$0f99,$0692,$0f99,$0691 ; righe 112..115
        dc.w    $0f99,$06a2,$0f99,$06b2,$0f99,$06c2,$0f99,$07d2 ; righe 116..119
        dc.w    $0f99,$07e2,$0f99,$07e3,$0f99,$07f2,$0fa9,$0702 ; righe 120..123
        dc.w    $0fa9,$0701,$0fa9,$0722,$0fa9,$0723,$0fa9,$0832 ; righe 124..127
        dc.w    $0fa9,$0842,$0fa9,$0852,$0fa9,$0862,$0fa9,$0872 ; righe 128..131
        dc.w    $0fa9,$0871,$0fa9,$0891,$0fa9,$0890,$0fa9,$0891 ; righe 132..135
        dc.w    $0fa9,$09b1,$0fa9,$09b2,$0fa9,$09d1,$0fa9,$09d0 ; righe 136..139
        dc.w    $0fa9,$09e1,$0fb9,$0902,$0fb9,$0924,$0fb9,$0954 ; righe 140..143
        dc.w    $0fb9,$0967,$0fb9,$0988,$0fb9,$0aa9,$0fb9,$0ada ; righe 144..147
        dc.w    $0fb9,$0afc,$0fc9,$0a1c,$0fc9,$0a2e,$0fc9,$0a5f ; righe 148..151
        dc.w    $0fca,$0a81,$0fca,$0a92,$0fca,$0ab4,$0fca,$0ad5 ; righe 152..155
        dc.w    $0fca,$0af6,$0fda,$0a27,$0fda,$0b39,$0fda,$0b69 ; righe 156..159
        dc.w    $0fda,$0b7b,$0fda,$0bac,$0fda,$0bcf,$0fda,$0bef ; righe 160..163
        dc.w    $0feb,$0b11,$0feb,$0b22,$0feb,$0b43,$0feb,$0b64 ; righe 164..167
        dc.w    $0feb,$0b86,$0feb,$0cb7,$0feb,$0cd8,$0feb,$0cea ; righe 168..171
        dc.w    $0ffb,$0c1b,$0ffb,$0c3d,$0ffb,$0c5e,$0ffb,$0c7f ; righe 172..175  <-- orizzonte

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
