# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 25 VERIFIED & PUSHED! Launching Wave 26 Immediately!)

### Verified Green Wave 25 Gate
- **`python3 tools/lint.py`**: **PASS — `0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `185 tests, 0 failures`, `0` ObjectDB/resource leaks**.
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (`max |dh| = 0.0117 m`, `|dn.y| = 0.0005`, `|dvx/z| = 0.0156` across ALL 24 Gerstner waves!).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op probe synced cleanly).
- Also fixed `Audio.is_shanty_playing()` in `src/audio/audio_manager.gd` to exclude `_shanty_stopping` so crewmates never auto-join a fading shanty.

### What Just Landed in Wave 25 (`25A`–`25D`)
1. **`25A` — Sea-of-Thieves Multi-Cascade 2D-FFT Ocean Overhaul** (`tools/textures/gen_ocean.py`, `assets/generated/ocean/{ocean_fft_chop.png,water_detail.png,foam.png}`, `src/ocean/sea.gd`, `src/ocean/ocean.gd`, `src/ocean/ocean.gdshader`, `tests/test_sea.gd`):
   - Generated seamless `1024×1024` 2D inverse-FFT directional JONSWAP/Phillips choppy ocean spectrum (`ocean_fft_chop.png`: slope XY + wavelet ridge height B + Jacobian crest fold A) + `1024×1024` capillary FFT normal/caustic map (`water_detail.png`).
   - Expanded `Sea.WAVE_TABLE` from 16 -> **24 prime-wavelength waves (`241 m .. 5.7 m`)** spread organically around full `360°` crossing cones (`calm_pinch = 0.4349`, `storm_pinch = 0.9272`, `long_spread = 3.30 rad` — ZERO segmented parallel rows!).
   - Upgraded `ocean.gdshader` with **3 rotated irrational-scale FFT chop cascades**, deep fathomless sapphire-indigo troughs (`trough_ao = 0.42`, `face_contrast = 0.24..1.48`), luminous backlit emerald-turquoise crest SSS, and crisp Beer-Lambert turquoise-to-abyss reef transition.
2. **`25B` — `1024×1024` Hand-Painted PBR Texture Generator + Full PBR Sloop & Brigantine + Local-GPU Finding #1** (`tools/textures/gen_world_textures.py`, `assets/generated/textures/*`, `tools/blender/gen_sloop.py`, `tools/blender/gen_brigantine.py`, `tools/build_assets.sh`):
   - Generated **27 seamless `1024×1024` / `512×512` procedural hand-painted PBR PNGs** in `assets/generated/textures/`:
     - **Terrain (10× `1024×1024` — ready for Local-GPU Milestone 7 stochastic PBR shader!)**:
       - `res://assets/generated/textures/terrain_grass_albedo.png` + `terrain_grass_normal.png`
       - `res://assets/generated/textures/terrain_dirt_albedo.png` + `terrain_dirt_normal.png`
       - `res://assets/generated/textures/terrain_sand_albedo.png` + `terrain_sand_normal.png`
       - `res://assets/generated/textures/terrain_cliff_albedo.png` + `terrain_cliff_normal.png`
       - `res://assets/generated/textures/terrain_volcanic_albedo.png` + `terrain_volcanic_normal.png`
     - **Ships (17× `1024×1024` / `512×512`)**: `ship_{oak,paint,iron,brass,rope}_{albedo,normal,rough}.png` + `ship_cloth_{albedo,normal}.png` (8-course staggered oak deck planks with knots, tarred seams, and paired trunnel nails!).
   - Re-exported `sloop.glb` & `brigantine.glb` (+ LODs) via Blender 5.3.0 with full Albedo + `Non-Color` Normal + `Non-Color` Roughness maps, `export_tangents=True`, AND **Local-GPU Finding #1 FIXED**: added braided hemp suspension clew ropes to Sloop & Brigantine crew hammocks and tucked Brigantine hammocks forward/outboard (`z = 2.35..4.30`, `x = ±1.76..1.82`) cleanly out of `shot=cabin`!
3. **`25C` — 24-Prop Bespoke Painterly PBR Upgrade** (`tools/blender/gen_props.py` + all 24 `.glb`s re-exported via Blender 5.3.0):
   - Replaced legacy `256×256` maps with **15 bespoke procedural PBR texture families** (`mat_bark_palm`, `mat_bark_banyan`, `mat_wood`, `mat_shingle`, `mat_thatch`, `mat_stone`, `mat_rock`, `mat_plaster`, `mat_foliage` [palm/fern vs 88-leaf broadleaf/ivy preserving exact `mat_foliage` hook], `mat_awning`, `mat_rope`, `mat_iron`, `mat_brass`, `mat_paint`), `export_tangents=True` (0 warnings across all 24 `.glb`s!), and per-piece `mb.newoff()` anti-repetition.
   - Removed 78 stale obsolete old extracted PNG + `.import` files.
4. **`25D` — Local-GPU Milestone 5 Polish Sweep**:
   - Finding #3: `FortBastion` weathered stone masonry contrast & grounded threshold skirt (`src/world/island_generator.gd`) + `shot=fort_siege` Brigantine seaward framing (`scenes/main.gd`).
   - Finding #5: `FlotsamCluster` asymmetric organic splintered planks (`src/world/flotsam_cluster.gd`).
   - Finding #6: bolder `OceanWhale` `BreachSprayCurtain` at apex (`src/world/ocean_whale.gd`), dry Pier Quartermaster crate (`src/world/outpost.gd`), Hurdy-Gurdy lower hand clearance (`src/characters/animation_driver.gd`), rainbow cumulus edge fix (`src/sky/cloud_field.gdshaderinc`).
   - Finding #7: clean `_exit_tree()` static cache drain in `scenes/main.gd`.

---

## 2. NEW LIVE-PLAYTEST DIRECTIVES & 3-WAY EXCLUSIVE OWNERSHIP MATRIX (ZERO CONFLICTS!)

The Owner tested live in Godot and gave us **TWO crystal-clear highest-priority gameplay & visual directives**:
1. **Ships, AI Crew Spacing, Sailing Physics & Tactile Interactions** *(Cloud Lead Wave 26 — launching IMMEDIATELY!)*:
   - *"with the AI crew, the ship feels a little crowded and so all should be a little bigger. Sailing also feels entirely wrong, so overhaul that with the proper sea of thieves mechanics, as well as most item interactions, like the anchor/raising sails etc"*
2. **Islands Looking Flat / Boring / 2D Smoothed Heightfields** *(Cloud Partner #2 `cloud/island-architect` + Local-GPU `local/gpu-polish` Joint Push!)*:
   - *"The other blatantly obvious gap is islands themselves looking flat, boring, and 2d; smoothed terrain with no detail, textures, unique characteristics, etc"*

### Active Exclusive File Ownership Fences (Effective Immediately!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/ship/*` (incl. `wind_ribbons.gd` [NEW]), `src/characters/player_controller.gd`, `src/characters/pawn.gd`, `src/crew/crew_brain.gd`, `src/items/inventory.gd`, `src/ui/hud.gd`, `src/world/outpost.gd` (mooring abeam offset only), `scenes/main.gd`, `tests/test_ship.gd`, `tests/test_crew.gd`, `tests/test_pawn.gd`, `tests/test_items.gd`, `tests/test_vertical_slice.gd`, `docs/status/cloud_to_local.md` | **Wave 26**: Spacious `1.24×` ships (+54% deck floor area!), AI crew wide watch spacing (`min_sep >= 2.0 m`), authentic Sea-of-Thieves sailing physics (Brig fastest cross/tailwind, Sloop fastest headwind dummy-sails, in-place zero-sail pivot, half-sail tight turn, golden center-spoke wheel clunk, instant `[F]` tap anchor drop + physical `[Hold W]` capstan heaving with gravity slip-back & multi-hand boost, `S=lower / W=raise` sail cleat, `[F]` enter & leave stations, live station & held-item prompts, 3D airborne Wind Stream Ribbons!). |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, **`src/ocean/ocean.gdshader` (HANDED OFF NOW!)**, `docs/status/local_gpu.md` | **Milestone 7 & 8**: (1) Stochastic non-repeating PBR terrain texture sampling (`use_terrain_textures = true` binding Cloud Wave 25B's 10 `assets/generated/textures/terrain_*.png` maps + triplanar steep cliffs!) in `island_shader.gdshader`! (2) Real RX 9070 XT look-dev on Wave 25's brand-new **2D-FFT Choppy Ocean (`src/ocean/ocean.gdshader`)** + `waterfall.gdshader`! (3) 1080p HIGH Wave 24/25 audit (`brig_deck`, `cabin`, `sovereigns_bastion`, `galleons_reach`, `emerald_waterfall`, `archipelago_panorama`, `sailing`, `storm`) + rebuilt Windows `.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `tools/blender/gen_island_landmarks.py` [NEW], `assets/generated/landmarks/*` [NEW], `src/world/island_details.gd` [NEW], **`src/world/island_generator.gd` (HANDED OFF NOW!)**, **`src/world/archipelago.gd` (HANDED OFF NOW!)**, `tests/test_island_details.gd` [NEW], `docs/status/cloud_islands.md` | **Wave I-1 & I-2**: Shatter the flat 2D heightfield look across all 14 islands! Build sculpted 3D cliff buttresses, sea-carved cliff overhangs, jagged basalt columns, natural rock bridges/arches, Skull Cliff cavern, Ancient Temple Stairs, sunken shipwreck ribs, terraced outpost seawalls, dense batched 3D MultiMesh ground cover (tropical grass clumps, low ferns, bright coastal hibiscus/wildflowers, mossy cobbles, driftwood, seashells — `CAST_SHADOW_OFF`!), dramatic sculpted terrain profiles + `COLOR.a` walkable dirt trails, and rich unique landmarks per island! *(NOTE: Keep `Outpost.MOORING_ABEAM_OFFSET` untouched — Cloud Lead owns `src/world/outpost.gd` in Wave 26!)* |

---

## 3. Immediate Action Items & Handoffs

### For Local-GPU (`origin/local/gpu-polish`) — Milestones 7 & 8 (Rebase onto Wave 25!)
1. **Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` (Wave 25)** — ALL 10 `1024×1024` seamless hand-painted terrain PBR maps are NOW IN THE REPO under `assets/generated/textures/terrain_{grass,dirt,sand,cliff,volcanic}_{albedo,normal}.png`!
2. **HIGHEST PRIORITY — Upgrade `src/world/island_shader.gdshader` with Non-Repeating Stochastic PBR Terrain Sampling**:
   - Wire `tex_grass_{albedo,normal}`, `tex_dirt_{albedo,normal}`, `tex_sand_{albedo,normal}`, `tex_cliff_{albedo,normal}`, `tex_volcanic_{albedo,normal}` (`repeat_enable, filter_linear_mipmap_anisotropic`) with fast 2-tap rotated hex/voronoi breakup (ZERO tiling!) + **triplanar projection on steep cliff walls** (`abs(smooth_n)`), default `use_terrain_textures = false` (or auto-bind / Cloud Lead & Island Architect will set `use_terrain_textures = true` & pass the 10 textures from `IslandGenerator._create_terrain_material()` the moment Milestone 7 pushes!).
   - Also keep `1.0 - COLOR.a` dirt-trail masking sharp and inviting — Cloud Island Architect is painting organic winding dirt footpaths across all 14 islands!
3. **NEW HANDOFF — Real RX 9070 XT Look-Dev on Wave 25's FFT Ocean (`src/ocean/ocean.gdshader`)**:
   - `src/ocean/ocean.gdshader` is **now exclusively yours** for Milestone 8! Inspect our new 3-cascade 2D-FFT chop + 24-wave Gerstner ocean at `1920x1080` `quality=high` across noon, sunset, storm, reef shallows, and night bioluminescence; tune chop crispness, trough abyss depth, foam lacing, and specular sparkle on live RDNA4 Vulkan (and check GPU ms cost of 24 waves + 3 FFT cascades vs our `0.634 ms` baseline!).
4. **Verify Wave 25 Visuals & Export `.exe`**:
   - Confirm Finding #1 (`cabin` / `hold` roped hammocks), Finding #3 (`FortBastion` stone contrast & `fort_siege` Brigantine), Finding #5 (organic `FlotsamCluster`), Finding #6 (whale spray, dry crate, Hurdy-Gurdy), Finding #7 (`0` exit leaks on `--quit-after`), plus Wave 25 `1024×1024` ship oak planks & 24 PBR props!
   - Rebuild `build/SeaOfScoundrels.exe` and report GPU ms / FPS / VRAM in `docs/status/local_gpu.md`.

### For Cloud Partner #2 (`origin/cloud/island-architect`) — Welcome Aboard!!
- **Both `src/world/island_generator.gd` and `src/world/archipelago.gd` are OFFICIALLY HANDED OFF TO YOU** on top of Wave 25!
- Follow the exact architecture in your onboarding brief:
  1. Keep `godot --headless --path . --import`, `python3 tools/lint.py`, and `bash tools/test.sh` 100% green (`0` leaks, `0` raw `PrimitiveMesh`es, Godot `4.7.2` + `4.8-beta5` compatible, `vertex_color_is_srgb = true` on vertex-colored meshes, strip `col_*` on visual-only `.glb`s).
  2. When populating `IslandDetails` (`MultiMeshInstance3D` ground cover + 3D cliff buttresses/overhangs/arches), respect `CAST_SHADOW_OFF` + `visibility_range_end = 160..320 m` for small grass/fern/flower/pebble clumps (per Local-GPU's RX 9070 XT benchmark!) while keeping dramatic sculpted cliff buttresses & signature landmarks visible out to `1600–2400 m` for unforgettable Sea-of-Thieves island silhouettes!
  3. Paint `COLOR.a` toward `0.0` along walkable inland footpaths/trails (dock -> tavern -> summit -> ruins -> cove) — Local-GPU's `island_shader.gdshader` already renders `1.0 - COLOR.a` as pebbled sun-warmed dirt paths!
  4. Do NOT touch `src/world/outpost.gd`, `src/ship/*`, `src/ocean/*`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, or `scenes/main.gd` — write all your status, screenshots, and requests to `docs/status/cloud_islands.md` and push to `origin/cloud/island-architect`! Cloud Lead will integrate your waves cleanly onto `ccr-663b66a0-rdiq4f`!

---

## 4. Open Questions From Cloud Lead -> Partners
- **Q7 (Local-GPU)**: On RX 9070 XT 1080p HIGH, how does Wave 25's 24-wave Gerstner + 3-cascade 2D-FFT `ocean.gdshader` measure in GPU ms vs the previous `+0.634 ms` baseline? Any chop/trough/foam look-dev tweaks you want to land in M8?
- **Q8 (Local-GPU)**: Does stochastic 2-tap rotated terrain PBR sampling + triplanar cliffs in `island_shader.gdshader` stay comfortably `< +0.25 ms` on RX 9070 XT with our 10 `1024×1024` `terrain_*.png` textures?
- **Q9 (Cloud Island Architect)**: Once `origin/cloud/island-architect` pushes Wave I-1 (`gen_island_landmarks.py` + `island_details.gd`), let us know in `docs/status/cloud_islands.md` if you'd like any new showcase camera shots added to `scenes/main.gd` (Cloud Lead will add them immediately on integration!).
