;=====================================================================
; MisuraRigheFrame - consegna mirata, da incollare in Gioco.s
;
; Chiude la voce 3 del backlog (BEAMCON0 / DIWHIGH) dal lato che si puo'
; davvero verificare: invece di SCRIVERE un registro alla cieca, MISURA la
; grandezza da cui il progetto dipende.
;
; PERCHE'
;   RASTER_LINES vale 313 per assunzione, non per misura. Nessuno scrive
;   BEAMCON0 ($1DC), quindi il generatore di sincronismo e' quello che ha
;   lasciato chi c'era prima: Kickstart, Workbench, un driver di monitor.
;   Se non e' il PAL di default, TUTTI i numeri di raster del progetto sono
;   sbagliati insieme - VBL_SYNC_LINE, il WAIT del pannello, il rilevatore
;   di frame persi - e non se ne accorge nessuno, perche' sono sbagliati in
;   modo coerente fra loro. Un solo numero a schermo chiude la domanda.
;   BEAMCON0 non e' leggibile (write-only), ma il conteggio delle righe si'.
;
; COME SI LEGGE (compare nel monitor, tasto P, con l'etichetta RI)
;   313 oppure 312 -> generatore PAL, RASTER_LINES e' giusto
;   262 oppure 263 -> NTSC: sono da rifare TUTTI i numeri di raster
;   qualunque altro -> modo di monitor esotico lasciato acceso da qualcun
;                      altro, e allora BEAMCON0 va scritto davvero
;   Una differenza di UNA riga dal valore atteso NON e' un difetto: e' il
;   quadro lungo contro quello corto. Quello che discrimina e' 313 contro
;   262, non 313 contro 312.
;
; Sono cinque innesti. I primi tre sono una riga l'uno.
;=====================================================================


;---------------------------------------------------------------------
; 1) UNA VOCE IN PIU' NEL MONITOR        (Gioco.s, riga 5871)
;
; PROF_ROWS_N e PROF_TEXT_Y sono derivate da PROF_VALUES, quindi la riga
; in piu' e la posizione del blocco di testo si sistemano da sole.
;---------------------------------------------------------------------
; PRIMA:
;PROF_VALUES     EQU     PROF_SLOTS+6    ; 11 fasi + WorstLines + DropCount + DDFSTRT + swap + ritardo + offset
; DOPO:
PROF_VALUES     EQU     PROF_SLOTS+7    ; 11 fasi + WorstLines + DropCount + DDFSTRT + swap + ritardo + offset + righe


;---------------------------------------------------------------------
; 2) L'ETICHETTA                          (Gioco.s, riga 5960)
;
; Due lettere, in coda, nello stesso ordine delle word dopo ProfWorst.
;---------------------------------------------------------------------
; PRIMA:
;        dc.b    'VBINSCPATIDKFACVENBOBLWODRDFSWDLPO'
; DOPO:
        dc.b    'VBINSCPATIDKFACVENBOBLWODRDFSWDLPORI'


;---------------------------------------------------------------------
; 3) LA VARIABILE                         (Gioco.s, subito dopo ProfParOfs,
;                                          riga 6058)
;
; DEVE stare subito dopo ProfParOfs: MostraProfilo legge PROF_VALUES word
; consecutive a partire da ProfWorst, e l'ordine delle word e' l'ordine
; delle etichette.
;---------------------------------------------------------------------
; RI = righe raster contate in un quadro vero. Vedi MisuraRigheFrame.
; DEVE restare subito dopo ProfParOfs: MostraProfilo legge word di seguito.
ProfRighe:      dc.w    0       ; RI: righe per quadro, misurate al boot


