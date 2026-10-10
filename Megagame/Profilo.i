; Profilo.i - Monitor delle prestazioni
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

	IFNE	PROFILING
; MostraProfilo - stampa i numeri del profilo NELL'AREA DI GIOCO
; L'indirizzo delle variabili non e' prevedibile (il loader riloca le sezioni a
; ogni avvio), quindi li scrive il gioco stesso. Premi P per mostrarli: mentre
; sono a schermo la misura e' CONGELATA.
; Ogni voce e' "XXnnn", 5 caratteri da 8 px = 40 px; quattro voci per riga.
; PROF_COLS puo' salire a 8 per usare tutta la larghezza.
;   VB VBLEND   IN INPUT   SC SCROLL   TI TILES   DK DARK   FA FALO
;   PA PARALLAX CV COPIAVIDEO   EN ENTITIES   BO BOB   BL BLTDRAIN
;   WO WORST (totale)   DR DROP (quadri persi)
; POSIZIONE: dentro l'area di gioco, NON sotto: sotto BG_VIS_ROWS il display
; mostra PannelloBuf e non il world buffer. E' il cambio di puntatori a rendere
; invisibile la coda, non il DIW, che arriva fino a PANNELLO_BOT_RASTER.
; E' l'ultima a scrivere prima dello swap, quindi i numeri stanno sopra a tutto.
; Scrive su TUTTI E 5 i piani: colore 31 su fondo 0, leggibile ovunque e senza
; dover pulire prima.
PROF_VALUES     EQU     PROF_SLOTS+9    ; 11 fasi + WorstLines + DropCount + DDFSTRT
                                        ; + swap + ritardo + offset + i due della
                                        ; ricostruzione (RQ, RV) + il blocco (MP)
; L'ULTIMA CELLA LIBERA E' STATA SPESA QUI. Il blocco e' PROF_COLS(4) x
; PROF_ROWS_N(5) = 20 celle e adesso PROF_VALUES vale 20: pieno. Le righe non si
; possono aggiungere (GUARDIA_PROF_PAN_ALTEZZA le ferma a SPIA_Y0 = 40) e il
; salto legale successivo sulle colonne e' 8, cioe' la larghezza intera del
; pannello. Chi ha bisogno di una voce in piu' paga quel salto.
PROF_COLS       EQU     4               ; voci per riga (4 x 80px = 320)
PROF_ROWS_N     EQU     (PROF_VALUES+PROF_COLS-1)/PROF_COLS
; Il rettangolo che il testo sporca, per registrarlo come fa ogni BOB. E'
; DERIVATO dalla griglia: cambiando PROF_COLS, il numero di cifre o il font
; non c'e' un secondo valore da aggiornare a mano.
PROF_CAR_VOCE   EQU     5               ; due lettere di etichetta piu' tre cifre
; IL BLOCCO STA NEL PANNELLO. `PROF_TEXT_Y`, `PROF_DIRTY_W` e `PROF_DIRTY_ROWS`
; stavano qui e posizionavano il testo dentro il MONDO, inseguendo la camera e
; registrando un rettangolo sporco: sono spariti tutti e tre il 23 settembre
; insieme al difetto che descrivevano (vedi la testa di MostraProfilo).
PROF_PAN_W      EQU     PROF_COLS*PROF_CAR_VOCE*FONT_CW ; byte per riga di testo
PROF_PAN_H      EQU     PROF_ROWS_N*FONT_H              ; righe del blocco
PROF_PAN_FONDO  EQU     4               ; grigio scuro della rotella, $334
PROF_PAN_CIFRA  EQU     6               ; grigio chiaro della rotella, $eee
; Il piano su cui si scrivono le cifre e' l'UNICO bit in cui i due indici
; differiscono: cosi' il fondo si riempie una volta sola e il testo cambia quel
; bit e basta. Cambiando i due colori la guardia dice subito se la coppia
; regge ancora (ne servono due che differiscano di UN bit).
PROF_PAN_PIANO  EQU     1
        IFNE    (PROF_PAN_FONDO^PROF_PAN_CIFRA)-(1<<PROF_PAN_PIANO)
GUARDIA_PROF_PAN_COLORI EQU     1/0
        ENDC
; Il riempimento del fondo va a long: la larghezza dev'essere multipla di 4.
        IFNE    PROF_PAN_W-(PROF_PAN_W/4)*4
GUARDIA_PROF_PAN_LARG   EQU     1/0
        ENDC
; ...e il ripristino e' un blit, quindi la larghezza in word sta in 6 bit.
        IFGT    PROF_PAN_W/2-64
GUARDIA_PROF_PAN_BLTSIZE EQU    1/0
        ENDC
