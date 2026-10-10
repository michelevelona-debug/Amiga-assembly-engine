; Bob.i - Disegno dei BOB
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


*			  ROUTINE DI COPIA DELLA PARTE VISIBILE SUI BITPLANE
* DisegnaBOB - UNICA routine di rendering di un bob
*   Input: A0 = puntatore alla struct bob_*, con bob_X/bob_Y gia' calcolate
*          dal chiamante come coordinate SCHERMO.
*   Fa tutto: cull, clip verticale, animazione, blit sui 5 piani e
*   registrazione del rettangolo sporco. Vale per qualunque bob e qualunque
*   formato di sheet: la geometria viene dalla struct (bob_Larghezza,
*   bob_Altezza, bob_Frames, bob_Bande) e non da EQU cablate.
*   Il cull e il clip erano in una DisegnaBOBConClip separata, che aveva un
*   solo chiamante e passava i suoi risultati per variabile: fusi qui dentro
*   sono un blocco in testa alla routine, e bob_Y non viene piu' sovrascritta
*   e ripristinata attorno al blit.
DisegnaBOB:
	MOVEM.L	D0-D7/A0-A3,-(SP)
	; A0 e' gia' settato dal chiamante (NON sovrascritto qui)

	; ================= CULL: il bob e' del tutto fuori? =================
	; Sta PRIMA di tutto, animazione compresa: un bob fuori schermo non
	; avanza i fotogrammi, esattamente come quando il cull era una routine
	; separata e il disegno non veniva nemmeno chiamato.
	; In Path B il bob si disegna alla sua posizione MONDO dentro il world
	; buffer ed e' la finestra di display a ritagliarlo: non serve clip
	; orizzontale, basta non disegnare chi e' del tutto fuori. L'unico
	; vincolo duro e' che la X MONDO resti dentro il buffer, altrimenti il
	; blit scrive prima dell'inizio della riga o oltre la sua fine.
	MOVE.W	bob_X(A0),D1
	TST.W	bob_WorldX(A0)
	BMI.W	.fuori					; X mondo negativa -> fuori dal buffer
	MOVE.W	#MAPPA_COLS*16,D4
	SUB.W	bob_Larghezza(A0),D4	; ultima X mondo ammessa
	CMP.W	bob_WorldX(A0),D4
	BLT.W	.fuori					; oltre il bordo destro della mappa
	MOVE.W	bob_Larghezza(A0),D4
	NEG.W	D4
	CMP.W	D4,D1
	BLE.W	.fuori					; tutto a sinistra della finestra
	CMP.W	#VIS_COLS*16,D1
	BGE.W	.fuori					; tutto a destra della finestra

	MOVE.W	bob_Y(A0),D1
	MOVE.W	bob_Altezza(A0),D4
	NEG.W	D4
	CMP.W	D4,D1
	BLE.W	.fuori					; tutto sopra la finestra
	CMP.W	#BG_VIS_ROWS,D1
	BGE.W	.fuori					; tutto sotto la finestra

	; ================= CLIP verticale =================
	; Di default si blitta il fotogramma intero.
	MOVE.W	#0,BobClipSkipRows
	MOVE.W	bob_Altezza(A0),BobClipNumRows
	TST.W	D1
	BPL.S	.clip_basso
	; bob_Y < 0: salta -bob_Y righe di sheet e disegna dalla cima
	MOVE.W	D1,D4
	NEG.W	D4
	MOVE.W	D4,BobClipSkipRows
	MOVE.W	bob_Altezza(A0),D4
	ADD.W	D1,D4					; altezza + bob_Y = righe da blittare
	MOVE.W	D4,BobClipNumRows
	MOVEQ	#0,D1					; il disegno parte da y=0
	BRA.S	.clip_fatto
.clip_basso:
	MOVE.W	#BG_VIS_ROWS,D4
	SUB.W	bob_Altezza(A0),D4		; ultima Y senza clip
	CMP.W	D4,D1
	BLE.S	.clip_fatto
	MOVE.W	#BG_VIS_ROWS,D4
	SUB.W	D1,D4					; righe ancora visibili
	MOVE.W	D4,BobClipNumRows
