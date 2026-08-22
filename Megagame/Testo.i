;=====================================================================
; Testo.i — stampa di testo su bitplane con font raster
;
; Modulo generico, indipendente dal profiling: usalo per il pannello,
; il punteggio, i messaggi, i menu.
;
; FORMATO DEL FONT (Metal.fnt, 768 byte)
;   Carattere 8x8 px = 1 byte per riga, 8 righe.
;   96 caratteri ASCII consecutivi da 32 (spazio) a 127: cifre,
;   MAIUSCOLE, minuscole e punteggiatura. Il set e' completo.
;   Layout: GLIFO CONTIGUO — ogni carattere occupa 8 byte consecutivi,
;   quindi il carattere c comincia a offset c*FONT_GLYPH e la sua riga
;   r sta a c*FONT_GLYPH + r*FONT_CW.
;   ATTENZIONE: e' un layout DIVERSO dal vecchio font16x20.raw, che era
;   una strip orizzontale (riga r del char c a r*pitch + c*2). Se un
;   giorno torni a un font a strip, va cambiato l'avanzamento di riga
;   in TestoChar, non solo le EQU.
;   1 solo bitplane (la forma della lettera), replicato dal codice
;   sui piani di destinazione.
;
; POSIZIONAMENTO
;   Le routine scrivono a byte interi: la X deve essere multipla di
;   8 px. (Col vecchio font 16x20 il vincolo era 16 px: adesso e' meno
;   restrittivo, quindi i chiamanti che allineavano a 16 restano validi.)
;
; PARAMETRI COMUNI (li passi in registro, cosi' il modulo non ha stato)
;   A1   = indirizzo di destinazione nel PIANO 1
;          = base_piano + y*pitch + (x/8)
;   D0.w = pitch della destinazione in byte
;   D1.w = su quanti piani replicare la stessa forma (1..8)
;   D2.l = distanza in byte fra un piano e il successivo
;
; Tutte le routine preservano ogni registro, A1 compreso: e' il
; chiamante che fa avanzare il cursore.
;
; NB: TestoStampa (stringa terminata da 0) e' stata RIMOSSA perche' non
; usata da nessuno. Se serve di nuovo: cicla su TestoChar avanzando A1
; di FONT_CW a ogni carattere.
;=====================================================================

FONT_W          EQU     8                       ; larghezza carattere (px)
FONT_H          EQU     8                       ; altezza carattere (righe)
FONT_CHARS      EQU     96                      ; caratteri nel file
FONT_FIRST      EQU     32                      ; primo carattere = spazio
FONT_CW         EQU     FONT_W/8                ; 1 byte per riga di carattere
FONT_GLYPH      EQU     FONT_CW*FONT_H          ; 8 byte = un glifo intero

;---------------------------------------------------------------------
; TestoChar — disegna UN carattere
; IN:  D3.w = codice ASCII, A1/D0/D1/D2 come sopra
; Un codice fuori dal font non disegna nulla (nessun crash, nessun
; carattere spurio): utile per stampare stringhe non filtrate.
;---------------------------------------------------------------------
TestoChar:
        MOVEM.L D0/D3-D5/A0-A3,-(SP)
        SUB.W   #FONT_FIRST,D3
        BLO.S   .skip                   ; sotto lo spazio -> niente
        CMP.W   #FONT_CHARS,D3
        BHS.S   .skip                   ; oltre l'ultimo -> niente
        ; MULU.W azzera la word alta di D3, quindi eventuale sporcizia
        ; lasciata dal chiamante (es. il resto di DIVU in TestoNumero)
        ; non arriva all'ADDA.W. Max 95*8 = 760: sta in una word.
        MULU.W  #FONT_GLYPH,D3          ; offset del glifo nel file
        LEA     FontData,A0
        ADDA.W  D3,A0                   ; A0 = carattere, riga 0
        MOVEA.L A1,A2                   ; A2 = cursore verticale nel dest
        MOVEQ   #FONT_H-1,D4
.riga:
        MOVE.B  (A0),D5                 ; gli 8 px di questa riga
        MOVEA.L A2,A3                   ; A3 = cursore fra i piani
        MOVE.W  D1,D3
        SUBQ.W  #1,D3
.piano:
        MOVE.B  D5,(A3)                 ; stessa forma su ogni piano
        ADDA.L  D2,A3
        DBRA    D3,.piano
        ADDA.W  #FONT_CW,A0             ; riga successiva dentro il glifo
        ADDA.W  D0,A2                   ; riga successiva nel dest
        DBRA    D4,.riga
.skip:
        MOVEM.L (SP)+,D0/D3-D5/A0-A3
        RTS

;---------------------------------------------------------------------
; TestoNumero — scrive un numero decimale a larghezza fissa
; IN:  D3.w = valore (0..65535), D4.w = quante cifre (1..5)
;      A1/D0/D1/D2 come sopra
; Stampa con gli zeri iniziali, cosi' le colonne restano allineate.
;---------------------------------------------------------------------
TestoNumero:
        MOVEM.L D0-D6/A0-A3,-(SP)
        MOVE.L  D3,D6
        AND.L   #$FFFF,D6               ; D6 = valore residuo
        MOVE.W  D4,D5
        SUBQ.W  #1,D5                   ; D5 = contatore cifre
        ; parte dall'ultima cifra e va a ritroso
        MOVE.W  D5,D3
        MULU.W  #FONT_CW,D3
        ADDA.W  D3,A1
.loop:
        MOVE.L  D6,D3
        DIVU.W  #10,D3                  ; lo = quoziente, hi = resto
        MOVE.W  D3,D6
        AND.L   #$FFFF,D6               ; residuo per il giro dopo
        CLR.W   D3
        SWAP    D3                      ; D3.w = cifra 0..9
        ADD.W   #'0',D3
        BSR.W   TestoChar
        SUBA.W  #FONT_CW,A1             ; cifra precedente
        DBRA    D5,.loop
        MOVEM.L (SP)+,D0-D6/A0-A3
        RTS

;---------------------------------------------------------------------
; Dati del font. Sta in CODE (non serve chip RAM: lo legge la CPU,
; non il blitter).
;---------------------------------------------------------------------
FontData:
        incbin  "grafica/Metal.fnt"
        even
