# Handoff – Antiriad porting A1200

*Scritto il 7 ottobre 2026 per chi riprende il lavoro. Fotografa il punto in cui ci si è fermati;
**come funziona il progetto** sta in `CLAUDE.md`, che va letto per primo e qui non viene ripetuto.*

Riferimento della versione: `Gioco.s` impronta `07978d9e3d48` (10.863 righe, ultima modifica
domenica 4 ottobre 2026, 21:36). Controlla con `py tools\impronta.py`: se non coincide, qualcuno
ha lavorato dopo questo documento.

## Dove siamo

Il motore è completo e stabile: scroll hardware, doppio buffer, parallasse a sprite, darkplane,
pannello con tutti gli strumenti, titolo e intro, BOB unificati. **Il lavoro in corso è il level
design**: riempire i 4 blocchi di mappa e farli funzionare insieme.

Cronologia dell'ultimo periodo (ricostruita dalle copie in `backup/`):

| Quando | Cosa |
|---|---|
| 24 settembre | Porta fra blocchi, dissolvenza della palette (`FADE_PASSAGGIO`), banco notte scritto dal copper, il mondo si costruisce mentre l'alba è ancora a video |
| 29–30 settembre | Da una mappa a più blocchi: griglia in `risorse/mappe.txt` → `Mappe.i`, porte sui 4 lati (`VERSO_*`), `mappa1..4` in `.txt` |
| 3–4 ottobre | Nuove tile 93–127 disegnate in `Tiles.raw`, usate da mappa2/3/4; `TileFlags` estese fino alla 127; salto ritarato (`GRAVITA_88` da 86 a 80) |

## Stato verificato oggi

- `py tools\porte.py` → **tutte le porte reggono** (anello orizzontale mappa1→2→3→4→1)
- `py tools\mappe.py --guarda` → griglia coerente con `Mappe.i`
- `py tools\controlla-forward.py` → nessun riferimento in avanti, il sorgente va bene anche a Devpac
- `TILE_VIA` (partenza del player) è solo in **mappa1**: corretto, si parte lì

## Lavoro a metà

1. **Collisioni delle tile nuove (93–127).** In `TileFlags` sono state messe in chiaro con la
   regola "si parte calpestabili e si alzano una alla volta guardando la sagoma". Alcune sono già a 1,
   altre ancora a 0. Il metodo: `py tools\mappa.py --mappa N` rigenera `risorse/mappaN-sagoma.txt`
   (`#` bloccata, `.` libera) e stampa quante volte compare ogni tile; si confronta la sagoma con
   l'anteprima `risorse/grafica/mappaN-arte.png` e si alza il flag di chi deve essere solido.
   Dopo ogni modifica a mappe o flag: `py tools\porte.py`.
2. **L'ultima build provata è più vecchia dell'ultima modifica.** L'eseguibile `uae/dh0/Gioco` è
   delle 21:32 del 4 ottobre, `Gioco.s` e `mappa1.raw` delle 21:36. Prima di tutto: build completa
   (Ctrl+Shift+B) e un giro nei 4 blocchi in WinUAE, attraversando ogni porta.

## Decisioni ancora aperte

- **Dissolvenza o tenda sulle porte**: oggi è attiva la dissolvenza; se convince, `TENDA_PASSAGGIO`
  e il suo codice vanno tolti (un interruttore con una sola posizione utile non deve restare).
- **Quanti blocchi**: l'originale richiede circa 4x4 blocchi (`tools/mappe.py` lo dice nel suo
  commento); oggi sono 4 in fila. La griglia supporta già anche sopra/sotto.
- **Nemici sulle mappe nuove**: le posizioni di partenza dei nemici non vengono ancora dalla mappa
  come quelle del player e del falò; i nemici non hanno gravità.

## Da sapere prima di toccare qualcosa

- Le mappe si scrivono in `risorse/mappaN.txt` (numeri o nomi `TILE_*`), mai nel `.raw`.
  I collegamenti in `risorse/mappe.txt`, mai in `Mappe.i`.
- Una riga di tile in più per blocco **sfora la word** di `SFONDO_PLANE_SIZE` (oggi 64000):
  la guardia ferma l'assemblaggio. Le misure di blocco attuali (73x24) sono il massimo.
- L'intestazione dei `.txt` delle mappe dice ancora "25 colonne x 22 righe": è vecchia.
- Prima di sovrascrivere `Gioco.s`, copia in `backup/` (`*.prima-<motivo>`). A fine settembre il
  file è tornato indietro da solo più volte: `impronta.py` prima e dopo.
- `Gioco-misura-sprite.s` e `build/Gioco-misura-sprite.o` vanno cancellati.

## Documenti di riferimento

- `CLAUDE.md` – architettura, strumenti, regole di lavoro
- `claude/architettura.md`, `claude/decisioni.md`, `claude/convenzioni.md`, `claude/prestazioni.md`,
  `claude/backlog.md` – **se presenti nel repository** (vengono dal progetto Claude di Michele)
- Commenti in testa a ogni strumento di `tools/` – spiegano perché esiste e come si usa

## Skill suggerite per la prossima sessione

Nessuna skill specifica serve per riprendere. A fine sessione usa `/handoff` per aggiornare questo
documento.

## Da completare da Michele prima del commit

- [ ] Su quale mappa o tile stavi lavorando per ultimo, e cosa volevi fare dopo
- [ ] Se ci sono difetti noti visti a schermo e non ancora corretti
- [ ] Come vi dividete il lavoro (chi tocca le mappe, chi il codice), per evitare conflitti su `Gioco.s`
