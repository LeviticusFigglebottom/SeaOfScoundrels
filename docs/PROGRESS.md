# Progress

Re-read this, ROADMAP.md, DECISIONS.md, ARCHITECTURE.md and the "Quality bar" in DESIGN.md when resuming.

## Current state (2026-11-26)
- Engine: Godot 4.8 beta 5 (`4.8-beta5`, owner request). Tooling: `tools/setup_env.sh`, `tools/test.sh`, `tools/test_net.sh`, `tools/test_gpu.sh`, `tools/lint.py` (Linux/macOS/Windows LSP URI clean), `tools/capture.sh`, `tools/build_assets.sh`.
- **All M0–M4 systems + Wave 4 depth & performance upgrades merged and verified on `ccr-663b66a0-rdiq4f`:**
  - Foundations, ENet host-authoritative co-op with late-join & reconnect (`Net`), `Profile` & `UserSettings` (`settings.json` with quality presets, accessibility & live key rebinding).
  - Sky & Weather pass 2 (`SkyRig`, silky IGN-jittered bisected volumetric SDF clouds, cross-warped dome cirrus, storm cells as places, lightning/thunder, cloud shadows, clean `_exit_tree()` teardown).
  - Ocean pass 2 (`Sea` 16-wave Gerstner set, `Ocean`, `FoamField`, `CrestSpray` with lagoon guard, `Underwater` with smooth shafts, hull water cutout).
  - Ships: Sloop (`sloop.tscn`) + two-masted Brigantine (`brigantine.tscn`, 4 cannons, 10 breach slots, live Outpost Shipwright class-swapping). Static sub-mesh material batching in `gen_sloop.py` & `gen_brigantine.py` cut active visual primitives/pass by **-51.8% on Sloop (`112 -> 54`)** and **-44.6% on Brigantine (`148 -> 82`)** (~290–330 fewer DC/frame per ship across shadow cascades) with zero geometry drift. `Cannonball` features swept raycasts, `Trail3D` tracer, tall foam water-geyser splash plumes, and fiery hull splinter bursts; cursed Drowned/Ghost/Corsair hull liveries & twin outboard feathered bow spray.
  - Characters & Animation: `Pawn` (rolling-deck riding with wave-heave snap), `CharacterVisual` (11 archetypes), `AnimationDriver` (analytical 2-bone grounded crouch leg flexion).
  - AI Crew (`CrewBrain`, `CrewDialogue`): 3 distinct crewmates (Barnaby, Maren, Pip), 9-wedge command wheel, combat-prioritized lookout callouts, automatic co-op slot yielding.
  - Combat, Beasts & Bosses: `CombatComponent` (cutlass, boarding axe, pistol, blunderbuss, parry/heavy sparks, beast hit support), `EnemyBrain` (Drowned variants, Tidecallers, Corsairs & rival captains), `AIShipBrain`, `Shark` (hitbox, jaw, circling dorsal wake), Living World Beasts (`SeabirdFlock` gulls marking harbours/flotsam/wrecks/dig sites, `IslandCrab` coral guardians dropping crab claws, `ReefEel` coastal ambushers), and flagship **Abyssal Leviathan** (`leviathan.gd`: 7-segment sculpted bioluminescent sucker-lined tentacles, rising `AbyssalCrown` with glowing amber-aqua eyes, wave-conformal `InkPool` shader with hull cutout, boiling foam vortex & spray eruptions).
  - Islands & Archipelago: 11 sculpted islands (distance-gated lights/foliage), 17 procedural Blender props (sunlit limestone sea stacks, cedar-shake tavern, lush palms), animated **Outpost Harbour NPCs** (Merchant Factor & Pier Quartermaster), harbour auto-restock, `DigSite` with golden unearth shimmer, `MerchantStall` with celebratory gold coin burst.
  - Held Tools, Armory, Map Table & UI: 13 procedural 3D PBR tools/weapons (11 radial tools + `Boarding Axe` & `Blunderbuss` switchable live in Shipwright Armory), `Inventory`, off-screen-throttled live SubViewport `MapTableView` (Sloop & Brigantine), `GameHUD` + diegetic Boss Encounter Bar + `RadialWheel` + 3-tab `ShipwrightMenu`, original 106-glyph ink-kerned procedural BMFont (`scoundrel_font.fnt`, D11 resolved).
  - Voyages, Economy, Audio & Downtime: 3 trading companies, balanced sidegrades, 3-chapter story voyage chain + 8+ procedural voyage shapes, `WorldDirector` living-sea events + ~60% salvage wreck restore, `FishingLine`, diegetic sizzling `CookingStove` (raw/seared/burnt fish & crab + steam), full synthesized audio + shanties + dedicated Milestone 3 music tracks (`sail_day`, `sail_night`, `storm`, `stinger_discovery`).
  - Integrated zero-placeholder `scenes/main.tscn` vertical slice (including `shot=leviathan` & `shot=fleet` 4-ship benchmark) & multi-platform CI (Linux, Windows Desktop, macOS exports passing green on GitHub Actions).

