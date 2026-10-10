; Chip.i - Dati in chip RAM: copperlist, grafica
; Incluso da Gioco.s: contiene solo codice/dati, la SECTION la dichiara Gioco.s.


; TITLE COPPERLIST - 8 bitplane AGA, lores 320x256, palette caricata via CPU.
; I puntatori BPL1..8PT (etichette TitleBPL_*) vengono patchati a runtime
; in ShowTitle a partire da TitoloBuf (10240 byte per plane, layout SEQUENTIAL).
; NON da title_bpl: quello e' il master da cui si ripristina il rettangolo
; dietro al droide, e non deve mai andare a video.
	cnop	0,4
TitleCopperList:
	; Forza FMODE = $03 (BPL32+BPAGEM) all'inizio del frame, in caso qualcuno
	; (PT Player IRQ, OS, ecc.) lo abbia resettato. FMODE va impostato PRIMA
	; di abilitare BPL DMA per garantire il fetch a 64-bit allineato.
	; I valori sono le EQU TIT_*, le STESSE che scrive ImpostaDisplayTitolo:
	; erano dodici numeri scritti due volte in due punti lontani del file.
	dc.w	$01fc,TIT_FMODE		; FMODE = BPL32 + BPAGEM (64-bit fetch)
	dc.w	$0100,TIT_BPLCON0	; BPU3=1 (8 BPL) + COLOR + ECSENA (no UHRES)
	dc.w	$0102,TIT_BPLCON1
	dc.w	$0104,TIT_BPLCON2	; PF2P=4, PF1P=4 (come gioco)
	; BRDRBLNK acceso anche qui: senza, l'area fuori dalla finestra mostra
	; COLOR00 e il titolo appare dentro una cornice chiara.
	dc.w	$0106,TIT_BPLCON3	; banca 0, LOCT=0, bordo NERO
	dc.w	$010c,TIT_BPLCON4	; sprite a colori OCS standard 16-31
	dc.w	$0108,TIT_BPLMOD	; BPL1MOD (sequential layout)
	dc.w	$010a,TIT_BPLMOD	; BPL2MOD
	dc.w	$0092,TIT_DDFSTRT	; lores 8 BPL AGA FMODE=3
	dc.w	$0094,TIT_DDFSTOP	; 5 fetch FMODE=3 allineati
	dc.w	$008e,TIT_DIWSTRT	; finestra propria del titolo, vedi le EQU
	dc.w	$0090,TIT_DIWSTOP
TitleBPL_0:	dc.w	$00e0,$0000,$00e2,$0000	; BPL1PT (high, low)
TitleBPL_1:	dc.w	$00e4,$0000,$00e6,$0000	; BPL2PT
TitleBPL_2:	dc.w	$00e8,$0000,$00ea,$0000	; BPL3PT
TitleBPL_3:	dc.w	$00ec,$0000,$00ee,$0000	; BPL4PT
TitleBPL_4:	dc.w	$00f0,$0000,$00f2,$0000	; BPL5PT
TitleBPL_5:	dc.w	$00f4,$0000,$00f6,$0000	; BPL6PT
TitleBPL_6:	dc.w	$00f8,$0000,$00fa,$0000	; BPL7PT
TitleBPL_7:	dc.w	$00fc,$0000,$00fe,$0000	; BPL8PT
	; Past line 255 + wait V=300, poi spegne i bitplane
	dc.w	$FFDF,$FFFE
	dc.w	$2C01,$FF00
	dc.w	$0100,%0000001000000001			; BPLCON0 = 0 BPL + ECSENA
	dc.w	$FFFF,$FFFE			; FINE COPPERLIST

; ---------------------------------------------------------------------------
; COPPERLIST DELL'INTRO. Stessa geometria della title - le stesse EQU TIT_* -
; piu' il blocco che riscrive TUTTA la palette a ogni quadro. Il blocco sta in
; testa, prima che il display cominci: il pennello non vede mai una palette a
; meta'. Il codice che lo riempie e' in Intro.i.
; ---------------------------------------------------------------------------
	cnop	0,4
IntroCopperList:
	dc.w	$01fc,TIT_FMODE
	dc.w	$0100,TIT_BPLCON0
	dc.w	$0102,TIT_BPLCON1
	dc.w	$0104,TIT_BPLCON2
	dc.w	$0106,TIT_BPLCON3
	dc.w	$010c,TIT_BPLCON4
	dc.w	$0108,TIT_BPLMOD
	dc.w	$010a,TIT_BPLMOD
	dc.w	$0092,TIT_DDFSTRT
	dc.w	$0094,TIT_DDFSTOP
	dc.w	$008e,TIT_DIWSTRT
	dc.w	$0090,TIT_DIWSTOP
IntroBPL_0:	dc.w	$00e0,$0000,$00e2,$0000	; BPL1PT (patchati da IntroEsegui)
IntroBPL_1:	dc.w	$00e4,$0000,$00e6,$0000
IntroBPL_2:	dc.w	$00e8,$0000,$00ea,$0000
IntroBPL_3:	dc.w	$00ec,$0000,$00ee,$0000
IntroBPL_4:	dc.w	$00f0,$0000,$00f2,$0000
IntroBPL_5:	dc.w	$00f4,$0000,$00f6,$0000
IntroBPL_6:	dc.w	$00f8,$0000,$00fa,$0000
IntroBPL_7:	dc.w	$00fc,$0000,$00fe,$0000
; La palette: ALBA_COP_BANCHI banchi, e per ognuno una MOVE su BPLCON3 piu'
; ALBA_COP_SLOT MOVE sui COLORxx, due volte (nibble alti e bassi). Nasce a
; ZERO, cioe' MOVE su BLTDDAT, che e' innocuo ma inutile: AlbaCostruisciCopper
; ci scrive i registri e AlbaPalette i valori, tutti e due PRIMA che il copper
; venga puntato qui.
	cnop	0,4
