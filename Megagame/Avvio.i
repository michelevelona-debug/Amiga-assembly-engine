; Avvio.i - il punto di ingresso del programma.
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.
;
; PERCHE' ESISTE, ED E' UNA RIGA SOLA DI SOSTANZA.
; I fogli di tile si leggono da disco, e da disco si puo' leggere SOLO finche'
; il sistema operativo e' vivo. Guardare `Startup2.i`: `MAINCODE` fa `FORBID`
; (multitasking fermo) e `DISABLE` (interrupt della CPU mascherati), poi chiama
; `HEAVYINIT`, che spegne tutti gli INTENA e tutti i DMA e SOLO ALLORA chiama
; `START`. Cioe' **tutto il gioco gira dentro Forbid + Disable**, e una `Read()`
; di dos.library li' dentro aspetta un interrupt di device che non puo' mai
; arrivare: non e' un errore, e' un blocco.
;
; Quindi il caricamento deve avvenire PRIMA di `MAINCODE`. Il modo per stare
; prima di `MAINCODE` senza toccarlo e' essere il PRIMO codice della SECTION:
; su AmigaDOS l'esecuzione comincia dal primo byte del primo hunk, quindi basta
; che questo file sia incluso prima di `Startup2.i`.
;
; E `Startup2.i` NON SI TOCCA: e' codice di terze parti (Fabio Ciucci), e' in
; latin-1 mentre tutto il resto del progetto e' UTF-8, e un innesto li' dentro
; e' la modifica che poi nessuno si ricorda di aver fatto.
;
; JSR E NON BSR.W, e non e' una svista. `CaricaFogli` sta in `Arte.i`, cioe'
; dall'altra parte di un file unico da ~12000 righe: un BSR.W copre +-32 KB e
; quella distanza cresce a ogni modulo che si aggiunge in mezzo. Un JSR non ha
; limite di distanza, costa due byte in piu' e gira UNA VOLTA al boot. Qui il
; conto e' facile.

AvvioMegaGame:
	IFNE	FOGLIO_DA_FILE
	JSR		CaricaFogli				; i fogli di tile, finche' il DOS c'e'
	TST.W	D0						; D0 = 0 se e' andata
	BNE.S	.fine					; se no CaricaFogli ha gia' spiegato
	ENDC
	JSR		MAINCODE				; da qui in poi e' il gioco
.fine:
	RTS								; torna al CLI / Workbench
