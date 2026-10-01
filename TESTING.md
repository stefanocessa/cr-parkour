# cr-parkour — protocollo di test in FiveM

Preparazione: `Config.TuningMode = true`, `restart cr-parkour`, `/parkourdebug` apre il menu. Tieni attivi
`state` e `animations`; accendi `rays` quando serve vedere la geometria, `performance` solo nel blocco 20.

Per ogni caso fallito: `/parkoursnapshot`, poi una riga nella tabella "Risultati in gioco" di `TUNING.md` con
priorità (P0–P3). Correggi prima P0/P1. Un caso negato è corretto solo se il player resta libero e nessuna parte
del ped entra nella geometria.

## 1. Input resolver (hold mode)
- [ ] `PARKOUR HELD: false` con E rilasciato: correndo contro muretti/muri non parte nulla, SPACE salta, CTRL accovaccia
- [ ] `PARKOUR HELD: true` finché E è tenuto, torna `false` al rilascio (anche aprendo il menu pausa)
- [ ] E tenuto + corsa verso muretto → vault senza ripremere E; più ostacoli in fila → un vault per ostacolo
- [ ] E tenuto davanti allo stesso ostacolo subito dopo il vault → nessun retrigger (`SAME_OBSTACLE_BLOCKED`)
- [ ] **stesso ostacolo ×3**: vault → allontanati ≥ 1 m → vault → allontanati → vault: tre successi su tre
- [ ] ringhiera sottile avanti e indietro senza pause → ogni passaggio riesce (lato opposto = target diverso)
- [ ] E tenuto + sprint lungo un muro laterale → wallrun; vault → corsa → wallrun → ledge se la geometria cambia
- [ ] durante wallrun con E tenuto: SPACE → walljump; rilascia e ripremi E → walljump
- [ ] appeso: SPACE con E tenuto o nuova pressione di E → climb; CTRL → drop anche senza E
- [ ] E + SPACE in sprint su terreno libero → long jump; vicino a un gap con target → precision; E + SPACE da fermo senza target → salto GTA
- [ ] E + X → wall flip / trick; X senza E → nulla
- [ ] corsa verso un muro alto (> 1.9 m) con E + X tenuti → wall flip, nessun wall climb; rilasciato X (solo E) → wall climb
- [ ] riga `E -> … CTRL -> … SPACE -> …` coerente con quello che hai davanti, riga `candidate` coerente

## 2. Slide
- [ ] sprint + CTRL **senza E** → crouch/stealth GTA, nessuna slide
- [ ] E tenuto + sprint + CTRL → slide diretta, senza entrare in stealth GTA (se entra in stealth: P1, snapshot)
- [ ] E tenuto + corsa sotto `Slide.minSpeed` + CTRL → stealth GTA (atteso)
- [ ] E tenuto + slide negata (salita/ostacolo) → nessuna animazione, nessuna doppia animazione
- [ ] piano, salita (`SLIDE_DENIED_SLOPE` se ripida), discesa (accelera poco)
- [ ] muro davanti → `SLIDE_DENIED_FRONT_BLOCKED` o `SLIDE_END_BLOCKED`, stop senza compenetrazione
- [ ] sotto ostacolo basso → passa sotto, non si alza dentro
- [ ] tarare: `Slide.minSpeed`, `Slide.deceleration`

