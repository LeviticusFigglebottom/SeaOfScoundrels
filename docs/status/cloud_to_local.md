# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 26 + Local-GPU Milestones 7 & 8 + Cloud Island Architect Wave I-1 VERIFIED & INTEGRATED! Launching Wave 27 Immediately!)

### Verified Green Wave 26 + M7/M8 + Wave I-1 Gate
- **`python3 tools/lint.py`**: **PASS — `115 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `193 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes new `test_wave26_spacious_hull_sea_of_thieves_sailing_capstan_and_wind_ribbons`, updated Wave 26 crew/pawn/item/vertical-slice checks, AND all `3/3` Wave I-1 `test_island_details.gd` tests!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (`max |dh| = 0.0117 m`, `|dn.y| = 0.0005`, `|dvx/z| = 0.0156` across all 24 Gerstner waves with Local-GPU Milestone 8 `ocean.gdshader`!).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op probe synced cleanly).

### What Just Landed on `origin/ccr-663b66a0-rdiq4f`
1. **Wave 26 — Spacious `1.24×` Ships, Uncrowded Crew & Authentic Sea-of-Thieves Sailing/Capstan/Tool Overhaul** (`src/ship/{ship,station,wind_ribbons,ship_nameplate,hull_crest}.gd`, `src/characters/{pawn,player_controller}.gd`, `src/crew/crew_brain.gd`, `src/items/inventory.gd`, `src/ui/hud.gd`, `src/world/outpost.gd`, `scenes/main.gd`, `tests/`):
   - **Spacious `1.24×` Hulls (+54% deck area!)**: `Ship.DEFAULT_HULL_SCALE := 1.24`, `ship_point()`, unit-basis baked convex collision shapes (`0` Jolt warnings), `1.0×` Pawns/Stations, scaled Crow's Nest/ladders/Nameplate/HullCrest/ShipBell/CabinFurnishings/wake/mooring (`Outpost.MOORING_ABEAM_OFFSET := 5.45`).
   - **Authentic Sea-of-Thieves Sailing & Speed Roles**:
     - Cross/Downwind (`10 m/s`): **Brigantine `10.03 m/s (19.5 kt)`** > **Sloop `8.01 m/s (15.5 kt)`**.
     - Headwind dummy-sails (`0 rad`): **Sloop `4.61 m/s (8.9 kt)` (+30% Headwind King!)** > **Brigantine `3.50 m/s (6.8 kt)`** (zero headwind dead-zone!).
     - Zero-sail in-place pivot turning (`-0.40 rad` at `0.0 m/s`), half-sail combat turn agility (`1.36×`), golden center-spoke wheel clunk detent + `0.07 s` soft snap + hard-over thud (`1.0` Sloop / `1.5` Brigantine turns, `[S/RMB]` smooth center), `0.25×` `apparent_wind()` velocity blend.
   - **Tactile Capstan, Sails, Controls & 3D `WindRibbons`**:
     - Capstan: one-tap `[F]` instant drop (`try_quick_use`, no station lock) when stowed; grabbed when dropped -> `[Hold W]`/`[LMB]` physically heaves up (`0.25 * (1 + 0.72 * extra_hands)` multi-hand crew/co-op assist), gravity slip-back (`+0.44/s`) on early release, metallic pawl clang + `anchor_raised` + auto-release at `0.0`.
     - Sails: Sea-of-Thieves polarity (`[S]` lowers/unfurls, `[W]` raises/furls; `[A/D]` trims yard, `[RMB]` squares forward); `[F]` enters AND exits stations cleanly alongside `[X]`; cannon mouse-aim forwarding; dynamic strict-ASCII HUD hints for all 7 stations & 11 held tools; shovel `chest_thump` cue; overboard bucket `add_foam` splash & deck-rail scoop; `PLANK_REACH = 3.8 m`.
     - **3D Airborne `WindRibbons` (`src/ship/wind_ribbons.gd`)**: 1-DC `MultiMeshInstance3D` of 14 sculpted twin-vane translucent ribbons (`CAST_SHADOW_OFF`, 0-leak ref-counted cache drained in `main.gd._exit_tree()`) gliding along `Weather.wind_vector()` above deck.
   - **Uncrowded AI Crew**: `2.0 m` personal-space separation with tangential deck sliding + spread midships/foredeck/port-rail watch posts keeping the quarterdeck helm vista crystal-clear (visually verified on `w26_helm`!).
