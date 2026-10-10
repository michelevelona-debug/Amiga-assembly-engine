*				   MEGA GAME												*
*																			*
*   Inserire effetti sonori e grafiche										*
*	Aggiungere nemici e logica di combattimento								*
*   Aggiungre effetti grafici (es. acqua, luci) 							*
*   Inserire logica di gioco (PF, punti, interfaccia grafica e game over)	*
*   Sviluppo intro 															*
*   Ottimizzazioni varie (es. AI nemici, routine di disegno)				*
*   Aggiungere tutta la mappa di gioco (ora c'e' solo una schermata)		*
*																			*

	SECTION	MegaGame,CODE

; SCROLL HARDWARE (quello che i commenti chiamavano "Path B")
; Non esistono piu' GestisciShiftPixel, CopiaVideo e AggiornaTiles: la mappa
; viene disegnata TUTTA all'init dentro SFONDOGRANDE, che e' il buffer
; VISUALIZZATO, e lo scroll e' solo aritmetica sui BPLxPT piu' BPLCON1
; (vedi ScrollHW.i). I BOB non lasciano scie: PathBRestoreAll ripristina
; dal master i rettangoli sporchi del frame precedente.
; L'interruttore PATH_B e' stato tolto il 19 agosto 2026: valeva 1 e non
; esisteva piu' nessun ramo alternativo. Il vecchio blocco descriveva lo
; stato del "passo 2", superato da un pezzo.
; Stessa sorte per SWITCH_PIANI il 22 agosto 2026: serviva a mostrare
; darkplane e parallasse UNO ALLA VOLTA per capire quale dei due avesse
; fatto esplodere il costo al passo 2b (WORST da 193 a 392). La misura e'
; stata fatta, valeva 3 da allora, e con 3 i due blocchi che dirottavano i
; piani ausiliari su un piano vuoto erano codice morto mentre il
; BSR SwapParBuffers stava dentro un condizionale attorno a una chiamata
; che deve avvenire sempre. Oggi quella misura non si puo' piu' rifare cosi':
; la parallasse non sta piu' nei bitplane e PAR_DISABLE non esiste.
	include	"CostTitolo.i"		; Costanti: schermata del titolo e droide

	include	"Startup2.i"		; Startup completo AGA + VBR + cache clear

	include	"CostDisplay.i"		; Costanti: DMA, mappa, scroll, display, fade, alba, sfondo, cielo, alberi
	include	"CostPannello.i"		; Costanti: strumenti del pannello
	include	"CostGioco.i"		; Costanti: pietra, player, fisica, tasti, luce, falo', suoni
	include	"CostProfilo.i"		; Costanti e macro PROFMARK del profiler

WaitDisk 		EQU 30 ; 50-150 al salvataggio (secondo i casi)
START:

