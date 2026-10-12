; Display.i - Stato di display di una scena: titolo e gioco
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.

* ImpostaDisplayTitolo / ImpostaDisplayGioco
*   Lo stato di display di una scena, in un posto solo. IN: A6 = $DFF000.
*
* Il blocco della CPU non e' ridondante rispetto alla copperlist: il DMA
* bitplane si accende PRIMA che COP1LC punti alla lista, quindi fra
* l'accensione e la prima passata del copper il prelievo gira con quello che
* ha lasciato la scena precedente. E' esattamente il buco in cui era caduto
* FMODE, che dal blocco CPU mancava.
*
* I valori sono le EQU TIT_* e GIOCO_*, le stesse che leggono le copperlist:
* qui non c'e' un solo numero scritto a mano, ed e' il punto della modifica.
* NESSUN VALORE E' CAMBIATO: sono le stesse dodici MOVE di prima, nello stesso
* ordine, con i letterali sostituiti dalle EQU che valgono lo stesso.
*
* ImpostaDisplayGioco ne scrive TRE e non e' una dimenticanza: la copperlist
* del gioco scrive gia' FMODE, BPLCON0/1/2, i moduli, DDF e DIW a ogni quadro,
* mentre BPLCON3 e BPLCON4 ne stanno fuori di proposito (li governa il blocco
* PALETTE con LOCT alternato). Scriverli anche qui creerebbe la seconda copia
* che questa modifica sta togliendo.
ImpostaDisplayTitolo:
	MOVE.W	#TIT_FMODE,$1FC(A6)		; PRIMA di tutto: decide la larghezza del prelievo
	MOVE.W	#TIT_BPLCON0,$100(A6)	; 8 bitplane + COLOR + ECSENA
	MOVE.W	#TIT_BPLCON1,$102(A6)
	MOVE.W	#TIT_BPLCON2,$104(A6)
	MOVE.W	#TIT_BPLCON3,$106(A6)	; banco 0, LOCT=0, bordo nero
	MOVE.W	#TIT_BPLCON4,$10c(A6)
	MOVE.W	#TIT_BPLMOD,$108(A6)	; BPL1MOD: layout sequenziale
	MOVE.W	#TIT_BPLMOD,$10a(A6)	; BPL2MOD
	; ($a8-$28)/32 = 4 -> cinque prelievi per riga, 5*64 px = 320 px
	MOVE.W	#TIT_DDFSTRT,$92(A6)
	MOVE.W	#TIT_DDFSTOP,$94(A6)
	MOVE.W	#TIT_DIWSTRT,$8e(A6)
	MOVE.W	#TIT_DIWSTOP,$90(A6)
	RTS

ImpostaDisplayGioco:
	MOVE.W	#SCROLL_FMODE_VAL,$1fc(A6)	; prelievo del GIOCO, vedi SCROLL_FETCH_BIT
	MOVE.W	#BPLCON3_LOCT0,$106(A6)
	MOVE.W	#GIOCO_BPLCON4,$10c(A6)		; sprite alle voci 64..79
	RTS
