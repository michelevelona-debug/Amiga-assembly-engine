# Scomposizione di Gioco.s in moduli (9-10 ottobre 2026)

Base: commit `86826fc` ("4 mappe"), `Gioco.s` con impronta `07978d9e3d48`
(10.285 righe, 448.033 byte).

## Cosa e' cambiato

`Gioco.s` e' stato diviso in 28 file `.i`. Resta la regia (~690 righe):
SECTION, include, START e main loop. Il codice e' stato **spostato, non
riscritto**: stesso ordine, stessi commenti.

Gli include stanno nello stesso punto in cui c'era il codice, quindi l'ordine
di assemblaggio non cambia:

| Modulo | Contenuto |
|---|---|
| `CostTitolo.i` | Costanti: schermata del titolo e droide |
| `CostDisplay.i` | Costanti: DMA, mappa, scroll, display, fade, alba, sfondo, cielo, alberi |
| `CostPannello.i` | Costanti: strumenti del pannello |
| `CostGioco.i` | Costanti: pietra, player, fisica, tasti, luce, falo', suoni |
| `CostProfilo.i` | Costanti e macro PROFMARK del profiler |
| `Sheet.i` | Fogli costruiti al boot: falo', rotella, indicatori |
| `Misura.i` | Misura del quadro: LeggiRiga, FineLavoro |
| `Input.i` | Joystick e tastiera |
| `Mondo.i` | Camera, bordi, porte fra i blocchi, ricostruzione del mondo |
| `Sfondo.i` | Disegno dello sfondo, copper del cielo, skyline |
| `Parallasse.i` | Parallasse degli alberi sugli sprite |
| `Init.i` | Inizializzazioni: pannello, player, nemici, pietra, maschere BOB |
| `Collisioni.i` | Centro camera, collisioni con tile e BOB, movimento nemici |
| `Palette.i` | Palette AGA, notte, dissolvenza, transizioni |
| `Titolo.i` | Schermata del titolo e droide |
| `Suoni.i` | Effetti sonori |
| `Combattimento.i` | Pietra, combattimento, uccisioni |
| `Luce.i` | Falo', partenza dalla mappa, cerchio di luce |
| `Nemici.i` | Intelligenza dei nemici |
| `Player.i` | Fisica e posizione del player |
| `Bob.i` | Disegno dei BOB |
| `Pannello.i` | Strumenti del pannello, AspettaBlitter, scritta scorrevole |
| `PathB.i` | Scroll hardware, rettangoli sporchi, master, darkplane |
| `Profilo.i` | Monitor delle prestazioni |
| `Variabili.i` | Variabili CPU (sezione DATI) |
| `Chip.i` | Dati in chip RAM: copperlist, grafica |
| `AssetCPU.i` | Asset letti solo dalla CPU |
| `BufferChip.i` | Buffer in chip RAM |

Gli include gia' esistenti (`Startup2.i`, `ScrollHW.i`, `Testo.i`,
`CieloGrad.i`, `Intro.i`, `Mappe.i`, `ptplayer.i`) non sono stati toccati.

## Verifica

- Dopo la scomposizione `.o` ed eseguibile erano **identici byte per byte**
  a quelli dell'originale (md5 `bdee1685...`).
- 10/10: ricompilato con vasm 2.0f / vlink 0.18a
  (`-m68020 -Fhunk -linedebug -I. -Iinclude`) e provato in FS-UAE
  (A1200, Kickstart 3.1, 2 MB chip + 8 MB fast): gira normalmente, nessun
  errore nel log.

## Correzione: allineamento in Variabili.i