## 3. Vault base
- [ ] debug rays: rosso front face sul bordo reale, blu sul top, giallo sulla landing, verde path, viola target
- [ ] muretto ~60 cm e ostacolo ~110 cm: `VAULT CTX` → `animation target Z` diverso, `top +` uguale (= `rootClearance` + correzioni)
- [ ] se il ped passa alto con il viola corretto → tarare `Vault.Offsets['vault.*'].verticalOffset` (negativo) o `rootClearance`; se il blu non è sul top → detection, snapshot
- [ ] ringhiera sottile vs blocco largo: `depth` diversa, stile diverso (speed/safety vs kong/slide)
- [ ] gradino < 50 cm → `OBSTACLE_TOO_LOW`, GTA lo sale normalmente
- [ ] colonna centrale: con E tenuto davanti a un muro `FINAL REASON` è sempre valorizzato; nessun caso "ray visibili ma nessun motivo"
- [ ] muro alto (1.4–3 m) da fermo con W verso il muro → wall climb → ledge; se no, FINAL REASON indica lo stadio (es. `WALLCLIMB_DENIED_NO_LEDGE (LEDGE_DENIED_TOO_HIGH)` dopo `vault OBSTACLE_TALL`)
- [ ] muretto 0.6 m: `jumpOver1/3`; 1.1 m profondo 0.9 in sprint: `monkey`/`kash`; diagonale 30°+: `reverse`; tavolo/cofano profondo: `roll`/`slide`
- [ ] durante il vault: ped che non passa troppo alto → `body peak (top +x)` tra ~0.3 e ~0.5; se il corpo passa alto/basso tarare `Vault.liftClearance` (unico valore globale) o `meta.verticalOffset` della clip
- [ ] appeso sotto un balcone/finestra: SPACE → `ledge_jump_up` (o `_power` se il bordo superiore è più alto); SPACE + A/D → `ledge_jump_l/r`
- [ ] secondo oggetto subito dopo → `VAULT_DENIED_LANDING_BLOCKED (second_object)` o `EXIT_BLOCKED`; top inclinato/irregolare → `VAULT_DENIED_INVALID_TOP`
- [ ] low / medium: limite minimo, limite massimo, troppo alto, profondo, sottile, diagonale, vicino ad altro oggetto
- [ ] landing libera / bloccata (`VAULT_DENIED_LANDING_BLOCKED`, `VAULT_DENIED_EXIT_BLOCKED`), soffitto basso, ringhiera (`VAULT_DENIED_AMBIGUOUS`)
- [ ] controllare: gambe nell'ostacolo, ped sopra/sotto il top, heading, momentum in uscita, uscita FALLING se oltre c'è un salto
- [ ] tarare: `Vault.maxDistance`, soglie `low/medium`, `Config.AnimationOffsets['vault.*']`

## 3c. Traversal Space Scanner (Phase 9)
Per ognuno: E tenuto + corsa, guardare `TRAVERSAL PROFILE` / `SELECTED` / `VARIANT`, poi ripetere 3 volte tornando indietro.
- [ ] muretto molto basso (< 0.5) → OVER invalid `OBSTACLE_TOO_LOW`, GTA lo sale
- [ ] muretto medio → OVER → vault (jump_over / safety / monkey secondo profondità e velocità)
- [ ] muretto alto (1.2–1.35) → OVER; oltre → CLIMB
- [ ] ringhiera (barra con spazio sotto) → OVER con penalità `floating`; se lo spazio sotto è ≥ 0.85 m confrontare UNDER
- [ ] tubo basso / trave / barriera a 1.0–1.3 m con spazio sotto → UNDER → slide → uscita in piedi
- [ ] struttura sotto cui scivolare lunga (rimorchio, scaffalatura) → UNDER se ≤ ~3.3 m, altrimenti `passage_too_long`
- [ ] passaggio troppo basso (< 0.85) → UNDER `UNDER_PASSAGE_TOO_LOW`
- [ ] sotto con muro all'uscita → `UNDER_EXIT_BLOCKED` / `exit_blocked`, nessuno slide
- [ ] finestra (davanzale + architrave) → THROUGH (window) → vault che passa nell'apertura
- [ ] apertura stretta (< 0.6) → THROUGH `THROUGH_TOO_NARROW`; porta normale → THROUGH 0.20 senza ability (corsa GTA)
- [ ] muro alto 2–3 m → CLIMB → wall climb → ledge → climb; muro 6 m → `WALLCLIMB_DENIED_NO_LEDGE (LEDGE_DENIED_TOO_HIGH)`
- [ ] ledge senza spazio sopra (balcone con muro) → LEDGE → wall climb fino all'hang
- [ ] parete laterale → WALL → wallrun; in aria contro parete angolata → tic-tac
- [ ] ostacolo spesso (> 0.8) → roll/slide vault; sottile → jump_over
- [ ] ostacolo seguito subito da un altro → `VAULT_DENIED_EXIT_BLOCKED`
- [ ] UNDER → successo → torno indietro → UNDER → successo; OVER idem
- [ ] durante uno slide sotto: `collision mode: UNDER`, torna `NORMAL` all'uscita; se il ped resta bloccato → snapshot (P0)

