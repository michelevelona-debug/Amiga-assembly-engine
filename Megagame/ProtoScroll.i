;=====================================================================
; ProtoScroll.i - prototipo dello scroll hardware AGA (Path B, passo 1)
;
; SCOPO: inchiodare i due numeri incerti (DDFSTRT e BPLxMOD) guardando
; una griglia scorrere, senza il rumore della logica di gioco.
;
; Riusa tutto quello che c'e' gia': startup, copperlist, palette, DMA,
; AspettaVBL, LeggiJoystick. L'unica cosa nuova e' il buffer di test.
;
; COME SI ATTIVA
;   PROTO_SCROLL EQU 1  in testa a Gioco.s -> parte il prototipo al
;   posto del gioco. Rimetti 0 e torna tutto come prima.
;
; COMANDI
;   joystick / cursori  = muovi la camera
;   il resto del gioco non gira (nessun BOB, nessun nemico, nessuna
;   fisica): quello che vedi e' SOLO l'effetto dello scroll hardware.
;
; COME SI LEGGE LA GRIGLIA
;   Ogni difetto ha una firma diversa, ed e' per questo che si usa una
;   griglia e non un'immagine:
;
;   - la griglia scorre liscia in entrambe le direzioni
;         -> DDFSTRT e BPLxMOD sono giusti, passo 1 finito
;   - striscia di spazzatura sul bordo SINISTRO, che appare solo
;     quando CameraX non e' multiplo di 64
;         -> DDFSTRT troppo tardi: togli 8 a SCROLL_DDFSTRT
;   - tutta l'immagine spostata di un blocco (64 px)
;         -> DDFSTRT troppo presto: aggiungi 8
;   - il bordo DESTRO perde una fascia o ripete la colonna
;         -> BPLxMOD: aggiusta SCROLL_BPLMOD di 8 alla volta
;   - le linee "saltano" di un pixel ogni 64
;         -> errore nel calcolo del ritardo (BPLCON1), non nei due EQU
;
;   Cambia UNA cosa alla volta e di 8 per volta.
;=====================================================================

; --- INTERRUTTORI DIAGNOSTICI ---------------------------------------
; PROTO_ONE_PLANE: griglia su UN SOLO piano invece di 5.
;   Serve a separare due difetti che si somigliano: se l'anomalia resta
;   identica ma di colore uniforme, il problema e' nella GEOMETRIA dello
;   scroll; se sparisce del tutto, i cinque piani stavano leggendo dati
;   diversi e il problema e' nei PUNTATORI, non nel calcolo.
;   Con 1 piano il colore e' sempre 1: nessuna ambiguita' possibile.
PROTO_ONE_PLANE     EQU     0
; PROTO_MARK_BLOCKS: marca i confini dei blocchi da 64 px sul piano 2.
;   Rende visibile DOVE cade il salto del puntatore. Se l'anomalia e'
;   agganciata a queste marche e' un problema di blocco/prefetch; se no,
;   e' interno alla word.
PROTO_MARK_BLOCKS   EQU     1
; PROTO_MARK_PLANE: su quale piano mettere le marche.
;   IL TEST DECISIVO. La griglia sta sul piano 1, che e' DISPARI e in
;   BPLCON1 usa il campo PF1H. Il piano 2 e' PARI e usa PF2H: sono due
;   campi separati, e se li stiamo scrivendo male i due gruppi di piani
;   si shiftano di quantita' diverse.
;   Metti 3 (dispari, come il piano 1): se lo sfasamento SPARISCE il
;   problema e' in BPLCON1 pari/dispari. Se RESTA sono i puntatori.
PROTO_MARK_PLANE    EQU     2
; PROTO_NO_FINE: azzera lo scroll fine, lasciando solo i salti da 64 px.
;   Secondo test decisivo: senza BPLCON1 in gioco, se l'anomalia sparisce
;   la colpa e' sicuramente sua; se resta, e' nei puntatori o nel fetch.
;   Lo scroll diventa a scatti di 64 px: e' atteso, non e' un difetto.
PROTO_NO_FINE       EQU     0
; PROTO_TUNE_D: modo taratura di BPLCON1, isolato da tutto il resto.
;   Con 1, la camera resta ferma a X=0 (offset del puntatore FISSO) e i
;   tasti SU/GIU' incrementano il solo ritardo D di 1 alla volta, 0..63.
;   Cosi' l'unica cosa che varia e' BPLCON1: qualunque salto che vedi e'
;   suo, senza ambiguita' col puntatore.
;
;   COME USARLO: parti da D=0 e premi GIU' una volta per volta contando.
;   La griglia deve spostarsi di UN pixel a destra per ogni pressione.
;   Annota i valori di D in cui invece SALTA e di quanto: sono quelli che
;   rivelano il peso vero dei bit. I sospetti sono 15->16 (entra la parte
;   alta) e 31->32 (secondo bit della parte alta).
PROTO_TUNE_D        EQU     0

