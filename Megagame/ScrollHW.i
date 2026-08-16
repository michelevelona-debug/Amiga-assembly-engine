;=====================================================================
; ScrollHW.i - scroll hardware AGA (Path B), passo 1
;
; Converte una posizione di camera (CameraX, CameraY) in pixel nei
; registri che il chipset vuole: BPLxPT + BPLCON1.
;
; Nessuna dipendenza dal gioco: si prova su un buffer statico, e la
; stessa routine serve poi identica nel passo 2.
;
;---------------------------------------------------------------------
; LA MATEMATICA (derivazione, perche' fra sei mesi non sara' ovvia)
;
; BPLCON1 ritarda l'immagine verso DESTRA di D pixel. Con FMODE=3 il
; fetch e' a 64 bit, quindi BPLxPT deve restare allineato a 8 byte e
; puo' muoversi solo a scatti di 64 px.
;
; Voglio che il pixel CameraX del buffer finisca sulla colonna 0.
; Se BPLxPT punta al byte B, il primo pixel fetchato e' 8*B e, per via
; del ritardo, appare alla colonna D. Il pixel fetchato k-esimo appare
; alla colonna D+k. Quindi:
;
;     8B + k = CameraX   e   D + k = 0     ->   8B = CameraX + D
;
; Con D in [0,63] e 8B multiplo di 64, l'unica soluzione e':
;
;     8B = 64 * ceil(CameraX / 64)
;     D  = 8B - CameraX
;
; Verifica: CameraX=0 -> D=0 | CameraX=1 -> D=63 | CameraX=64 -> D=0
;
; MA le colonne 0..D-1 verrebbero da un fetch che non c'e'. Serve
; quindi fetchare UN BLOCCO PRIMA (BPLxPT indietro di 8 byte) e
; anticipare DDFSTRT di un fetch interval. Con il blocco extra i conti
; tornano a zero: il pixel CameraX cade esattamente sulla colonna 0.
;
; Conseguenza: ogni riga del buffer ha 8 BYTE DI GUARDIA A SINISTRA,
; che esistono solo per essere fetchati e scartati. Il pitch cresce di
; 8 byte e la mappa vera comincia all'offset 8.
;
;---------------------------------------------------------------------
; QUELLO CHE VA TARATO NEL PROTOTIPO (non fidarti dei valori sotto)
;
; SCROLL_DDFSTRT e SCROLL_BPLMOD sono le due incognite. Il valore di
; DDFSTRT per FMODE=3 non si ricava in modo affidabile dalla doc AGA
; (i valori attuali del gioco, $28/$A8 con "5 fetch", non sono
; ricostruibili da una formula pulita), quindi vanno trovati a video:
;
;   1. Metti SCROLL_TEST_X a un multiplo di 64 e verifica che la
;      griglia sia allineata e senza colonne spurie ai bordi.
;   2. Porta la camera a 64n+1: se compare una striscia di spazzatura
;      a SINISTRA, o se spariscono pixel dal bordo sinistro, DDFSTRT e'
;      troppo tardi -> togli 32 unita' (= 64 px = un fetch intero).
;      Se l'immagine e' spostata di un blocco, e' troppo presto -> +32.
;      RICORDA: 1 unita' di DDFSTRT = 2 px lores, quindi un fetch da
;      64 px sono 32 unita'. Ragiona sempre in pixel e poi dividi per 2.
;   3. Con lo scroll continuo, se il bordo DESTRO perde 64 px o
;      mostra ripetizioni, e' BPLMOD -> aggiusta di 8 alla volta.
;
; Cambia UNA cosa alla volta e di 8 per volta: sono gli unici due
; numeri in ballo e si convergono in pochi tentativi.
;=====================================================================

