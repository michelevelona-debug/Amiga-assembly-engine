; Misura.i - Misura del quadro: LeggiRiga, FineLavoro
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

	IFNE	PROFILING
; LeggiRiga -> d0.w = riga raster corrente (0..312)
; $DFF004 letto come LONG = VPOSR+VHPOSR in un colpo -> atomico, niente
; race sul bit V8 (che sta in VPOSR bit 0 = bit 16 del long).
; Richiede A6 = $DFF000.  Distrugge solo D0.
LeggiRiga:
        move.l  $04(A6),d0
        lsr.l   #8,d0
        and.w   #$01FF,d0
        rts

; FineLavoro - da chiamare subito dopo AspettaBlitter, PRIMA di AspettaVBL.
; Misura quante righe raster ha consumato il lavoro del quadro, tiene il peggior
; caso mai visto e conta i quadri persi.
; Il lavoro parte a VBL_SYNC_LINE, che e' DERIVATA ($2C+BG_VIS_ROWS) e si sposta
; da sola se cambia CUT_BOTTOM_ROWS: per questo il suo valore qui non c'e'.
; QUADRO PERSO, senza interrupt VERTB. Il conto (riga - VBL_SYNC_LINE) mod
; RASTER_LINES sta per forza in 0..RASTER_LINES-1 e da solo non distingue un
; quadro rientrato da uno che ha sforato. La durata vera si ricostruisce a .ptot
; contando i wrap: i latch delle fasi crescono in modo monotono finche' il quadro
; sta in un giro di raster, quindi ogni delta NEGATIVO fra due latch consecutivi
; e' un wrap. Durata = wrap*RASTER_LINES + righe_dal_sync, e il quadro e' perso
; quando supera RASTER_LINES.
; Il conteggio dei wrap regge perche' tutte e PROF_SLOTS le PROFMARK stanno sul
; percorso dritto del main loop: nessun latch resta fermo, nessun delta negativo
; e' finto. UNA PROFMARK DENTRO UN IF FA SALTARE QUESTA GARANZIA.
; FrameLines si scrive DUE volte: la prima con le righe dal sync, la seconda -
; solo sui quadri misurati davvero - con la durata ricostruita, che puo' superare
; RASTER_LINES.
; Richiede A6 = $DFF000.  Preserva tutti i registri.
FineLavoro:
        movem.l d0-d5/a0-a1,-(sp)

        ; --- 1. righe consumate da questo frame ---------------------
        bsr.s   LeggiRiga
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .nowrap
        add.w   #RASTER_LINES,d0
.nowrap:
        move.w  d0,FrameLines
        move.w  d0,d4                   ; d4 = fine del frame, serve sotto

        ; --- reset degli high-water su richiesta (tasto R) ----------
        ; Sta PRIMA dell'uscita per ProfShow: cosi' puoi azzerare anche
        ; mentre stai guardando i numeri, e riparti pulito.
        tst.w   WorstReset
        beq.s   .noreset
        clr.w   WorstReset
        clr.w   WorstLines
        clr.w   DropCount
        clr.w   ProfSwapRaster
        lea     ProfWorst,a0
        moveq   #PROF_SLOTS-1,d2
.pclr:  clr.w   (a0)+
        dbra    d2,.pclr
.noreset:

        ; Se i numeri sono a schermo la misura e' CONGELATA per intero:
        ; disegnarli costa ~90 righe, che falserebbero proprio i valori che
        ; stai leggendo e farebbero scattare il rilevatore di frame persi.
        ;
        ; QUI C'ERA `move.w #$0000,$180(A6)`: fondo nero perche' le cifre erano
        ; colore 31 dentro il MONDO e su cielo chiaro non si leggevano. Dal 23
        ; settembre il monitor sta nel pannello con due voci sue (PROF_PAN_FONDO
        ; e PROF_PAN_CIFRA), quindi quella riga non serviva piu' a niente - ma
        ; faceva ancora danno: COLOR00 lo riscrive il COPPER in cima a ogni
        ; quadro, mentre la CPU lo scriveva dove arrivava il lavoro. Il confine
        ; fra cielo e nero camminava col carico del quadro e si vedeva come uno
        ; sfarfallio. **Un registro che il copper riscrive ogni quadro non si
        ; scrive dalla CPU a meta' schermo**: e' la stessa lezione di BPLCON1.
        tst.b   ProfShow
        beq.s   .measure
        bra     .out
