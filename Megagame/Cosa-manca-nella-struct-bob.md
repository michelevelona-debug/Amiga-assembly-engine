# Cosa avrebbe senso spostare dentro la struct bob — e cosa no

Check finale su `Gioco.s` dopo i cinque punti dell'audit. Ho guardato due
cose: quali variabili/costanti stand-alone sono in realtà **stato o proprietà
di una singola entità**, e quali campi della struct sono oggi inerti.

Comincio da una cosa che non è una proposta ma un difetto, perché l'ho trovata
proprio guardando quale campo potrebbe ospitare la direzione del proiettile.

---

## 0. TRAPPOLA ATTIVA: `bob_Direzione` non è sicuro su uno sheet a banda unica

`DisegnaBOB` calcola l'offset del fotogramma così:

```
banda = bob_Altezza * sheetPitch          ; sempre, anche con una banda sola
D3    = bob_Direzione * banda
```

Per la pietra: `banda = 16 * 32 = 512`, che è **l'intero piano** dello sheet.
Oggi non succede niente perché `InitPietra` mette `bob_Direzione` a 0 e nessuno
la tocca. Ma basta scriverci dentro un valore — ed è esattamente quello che
verrebbe naturale fare per ricordare in che direzione vola il sasso — perché
`bob_Direzione = 4` produca un offset di 2048 byte su un piano che ne ha 512:
il blit legge 1536 byte oltre la fine, cioè dentro `PIETRA_MASK` e oltre.

Non è teorico: è la stessa classe di bug del `MOVEQ #17-1,D7` di
`AddColonna`, un valore giusto per un formato e sbagliato per un altro.

**Rimedio, tre istruzioni** nel blocco della geometria, sfruttando il fatto che
`bob_Bande` è una potenza di 2 come `bob_Frames`:

```m68k
	MOVE.W	bob_Direzione(A0),D3
	MOVE.W	bob_Bande(A0),D2
	SUBQ.W	#1,D2				; maschera = bande-1 (0 se banda unica)
	AND.W	D2,D3				; direzione fuori range non esce dallo sheet
	MULU.W	D1,D3
```

Con `bob_Bande=1` la maschera è 0 e la direzione non produce mai salto; con 8
si comporta come adesso. Dopo questo, `bob_Direzione` diventa un campo che
qualunque bob può usare per il proprio scopo, anche se il suo sheet non ha
bande.

---

## 1. Campi già nella struct, ma inerti