PROTO_MAP_W         EQU     384                     ; larghezza mappa in px
PROTO_MAP_H         EQU     352                     ; altezza mappa in px
PROTO_VIS_W         EQU     320
PROTO_VIS_H         EQU     BG_VIS_ROWS
PROTO_PLANE_SIZE    EQU     SCROLL_PITCH*PROTO_MAP_H
PROTO_CAM_XMAX      EQU     PROTO_MAP_W-PROTO_VIS_W ; 64 px di corsa
PROTO_CAM_YMAX      EQU     PROTO_MAP_H-PROTO_VIS_H ; 176 px di corsa

;---------------------------------------------------------------------
; ProtoScrollInit - griglia nel buffer e patch della copperlist
; IN: A6 = $DFF000
;---------------------------------------------------------------------
ProtoScrollInit:
        MOVEM.L D0-D2/A0-A1,-(SP)

        ; --- griglia su tutti e 5 i piani -> colore 31 --------------
        ; Su un piano solo uscirebbe colore 1, che nella palette a
        ; banchi del gioco non e' detto sia visibile. Il 31 e' l'ultimo
        ; del banco 0 e lo forziamo bianco qui sotto.
        LEA     ProtoBuffer,A0
        IFNE    PROTO_ONE_PLANE
        MOVEQ   #1-1,D2                 ; solo il piano 1 -> colore 1
        ENDC
        IFEQ    PROTO_ONE_PLANE
        MOVEQ   #5-1,D2                 ; tutti e 5 -> colore 31
        ENDC
.pianograglia:
        MOVE.W  #PROTO_MAP_H,D0
        BSR.W   ScrollHWGriglia
        ADDA.L  #PROTO_PLANE_SIZE,A0
        DBRA    D2,.pianograglia

        IFNE    PROTO_MARK_BLOCKS
        ; marca i confini dei blocchi da 64 px sul PIANO 2: dove cade il
        ; salto di BPLxPT si vede a occhio, e il colore lo distingue
        ; dalla griglia.
        LEA     ProtoBuffer+(PROTO_MARK_PLANE-1)*PROTO_PLANE_SIZE,A0
        MOVE.W  #PROTO_MAP_H-1,D0