SCROLL_GUARD_BYTES  EQU     8               ; blocco di prefetch a sinistra
; IL PITCH DEVE ESSERE QUELLO VERO DEL BUFFER, NON UN VALORE CABLATO.
; Era 48+SCROLL_GUARD_BYTES = 56, mentre SFONDO_PITCH vale 64 da quando la
; riga deve contenere guardia + mappa intera. La parte verticale fa
; CameraY * SCROLL_PITCH: con 56 invece di 64 si perdevano 8 byte per ogni
; riga di camera, cioe' 64 px di scivolamento ORIZZONTALE per pixel di
; scroll verticale. Non si vedeva in platform perche' CAM_STEP_Y=8 fa
; muovere la camera solo di 8 px alla volta e l'errore cade sempre su un
; numero intero di righe (8*8 = 64 = un pitch esatto). Si vedeva solo in
; 8-direzioni (tasto G), dove ScrllY arriva dall'input a 1 px per frame.
; ScrollHW.i e' incluso dopo la EQU di SFONDO_PITCH, quindi il riferimento
; e' risolvibile.
SCROLL_PITCH        EQU     SFONDO_PITCH            ; byte per riga del buffer
; Il gioco usa DDFSTRT=$38, che e' il valore SENZA prefetch: torna con la
; formula standard (DIWSTRT_H - $11)/2 = ($81-$11)/2 = $38.
;
; QUANTO VALE UNA UNITA' DI DDFSTRT: invertendo quella stessa formula,
; DIWSTRT_H = DDFSTRT*2 + $11, e DIWSTRT_H e' in PIXEL LORES. Quindi
; UNA unita' di DDFSTRT vale 2 PIXEL LORES. (Non 4: contarla come
; "2 cicli di colore = 4 px" e' l'errore che ha fatto sparire 32 px dal
; bordo sinistro a meta' fra due blocchi.)
;
; Il ritardo BPLCON1 arriva a 63, quindi il prefetch deve coprire un
; fetch FMODE=3 INTERO = 64 px = 32 unita':
;   $38 - 32 = $18
; Con $28 (32 px di anticipo) il prefetch si esaurisce a ritardo 32, ed
; e' esattamente li' che si vedevano sparire due tile a sinistra.
SCROLL_DDFSTRT      EQU     $38-32          ; = $18. Un fetch intero = 64 px
; DDFSTOP allargato di UN blocco ($b8 -> $d8) per coprire la finestra piu'
; larga. Con FMODE=3 in lores il passo di fetch e' 32 color clock e ogni fetch
; porta 8 byte = 64 px, quindi il numero di fetch e' (STOP-STRT)/32+1.
SCROLL_DDFSTOP      EQU     $d8
SCROLL_FETCHES      EQU     ((SCROLL_DDFSTOP-SCROLL_DDFSTRT)/32)+1
SCROLL_FETCH_BYTES  EQU     SCROLL_FETCHES*8        ; byte letti per riga e per piano
; BPLxMOD = pitch - byte fetchati per riga. I fetch sono 6 blocchi da 8
; byte = 48 (320 px visibili + 64 di prefetch), quindi il modulo segue il
; pitch: con 56 valeva 8, con 64 vale 16. Va tenuto derivato, non fisso.
; Il modulo e' pitch meno i byte davvero fetchati: era cablato a 48, cioe'
; ai 6 fetch di prima. Ora deriva, quindi allargare o stringere il DDF non
; richiede di ricordarsi di aggiornare anche qui.
SCROLL_BPLMOD       EQU     SFONDO_PITCH-SCROLL_FETCH_BYTES

;---------------------------------------------------------------------
; ScrollHWCalc - da CameraX/CameraY ai valori hardware
; IN:  D0.w = CameraX (px), D1.w = CameraY (px)
;      A0   = base del buffer (piano 1, angolo alto-sinistro, guardia
;             INCLUSA: e' l'indirizzo del byte di guardia)
; OUT: D2.l = offset in byte da sommare alla base di OGNI piano
;      D3.w = valore da scrivere in BPLCON1
; Preserva D0/D1/A0.
;---------------------------------------------------------------------
ScrollHWCalc:
        MOVEM.L D4-D5,-(SP)

        ; --- orizzontale: blocco da 64 px + ritardo 0..63 -----------
        MOVE.W  D0,D4
        ADD.W   #63,D4
        LSR.W   #6,D4                   ; D4 = ceil(CameraX/64) in blocchi
        MOVE.W  D4,D5
        LSL.W   #6,D5                   ; D5 = 8B = blocchi*64 (in pixel)
        SUB.W   D0,D5                   ; D5 = D = ritardo 0..63

        LSL.W   #3,D4                   ; D4 = blocchi*8 = offset byte
        ; il blocco di prefetch: si resta dentro il buffer perche' la
        ; base include gia' gli 8 byte di guardia
        MOVEQ   #0,D2
        MOVE.W  D4,D2                   ; D2 = offset orizzontale in byte

        ; --- BPLCON1: stesso shift su piani pari e dispari ----------
        ; MAPPA DEI BIT AGA, che NON e' quella intuitiva. In AGA lo scroll
        ; ha granularita' 35 ns (un quarto di pixel lores) e i bit sono
        ; stati RINOMINATI: il vecchio PF1H0 e' diventato PF1H2, mentre i
        ; nuovi PF1H0/PF1H1 (bit 8-9) sono il sub-pixel e in lores DEVONO
        ; restare a zero. I bit alti dello scroll stanno in 10-11 e 14-15,
        ; NON in 8-9 e 10-11.
        ;
        ;   PF1H (piani DISPARI)          PF2H (piani PARI)
        ;     bit 0-3   = 0..15 px          bit 4-7   = 0..15 px
        ;     bit 8-9   = sub-pixel -> 0    bit 12-13 = sub-pixel -> 0
        ;     bit 10-11 = +16, +32 px       bit 14-15 = +16, +32 px
        ;
        ; Sbagliare questo mette i bit alti nel campo sub-pixel: i piani
        ; dispari si shiftano di 16 px in piu' dei pari e compaiono frange
        ; di colore sbagliato sul bordo sinistro. Non si vede quando il
        ; ritardo e' multiplo di 16, quindi il difetto sembra intermittente.
        MOVE.W  D5,D3
        AND.W   #$0F,D3                 ; parte fine, 0..15 px lores
        MOVE.W  D3,D4
        LSL.W   #4,D4
        OR.W    D4,D3                   ; bit 0-3 = PF1, bit 4-7 = PF2
        MOVE.W  D5,D4
        LSR.W   #4,D4
        AND.W   #$03,D4                 ; parte alta, multipli di 16 px
        MOVE.W  D4,D5
        LSL.W   #8,D5
        LSL.W   #2,D5                   ; <<10 (lo shift immediato arriva a 8)
        OR.W    D5,D3                   ; bit 10-11 = PF1H6,PF1H7
        LSL.W   #8,D4
        LSL.W   #6,D4                   ; <<14
        OR.W    D4,D3                   ; bit 14-15 = PF2H6,PF2H7

        ; --- verticale: una riga = un pitch, sempre allineato -------
        MOVE.W  D1,D4
        MULU.W  #SCROLL_PITCH,D4
        ADD.L   D4,D2

        MOVEM.L (SP)+,D4-D5
        RTS