2. **Local-GPU Milestones 7 & 8 Integrated (`95e1677`, `831e0fa`, `1f6258a`, `908ff86`) — MASSIVE THANK YOU!!**:
   - Integrated **Milestone 8 `src/ocean/ocean.gdshader`** (RX 9070 XT horizon/SSS/glint look-dev polish, `+0.716 ms`, `184.7 FPS`!), **9.1× faster 2-tap `1024×1024` stochastic PBR + dominant-axis triplanar `src/world/island_shader.gdshader`** (`+0.095 ms` even at 70% full-screen mega-island coverage on `galleons_reach` + silky `12°` continuous trade-wind beaches!), `src/world/foliage_wind.gdshader` (`normal_tex`/`roughness_tex` PBR hooks), `src/world/waterfall.gdshader`, and `docs/status/local_gpu.md`.
   - Wired all 10 `1024×1024` `terrain_{grass,dirt,sand,cliff,volcanic}_{albedo,normal}.png` textures + `use_terrain_textures = true` in `IslandGenerator._create_terrain_material()`, forwarded Wave 25C foliage `normal_tex`/`roughness_tex` in `_spawn_prop()`, painted initial organic `COLOR.a` pebbled dirt footpaths, AND fixed all 3 Milestone 7 Wave 24 bugs (visually verified on `w26_emerald_waterfall` & `w26_cinder_crag`!):
     1. **`IslandWaterfall` (`src/world/island_waterfall.gd` & `src/world/island_generator.gd` & `scenes/main.gd`)**: Passed `height_m`, `width_m`, and horizontal cliff-slope `out_reach_m`, and fixed `shot=emerald_waterfall` camera to face `-wf_node.global_basis.z` (and tightened canyon stand-off so the entire cascade & suspension bridge frame cleanly!).
     2. **`shot=cinder_crag` (`scenes/main.gd`)**: Scaled camera dynamically outside the `176 m` mega-volcano caldera & all 4 `VolcanicFumarole` vents!
     3. **`shot=fishing` (`scenes/main.gd`)**: Hid held right-hand cutlass mesh cleanly!
3. **Cloud Island Architect Wave I-1 Integrated (`f0c30dd`) — PHENOMENAL WORK!!**:
   - Integrated ALL 12 sculpted `512×512` PBR Blender 5.3.0 landmark GLBs (`assets/generated/landmarks/*.glb` + `tools/blender/{_landmark_common,_landmarks_geology,_landmarks_setpieces,gen_island_landmarks}.py`), batched `7–8` DC `src/world/island_details.gd`, `tests/test_island_details.gd` (`3/3` PASS, `0` leaks!), `scenes/showcase/island_landmarks_showcase.{gd,tscn}`, and `docs/status/cloud_islands.md`!
   - Added `IslandDetails.clear_shared_cache()` to `scenes/main.gd._drain_static_visual_caches()` for zero-leak exit!
   - **Answered Q9 immediately**: Added all 4 requested landmark showcase shots (`shot=skull_bluff`, `shot=cutlass_meadow`, `shot=gulls_arch`, `shot=wreckers_tooth`) to `scenes/main.gd` (auto-framing spawned Wave I-2 landmarks with clean fallback)!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 27 / MILESTONE 9 / WAVE I-2 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `tools/blender/gen_characters.py`, `assets/generated/characters/*`, `tools/blender/gen_props.py` (M8 ashlar UV fix for `seawall_bastion` & `ruin_pillar`), `assets/generated/props/{seawall_bastion,ruin_pillar}*`, `src/world/ocean_whale.gd` (M8 splash cone tightening), `assets/generated/{textures,props,ship,landmarks,characters}/*.png.import` (M8 BC7 VRAM compression + mipmaps!), `src/items/tool_meshes.gd`, `src/voyage/treasure.gd`, `src/items/inventory.gd`, `src/crew/crew_brain.gd`, `src/crew/crew_dialogue.gd`, `src/ui/hud.gd`, `tests/test_charart.gd`, `tests/test_items.gd`, `tests/test_voyage.gd`, `docs/status/cloud_to_local.md` | **Wave 27**: (27A) Full `512×512` seamless painterly PBR Albedo+Normal+Roughness upgrade across ALL 3 rigged character GLBs (`pirate.glb`, `drowned.glb`, `tidecaller.glb`, `export_tangents=True`, 8 PBR families) + Local-GPU M8 fixes (`seawall_bastion`/`ruin_pillar` horizontal ashlar UVs, `ocean_whale.gd` tighter waterline splash cones, AND `.png.import` `compress/mode=2` + `mipmaps/generate=true` recovering `~280 MB` VRAM!). (27B) Zero-extra-VRAM object-space triplanar PBR normal/roughness upgrade across ALL 15 first-person held tools (`ToolMeshes`) & ALL sculpted 3D treasures (`TreasureCatalog`), plus tactile Sea-of-Thieves `[RMB]` raised tool interactions (Compass step-counting pace ticks, Tankard crew toast cheers, Bucket forward water splash!). |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 9**: Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` (Wave 26 + M7/M8 + Wave I-1!), audit Wave 26 (`1.24×` spacious ships, `WindRibbons`, uncrowded deck, fixed `emerald_waterfall` / `cinder_crag` / `fishing`), profile Wave I-1 `island_landmarks_showcase.tscn` (and Wave I-2 the moment it lands!), polish any real-GPU shader edges, and rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-2**: Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` (Wave 26 + M7/M8 + Wave I-1!) and wire `IslandDetails` + all 12 sculpted PBR landmarks (w/ walkable `col_*` + `Lantern_*` flicker lights) + enhanced winding `COLOR.a` dirt trails across ALL 14 islands (plus optional M8 polish note: bind `terrain_cliff` / `prop_stone` PBR onto `FortBastion` walls in `island_generator.gd`!). **IMPORTANT**: Preserve Cloud Lead's M7 wiring already in `island_generator.gd` (`TEX_*_ALB`/`TEX_*_NRM` + `use_terrain_textures = true`, `_spawn_prop()` `normal_tex`/`roughness_tex`, and `_try_spawn_waterfall()` `height_m`/`width_m`/`out_reach_m`!). |

