# cr-parkour — development notes (Italian)

> Historical design notes written phase by phase during development (Phase 1 → Phase 10), in Italian.
> They explain *why* the systems work the way they do. Some details were superseded by later phases
> (e.g. `Config.Vault.styles` / `pickMode` no longer exist): the code and the main [README](../README.md) win.

## Phase 1

Traversal engine contestuale, standalone (solo `ox_lib`). Nessuna coordinata o zona: tutto deriva da raycast
sull'ambiente e dallo stato del ped.

## Flusso

```text
+parkour / -parkour (hold) + combinazioni SPACE / CTRL / X → Input (buffer)
Context.Update   → stato ped, velocità, input camera-relative, tracking caduta
Scanner.Run      → obstacle / wall (front, left, right) / ledge, frequenza adattiva
Resolver.Tick    → Evaluate(ctx, scan) delle ability compatibili con lo stato
Ability          → Enter / Update / Exit, restituisce { next, payload, velocity, motion }
Movement/Momentum/Animation → controllo cinematico (ped congelato + interpolazione) o fisico (velocity)
```

File extra rispetto allo schema richiesto: `client/core/vec.lua` (matematica vettori), `client/core/scanner.lua`
(Environment Scanner), `client/core/resolver.lua` (Parkour Resolver).

## Input — parkour mode a pressione mantenuta (Phase 7)

Centralizzato in `client/core/input.lua`. Il tasto parkour è un **hold**: `RegisterCommand('+parkour')` /
`('-parkour')` + `RegisterKeyMapping` (`Config.Input.command`, default **E**, modificabile nelle impostazioni tasti
di FiveM → `Input.IsParkourHeld()`).

| Stato | Comportamento |
| --- | --- |
| E rilasciato | GTA normale: nessuno scanner, nessun vault/wallrun/climb automatico, SPACE salta, CTRL accovaccia |
| E tenuto | scanner continuo + resolver automatico: vault, wall climb, wallrun, balance a terra; ledge, tic-tac, wallrun in aria |
| E + SPACE | precision se c'è un gap con target valido, altrimenti long jump (SPACE intercettato solo se uno dei due è valido) |
| E + CTRL | slide (o roll in caduta / roll tardivo); se la slide non è valida per la velocità CTRL resta al crouch GTA, se è negata per pendenza/ostacolo l'input viene ignorato |
| E + X | wall flip, poi trick aereo; con E + X tenuti il resolver automatico (vault / climb / slide...) non parte e a ogni scan si prova solo il wall flip |
| durante un'ability | nuova pressione di E oppure SPACE (con E tenuto): appeso → climb, wallrun/wall climb → walljump, balance → salto; CTRL appeso → drop (anche senza E) |

Il resolver automatico (`Resolver.Tick`) parte solo su una scansione fresca dello stesso tick e sceglie in base a
geometria, velocità e angolo: a terra balance → vault → (se un ostacolo vaultabile è in avvicinamento aspetta, non
parte un wallrun) → wall climb → wallrun; in aria ledge → tic-tac / wallrun ordinati per angolo col muro.
Anti-loop: scan fresco obbligatorio, cooldown per ability, `Config.TraversalRepeat` (vedi Phase 8), same-wall del
wallrun. Tenere E non consuma stamina.

## Ability avanzate (Phase 4)

| Ability | Input | Condizioni principali | Animazione |
| --- | --- | --- | --- |
| Tic-tac L/R | E in aria | muro entro `contactDistance`, angolo 20–70° dalla parete, spazio d'uscita libero; momentum riflesso sulla normale | `tictak_l/r_vault` |
| Wall flip | X+E | muro frontale alto, spazio dietro/sopra libero, atterraggio previsto valido (anche da wallrun) | `wall_flip` |
| Precision | E a terra | gap → superficie target → larghezza/profondità/clearance → velocità balistica plausibile → traiettoria libera | nativa / `big_jump_01` (long) |
| Long jump | E in sprint | velocità alta, nessun ostacolo vicino, traiettoria non bloccata | `big_jump_01` |
| Air trick | X+E in aria | altezza/tempo di volo sufficienti, atterraggio previsto, testa libera | solo `front_twist_flip` (nessuna clip per front/back/side flip → `TRICK_DENIED_NO_ANIMATION`) |
| Balance | E su superficie stretta | superficie più stretta di `maxWidth`, con dislivello su entrambi i lati; W/S cammina, E salta | `balance_idle/run/jump_f` |