* TITLE SCREEN
*   Setup AGA + PT Player, avvia musica, mostra title.raw, attende SPACE
*   o tasto fire del joystick. Poi ferma la musica e procede col gioco.
	LEA		$DFF000,A6
	MOVE.W	#$3,$1fc(A6)			; FMODE = $03 (AGA fetch 64-bit)
	MOVE.W	#BPLCON3_LOCT0,$106(A6)			; BPLCON3 default
	MOVE.W	#$0000,$10c(A6)			; BPLCON4 default

	; ----- PT Player: installa interrupt CIA-B -----
	; VectorBase: _mt_install NON cerca la tabella dei vettori da solo, si fida
	; di A0 e scrive il proprio handler di livello 6 in VectorBase+$78. Dal
	; 68010 in su la tabella non sta piu' per forza in 0: il registro VBR dice
	; dove sta, e SetPatch su 68020+ con fast RAM la sposta li' per risparmiare
	; cicli a ogni interrupt. Con A0=0 su una macchina col VBR spostato ptplayer
	; scriverebbe in $78 mentre il processore legge da VBR+$78: il Timer A del
	; CIA-B continua a scadere ma salta all'handler vecchio, mt_music non gira
	; mai e la musica non parte (silenzio, o una nota appesa).
	; Startup2 il VBR lo legge gia' - col MOVEC assemblato a mano - e ci salva
	; sopra i sei vettori di sistema; qui si riusa lo stesso valore invece di
	; contraddirlo. Su 68000 BaseVBR resta lo 0 con cui nasce, quindi dove oggi
	; funziona il comportamento e' identico bit per bit.
	MOVE.L	BaseVBR,A0				; VectorBase vero (0 su 68000, VBR su 68010+)
	MOVEQ	#1,D0					; PAL flag = 1
	JSR		_mt_install
	MOVE.W	#$E000,$DFF09A			; abilita INT level 6 (EXTER) + master enable
	MOVE.W	#$8200,$96(A6)			; DMACON: master DMA on (per audio Paula)

	; Riserva 3 canali alla musica: gli SFX (sfx_cha=-1) potranno usare
	; solo il 4o canale. Evita che uno sparo "buchi" un canale musicale.
	MOVE.B	#3,_mt_MusicChannels

	; ----- Carica modulo e avvia musica -----
	LEA		ANTIRIAD_MOD,A0
	SUBA.L	A1,A1					; campioni embedded
	MOVEQ	#0,D0					; SongPos = 0
	JSR		_mt_init
	MOVE.B	#1,_mt_Enable			; play

	; ----- Mostra title screen e attende input -----
	BSR.W	ShowTitle				; setup 8 BPL AGA + palette + copper
	BSR.W	WaitTitleInput			; il droide fluttua fino a SPACE o fire

	; ----- Poi l'intro: l'alba sul lembo della Terra (Intro.i) -----
	; Stessa geometria di display del titolo e stesso DMA, quindi qui in mezzo
	; non c'e' niente da riconfigurare. La musica continua: la ferma il blocco
	; qui sotto, quando parte il gioco.
	BSR.W	IntroEsegui

	; ----- Click: ferma la musica della title -----
	MOVE.B	#0,_mt_Enable
	; _mt_Enable=0 mette in pausa il PT Player, ma Paula continua a
	; ripetere in loop l'ultimo sample caricato (= ultima nota infinita).
	; Azzero i 4 volumi audio: in pausa il PT Player non li sovrascrive,
	; quando la musica viene riattivata (tasto M) il player ricarica
	; automaticamente i volumi al primo tick.
	MOVE.W	#0,$a8(A6)				; AUD0VOL = 0
	MOVE.W	#0,$b8(A6)				; AUD1VOL = 0
	MOVE.W	#0,$c8(A6)				; AUD2VOL = 0
	MOVE.W	#0,$d8(A6)				; AUD3VOL = 0

	; ====================================================================
	; QUI NON SI PASSA AL DISPLAY DEL GIOCO. Il blocco che lo fa - spegnere
	; BPL+COP, puntare i bitplane, caricare la palette, riaccendere il DMA e
	; far partire la copperlist - sta IN FONDO, subito prima di .mainloop.
	;
	; PERCHE', ed e' l'unico motivo: fino al 24 settembre 2026 stava qui, e
	; quindi tutto quello che viene dopo - le Init*, le Build* e soprattutto
	; la costruzione del mondo, che da sola dura 41 quadri - girava con lo
	; schermo del gioco GIA' acceso su un SFONDOGRANDE ancora vuoto. Si vedeva
	; la mappa comparire una tile alla volta per quasi un secondo.
	; Spostando il passaggio in fondo, per tutto quel tempo resta a video
	; l'ultimo fotogramma dell'alba, che l'intro lascia li' com'e'; poi si
	; passa, e il mondo compare gia' fatto.
	;
	; COSA LO RENDE POSSIBILE, verificato e non sperato:
	;  - i buffer non si sovrappongono. TitoloBuf, PathBMaster, PathBDarkPlane,
	;    SFONDOGRANDE, SFONDOGRANDE_B, PannelloBuf e AlbaImg sono blocchi
	;    distinti in PLANEVUOTO,BSS_C: costruire il mondo non tocca un byte di
	;    quello che l'alba sta mostrando;
	;  - il blitter e' acceso. TIT_DMASET, che regge titolo e intro, contiene
	;    DMA_BLITTER: e' l'unico canale che serve a chi costruisce;
	;  - nessuna delle routine qui sotto scrive un registro di colore. La
	;    palette del gioco la carica InitPalette8BPL, che e' dentro il blocco
	;    spostato: se girasse adesso ripingerebbe l'alba sotto i piedi;
	;  - chi scrive nella copperlist del GIOCO (AggiornaCopper*, PathBInit,
	;    BuildSkyCopper, InitParallasseSprite) lo fa mentre il copper sta
	;    eseguendo IntroCopperList, che e' un'altra lista: nessuna corsa.
	;
	; PREZZO, dichiarato: durante la costruzione gira il blocco copper
	; dell'alba, che sono 528 MOVE per quadro, cioe' ~9 righe raster rubate al
	; blitter a ogni giro. Su 41 quadri fa circa un quadro in piu': **RQ al
	; boot salira' di 1-2 e non e' una regressione**. Il copper non si puo'
	; spegnere per risparmiarlo: e' lui che ricarica i BPLxPT a ogni quadro, e
	; senza di lui l'immagine dell'alba scivolerebbe via dopo un quadro solo.
	; ====================================================================

	; PRIMA di tutto quello che legge la mappa, e InitPlayer la legge subito:
	; in coda chiama TrovaPartenza, che cerca la TILE_VIA. ImpostaBlocco mette
	; MappaPtr dal blocco che dice MappaCorrente, e finche' non gira quel
	; puntatore vale zero.
	MOVE.W	MappaCorrente,D0
	BSR.W	ImpostaBlocco

	BSR.W   InitPlayer				; <-- INIZIALIZZA IL PLAYER
	BSR.W   InitEnemies				; <-- INIZIALIZZA I NEMICI
	BSR.W	InitPietra				; <-- INIZIALIZZA IL PROIETTILE (BOB pietra)
	BSR.W	BuildBobMasks			; Genera le maschere di OMINO/NEMICO/PIETRA al boot
	BSR.W	BuildFaloSheet			; espande la striscia del falo' a 5 piani
	BSR.W	BuildRotellaSheet		; espande la striscia della rotella a 5 piani
	BSR.W	BuildIndicSheet			; espande la striscia degli indicatori a 4 piani
	BSR.W	ComponiSheets			; schermo, spie e quadrante: espansione a 4
	; piani PIU' lo sfondo del pannello sotto
	LEA		ScrittaMessaggio,A0
	BSR.W	ImpostaScritta			; il messaggio che scorre sotto il monitor
	BSR.W	InitFalo				; il falo' e' un BOB come tutti gli altri
	IFNE	CIELO_GRADIENTE
	IFEQ	PROFILING*PROF_KILL_SKY
	BSR.W	BuildSkyCopper			; genera il gradiente cielo su BG_VIS_ROWS righe
	ENDC							; (con PROF_KILL_SKY=1 lo spazio non e' riservato)
	ENDC							; (con CIELO_GRADIENTE=0 non c'e' niente da generare)

	; ----- Musica: resta in pausa dopo il click sulla title.
	; L'utente la riattiva con M (toggle MusicOn -> _mt_Enable via GestisciMusica).
	; MusicOn=0/MusicOnPrev=0 -> nessun cambio rilevato, _mt_Enable resta 0.
	MOVE.B	#0,MusicOn
	MOVE.B	#0,MusicOnPrev

	; La sequenza che ricostruisce il mondo comincia QUI e finisce con
	; PathBBuildDark, e si misura al boot gratis: tasto P, voci RQ e RV.
	; DAL 24 SETTEMBRE questa misura si prende con l'ALBA a video, quindi col
	; blocco copper dell'alba (528 MOVE per quadro) che ruba cicli al blitter:
	; il 41 di prima diventa 42-43 e NON e' un peggioramento del disegno, e'
	; un'altra condizione di misura. Il numero da confrontare col passaggio
	; resta quello, ma sapendo che adesso i due sono meno lontani per questo.
	; ATTENZIONE, non e' la stessa che gira al passaggio fra blocchi: qui dentro
	; ci sono anche DisegnaPannello, InitParallasseSprite,
	; AggiornaParallasseSprite e PathBInit, che sono preparazione UNA TANTUM e
	; RicostruisciMondo non rifa' (il perche' di ognuna sta scritto la').
	; Quindi il 41 del boot e il 44 del passaggio non sono lo stesso insieme di
	; lavoro, e la differenza non e' il prezzo della porta.
	IFNE	PROFILING
	BSR.W	MisuraRicAvvia
	ENDC
	BSR.W	DisegnaSfondo			; Routine che disegna lo sfondo
	; DOPO DisegnaSfondo: da qui in poi tutti - parallasse, ScrollPathB, la
	; posizione a schermo dei bob - leggono la camera giusta.
	; (Fino al 24 settembre l'ordine era un VINCOLO, perche' DisegnaSfondo
	; leggeva TileX. Adesso e' solo il modo sensato di metterli.)
	BSR.W	CentraCameraSulPlayer	; il player nasce dove dice TILE_VIA

	; Pre-render su entrambi i buffer per evitare il primo frame nero
	BSR.W	DisegnaPannello				; costruisce il pannello
	; Init mette i canali sulla posa 0, cosi' il display non parte mai su
	; puntatori mai scritti; da li' in poi li riscrive il quadro, perche' e'
	; il puntatore a scegliere la posa e quindi a fare il vento.
	BSR.W	InitParallasseSprite
	BSR.W	AggiornaParallasseSprite
	; (al primo giro del loop il display è B, e disegnamo su A — entrambi pronti)

	BSR.W	PathBInit				; DDFSTRT/BPLxMOD + piani 6-8 su buffer vuoto
	LEA		SFONDOGRANDE,A0
	LEA		PathBMaster,A1
	BSR.W	PathBBuildMaster		; copia pulita per il restore dei BOB
	; Col doppio buffer la mappa deve stare in ENTRAMBI: il secondo buffer non
	; viene mai ridisegnato da zero, si ripulisce solo per rettangoli.
	LEA		SFONDOGRANDE,A0
	LEA		SFONDOGRANDE_B,A1
	BSR.W	PathBBuildMaster		; stessa mappa nel secondo buffer del mondo
	; DisegnaCerchioLuceBlitter scrive dove punta CurrentDarkDraw: in Path B
	; e' sempre il buffer statico, che non fa piu' doppio buffering.
	; Stessa origine dello sfondo: il darkplane deve stare allineato con lui,
	; e il suo BPL6PT usa lo stesso offset dei piani 1-5.
	MOVE.L	#PathBDarkPlane+DELTA_MAPPAVERA+BG_ORIGIN_OFS,CurrentDarkDraw
	BSR.W	PathBBuildDark			; darkplane statico, una volta sola
	; Fine della sequenza di ricostruzione: BuildLightMask sta FUORI apposta,
	; e' preparazione una tantum e al passaggio fra blocchi non si rifara'.
	IFNE	PROFILING
	BSR.W	MisuraRicChiudi
	ENDC
	BSR.W	BuildLightMask			; costruisce una volta la maschera del disco di luce

	; ====================================================================
	; PASSAGGIO AL DISPLAY DEL GIOCO. Da qui in giu' l'alba non c'e' piu' e il
	; mondo, che e' gia' completo, va a video in un colpo solo. Questo blocco
	; stava PRIMA di InitPlayer fino al 24 settembre 2026: il motivo dello
	; spostamento e' scritto per esteso la' dove stava.
	; Il blocco e' AUTOSUFFICIENTE di proposito - si rimette A6 da solo -
	; perche' fra la sua vecchia e la sua nuova posizione ci sono una ventina
	; di BSR e nessuna promette di conservarlo.
	; ====================================================================
	LEA		$dff000,A6

	; ----- Spegne BPL+COP DMA prima di riconfigurare per il gioco -----
	; (audio DMA preservato per il restart musica successivo)
	MOVE.W	#$0180,$96(A6)			; CLR BPLEN+COPEN

*	PUNTIAMO I BITPLANES DELLE TILES

	MOVE.L	#SFONDOGRANDE,D0		; Path B visualizza direttamente il world buffer
	MOVE.L	#PathBDarkPlane,D2		; darkplane di Path B (i doppi buffer vecchi non ci sono piu')

	BSR.W	AggiornaCopperBPL 		; aggiorna i puntatori bitplane nella copperlist

	BSR.W	AggiornaCopperSPR 		; aggiorna anche i puntatori sprite nella copperlist

	; ----- Banchi palette 1..7 (colori 32..255) per gli 8 bitplane.
	; Copper DMA ancora spento: BPLCON3 e' tutto nostro, niente race.
	BSR.W	InitPalette8BPL
	; Dopo, e non prima: i livelli si scalano da GamePal24 e GamePalBk, che li
	; riempie lei. Non serve applicarne nessuno adesso - la copperlist nasce
	; gia' con la palette piena, e il livello FADE_LIVELLI-1 la riproduce
	; esatta.
	BSR.W	BuildFadeTab

	; La LEA c'era gia' qui prima dello spostamento, e ci resta: una delle tre
	; BSR qui sopra si porta via A6. Quella in testa al blocco e' IN PIU', non
	; al suo posto - serve alla CLR di BPLEN+COPEN, che nella posizione nuova
	; non trova piu' l'A6 lasciato dalle scritture dei volumi audio.
	LEA		$dff000,A6
	MOVE.W	#DMASET,$96(A6)			; DMACON - abilita dma
	MOVE.L	#CopperList,$80(A6)		; Puntiamo la nostra COP
	MOVE.W	D0,$88(A6)				; Facciamo partire la COP

	; Rimette i registri di display DEL GIOCO: il titolo aveva i suoi, e questi
	; tre la copperlist del gioco non li scrive (vedi ImpostaDisplayGioco).
	BSR.W	ImpostaDisplayGioco
	; Gli otto SPRxPT non si scrivono da qui: AggiornaCopperSPR li ha gia' messi
	; a EmptySprite nella copperlist col DMA spento, e il copper li ricarica da
	; li' a ogni quadro. Le otto MOVE.L che stavano qui erano un ripiego
	; dell'epoca in cui la copperlist non li aggiornava.

.mainloop:
	PROFMARK PH_INPUT,$0404			; viola scuro
	; NB: LeggiTastiera deve stare QUI, prima di tutto. Provata dopo la parallasse
	; per togliere le sue righe dall'overhead che ritarda la pubblicazione del
	; buffer: i BOB partono piu' tardi di quanto lei costa e si corrompono.
	; Il tempo va tolto altrove, non da qui.
	BSR.W	LeggiTastiera			; Routine che legge la tastiera
	BSR.W	LeggiJoystick			; Routine che legge il Joystick
	BSR.W	RettangoloScrollNelCentro		; Se bob NON al centro, azzera ScrllX/Y
	BSR.W	AggiornaFisicaPlayer		; gravita' + salto -> IntentY
	BSR.W	AggPosizioneGlobalePlayer	; Aggiorna bob_WorldX/Y (Fase 2)
	; SUBITO DOPO il clamp e PRIMA che camera e bordi lavorino sulla posizione:
	; se il player spinge oltre la colonna 72 si attraversa la porta, e il
	; resto del quadro deve gia' vedere il mondo nuovo.
	BSR.W	ControllaPassaggio			; il bordo destro e' una porta
	BSR.W	CalcolaInseguimentoCameraY	; camera insegue il player in verticale -> ScrllY
	BSR.W	ControllaBordi			; Controllo dei bordi
	PROFMARK PH_SCROLL,$0F80		; arancione
	BSR.W	ScrollPathB				; scroll hardware: solo puntatori + BPLCON1

	; La parallasse va DOPO i BOB, non prima. Il suo blit e' 8800 word (~77
	; scanline di blitter) e gira in background: mettendolo prima, ogni blit di
	; BOB si accodava dietro di lui e il disegno dei BOB finiva verso la riga 94,
	; quando il pennello era gia' passato -> BOB tagliati in una fascia FISSA
	; dello schermo. Misurato col monitor: PA 001 (solo il tempo di programmare)
	; contro BO 082 per un lavoro che di blitter ne vale 46: la differenza era
	; pura attesa in coda.
	; La fase misura AggiornaParallasseSprite: sette puntatori di copper piu'
	; VENTO_POSE*2 byte di HSTART per albero, zero blit. Se PA vale piu' di un
	; paio di righe il tempo non e' suo ma di chi aspetta il blitter (vedi la
	; regola 2 in prestazioni.md).
	PROFMARK PH_PARALLAX,$00F0		; verde
	BSR.W	AggiornaParallasseSprite	; sette alberi, due velocita', il vento

	; Il blit della parallasse parte QUI, subito dopo ScrollPathB che ha appena
	; scritto BPLCON1: contenuto e ritardo appartengono cosi' allo STESSO frame.
	; Poi si aspetta il blitter e si pubblica subito, mentre il pennello e'
	; ancora nel blank: il copper rilegge la copperlist all'inizio del quadro e
	; trova gia' i puntatori nuovi. Prima lo swap stava dopo AspettaVBL e
	; pubblicava il buffer del giro PRECEDENTE, compensato per il ritardo di un
	; frame prima: da li' il flash quando il ritardo salta da 0 a 63 al primo
	; pixel di scroll.
	; I BOB partono dopo, ma con CUT_BOTTOM_ROWS=96 finiscono verso la riga 27,
	; molto prima che il display cominci alla 44.
	BSR.W	AspettaBlitter			; il buffer parallasse dev'essere completo
	; NB: qui NON si pubblica. Lo swap sta in ScrollPathBApply insieme a BPLCON1
	; e ai puntatori del mondo: contenuto e compensazione devono diventare
	; effettivi nello STESSO quadro, altrimenti la parallasse mostra un frame
	; compensato per un ritardo che non e' ancora in vigore.
	PROFMARK PH_TILES,$0FF0			; giallo
	PROFMARK PH_DARK,$000F			; blu acceso
	; In Path B il darkplane e' STATICO: disegnato una volta in coordinate
	; mondo da PathBBuildDark e ricostruito solo al toggle di NightMode.
	; Qui non serve fare nulla: il costo per frame e' zero.
	; NOTA: il dark plane e' gia' double-buffered correttamente.
	; UpdateDarkPlane scrive SOLO CurrentDarkDraw (mai il buffer in display);
	; SwapBuffers alterna A/B e aggiorna BPL5PT. Nessuna copia extra serve qui:
	; copiare in CurrentDarkDisplay = scrivere nel piano EHB mentre il pennello
	; lo legge -> tearing visibile sul bordo del cerchio (lo "sfarfallio in basso").

	PROFMARK PH_FALO,$0088			; ciano scuro
	BSR.W	AnimaFalo				; anima sprite falo' e lo mette a col 5 riga 15 (posizione cablata)
	PROFMARK PH_COPIAVIDEO,$0F0F	; magenta
	PROFMARK PH_ENTITIES,$0808		; viola medio
	BSR.W	AggiornaPlayerScreenPos	; Calcola bob_X/Y dalle coord. mondo
	BSR.W	AggiornaNemici			; AI dei nemici (movimento)
	BSR.W	Combattimento			; gestisce collisioni player-nemici (vita)
	BSR.W	Proiettile				; gestione fire + proiettile (move, collisione)
	BSR.W	SuonoPassi				; passi del player: gira dopo la fisica, cosi'
	;  legge un bob_Grounded gia' aggiornato
	PROFMARK PH_BOB,$00FF			; ciano acceso
	BSR.W	PathBRestoreAll			; ripulisce lo sfondo dietro ai BOB del frame scorso
	BSR.W	DisegnaBOBs				; nemici + player + pietra, in un ciclo solo

