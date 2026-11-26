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
  - `scenes/main.tscn` (`sailing`): `1.32 ms` GPU MED (`285 FPS`), `1.57 ms` GPU HIGH (`256 FPS`), `storm` HIGH `1.96 ms` GPU (`230 FPS`), ~`6.6 ms` est. GTX 1660 class (well under the `16.6 ms` / 60 fps D10 budget).
  - 51/51 real-Vulkan captures exited cleanly (`exit=0`, zero `__futex_wait` deadlocks).
  - Audio analysis: 155 files, `0 flagged`, 100% of musical notes in tune.
- **Note for `local/gpu-polish` on next `git fetch origin` (zero-conflict handoff):**
  - Cloud Lead has **already fixed and pushed on `ccr-663b66a0-rdiq4f`** ALL of:
    1. `tools/lint.py` Windows LSP URI fix (ported from your Milestone 1).
    2. All Round 2 visual defects: `RadialWheel` & `HUD` `PRESET_FULL_RECT` centering + wrapping, 105-glyph `scoundrel_font.fnt`, `ToolMeshes` loft cap/pistol winding & spyglass tube overlap, `MapTableView` baked-paper cover/warmth/label clamping/Brigantine height, `Inventory` compass raise pose, `items_showcase.gd` grounded rack, `island_shader.gdshader` spire peaks/organic limestone/sand ripples, `island_generator.gd` monotonic Cutlass Cay cove & cliff boulder slope filter, `gen_props.py` limestone sea stacks/cedar tavern roof/lush palms, `animation_driver.gd` 2-bone crouch flexion & `gen_characters.py` Drowned neck, `ocean.gdshader` foreground wash/aerial SSS breakup, `ocean_common.gdshaderinc` smooth underwater shafts, `crest_spray.gd` fair-weather mist + lagoon guard, `ship.gd` twin outboard bow spray/feathered leak jets/cursed Drowned hull livery/stern hold cutout threshold/Brigantine wake length scaling, `gen_brigantine.py` outboard quarterdeck backstay & brace anchors, and `scenes/main.gd` tracking hero cameras + cleared `map_table`/`hold` cameras + live harbour Brigantine swap!
  - **Best high-value non-overlapping work for `local/gpu-polish` next:**
    1. Rebase onto latest `origin/ccr-663b66a0-rdiq4f` before pushing Milestone 2 so there are zero conflicts on the files above.
    2. Keep owning: `src/sky/sky_body.gdshaderinc` (smooth volumetric cloud raymarch edges & subtle cirrus), `src/world/island.gd` + `src/items/map_table_view.gd` distance/visibility CPU p95 throttling, `scenes/showcase/{combat,charart}_showcase.gd` framing tweaks, and **Milestone 3** (`tools/audio/gen_music.py` 4 dedicated tracks: `sail_day`, `sail_night`, `storm`, `discovery` stinger).
    3. Re-profile & visually verify our newly pushed Round 2 Polish + Brigantine fixes at 1080p on RX 9070 XT, plus Windows `.exe` export real-GPU boot smoke test.

## Known issues / open polish
- Ship draw calls (~358 DC per Sloop, ~480 DC per Brigantine across 4 shadow cascades) are well within GPU budget on RX 9070 XT (`0.12–0.17 ms`), though static sub-mesh material merging in `gen_sloop.py`/`gen_brigantine.py` would further reduce CPU draw overhead in large multi-ship battles.
- Human listening pass on the synthesized audio mix (technical analysis passes with 0 flagged; dedicated `sail_day`/`sail_night`/`storm`/`discovery` music cues queued with `local/gpu-polish`).
