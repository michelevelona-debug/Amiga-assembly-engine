; BufferChip.i - Buffer in chip RAM
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


	cnop	0,8
; QUI STAVA PathBVuoto, un piano vuoto da 14336 byte di chip (pitch 56 x 256).
; Serviva a PAR_DISABLE per dirottarci i piani 7-8 e misurare il costo della
; parallasse a bitplane. Quell'interruttore e' sparito col trasloco agli sprite
; il 5 settembre, il buffer e' rimasto: nessuna riga di codice lo nominava piu'.
	cnop	0,8
; COPIA DI LAVORO DELLA SCHERMATA DEL TITOLO. E' questa che va a video, non
; l'incbin: title_bpl fa da MASTER e non si tocca mai, cosi' il rettangolo
; dietro al droide si ripristina da una copia pulita invece di doverlo salvare
; prima di ogni disegno. Stessa struttura di PathBMaster/SFONDOGRANDE qui
; sotto, e per la stessa ragione.
; Costa 80 KB di chip. Il bilancio dice ~730 KB usati su 2048: si puo'.
TitoloBuf:
	ds.b	TITLE_PLANE_SIZE*TITLE_PIANI

	cnop	0,8
; Copia pulita della mappa, sorgente del restore dietro ai BOB.
PathBMaster:
	ds.b	5*SFONDO_PLANE_SIZE
	cnop	0,8
; Darkplane STATICO: stesso layout dei piani 1-5, disegnato una volta in
; coordinate mondo e fatto scorrere con loro. Sostituisce DARKPLANE_A/B.
PathBDarkPlane:
	ds.b	SFONDO_PLANE_SIZE

	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
	cnop	0,8				; allinea a 8 byte per AGA FMODE=3
; DOPPIO BUFFER DEL MONDO. Si disegna in WorldDraw e si visualizza WorldShow,
; scambiati in coda al blocco di lavoro da ScrollPathBApply. Serve perche' il
; blocco SCAVALCA il confine del quadro: senza secondo buffer il pennello puo'
; raggiungere un BOB ancora in corso di disegno e mostrarlo tagliato.
SFONDOGRANDE:
	ds.b	5*SFONDO_PLANE_SIZE	; 5 plane * SFONDO_PITCH * SFONDO_HEIGHT

	cnop	0,8
SFONDOGRANDE_B:
	ds.b	5*SFONDO_PLANE_SIZE	; secondo buffer del mondo, stesso layout di SFONDOGRANDE

	; I due buffer di parallasse sono puntati da BPL7PT/BPL8PT: con FMODE=3 il
	; puntatore deve essere allineato a 8 byte. Finora reggeva per ACCUMULO,
	; perche' 5*SFONDO_PLANE_SIZE e 2*PAR_PLANE_BANDA sono entrambi multipli di
	; 8 — ma bastava cambiare SFONDO_HEIGHT, il pitch o PAR_PLANE_BANDA per
	; romperlo IN SILENZIO. Meglio dichiararlo che sperarci.
	cnop	0,8
PannelloBuf:
	ds.b	4*PANNELLO_BUF_PLANE	; 4 piani, pitch del mondo, PANNELLO_HEIGHT righe

	; Qui stavano PARALLASSE_A, PARALLASSE_B (due buffer da 2 piani l'uno) e
	; PARALLAX_STRIP: in tutto ~141 KB di chip, liberati il 5 settembre col
	; passaggio della parallasse agli sprite, che di chip ne usa 27,8.
	cnop	0,8
; Maschera del disco di luce (bit=1 dentro). Sorgente A del blitter in
; DisegnaCerchioLuceBlitter. In chip RAM (la DMA del blitter la legge).
; Costruita una volta al boot da BuildLightMask.
LightMask:
	ds.b	LIGHT_MASK_BANDA*LIGHT_MASK_H	; 18 byte * 128 righe = 2304 byte

; Maschera dell'OMINO: 1 bitplane (10240 byte = 40*256) calcolata al boot
; come OR dei 5 bitplane dello spritesheet originale.
; Il blitter la usa come canale B per il cookie-cut nei BOB.
OMINO_MASK:
	ds.b	PLANE_SIZE			; 1 plane mask (stesso pitch di OMINO)

; Maschera del NEMICO: i nemici usano lo stesso DisegnaBOB ma un altro sheet,
; quindi serve la loro silhouette, non quella dell'omino.
NEMICO_MASK:
	ds.b	PLANE_SIZE			; 1 plane mask (stesso pitch di NEMICO)

; Maschera della PIETRA (il proiettile). Sheet piu' piccolo degli altri due,
; quindi la sua maschera e' grande quanto UN piano DI QUESTO sheet, non
; quanto PLANE_SIZE: e' il motivo per cui BuildBobMask ora prende la
; dimensione del piano come parametro invece di leggerla da una EQU globale.
PIETRA_MASK:
	ds.b	PIETRA_PLANE_SIZE	; 1 plane mask (stesso pitch di PIETRA)

; FALO' - spritesheet a 5 piani, piu' la sua maschera
; Sta qui e non fra i dati inizializzati perche' e' tutto costruito al boot:
; BuildFaloSheet espande la striscia a 2 piani dell'arte (falo_strip, che vive
; in fast RAM perche' la legge solo la CPU) nei 5 piani che vuole il blitter, e
; ne ricava subito la maschera. La maschera si fa LI' e non in BuildBobMasks:
; quella gira prima, e prenderebbe l'OR di cinque piani ancora vuoti.
; In BSS_C non occupa un byte nell'eseguibile, solo chip RAM a runtime.
; Il pitch dello sheet e' quello che DisegnaBOB DERIVA da larghezza, frame e
; bande, e coincide con quello della striscia perche' FALO_CELL_W discende da
; FALO_SLOT: sono la stessa catena, non due numeri da confrontare.
	cnop	0,8
FaloSheet:
	ds.b	FALO_PLANE_SZ*5		; 5 bitplane, stesso pitch della striscia
	cnop	0,8
FALO_MASK:
	ds.b	FALO_PLANE_SZ		; 1 plane mask (stesso pitch di FaloSheet)