.measure:

        ; --- 2. profilo per fase + durata REALE del frame -----------
        ; Un solo passaggio: normalizza il latch rispetto al sync, calcola il
        ; costo della fase che si chiude qui (distanza dal latch precedente)
        ; e aggiorna il suo high-water.
        ; I latch sono monotoni crescenti finche' il frame sta dentro un giro
        ; di raster. Un delta NEGATIVO significa che il raster ha wrappato:
        ; il costo vero di quella fase e' delta+RASTER_LINES, e il frame dura
        ; un giro in piu'. Contando i wrap si ricostruisce la durata reale
        ; anche quando il frame sfora -- ed e' proprio il caso che interessa,
        ; perche' e' li' che stanno i costi peggiori.
        ; LIMITE: una singola fase che da sola superi RASTER_LINES non viene
        ; vista (il suo delta tornerebbe positivo ma sbagliato). Con lo scroll
        ; a ~243 righe siamo sotto, ma se un giorno una fase si avvicina a 313
        ; questo numero va preso con le pinze.
        moveq   #0,d5                   ; d5 = quanti wrap in questo frame
        lea     ProfRaw,a0
        lea     ProfWorst,a1

        ; Primo latch: va solo normalizzato, non chiude nessuna fase (il costo
        ; di una fase e' la distanza FINO al marker successivo).
        move.w  (a0),d0
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .pnw0
        add.w   #RASTER_LINES,d0
.pnw0:
        move.w  d0,(a0)+
        move.w  d0,d1                   ; d1 = latch precedente

        moveq   #PROF_SLOTS-2,d2        ; i PROF_SLOTS-1 latch rimanenti
.pnorm:
        move.w  (a0),d0
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .pnw
        add.w   #RASTER_LINES,d0
.pnw:
        move.w  d0,(a0)+                ; riscrive normalizzata (comoda al debugger)
        move.w  d0,d3
        sub.w   d1,d3                   ; costo della fase che si chiude qui
        bpl.s   .pok
        addq.w  #1,d5                   ; il raster ha wrappato qui
        add.w   #RASTER_LINES,d3        ; ...quindi il costo vero e' questo
.pok:
        cmp.w   (a1),d3
        bls.s   .pnext
        move.w  d3,(a1)                 ; nuovo peggior costo per questa fase
.pnext:
        addq.w  #2,a1
        move.w  d0,d1                   ; questo latch diventa il riferimento
        dbra    d2,.pnorm

        ; L'ultima fase si chiude sulla fine del lavoro
        move.w  d4,d3
        sub.w   d1,d3
        bpl.s   .plok
        addq.w  #1,d5
        add.w   #RASTER_LINES,d3
.plok:
        cmp.w   (a1),d3
        bls.s   .ptot
        move.w  d3,(a1)

.ptot:  ; --- 3. durata reale = righe dal sync + un giro per ogni wrap
        move.w  d5,d3
        mulu.w  #RASTER_LINES,d3
        add.w   d4,d3                   ; d3 = durata VERA del frame
        move.w  d3,FrameLines           ; sovrascrive con il valore ricostruito
        move.w  d3,d4

        ; L'high-water del totale si aggiorna SEMPRE, anche quando il frame
        ; sfora: ora la durata e' un numero vero e non piu' spazzatura.
        cmp.w   WorstLines,d4
        bls.s   .nowl
        move.w  d4,WorstLines
.nowl:
        ; --- 5. frame perso? ---------------------------------------
        ; Ora e' un confronto diretto: il lavoro e' durato piu' di un frame.
        cmp.w   #RASTER_LINES,d4
        blo.s   .frameok
        addq.w  #1,DropCount
        IFNE    PROF_COLORS
        move.w  #$0F00,$180(A6)         ; ROSSO PIENO = frame perso
        ENDC
        bra     .out

.frameok:
        ; --- 6. fascia ROSSA fino al peggior caso, poi BIANCO -------
        ; Lo spin si ferma comunque prima della riga di sync: se WorstLines
        ; e' oltre un frame intero (succede scrollando) la fascia bianca non
        ; compare proprio, ed e' l'informazione giusta -- margine zero.
        move.w  WorstLines,d1
        cmp.w   #RASTER_LINES-1,d1
        blo.s   .spinok
        move.w  #RASTER_LINES-1,d1
.spinok:
        IFNE    PROF_COLORS
        move.w  #$0800,$180(A6)         ; rosso scuro = margine bruciato
        ENDC
.wait:  move.l  $04(A6),d0              ; LeggiRiga inline: in uno spin loop
        lsr.l   #8,d0                   ; il bsr/rts e' ~30 cicli buttati
        and.w   #$01FF,d0
        sub.w   #VBL_SYNC_LINE,d0
        bpl.s   .nw2
        add.w   #RASTER_LINES,d0
.nw2:   cmp.w   d1,d0
        blo.s   .wait                   ; confronto in "righe dal sync", non
                                        ; uguaglianza di riga: se un interrupt
                                        ; ci fa saltare la riga esatta non
                                        ; restiamo appesi per un frame intero
        IFNE    PROF_COLORS
        move.w  #$0FFF,$180(A6)         ; BIANCO = margine RESIDUO
        ENDC
.out:
        movem.l (sp)+,d0-d5/a0-a1
        rts
	ENDC