; --- Sincronizzazione e swap ---
	PROFMARK PH_BLTDRAIN,$0FF8		; giallo pallido = attesa pura del blitter
	; (era $0840, indistinguibile dal rosso
	;  scuro $0800 dell'high-water)
	BSR.W	AspettaBlitter

	; Il disegno e' finito e il blitter ha drenato: ORA si pubblica il buffer e
	; si scambia con l'altro. Prima di qui il pennello non ha mai visto un
	; buffer a meta'.
	BSR.W	ScrollPathBApply

	; Il pannello non e' doppio bufferizzato e i suoi puntatori nella
	; copperlist sono fissi dal boot: si puo' scrivere quando capita, e qui
	; capita a lavoro finito. Nei frame in cui il punteggio non cambia costa
	; un confronto. Sta DENTRO la zona misurata apposta: se un giorno
	; costasse, si vedrebbe nel margine invece di nascondersi.
	BSR.W	DisegnaPunteggio
	BSR.W	DisegnaIndicatori
	BSR.W	DisegnaSchermo
	BSR.W	DisegnaSpie
	BSR.W	DisegnaQuadrante
	BSR.W	DisegnaLettera
	BSR.W	DisegnaScritta

	IFNE	PROFILING
	BSR.W	FineLavoro			; misura margine + high-water + frame persi
	; (scrive lui ROSSO/BIANCO: niente $0FFF qui,
	;  sarebbe sovrascritto subito)
	TST.B	ProfShow			; premi P per mostrare/nascondere i numeri
	BEQ.S	.noprof
	BSR.W	MostraProfilo		; DOPO la misura: non entra in FrameLines
	BRA.S	.profatto
.noprof:
	; P appena spento: rimetti l'arte del pannello sotto il blocco. Il flag lo
	; alza il gestore del tasto, il blit si fa QUI perche' vuole A6 e un punto
	; del quadro in cui il pennello ha gia' passato la fascia del pannello -
	; che e' esattamente dove si scrive il pannello da sempre.
	TST.B	ProfPanRipara
	BEQ.S	.profatto
	CLR.B	ProfPanRipara
	BSR.W	ProfPanRipristina
.profatto:
	ENDC
	BSR.W	AspettaVBL
	PROFMARK PH_VBLEND,$0008		; BLU = inizio lavoro (musica + swap)
 	BSR.W	GestisciMusica			; start/stop + tick PT Player (chiama _mt_music ogni VBL)
	; La dissolvenza scrive QUI, e il punto conta: dopo AspettaVBL il copper ha
	; gia' letto il blocco palette per questo quadro, quindi il livello nuovo
	; vale dal prossimo e non si vede mai mezza palette. A6 e' $DFF000, che e'
	; quello che RicostruisciMondo chiede quando la fase 1 arriva al nero.
	BSR.W	AggiornaTransizione
	; Ora SwapParBuffers torna: scrive BPL7PT/BPL8PT sul parallasse vero,
	; che ha finalmente il pitch giusto. Il darkplane non ha doppio buffer:
	; e' statico, e il suo BPL6PT lo aggiorna ScrollPathB insieme ai puntatori
	; dei piani 1-5, perche' scorre come loro.

	BTST.B	#6,$bfe001				; tasto sx del mouse premuto?
	BNE.W	.mainloop

; Ci si arriva per CADUTA quando il loop esce (tasto sinistro del mouse).
; La label e' GLOBALE per un motivo storico: il prototipo di scroll ci
; saltava dentro con un forward reference che il linker non risolveva come
; ".cleanup" nello scope di START. Quel salto non esiste piu' (PROTO_SCROLL
; tolto il 22 agosto 2026), ma la label globale non da' fastidio: fra qui e
; l'RTS non ci sono label locali, quindi nessuno scope cambia.
GameCleanup:
	; ----- Cleanup PT Player prima di tornare all'OS -----
	LEA		$DFF000,A6
	JSR		_mt_end					; ferma replay + azzera canali audio
	JSR		_mt_remove				; rimuove handler CIA-B, ripristina timer
	RTS
