; ============================================================================
; QUESTO FILE NON SERVE PIU'. CANCELLALO, e con lui:
;
;     build\Gioco-misura-sprite.o
;
; Il .o vecchio (600 KB) e' quello che il linker continuava a prendere anche
; dopo: cancellare solo il sorgente non bastava.
;
; ----------------------------------------------------------------------------
; PERCHE' ERA SBAGLIATO
;
; Il build assembla TUTTI i .s della cartella e linka TUTTI gli .o. Quindi un
; secondo sorgente completo accanto a Gioco.s non e' un file di prova: e' un
; secondo programma, con dentro un'altra copia di ptplayer, e il linker si
; ferma su "Global symbol _mt_install ... is already defined".
;
; Gli innesti della misura sprite adesso si mettono e si tolgono DENTRO
; Gioco.s:
;
;     py tools\innesta-misura-sprite.py            li mette (con backup)
;     py tools\innesta-misura-sprite.py --togli    li toglie
;
; ----------------------------------------------------------------------------
; INTANTO CHE E' QUI
;
; Il contenuto e' vuoto: assemblandolo esce un .o senza simboli, che sovrascrive
; quello vecchio in build\ e toglie di mezzo l'errore del linker anche prima che
; tu cancelli i due file.
; ============================================================================

	end