Gli input della tabella sopra sono quelli della Phase 4: dalla Phase 7 tic-tac, balance, vault, wallrun e wall climb
partono da soli con E tenuto; precision e long jump sono E + SPACE; wall flip e trick E + X. Vault: stile scelto da `Config.Vault.styles` (kong, speed, slide, reverse,
safety) in base ad altezza, profondità, velocità, angolo e caduta; nessuna scelta casuale.

Moduli: `detection/trajectory.lua` (previsione balistica a segmenti), `detection/surface.lua` (larghezza superficie),
`systems/launch.lua` (lancio fisico guidato condiviso), `core/combo.lua` (finestra di transizione e tolleranza velocità
tra ability concatenate, `Config.Combo`).

## Debug

`Config.Debug = true` oppure `/parkourdebug`. Colori: verde raycast libero, rosso colpito / front face, blu top
surface, giallo landing, viola ledge / target animazione vault. Il pannello mostra stato, velocità, muro, ledge, ostacolo, caduta e l'ultimo reason
code per ogni ability (verde OK, rosso negato).

## Animazioni (Phase 2)

- Registry: `shared/animations.lua` (`Config.AnimationRegistry`). Ogni voce ha `custom` e/o `native`; un valore
  stringa è un alias a un'altra voce (niente dict/clip duplicati). Override per voce: `Config.AnimationOverrides['ledge.idle'] = { custom = {...} }`.
