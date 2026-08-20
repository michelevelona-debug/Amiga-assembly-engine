# MegaGame / Antiriad — audit dei simboli e proposta di disegno BOB unico

Analisi su `Gioco.s` (6.283 righe) più gli include realmente assemblati
(`title.i`, `Startup2.i`, `Testo.i`, `ScrollHW.i`, `CieloGrad.i`, `ptplayer.i`,
`Pannello.cop`, `Tiles.cop`). `ProtoScroll.i` è escluso perché il suo include
sta dentro `IFNE PROTO_SCROLL` e l'interruttore vale 0.

Simboli definiti: **887**. Mai referenziati da nessuna parte: **111**, di cui 63
appartengono a `ptplayer.i` (tabelle generate da macro di Frank Wille: non si
toccano).

---

## 1. Il limite del metodo, prima dei risultati

Un'analisi automatica in assembly non può vedere tre cose, e in questo progetto
ci sono tutte e tre. Le elenco perché sono la ragione per cui il paragrafo dei
**falsi positivi** va letto prima di cancellare qualsiasi cosa.

1. **Accessi per aritmetica di indirizzo.** `MostraProfilo` legge
   `PROF_VALUES` word *consecutive* a partire da `ProfWorst`: i simboli
   `DropCount`, `ProfDdf`, `ProfSwapRaster`, `ProfDelay`, `ProfParOfs` non
   compaiono mai come sorgente di una MOVE, eppure sono letti tutti.
2. **Etichette usate come punto d'appoggio.** `TitleBPL_1..7` non sono mai
   nominate: il codice fa `LEA TitleBPL_0,A1` e poi cammina. Le etichette
   servono a leggere la copperlist, e non costano un byte.
3. **Padding strutturale.** `dirty_Pad` non è letto né scritto da nessuno:
   esiste per allineare `dirty_Ofs` a long. Toglierlo romperebbe la struttura.

Per questo ho classificato ogni voce con un verdetto invece di darti una lista
piatta.

---

## 2. Variabili scritte e mai lette — questa è la zavorra vera

Sono le uniche voci che portano via sia memoria sia **istruzioni eseguite ogni
frame**. Tutte verificate a mano una per una.

| Variabile | Righe che la scrivono | Verdetto |
|---|---|---|
| `VScrollStep` | 1850, 4633, 4637, 4644, 4648 | **Eliminare.** Cinque scritture, zero letture, in tutto il progetto include compresi. Era il passo di shift verticale di Path A; in Path B lo scroll è fatto dai puntatori e nessuno la consulta più. |
| `PdngAddRx` | 1957, 1973 | **Eliminare.** |
| `PdngAddSx` | 1958, 1972 | **Eliminare.** |
| `PdngAddBot` | 1986, 2002 | **Eliminare.** |
| `PdngAddTop` | 1987, 2001 | **Eliminare.** |
| `FrameLines` | 1445, 1540 | **Eliminare** (vedi nota sotto). |

### I quattro `PdngAdd*` meritano due parole

Non sono solo inutilizzate: i loro commenti dicono `; era BSR.W AddColonnaDestra`,
e **le routine `AddColonnaDestra`, `AddColonnaSinistra`, `AddRigaBasso`,
`AddRigaAlto` non esistono più nel sorgente**. Restano solo citate nei commenti
e nel nome della fase `PH_TILES`.

Quindi il meccanismo "posticipa l'Add a dopo lo shift" è un residuo completo di
Path A: quattro variabili, otto istruzioni che le mettono a 1 e le azzerano, e
nessuno che le guardi. Sono 8 byte e 8 istruzioni per frame che non fanno nulla.

Ho letto a mano quel tratto (righe 1950–2005, dentro `ControllaBordi`) proprio
perché era l'unico punto dove il taglio poteva scoprire che *manca* qualcosa
invece che avanzare: **non manca nulla**. La logica intorno è viva e corretta —
avanza `TileX`/`TileY`, riporta `D0`/`D1` nell'intervallo 0..15, azzera
`ScrllX`/`ScrllY` ai bordi — e le otto scritture ai flag sono l'unica parte
inerte. In Path B il buffer contiene tutta la mappa, quindi non c'è nessuna
colonna o riga da aggiungere: il meccanismo non serve più, non è rimasto a
metà.