.markrow:
        MOVE.W  #$8000,(A0)             ; una colonna ogni 64 px = ogni 8 byte
        MOVE.W  #$8000,8(A0)
        MOVE.W  #$8000,16(A0)
        MOVE.W  #$8000,24(A0)
        MOVE.W  #$8000,32(A0)
        MOVE.W  #$8000,40(A0)
        MOVE.W  #$8000,48(A0)
        ADDA.W  #SCROLL_PITCH,A0
        DBRA    D0,.markrow
        ENDC

        ; --- colore 31 bianco, colore 0 blu scuro -------------------
        ; Banco 0 (BPLCON3 e' a 0 nel gioco): COLOR31 sta a $1BE.
        ; Gira DOPO InitPalette8BPL, quindi vince. Se la griglia dovesse
        ; risultare invisibile vuol dire che la copperlist riscrive questi
        ; due registri per frame: in quel caso togli le due MOVE e leggi
        ; la griglia col colore che le tocca.
        MOVE.W  #$0002,$180(A6)         ; sfondo: blu quasi nero
        MOVE.W  #$0FFF,$1BE(A6)         ; griglia: bianco

        ; --- patch della copperlist ---------------------------------
        LEA     CL_Ddf,A1
        MOVE.W  #SCROLL_DDFSTRT,2(A1)   ; DDFSTRT anticipato di un fetch
        MOVE.W  #SCROLL_DDFSTOP,6(A1)
        LEA     CL_BplMod,A1
        MOVE.W  #SCROLL_BPLMOD,2(A1)    ; BPL1MOD
        MOVE.W  #SCROLL_BPLMOD,6(A1)    ; BPL2MOD

        ; --- piani 6/7/8 su un piano vuoto --------------------------
        ; Restano accesi (la contesa DMA deve essere quella vera, 8
        ; piani) ma non devono disturbare la lettura della griglia.
        MOVE.L  #ProtoVuoto,D0
        LEA     BitPlaneTiles+5*8,A1    ; entry del 6o piano
        BSR.S   .ptr
        LEA     BitplaneParall,A1       ; 7o e 8o
        BSR.S   .ptr
        LEA     BitplaneParall+8,A1
        BSR.S   .ptr

        CLR.W   ProtoCamX
        CLR.W   ProtoCamY
        MOVEM.L (SP)+,D0-D2/A0-A1
        RTS

.ptr:   MOVE.W  D0,6(A1)
        SWAP    D0
        MOVE.W  D0,2(A1)
        SWAP    D0
        RTS

;---------------------------------------------------------------------
; ProtoScrollMain - il loop del prototipo. Non ritorna.
; IN: A6 = $DFF000, chiamato dopo l'init del gioco
;---------------------------------------------------------------------
ProtoScrollMain:
        BSR.W   ProtoScrollInit
.loop:
        ; ReadKeyboard PRIMA di LeggiJoystick: e' lui a chiamare
        ; ProcessArrowKey, che setta le flag arrow_* che LeggiJoystick
        ; poi legge. Senza, i tasti freccia non arrivano mai.
        BSR.W   ReadKeyboard
        BSR.W   LeggiJoystick           ; riusa l'input del gioco

        IFNE    PROTO_TUNE_D
        ; ============ MODO TARATURA DI BPLCON1 ======================
        ; DESTRA/SINISTRA cambiano il RITARDO di 1 px alla volta (0..63).
        ; La camera resta ferma a zero, quindi l'offset del puntatore non
        ; varia MAI: l'unica cosa che cambia a schermo e' BPLCON1, e
        ; qualunque salto vedi e' suo.
        ; La griglia deve spostarsi di UN pixel a destra per pressione.
        MOVE.W  ProtoTuneD,D0
        ADD.W   ScrllX,D0               ; destra = +1
        AND.W   #63,D0                  ; wrap 0..63
        MOVE.W  D0,ProtoTuneD
        MOVEQ   #0,D0                   ; CameraX = 0
        MOVEQ   #0,D1                   ; CameraY = 0
        BRA.W   .applica
        ENDC

        ; --- camera dalle direzioni, con clamp ai bordi mappa -------
        ; LeggiJoystick lascia in ScrllX/ScrllY un -1/0/+1 gia' pronto
        ; (somma joystick + tasti freccia), quindi non serve rileggere
        ; l'hardware: si riusa lo stesso ingresso del gioco.
        MOVE.W  ProtoCamX,D0
        ADD.W   ScrllX,D0
        BPL.S   .xpos
        MOVEQ   #0,D0
.xpos:  CMP.W   #PROTO_CAM_XMAX,D0
        BLE.S   .xok
        MOVE.W  #PROTO_CAM_XMAX,D0
.xok:   MOVE.W  D0,ProtoCamX

        MOVE.W  ProtoCamY,D1
        ADD.W   ScrllY,D1
        BPL.S   .ypos
        MOVEQ   #0,D1
.ypos:  CMP.W   #PROTO_CAM_YMAX,D1
        BLE.S   .yok
        MOVE.W  #PROTO_CAM_YMAX,D1
.yok:   MOVE.W  D1,ProtoCamY

.applica:
        ; --- la parte che stiamo testando ---------------------------
        LEA     ProtoBuffer,A0
        BSR.W   ScrollHWCalc            ; D0/D1 -> D2 offset, D3 BPLCON1

        IFNE    PROTO_NO_FINE
        MOVEQ   #0,D3                   ; niente scroll fine: solo blocchi 64px
        ENDC

        IFNE    PROTO_TUNE_D
        ; BPLCON1 dal solo ProtoTuneD: stessa formula di ScrollHWCalc, ma
        ; sul valore sotto test invece che sul ritardo derivato dalla camera
        MOVE.W  ProtoTuneD,D5
        MOVE.W  D5,D3
        AND.W   #$0F,D3
        MOVE.W  D3,D4
        LSL.W   #4,D4
        OR.W    D4,D3                   ; bit 0-3 = PF1, bit 4-7 = PF2
        MOVE.W  D5,D4
        LSR.W   #4,D4
        AND.W   #$03,D4
        MOVE.W  D4,D5
        LSL.W   #8,D5
        LSL.W   #2,D5
        OR.W    D5,D3                   ; bit 10-11 = PF1 alto
        LSL.W   #8,D4
        LSL.W   #6,D4
        OR.W    D4,D3                   ; bit 14-15 = PF2 alto
        ENDC

        LEA     ProtoBuffer,A0
        LEA     BitPlaneTiles,A1
        LEA     CL_BplCon1,A2           ; BPLCON1 va patchato nella lista
        MOVEQ   #5,D4                   ; solo i 5 piani della griglia
        MOVE.L  #PROTO_PLANE_SIZE,D5
        BSR.W   ScrollHWApply

        BSR.W   AspettaVBL

        ; BNE.W e non BNE.S: il loop supera i 128 byte di portata del
        ; branch corto, e cresce ancora se si aggiungono modi di test.
        BTST.B  #6,$bfe001              ; tasto sinistro del mouse = esci
        BNE.W   .loop
        RTS