## Satellite session coordination (`origin/local/gpu-polish`)
- Active Windows real-GPU partner (AMD Radeon RX 9070 XT, i9-12900K, Godot `4.8-beta5`) pushing reports & polish to `origin/local/gpu-polish` (`docs/status/local_gpu.md`).
- **Integrated into `ccr-663b66a0-rdiq4f` from `local/gpu-polish`:**
  - Milestone 1 (`532e053`): `tools/lint.py` Windows LSP fix + baseline 1080p RX 9070 XT Vulkan profiling (`1.32–1.57 ms` GPU sailing, 51/51 clean Vulkan exits).
  - Milestone 2 (`6d8318d` -> `3952bcc`): silky IGN cloud bisection & dome cirrus (`+0.029 ms` GPU), `island.gd` + `map_table_view.gd` CPU p95 throttling (`6.18–7.21 ms` -> `5.84–6.73 ms`), ink-kerned 106-glyph `scoundrel_font.fnt`, showcase polish.
  - Milestone 3 (`618e06b`/`732e134` -> `af0b18b`): dedicated `sail_day`, `sail_night`, `storm`, and `stinger_discovery` procedural music tracks (`test_audio` 9/9 PASS).
- **High-value Milestone 4 asks for `local/gpu-polish` (after `git fetch origin` & rebase onto latest `origin/ccr-663b66a0-rdiq4f`):**
  1. **Re-profile Ship Draw-Call Reduction** on RX 9070 XT: measure before/after DC & CPU/GPU frame time for batched Sloop (`-51.8%`) and Brigantine (`-44.6%`).
  2. **4-Ship Multi-Faction Fleet Stress Benchmark**: profile & capture `scenes/main.tscn -- shot=fleet ship=brigantine quality=high` (Player Brigantine + Drowned Sloop + Ghost Ship + Corsair Sloop + cannonball water-geysers & splinters).
  3. **Abyssal Leviathan & Living World Visual Audit at 1080p**: capture & visually review `scenes/main.tscn -- shot=leviathan ship=brigantine quality=high` (sculpted tentacles, `AbyssalCrown`, `InkPool` hull cutout, Boss HUD), `shot=outpost_dock` (Harbour NPCs + circling gulls), and Armory weapons (`Boarding Axe` / `Blunderbuss`).
  4. **Multi-Platform Export Smoke Test**: export & boot-verify the Windows Desktop `.exe` on real Vulkan hardware + run `test_gpu` + `test_net`, updating `docs/status/local_gpu.md` with final Milestone 4 numbers and any visual/perf flags for Cloud Lead!

## Known issues / open polish
- Human listening pass on the synthesized audio mix (technical analysis passes with 0 flagged across all tracks including new `sail_day`/`sail_night`/`storm`/`discovery`).
- Awaiting Milestone 4 real-GPU draw-call verification of batched ships, 4-ship fleet stress benchmark, Abyssal Leviathan visual audit, and Windows `.exe` boot smoke test from `local/gpu-polish`.