* ASPETTA VBL
AspettaVBL:
	MOVEM.L D0-D2,-(SP)

	MOVE.L  #$1ff00,D1
	MOVE.L  #(VBL_SYNC_LINE<<8),D2	  ; riga di sincronismo, oggi 220: e' dove
									  ; finisce il display del mondo e comincia
									  ; il pannello. NON scrivere il numero a
									  ; mano: FineLavoro misura a partire da
									  ; questa stessa EQU, e le due scollate
									  ; sfasano la misura senza dirlo.
.wait:
	MOVE.L  $dff004,D0		  ; VPOSR
	AND.L   D1,D0
	CMP.L   D2,D0
	BNE.S   .wait
	movem.l (SP)+,D0-D2
	RTS
* AGGIORNA I BPL POINTER NELLA COPPERLIST
* INPUT:  D0 = indirizzo del primo bitplane
* OUTPUT: 5 BPL pointer aggiornati a partire da BitPlaneTiles
* DISTRUGGE: D0, A1 (e usa internamente D1)
AggiornaCopperBPL:
	MOVEM.L D1/A1,-(SP)
	LEA	 BitPlaneTiles,A1

	; --- Primi 5 plane: standard BPSFONDO ---
	MOVEQ   #5-1,D1
.loop:
	MOVE.W	D0,6(A1)			; word bassa
	SWAP	D0
	MOVE.W	D0,2(A1)			; word alta
	SWAP	D0
	ADD.L	#BG_PLANE_BANDA,D0	; prossimo bitplane (passo con padding anti over-fetch FMODE=3)
	ADDQ.W	#8,A1				; prossimi 4 dc.w nella copperlist
	DBRA	D1,.loop

	; --- 6° plane: DARK plane (gestito separatamente) ---
	; A1 punta ora a $f4,0,$f6,0 (BPL5PT entry)
	MOVE.W	D2,6(A1)			; BPL5PTL word bassa
	SWAP	D2
	MOVE.W	D2,2(A1)			; BPL5PTH word alta

	MOVEM.L	(SP)+,D1/A1
	RTS