; Il blocco deve stare SOPRA `SPIA_Y0`: da quella riga in giu' il copper
; ridipinge le voci 4/5/6 col rosso della quinta spia, e il fondo cambierebbe
; colore a meta' testo. E' la stessa regola di "la fascia raster e' la vera
; risorsa", letta al contrario: chi scrive nel pannello deve sapere in quale
; fascia sta.
        IFGT    PROF_PAN_H-SPIA_Y0
GUARDIA_PROF_PAN_ALTEZZA EQU    1/0
        ENDC

MostraProfilo:
        MOVEM.L D0-D7/A0-A4,-(SP)

        ; IL MONITOR STA NEL PANNELLO, non nel mondo. Ci si e' arrivati il 23
        ; settembre, dopo che le cifre andavano e venivano e lo sfondo sembrava
        ; lampeggiare. Nel world buffer il testo aveva contro TRE meccanismi, e
        ; bastava un nemico in piu' da blittare a cambiare il risultato:
        ;   - il DOPPIO BUFFER: MostraProfilo gira dopo ScrollPathBApply, quindi
        ;     scriveva nel buffer GIA' A VIDEO ed era in corsa col pennello. Se
        ;     il pennello aveva gia' passato la riga del testo, quelle cifre in
        ;     quel quadro non si vedevano affatto;
        ;   - PathBRestoreAll: il rettangolo andava registrato e ripulito, e lo
        ;     si vedeva cancellare sotto il pennello;
        ;   - lo SCROLL: la posizione andava inseguita con PathBCamX/PathBCamY.
        ; PannelloBuf non ha nessuno dei tre. Non e' doppio bufferizzato, i suoi
        ; puntatori in copperlist sono fissi dal boot, non scorre, e
        ; PathBRestoreAll non lo guarda. E il pennello ci passa a raster
        ; PANNELLO_ART_RASTER, due righe dopo VBL_SYNC_LINE: qui si scrive
        ; sempre dietro di lui, per costruzione e non per fortuna.
        ;
        ; I COLORI NON SONO PIU' COLOR00. Fondo PROF_PAN_FONDO e cifre
        ; PROF_PAN_CIFRA sono due voci VERE della palette del pannello, quindi
        ; il fondo non dipende piu' da chi scrive $180 e il cielo non c'entra.
        ;
        ; PREZZO, dichiarato: mentre i numeri sono a schermo il blocco COPRE gli
        ; strumenti che stanno sotto. Spegnendo P torna l'ARTE (vedi
        ; ProfPanRipristina), non la composizione: gli strumenti dentro il
        ; blocco ricompaiono quando si ridisegnano da soli. E' uno strumento di
        ; misura, non una schermata di gioco.

        ; --- 1. il fondo: PROF_PAN_FONDO su tutto il rettangolo ------------
        LEA     PannelloBuf+PANNELLO_ART_BYTE_OFS,A0
        LEA     ProfPanFondo,A3                 ; un long per piano, DERIVATO
        MOVEQ   #PANNELLO_BITPLANES-1,D7
.piano_fondo:
        MOVE.L  (A3)+,D2                        ; -1 se il piano e' acceso, 0 se no
        MOVEA.L A0,A1
        MOVE.W  #PROF_PAN_H-1,D5
.riga_fondo:
        MOVEA.L A1,A4
        MOVE.W  #PROF_PAN_W/4-1,D6
.long_fondo:
        MOVE.L  D2,(A4)+
        DBRA    D6,.long_fondo
        ADDA.W  #PANNELLO_BUF_PITCH,A1
        DBRA    D5,.riga_fondo
        ADDA.L  #PANNELLO_BUF_PLANE,A0
        DBRA    D7,.piano_fondo

        ; --- 2. il cursore: SOLO il piano che distingue i due indici -------
        LEA     PannelloBuf+PANNELLO_ART_BYTE_OFS,A4
        ADDA.L  #PROF_PAN_PIANO*PANNELLO_BUF_PLANE,A4
        ; A4 e' l'inizio della riga di testo corrente e avanza di riga in riga.
        ; Qui c'era anche una copia in A0, che serviva SOLO a ritrovare l'inizio
        ; del blocco per registrare il rettangolo sporco: senza quel rettangolo
        ; non serve piu' a nessuno.
        MOVE.W  #PANNELLO_BUF_PITCH,D0
        MOVE.L  #PANNELLO_BUF_PLANE,D2