.clip_fatto:
	; Y SCHERMO da cui parte il disegno. Prima si sovrascriveva bob_Y e lo si
	; ripristinava dopo il blit, perche' col clip in alto il disegno deve
	; partire da 0: con una variabile a parte la struct non viene piu' toccata.
	MOVE.W	D1,BobDrawY

	; ----------------- Geometria dello sheet, DERIVATA -----------------
	; La struct porta solo bob_Frames e bob_Bande: pitch, slot, word del
	; blit, banda direzione e piano si ricavano da quelli piu' larghezza e
	; altezza del fotogramma, che c'erano gia'. Cosi' la stessa routine
	; disegna sheet di formato diverso senza duplicare nulla e senza tenere
	; in struct valori che sarebbero copie della stessa informazione.
	MOVE.W	bob_Larghezza(A0),D0
	LSR.W	#4,D0
	ADDQ.W	#1,D0					; +1 word: lo shift orizzontale sconfina
	MOVE.W	D0,BobGeoBlitW
	ADD.W	D0,D0					; slot = word del blit * 2 byte
	MOVE.W	D0,BobGeoSlot
	MULU.W	bob_Frames(A0),D0		; riga di sheet = fotogrammi * slot
	MOVE.W	D0,BobGeoPitch
	MULU.W	bob_Altezza(A0),D0		; banda direzione = altezza * riga
	MOVE.L	D0,D1					; D1 = banda, serve fra poche righe
	MULU.W	bob_Bande(A0),D0		; piano = banda * numero di bande
	MOVE.L	D0,BobGeoPlane

	; ----------------- Animazione -----------------
	; bob_IsMoving ha tre posizioni, non due:
	;    1  il fotogramma lo fa avanzare questa routine
	;    0  fermo, e il fotogramma torna a 0 (posa di riposo)
	;   <0  ANIM_ESTERNA: il fotogramma lo decide il proprietario del bob e qui
	;       non si tocca. Serve al falo', che ha una sequenza a ritroso con
	;       un'accensione che non si ripete.
	MOVE.W	bob_IsMoving(A0),D0
	BMI.S	.fineAnimazione
	BEQ.S	.notmoving
	ADD.W	#1,bob_FrameCont(A0)
	MOVE.W	bob_FrameCont(A0),D0
	CMP.W	bob_AnimDelay(A0),D0	; passo DI QUESTO bob, non piu' uguale per tutti
	BLT.S	.fineAnimazione
	CLR.W	bob_FrameCont(A0)
	; il wrap non e' piu' fisso a 8: la maschera e' bob_Frames-1
	MOVE.W	bob_AnimFrame(A0),D0
	ADDQ.W	#1,D0
	MOVE.W	bob_Frames(A0),D2
	SUBQ.W	#1,D2
	AND.W	D2,D0
	MOVE.W	D0,bob_AnimFrame(A0)
	BRA.S	.fineAnimazione
.notmoving:
	CLR.W	bob_FrameCont(A0)
	CLR.W	bob_AnimFrame(A0)
