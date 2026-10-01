# cr-parkour — tuning log

Stati: `CODE FIXED` → `WAITING IN-GAME TEST` → `VERIFIED IN GAME`.
Priorità: P0 player bloccato / crash / stato corrotto · P1 collisione grave / teleport / ability inutilizzabile ·
P2 animazione o detection sbagliata · P3 estetica / tuning.

Nessuna voce è ancora `VERIFIED IN GAME`. Nessun valore di tuning è stato cambiato senza un problema osservato in
gioco: i valori numerici del config sono quelli della Phase 5.

## Strumenti (Phase 6)

| Strumento | Uso |
| --- | --- |
| `Config.TuningMode = true` + `/parkourdebug` | menu ox_lib: flag debug (rays, state, animations, performance), reload registry animazioni, reset stato, recovery forzato, snapshot, parametri runtime per categoria, offset per animazione, elenco e ripristino delle modifiche |
| `/parkourdebug` con `TuningMode = false` | come prima: accende/spegne il debug |
| `/parkoursnapshot` | stampa in F8 e copia negli appunti stato, posizione, velocità, muro, ledge, ostacolo, animazione (CUSTOM/FALLBACK, dict, clip, tempo normalizzato), momentum, camera, cooldown, ultimi reason code, candidati vault, modifiche runtime |
| `/parkourperf` | profiler `Config.Profiler` (ms context / scanner / body / top / under / through / resolver / ability, raycast per frame e al secondo, tick corrente) |
| `Config.Ledge.Offsets` | offset `forward/right/up/heading` per grab, idle, moveLeft, moveRight, cornerLeft, cornerRight, climb |
| `Config.Wallrun.Offsets` | `heading/wallOffset/up` separati per wallrun sinistro e destro |
| `Config.AnimationOffsets['voce.registry']` | offset generico per le ability cinematiche (vault, wallrun, wallclimb, ledge, climb) |

Le modifiche runtime non sono persistenti: dal menu "Valori modificati" le copi e le riporti in `shared/config.lua`.
Con `Ledge.handAlign.enabled = true` gli offset `up`/`forward` delle animazioni ledge vengono compensati
dall'allineamento automatico delle mani: per tararli a mano disattivalo dal menu Ledge.
"Reload animation config" riesegue `shared/animations.lua` così come è stato scaricato all'avvio della resource
(scarta le modifiche runtime al registry); per caricare modifiche fatte su disco serve `restart cr-parkour`.

## Modifiche

### Wall flip — animazione interrotta subito
- Stato: `CODE FIXED` → `WAITING IN-GAME TEST`
- Causa: `wall_flip` (YCD, 2.23 s) è una clip terra-terra: il mover avanza di 1.68 m fino al muro (fase 0.27), il flip
  è tutto nel root bone (+0.88 m), atterraggio a 0.58, assestamento a 0.84 a ~1.4 m dal contatto. Il codice la trattava come
  un salto fisico (velocità su/indietro) e chiudeva l'ability al primo contatto col suolo, fermando la clip a metà.
- Modifica: a terra il wall flip è cinematico lungo la curva del mover (`meta` in `shared/animations.lua`), la clip parte
  dalla fase che corrisponde alla distanza reale dal muro (`Config.WallFlip.wallGap`), entity alla quota del terreno,
  atterraggio verificato dove la clip finisce (`landingTolerance`). Da wallrun / in aria resta il lancio fisico.
- Da tarare in gioco: `wallGap` (piede che non arriva al muro → abbassare; piede dentro il muro → alzare).

### Phase 10 — ottimizzazione
- Stato: `CODE FIXED` → `WAITING IN-GAME TEST` (performance e regressioni da misurare in FiveM, sezioni 21–22 di `TESTING.md`)
- Audit: il loop principale girava per-frame appena il player si muoveva (anche in veicolo, dove la velocità è quella del
  mezzo) con ~30 native per frame; con E tenuto in campo aperto ogni scan faceva ~23 raggi, di cui 11 per il THROUGH aperto
  e la clearance laterale (solo informativi) e 3 per il muro frontale già coperto dal fan.
- Verifica fuori dal gioco (stesso mondo di box della Phase 9, codice reale di scanner/detection): classificazioni identiche
  in 19 scenari tra percorso "debug" e percorso lazy (unica differenza voluta: THROUGH aperto senza debug). Raggi per scan:
  campo aperto 23 → 13 (fermo 19 → 9; da fermo gli scan successivi 0 grazie alla cache tra tick), avvicinamento a un
  muretto 38 → 14 con la cache della geometria, muro laterale 24 → 14.