* GestisciMusica
*   Chiamata ogni frame nel main loop.
*   In modalita' standard Timer-A gestisce il tick automaticamente:
*   qui ci limitiamo a propagare MusicOn -> _mt_Enable.
*   - MusicOn=1 -> _mt_Enable=1: Timer-A chiama il player automaticamente.
*   - MusicOn=0 -> _mt_Enable=0: Timer-A chiama solo mt_sfxonly (SFX ok).
GestisciMusica:
	MOVEM.L	D0/A6,-(SP)

	MOVE.B	MusicOn,D0
	CMP.B	MusicOnPrev,D0
	BEQ.S	.done
	MOVE.B	D0,MusicOnPrev
	MOVE.B	D0,_mt_Enable		; 1 = play, 0 = pausa (SFX restano attivi)

.done:
	MOVEM.L	(SP)+,D0/A6
	RTS

* AggiornaCopperSPR
*   Aggiorna gli sprite pointer nella copperlist (entry "Sprites").
*   - SPR0..SPR7 -> EmptySprite (tutti disattivati)
*   Il falo' era l'ultimo cliente dello sprite hardware ed e' diventato un BOB:
*   qui non resta nessuno sprite acceso. La routine e' tenuta finche' non si
*   smonta il resto dell'impianto (tabella Sprites nella copperlist, SPREN in
*   DMACON, BPLCON4): e' la seconda meta' della decisione del 18 agosto.
* DISTRUGGE: D0/D1/A0/A1 (preserva tramite stack)
AggiornaCopperSPR:
	MOVEM.L D0-D1/A0-A1,-(SP)

	; --- SPR0..SPR7: tutti puntano a EmptySprite ---
	; SPR0 compreso: prima lo saltava perche' ci stava il falo', e lasciarlo
	; fuori adesso significherebbe lasciare nella copperlist il suo valore
	; iniziale, che e' ZERO. Uno sprite puntato all'indirizzo 0 legge l'inizio
	; della chip RAM e disegna spazzatura.
	MOVE.L	#EmptySprite,D0
	LEA		Sprites,A1				; SPR0PT entry
	MOVEQ	#8-1,D1					; 8 sprite da disattivare