.fineAnimazione:
	; ----------------- Calcolo offset frame nello spritesheet -----------------
	; Lo slot e' piu' largo dell'arte: la word di stacco fra un frame e
	; l'altro e' quella su cui si spalma lo shift orizzontale.
	; La direzione va MASCHERATA sul numero di bande, non usata cruda: la banda
	; vale altezza*pitch anche quando lo sheet ne ha una sola, e li' coincide
	; con l'INTERO piano. Su uno sheet a banda unica (la pietra: banda 512 =
	; piano 512) una direzione diversa da zero manderebbe il blit a leggere
	; fuori dal piano, dentro la maschera e oltre. Con bob_Bande potenza di 2
	; la maschera vale 0 quando la banda e' unica, quindi la direzione si puo'
	; usare per altri scopi senza rischi.
	MOVE.W	bob_Direzione(A0),D3
	MOVE.W	bob_Bande(A0),D2
	SUBQ.W	#1,D2					; maschera = bande-1 (0 se banda unica)
	AND.W	D2,D3
	MULU.W	D1,D3					; Direzione * banda (D1 dal blocco geometria)
	MOVE.W	bob_AnimFrame(A0),D5
	MULU.W	BobGeoSlot,D5			; AnimFrame * slot (arte + stacco)
	ADD.W	D5,D3					; D3 = offset frame nel plane 0

	; ----------------- A2 = sorgente A (spritesheet plane 0) -----------------
	MOVE.L 	bob_Gfx(A0),A2
	ADDA.W	D3,A2
	; Applica clip top: sposta A2 in avanti di SkipRows * 40 byte
	MOVE.W	BobClipSkipRows,D2
	MULU.W	BobGeoPitch,D2			; D2 = skip * pitch sheet (long)
	ADDA.L	D2,A2					; A2 punta alla riga di partenza del frame
 	; ----------------- A3 = maschera PER-FRAME (canale A) -----------------
	; La silhouette del frame, non piu' un quadrato pieno: a 32x32 il quadrato
	; cancellerebbe lo sfondo su tutto il riquadro. Stesso layout dello sheet,
	; quindi stesso offset frame (D3) e stesso pitch. La maschera e' UNA sola
	; per tutti i 5 piani, quindi A3 non avanza nel loop dei piani.
	MOVE.L	bob_Mask(A0),A3
	ADDA.W	D3,A3					; stesso offset frame dell'arte
	MOVE.W	BobClipSkipRows,D2
	MULU.W	BobGeoPitch,D2			; D2 = skip * pitch sheet
	ADDA.L	D2,A3

	; ----------------- Calcolo destinazione e shift -----------------
	; bob_X = posizione X in pixel
	; D7 = shift = bob_X mod 16
	; D6 = byte offset (allineato a word) = (bob_X / 16) * 2
	MOVE.W	bob_X(A0),D6
	; Path B: i BOB si disegnano sul WORLD buffer, quindi la posizione va
	; convertita da coordinate SCHERMO a coordinate MONDO sommando la
	; camera. Senza questo finirebbero sempre nell'angolo alto-sinistro
	; della mappa invece che davanti al giocatore.
	ADD.W	PathBCamX,D6
	MOVE.W	D6,D7
	AND.W	#15,D7					; D7 = shift (0..15)
	LSR.W	#3,D6					; D6 = bob_X / 8 (in byte)
	AND.W	#$FFFE,D6				; D6 allineato a word

	; Path B: destinazione = world buffer (che E' quello visualizzato),
	; saltando la guardia del prefetch. Y in coordinate mondo.
	MOVEA.L	WorldDraw,A1			; si disegna nel buffer NON a video
	ADDA.L	#DELTA_MAPPAVERA+BG_ORIGIN_OFS,A1
	MOVE.W	BobDrawY,D0				; Y gia' clippata, non bob_Y grezza
	ADD.W	PathBCamY,D0
	MULU.W	#SFONDO_PITCH,D0
	ADD.W	D6,D0
	ADDA.L	D0,A1

	; ----------------- BLTCON0 = (shift << 12) | $0FCA -----------------
	; bit 15-12: ASH (shift sorgente A)
	; bit 11-8:  USEA|USEB|USEC|USED = $F
	; bit  7-0:  LF = $CA (cookie cut: D = (A AND B) OR (NOT A AND C))
	;            Qui c'era scritto "(C AND NOT B)", che e' un'altra funzione.
	;            $CA = %11001010, e i bit sono indicizzati da (A,B,C): valgono 1
	;            il 7 e il 6 (A=1,B=1, qualunque C) e il 3 e l'1 (A=0,C=1).
	;            Cioe' comanda A, che infatti e' la MASCHERA: dove vale 1 passa
	;            il BOB (B), dove vale 0 resta lo sfondo (C). Con "NOT B" il
	;            ruolo di maschera toccherebbe all'arte, e i registri qui sotto
	;            sono assegnati al contrario.
	MOVE.W	D7,D5
	LSL.W	#8,D5
	LSL.W	#4,D5					; D5 = shift << 12
	OR.W	#$0FCA,D5				; D5.w = BLTCON0 (cookie cut)

	; ----------------- BLTCON1 = BSH << 12 -----------------
	MOVE.W	D7,D6
	LSL.W	#8,D6
	LSL.W	#4,D6					; D6.w = BSH << 12 = BLTCON1

	; ----------------- BLTSIZE: NumRows righe x 2 word -----------------
	; NumRows = numero righe da blittare (default 16, o ridotto se clip Y)
	; 2 word per riga per gestire lo shift orizzontale.
	MOVE.W	BobClipNumRows,D4
	LSL.W	#6,D4					; D4 = NumRows << 6
	ADD.W	BobGeoBlitW,D4			; word per riga DI QUESTO sheet

	; ----------------- Registri "fissi" del blit settati una sola volta -----------------
	; Questi registri sono uguali per tutti i 5 plane, quindi li settiamo PRIMA
	; del loop dei plane invece che ad ogni iterazione.
	BSR.W	AspettaBlitter			; assicura che il blit precedente sia finito

	MOVE.L	#$ffffffff,$44(A6)		; BLTAFWM/BLTALWM = $FFFF/$FFFF
	MOVE.W	D5,$40(A6)				; BLTCON0 (con ASH = shift sulla MASCHERA = A)
	MOVE.W	D6,$42(A6)				; BLTCON1 (BSH = shift sul BOB = B)
	; I moduli dipendono dallo slot e dal pitch DI QUESTO sheet: con le EQU
	; cablate la routine funzionava solo per sheet fatti come Omino/Nemico.
	; D5/D6 sono gia' stati versati nell'hardware qui sopra, D2/D3 sono liberi.
	MOVE.W	BobGeoSlot,D3
	MOVE.W	#DEST_PITCH,D2
	SUB.W	D3,D2
	MOVE.W	D2,$60(A6)				; BLTCMOD (sfondo = dest)
	MOVE.W	D2,$66(A6)				; BLTDMOD (destinazione)
	MOVE.W	BobGeoPitch,D2
	SUB.W	D3,D2
	MOVE.W	D2,$62(A6)				; BLTBMOD (BOB nello sheet)
	MOVE.W	D2,$64(A6)				; BLTAMOD (maschera per-frame)

	; ----------------- Loop sui 5 bitplane -----------------
	; L'incremento per passare al plane successivo e' SEMPRE plane_size = 10240 byte.
	; Il valore di A1/A2 nei registri CPU NON viene modificato dal blitter
	; (il blitter modifica BLTAPT/BLTBPT/BLTCPT/BLTDPT, registri propri).
	; annota il rettangolo: il frame prossimo PathBRestoreAll lo ripulira'.
	; Va fatto ORA, con A1 ancora sul piano 1 e prima che il loop lo faccia
	; avanzare.
	MOVE.W	BobClipNumRows,D4
	MOVE.W	BobGeoBlitW,D5			; D5 = larghezza del rettangolo (word)
	BSR.W	PathBRegistraDirty
	MOVE.W	BobClipNumRows,D4
	LSL.W	#6,D4
	ADD.W	BobGeoBlitW,D4			; ricostruisce BLTSIZE, che D4 conteneva
	MOVEQ	#5-1,D0
.BlittaLoopBob:
	BSR.W	AspettaBlitter			; aspetta che il blit del plane precedente finisca
	MOVE.L	A1,$48(A6)				; BLTCPT (sfondo)
	MOVE.L	A2,$4C(A6)				; BLTBPT = BOB sorgente
	MOVE.L	A3,$50(A6)				; BLTAPT = MASCHERA
	MOVE.L	A1,$54(A6)				; BLTDPT (destinazione)

	MOVE.W	D4,$58(A6)				; BLTSIZE -> avvia blit

	ADDA.L	BobGeoPlane,A2			; prossimo plane sorgente BOB (B)
	ADD.L	#DEST_PLANE_SZ,A1		; prossimo plane di destinazione

	; A3 (MASCHERA = A) NON avanza: e' una sola per tutti i plane

	DBRA	D0,.BlittaLoopBob

.fuori:
	MOVEM.L	(SP)+,D0-D7/A0-A3
	RTS
* DisegnaBOBs - UNICA routine di disegno di tutti i bob
*   Sostituisce DisegnaBOBPlayer, DisegnaBOBEnemy e DisegnaBOBPietra, che
*   facevano la stessa identica cosa e differivano solo per come
*   raggiungevano la struct: prendere un bob, calcolare
*   bob_X/bob_Y = World - Camera, passarlo a cull, clip e blit.
*   I bob sono contigui sotto BobArray (vedi SECTION Entities): un solo ciclo
*   li percorre, e l'ordine in memoria E' lo z-order.
*   Il player ci passa come tutti gli altri, cull compreso. Non cambia nulla:
*   PLAYER_MAX_X = MAPPA_COLS*16-BOB_COLL_W = 368 coincide con la soglia di
*   cull (MAPPA_COLS*16 - bob_Larghezza), che scarta solo se MAGGIORE; e in Y
*   la camera lo tiene fra 0 e BG_VIS_ROWS-BOB_H = 144, cioe' esattamente il
*   limite oltre il quale scatterebbe il clip. Nessuna posizione raggiungibile
*   dal player viene cullata o clippata.
DisegnaBOBs:
	MOVEM.L	D0-D4/A0,-(SP)

	; camera in pixel, calcolata UNA volta per tutti i bob
	MOVE.W	TileX,D2
	LSL.W	#4,D2					; D2 = TileX*16
	ADD.W	PixelOffX,D2			; D2 = CameraX in pixel
	MOVE.W	TileY,D3
	LSL.W	#4,D3					; D3 = TileY*16
	ADD.W	PixelOffY,D3			; D3 = CameraY in pixel

	LEA		BobArray,A0
	MOVEQ	#BOB_TOTALI-1,D0
.loop:
	TST.W	bob_Active(A0)
	BEQ.S	.next					; slot spento: nemico morto, proiettile a riposo

	; bob_X/bob_Y (schermo) SEMPRE aggiornati, anche se poi il bob viene
	; cullato: altre routine li leggono (es. la camera legge Player+bob_X).
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	D2,D1
	MOVE.W	D1,bob_X(A0)
	MOVE.W	bob_WorldY(A0),D4
	SUB.W	D3,D4
	MOVE.W	D4,bob_Y(A0)

	BSR.W	DisegnaBOB				; cull, clip, blit e rettangolo sporco
.next:
	LEA		bob_Length(A0),A0		; prossimo bob
	DBRA	D0,.loop

	MOVEM.L	(SP)+,D0-D4/A0
	RTS