### `FrameLines`

Scritta due volte in `FineLavoro` (riga 1445 il valore grezzo, riga 1540 quello
ricostruito coi wrap) e mai riletta: il valore che conta finisce subito dopo in
`WorstLines`, ed è quello che `MostraProfilo` stampa.

Attenzione: **non è un simbolo da togliere alla leggera**, perché è l'unico
posto dove esiste la durata del frame *corrente* (non il peggiore). Se un giorno
vuoi un contatore istantaneo invece dell'high-water, quella è la variabile.
Suggerimento: tienila, ma togli la scrittura di riga 1445 che viene comunque
sovrascritta dalla 1540 senza essere letta in mezzo.

---

## 3. Costanti mai usate

### 3a. Orfane per via del refactor dei BOB di oggi

| EQU | Riga | Nota |
|---|---|---|
| `OMINO_DIR_BANDA` | 99 | Ora `DisegnaBOB` deriva la banda da `altezza * pitch`. |
| `BOB_MASK_PITCH` | 95 | Era `= BOB_SLOT_BYTES`, alias mai usato. |

`BOB_WORDS`, `BOB_BLIT_W`, `BOB_SLOT_BYTES`, `OMINO_PITCH`, `OMINO_ROWS` non
compaiono più nel codice ma **restano necessarie**: alimentano la catena che
arriva a `PLANE_SIZE`, che dimensiona `OMINO_MASK` e `NEMICO_MASK` e viene
passata a `BuildBobMask`. Stessa cosa per `PIETRA_WORDS/BLIT_W/SLOT_BYTES` verso
`PIETRA_PITCH` e la guardia.

### 3b. Residui di funzionalità rimosse — eliminabili

| EQU | Riga | Da cosa avanza |
|---|---|---|
| `NUM_PLANES` | 82 | Diceva 6 piani (5 + EHB notte). Il display è a 8 piani con EHB spento da un pezzo. **Fuorviante**: è il tipo di commento falso che ti è già costato giorni. |
| `HEALTHBAR_COLOR` | 714 | Barre vita non più disegnate. |
| `HEALTHBAR_YOFFSET` | 715 | idem |
| `INVULN_FRAMES` | 716 | Sostituita da `bob_InvulnMax` per bob, presa da `EnemyInitTable`. |
| `BULLET_HEIGHT` | 735 | Altezza dello sprite proiettile: con la pietra a BOB non serve più. |
| `VIS_ROWS` | 669 | Sostituita da `BG_VIS_ROWS`. |
| `XTiles` / `YTiles` | 583/584 | Valgono 16 e 16, mai usate: la dimensione tile è cablata altrove. |
| `BG_MARGIN_TOP_ROWS` | 255 | La parametrizzazione dell'altezza di `SFONDOGRANDE` è stata superata da Path B, che tiene tutta la mappa nel buffer. |
| `BG_MARGIN_BOT_ROWS` | 256 | idem — ed è ancora commentata come «LA LEVA DEL TAGLIO», che oggi **non è più vera**. |
| `PARALLAX_SRC_PLANE_SZ` | 282 | |
| `DBG_FIXLIGHT` | 772 | Diagnostica della luce. |

Su `BG_MARGIN_*`: se le togli, togli anche il blocco di commento alle righe
215–235 che le descrive come manopola viva, altrimenti resta documentazione che
promette una leva che non c'è.

### 3c. Generate da `png2amiga.py` e mai usate

`PIETRA_WIDTH` (555), `PIETRA_PALETTE_SIZE` (559), `PANNELLO_WIDTH` (454),
`PANNELLO_COLORS` (457), `PANNELLO_PALETTE_SIZE` (460).

Sono l'intestazione che lo script emette per ogni conversione. Innocue, ma
`PIETRA_PLANE_SIZE` che veniva dalla stessa fonte era **sbagliata** (bit invece
di byte) e ci ha già fatto perdere tempo: o le tieni tutte e le verifichi, o le
togli tutte e derivi solo da quello che ti serve. Non lascerei metà lista.

