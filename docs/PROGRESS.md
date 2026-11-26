# Progress

Re-read this, ROADMAP.md, DECISIONS.md, ARCHITECTURE.md and the "Quality bar" in DESIGN.md when resuming.

## Current state (2026-11-26)
- Engine: Godot 4.8 beta 5 (`4.8-beta5`, owner request). Tooling: `tools/setup_env.sh`, `tools/test.sh`, `tools/test_net.sh`, `tools/test_gpu.sh`, `tools/lint.py` (Linux/macOS/Windows LSP URI clean), `tools/capture.sh`, `tools/build_assets.sh`.
- **All M0–M4 systems merged and verified on `ccr-663b66a0-rdiq4f`:**
  - Foundations, ENet host-authoritative co-op with late-join & reconnect (`Net`), `Profile` & `UserSettings` (`settings.json` with quality presets, accessibility & live key rebinding).
  - Sky & Weather pass 2 (`SkyRig`, volumetric SDF clouds, storm cells as places, lightning/thunder, cloud shadows, clean `_exit_tree()` teardown).
  - Ocean pass 2 (`Sea` 16-wave Gerstner set, `Ocean`, `FoamField`, `CrestSpray` with lagoon guard, `Underwater` with smooth IGN shafts, hull water cutout).
  - Ships: Sloop (`sloop.tscn`) + two-masted Brigantine (`brigantine.tscn`, `gen_brigantine.py`, 4 cannons, 10 breach slots, live Outpost Shipwright class-swapping), `Cannonball` (`Trail3D` + non-allocating swept rays), twin outboard feathered bow spray, cursed Drowned/Ghost/Corsair hull liveries.
  - Characters & Animation: `Pawn` (rolling-deck riding with wave-heave snap), `CharacterVisual` (11 archetypes across pirates, Drowned, Tidecallers, Corsairs), `AnimationDriver` (analytical 2-bone grounded crouch leg flexion).
  - AI Crew (`CrewBrain`, `CrewDialogue`): 3 distinct crewmates (Barnaby, Maren, Pip), 9-wedge command wheel, combat-prioritized lookout callouts, automatic co-op slot yielding.
  - Combat & Threats: `CombatComponent` (cutlass, boarding axe, pistol, blunderbuss, parry/stagger/dodge), `EnemyBrain` (Drowned variants, Tidecallers, Corsairs & rival captains), `AIShipBrain`, `Shark`, `Leviathan` multi-tentacle boss.
  - Islands & Archipelago: 11 sculpted islands (`Port Scoundrel` home outpost, 2 outlying outposts, `Cutlass Cay`, forts/spires/arches), 17 procedural Blender props (unified sunlit limestone sea stacks, cedar-shake tavern, lush palms), `DigSite`, `MerchantStall`.
  - Held Tools, Map Table & UI: 11 procedural 3D tools (`ToolMeshes` outward-normal audited), `Inventory`, live SubViewport `MapTableView` (Sloop & Brigantine), `GameHUD` + `RadialWheel` + 3-tab `ShipwrightMenu`, original 105-glyph procedural BMFont (`scoundrel_font.fnt`, D11 resolved).
  - Voyages, Economy & Downtime: 3 trading companies, balanced sidegrades, 3-chapter story voyage chain + 8+ procedural voyage shapes, `WorldDirector` living-sea events + ~60% salvage wreck restore, `FishingLine`, `CookingStove`, full synthesized audio + shanties.
  - Integrated zero-placeholder `scenes/main.tscn` vertical slice & multi-platform CI (Linux, Windows Desktop, macOS exports passing green on GitHub Actions).
- **Verification baseline:** `tools/lint.py` 0 errors/0 warnings across all scripts; `tools/test.sh` **108/108 tests pass**; `tools/test_gpu.sh` **3/3 pass**; `tools/test_net.sh` **PASS**; two full independent Flagship Visual Reviews (Round 1 & Round 2) completed with all MUST-FIX defects resolved and visually verified.

## Satellite session coordination (`origin/local/gpu-polish`)
- Active Windows real-GPU partner (AMD Radeon RX 9070 XT, i9-12900K, Godot `4.8-beta5`) pushing reports & polish to `origin/local/gpu-polish` (`docs/status/local_gpu.md`).
- **Real-GPU D9/D10 profiling achieved (1920x1080 Forward+, MSAA 2x, VSync off):**
  - `scenes/main.tscn` (`sailing` after Milestone 2 cloud & CPU p95 polish): `1.36 ms` GPU MED (`+0.029 ms` for silky raymarched clouds & dome cirrus), CPU p95 frame time dropped from `6.18–7.21 ms` to **`5.84 ms` (MED) / `6.73 ms` (HIGH)** (~`6.6 ms` est. GTX 1660 class — well under the `16.6 ms` / 60 fps D10 budget).
  - 51/51 real-Vulkan captures exited cleanly (`exit=0`, zero `__futex_wait` deadlocks).
  - Audio analysis: 155 files, `0 flagged`, 100% of musical notes in tune.
- **Integrated into `ccr-663b66a0-rdiq4f` from `local/gpu-polish` Milestone 1 (`532e053`) + Milestone 2 (`6d8318d`):**
  - `tools/lint.py` Windows LSP URI fix; `src/sky/sky_body.gdshaderinc` IGN cloud raymarch smoothing & dome cirrus; `src/world/island.gd` + `src/items/map_table_view.gd` distance/visibility CPU p95 throttling; `tools/textures/gen_font.py` + `scoundrel_font.{png,fnt}` (106 glyphs + ink-measured proportional kerning); `scenes/showcase/{combat,charart}_showcase.gd` framing & glare polish.
  - All Cloud-Lead Round 2 fixes (Ocean, Ship/Brigantine VFX & rigging, Islands/Props, ToolMeshes/HUD/Radial, Characters/AnimationDriver, `scenes/main.gd`) are already merged on `ccr-663b66a0-rdiq4f`.
- **Next non-overlapping handoff for `local/gpu-polish`:**
  1. `git fetch origin` and reset/rebase `local/gpu-polish` onto latest `origin/ccr-663b66a0-rdiq4f` (keeping `docs/status/local_gpu.md`) so Milestone 3 starts cleanly from our unified flagship baseline with zero conflicts!
  2. Execute **Milestone 3**: synthesize the 4 dedicated original procedural music cues in `tools/audio/gen_music.py` (`sail_day`, `sail_night`, `storm`, `discovery` stinger) + verify `analyze.py --strict`, `analyze.py --music`, and `test_audio.gd`.
  3. Execute **Milestone 4**: final 1080p RX 9070 XT visual & performance verification of the unified baseline (including polished Ocean/Brigantine/Drowned combat/Cutlass Cay/Sky/UI) + Windows `.exe` export real-GPU boot smoke test + `test_gpu` + `test_net`.

## Known issues / open polish
- Ship draw calls (~358 DC per Sloop, ~480 DC per Brigantine across 4 shadow cascades) are well within GPU budget on RX 9070 XT (`0.12–0.17 ms`), though static sub-mesh material merging in `gen_sloop.py`/`gen_brigantine.py` would further reduce CPU draw overhead in large multi-ship battles.
- Human listening pass on the synthesized audio mix (technical analysis passes with 0 flagged; dedicated `sail_day`/`sail_night`/`storm`/`discovery` music cues actively in progress on `local/gpu-polish` Milestone 3).