- Campi clip: `dict, clip, blendIn, blendOut, duration, flag` (o `flags` per nome), `playbackRate, lockX/Y/Z, rootMotion`.
  Voce: `syncDuration` (la durata dell'ability segue la clip custom), `events` (override dei tempi `start/assist/transition/control/exit`).
- Priorità: custom → nativa GTA → safe (nessuna clip, timeline virtuale). Un'animazione mancante non blocca mai l'ability.
- Pack presenti (verificati contro i TXT `stream/animas-1.txt` e `stream/anims-2.txt`):
  - `parkour@anims`: slide, slide_backside, slide_kip_up, jump_over_01/02/03, big_jump_01, swing_jump, wall_flip, front_twist_flip
  - `parkour_part_2@anim`: ledge_idle, ledge_move_l/r, ledge_corner_outer_l/r, ledge_jump_l/r/up/up_power, wallrun_left/right_side,
    diveroll_l/r, safety_l/revers_l/slide_r/monkey/kash/roll_a/tictak_l/tictak_r_vault, balance_idle/run/jump_f
    (+ `balance_drop_l/r` e `hanging_sequince`, presenti nel YCD ma non nel TXT)
- In uso: ledge (idle/move/corner), wallrun, roll (diveroll), slide, vault (low: slide/safety/jump_over_01, medium:
  monkey/kash/jump_over_02, scelta casuale `Config.Vault.pickMode`). Registrate ma non usate: ledge jump, tictak,
  reverse/roll vault, balance, tricks. Ledge climb e walljump restano native (nessuna clip dedicata nel pack).
- `/parkouranims`: report `CUSTOM ANIMATIONS FOUND` (TXT validato contro gli asset, voci del registry, `ANIMATION_ASSET_MISSING`, `ANIMATION_NOT_IN_MANIFEST`). Parte da solo con il debug attivo. `/parkouranim <voce>`: riproduce la clip da
  fermo e misura spostamento/heading → indica se impostare `rootMotion = true`.
- `headingOffset` / `positionOffset {forward,right,up}` per clip: correzione visiva applicata sopra la posa geometrica
  (heading = verso il muro da `-wallNormal`). La nativa del boma usata per il ledge ha `headingOffset = 180`.
- `rootMotion = true`: slide e roll applicano solo un assist di velocità (`Config.Animations.rootMotionAssist`);
  nelle ability cinematiche (vault, ledge, climb) la posizione resta sempre guidata dalla geometria.

## Production polish (Phase 5)

Moduli nuovi:

| File | Ruolo |
| --- | --- |
| `client/core/lifecycle.lua` | ciclo `enter → active → exit / recovery` di ogni ability, eventi, cooldown, camera, gate armi |
| `client/core/recovery.lua` | `Recovery.SafeReset(ctx, reason, options)` + watchdog (`Config.StateTimeouts`, hold/anim/ragdoll orfani) |
| `client/core/cooldowns.lua` | `Cooldown.CanUse/Start/End/Remaining/CanExit` da `Config.Cooldowns` (`cooldown` dopo la fine, `retriggerDelay` dopo l'inizio, `minimumExitTime` prima di un'uscita volontaria, `globalGap` tra due start) |
| `client/systems/camera.lua` | effetti leggeri (roll/FOV via cam overlay che copia la gameplay cam solo mentre un effetto è attivo, shake), `Camera.Reset()` |
| `client/systems/damage.lua` | hook danni `hardLanding`, `failedRoll`, `largeFall`, `collision` |
| `client/debug/profiler.lua` | `/parkourperf` (`Config.Profiler`): ms context / scanner (body, top, under, through) / resolver / ability, raycast per tick e al secondo, cache hit, loop attivi |
| `shared/presets.lua` | `Config.Preset = 'realistic' | 'balanced' | 'arcade'` come moltiplicatori/override, senza duplicare il config |

Comportamenti:

- **Nessun auto-parkour senza E**: tutto il traversal automatico richiede E tenuto (Phase 7). Il ledge grab resta
  automatico anche senza E solo in catena da un'ability aerea già avviata (`autoGrabFromAbility`).
- **Input buffer** (`Config.InputBuffer`): E 200 ms, climb 450, walljump 300, roll 250, trick 150. Una pressione in buffer
  viene ritentata solo quando arriva una scansione nuova, mai a ogni frame.
- **Coyote time** (`Config.CoyoteTime`, 120 ms): solo dopo essere scesi da un bordo camminando (non dopo un salto o
  un'ability), solo per precision e long jump.
- **Sicurezza ped** (`Context.CanParkour`): morto, veicolo (anche entrando), ragdoll, rialzo, nuoto, sott'acqua, scala
  (`GetIsTaskActive` 1/47/48), climb nativo, paracadute, caduta libera, parkour disabilitato via export. Al passaggio a
  uno di questi stati → `SafeReset` una volta.
- **Teleport/respawn**: salto di coordinate > `Config.Recovery.teleportDistance` o cambio del ped → reset senza
  velocità residua.
- **Superfici**: le normali sono classificate floor / wall / slope / ceiling (`Raycast.Classify`). Veicoli, oggetti in
  movimento e ped non sono superfici parkour (`Config.DynamicSurfaces`, `PARKOUR_DENIED_DYNAMIC_SURFACE`); i
  materiali si filtrano con `Config.Materials` (nomi o hash, `PARKOUR_DENIED_MATERIAL`). Un'entità rifiutata resta
  comunque un ostacolo che blocca.
- **Geometria ambigua**: muro con normali discordanti (angolo, superficie curva) → `WALL_AMBIGUOUS`; ostacolo con
  qualcosa subito sopra (ringhiera sopra il muretto) → `VAULT_DENIED_AMBIGUOUS`.
- **Vault**: clearance sopra il top, percorso a due altezze, secondo ostacolo dopo l'atterraggio
  (`VAULT_DENIED_EXIT_BLOCKED`), uscita RUNNING/SPRINTING se c'è terreno sotto il target, FALLING altrimenti.
- **Wallrun**: distanza corretta solo lungo la normale e solo oltre `distanceTolerance`, refresh del muro ogni 50 ms,
  decay con drag, uscite distinte (walljump, ledge, fine muro, velocità, curva > `maxCurve`, durata, terreno,
  collisione con spinta via dal muro).
- **Ledge**: validazione ogni 150 ms durante l'hang (`LEDGE_INVALIDATED` → caduta con spinta fuori dal muro), ped
  spostato da altri (`LEDGE_DISPLACED`), allineamento mani con isteresi, correzione distanza dal muro limitata in
  velocità, `SetEntityCoordsNoOffset` solo quando posizione o heading cambiano davvero.
- **Slide**: niente in salita ripida (`SLIDE_DENIED_SLOPE`) o con ostacolo davanti, gravità della pendenza, stop
  sicuro (sotto copertura inverte invece di fermarsi dentro).
- **Roll**: spazio davanti (`ROLL_DENIED_FRONT_BLOCKED`), su cadute enormi conserva meno momentum e il danno è
  ridotto, non annullato.
- **Animazioni**: `Animation.CrossFade` per i cambi dentro un'ability, `Stop(name, { blendOut })`,
  `StopAllParkour(immediate)`, campo `cancelable`. Nessun `ClearPedTasksImmediately`; `ClearPedTasks` solo nel
  recovery del watchdog.

## Ostacoli, vault e stamina (Phase 7)

- **Rilevazione ostacolo** (`client/detection/obstacle.lua`): faccia frontale dal fan di raycast → `Obstacle.FindEdge`
  (ricerca binaria verticale `edgeRefine` volte tra l'ultima altezza colpita e la prima libera) →
  `Obstacle.GetTopSurface` (raggi verso il basso a `topSamples` dentro il bordo, normale e varianza validate) →
  `Obstacle.GetDepth` (passi da `depthStep` lungo `-normal` finché la superficie continua, poi ricerca binaria) →
  landing, path e uscita lungo la stessa direzione. Altezza = `topZ - groundZ`, con `groundZ` dal raycast sotto i piedi
  (`Obstacle.GroundZ`), non dalla root del ped.
- **Vault**: `Vault.BuildContext` produce il `VaultContext` (`obstacleHeight`, `obstacleDepth`, `topZ`, `groundZ`,
  `landingZ`, `approachSpeed`, front face, top, center, landing). Il path è una curva a due segmenti con apice sopra
  il centro reale dell'ostacolo a `topZ + rootClearance + HeightCorrection[banda] + Offsets[anim].verticalOffset`
  (mai sotto `root di partenza + minRootLift`), raggiunto alla fase `cross` della clip
  (`Config.Animations.events.cross`, override per voce con `events.cross` nel registry).
- **Reason code vault**: vedi Phase 8 (`OBSTACLE_*` per la geometria, `VAULT_DENIED_*` per l'ability).
- **Blacklist** (`Config.DynamicSurfaces.blacklistModels`, `blacklistVehicleClasses`, `Config.Materials.blacklist`):
  distributori, ATM, cabine, pompe di benzina, mezzi pesanti/militari, barche/aerei/elicotteri/treni e vegetazione
  non sono superfici parkour (`PARKOUR_DENIED_BLACKLISTED`, `PARKOUR_DENIED_MATERIAL`).
- **Stamina** (`client/systems/stamina.lua`, `Config.Stamina`): `enabled = false` → nessun controllo, consumo o
  deny. Attiva: `Stamina.CanPerform(ability)` dentro `Lifecycle.Allowed` (unico gate per tutte le ability, più il
  walljump), consumo singolo all'avvio effettivo (`costs`, in % della stamina massima GTA), consumo continuo per
  `drain` (wallrun, % al secondo; a stamina finita l'ability termina con `PARKOUR_END_LOW_STAMINA`). Native CFX
  `GetPlayerStamina` / `GetPlayerMaxStamina` / `SetPlayerStamina`. Deny: `VAULT_DENIED_LOW_STAMINA`,
  `WALLRUN_DENIED_LOW_STAMINA`, `PARKOUR_DENIED_LOW_STAMINA`.
- **Debug**: pannello con `PARKOUR HELD`, candidate, selected, stamina, last deny, `VAULT GEO` (groundZ, baseZ, edgeZ,
  topZ, height, depth, landingZ) e `VAULT CTX` (player ground Z, obstacle top Z, calculated height, animation target
  Z, vertical offset). Disegno 3D: rosso front face, blu top surface/centro, giallo landing, verde path calcolato
  della root, viola target animazione (con segmento fino al top). Se il viola è giusto ma il ped passa alto →
  offset animazione; se il blu è sbagliato → detection.

## Affidabilità, resolver a punteggio e animazioni reali (Phase 8)

- **Riferimento terreno unico**: lo scanner misura il suolo sotto i piedi una volta per scan (`Obstacle.GroundZ`) e
  tutte le detection (ostacolo, muri, ledge, superficie) usano quella quota. Prima vault e ledge usavano riferimenti
  diversi e intorno a 1.30 m nessuno dei due accettava l'ostacolo.
- **Tolleranze** (`Config.Detection`): altezza ±5 cm, distanza +15 cm, angolo +10°, velocità −0.5 m/s su tutti i
  confini (vault, clip, wall climb, ledge).
- **Intento a bassa velocità**: vault e wall climb non richiedono più velocità minima; sotto `intentSpeed` serve
  l'input di movimento verso l'ostacolo (`PARKOUR_DENIED_NO_INTENT`). Wall climb da fermo/lento limitato a
  `Wallclimb.slowMaxHeight`.
- **Ripetizione** (`Config.TraversalRepeat`): lo stesso ostacolo è bloccato solo se è lo stesso lato
  (`sameSideDot`), entro `radius`, e non sono passati `sameObstacleCooldown` ms **oppure** il player non si è
  allontanato di `resetDistance` (rilascio comunque dopo `releaseMs`). Tornare indietro sulla stessa ringhiera è un
  target diverso. Cooldown gameplay separati in `Config.Cooldowns` (vault 150 ms).
- **Resolver a punteggio** (`Config.Resolver`): a ogni scan fresco con E tenuto vengono valutate tutte le ability
  compatibili (a terra balance, vault, wall climb, wallrun; in aria ledge, tic-tac, wallrun), ognuna con score; parte
  la migliore, a parità (`tieMargin`) vince `priority`. Se la migliore non può partire (cooldown globale, stamina…)
  si prova la successiva. Un ostacolo troppo alto per il vault passa da solo al wall climb → ledge grab.
- **Persistenza** (`Detection.candidatePersistMs`): se un candidato valido non è partito e lo scan dopo fallisce per
  rumore, per 120 ms si riprova lo stesso payload solo se `Verify` conferma con un raycast che la superficie esiste
  ancora (`CANDIDATE_PERSISTED`).
- **Animazioni vault con metadata** (`shared/animations.lua`, `meta`): `lift`, `cross`, `crossDistance`, `touch`,
  `touchDistance`, `duration` sono estratti dagli YCD (traccia mover + root bone); `minHeight/maxHeight/minDepth/
  maxDepth/minSpeed/preferredAngle/minAngle/maxAngle/verticalOffset/forwardOffset` sono le regole di selezione.
  `Vault.Select` valuta tutto `Config.Vault.pool` con uno score (altezza rispetto all'altezza di progetto della clip,
  profondità, velocità entro il range di playback, angolo, distanza d'attacco); un avanzato vince se supera
  `minAdvanced` ed è confrontabile col miglior generico (`advancedBonus`), altrimenti fallback `jump_over_01/03/02`.
  Spazio d'uscita verificato per la distanza reale di atterraggio della clip (`runout_blocked`).
- **Modello di moto del vault**: le clip alzano già il corpo (root bone fino a +0.77 m) mentre il mover è piatto,
  quindi l'entity non viene più sollevata sopra il top: segue terreno → centro ostacolo → atterraggio con una
  correzione `clamp(altezza − altezza di progetto, −maxLower, +maxRaise)`. La clip parte dalla fase che corrisponde
  alla distanza reale dall'ostacolo (`SetEntityAnimCurrentTime`) e alla velocità del player
  (`SetEntityAnimSpeed`, `Vault.rate`), l'apice coincide con la fase `cross` della clip.
- **Ledge**: `ledge_move_l/r` per lo shimmy (velocità allineata alla clip, 1.13 m/s), `ledge_corner_outer_l/r` per
  gli angoli, `ledge_jump_up` / `ledge_jump_up_power` con SPACE (o nuova E) quando il bordo non è scalabile e c'è un
  ledge superiore (fino a 1.5 / 2.6 m), `ledge_jump_l/r` con SPACE + laterale verso un ledge a 1.2–3.6 m.
- **Altre clip**: `swing_jump` → precision lunga, `big_jump_01` → long jump, `front_twist_flip` / `wall_flip` →
  trick, `tictak_l/r_vault` → tic-tac, `diveroll_l/r` → roll, `balance_*` → balance, `wallrun_*_side` → wallrun.
- **Debug pipeline** (colonna centrale): FRONT WALL, OBSTACLE, LANDING, LEDGE, PLAYER (con età dello stato),
  RESOLVER (score o reason per ogni candidato), VAULT CLIPS (score o motivo di scarto per ogni clip), SELECTED,
  ANIMATION (dict/clip, WHY, altezza di progetto, body peak rispetto al top, fase e rate), FINAL REASON (mai vuoto:
  `NO_GEOMETRY`, `INPUT_NOT_HELD`, `ABILITY_ALREADY_ACTIVE` o la reason dello stadio che ha fermato tutto).

## Traversal Space Scanner (Phase 9)

Il sistema non classifica più "basso / medio / alto" ma **come** si attraversa lo spazio davanti.
`client/detection/traversal.lua` costruisce un `TraversalProfile` una volta per scan (`scan.profile`); le ability
leggono il profile e non rifanno gli stessi raycast.

- **Body layers** (`Config.Traversal.layers`): feet, knees, waist, chest, head, overhead lungo la direzione di
  avvicinamento, con hit/distanza/coords/normale/entità/materiale. Lo stesso fan alimenta la detection dell'ostacolo.
- **Categorie**, ognuna con score (`Config.Traversal.scores` × qualità geometrica) o reason di invalidità:
  - `OVER`: contatto con la parte bassa del corpo, top valido, clearance sopra il top, landing, profondità → vault.
    Ostacoli "sospesi" (piedi/ginocchia liberi) hanno penalità (`floatingPenalty`) così un passaggio sotto vince.
  - `THROUGH`: finestra (OVER con architrave, clearance < `TraversalCapsule.standingHeight`) → vault filtrato per
    `clearanceRequired`; apertura a tutta altezza (porta, telaio) → nessuna ability, corsa GTA normale.
  - `UNDER`: parte bassa libera, blocco sopra il busto, poi scansione longitudinale del corridoio (`Traversal.Corridor`):
    terreno continuo, corridoio piedi/ginocchia libero al centro e alle spalle, altezza del passaggio, uscita con
    altezza piena per abbastanza metri → slide sotto.
  - `CLIMB`: muro frontale oltre il vault, ledge raggiungibile e scalabile (landing sopra) → wall climb.
  - `LEDGE`: bordo afferrabile senza landing sopra (a terra wall climb fino all'hang, in aria ledge grab).
  - `WALL`: parete laterale (o frontale in aria) → wallrun / tic-tac.
  - `BALANCE`: superficie stretta (invariato).
- **Selezione**: categoria valida con score più alto; a parità `Config.Traversal.priority`. Se l'ability mappata non può
  partire si prova la categoria successiva. Nessuna ability parte senza `path.entry/cross/exit` validi (eccezione
  LEDGE, la cui uscita è la posizione di hang).
- **Entry / cross / exit**: OVER → davanti all'ostacolo / sopra il top reale / landing; UNDER → inizio corridoio /
  centro passaggio / prima posizione con altezza piena; THROUGH → telaio / dentro l'apertura / oltre.
- **UNDER animazioni**: `slide` (default), `slide_backside` (corpo più basso, passaggi da 0.85 m), `slide_kip_up`
  (bassa velocità, richiede ~6.6 m d'uscita per il recupero). Dagli YCD: finestra a corpo basso 0.17–0.65 / 0.13–0.56 /
  0.12–0.47 della clip; la variante è valida solo se quella finestra copre tutto il passaggio (`passage_too_long`
  altrimenti) e se il corridoio è libero fino a quando il corpo si rialza (`exit_too_short`, `exit_blocked`).
  Lo slide sotto è cinematico lungo il corridoio validato (entity congelata e piazzata, terreno seguito campione per
  campione); la clip parte alla fase che porta il corpo basso all'ingresso del passaggio, velocità dalla corsa.
- **Collision traversal mode** (`Collision.BeginTraversal(ped, mode, durationMs)` / `EndTraversal()`, modi NORMAL,
  OVER, UNDER, THROUGH, LEDGE): il passaggio attraverso il volume avviene solo con l'entity cinematica lungo il path già
  validato (nessun noclip, nessuna collisione disattivata globalmente). Scadenza `durata + CollisionTraversal.graceMs`:
  il watchdog fa `SafeReset` (`COLLISION_TRAVERSAL_TIMEOUT`); `Recovery.SafeReset` chiama sempre `EndTraversal`.
- **Fallback**: OVER valido senza vault avanzato → `jump_over_01/03/02` (la soglia di clearance della categoria è
  quella dei generici, quindi un OVER valido ha sempre almeno un generico compatibile per clearance); UNDER valido →
  almeno `slide`; OVER troppo alto → CLIMB/LEDGE.
- **Debug** (colonna centrale con E tenuto): `TRAVERSAL PROFILE` (score o `invalid reason` per categoria, ability
  scelta), `SELECTED` / `VARIANT` / collision mode, `BODY LAYERS`, blocchi `OVER CANDIDATE`, `UNDER CANDIDATE` (lowest
  obstruction Z, ground Z, passage height/depth, exit clear, varianti con score o motivo, selected animation),
  `THROUGH CANDIDATE` (larghezza/altezza apertura, capsule, entry/cross/exit). In 3D: corridoio basso verde, punti del
  blocco superiore rossi, uscita gialla, larghezza dell'apertura viola.

## Performance (Phase 10)

Nessuna ability nuova e nessun cambio di logica: stesso flusso, meno lavoro inutile.

| Sistema | Frequenza | Native / raycast | Note |
| --- | --- | --- | --- |
| loop principale (`client/main.lua`) | E non premuto: `idleTick` da fermo, `moveTick` in movimento; per-frame solo con E tenuto, in aria, con ability attiva o input bufferizzato | context | prima girava per-frame appena il player si muoveva (anche in veicolo); quando il parkour è bloccato (veicolo, morte, nuoto...) resta a `idleTick`. Il sonno è a fette (`wakeSlice`): la pressione di E sveglia il loop subito |
| context (`client/core/context.lua`) | ogni tick | movimento per-frame (coords, velocity, heading, input, salto/caduta, ragdoll, morte); stato "lento" (piedi, veicolo, nuoto, scala, paracadute, arma) ogni `statusInterval` o su evento | `forward` dal heading (niente `GetEntityForwardVector`), camera letta solo se serve, veicolo/arma da `cache.vehicle` / `cache.weapon` di ox_lib, tabella input riusata |
| scanner (`client/core/scanner.lua`) | solo E tenuto / ability aerea, intervalli `Config.Scan` | a stadi | 1) fan dei body layer + terreno; 2) solo se un layer colpisce: classificazione ostacolo; 3) top / profondità / landing solo con contatto della parte bassa del corpo; 4) corridoio UNDER solo con blocco sopra e spazio sotto, ledge solo con muro frontale valido; 5) scoring ability lazy |
| muro frontale / faccia del ledge in aria | — | 0 raycast | ricavati dal fan già fatto (stessa origine, stessa direzione, altezze incluse, distanza minore) |
| muri laterali | velocità ≥ `sideScanSpeed` o in aria | fan con early-out | si ferma appena non può più raggiungere `Wall.minHits` (2 raggi in campo aperto invece di 3 per lato); risultato identico |
| THROUGH aperto e clearance laterale | solo con debug attivo | — | sono informativi (nessuna ability parte da un'apertura libera): senza debug il candidato THROUGH aperto risulta `THROUGH_NO_FRAME (lazy)`; la finestra (THROUGH vault) è sempre calcolata |
| cache raycast | per tick + generazioni brevi | — | stesso raggio nello stesso tick → risultato in memoria; tra tick (solo a terra, senza ability, `Config.Cache.geometryTTL`) restano solo i risultati statici (miss o mondo senza entity); svuotata a ogni cambio di stato ability, teleport, rilascio di E |
| cache geometria ostacolo | `geometryTTL` | 2 raggi invece di ~25 | stessa faccia (posizione, normale, direzione entro `Config.Cache`), stesso terreno, nessuna entity: riusa top / profondità / landing / path, ricalcola distanza, angolo, altezza, head clearance |
| resolver | per scan | — | categorie ordinate per score, ability valutate in ordine e solo fino alla prima che può partire (con debug attivo le valuta tutte per il pannello); array e voci riusati |
| ability attiva | per-frame | quelli dell'ability | un solo loop: `Lifecycle.Update` (ability manager) aggiorna solo l'ability attiva; nessun thread per ability |
| animazioni | evento | — | dict già caricati in cache, caricamento a stati con timeout (`loadTimeout`), progress letto una volta per tick |
| camera | solo con effetto attivo | — | thread creato al primo effetto, termina quando gli effetti sono assestati |
| collisione traversal | nessun loop | — | stato + scadenza controllata dal watchdog |
| watchdog | `watchdogInterval` | — | timeout stati, scadenza traversal, risorse orfane |
| cooldown / ripetizioni | timestamp | — | nessun thread; distanze al quadrato |
| stamina | solo inizio ability e drain dell'ability attiva | 0 se `Config.Stamina.enabled = false` | |
| debug | solo `Config.Debug` / `/parkourdebug` | — | testo ricostruito ogni `textRefreshMs` e disegnato ogni frame; raggi e reason non registrati con debug spento |
| server / eventi / exports | evento | — | invariati: eventi solo su start/end/cancel e cambi di stato non-locomotion, exports leggono stato già pronto |

- **Hold**: `lib.addKeybind` (`+parkour`, stesso comando e tasto di prima, quindi i binding salvati restano validi) con
  `onPressed` / `onReleased`; il menu pausa rilascia il tasto (ox_lib ignora il rilascio in pausa), lo stop della risorsa lo
  azzera. CTRL e SPACE restano controlli GTA letti nel loop; il tasto trick è un secondo keybind (`+parkourtrick`, default X, `Config.Tricks.modifier`). "E" indica il tasto parkour, qualunque sia il binding.
- **Preset** `Config.Performance.mode = 'quality' | 'balanced' | 'performance'`: cambiano solo intervalli (idle, movimento,
  scan, stato, watchdog, testo debug), persistenza candidati e TTL della cache geometria.
- **Profiler** `Config.Profiler.enabled` / `/parkourperf`: Context, Scanner (body / top / under / through), Resolver, Ability,
  `Raycasts/frame` (`Profiler.raycastsThisFrame`), `Raycasts/sec` (`Profiler.raycastsPerSecond`), held, traversal, ability,
  tick corrente. Spento non misura e non conta nulla.
- **Non fatto, di proposito**: shape test asincroni e capsule (`StartShapeTestLosProbe` / `StartShapeTestCapsule` danno il
  risultato in un frame successivo: ogni decisione arriverebbe in ritardo; il costo del test fisico è lo stesso), distanza
  di scan ridotta con la velocità (il fan è 1.5 m e il vault parte fino a 1.45 m: accorciarlo taglierebbe vault validi),
  scan solo del lato muro "probabile" (in un corridoio cambierebbe il muro scelto).

## Integrazione

Export client:

```lua
exports['cr-parkour']:IsParkouring()
exports['cr-parkour']:GetParkourState()
exports['cr-parkour']:GetCurrentAbility()
exports['cr-parkour']:SetParkourEnabled(false)
exports['cr-parkour']:IsParkourEnabled()
exports['cr-parkour']:CanParkour()          -- ok, reason
exports['cr-parkour']:CancelParkour(force)  -- false se l'animazione non è cancelable e force non è true
exports['cr-parkour']:SetLandingDamageHandler(function(data) return true end)  -- true = sostituisce il default
exports['cr-parkour']:SetDamageHandler('collision', function(data) end)
```

Eventi locali (client), payload minimo, nessun evento per frame:

- `cr-parkour:abilityStarted` `{ ability, state }`
- `cr-parkour:abilityEnded` `{ ability, state, next, reason }`
- `cr-parkour:abilityCancelled` `{ ability, state, reason }`
- `cr-parkour:stateChanged` `{ state, previous }` (non emesso per locomotion → locomotion)
- `cr-parkour:damage` `(kind, data)` e `cr-parkour:fallImpact` `(distance, rolled)`

Server: solo `cr-parkour:fallImpact` (rate limited) e il callback del manifest animazioni.

## Tuning in gioco (Phase 6)

`Config.TuningMode = true` → `/parkourdebug` apre un menu ox_lib con flag di debug, reload del registry animazioni,
reset/recovery, snapshot e modifica runtime dei parametri principali e degli offset per animazione
(`Config.Ledge.Offsets`, `Config.Wallrun.Offsets`, `Config.AnimationOffsets`). `/parkoursnapshot` copia lo stato
corrente negli appunti. Log delle modifiche e risultati in [TUNING.md](../TUNING.md).

## Test in FiveM

Protocollo completo in [TESTING.md](../TESTING.md).
