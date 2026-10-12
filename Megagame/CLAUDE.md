# Antiriad – porting per Amiga 1200 (titolo di lavoro: MegaGame)

> **Verificato contro il sorgente il 7 ottobre 2026** (`Gioco.s` 10.863 righe, impronta
> `07978d9e3d48` secondo `py tools\impronta.py`). Se l'impronta non coincide più, i numeri qui
> sotto possono essere superati: **vince sempre il codice**, e i valori veri delle EQU li stampa
> `py tools\valori.py`.

## Cos'è

Port di *The Sacred Armour of Antiriad* (Palace Software, 1986) dal C64 all'**Amiga 1200 AGA**,
platform a vista laterale in **Assembly 68k**. Proporzioni ribilanciate rispetto al C64: area di
gioco 176 righe (2/3) e pannello 80 righe (1/3). A differenza delle stanze del C64, il mondo è fatto
di **blocchi grandi** (oggi 73x24 tile) collegati da porte, con scroll libero dentro il blocco.

Flusso del programma: **titolo** (8 piani, droide che fluttua) → **intro** (alba, anima solo la
palette) → **gioco**. Si esce col tasto sinistro del mouse.

## Toolchain, build e test

- **vasm** (`vasmm68k_mot -m68020 -Fhunk -linedebug`) e **vlink** tramite l'estensione
  **vscode-amiga-assembly** di VS Code (`.vscode/tasks.json`). L'eseguibile esce in `uae/dh0/Gioco`.
- Il sorgente deve assemblare **anche con Devpac**, che valuta le EQU in una sola passata:
  niente riferimenti in avanti nelle EQU e nelle IFxx (`py tools\controlla-forward.py` lo verifica).
- **Il build assembla TUTTI i `.s` della cartella e linka TUTTI gli `.o` di `build/`.**
  Non mettere altri `.s` in radice: diventano un secondo programma (errore "symbol already defined").