- Valori iniziali da confermare: `Config.Performance.presets` (tick, `wakeSlice`, `statusInterval`), `Config.Cache`
  (`geometryTTL`, `positionTolerance`, `headingTolerance`).

### Phase 9 — Traversal Space Scanner
- Stato: `CODE FIXED` → `WAITING IN-GAME TEST`
- Verifica fatta solo fuori dal gioco: il codice reale (raycast, obstacle, wall, ledge, traversal, vault, slide) è stato
  eseguito contro un mondo di box che simula lo shape test. Hanno dato la classificazione attesa: muretti 0.6/1.0/1.25,
  muro 2.4 (CLIMB), muro 6 m (nessun ledge), tubo e rimorchio (UNDER → slide), trave 0.7 (OVER), uscita bloccata,
  finestra (THROUGH → jump_over), porta, fessura 0.4 (invalid), parete laterale (WALL), doppio ostacolo, ledge in aria.
  Corretti in quel passaggio: ostacoli sospesi classificati OVER, finestra respinta per path sopra l'architrave,
  larghezza dell'apertura misurata dietro il telaio, clearance top senza l'offset di superficie, scansione d'uscita
  UNDER troppo corta, scoring delle varianti slide che premiava sempre `slide_backside`.
- Valori iniziali da confermare in gioco: `TraversalCapsule` (0.6 / 1.8 / 1.2 / 0.95), `meta.minPassage` delle slide
  (1.0 / 0.85 / 1.0), `meta.clearanceRequired` dei vault, `Traversal.floatingPenalty`, `Under.exitScan`.

### Phase 8 — affidabilità resolver e dati reali delle clip
- Stato: `CODE FIXED` → `WAITING IN-GAME TEST`
- Cause trovate nel codice (audit): wall climb a 3.5 m/s minimi e vault a 1.2 m/s (da fermo davanti al muro non
  partiva nulla); `sameTarget` con solo raggio 0.75 m e 1.5 s (ringhiera sottile bloccata anche dal lato opposto);
  vault e ledge misuravano l'altezza da riferimenti diversi (gap intorno a 1.30 m); soglie senza tolleranza; top
  "irregolare" a 12 cm; clip avanzate scelte solo con match perfetto; lift della clip sommato al sollevamento
  dell'entity (vault troppo alto).
- Dati estratti dagli YCD (decoder offline del formato clip, traccia mover + root bone), usati nei `meta`:

| clip | durata | lift corpo | apice (fase) | distanza ostacolo nella clip | atterraggio dopo l'apice |
| --- | --- | --- | --- | --- | --- |
| jump_over_01 | 1.17 | 0.44 | 0.63 | 2.75 | 1.01 |
| jump_over_02 | 2.10 | 0.78 | 0.37 | 2.57 | 1.08 |
| jump_over_03 | 1.20 | 0.41 | 0.31 | 1.09 | 2.07 |
| kash_vault | 1.48 | 0.77 | 0.32 | 1.80 | 2.99 |
| monkey_vault | 0.97 | 0.76 | 0.41 | 1.80 | 2.19 |
| safety_l_vault | 1.00 | 0.77 | 0.37 | 1.54 | 1.49 |
| revers_l_vault | 0.93 | 0.65 | 0.36 | 1.94 | 1.46 |
| slide_r_vault | 1.33 | 0.60 | 0.25 | 1.11 | 3.37 |
| roll_a_vault | 1.07 | 0.64 | 0.22 | 1.11 | 3.51 |
| ledge_jump_up / power | 0.87 / 1.00 | salita finale 1.19 / 2.42 | | | |
| ledge_jump_l/r | 1.00 | laterale 3.35 | | | |
| ledge_move_l/r | 0.67 | laterale 0.76 per ciclo (1.13 m/s) | | | |
| wallrun_*_side | 1.67 | 1.24 | 0.46 | | |

- Valore da tarare per primo in gioco: `Vault.liftClearance` (0.45). Definisce l'altezza di progetto di ogni clip
  (`rootHeight + lift − liftClearance`): se tutti i vault passano alti, alzarlo; bassi, abbassarlo. Poi eventuali
  `meta.verticalOffset` per singola clip.
- Da verificare in gioco: il wallrun ha lift interno 1.24 m oltre a `Wallrun.initialLift` → se il corpo sale troppo,
  ridurre `Wallrun.Offsets.*.up` o `initialLift`. I range `minHeight/maxHeight` delle clip sono iniziali, derivati dal
  lift e dal tipo di vault, non ancora confermati visivamente.
- Ledge jump up: a fine clip l'entity viene spostata della salita della clip e riparte `ledge_idle` con blend
  istantaneo; se si vede uno scatto di un frame annotarlo qui.