### 3d. Diagnostiche da tenere

`PANNELLO_PTR_WAIT_H` (522), `PANNELLO_TEST_COLOR` (541),
`SKY_SRC_FIRST` / `SKY_FADE_ROWS` (`CieloGrad.i` 18/20),
`SCROLL_GUARD_BYTES` (`ScrollHW.i` 63), `TITLE_WIDTH` / `TITLE_HEIGHT`.

Sono reti di sicurezza e documentazione di geometria. `PANNELLO_PTR_WAIT_H` in
particolare è la manopola da riprendere in mano se la geometria del pannello
cambia e la corsa col DMA torna: il commento che la descrive vale più della
riga stessa.

`GUARDIA_PIETRA_PITCH` (579) risulta "mai referenziata" per costruzione: è la
guardia `1/0`, esiste per far fallire l'assemblaggio. Corretta così.

---

## 4. Riepilogo di cosa si guadagna

| | Byte | Istruzioni/frame |
|---|---|---|
| Variabili morte (`VScrollStep`, 4× `PdngAdd*`, mezza `FrameLines`) | 12 | ~9 |
| Costanti morte (3b + 3c) | 0 | 0 |
| `bob_Stato` (se un giorno lo togli) | 2 × 6 bob = 12 | 0 |

Le costanti non costano niente in memoria: il guadagno è di **leggibilità**, ed
è dove sta il valore vero — `NUM_PLANES` che dice 6 e `BG_MARGIN_BOT_ROWS`
descritta come leva viva sono esattamente il tipo di commento falso che il file
ha già dimostrato di saper produrre.

---

## 5. Routine di disegno unica

Sì, si può, e con la struct com'è adesso manca poco.

### Dove siamo

Dopo il lavoro di oggi le routine sono cinque, ma solo due contengono logica:

```
DisegnaBOB           blit vero, tutto parametrico sulla struct
DisegnaBOBConClip    cull + clip verticale, su bob_Larghezza/bob_Altezza
DisegnaBOBPlayer     wrapper: A0=Player, niente clip
DisegnaBOBEnemy      ciclo sull'array + world->schermo
DisegnaBOBPietra     singolo + world->schermo
```

Le ultime tre fanno **la stessa cosa**: prendono un bob, calcolano
`bob_X/bob_Y = World - Camera`, chiamano il disegno. Differiscono solo per come
raggiungono la struct.

### La modifica che le fa collassare in una

Basta che i bob stiano **in memoria contigua**, così una sola `LEA
bob_Length(A0),A0` li percorre tutti. Non serve un array di puntatori né
cambiare una sola riga del codice che li usa: si sfrutta il fatto che tre `ds.b`
consecutivi nella stessa sezione sono già contigui.

```m68k
	SECTION	Entities,BSS
	EVEN
BobArray:                                ; <- la lista comincia qui
Enemies:	ds.b	bob_Length*ENEMY_COUNT   ; per primi: stanno sotto a tutti
Player:		ds.b	bob_Length               ; poi il player
BobPietra:	ds.b	bob_Length               ; per ultima la pietra, sopra a tutti
BOB_TOTALI	EQU		ENEMY_COUNT+2
```

`Player` ed `Enemies` restano etichette vere, quindi `Player+bob_WorldX`,
`LEA Enemies,A0` e tutto il resto continuano a funzionare senza toccarli.
**L'ordine di dichiarazione È l'ordine di disegno**, cioè lo z-order: nemici,
player, pietra — esattamente quello che il main loop fa oggi a mano.

```m68k
DisegnaBOBs:
	MOVEM.L	D0-D4/A0,-(SP)
	MOVE.W	TileX,D2
	LSL.W	#4,D2
	ADD.W	PixelOffX,D2			; D2 = CameraX in pixel
	MOVE.W	TileY,D3
	LSL.W	#4,D3
	ADD.W	PixelOffY,D3			; D3 = CameraY in pixel
	LEA		BobArray,A0
	MOVEQ	#BOB_TOTALI-1,D0
.loop:
	TST.W	bob_Active(A0)
	BEQ.S	.next
	MOVE.W	bob_WorldX(A0),D1
	SUB.W	D2,D1
	MOVE.W	D1,bob_X(A0)
	MOVE.W	bob_WorldY(A0),D4
	SUB.W	D3,D4
	MOVE.W	D4,bob_Y(A0)
	BSR.W	DisegnaBOBConClip
.next:
	LEA		bob_Length(A0),A0
	DBRA	D0,.loop
	MOVEM.L	(SP)+,D0-D4/A0
	RTS
```