- Test: **WinUAE** (config `uae/MegaGame.uae`, lancio "WinUAE Debug" in `.vscode/launch.json`),
  validazione finale sull'**A1200 reale** (8 MB Fast RAM, 68882). Ciò che tocca FMODE, DDF,
  moduli e prefetch va provato sul ferro: WinUAE è più permissivo (la title screen era perfetta
  nell'emulatore e illeggibile sulla macchina vera).
- Script Python in `tools/` (su Windows `py tools\nome.py`, dalla cartella Megagame).
- Audio: **sox** per convertire in 8 bit signed mono; musica e SFX con **ptplayer** (Frank Wille).

## Mappa dei file

| File / cartella | Contenuto |
|---|---|
| `Gioco.s` | Sorgente principale: EQU in testa, codice, poi le SECTION dati/chip/BSS |
| `ScrollHW.i` | Scroll hardware: da CameraX/Y a BPLxPT + BPLCON1 (`ScrollHWCalc`, `ScrollHWApply`) |
| `Mappe.i` | **Generato** da `tools/mappe.py` a partire da `risorse/mappe.txt`: non si modifica a mano |
| `Intro.i` | L'alba: palette animata dal copper, immagine ferma |
| `Testo.i` | Font **Metal.fnt** 8x8 (ASCII 32..127). API: `TestoChar`, `TestoNumero` (`TestoStampa` è stata rimossa) |
| `CieloGrad.i` | Dati del gradiente cielo (oggi spento: `CIELO_GRADIENTE 0`) |
| `Startup2.i` | Startup AGA, VBR (`BaseVBR`), cache |
| `Pannello.cop` | Palette del pannello come MOVE copper (inclusa due volte, LOCT0 e LOCT1) |
| `ptplayer.i` | Player MOD/SFX (rinominato `.i` per non farlo compilare da solo all'estensione) |
| `grafica/`, `suono/` | **Solo** i file che il gioco incbinna (`.raw`, `.fnt`, `.pal`, `.mod`) |
| `risorse/` | Sorgenti: PNG, IFF, `.txt` delle mappe (`mappaN.txt` è la fonte, `grafica/mappaN.raw` il prodotto) |
| `backup/` | Copie di sicurezza `*.prima-<motivo>` (le gestisce `tools/copie.py`) |
| `tools/` | Generatori e controlli (sotto) |
| `Gioco-misura-sprite.s` | Guscio vuoto da **cancellare** insieme a `build/Gioco-misura-sprite.o` |

**Strumenti principali in `tools/`**
- `mappa.py` – mappa da `.txt` a `.raw` + anteprime (`--mappa N` per il blocco N)
- `mappe.py` – genera `Mappe.i` e **verifica la reciprocità** dei collegamenti; poi `porte.py`
  controlla che le porte siano raggiungibili e non buttino il player nel vuoto
- `valori.py` – valore vero di ogni EQU, rami condizionali compresi (`--chip` per l'inventario della chip RAM)
- `controlla-forward.py` – riferimenti in avanti (Devpac) e codice dopo `end`
- `impronta.py` – quale versione di `Gioco.s` c'è sul disco
- `fotogramma.py` – ricostruisce dai file veri ciò che il chipset manda a video
- `registri.py` – quali registri custom scrive ogni percorso
- `copie.py`, `sposta-risorse.py` – dove vanno backup e file non necessari al build
- `genera-*.py` + `grafica.py` – arte generata; **ogni `.raw` generato ha anche il suo `.iff`**

## Architettura

**Display del gioco** (le due scene hanno geometrie diverse: vedi `ImpostaDisplayTitolo` / `ImpostaDisplayGioco`)
- **6 bitplane lores**, prelievo bitplane a **16 bit** (`SCROLL_FETCH_BIT 16`), sprite a **64 px** (`SPRITE64 1`, FMODE = `$000C`)
- Piani 1–5: mondo (tile + BOB). Piano 6: **darkplane** della notte (sceglie il banco colori 32..63)
- Finestra 320 px (`DIW_H_START $81`, `DIW_H_STOP $C1`), `VIS_COLS` = 20
- `SCROLL_DDFSTRT $30` / `SCROLL_DDFSTOP $D8`: prefetch di un blocco da 16 px, 22 fetch per riga
- BRDRBLNK acceso: bordi neri. Cielo a tinta fissa `CIELO_FISSO_RGB` (gradiente disattivato)
- Il titolo e l'alba usano invece 8 piani, prelievo a 64 bit, DDF `$28..$A8`

**Scroll ("Path B")**: tutto il blocco di mappa sta in `SFONDOGRANDE` (pitch 160, 400 righe) e lo
scroll è solo aritmetica su BPLxPT + `BPLCON1`. Offset = `ceil(CameraX/16)*2 + CameraY*SFONDO_PITCH`,
ritardo `D = ceil(CameraX/16)*16 - CameraX` (0..15). `BPLCON1` si scrive **patchando la copperlist**,
mai dalla CPU a metà schermo. L'intera geometria discende da `SCROLL_FETCH_BIT`: c'è un solo posto da toccare.

**Doppio buffer del mondo**: `SFONDOGRANDE` / `SFONDOGRANDE_B`. I BOB si cancellano con
**restore dal master** `PathBMaster` (lista di rettangoli sporchi: offset, righe, larghezza).
Puntatori, BPLCON1 e swap si pubblicano **insieme** in `ScrollPathBApply`, a disegno finito.

**Parallasse = alberi sugli sprite** (dal 5 settembre): **7 alberi su 7 canali sprite** da 64 px,
due velocità (vicini a 1/2 della camera, lontani a 1/4), vento disegnato in `VENTO_POSE` pose
(si cambia il puntatore del canale). Ogni quadro si riscrivono solo HSTART e puntatori
(`AggiornaParallasseSprite`): zero blit. Sette è il **tetto esatto**: con prelievo a 16 bit
sopravvivono 7 canali sprite, e quel prelievo regge al massimo 6 bitplane in lores
(guardia `ERRORE_LA_PARALLASSE_A_SPRITE_VUOLE_FETCH_16`). Arte e tabella le genera
`tools/genera-alberi-sprite.py`; i canali 0..3 sono i vicini e 4..6 i lontani (le rampe di colore dipendono da questo).

**Darkplane (notte, tasto N)**: statico, disegnato **una volta** in coordinate mondo (`PathBBuildDark`),
scorre coi puntatori come i piani 1–5. Le luci sono le tile `TILE_LUCE` della mappa.

**Mappe a blocchi e porte**: 4 blocchi (`mappa1..4`) collegati ad anello in orizzontale
(`risorse/mappe.txt` → `Mappe.i`). Un bordo è una porta se ha un vicino, altrimenti è muro.
`ControllaPassaggio` → `EseguiPassaggio` → `RicostruisciMondo` (~44 quadri) dietro una
**dissolvenza** della palette (`FADE_PASSAGGIO 1`). Partenza del player e posizione del falò
vengono **dalla mappa** (tile `TILE_VIA` e `TILE_LUCE`), non da EQU.

**Pannello**: fascia sotto l'area di gioco, 4 bitplane, `PannelloBuf` con **lo stesso pitch del mondo**,
non doppio bufferizzato, puntatori fissi dal boot. Due righe di separazione a bitplane spenti danno al
copper il tempo per la palette a 24 bit ed eliminano la corsa col DMA sui puntatori.
Strumenti funzionanti: punteggio a rotelle, due indicatori a liquido (energia e vita), schermo,
spie, quadrante, lettera, scritta scorrevole. Si disegnano **in coda** al quadro, dopo `ScrollPathBApply`.
`PANNELLO_ART_BYTE_OFS` è **misurato a schermo** per ogni valore di `SCROLL_FETCH_BIT`, non derivato.

**BOB**
- Struct `bob_*` unica per tutte le entità; `bob_Length` deve restare multiplo di 4 (c'è la guardia)
- Bob contigui in `BobArray`: **`BobFalo` → `Enemies` → `Player` → `BobPietra`**.
  L'ordine di dichiarazione è lo **z-order**; `BOB_TOTALI = ENEMY_COUNT+3`
- Catena di disegno unica: `DisegnaBOBs` → `DisegnaBOB` (cull, clip, animazione, blit, dirty).
  La geometria dello sheet viene dalla struct (`bob_Larghezza`, `bob_Altezza`, `bob_Frames`, `bob_Bande`)
- BOB 32x32, collisione 32x32 (`IsBoxBlocked` sonda a passo 16 px). Maschera = **OR dei 5 piani**:
  un pixel di colore 0 dentro la sagoma diventa trasparente
- Il **falò è un BOB** (acceso solo di notte da `AnimaFalo`). Il proiettile **pietra** è un BOB
  lanciato a 30° con parabola in virgola fissa 8.8. Anche la verticale del player è in 8.8
  (`GRAVITA_88`, `JUMP_VEL_88`, `MAX_FALL_88`), con guardie anti-tunnel e anti-fuga dalla camera

**Ordine del main loop** (`.mainloop`, conta per la misura): input e fisica → `ControllaPassaggio` →
camera e bordi → `ScrollPathB` → `AggiornaParallasseSprite` → `AnimaFalo` → entità (nemici,
combattimento, pietra, passi) → `PathBRestoreAll` + `DisegnaBOBs` → `AspettaBlitter` →
`ScrollPathBApply` → strumenti del pannello → misura → `AspettaVBL` → musica e `AggiornaTransizione`.

**Audio**: ptplayer installato su `BaseVBR` (non 0: su 68010+ la tabella dei vettori può essere spostata),
3 canali alla musica e 1 agli SFX. Sample di lunghezza pari, **prima word a zero**. Period PAL = 3546895 / frequenza.

## Interruttori e diagnostica

| EQU | Valore | Significato |
|---|---|---|
| `SCROLL_FETCH_BIT` | 16 | Imposto dalla parallasse a sprite: non cambiarlo |
| `SPRITE64` | 1 | Sprite da 64 px |
| `CIELO_GRADIENTE` | 0 | Cielo a tinta fissa |
| `FADE_PASSAGGIO` | 1 | Dissolvenza sulle porte |
| `TENDA_PASSAGGIO` | 0 | Alternativa alla dissolvenza, da togliere se questa convince |
| `PROFILING` | 1 | Monitor delle prestazioni compilato |
| `PROF_COLORS`, `PROF_KILL_SKY` | 0 | Fasce colorate su COLOR00 (spente) |
| `TITLE_TEST_FILL`, `PANNELLO_TEST_FILL`, `BULLET_DEBUG` | 0 | Prove a costanti note / percorso di disegno |

**Monitor** (sta nel **pannello**, non nel mondo): **P** mostra/nasconde, **R** azzera gli high-water,
**6** scroll automatico. Etichette: `VB IN SC PA TI DK FA CV EN BO BL WO DR DF SW DL PO RQ RV MP`.
Si legge prima **DR** (quadri persi), poi **WO** (peggior quadro, "sticky": basta un picco isolato).
**RQ/RV** sono i quadri della ricostruzione del mondo misurati per due strade indipendenti.
Altri tasti: **N** giorno/notte, **M** musica, **G** gravità / 8 direzioni, **Q S L A** provano gli strumenti del pannello.

## Regole di lavoro (lezioni costate care)

1. **I commenti in `Gioco.s` possono essere vecchi** (anche nel main loop ce ne sono ancora sul
   vecchio parallasse a bitplane). Verificare sempre sul codice; i valori li dà `tools/valori.py`.
2. **File in UTF-8.** Non riscriverli in latin-1 e non inserire em-dash nel codice.
3. **L'assemblatore ignora `FAIL`.** Le guardie sono EQU dal nome parlante che valgono `1/0`
   (es. `GUARDIA_PIANO_IN_WORD`): se scatta, l'assemblaggio si ferma.
4. **Una sola fonte di verità**: i valori si derivano (dall'asset, dalla finestra, da `SCROLL_FETCH_BIT`),
   non si duplicano. I refactor devono essere no-op **dimostrati**.
5. **Regola delle variabili**: se una seconda entità avesse bisogno dello stesso stato, va nella struct `bob_*`.
6. **Prima di sovrascrivere un file, rileggerlo dal disco e metterne una copia in `backup/`**
   (`*.prima-<motivo>`). Michele modifica anche a mano; a fine settembre `Gioco.s` è anche tornato
   indietro da solo più volte: controllare con `impronta.py` prima e dopo.
7. Un registro che il copper riscrive ogni quadro **non si scrive dalla CPU** a metà schermo
   (BPLCON1, COLOR00): si patcha la copperlist.
8. Le EQU vanno definite **prima dell'uso** (Devpac). Gli indici `PH_*` del profiler sono
   **posizionali e in ordine cronologico**; l'ordine di `ProfWorst` e seguenti in memoria è vincolante.
9. `SFONDO_PLANE_SIZE` deve stare in una word (64000 oggi): **una riga di tile in più nella mappa
   la sfora** e la guardia ferma l'assemblaggio. `BLTSIZE` ha 6 bit di larghezza: i piani interi si copiano a strisce.
10. **Prova a costanti note** per separare "percorso di display rotto" da "contenuto sbagliato".
11. Quando l'utente ripete una condizione del difetto, **quella è il dato chiave**.
12. Prima di cambiamenti invasivi: spiegare cosa si tocca e i rischi, poi procedere.

## Documentazione di progetto fuori dal repository

`Gioco.s` rimanda a `claude/architettura.md`, `claude/decisioni.md`, `claude/convenzioni.md`,
`claude/prestazioni.md` e a un backlog. **Quei file non sono in questa cartella**: vivono nel
progetto Claude "Antiriad porting A1200". Vanno esportati qui (cartella `claude/`) se il
collaboratore deve averli.

## Lavori aperti noti

1. Cancellare `Gioco-misura-sprite.s` e `build/Gioco-misura-sprite.o`.
2. Decidere fra dissolvenza e tenda sulle porte, e togliere quella che non serve.
3. Sample `Sparo.raw` e `HitPlayer.raw` ancora segnaposto da 16 byte.
4. I nemici non hanno ancora gravità (`bob_VelY`/`bob_Grounded` esistono già nella struct).
5. Il mondo dell'originale richiede circa 4x4 blocchi: oggi ce ne sono 4 in fila.
6. Collaudo sull'A1200 reale di tutto ciò che tocca FMODE e sprite a 64 px.
7. Il backlog completo sta in `claude/backlog.md` (vedi sopra).

## Convenzioni

- Nomi di routine e variabili progressivamente in **italiano** (i nomi `PathB*`/`ScrollPathB*` restano).
- Spritesheet: frame separati da un riquadro vuoto delle stesse dimensioni (anche dopo l'ultimo);
  raw planare a piani sequenziali, piano 0 = bit basso.
- Le misure degli asset si dichiarano come misure del **file vero** e il resto si deriva, con una guardia sulla lunghezza dell'incbin.
- Lingua di lavoro: italiano, tono tecnico e diretto.