## 3b. Stamina
- [ ] `Config.Stamina.enabled = false`: riga `stamina off`, nessuna ability negata, la stamina GTA non scende per il parkour
- [ ] `enabled = true`: E tenuto senza ability → stamina invariata; vault/slide/longjump → calo singolo; wallrun → calo continuo
- [ ] stamina esaurita (sprint lungo) → `VAULT_DENIED_LOW_STAMINA` / `WALLRUN_DENIED_LOW_STAMINA`, nessuno stato parziale
- [ ] stamina che finisce durante il wallrun → `PARKOUR_END_LOW_STAMINA`, caduta pulita

## 4. Wallrun
- [ ] muro dritto, corto, molto lungo, inclinato, curvo, con finestre, con props, che termina, angolo esterno, angolo interno
- [ ] il ped non entra nel muro, non si allontana, non sale senza motivo, non cade troppo in fretta, non resta attaccato
- [ ] camera: roll leggero verso il muro, FOV che torna morbido
- [ ] tarare: `Wallrun.wallDistance`, `minSpeed`, `gravityScale`, `maxDuration`

## 5. Wallrun sinistro / destro
- [ ] provare i due lati separatamente con lo stesso muro
- [ ] tarare `Wallrun.Offsets.left` e `Wallrun.Offsets.right` indipendentemente (heading, wallOffset, up)

## 6. Walljump
- [ ] da wallrun sinistro, da wallrun destro, verso spazio libero, verso un muro, sotto soffitto, walljump + ledge
- [ ] la direzione segue la normale del muro (snapshot: `wall normal` contro `velocity`)

## 7. Ledge grab
- [ ] basso, medio, alto; salto frontale, caduta dall'alto, long jump → ledge, wallrun → ledge, precision → ledge
- [ ] da salto GTA serve E (nessun grab automatico)
- [ ] controllare: timing, posizione hang, heading, mani sul bordo, distanza corpo-muro

## 8. Ledge idle custom
- [ ] pannello: `ledge.idle CUSTOM parkour_part_2@anim/ledge_idle`; `FALLBACK` in rosso = bug P2
- [ ] grab: `ledge.grab` risolve all'idle custom (alias), quindi deve risultare `CUSTOM`
- [ ] tarare `Config.Ledge.Offsets.idle` (con allineamento mani spento per up/forward), oppure `handAlign.heightOffset/wallDistance`

## 9. Shimmy
- [ ] bordo lungo, corto, fine ledge (si ferma o cerca il corner), ostacolo laterale (corner interno), superficie irregolare
- [ ] `moveLeft` / `moveRight` entrambi `CUSTOM`; tarare `Offsets.moveLeft/moveRight` separatamente
- [ ] corner sinistro e destro, 90°, poco diverso da 90°, angolo non valido (`SHIMMY_DENIED_CORNER`)
- [ ] la rotazione segue la transizione, nessuno scatto istantaneo

## 10. Climb-up
- [ ] spazio libero sopra, muretto basso/alto sulla landing, soffitto (`CLIMB_DENIED_HEAD_BLOCKED`), oggetto sulla landing (`CLIMB_DENIED_LANDING_BLOCKED`)
- [ ] negato → resta appeso, nessun movimento nella geometria
- [ ] `ledge.climb` risulta `NATIVE` (nessuna clip climb nel pack: atteso, non è un bug)

## 11. Roll
- [ ] caduta piccola (nessun roll), media, grande, enorme (> 9 m: roll con danno ridotto), oltre 14 m (nessun roll)
- [ ] troppo presto, corretto, troppo tardi (finestra tardiva), spazio davanti bloccato (`ROLL_DENIED_FRONT_BLOCKED`)
- [ ] tarare `Roll.windowMs`, `Roll.minFall` finché la finestra è percepibile ma non permissiva

## 12. Vault avanzati
- [ ] speed, safety, kong, reverse, slide: per ognuno leggere `vault candidates` e `selected`
- [ ] se vince lo stile sbagliato: annotare `h d v a drop` dello snapshot e il vincolo fallito
- [ ] stesse geometrie del blocco 3

## 13. Tic-tac
- [ ] muro a sinistra / destra, approccio lento (`TICTAC_DENIED_LOW_SPEED`), veloce, angolo cattivo / buono, uscita libera / bloccata (`TICTAC_DENIED_NO_SPACE`)
- [ ] il momentum viene riflesso sulla normale, non con una direzione fissa