.parametri:
        MOVEQ   #1,D1                   ; UN piano solo: vedi PROF_PAN_PIANO

        ; DDFSTRT non e' leggibile dal registro: lo prendo dalla copperlist,
        ; che e' la fonte di verita' di cio' che il copper scrive ogni frame.
        MOVE.W  CL_Ddf+2,ProfDdf
        MOVE.W  PathBDelay,ProfDelay
        MOVE.W  ParSprOfs,ProfParOfs
        ; MP: quale blocco si sta giocando. Con due mappe uguali al byte e'
        ; l'UNICO modo di sapere se la porta ha portato da qualche parte -
        ; guardare lo schermo non risponde alla domanda.
        MOVE.W  MappaCorrente,ProfMappa

        LEA     ProfLabels,A3
        LEA     ProfWorst,A2                    ; WorstLines/DropCount/DDF seguono
        MOVEA.L A4,A1
        MOVEQ   #0,D6                           ; colonna corrente
        MOVEQ   #PROF_VALUES-1,D7
.valore:
        MOVEQ   #0,D3                           ; etichetta, 1a lettera
        MOVE.B  (A3)+,D3
        BSR.W   TestoChar
        ADDA.W  #FONT_CW,A1
        MOVEQ   #0,D3                           ; etichetta, 2a lettera
        MOVE.B  (A3)+,D3
        BSR.W   TestoChar
        ADDA.W  #FONT_CW,A1

        MOVE.W  (A2)+,D3                        ; il valore
        MOVEQ   #3,D4                           ; 3 cifre
        BSR.W   TestoNumero
        ADDA.W  #3*FONT_CW,A1

        ADDQ.W  #1,D6
        CMP.W   #PROF_COLS,D6
        BLT.S   .prossimo
        MOVEQ   #0,D6                           ; a capo
        ; il salto di riga deve usare il pitch REALE del buffer (D0 =
        ; SFONDO_PITCH, oggi 72 e DERIVATO da MAPPA_COLS), non una costante:
        ; ogni byte di differenza sposta la riga di testo di 8 px, e quando
        ; qui c'era 48 contro un pitch di 56 ogni riga finiva 64 px a destra
        ; della precedente
        MOVE.W  D0,D5
        MULU.W  #FONT_H,D5
        ADDA.L  D5,A4
        MOVEA.L A4,A1
.prossimo:
        DBRA    D7,.valore

        ; NESSUN RETTANGOLO SPORCO DA REGISTRARE: il pannello non lo ripulisce
        ; nessuno, e il fondo lo riscrive questa stessa routine a ogni quadro.
        ; Qui c'era la PathBRegistraDirty che serviva quando il testo stava nel
        ; world buffer.
        MOVEM.L (SP)+,D0-D7/A0-A4
        RTS

; Un long per piano: tutti uno se quel piano e' acceso in PROF_PAN_FONDO, zero
; se no. DERIVATO dall'indice del colore, non scritto a mano: cambiando
; PROF_PAN_FONDO cambia il riempimento senza toccare niente.
ProfPanFondo:
        dc.l    -((PROF_PAN_FONDO>>0)&1)
        dc.l    -((PROF_PAN_FONDO>>1)&1)
        dc.l    -((PROF_PAN_FONDO>>2)&1)
        dc.l    -((PROF_PAN_FONDO>>3)&1)
ProfPanFondoFine:
        IFNE    (ProfPanFondoFine-ProfPanFondo)/4-PANNELLO_BITPLANES
GUARDIA_PROF_PAN_PIANI  EQU     1/0
        ENDC

; ProfPanRipristina - rimette l'arte vera sotto il blocco quando si spegne P.
; Stessa sorgente di DisegnaPannello (`pannello`, 4 piani contigui da
; PANNELLO_BYTES_PER_ROW), ma solo il rettangolo del monitor invece dell'intera
; fascia: cosi' gli strumenti FUORI dal blocco non vengono toccati.
; Quelli DENTRO tornano solo quando si ridisegnano da soli, perche' qui torna
; l'arte e non la composizione. Vale la pena saperlo prima di spaventarsi.
; Richiede A6 = $DFF000. Gira una volta sola, sul fronte di spegnimento.
ProfPanRipristina:
        MOVEM.L D0/A1-A2,-(SP)
        LEA     PannelloBuf+PANNELLO_ART_BYTE_OFS,A1
        LEA     pannello,A2
        BSR.W   AspettaBlitter
        MOVE.L  #$ffffffff,$44(A6)              ; BLTAFWM/BLTALWM
        MOVE.L  #$09F00000,$40(A6)              ; BLTCON0/1: D = A
        MOVE.W  #PANNELLO_BYTES_PER_ROW-PROF_PAN_W,$64(A6)      ; BLTAMOD
        MOVE.W  #PANNELLO_BUF_PITCH-PROF_PAN_W,$66(A6)          ; BLTDMOD
        MOVEQ   #PANNELLO_BITPLANES-1,D0
