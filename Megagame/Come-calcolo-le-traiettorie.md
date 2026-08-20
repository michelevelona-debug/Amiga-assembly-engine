# Come calcolo le traiettorie (salto e pietra)

Risposta alla domanda "come fai i conti". Il metodo è sempre lo stesso in tre
passi: **formula per arrivare nel quartiere giusto, simulazione per sapere il
numero vero, vincoli del gioco per scegliere fra i candidati.**

---

## 1. Le formule della scuola: servono, ma non bastano

Con accelerazione costante `g` e velocità iniziale `v`:

```
apice      h = v² / (2g)
salita     t = v / g              frame
gittata    R = 2·vx·vy / g        (misurata alla STESSA quota di partenza)
a 30°      vy = vx · tan(30°) = vx · 0,5774
quindi     R = 2·vx²·0,5774 / g
e anche    apice = R·tan(30°)/4   ≈ un settimo della gittata
```

Quest'ultima è la ragione per cui ti dicevo che a 30° l'arco è teso e non una
campana: la forma dipende **solo** dall'angolo. Allungare la gittata alza
l'apice in proporzione, ma non cambia il disegno della curva.

### Perché non bastano

Il 68000 non integra: fa due somme per frame, e **in quest'ordine**.

```m68k
    ADD.W   #GRAVITA,velocita      ; prima accelera
    ADD.W   velocita,posizione     ; poi muove
```

Accelerare prima di muovere significa che il primo passo vale già `v−g` e non
`v`. Il risultato è **sempre più basso** della formula continua:

| `v` (g=1) | formula `v²/2g` | simulazione | 
|---|---|---|
| 8  | 32,0 | **28** |
| 12 | 72,0 | **66** |
| 14 | 98,0 | **91** |
| 16 | 128,0 | **120** |

Con gravità intera la differenza ha una forma chiusa esatta:

```
apice discreto = v·(v − g) / (2g)          e per g=1:  v·(v−1)/2
```

Verificata su tutta la tabella: 8·7/2 = 28, 14·13/2 = 91, 16·15/2 = 120.

**È da qui che è nato l'equivoco sul "triplicare".** Il salto di partenza non
era 32 px come dice la formula: erano 28. Il triplo era 84, non 96.

---

## 2. La simulazione: stessa aritmetica del 68000, non una approssimazione

Lo script che uso non è un modello: **ricopia le istruzioni**, virgola fissa
compresa. Questo è il ciclo del salto, riga per riga uguale a
`AggiornaFisicaPlayer`:

```python
v += G                      # ADD.W  #GRAVITA_88,D0
if v > MAX_FALL: v = MAX_FALL
frac += v                   # ADD.W  PlayerVelY,D0
d = frac >> 8               # ASR.W  #8,D1        <- aritmetico, tiene il segno
y += d                      # MOVE.W D1,IntentY
frac &= 0xFF                # AND.W  #$00FF,D0
```

Due dettagli che devono corrispondere o i conti si separano dal gioco:

- **`>>` in Python su interi negativi è aritmetico**, come `ASR` sul 68000.
  Con `LSR` il segno si perderebbe e la caduta a sinistra sarebbe sbagliata.
- **l'ordine accelera-poi-muovi**, che è tutta la differenza della tabella
  qui sopra.

Il controllo che faccio sempre: `-1365` di velocità con frazione 0 deve dare
`-6` px e frazione `171/256`, che risommati fanno `-5,33` esatti. Se quel
conto torna, l'accumulatore è giusto.

---

## 3. La virgola fissa 8.8: perché serve

`256 = un pixel per frame`. Serve ogni volta che il rapporto fra due
grandezze non si può scrivere con interi piccoli:

- **a 30°** servono 3,29 px/frame in verticale contro 5,69 in orizzontale.
  Coi soli interi 3 e 6 l'angolo diventerebbe 27°, con 3 e 5 diventerebbe 31°.
- **per un salto più basso e più lento insieme** serve `g < 1`, che a interi
  non esiste. Con `g` frazionaria apice e durata tornano indipendenti:
  altrimenti sono legati, perché abbassando l'apice si accorcia anche `v/g`.

L'accumulatore è la parte che rende tutto questo possibile a 16 bit: la
velocità è frazionaria, ma nel mondo si spostano solo pixel interi, e il resto
si conserva per il frame dopo.