.loop:
	MOVE.W	D0,6(A1)
	SWAP	D0
	MOVE.W	D0,2(A1)
	SWAP	D0
	ADDQ.W	#8,A1					; prossima entry sprite nella copperlist
	DBRA	D1,.loop

	MOVEM.L	(SP)+,D0-D1/A0-A1
	RTS
	include	"Sheet.i"		; Fogli costruiti al boot: falo', rotella, indicatori
	include	"Misura.i"		; Misura del quadro: LeggiRiga, FineLavoro
	include	"Input.i"		; Joystick e tastiera
	include	"Mondo.i"		; Camera, bordi, porte fra i blocchi, ricostruzione del mondo
	include	"Sfondo.i"		; Disegno dello sfondo, copper del cielo, skyline
	include	"Parallasse.i"		; Parallasse degli alberi sugli sprite
	include	"Init.i"		; Inizializzazioni: pannello, player, nemici, pietra, maschere BOB
	include	"Collisioni.i"		; Centro camera, collisioni con tile e BOB, movimento nemici
	include	"Palette.i"		; Palette AGA, notte, dissolvenza, transizioni
	include	"Titolo.i"		; Schermata del titolo e droide
	include	"Suoni.i"		; Effetti sonori
	include	"Combattimento.i"		; Pietra, combattimento, uccisioni
	include	"Luce.i"		; Falo', partenza dalla mappa, cerchio di luce
	include	"Nemici.i"		; Intelligenza dei nemici
	include	"Player.i"		; Fisica e posizione del player
	include	"Bob.i"		; Disegno dei BOB
	include	"Pannello.i"		; Strumenti del pannello, AspettaBlitter, scritta scorrevole
	include	"PathB.i"		; Scroll hardware, rettangoli sporchi, master, darkplane
	include	"Profilo.i"		; Monitor delle prestazioni