### Phase 7 — hold mode, detection altezza reale, stamina
- Stato: `CODE FIXED` → `WAITING IN-GAME TEST`
- Vault troppo alto: prima l'apice della root era `topZ + rootHeight * arc + bodyClearance` (≈ top + 0.85 m) a metà
  percorso. Ora `topZ + rootClearance (0.4) + correzioni`, sopra il centro misurato dell'ostacolo, alla fase `cross`.
  Valori iniziali non tarati in gioco: `Vault.rootClearance`, `Vault.minRootLift`, `Vault.HeightCorrection`,
  `Vault.Offsets[*].verticalOffset` (tutti a 0).
- Dal config di riferimento analizzato (altro script parkour con lo stesso pack di animazioni): vault minimo 0.5 m
  (sotto è un gradino gestito da GTA), fase `cross` 0.5 delle clip vault, blacklist modelli/classi veicolo e
  materiali vegetazione. Non applicato ma da confrontare se l'hang resta sbagliato: lì i piedi pendono 1.8 m sotto il
  bordo con `ledge_idle` (root ≈ bordo − 0.82 con `Body.rootHeight` 0.98), da noi `Ledge.verticalOffset = -1.15`
  compensato da `handAlign`.
- Scanner: intervalli `Config.Scan` abbassati (idle 120, move 60, run 40, sprint 30 ms) perché ora girano solo con E tenuto.

### Debug animazioni — custom vs fallback
- Problema: il pannello mostrava solo `source`, senza distinguere un fallback legittimo da una custom non caricata.
- Causa: mancava il confronto con la voce del registry.
- Modifica: etichetta `CUSTOM` / `FALLBACK` / `NATIVE` / `SAFE`; `FALLBACK` in rosso con "BUG: custom presente" quando
  la voce ha una custom ma ne viene usata un'altra.
- Prima / dopo: — / —
- Stato: CODE FIXED · WAITING IN-GAME TEST

### Climb — landing bloccata
- Problema: con landing trovata ma occupata (oggetto, muretto) il reason era `CLIMB_DENIED_NO_LANDING`.
- Causa: `ClimbFrom` distingueva solo head clearance / no landing.
- Modifica: nuovo `CLIMB_DENIED_LANDING_BLOCKED`; il ped resta appeso, nessun movimento nella geometria.
- Prima / dopo: — / —
- Stato: CODE FIXED · WAITING IN-GAME TEST

### Vault — scelta dello stile non leggibile
- Problema: impossibile capire perché veniva scelto uno stile invece di un altro.
- Causa: la selezione restituiva solo il primo stile valido.
- Modifica: debug `vault candidates` con score (frazione di vincoli rispettati), primo vincolo fallito, clip
  mancante e `selected`. La selezione resta deterministica (primo stile valido nell'ordine di `Config.Vault.styles`).
- Prima / dopo: — / —
- Stato: CODE FIXED · WAITING IN-GAME TEST

### Scanner — soglie vault non aggiornate a runtime
- Problema: cambiando `Vault.*.maxHeight` dal menu, la scansione del muro frontale usava ancora il valore iniziale.
- Causa: altezza massima calcolata una sola volta al caricamento.
- Modifica: calcolata a ogni scansione.
- Stato: CODE FIXED · WAITING IN-GAME TEST

### Precision — velocità disponibile non visibile
- Modifica: il debug mostra `req` (richiesta) e `avail` (disponibile).
- Stato: CODE FIXED · WAITING IN-GAME TEST

### Wallrun — offset per lato
- Modifica: `Config.Wallrun.Offsets.left/right` (`heading`, `wallOffset` lungo la normale, `up`), applicati solo
  alla posa visiva; la distanza fisica resta `wallDistance`.
- Prima / dopo: nessun offset / tutti 0.0 (comportamento invariato finché non tarati)
- Stato: CODE FIXED · WAITING IN-GAME TEST

## Risultati in gioco

Da compilare durante i test (una voce per problema osservato, con lo snapshot allegato).

| Ability | Priorità | Problema | Causa | Modifica | Prima | Dopo | Stato |
| --- | --- | --- | --- | --- | --- | --- | --- |
| | | | | | | | |

## Performance rilevate

| Scenario | resmon ms | raycast/s | scanner ms (avg/peak) | context ms (avg) | tick | note |
| --- | --- | --- | --- | --- | --- | --- |
| A fermo senza E | | | | | | |
| B corsa senza E | | | | | | |
| C E campo aperto | | | | | | |
| D E davanti muro | | | | | | |
| E E zona complessa | | | | | | |
| F vault | | | | | | |
| G wallrun | | | | | | |
| H ledge | | | | | | |
| I UNDER | | | | | | |
| J combo lunga | | | | | | |