---

## 4. La ricerca: non risolvo l'equazione, cerco fra i candidati interi

I valori finali devono essere **interi** e rispettare più vincoli insieme.
Quindi uso la formula per delimitare l'intervallo, poi provo tutte le
combinazioni e tengo quelle che passano ogni controllo:

```python
for J in range(1700, 2100, 8):
    for G in range(80, 120, 2):
        apice, salita, discesa = simula(J, G)
        if tile_scavalcate >= 4 and margine >= 8 and 18 <= salita <= 22:
            candidati.append(...)
```

### I vincoli che scelgono il vincitore

**Le tile, non i pixel.** Il livello è fatto di tile da 16 px: quello che
conta è *quante se ne scavalcano*, non l'altezza in sé. Un salto da 78 px
sembra buono finché non ti accorgi che è **2 px sotto** le cinque tile: e un
margine di 2 px è la ricetta esatta per un salto che «funziona quasi sempre»,
cioè per giorni passati a cercare un bug che non c'è. Per questo con `-13`
scartato ho preso `-14`.

**Il punto di partenza vero.** La pietra non parte da terra, parte dal
*centro* del player: per toccare il suolo deve scendere 16 px **più in basso**
di dove è partita. La formula della gittata misura da pari a pari e quindi
sottostima. Tarando sulla formula pura, a 8 word atterrava a 147 invece di
128 e il tetto la tagliava a mezz'aria: sparizione che avresti letto come un
difetto di disegno, non di fisica.

**Il tunnel.** Se in un frame ci si sposta di più di una tile, il controllo di
collisione può saltarla. Verificato ogni volta: la pietra a 5,69 px/frame
contro tile da 16 sta larga; il player a 14 px/frame di salita era a 2 px dal
limite, ed è uno dei motivi per cui non sarei salito oltre. Per il BOB del
player c'è un margine in più: essendo alto 32 px, la posizione vecchia e la
nuova si sovrappongono sempre, quindi nessuna tile può passare in mezzo.

**La camera.** Il player sale più veloce di quanto `CAM_STEP_Y=8` lo insegua,
quindi guadagna terreno sulla telecamera durante la salita. Simulato per ogni
candidato: con l'ultimo salto la Y schermo minima è 64 px su 176, ampiamente
dentro. Se fosse andata sotto zero il player sarebbe uscito dallo schermo in
cima al salto.

---

## 5. Le guardie: il conto che resta nel sorgente

Un numero verificato una volta e poi dimenticato è il difetto tipico di questo
progetto. Quindi dove posso il controllo resta nel file e blocca
l'assemblaggio:

```m68k
PIETRA_VOLO_FRAMES  EQU  (2*PIETRA_VEL_Y)/PIETRA_GRAVITA
PIETRA_GITTATA      EQU  (PIETRA_VEL_X*PIETRA_VOLO_FRAMES)/256
    IFGT  PIETRA_GITTATA-PIETRA_RAGGIO
GUARDIA_PIETRA_GITTATA  EQU  1/0        ; l'arco non ci sta nel tetto
    ENDC
```

Se alzi la velocità senza allungare la gittata, non lo scopri giocando: non
compila.

---

## 6. In pratica, se vuoi rifare i conti da solo

1. **Altezza voluta → velocità**: `v ≈ √(2·g·h)`, poi correggi in giù con
   `v(v−g)/(2g)` e ritocca finché il numero torna.
2. **Durata voluta → gravità**: `g = v/t` frame di salita. Se serve `g < 1`,
   virgola fissa.
3. **Gittata a 30°**: `vx = √(R·g / (2·tan30))`, e `vy = vx·0,5774`.
4. **Controlla**: quante tile scavalca, che margine resta, che il passo per
   frame stia sotto i 16 px, e che il tetto della gittata non tagli l'arco.

I numeri attuali, per riferimento:

| | velocità (8.8) | gravità (8.8) | risultato |
|---|---|---|---|
| salto | `JUMP_VEL_88 = -1792` (7,0 px/f) | `GRAVITA_88 = 86` (0,336) | apice 70 px, 21+20 frame |
| pietra | `PIETRA_VEL_X = 1456` (5,69 px/f) | `PIETRA_GRAVITA = 42` (0,164) | gittata 250 px, 44 frame, apice 32 px |