;---------------------------------------------------------------------
; 4) LA ROUTINE          (Gioco.s, dentro il blocco IFNE PROFILING che
;                         comincia a riga 1505, accanto a LeggiRiga)
;
; La lettura del pennello e' INLINE e non chiama LeggiRiga: cosi' la
; routine si puo' mettere in qualunque punto del blocco senza dipendere
; dalla distanza di un bsr, ed e' la stessa scelta gia' fatta nello spin
; di FineLavoro (li' il commento dice "il bsr/rts e' ~30 cicli buttati").
;
; Si imposta A6 da sola e lo ripristina: si puo' chiamare da dove capita.
;---------------------------------------------------------------------
MISURA_QUADRI   EQU     8       ; su quanti quadri prendere il massimo

;---------------------------------------------------------------------
; MisuraRigheFrame - quante righe raster ha DAVVERO un quadro
;
; COME: non conta le iterazioni di un loop, che dipenderebbero dalla
; velocita' della CPU e da chi le ruba cicli. Tiene il numero di riga PIU'
; ALTO visto fra due passaggi da zero: le righe sono 0..max, quindi sono
; max+1. Un interrupt che ruba tempo puo' solo far perdere un campione, e
; il massimo non cala per questo. Il campionamento e' abbondante: una riga
; PAL dura ~63 us e il giro di lettura ne costa una frazione minima.
;
; Ripete su MISURA_QUADRI quadri e tiene il massimo, cosi' se il
; generatore alterna quadro lungo e quadro corto esce quello lungo, che e'
; il numero da confrontare con RASTER_LINES.
;
; Gira UNA VOLTA al boot e costa MISURA_QUADRI quadri (~160 ms a 50 Hz).
; Non serve rifarla: il conteggio non cambia mentre il gioco gira.
; Preserva tutti i registri, A6 compreso.
;---------------------------------------------------------------------
MisuraRigheFrame:
        movem.l d0-d3/a6,-(sp)
        lea     $DFF000,a6
        moveq   #0,d2                   ; d2 = massimo su tutti i quadri
        moveq   #MISURA_QUADRI-1,d3

.quadro:
        ; --- 1. aspetta l'inizio di un quadro (riga 0) ---
.att0:  move.l  $04(A6),d0              ; VPOSR+VHPOSR come long = atomico
        lsr.l   #8,d0
        and.w   #$01FF,d0
        tst.w   d0
        bne.s   .att0

        ; --- 2. esci dalla riga 0, se no il passo 3 finisce subito ---
.esci0: move.l  $04(A6),d0
        lsr.l   #8,d0
        and.w   #$01FF,d0
        tst.w   d0
        beq.s   .esci0

        ; --- 3. fino al prossimo zero, tieni il massimo ---
.gira:  move.l  $04(A6),d0
        lsr.l   #8,d0
        and.w   #$01FF,d0
        tst.w   d0
        beq.s   .chiudi
        cmp.w   d2,d0
        bls.s   .gira
        move.w  d0,d2
        bra.s   .gira

.chiudi:
        dbra    d3,.quadro

        addq.w  #1,d2                   ; le righe sono 0..max: sono max+1
        move.w  d2,ProfRighe
        movem.l (sp)+,d0-d3/a6
        rts


;---------------------------------------------------------------------
; 5) LA CHIAMATA                          (Gioco.s, in START, subito dopo
;                                          BSR.W PathBInit, riga 1190)
;
; Dentro IFNE PROFILING, perche' con l'harness fuori dalla build la
; routine non esiste. Deve stare PRIMA del loop principale: costa otto
; quadri, e al boot non se ne accorge nessuno.
;---------------------------------------------------------------------
        IFNE    PROFILING
        BSR.W   MisuraRigheFrame        ; RI nel monitor: righe vere del quadro
        ENDC


;=====================================================================
; DOPO AVERLO INCOLLATO
;
; - le voci del monitor passano da 17 a 18, cioe' da 5 righe di testo a 5
;   (17 e 18 stanno tutte e due in 5 righe da 4 colonne): il blocco non si
;   sposta e PROF_TEXT_Y non cambia. Se un domani si arriva a 21 voci, si
;   sposta da solo.
; - il numero non ha bisogno di un reset: e' misurato una volta e resta.
; - se RI legge 0, la routine non e' stata chiamata (o e' rimasta fuori da
;   un IFNE): 0 e' impossibile come conteggio di righe, quindi e' un
;   valore che si autodenuncia.
;=====================================================================
