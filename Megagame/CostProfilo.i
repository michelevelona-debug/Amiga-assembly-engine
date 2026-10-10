; CostProfilo.i - Costanti e macro PROFMARK del profiler
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

; PROFILING HARNESS — margine con high-water mark + frame persi
; Come si legge la barra (dall'alto in basso):
;   BLU     = lavoro reale di QUESTO frame
;   ROSSO   = margine gia' bruciato in passato (high-water, sticky)
;   BIANCO  = margine RESIDUO -> e' il budget che ti resta
;   SCHERMO TUTTO ROSSO per un frame = FRAME PERSO
; La fascia bianca si assottiglia da sola man mano che il gioco incontra
; situazioni piu' pesanti. Dopo 2-3 minuti di gioco vario si stabilizza:
; quel valore e' il tuo margine reale. Riferimento: 1 riga raster = 227
; cicli di colore, il BOB 32x32 costa ~6 righe in piu' del 16x16.
PROFILING       EQU     1       ; 0 = harness completamente fuori dalla build
; PROF_COLORS: TUTTA la strumentazione che scrive COLOR00 — sia le barre di
; PROFMARK a ogni marca di fase, sia le tre fasce di fine frame (rosso pieno =
; frame perso, rosso scuro = margine bruciato, bianco = margine residuo).
; Erano gattate solo le prime: le fasce restavano accese e si vedevano come
; una riga orizzontale colorata a tutta larghezza dello schermo.
; Servono
; solo a leggere il costo delle fasi a occhio sul bordo schermo; la MISURA sta
; nel latch di ProfRaw e funziona lo stesso. Spente: il gioco si vede pulito.
PROF_COLORS     EQU     0
; PROF_KILL_SKY: a 1 toglie al COPPER la voce COLOR00, che diventa un NO-OP
; ($1fe) in GamePalHi e GamePalLo, e la lascia alla CPU.
;
; QUI C'ERA SCRITTO che serviva solo per leggere il costo dalle fasce colorate
; a bordo schermo, e che con lo 0 "la misura non ne risente". E' FALSO, e il 23
; settembre e' costato un pomeriggio: **serve anche per LEGGERE I NUMERI.**
; La catena e' questa, e nessuno dei tre pezzi e' sbagliato da solo:
;   - FineLavoro, quando i numeri sono a schermo, scrive COLOR00 = nero con la
;     CPU, apposta perche' le cifre sono colore 31 e su fondo chiaro non si
;     leggono;
;   - il copper riscrive COLOR00 con la tinta del cielo in cima a OGNI quadro;
;   - la scrittura della CPU cade dove arriva il lavoro del quadro, che cambia
;     di qualche riga a ogni giro.
; Risultato a schermo: cielo sopra la riga in cui scrive la CPU, nero sotto, e
; il confine che cammina. **Si vede come uno sfarfallio grigio/nero**, e i
; numeri compaiono solo nei quadri in cui il confine e' salito sopra di loro.
; E' la stessa lezione di BPLCON1: **un registro che il copper riscrive ogni
; quadro non si scrive dalla CPU a meta' schermo.** La correzione definitiva e'
; patchare le due voci COLOR00 della copperlist invece di scrivere $180; finche'
; non c'e', questo interruttore e' il modo di leggere il monitor.
;
; DAL 23 SETTEMBRE NON SERVE PIU' PER LEGGERE I NUMERI, e torna a 0: il monitor
; sta nel pannello e usa due voci sue, quindi COLOR00 non lo tocca piu' nessuno
; per conto suo (la riga della CPU in FineLavoro e' stata tolta). Resta quello
; che il nome dice: **con `CIELO_GRADIENTE 1` serve a 1**, perche' il gradiente
; riscrive COLOR00 riga per riga e coprirebbe le fasce colorate di PROF_COLORS.
; Con il cielo a tinta fissa, come oggi, non cambia niente.
PROF_KILL_SKY   EQU     0

; Riga su cui sincronizza AspettaVBL. UNICA fonte di verita': AspettaVBL
; costruisce da qui il valore di confronto, FineLavoro la usa come origine
; della misura. NON duplicare il numero altrove: se le due si scollano, la
; misura e' sfasata di quella differenza e non te ne accorgi.
; Il lavoro del frame comincia appena il display finisce, cioe' alla riga
; ($2C + BG_VIS_ROWS). Era cablato a $108 = 264, che buttava 44 righe di blank;
; poi a $0DC = 220, giusto ma solo per BG_VIS_ROWS=176. Ora DERIVA, cosi'
; cambiando CUT_BOTTOM_ROWS il sync si sposta da solo — altrimenti alzando il
; CUT si guadagnerebbe blank senza usarlo, o peggio si partirebbe dentro il
; display.
VBL_SYNC_LINE   EQU     $2C+BG_VIS_ROWS
RASTER_LINES    EQU     313     ; PAL (NTSC = 262)

; NB: non serve piu' una soglia euristica per i frame persi. FineLavoro
; conta i wrap del raster e ricostruisce la durata REALE del frame, quindi
; il rilevamento e' diventato un confronto diretto: durata >= RASTER_LINES.
; Questo permette anche di misurare i frame che sforano, che sono proprio
; quelli dove stanno i costi peggiori.

; PROFILO PER FASE — dove vanno le righe
; Ogni confine del main loop scrive COLOR00 col colore della fase che
; INIZIA e latcha la riga raster. Risultato: lo schermo diventa una
; striscia di bande colorate, e l'altezza di ogni banda E' il costo di
; quella fase. Triage visivo immediato, senza debugger.
; I numeri precisi stanno in ProfWorst (peggior costo per fase, sticky):
; leggibile dal debugger come array di word, indice = PH_xxx.
; ATTENZIONE: la somma dei ProfWorst NON e' il worst totale — i picchi
; delle singole fasi non avvengono nello stesso frame.
; Overhead dell'harness completo: ~40 cicli per marker (11 marker) piu'
; il loop di normalizzazione in FineLavoro = circa 4-5 righe raster in
; totale. Sottraile mentalmente dai valori.
; Gli indici DEVONO essere in ordine temporale: il costo della fase i si
; ricava come ProfRaw[i+1] - ProfRaw[i] (l'ultima usa FrameLines come fine).
PH_VBLEND       EQU     0       ; GestisciMusica + SwapBuffers (subito dopo il sync)
PH_INPUT        EQU     1       ; input + fisica + camera + bordi
PH_SCROLL       EQU     2       ; GestisciShiftPixel  (treadmill)
PH_PARALLAX     EQU     3       ; AggiornaParallasseSprite (HSTART e puntatori)
PH_TILES        EQU     4       ; AggiornaTiles       (AddColonna/AddRiga)
PH_DARK         EQU     5       ; UpdateDarkPlane
PH_FALO         EQU     6       ; AnimaFalo
; ATTENZIONE: l'indice della fase DEVE seguire l'ordine CRONOLOGICO delle
; PROFMARK nel main loop. Il profiler calcola la durata di una fase come
; distanza dal marker SUCCESSIVO nell'array: se un latch arriva fuori ordine
; la differenza va negativa, la logica di wrap ci somma un frame intero e il
; totale si gonfia di ~313 righe (WO falsato e DR che sale anche da fermo).
; Le righe qui sotto stanno in ordine di indice, che e' anche quello
; cronologico: e' l'unico modo di vedere a colpo d'occhio se l'invariante
; vale ancora. PH_PARALLAX era finita in fondo alla lista con un commento
; che la dava dopo i BOB, mentre AggiornaParallax gira prima: il valore
; era giusto, la posizione e il commento no, e per capirlo bisognava
; andare a contare le PROFMARK nel main loop.
PH_COPIAVIDEO   EQU     7       ; (CopiaVideo non esiste piu': fase a costo zero)
PH_ENTITIES     EQU     8       ; screenpos + nemici + combattimento + proiettile
PH_BOB          EQU     9       ; restore + DisegnaBOB*
PH_BLTDRAIN     EQU     10      ; AspettaBlitter (attesa pura: se e' grossa, il
                                ;   blitter e' il collo di bottiglia, non la CPU)
PROF_SLOTS      EQU     11

; PROFMARK <indice fase>,<colore>
;   Marca l'inizio di una fase: colora COLOR00 e latcha la riga raster.
;   Salva la riga ASSOLUTA come la da' il pennello: la normalizzazione
;   la fa FineLavoro, cosi' la macro resta senza salti e senza label
;   (niente \@, massima compatibilita' fra assemblatori).
;   Indirizzamento assoluto e non A6: funziona anche dove A6 non e' caricato.
;   Distrugge: nulla.
PROFMARK        MACRO
        IFNE    PROFILING
        move.l  d0,-(sp)
        IFNE    PROF_COLORS
        move.w  #\2,$DFF180             ; COLOR00 = colore di questa fase
        ENDC
        move.l  $DFF004,d0              ; VPOSR+VHPOSR come long = atomico
        lsr.l   #8,d0
        and.w   #$01FF,d0
        move.w  d0,ProfRaw+(\1*2)
        move.l  (sp)+,d0
        ENDC
        ENDM