Spariscono `DisegnaBOBPlayer`, `DisegnaBOBEnemy` e `DisegnaBOBPietra`: nel main
loop tre `BSR` diventano uno. E il falò, quando avrà l'arte, si aggiunge
dichiarando un altro `ds.b bob_Length` e alzando `BOB_TOTALI` — zero codice.

### Le quattro cose da sapere prima di dire di sì

1. **Il player oggi non viene clippato.** `DisegnaBOBPlayer` dice
   esplicitamente «Player non viene mai clippato (ha PLAYER_MAX_X/Y che lo
   tiene dentro)». Nel ciclo unico passerebbe dal cull come tutti. Se i limiti
   lo tengono davvero dentro è identico; se non lo tengono, oggi stai
   disegnando fuori dai bordi e non te ne accorgi — nel qual caso il ciclo
   unico non introduce un bug, ne **scopre** uno.

2. **`AggiornaPlayerScreenPos` deve restare.** Calcola gli stessi `bob_X/bob_Y`,
   ma serve *prima*, perché `RettangoloScrollNelCentro` decide lo scroll
   guardando `Player+bob_X`. Il ciclo li ricalcola identici: è una moltiplicazione
   ridondante per un bob su sei, non un rischio.

3. **`AggiornaProiettile` va spezzata e spostata.** Oggi fa due lavori: copia
   `Bullet_*` nella struct *e* disegna. Nel modello unico deve solo copiare, e
   deve girare **prima** del ciclo di disegno, non dopo. Sposta un `BSR` nel
   main loop: le `PROFMARK` restano dove sono, ma la fase `PH_BOB` finirebbe a
   misurare anche la pietra, che oggi cade nella fase successiva. È un cambio di
   *attribuzione* del costo, non di costo — però va saputo prima di leggere i
   numeri e concludere che qualcosa è peggiorato.

4. **`bob_Active` del player deve valere 1 sempre.** Oggi `InitPlayer` lo mette
   a 1 e nessuno lo azzera; se un giorno userai `bob_Active=0` per la morte del
   player, il player sparirebbe invece di mostrare l'animazione di morte.
   Meglio prevedere `bob_Stato` per quello (ecco un uso per il campo che oggi è
   vuoto) e lasciare `bob_Active` come "esiste".

### Volendo spingere oltre

`DisegnaBOBConClip` e `DisegnaBOB` potrebbero fondersi in una sola routine: il
cull costa una manciata di confronti e nessuno chiama più `DisegnaBOB` senza
passare dal clip. Resterebbe **una** routine di disegno e **un** ciclo. Lo terrei
come passo successivo, dopo che il ciclo unico ha girato: sono due modifiche
indipendenti e conviene poterle validare separatamente.

---

## 6. Ordine consigliato

1. Togliere le variabili morte (`VScrollStep`, `PdngAdd*`) e le istruzioni che
   le scrivono — controllando a mano il tratto 1950–2005.
2. Togliere le costanti di 3b e 3c, e i commenti che le descrivono come vive.
3. Contiguità dei bob + `DisegnaBOBs` unica, con `AggiornaProiettile` ridotta a
   copia e spostata prima.
4. Solo dopo, se convince: fondere `DisegnaBOBConClip` dentro `DisegnaBOB`.
5. Alla fine, smontare l'impianto sprite (`BulletSprite`, `EmptySprite`, il ramo
   `SPR1PT`, `PROIETTILE_BOB`) come già previsto.

I passi 1 e 2 sono no-op dimostrabili: il binario deve cambiare solo per le
istruzioni tolte. Il passo 3 no, va guardato a schermo.