vasm dava tre warning `3023 unaligned relocation offset` su `WorldShow`,
`WorldDraw` e `CurDirty`. La causa era un `ds.b 1` ("padding: riallinea a
word") subito dopo `EVEN` + `AutoScrollCnt: dc.w 0`: invece di riallineare,
spostava a indirizzi dispari tutte le variabili che seguono. Il 68020 lo
tollera, ma paga cicli in piu' a ogni accesso, e un 68000 andrebbe in address
error. Il `ds.b 1` e' stato tolto e i warning sono spariti.

Questa e' l'unica modifica al codice. Da qui in poi l'eseguibile **non e' piu'
identico** a quello di `86826fc`: le variabili da `PathBCamX` in giu' stanno
un byte prima.

## Strumenti Python adattati

Gli strumenti che leggevano `Gioco.s` come file unico ora espandono gli
include (`valori._espandi`), cosi' vedono lo stesso testo di prima:

- `impronta.py`: l'elenco dei sorgenti si ricava dagli include di `Gioco.s`,
  quindi un modulo nuovo entra in automatico;
- `registri.py`, `mappe.py`, `grafica.py`, `simula-strumenti.py`: leggono il
  sorgente espanso. I numeri di riga che riportano sono quelli del testo
  espanso, non di un singolo modulo.

## Se modifichi Gioco.s su una versione precedente

Se hai modifiche a `Gioco.s` fatte prima di questo commit, non si fondono
automaticamente: il codice ora sta nei moduli. Le modifiche vanno riportate a
mano nel `.i` corrispondente (vedi la tabella).

---

# Come e' organizzato il codice (11 ottobre 2026)

*Questa parte e' RICAVATA DAL CODICE, non dalla tabella qui sopra: l'ordine
degli `include` e le SECTION sono stati letti da `Gioco.s`, e ogni routine
nominata e' stata cercata con la sua etichetta nel modulo che la definisce.*

## La forma di Gioco.s (688 righe di regia)

```
SECTION MegaGame,CODE  ─────────── tutto il codice sta qui dentro
│
├─ CostTitolo.i                    le COSTANTI aprono il file
├─ Startup2.i                      startup AGA + VBR + cache  (latin-1!)
├─ CostDisplay.i  CostPannello.i  CostGioco.i  CostProfilo.i
│
├─ START:  ~470 righe              boot: titolo -> intro -> init -> mainloop
│   └─ .mainloop:                  il quadro (resta nella regia)
│
├─ Sheet  Misura  Input  Mondo  Sfondo  Parallasse  Init  Collisioni
├─ Palette  Titolo  Suoni  Combattimento  Luce  Nemici  Player  Bob
├─ Pannello.i ──include──> Testo.i
├─ PathB.i    ──include──> ScrollHW.i + CieloGrad.i
├─ Profilo.i
└─ Intro.i

SECTION DATI,DATA        fast   Variabili.i ──include──> Mappe.i
SECTION ChipStuff,DATA_C CHIP   Chip.i ──include──> Pannello.cop (due volte)
SECTION AssetCPU,DATA    fast   AssetCPU.i
SECTION PLANEVUOTO,BSS_C CHIP   BufferChip.i
SECTION LavoroCPU,BSS    fast   (nella regia)
SECTION SpritesData,DATA_C CHIP (nella regia)
SECTION Entities,BSS     fast   (nella regia)
SECTION PTPlayerCode,CODE       ptplayer.i  <- l'`end` VERO e' qui dentro
end                             <- gia' codice morto
```

Quattro cose che la tabella dei moduli non dice:

- **I moduli non sono unita' di link: sono tagli di un file unico.** Un solo
  `SECTION CODE`, nell'ordine del vecchio `Gioco.s`. Non c'e' incapsulamento,
  ogni etichetta resta globale: spostare una routine in un altro `.i` non
  cambia niente per l'assemblatore, cambia solo chi la trova.
- **Le costanti stanno in testa, e non per estetica.** Devpac valuta una EQU
  dove la incontra: una EQU nuova usata da un modulo va in un `Cost*.i`, non
  accanto al codice che la usa.
- **Quattro include sono ANNIDATI dentro altri moduli**, non nella regia:
  `Testo.i` dentro `Pannello.i`, `ScrollHW.i` e `CieloGrad.i` dentro `PathB.i`,
  `Mappe.i` dentro `Variabili.i`. Chi cerca "dove e' incluso X" guardando solo
  `Gioco.s` non li trova.
- **I dati sono divisi per CHI LI LEGGE, non per cosa sono.** In chip quello
  che leggono blitter, copper, display e Paula; in fast quello che legge solo
  la CPU. E `PTPlayerCode` deve restare l'ULTIMA SECTION: un modulo nuovo va
  prima, se no finisce sotto l'`end` di ptplayer e non esiste.

## Il quadro, e in quale modulo vive ogni pezzo

```
AspettaVBL  ····················· Gioco.s (regia)
GestisciMusica ·················· Gioco.s (regia)
AggiornaTransizione ············· Palette.i      la dissolvenza fra blocchi
LeggiTastiera / LeggiJoystick ··· Input.i
RettangoloScrollNelCentro ······· Collisioni.i
AggiornaFisicaPlayer ············ Player.i       gravita' e salto -> IntentY
AggPosizioneGlobalePlayer ······· Player.i
ControllaPassaggio ·············· Mondo.i        le PORTE fra i blocchi
CalcolaInseguimentoCameraY ······ Mondo.i
ControllaBordi ·················· Mondo.i
ScrollPathB ····················· PathB.i
AggiornaParallasseSprite ········ Parallasse.i
AnimaFalo ······················· Luce.i
AggiornaNemici ·················· Nemici.i
Combattimento / Proiettile ······ Combattimento.i
SuonoPassi ······················ Suoni.i
PathBRestoreAll ················· PathB.i
DisegnaBOBs ····················· Bob.i
AspettaBlitter ·················· Pannello.i
ScrollPathBApply ················ PathB.i        scambio dei buffer
Disegna* (i 7 strumenti) ········ Pannello.i
FineLavoro ······················ Misura.i
MostraProfilo ··················· Profilo.i
```

## Dove il nome del modulo inganna

Ne era rimasto uno, dopo gli spostamenti dell'11 ottobre (vedi sotto):

- **`ImpostaDisplayGioco` sta in `Titolo.i`** (riga 99), accanto alla gemella
  `ImpostaDisplayTitolo` (riga 83), con cui condivide le EQU.

E quattro routine sono rimaste NELLA REGIA, non in un modulo: `AspettaVBL`,
`GestisciMusica`, `AggiornaCopperBPL` e `AggiornaCopperSPR`.

## Spostamenti dopo la scomposizione

La tabella dei moduli in testa a questo file descrive il **9-10 ottobre**, cioe'
com'era al taglio. Non si aggiorna: ha una data e serve a chi deve riportare a
mano una modifica fatta prima di quel commit. Dove sta una routine ADESSO lo
dicono le due mappe qui sopra, e questo elenco:

| Data | Routine | Da | A | Perche' |
|---|---|---|---|---|
| 11 ott | `DisegnaPannello` | `Init.i` | `Pannello.i` | il nome prometteva Pannello.i e la gente la cercava la' |
| 11 ott | `AggiornaNemici` | `Collisioni.i` | `Nemici.i` | movimento e decisione dei nemici nello stesso file |

Effetto sulle descrizioni della tabella del 9-10 ottobre: per `Init.i`,
`Collisioni.i`, `Nemici.i` e `Pannello.i` non valgono piu'. `Init.i` non
costruisce piu' il pannello; `Collisioni.i` non muove piu' i nemici; `Nemici.i`
ha decisione **e** movimento; `Pannello.i` ha anche la costruzione di boot.

Lo spostamento e' stato un no-op dimostrato: il sorgente espanso ha le stesse
12.161 righe, lo stesso multiset, e `tools/misura-salti.py` conta 410 salti
corti prima e 410 dopo, nessuno allungato. Il codice e' stato tagliato e
incollato, non riscritto.