; L'intro. Come tutti gli include di questo progetto contiene SOLO codice: le
; sezioni le dichiara Gioco.s, e i suoi dati - l'immagine, il blocco copper, le
; due tabelle - stanno nelle sezioni qui sotto insieme a tutti gli altri.
	include	"Intro.i"

        SECTION DATI,DATA       ; variabili CPU-only -> fast RAM
	include	"Variabili.i"		; Variabili CPU (sezione DATI)

* 		COPPER

	SECTION	ChipStuff,DATA_C
	include	"Chip.i"		; Dati in chip RAM: copperlist, grafica

* AssetCPU - dati che NON vede nessun DMA
*   La chip RAM serve a chi non puo' farne a meno: display, blitter, copper,
*   Paula. Tutto quello che legge solo la CPU sta in memoria pubblica, che su
*   una macchina espansa e' fast e su un 1200 liscio torna chip da sola - non
*   si perde niente, si guadagna dove c'e' da guadagnare.
*   Il criterio non e' "e' grafica quindi va in chip": e' CHI LA LEGGE. Queste
*   tre sono grafica che nessun DMA tocca mai.
*   - title_pal      la palette del titolo la scrive nei registri
*                    LoadAGAPalette256, un long alla volta, con la CPU
*   - falo_strip     la legge BuildFaloSheet al boot; in chip ci va il
*                    risultato, FaloSheet, che quello si' lo blitta
*   - rotella_strip  la legge BuildRotellaSheet al boot; il risultato,
*                    RotellaSheet, non lo blitta nessuno perche' le cifre le
*                    scrive la CPU: sta in fast anche lui
*   Se un domani uno di questi finisse sotto il blitter o sotto il copper,
*   va rimesso in una sezione _C: da qui il DMA non lo vede e leggerebbe
*   spazzatura senza dare nessun errore.
*   cnop 0,4 e non 0,8: l'allineamento a 8 serve a FMODE=3, cioe' al fetch
*   dei bitplane. Qui legge la CPU a long, e 4 basta.

	SECTION	AssetCPU,DATA
	include	"AssetCPU.i"		; Asset letti solo dalla CPU

	SECTION	PLANEVUOTO,BSS_C
	include	"BufferChip.i"		; Buffer in chip RAM

* LavoroCPU - buffer costruiti al boot che nessun DMA legge
*   Stesso criterio di AssetCPU, per la memoria che non arriva da un file.
*   RotellaSheet e' l'unico cliente per ora: lo scrive BuildRotellaSheet al
*   boot e lo rilegge DisegnaPunteggio con MOVE.B. Il blitter non lo tocca -
*   una cifra e' larga un byte e allineata, quindi la copia la fa la CPU - e
*   percio' non ha nessun motivo di occupare chip RAM.
*   Non e' insieme a FaloSheet apposta: quello e' l'esempio opposto, un
*   buffer costruito al boot che il blitter DEVE poter leggere.

	SECTION	LavoroCPU,BSS

	cnop	0,4