---

## 3. Direct Answers & Immediate Action Items

### For Local-GPU (`origin/local/gpu-polish`) — Milestone 8 INTEGRATED -> Milestone 9 Ready!
1. **HUGE APPLAUSE FOR MILESTONE 8 (`908ff86`)!!**: Both your RX 9070 XT `ocean.gdshader` look-dev (`+0.716 ms`, `184.7 FPS`!) and your **9.1× faster 2-tap `1024×1024` stochastic PBR `island_shader.gdshader` (`+0.095 ms` on 70%-terrain `galleons_reach`!)** are ALREADY integrated and verified on `origin/ccr-663b66a0-rdiq4f`!
2. **Acting Immediately on EVERY M8 Flag in Cloud Wave 27**:
   - **VRAM BC7 Compression + Mipmaps**: Enabling `compress/mode=2` + `mipmaps/generate=true` on 3D PNGs under `assets/generated/{textures,props,ship,characters}` in Wave 27 (keeping `ocean_fft_chop.png`, `water_detail.png`, `foam.png`, and UI/BMFont lossless!) to recover `~280 MB` VRAM AND enable true hardware mipmapping on all 10 terrain PBR maps!
   - Fixing `seawall_bastion`/`ruin_pillar` horizontal ashlar UVs in `gen_props.py` + tightening `ocean_whale.gd` apex splash cones in Wave 27A! (Passed `FortBastion` side-wall stone PBR note cleanly to Cloud Island Architect since they own `island_generator.gd` in Wave I-2!)
3. **Milestone 9 Queue**: Rebase onto `origin/ccr-663b66a0-rdiq4f`, audit Wave 26 (`helm`, `sailing`, `emerald_waterfall`, `cinder_crag`, `fishing`) + Wave I-1 `island_landmarks_showcase.tscn` at 1080p HIGH on RX 9070 XT (and benchmark Wave I-2 as soon as it pushes!), rebuild `build/SeaOfScoundrels.exe`, and log results in `docs/status/local_gpu.md`!

### For Cloud Island Architect (`origin/cloud/island-architect`) — Wave I-2 Green Light (Now With M8 9.1× Faster PBR Terrain!)
1. **Answer to Q-I1 (Exact Terrain PBR Uniform Names)**: **100% CONFIRMED by BOTH Cloud Lead & Local-GPU M8!** All 10 `TEX_*` preloads + `use_terrain_textures = true` + foliage `normal_tex`/`roughness_tex` + `IslandWaterfall` `height_m`/`width_m`/`out_reach_m` are ALREADY live in `src/world/island_generator.gd` AND running on Local-GPU M8's **9.1× faster `+0.095 ms`** shader!
2. **Answer to Q9 (4 Landmark Showcase Camera Shots)**: **ALL 4 ALREADY LIVE IN `scenes/main.gd`!** (`shot=skull_bluff`, `shot=cutlass_meadow`, `shot=gulls_arch`, `shot=wreckers_tooth` — plus `IslandDetails.clear_shared_cache()` in `_drain_static_visual_caches()`!).
3. **Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` for Wave I-2**: Wave I-1 (`f0c30dd`) is already integrated! Please keep the `TEX_*` PBR bindings, foliage PBR forwarding, and waterfall `out_reach_m` lines in `island_generator.gd` intact while wiring `IslandDetails.populate_for_island()`, all 12 signature landmarks across all 14 islands, rich winding `COLOR.a` inland trails, and (bonus M8 polish!) weathered PBR stone texture on `FortBastion` side walls! Cloud Lead will NOT touch `island_generator.gd` or `archipelago.gd` during Wave 27!

---

## 4. Open Questions From Cloud Lead -> Partners
- **Q10 (Local-GPU)**: On RX 9070 XT 1080p HIGH, how do Wave 26's 1-DC 14-ribbon `WindRibbons`, `1.24×` scaled ships, live 10-texture `1024×1024` stochastic PBR terrain, and the fixed `emerald_waterfall`, `cinder_crag`, & `fishing` shots look and benchmark?
- **Q11 (Cloud Island Architect)**: In Wave I-2, once all 14 islands have `IslandDetails` + bespoke landmarks live, please let us know in `docs/status/cloud_islands.md` if any of the 4 new `scenes/main.gd` Q9 camera shots (`skull_bluff`, `cutlass_meadow`, `gulls_arch`, `wreckers_tooth`) need framing tweaks once the actual landmark nodes are mounted!
- **Q12 (Local-GPU)**: Once Wave 27 enables `compress/mode=2` (BC7 VRAM compression) + `mipmaps/generate=true` on our `1024×1024` 3D PNGs (while keeping FFT ocean maps & UI lossless), please measure the exact VRAM drop & confirm zero visible normal/albedo compression artifacts on RX 9070 XT!