;---------------------------------------------------------------------
; ScrollHWApply - scrive i puntatori e BPLCON1 NELLA COPPERLIST
;
; ATTENZIONE: BPLCON1 va patchato nella copperlist, non scritto via CPU.
; La copperlist del gioco contiene una MOVE $102,0 che ogni frame
; azzererebbe lo scroll fine subito dopo la scrittura della CPU -> si
; vedrebbero solo scatti da 64 px. Scriverlo nella lista lo applica
; anche in modo sincrono all'inizio del frame, senza tearing.
;
; IN:  D2.l = offset (da ScrollHWCalc)
;      D3.w = BPLCON1
;      A0   = base del buffer (piano 1, guardia inclusa)
;      A1   = prima MOVE di BPL1PTH nella copperlist
;             (la lista deve avere le coppie PTH/PTL consecutive)
;      A2   = entry BPLCON1 nella copperlist (la MOVE $102,x)
;      D4.w = quanti piani scrivere
;      D5.l = distanza fra i piani in byte
;---------------------------------------------------------------------
ScrollHWApply:
        MOVEM.L D0-D4/A0-A1,-(SP)
        MOVE.W  D3,2(A2)                ; BPLCON1: patch del valore nella lista
        ADDA.L  D2,A0                   ; A0 = primo byte visibile del piano 1
        SUBQ.W  #1,D4
.plane:
        MOVE.L  A0,D0
        SWAP    D0
        MOVE.W  D0,2(A1)                ; parte alta in BPLxPTH
        SWAP    D0
        MOVE.W  D0,6(A1)                ; parte bassa in BPLxPTL
        ADDA.L  D5,A0                   ; piano successivo
        ADDA.W  #8,A1                   ; coppia di MOVE successiva
        DBRA    D4,.plane
        MOVEM.L (SP)+,D0-D4/A0-A1
        RTS

;---------------------------------------------------------------------
; ScrollHWGriglia - riempie un piano con una griglia da 16 px
;
; Serve solo al prototipo: una griglia rende immediatamente visibile
; ogni difetto dello scroll. Una linea che "salta" di un pixel ogni 64
; e' un errore nel ritardo; una colonna che appare e sparisce ai bordi
; e' DDFSTRT; una ripetizione a destra e' BPLMOD.
;
; IN: A0 = base del piano (guardia inclusa), D0.w = righe
;---------------------------------------------------------------------
ScrollHWGriglia:
        MOVEM.L D0-D3/A0-A1,-(SP)
        SUBQ.W  #1,D0
        MOVEQ   #0,D3                   ; contatore righe
.riga:
        MOVEA.L A0,A1
        MOVE.W  #SCROLL_PITCH/2-1,D1
        ; ogni 16 righe una riga piena, altrimenti solo le colonne
        MOVE.W  D3,D2
        AND.W   #15,D2
        BNE.S   .colonne
        MOVE.W  #$FFFF,D2               ; riga orizzontale piena
        BRA.S   .scrivi
.colonne:
        MOVE.W  #$8000,D2               ; una colonna verticale ogni 16 px
.scrivi:
        MOVE.W  D2,(A1)+
        DBRA    D1,.scrivi
        ADDA.W  #SCROLL_PITCH,A0
        ADDQ.W  #1,D3
        DBRA    D0,.riga
        MOVEM.L (SP)+,D0-D3/A0-A1
        RTS