RotellaSheet:
	ds.b	ROTELLA_SHEET_SZ	; 4 piani, stesso pitch della striscia
	cnop	0,4
IndicSheet:
	ds.b	INDIC_SHEET_SZ		; 4 piani, stesso pitch della striscia
	cnop	0,4
SchermoSheet:
	ds.b	SCHERMO_SHEET_SZ	; 4 piani, stesso pitch della striscia
	cnop	0,4
SpiaSheet:
	ds.b	SPIA_SHEET_SZ
	cnop	0,4
SpiaRossaSheet:
	ds.b	ROSSA_SHEET_SZ
	cnop	0,4
QuadSheet:
	ds.b	QUAD_SHEET_SZ
	cnop	0,4
; Mappa a 1 piano del messaggio che scorre, gia' negata. Un byte per carattere,
; SCRITTA_H righe, piu' la coda che chiude il giro.
ScrittaBuf:
	ds.b	SCRITTA_BUF_SZ

	SECTION	SpritesData,DATA_C
	cnop	0,8				; allineamento sprite
; MOD ProTracker - DEVE essere in chip RAM (data_c) per Paula DMA
	cnop	0,4
ANTIRIAD_MOD:
	incbin	"suono/antiriad.amiga.mod"

; Sound effects samples (8-bit signed PCM raw mono).
; DEVONO essere in CHIP RAM per il DMA audio Paula.
; Lunghezza calcolata a compile-time da (End-Start)/2 nelle SfxStructure,
; quindi puoi sostituire i .raw con sample di lunghezza diversa senza
; toccare il sorgente: basta che il file abbia un numero pari di byte.
	cnop	0,4
SparoSample:
	incbin	"suono/Sparo.raw"
SparoSampleEnd:
SPARO_LEN		EQU	(SparoSampleEnd-SparoSample)/2

	cnop	0,4
PassoSample:
	incbin	"suono/passo.raw"
PassoSampleEnd:
PASSO_LEN		EQU	(PassoSampleEnd-PassoSample)/2

	cnop	0,4
NemicoColpitoSample:
	incbin	"suono/nemico_colpito.raw"
NemicoColpitoSampleEnd:
NEMICO_COLPITO_LEN	EQU	(NemicoColpitoSampleEnd-NemicoColpitoSample)/2

	cnop	0,4
HitPlayerSample:
	incbin	"suono/HitPlayer.raw"
HitPlayerSampleEnd:
HITPLAYER_LEN	EQU	(HitPlayerSampleEnd-HitPlayerSample)/2

	cnop	0,4
NemicoMortoSample:
	incbin	"suono/nemico_morto.raw"
NemicoMortoSampleEnd:
NEMICO_MORTO_LEN	EQU	(NemicoMortoSampleEnd-NemicoMortoSample)/2

	cnop	0,8
; Sprite vuoto per disattivare gli sprite non usati (SPR1..SPR7)
EmptySprite:
	dc.w	0,0				; SPRPOS, SPRCTL
	dc.w	0,0				; terminator

	SECTION	Entities,BSS

	cnop	0,4				; base allineata a 4: bob_Length e' multiplo di 4,
	; quindi i campi long restano allineati per OGNI bob
; I bob stanno TUTTI in memoria contigua sotto BobArray: tre ds.b consecutivi
; nella stessa sezione lo sono per costruzione. Cosi' un solo ciclo li percorre
; con LEA bob_Length(A0),A0 e non serve nessuna tabella di puntatori.
; Player ed Enemies restano ETICHETTE VERE, quindi Player+bob_WorldX e
; LEA Enemies,A0 continuano a funzionare identici in tutto il resto del file.
; L'ORDINE DI DICHIARAZIONE E' L'ORDINE DI DISEGNO, cioe' lo z-order:
; i nemici sotto, sopra di loro il player, la pietra sopra a tutti.
; Aggiungere un bob (il falo', le parti del pannello) = un ds.b in piu' qui
; e BOB_TOTALI alzato di uno. Nessun codice da toccare.
BobArray:
; Il falo' per PRIMO: e' scenografia, e chi ci passa davanti deve coprirlo.
BobFalo:
	ds.b	bob_Length		; il falo': stessa struct di tutti gli altri
Enemies:
	ds.b	bob_Length*ENEMY_COUNT	; array dei nemici
Player:
	ds.b	bob_Length		  		; struct del player
BobPietra:
	ds.b	bob_Length				; il proiettile: stessa struct di tutti gli altri

; PT PLAYER di Frank Wille (rinominato ptplayer.i per evitare la
; compilazione automatica dell'extension vscode-amiga-assembly).
; IMPORTANTE: ptplayer.i NON dichiara una propria SECTION code, quindi
; eredita la SECTION corrente. Bisogna riportare la SECTION corrente in
; CODE prima dell'include, altrimenti il codice del player finisce
; in BSS e crasha appena chiamato.
	SECTION	PTPlayerCode,CODE

	include	"ptplayer.i"

	end