## 14. Wallflip
- [ ] muro frontale alto, spazio dietro libero / muro dietro (`WALLFLIP_DENIED_BACK_BLOCKED`), soffitto, spazio ridotto
- [ ] mai eseguito senza clearance

## 15. Precision jump
- [ ] short, medium, al limite, oltre limite (`PRECISION_DENIED_TOO_FAR`)
- [ ] landing più alta, uguale, più bassa
- [ ] leggere `dist dh req avail` nel pannello

## 16. Long jump
- [ ] deve sembrare umano: controllare entry speed, air time e landing nello snapshot
- [ ] tarare `LongJump.forwardMultiplier`, `verticalBoost`, `maxHorizontalSpeed`

## 17. Air tricks
- [ ] front twist (X+E senza direzione) da altezza sufficiente
- [ ] frontflip / backflip / side → `TRICK_DENIED_NO_ANIMATION` (nessuna clip: atteso)
- [ ] vicino al suolo → `TRICK_DENIED_LOW_CLEARANCE`; mai senza X+E

## 18. Balance
- [ ] muretto stretto + E → balance; ringhiera larga, superficie normale, bordo, tetto stretto
- [ ] mai BALANCING su superfici normali; leggere `width left right` nel pannello

## 19. Combo
- [ ] sprint → vault → wallrun → walljump
- [ ] wallrun → ledge grab → shimmy → climb
- [ ] long jump → ledge grab
- [ ] vault → precision → roll
- [ ] tic-tac → wallrun → walljump

## 20. Recovery
- [ ] durante ogni ability: collisione, ragdoll, morte, `restart cr-parkour`, teleport, entrata in veicolo
- [ ] dal menu: "Reset parkour state" e "Force recovery" durante wallrun / ledge / climb
- [ ] dopo ogni recovery: niente freeze, camera normale, SPACE/CTRL/E funzionano

## 21. Performance (Phase 10)
`/parkourperf` attivo, `resmon 1` aperto. Annotare in `TUNING.md` (Performance rilevate): resmon ms, raycast/s, scanner ms, tick.
- [ ] A. fermo senza E → `tick` = `idleTick`, Raycasts/sec 0, resmon quasi nullo
- [ ] B. corsa senza E → `tick` = `moveTick`, Raycasts/sec 0
- [ ] C. E tenuto in campo aperto → tick 0, pochi raggi per scan (fan + terreno + lati)
- [ ] D. E tenuto davanti a un muro → top detection compare, poi `cache` sale e i raggi per scan scendono mentre ci si avvicina
- [ ] E. E tenuto in zona complessa (scale, ringhiere, veicoli) → nessun picco persistente
- [ ] F. vault / G. wallrun / H. ledge / I. UNDER / J. combo lunga → Ability ms solo durante l'ability, poi torna a zero
- [ ] in veicolo con o senza E → tick = `idleTick`, nessun teleport/recovery spurio
- [ ] premere E da fermi → lo scan parte senza ritardo percepibile (sveglia del loop)
- [ ] `Config.Performance.mode` = `quality` / `performance` → stessi risultati di gameplay, intervalli diversi

## 22. Regressione dopo l'ottimizzazione
- [ ] stesso ostacolo ripetuto (OVER e UNDER), vault basso, medio, avanzato, under slide, through (finestra)
- [ ] wall climb, wallrun (anche in corridoio a due muri), ledge, shimmy, long jump (E + SPACE), slide (E + CTRL), roll
- [ ] stamina `enabled = true` e `false`
- [ ] hold: premi/rilascia E, menu pausa con E premuto, morte con E premuto, entrata in veicolo con E premuto, `restart cr-parkour` con E premuto
- [ ] caduta senza E da 3+ m: danno/ragdoll come prima (l'apice parte dall'ultima quota a terra anche se il loop dormiva)
- [ ] debug on: pannelli identici a prima, testo aggiornato ~6 volte al secondo, raggi ogni frame
- [ ] wall flip a terra: la clip va fino in fondo (corsa al muro, calcio, flip, atterraggio in piedi), il piede tocca il muro senza entrarci (`Config.WallFlip.wallGap`)
- [ ] wall flip automatico: con solo il tasto parkour, corsa verso un muro più alto di `Wallclimb.maxHeight` (4.4 m) senza ledge raggiungibile → wall flip (`Config.WallFlip.autoWhenTooHigh`)