AlbaCopper:
	ds.w	ALBA_COP_WORDS
; Il blocco lascia BPLCON3 sul banco 7 con LOCT=1. Al display non importa -
; banco e LOCT decidono solo dove finiscono le SCRITTURE sui colori, non cosa
; legge il pennello - ma lasciare un registro in uno stato qualsiasi e' il
; modo in cui in questo sorgente sono gia' nati due difetti. Costa una MOVE.
	dc.w	$0106,BPLCON3_LOCT0
	dc.w	$FFDF,$FFFE			; arma i WAIT oltre la riga 255
	dc.w	$2C01,$FF00
	dc.w	$0100,%0000001000000001			; BPLCON0 = 0 BPL + ECSENA
	dc.w	$FFFF,$FFFE			; FINE COPPERLIST

CopperList:
	; Il gioco gira a SEI bitplane lores: 1-5 = sfondo, 6 = darkplane. La
	; parallasse non e' piu' sui piani 7-8, sta sugli sprite dal 5 settembre, e
	; il prelievo e' a 16 bit (SCROLL_FETCH_BIT), non a 64: e' proprio il
	; prelievo stretto che apre i sette canali sprite. Qui c'era scritto
	; "8 bitplane, fetch a 64 bit, piani 7-8 = parallasse", vero fino ad agosto.
	; Il "fetch-ahead" in fondo
	; allo schermo legge oltre i piani: per renderlo innocuo i 5 piani di
	; BPSFONDO sono distanziati da BG_PLANE_BANDA (con righe di padding vuote
	; tra un piano e l'altro), cosi' il prefetch pesca righe blank invece dei
	; dati del piano successivo. Vedi BG_PLANE_BANDA / BG_PAD_ROWS.
	dc.w	$01fc,SCROLL_FMODE_VAL	; FMODE: 16, 32 o 64 bit secondo SCROLL_FETCH_BIT
	; Sei piani: i due della parallasse sono passati agli sprite. Non e' solo
	; risparmio, e' un requisito - il prelievo a 16 bit che apre i sei canali
	; ne regge sei e basta in lores.
	; L'etichetta serve alla tenda: MondoNascondi/MondoMostra scrivono QUI, nel
	; dato della copperlist, invece di scrivere $100(A6) con la CPU. E' la
	; stessa lezione di BPLCON1: un registro che il copper riscrive a ogni
	; quadro, se lo tocca la CPU, dura fino al quadro dopo e non oltre.
CL_Bplcon0:
	dc.w	$0100,BPLCON0_GIOCO			; BPLCON0: 6 bitplane, color burst + ECSENA
	; (via anche il bit 7 UHRES che ci trascinavamo). L'EHB non c'entra:
	; il dimezzamento notturno lo fanno i colori 32..63, e i piani 7-8
	; portano il parallasse a 4 colori (vedi InitPalette8BPL).
				  ;5432109876543210
; bit 15		HiRes
; bit 14-12		Numero di Bitplanes
; bit 11		HAM
; bit 10 		Dual Playfield
; bit 9			Color burst
; bit 8			GENLOCK AUDIO
; bit 7			UHRES (NON e' EHB! L'EHB non ha un bit: scatta solo con BPU=6)
; bit 6-4		non utilizzati
; bit 3			Light Pen
; bit 2			LACE
; bit 1			External Resync
; bit 0 		non utilizzato (ECSENA per AGA palette)

CL_BplCon1:
	dc.w	$102,0			; BplCon1 (patchato per frame dallo scroll hardware)
	; BPLCON2, bit 5-3 = PF2P e 2-0 = PF1P: il valore e' quante COPPIE di sprite
	; stanno DAVANTI al playfield. 0 = nessuna (playfield davanti a tutti gli
	; sprite, che si vedono solo dove il playfield ha indice 0); 4 = tutte e
	; quattro, cioe' gli sprite davanti a tutto.
	; MISURATO, non dedotto: con $0000 le barre di prova si vedevano sul cielo
	; ma sparivano dietro ai tronchi; togliendolo, con $0024, sono passate
	; davanti a tutto. Due osservazioni indipendenti e concordi.
	; La parallasse e' uno SFONDO: deve stare dietro alle tile e al player.
	dc.w	$104,$0000		; playfield davanti a tutti gli sprite
	; bit 5-3 = PF2P, bit 2-0 = PF1P (4 = primi 4 sprite davanti)
	; Nota: BPLCON3 e BPLCON4 NON sono qui perche' la PALETTE section piu' avanti
	; gia' imposta BPLCON3 (con LOCT alternato) e nessuno modifica BPLCON4 a runtime.
	; Settarli qui rompe la palette degli sprite hardware (es. falo' diventa verde).
; ATTENZIONE: i valori scritti qui in CL_BplMod e CL_Ddf sono SEGNAPOSTO.
; PathBInit li sovrascrive al boot con SCROLL_BPLMOD, SCROLL_DDFSTRT e
; SCROLL_DDFSTOP (patch su CL_BplMod+2/+6 e CL_Ddf+2/+6), quindi la geometria
; che va davvero a video e' quella di ScrollHW.i, non questa. Restano perche'
; la copperlist dev'essere sintatticamente completa prima della patch.
CL_BplMod:
	dc.w	$108,BPSF_PITCH-40	; SEGNAPOSTO Path A: sovrascritto con SCROLL_BPLMOD
	dc.w	$10A,BPSF_PITCH-40	; SEGNAPOSTO Path A: sovrascritto con SCROLL_BPLMOD
CL_Ddf:
	dc.w 	$0092,$0038,$0094,$00b8 ; SEGNAPOSTO (5 fetch): sovrascritti con SCROLL_DDFSTRT/STOP
	; DIWSTOP verticale arriva a PANNELLO_BOT_RASTER, non a fine area di gioco:
	; la fascia del pannello deve stare DENTRO la finestra, altrimenti sarebbe
	; bordo e non si vedrebbe.
	; Il V8 di DIWSTOP e' implicito come complemento di V7: con 302 il byte
	; basso vale $2E, che ha V7=0, quindi il complemento mette V8=1 e il conto
	; torna (256+46 = 302).
	; NB: qui c'era una PRIMA coppia $008e/$0090 che fermava DIWSTOP a
	; $2C+BG_VIS_ROWS. Senza WAIT fra le due vinceva comunque questa, quindi
	; era un residuo che il copper eseguiva ogni frame senza effetto: tolta.
	dc.w	$008e,($2C<<8)|DIW_H_START,$0090,((PANNELLO_BOT_RASTER&$FF)<<8)|DIW_H_STOP	; DiwStrt - DiwStop

BitPlaneTiles:
	dc.w 	$e0,$0000,$e2,$0000	;primo   bitplane - BPL0PT
	dc.w 	$e4,$0000,$e6,$0000	;secondo bitplane - BPL1PT
	dc.w 	$e8,$0000,$ea,$0000	;terzo   bitplane - BPL2PT
	dc.w 	$ec,$0000,$ee,$0000	;quarto  bitplane - BPL3PT
	dc.w 	$f0,$0000,$f2,$0000	;quinto  bitplane - BPL4PT
	dc.w 	$f4,$0000,$f6,$0000	;sesto   bitplane - BPL5PT (EHB dark mask)

; Qui stavano BPL7PT/BPL8PT, i due piani della parallasse. Dal 5 settembre la
; parallasse vive sugli sprite e i piani sono sei: quei due puntatori non li
; leggeva piu' nessuno (BPU=6) e occupavano quattro MOVE del copper a quadro.

Sprites:
	dc.w	$120,0,$122,0			; SPR0PT (AggiornaCopperSPR al boot, poi
	; AggiornaParallasseSprite a ogni quadro: SPR0..SPR6 sono
	; gli alberi, e il puntatore e' quello che sceglie la posa)
	dc.w	$124,0,$126,0			; SPR1PT
	dc.w	$128,0,$12a,0			; SPR2PT
	dc.w	$12c,0,$12e,0			; SPR3PT
	dc.w	$130,0,$132,0			; SPR4PT
	dc.w	$134,0,$136,0			; SPR5PT
	dc.w	$138,0,$13a,0			; SPR6PT
	dc.w	$13c,0,$13e,0			; SPR7PT

; PALETTE AGA (24-bit, 32 colori)
; Strutturata come due blocchi consecutivi nella copperlist:
;   - Blocco 1: BPLCON3 con LOCT=0, scrive nibble ALTI di ogni canale RGB
;   - Blocco 2: BPLCON3 con LOCT=1, scrive nibble BASSI di ogni canale RGB
; Conversione OCS->AGA per ognuno dei 32 colori:
;   colore OCS $0RGB -> 24-bit $0RRGGBB con R duplicato in RR, ecc.
;   es. $0fff -> $0FFFFFF (R=$FF, G=$FF, B=$FF)
;   In questo caso i 4 bit alti = i 4 bit bassi = il valore originale.
;   Quindi entrambe le passate scrivono lo stesso valore di nibble.
; BPLCON3 = $0a0c0:
;   bit 9   = LOCT (0 = nibble alti, 1 = nibble bassi)
;   bit 13-15 = PALBANK (0 = banca 0)
;   bit 10  = BRDRBLNK (1 = bordo blank)
;   bit 6   = SPRES (0 = sprite a hires)
;   bit 5-4 = riservati 0
;   bit 0-3 = utilizzati per setting vari (qui = $0)
; Valore $0c00 = LOCT=0, banca 0, bordo blank
; Valore $0e00 = LOCT=1, banca 0, bordo blank
PALETTE:
	; BPLCON4: bit 15-8 BPLAM (XOR sull'indice dei bitplane), 7-4 ESPRM e 3-0
	; OSPRM (i 4 bit ALTI dell'indice sprite, pari e dispari). Il valore vero lo
	; scrive il blocco degli alberi piu' sotto: $0044, sprite alle voci 64..79.

	; ----- Blocco 1: nibble ALTI (LOCT=0) -----
	dc.w	$0106,BPLCON3_LOCT0		; BPLCON3 = LOCT=0
GamePalHi:
	; COLOR00: durante il profiling diventa un NO-OP copper ($1fe), altrimenti
	; il copper lo riporterebbe a nero in cima a ogni frame cancellando la
	; fascia BLU scritta dalla CPU nel blanking precedente.
	IFNE	PROFILING*PROF_KILL_SKY
	dc.w	$01fe,$0000			; NO-OP: COLOR00 riservato alle fasce
	ENDC
	IFEQ	PROFILING*PROF_KILL_SKY
	IFNE	CIELO_GRADIENTE
	dc.w	$0180,$0000			; nero: lo riscrive SkyCopper riga per riga
	ENDC
	IFEQ	CIELO_GRADIENTE
	dc.w	$0180,CIELO_FISSO_HI	; la tinta unica del cielo, nibble alti
	ENDC
	ENDC
	dc.w 	$0182,$0fff,$0184,$0040,$0186,$0070
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0850
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	; COLOR13/14/15 = le tre tinte del falo'. Erano tre viola che nessuna
	; arte a 5 piani usava: verificato contando gli indici davvero presenti
	; in Tiles, Omino32, Nemico32 e Pietra. Derivati da FALO_C*_RGB.
	dc.w 	$0198,$000f,$019a,FALO_C1_HI,$019c,FALO_C2_HI,$019e,FALO_C3_HI
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca
	dc.w 	$01a8,$0000,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff
	; ----- Blocco 2: nibble BASSI (LOCT=1) -----
	dc.w	$0106,BPLCON3_LOCT1		; BPLCON3 = LOCT=1
GamePalLo:
	IFNE	PROFILING*PROF_KILL_SKY
	dc.w	$01fe,$0000			; NO-OP (vedi GamePalHi)
	ENDC
	IFEQ	PROFILING*PROF_KILL_SKY
	IFNE	CIELO_GRADIENTE
	dc.w	$0180,$0000
	ENDC
	IFEQ	CIELO_GRADIENTE
	dc.w	$0180,CIELO_FISSO_LO	; nibble bassi: senza questi uscirebbe $7799CC
	ENDC
	ENDC
	dc.w 	$0182,$0fff,$0184,$0040,$0186,$0070
	dc.w 	$0188,$00c0,$018a,$0410,$018c,$0621,$018e,$0880
	dc.w 	$0190,$00b6,$0192,$00dd,$0194,$00af,$0196,$007c
	; COLOR13/14/15: nibble bassi delle stesse tre tinte del falo'.
	dc.w 	$0198,$000f,$019a,FALO_C1_LO,$019c,FALO_C2_LO,$019e,FALO_C3_LO
	dc.w 	$01a0,$0620,$01a2,$0e52,$01a4,$0a52,$01a6,$0fca
	dc.w 	$01a8,$0000,$01aa,$0444,$01ac,$0555,$01ae,$0666
	dc.w 	$01b0,$0777,$01b2,$0888,$01b4,$0999,$01b6,$0aaa
	dc.w 	$01b8,$0ccc,$01ba,$0ddd,$01bc,$0eee,$01be,$0fff

	; ----- BANCO 1: i colori 32..63, LO SFONDO NOTTURNO -----
	; Il valore di ogni voce e' il banco 0 dimezzato, e le voci le riempie
	; BuildNotteCopper al boot: qui c'e' solo lo spazio, esattamente come fa
	; SkyCopper piu' sotto. Le tre coppie di BPLCON3 invece sono letterali,
	; perche' non dipendono dalla palette.
	; Fino al 24 settembre 2026 questo banco lo scriveva la CPU una volta sola
	; (InitPalette8BPL -> WriteAGABank32) e nei registri ci restava. Adesso lo
	; riscrive il copper a ogni quadro come gli altri due banchi: 134 word,
	; ~1,2 righe raster, ed e' quello che permette alla dissolvenza di
	; raggiungere la notte (vedi NOTTE_VOCI).
	dc.w	$0106,(1<<BPLCON3_BANK_SHIFT)|BPLCON3_LOCT0
NotteHi:
	ds.w	NOTTE_VOCI*2
NotteHiFine:
	IFNE	(NotteHiFine-NotteHi)/4-NOTTE_VOCI
GUARDIA_NOTTE_HI	EQU		1/0
	ENDC
	dc.w	$0106,(1<<BPLCON3_BANK_SHIFT)|BPLCON3_LOCT1
NotteLo:
	ds.w	NOTTE_VOCI*2
NotteLoFine:
	IFNE	(NotteLoFine-NotteLo)/4-NOTTE_VOCI
GUARDIA_NOTTE_LO	EQU		1/0
	ENDC

	; Ripristino BPLCON3 a default LOCT=0 (per il prossimo frame)
	dc.w	$0106,BPLCON3_LOCT0

	; ----- I COLORI DELLA PARALLASSE SUGLI SPRITE -----
	; A sei bitplane l'arte arriva all'indice 63, quindi 64..255 sono liberi:
	; BPLCON4 con ESPRM=OSPRM=$4 manda gli sprite alle voci 64..79, dove non
	; puo' arrivare nessun pixel di bitplane. BPLAM resta $00.
	; Le tinte sono PER COPPIA di canali: 65/66/67 per SPR0-1, 69/70/71 per
	; SPR2-3, 73/74/75 per SPR4-5, 77/78/79 per SPR6-7. Dodici voci contro le
	; 192 dei banchi 2..7 che servivano quando la parallasse stava nei bitplane.
	; LE COPPIE SONO QUATTRO, non tre: scrivendone tre l'albero del canale 6
	; esce col colore che nessuno ha inizializzato. Chi aggiunge un canale
	; aggiunge la sua coppia.
	; Le voci sopra la 31 vogliono la BANCA 2 in BPLCON3 (colori 64..95): li'
	; i registri $0180..$019e SONO quelle voci.
	;
	; DENTRO una coppia i tre valori sono OMBRA, CORPO, LUCE - non tre
	; profondita'. La profondita' la fa la coppia: 0 e 1 (canali 0..3) i vicini,
	; 2 e 3 (canali 4..6) i lontani. E' quello che ha sbloccato i due terzi di
	; palette sprite che stavano fermi: ogni albero usava un colore su tre.
	; Il generatore si rifiuta di produrre l'arte se la mappa canale->livello
	; non e' 1,1,1,1,3,3,3, perche' da qui in poi quella mappa e' portante.
	dc.w	$010c,GIOCO_BPLCON4	; ESPRM=OSPRM=$4, sprite a 64..79. Stessa EQU
								; che scrive ImpostaDisplayGioco: era un $0044
								; ricopiato in due posti.
	dc.w	$0106,(2<<BPLCON3_BANK_SHIFT)|BPLCON3_LOCT0
	; Le due etichette servono alla dissolvenza: dodici coppie contigue da 4
	; byte col valore a +2, esattamente come GamePalHi/GamePalLo. I numeri di
	; registro NON sono consecutivi (le voci 64, 68, 72 e 76 restano all'arte)
	; ma alla passeggiata del fade non interessa: legge le coppie, non i
	; registri. L'ORDINE qui e' anche quello di AlberiPal24, e le due cose
	; devono restare allineate.
AlberiPalHi:
	dc.w	$0182,ALB_V_OMBRA_HI,$0184,ALB_V_CORPO_HI,$0186,ALB_V_LUCE_HI
	dc.w	$018a,ALB_V_OMBRA_HI,$018c,ALB_V_CORPO_HI,$018e,ALB_V_LUCE_HI
	dc.w	$0192,ALB_L_OMBRA_HI,$0194,ALB_L_CORPO_HI,$0196,ALB_L_LUCE_HI
	dc.w	$019a,ALB_L_OMBRA_HI,$019c,ALB_L_CORPO_HI,$019e,ALB_L_LUCE_HI
AlberiPalHiFine:
	IFNE	(AlberiPalHiFine-AlberiPalHi)/4-FADE_VOCI_ALBERI
GUARDIA_ALBERI_HI	EQU		1/0
	ENDC
	dc.w	$0106,(2<<BPLCON3_BANK_SHIFT)|BPLCON3_LOCT1
AlberiPalLo:
	dc.w	$0182,ALB_V_OMBRA_LO,$0184,ALB_V_CORPO_LO,$0186,ALB_V_LUCE_LO
	dc.w	$018a,ALB_V_OMBRA_LO,$018c,ALB_V_CORPO_LO,$018e,ALB_V_LUCE_LO
	dc.w	$0192,ALB_L_OMBRA_LO,$0194,ALB_L_CORPO_LO,$0196,ALB_L_LUCE_LO
	dc.w	$019a,ALB_L_OMBRA_LO,$019c,ALB_L_CORPO_LO,$019e,ALB_L_LUCE_LO
AlberiPalLoFine:
	IFNE	(AlberiPalLoFine-AlberiPalLo)/4-FADE_VOCI_ALBERI
GUARDIA_ALBERI_LO	EQU		1/0
	ENDC
	dc.w	$0106,BPLCON3_LOCT0	; banca 0, LOCT 0: da qui in giu' tutto come prima

; Gradiente cielo: e' parte della copperlist perche' cambia COLOR00 riga per
; riga, in sincrono col pennello.
; VERIFICATO sul contenuto di CieloCopper.i: scrive SOLO due registri, BPLCON3
; ($106, per alternare LOCT fra nibble alti e bassi) e COLOR00 ($180). NON
; tocca i puntatori bitplane, quindi non interferisce con lo scroll hardware
; che riscrive BPL1PT..BPL6PT a ogni frame. Il vecchio commento qui diceva che
; scriveva a BPL1PT..BPL5PT: era falso.
; Copre esattamente le righe visibili, da $2c a $2c+BG_VIS_ROWS-1, perche' la
; lista e' generata su misura. Lascia BPLCON3 a LOCT=0 in coda.
; Va ESCLUSO solo se si vuole leggere il costo delle fasi dalle fasce colorate
; a bordo schermo (PROF_KILL_SKY=1): riscrivendo COLOR00 su ogni riga le
; coprirebbe nell'area di gioco. La misura numerica del monitor P non ne
; risente in nessun caso.
	IFNE	CIELO_GRADIENTE
	IFEQ	PROFILING*PROF_KILL_SKY
	; Il gradiente NON e' piu' un include statico: BuildSkyCopper riempie questo
	; spazio al boot ricampionando SkyGradient su BG_VIS_ROWS righe, cosi' resta
	; interamente visibile qualunque sia CUT_BOTTOM_ROWS. Lo spazio sta QUI, in
	; linea nella copperlist, per non cambiare nulla di dove vive la lista.
SkyCopper:
	ds.w	SKY_COPPER_WORDS
	ENDC
	ENDC

; Spegne il DMA bitplane in fondo allo schermo. Senza, il fetch continua oltre
; BPSFONDO (pitch 40) dentro SFONDOGRANDE (pitch 48) e legge a mosaico pezzi di
; righe diverse: riga parziale e sfarfallante in fondo.
; Lo spegnimento va a FINE scanline 299 (H=$E0), non all'inizio di V=300: il
; fetch della riga 300 parte a DDFSTRT prima che il copper, che ha priorita' DMA
; piu' bassa del bitplane, riesca a scrivere BPLCON0=0. Spegnendo a 299/$E0 la
; riga di over-fetch non avviene MAI.
; Il VP del copper e' a 8 bit: per V>=256 serve prima WAIT $FFDF,$FFFE.
	; CONFINE AREA DI GIOCO / PANNELLO
	; A PANNELLO_TOP_RASTER si passa dal mondo (buffer che scorre) al pannello
	; (4 piani, buffer fisso). I moduli NON si toccano: il buffer del pannello ha
	; lo stesso pitch del mondo apposta, quindi il fetch non va ritarato.
	; Il WAIT vale $DC03: VP=$DC=220, HP=1. Quel $DC e' un numero di RIGA, non
	; una posizione orizzontale.
	; Qui la posizione orizzontale non e' critica: le righe di separazione girano
	; a 0 piani, quindi niente DMA bitplane e il copper ha la riga per se'. Sono
	; 36 MOVE da 2 color clock = 72 cc su 227. I puntatori dei bitplane stanno
	; dopo il WAIT successivo, dove invece la posizione conta.
	dc.w	((PANNELLO_TOP_RASTER&$FF)<<8)|$02|$01,$FFFE	; WAIT righe di separazione
	; BPLCON0 per PRIMO: deve valere prima che parta il fetch, e costa un MOVE
	; solo. Poi i quattro puntatori, in ordine naturale. BPLCON1 e COLOR00 vanno
	; in coda: a loro basta arrivare prima della parte VISIBILE della riga, che
	; comincia molto piu' tardi, quindi possono cadere anche dopo DDFSTRT.
	; --- righe di separazione: bitplane spenti, e qui si carica la palette ---
	dc.w	$0100,%0000001000000001 		; BPLCON0: 0 bitplane
	; La palette del pannello e' lo stesso file INCLUSO DUE VOLTE: una con LOCT=0
	; per i nibble alti e una con LOCT=1 per i bassi. Scrivendo lo stesso valore
	; in entrambi si ottiene l'espansione 12->24 bit ($F diventa $FF), che e' la
	; convenzione con cui e' fatta anche la palette del gioco.
	dc.w	$0106,BPLCON3_LOCT0
	include	"Pannello.cop"
	dc.w	$0106,BPLCON3_LOCT1
	include	"Pannello.cop"
	dc.w	$0106,BPLCON3_LOCT0

	; --- colore della barra ALTA (energia) ---
	; Le voci 13 e 14 sono la coppia scura/viva dell'indicatore, e il loro
	; colore dipende dal LIVELLO: rosso in basso, giallo in alto. Non ci sono
	; sei voci di palette libere per tenere le tre fasce tutte insieme, quindi
	; il colore lo cambia il copper e le voci restano due.
	; Sta QUI, nelle righe di separazione, e non nel blocco dell'arte: quello ha
	; 2 color clock di margine prima di DDFSTRT e cinque MOVE in piu' lo
	; sfonderebbero. Qui i bitplane sono spenti e non c'e' nessuna corsa.
	; Le word dei colori le riscrive DisegnaIndicatori: sono a +2 e +6 da
	; ognuna delle due etichette. LOCT0 e' gia' impostato dalla riga qui sopra.
IndicAltoHi:
	dc.w	$019A,$0c23,$019C,$0f68
	dc.w	$0106,BPLCON3_LOCT1
IndicAltoLo:
	dc.w	$019A,$0c23,$019C,$0f68
	dc.w	$0106,BPLCON3_LOCT0

	; --- inizio dell'arte: puntatori e 4 bitplane ---
	; QUI la posizione orizzontale del WAIT e' il valore piu' delicato del blocco.
	; Da cc 2 seguono 10 MOVE (8 word di puntatore, BPLCON0, BPLCON1) da 2 color
	; clock l'una: finiscono verso il cc 22, e il DMA bitplane di QUESTA riga
	; parte a DDFSTRT = $18 = 24. Restano 2 cc di margine. Se i puntatori
	; arrivassero dopo, i piani continuerebbero a leggere il buffer del MONDO e
	; resterebbero sfasati per tutto il frame: a schermo i colori delle tile
	; mescolati al pannello.
	; NON c'e' invece nessuna corsa col DMA sui puntatori: la riga precedente
	; (221) e' di separazione e gira a 0 piani, quindi non sfora nessun fetch
	; dentro questa riga e non c'e' auto-incremento che se li mangi. E' il motivo
	; per cui la compensazione che stava in DisegnaPannello e' stata tolta.
	; TARATURA: alzare la posizione orizzontale di 2 alla volta sposta le
	; scritture piu' avanti nella riga; oltre DDFSTRT (24) e' troppo tardi.
	dc.w	((PANNELLO_ART_RASTER&$FF)<<8)|$02|$01,$FFFE	; WAIT inizio arte
BitplanePannello:
	dc.w	$00e0,0,$00e2,0		; BPL1PT (riempiti da DisegnaPannello, una volta al boot)
	dc.w	$00e4,0,$00e6,0		; BPL2PT
	dc.w	$00e8,0,$00ea,0		; BPL3PT
	dc.w	$00ec,0,$00ee,0		; BPL4PT
	dc.w	$0100,%0100001000000001 ; BPLCON0: 4 bitplane (BPU=4), COLOR, ECSENA
	dc.w	$0102,$0000			; BPLCON1: niente scorrimento fine qui

	; --- colore della barra BASSA (vita) ---
	; I due riquadri stanno su righe raster diverse, quindi possono avere due
	; colori diversi nello stesso quadro: basta ricambiare le voci 13 e 14 fra
	; l'uno e l'altro. Il WAIT e' sulla PRIMA riga del riquadro basso; il
	; riquadro alto e' finito 10 righe prima.
	; Cinque MOVE da 2 color clock finiscono verso il cc 12, e il primo pixel
	; visibile e' al 64: qui il margine e' largo, al contrario del blocco dei
	; puntatori qui sopra. Vale la pena saperlo se un domani si aggiunge roba.
	dc.w	((INDIC_BASSO_RASTER&$FF)<<8)|$02|$01,$FFFE	; WAIT prima riga del riquadro basso
IndicBassoHi:
	dc.w	$019A,$0c23,$019C,$0f68
	dc.w	$0106,BPLCON3_LOCT1
IndicBassoLo:
	dc.w	$019A,$0c23,$019C,$0f68
	dc.w	$0106,BPLCON3_LOCT0

	; --- i gialli delle spie ---
	; Le quattro spie stanno da SPIA_Y0 in giu', cioe' SOTTO il riquadro basso
	; degli indicatori, che finisce sette righe dopo INDIC_BASSO_RASTER. Da qui
	; in giu' le tre voci degli indicatori (2, 13, 14) non le usa piu' nessuno,
	; quindi si ridipingono di giallo: le spie non costano una voce di palette
	; in piu'. Schermo e quadrante non c'entrano, usano i grigi 4/5/6.
	; L'ARMA DEL V8 STA QUI e non piu' davanti al WAIT di fine fascia: serve una
	; volta sola, e da 256 in su valgono tutti e due i WAIT che seguono. Un
	; secondo $FFDF fra i due aspetterebbe la riga 255 del quadro DOPO, e il
	; WAIT di fine fascia non scatterebbe mai.
	; Otto MOVE da 2 color clock: col conto di IndicBassoHi finiscono verso il
	; cc 18, e il primo pixel visibile e' al 64. Qui pero' i bitplane sono
	; ACCESI e si contendono i cicli col copper: e' il blocco da guardare per
	; primo se sulla prima riga delle spie comparisse una striscia di colore
	; sbagliato.
	dc.w	$FFDF,$FFFE		; past end of line 255 (arma V8)
	dc.w	(((SPIA_RASTER-256)&$FF)<<8)|$02|$01,$FFFE	; WAIT prima riga delle spie
	dc.w	$0184,SPIA_COL1,$019A,SPIA_COL2,$019C,SPIA_COL3
	dc.w	$0106,BPLCON3_LOCT1
	dc.w	$0184,SPIA_COL1,$019A,SPIA_COL2,$019C,SPIA_COL3
	dc.w	$0106,BPLCON3_LOCT0

	; --- il rosso della quinta spia ---
	; I tre grigi 4/5/6 servono alla rotella, allo schermo e al quadrante, che
	; finiscono rispettivamente a y30, y41 e y46. Da qui in giu' non li usa piu'
	; nessuno e diventano il rosso della spia sotto la lancetta, che sta sulle
	; stesse righe delle due spie gialle in basso e percio' non poteva usare le
	; loro voci. L'arma del V8 e' gia' stata data qui sopra.
	dc.w	(((ROSSA_RASTER-256)&$FF)<<8)|$02|$01,$FFFE	; WAIT prima riga del rosso
	dc.w	$0188,ROSSA_COL1,$018A,ROSSA_COL2,$018C,ROSSA_COL3
	dc.w	$0106,BPLCON3_LOCT1
	dc.w	$0188,ROSSA_COL1,$018A,ROSSA_COL2,$018C,ROSSA_COL3
	dc.w	$0106,BPLCON3_LOCT0

	; --- il colore della scritta scorrevole ---
	; Solo la voce della tinta, che sotto l'ultima riga delle spie (y56) e'
	; libera un'altra volta. Due MOVE per passata invece di sei.
	dc.w	(((SCRITTA_RASTER-256)&$FF)<<8)|$02|$01,$FFFE	; WAIT prima riga della scritta
	dc.w	$0180+SCRITTA_TINTA*2,SCRITTA_COL
	dc.w	$0106,BPLCON3_LOCT1
	dc.w	$0180+SCRITTA_TINTA*2,SCRITTA_COL
	dc.w	$0106,BPLCON3_LOCT0

	dc.w	(((PANNELLO_BOT_RASTER-256)&$FF)<<8)|$E0|$01,$FFFE	; WAIT fine fascia pannello
	dc.w	$0100,%0000001000000001		; BPLCON0: 0 bitplane, Color burst, ECSENA

	dc.w	$FFFF,$FFFE		; FINE DELLA COPPERLIST

; La palette del titolo NON e' piu' qui: la legge solo la CPU e vive in
; SECTION AssetCPU, in fondo a questo blocco.

* Qui sono memorizzate le tiles dello sfondo e tutti gli oggetti che ci si
* muovono sopra: OMINO, NEMICO, ecc. Tutti i dati sono in formato bitplane

TILES:
	incbin	"grafica/Tiles.raw"
TILES_FINE:
; Sesta della famiglia GUARDIA_*_RAW. Lega la FORMA dichiarata del foglio
; (FOGLIO_TILE_COLS, FOGLIO_TILE_RIGHE, FOGLIO_TILE_BYTE, in testa a TileFlags) alla lunghezza
; VERA del file: riesportare Tiles.raw con un'altra geometria fermerebbe
; l'assemblaggio invece di far leggere a DisegnaSfondo la tile sbagliata.
	IFNE	(TILES_FINE-TILES)-FOGLIO_TILE_N*FOGLIO_TILE_BYTE
GUARDIA_TILES_RAW	EQU		1/0
	ENDC

OMINO:
	incbin	"grafica/Omino32.raw"

NEMICO:
	incbin	"grafica/Nemico32.raw"

PIETRA:
	incbin	"grafica/Pietra.raw"

; La striscia dell'arte del falo' NON e' piu' qui: la legge solo la CPU e vive
; in SECTION AssetCPU, in fondo a questo blocco. In chip resta la copia gia'
; espansa a 5 piani, FaloSheet, che e' quella che il blitter disegna.

; grafica/parallasse.raw NON si incbinna piu' (erano 40 KB di chip): e' l'arte
; della VECCHIA parallasse a bitplane, tenuta come riferimento. Non e' la
; sorgente di niente - se serve si rigenera con tools/genera-parallasse.py -
; e le "fette" che se ne ricavavano sono state tolte l'8 settembre insieme al
; loro script: gli alberi a sprite le hanno sostituite.

; Gli ALBERI della parallasse, gia' in formato sprite a 64 bit. DEVE stare in
; CHIP RAM: li legge il DMA sprite. Il cnop vale per il primo; gli altri sono
; allineati perche' ogni albero occupa 16 + righe*16 + 16 byte, multiplo di 8.
; La TABELLA e' in ordine di canale e la genera lo script insieme all'arte:
;   dc.w  offset nel blob, x nel periodo, livello (1 = vicino, 3 = lontano)
	cnop	0,8
AlberiParallasse:
	incbin	"grafica/alberi_parallasse.raw"
AlberiParallasseFine:
; Il file e la tabella devono descrivere la stessa arte: se si rigenerano gli
; alberi con altezze diverse e non si aggiorna la tabella, l'ultimo offset piu'
; il suo albero non arriva in fondo al file. La guardia confronta la lunghezza
; vera con quella che la tabella implica.
	IFNE	(AlberiParallasseFine-AlberiParallasse)-ALBERI_LEN_ATTESA
ERRORE_ALBERI_TAGLIA_DIVERSA_DAL_SORGENTE	EQU		1/0
	ENDC

; La tabella sta in questa stessa sezione: sono 42 byte, e aprirne una nuova
; qui spedirebbe fuori dalla CHIP RAM tutto quello che segue - a cominciare
; dall'arte del pannello.
; Ogni albero ha VENTO_POSE disegni contigui e lunghi uguali, ognuno un pezzo
; unico col suo terminatore: il puntatore del canale sceglie quale mostrare.
; L'offset e' un LONG perche' l'arte supera i 32 KB e una word con segno non ci
; arriva - e' l'errore che si vedrebbe solo sugli alberi in fondo al file.
AlberiTab:
	dc.l	24320
	dc.w	2528,192,1,0	; canale 0, V2
	dc.l	0
	dc.w	2464,0,1,13	; canale 1, V0
	dc.l	12320
	dc.w	2400,96,1,4	; canale 2, V1
	dc.l	36960
	dc.w	2304,288,1,12	; canale 3, V3
	dc.l	69600
	dc.w	2272,304,3,8	; canale 4, L2
	dc.l	48480
	dc.w	2176,48,3,12	; canale 5, L0
	dc.l	59360
	dc.w	2048,176,3,10	; canale 6, L1

; Il ciclo del vento: le pose percorse avanti e INDIETRO, cosi' il ritorno non
; ha lo scatto che avrebbe un 4->0. Sedici passi, potenza di due perche' il
; codice ci arriva con un AND, campionati su un seno: tre passi fermi su ogni
; posa estrema, uno solo in mezzo. Generato insieme all'arte.
VentoCiclo:
	dc.b	2,3,3,4,4,4,3,3,2,1,1,0,0,0,1,1

; Grafica Pannello  : 4 bitplane AGA, 320x80, sequential layout.
; DEVE essere in CHIP RAM per la display DMA.
	cnop	0,8					; allineamento AGA FMODE=3
pannello:
	incbin	"grafica/Pannello.raw"

; La striscia della rotella NON e' piu' qui, stesso motivo del falo': la legge
; solo la CPU. Vive in SECTION AssetCPU, qui sotto.

; Title screen image: 8 bitplane AGA, 320x256, sequential layout.
; DEVE essere in CHIP RAM per la display DMA.
; DA QUANDO C'E' IL DROIDE QUESTO FILE NON VA PIU' A VIDEO: e' il MASTER, la
; copia pulita da cui si ripristina il rettangolo dietro al droide. A video ci
; va TitoloBuf, che ne e' la copia di lavoro. Stessa idea di PathBMaster per i
; BOB del gioco, e per lo stesso motivo: senza una copia pulita un oggetto che
; si muove lascia la scia.
	cnop	0,8					; allineamento AGA FMODE=3
title_bpl:
	incbin	"grafica/title.raw"
title_bpl_fine:
	IFNE	(title_bpl_fine-title_bpl)-TITLE_PLANE_SIZE*TITLE_PIANI
ERRORE_TITLE_TAGLIA_DIVERSA_DALLE_EQU	EQU		1/0
	ENDC

; L'arte del droide. In CHIP perche' la legge il BLITTER.
; Le due guardie confrontano la lunghezza vera dei file con quella che le EQU
; implicano: se si rigenera l'arte con un numero di pose o un'altezza diversi e
; non si aggiornano le EQU, l'assemblaggio si ferma qui invece di far leggere
; al blitter byte che non gli appartengono.
	cnop	0,8
Droide:
	incbin	"grafica/droide.raw"
DroideFine:
	IFNE	(DroideFine-Droide)-DROIDE_LEN_ATTESA
ERRORE_DROIDE_TAGLIA_DIVERSA_DALLE_EQU	EQU		1/0
	ENDC
	cnop	0,8
DroideMask:
	incbin	"grafica/droide_mask.raw"
DroideMaskFine:
	IFNE	(DroideMaskFine-DroideMask)-DROIDE_MASK_ATTESA
ERRORE_DROIDE_MASCHERA_TAGLIA_DIVERSA	EQU		1/0
	ENDC

; L'immagine dell'intro: 320x256 a 8 piani, layout sequenziale come la title.
; DEVE stare in CHIP: la legge il display. E' l'immagine di ARRIVO - il giorno
; pieno - e l'alba e' la palette che ci arriva sopra, quindi qui non serve
; nessun buffer di lavoro: sopra questi piani non disegna nessuno.
	cnop	0,8
AlbaImg:
	incbin	"grafica/alba.raw"
AlbaImgFine:
	IFNE	(AlbaImgFine-AlbaImg)-ALBA_LEN_ATTESA
ERRORE_ALBA_TAGLIA_DIVERSA_DALLE_EQU	EQU		1/0
	ENDC