.piano:
        BSR.W   AspettaBlitter
        MOVE.L  A2,$50(A6)                      ; BLTAPT
        MOVE.L  A1,$54(A6)                      ; BLTDPT
        MOVE.W  #(PROF_PAN_H<<6)|(PROF_PAN_W/2),$58(A6)
        ADDA.L  #PANNELLO_BYTES_PER_ROW*PANNELLO_HEIGHT,A2
        ADDA.L  #PANNELLO_BUF_PLANE,A1
        DBRA    D0,.piano
        BSR.W   AspettaBlitter
        MOVEM.L (SP)+,D0/A1-A2
        RTS

; Etichette a 2 lettere, nello stesso ordine di ProfWorst + i due extra.
; Maiuscole per leggibilita' a 8x8; il font Metal ha anche le minuscole.
ProfLabels:
        dc.b    'VBINSCPATIDKFACVENBOBLWODRDFSWDLPORQRVMP'
        even

; ============================================================================
; QUANTO COSTA RICOSTRUIRE IL MONDO (voce 0 del backlog)
; La sequenza DisegnaSfondo + due PathBBuildMaster + PathBBuildDark dura PIU'
; DI UN QUADRO, e l'harness per quadro non la puo' misurare: FineLavoro
; normalizza tutto rispetto al sync, e una fase piu' lunga di RASTER_LINES gli
; sfugge - lo dice il suo stesso commento ("LIMITE").
;
; Qui si contano i QUADRI, e si contano DUE VOLTE per strade indipendenti:
;   RQ dal TOD del CIA-A, un contatore clockato dal sync verticale: non puo'
;      perdere un quadro qualunque cosa faccia la CPU;
;   RV contando i giri del pennello fra un campione e l'altro di LeggiRiga.
; Se i due COINCIDONO la misura e' buona. Se RV e' piu' BASSO, un singolo blit
; ha superato un quadro intero e il campionamento ha perso un giro: e' il
; limite dichiarato del metodo a pennello, e qui si vede invece di nascondersi.
; Se RQ e' ZERO e RV no, su questa macchina il TOD non sta girando e RQ non va
; creduto. Due derivazioni indipendenti che si controllano a vicenda: nessuna
; delle due, da sola, sarebbe una misura.
;
; A6 deve valere $DFF000: LeggiRiga legge $04(A6).
; ============================================================================
MisuraRicAvvia:
        MOVEM.L D0,-(SP)
        CLR.W   ProfRicTOD
        CLR.W   ProfRicVPOS
        BSR.S   MisuraRicTOD
        MOVE.W  D0,MisuraRicTOD0
        BSR.W   LeggiRiga
        MOVE.W  D0,MisuraRicRiga
        MOVE.B  #1,MisuraRicAttiva
        MOVEM.L (SP)+,D0
        RTS

; Un campione. Va messo fra due pezzi di lavoro che da soli NON superano un
; quadro: e' l'unica condizione che RV chiede per essere giusto.
; Preserva tutto, flag compresi per quel che serve al DBRA che spesso la segue.
MisuraRicPassa:
        TST.B   MisuraRicAttiva
        BEQ.S   .fine
        MOVEM.L D0-D1,-(SP)
        BSR.W   LeggiRiga
        MOVE.W  MisuraRicRiga,D1
        MOVE.W  D0,MisuraRicRiga
        CMP.W   D1,D0
        BGE.S   .nogiro                 ; riga cresciuta: il pennello non ha girato
        ADDQ.W  #1,ProfRicVPOS
.nogiro:
        MOVEM.L (SP)+,D0-D1
.fine:
        RTS

MisuraRicChiudi:
        BSR.S   MisuraRicPassa          ; un ultimo campione prima di chiudere
        MOVEM.L D0,-(SP)
        BSR.S   MisuraRicTOD
        SUB.W   MisuraRicTOD0,D0
        MOVE.W  D0,ProfRicTOD
        CLR.B   MisuraRicAttiva
        MOVEM.L (SP)+,D0
        RTS

; Il TOD del CIA-A in quadri. L'ORDINE DI LETTURA NON E' LIBERO: leggere
; TODHI CONGELA tutti e tre i byte, leggere TODLOW li sblocca. In un altro
; ordine si prende un valore strappato a meta' incremento.
; Bastano MID e LOW: 65536 quadri sono 22 minuti.
MisuraRicTOD:
        TST.B   $BFEA01                 ; TODHI: la lettura congela il contatore
        MOVEQ   #0,D0
        MOVE.B  $BFE901,D0              ; TODMID
        LSL.W   #8,D0
        OR.B    $BFE801,D0              ; TODLOW: la lettura lo sblocca
        RTS
	ENDC