| Campo | Stato | Cosa farne |
|---|---|---|
| `bob_Stato` | mai scritto né letto | È il posto giusto per lo stato del player (vivo / colpito / morto), che oggi non esiste. Vedi §3. |
| `bob_Type` | 3 scritture, **0 letture** | Nessuno distingue più player da nemico guardando il tipo: lo si deduce dal contesto (chi cammina nell'array, chi è `Player`). O lo si usa, o è zavorra. |
| `bob_PFmax` | 2 scritture, **0 letture** | Scritto da `InitPlayer` e `InitEnemies` e mai riletto. Serve solo se un giorno fai una barra vita proporzionale o una cura. |

`bob_Type` e `bob_PFmax` sono lo stesso caso di `bob_BltSize` che abbiamo già
tolto: campi che qualcuno riempie diligentemente e nessuno consulta.

---

## 2. Il proiettile ha DUE rappresentazioni parallele

Questa è la duplicazione più grossa rimasta. Oggi convivono:

| Variabile stand-alone | Campo struct che fa la stessa cosa |
|---|---|
| `Bullet_Active` | `bob_Active` di `BobPietra` |
| `Bullet_X` | `bob_WorldX` (a meno di mezzo fotogramma) |
| `Bullet_Y` | `bob_WorldY` (idem) |
| `BULLET_SPEED` (EQU 4) | `bob_Speed` — **esiste già ed è letto** da `AI_Patrol`, `AI_Hunt` e `ProcessaFrecce` |
| `BULLET_DAMAGE` (EQU 2) | `bob_Damage` — **esiste già ed è letto** da `Combattimento` |
| `Bullet_DirX` / `Bullet_DirY` | derivabili da `bob_Direzione` + `DirectionDeltas`, che è già come li calcola lo spawn |
| `Bullet_TTL` | nessuno — servirebbe un `bob_TTL` |

`AggiornaProiettile` esiste **solo** per copiare la prima colonna nella
seconda. Se la logica di traiettoria lavorasse direttamente su `BobPietra`,
quella routine sparirebbe del tutto e con lei la chiamata nel main loop.

Costo: un campo nuovo (`bob_TTL`), più il fix della §0 per poter usare
`bob_Direzione`. `Bullet_Cooldown` invece **non** va nella struct: è lo stato
di chi spara, non del proiettile — semmai è un campo del player.

### Il bonus: sparirebbero tre misure di collisione incoerenti

Oggi il proiettile ha una geometria di collisione tutta sua e cablata:

- lo spawn mette il sasso a `Player.bob_WorldX + 8`
- la collisione confronta `nemico.bob_WorldX + 8` con soglia `#10`
- ma `BOB_COLL_W` vale 32, e il fotogramma della pietra è 16

Quei `+8` sono il centro di un BOB **16x16**, cioè la taratura di prima che i
bob diventassero 32x32. Con `bob_Larghezza` nella struct il centro si scrive
`bob_Larghezza/2` e diventa giusto per ogni bob senza pensarci.

---

## 3. Fisica del player: metà dentro, metà fuori

| Variabile | Verdetto |
|---|---|
| `PlayerVelY` | **Per-entità.** Il giorno che un nemico cade o salta serve anche a lui. Candidato a `bob_VelY`. |
| `PlayerGrounded` | **Per-entità.** Stessa cosa: candidato a `bob_Grounded`, o meglio un bit di `bob_Stato`. |
| `UpNow` / `UpPrev` | **No.** Sono stato dell'input, non del bob. |
| `GravityOn` | **No.** È una modalità globale del gioco. |

`GRAVITY`, `MAX_FALL`, `JUMP_VEL` restano costanti globali finché la fisica
vale per una sola entità; diventerebbero campi solo se volessi nemici con peso
diverso — non lo consiglierei prima di averne davvero bisogno.

---

## 4. Il falò, quando diventerà un BOB

Due variabili spariranno da sole perché duplicano campi già esistenti:

| Oggi | Diventa |
|---|---|
| `FaloAnimFrame` | `bob_AnimFrame` |
| `FaloAnimDelay` | `bob_FrameCont` |

Ma ce n'è una terza che **non** ha un campo dove andare, ed è la più
interessante:

### `ANIM_DELAY` dovrebbe essere per bob

`ANIM_DELAY EQU 3` è globale e vale per tutti in `DisegnaBOB`. La prova che
non basta è già nel file: esiste `FaloAnimSpeed EQU 5`, nato **proprio perché**
il falò non poteva usare 3. Oggi i due valori vivono in due meccanismi di
animazione separati; quando il falò diventerà un BOB si troveranno nello
stesso, e uno dei due dovrà cedere — a meno di aggiungere `bob_AnimDelay`.

È un campo che vale la pena mettere adesso, insieme al falò: la pietra che gira
e un omino che cammina non hanno motivo di avere lo stesso passo.

### E `BOB_COLL_W` / `BOB_COLL_H`

Sono globali e oggi valgono `BOB_W`/`BOB_H`. Il commento dice che erano
deliberatamente diversi (16x16 su grafica 32x32) e che riportarli a 32 ha
richiesto di spostare un nemico. Sono la prossima cosa che si romperà quando
avrai bob di dimensioni diverse nello stesso mondo — e la pietra, con la sua
soglia `#10` cablata, è già il primo caso.

---

## 5. Cosa NON va nella struct, e perché

Lo scrivo perché la tentazione, dopo un elenco così, è di infilarci dentro
tutto.

| | Perché no |
|---|---|
| `BobGeoBlitW/Slot/Pitch/Plane` | Sono derivati, validi per una sola chiamata. Metterli nella struct significherebbe tenere due volte la stessa informazione — è esattamente la correzione che hai chiesto tu. |
| `BobClipSkipRows/NumRows/BobDrawY` | Risultato del clip di **questo** frame, non proprietà del bob. |
| `CENTER_X` / `CENTER_Y` | Proprietà della camera, non del player. |
| `PLAYER_SPAWN_X/Y` | Valori di inizializzazione, letti una volta sola. |
| `Bullet_Cooldown` | Stato di chi spara. |
| `GravityOn`, `UpNow`, `UpPrev` | Input e modalità globali. |

---

## 6. Se dovessi mettere in fila

1. **Il fix della §0** — tre istruzioni, chiude una trappola attiva. Lo farei
   subito e a prescindere dal resto.
2. **Togliere `bob_Type` e `bob_PFmax`**, o decidere di usarli. Sono l'ultimo
   residuo della categoria "scritto e mai letto".
3. **`bob_AnimDelay`**, insieme al falò a BOB: quello è il momento in cui il
   conflitto `ANIM_DELAY` / `FaloAnimSpeed` diventa reale.
4. **Unificare il proiettile**: la logica lavora su `BobPietra`, spariscono le
   sette `Bullet_*`, `BULLET_SPEED`/`BULLET_DAMAGE` diventano `bob_Speed` e
   `bob_Damage`, e `AggiornaProiettile` sparisce. Qui si sistemano anche i `+8`
   e il `#10`, quindi tocca la collisione: è l'unico passo che cambia il
   comportamento di gioco e va guardato a schermo, non solo dimostrato.
5. **`bob_VelY` / `bob_Grounded`** solo se e quando un nemico dovrà cadere.

I passi 1 e 2 sono no-op dimostrabili. Il 3 e il 4 no.
