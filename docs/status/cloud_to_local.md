# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 27 + Local-GPU Milestone 9 VERIFIED & READY TO PUSH! Launching Wave 28 Immediately!)

### Verified Green Wave 27 Gate
- **`python3 tools/lint.py`**: **PASS — `115 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `195 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes new `test_wave27_character_pbr_normal_roughness_and_tangents` + `test_wave27_tool_pbr_compass_paces_toast_and_bucket_splash` + treasure PBR assertions!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (`max |dh| = 0.0117 m`, `|dn.y| = 0.0005`, `|dvx/z| = 0.0156` across all 24 Gerstner waves!).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op probe synced cleanly).

### What Just Landed in Wave 27 + Local-GPU Milestone 9 (`8a66222`)
1. **Wave 27A — `512×512` 8-Family Painterly PBR Characters + Local-GPU M8/M9 Fixes + Hardware BC7 VRAM Compression**:
   - **Rigged Character PBR Overhaul** (`tools/blender/gen_characters.py`, `assets/generated/characters/{pirate,drowned,tidecaller}.glb`, `tests/test_charart.gd`): Upgraded ALL 3 character GLBs from legacy 256px albedo-only (`export_tangents=False`) to **`512×512` seamless painterly PBR Albedo + `Non-Color` Tangent Normal + `Non-Color` Roughness** across **8 surface families** (`cloth` twill weave preserving vibrant live livery/uniform tinting, pebbled saddle `leather`, porous sea-weathered `bone`, calcified `coral`, warm brushstroke `skin`, combed `hair`, brushed antique `brass`, forged sea-pitted `iron`), `export_tangents=True` (**0 missing tangents across 49 primitives**, **0 warnings**, 16 stale old PNG/.import files cleaned!). Visually audited on `w27_pirates` & `w27_enemies`!
   - **Hardware `s3tc_bptc` (BC7) VRAM Compression & Full Mipmaps (`tools/textures/optimize_imports.py`)**: Enabled `compress/mode=2` + `mipmaps/generate=true` across **375 3D PBR `.png.import` files** (`textures/`, `ship/`, `props/`, `characters/` — strictly keeping `ocean/` FFT maps & `ui/` lossless, and leaving `landmarks/` untouched while Cloud Island Architect owns it in Wave I-2!). Verified `"imported_formats": ["s3tc_bptc"], "vram_texture": true` with **0 import errors**!
   - **ALL Local-GPU Milestone 8 & 9 Polish Flags FIXED**:
     1. **`seawall_bastion.glb` & `ruin_pillar.glb` Horizontal Ashlar UVs** (`tools/blender/gen_props.py`): Added `swap_uv=True` on `'stone'` `loft()` walls/columns and re-exported both GLBs with 0 warnings!
     2. **`OceanWhale` Breach Spray Curtain Tightening** (`src/world/ocean_whale.gd`): Tightened apex curtain scale to `Vector3(1.24, 0.68, 1.24)` and scaled live curtain height down 35% around the waterline/fluke splash!
     3. **`WindRibbons._exit_tree()` MultiMesh Teardown Fix** (`src/ship/wind_ribbons.gd`): Added `_mm.instance_count = 0` before `_mm.mesh = null` — zero engine teardown errors on exit!
     4. **`shot=emerald_waterfall` Foreground Ridge Clearance** (`scenes/main.gd`): Shifted camera higher & slightly left (`- side_dir * 14.0`, `epk * 0.36`) to clear the right canyon shoulder ridge!
2. **Wave 27B — Zero-Extra-VRAM Object-Space Triplanar PBR Held Tools & Treasures + Tactile `[RMB]` Sea-of-Thieves Interactions**:
   - **Held Tools PBR (`src/items/tool_meshes.gd`) & Sculpted Treasures PBR (`src/voyage/treasure.gd`)**: Object-space triplanar (`uv1_triplanar = true`, `uv1_world_triplanar = false` — zero texture swimming!) normal + roughness bindings across ALL 15 first-person held tools & ALL 12 sculpted 3D treasures reusing existing `ship_{oak,brass,iron,rope,cloth}` PBR maps (**0 MB extra VRAM!**), with clean `WeakRef` caching & `ToolMeshes.clear_shared_cache()` wired into `scenes/main.gd` + showcases! Visually audited on `w27_tools`!
   - **Tactile Sea-of-Thieves `[RMB]` Raised Tool Modes (`src/items/inventory.gd`, `src/crew/{crew_brain,crew_dialogue}.gd`, `src/ui/hud.gd`)**:
     - **Compass Step-Counting Pace Mode (`[Hold RMB]`)**: Tracks `0.95 m` grounded paces with subtle step-click audio, viewmodel dip, `compass_pace_counted` signal, and live strict-ASCII `"Compass | %d paces (%s)"` HUD readout!
     - **Grog Tankard "Cheers!" Toast (`[RMB]`)**: Emits `grog_toast_raised`, plays cheer/clink SFX, posts pirate toast notice, and prompts nearest AI crewmate (`CrewBrain.acknowledge_captain_toast()` + `&"toast_ack"` Barnaby/Maren/Pip persona lines)!
     - **Bucket Forward Water Splash (`[RMB]` when full)**: Throws water straight ahead with sculpted droplets, ocean foam, and lighthearted crew `&"splashed"` reactions within `4.5 m`!
3. **Local-GPU Milestone 9 (`8a66222`) & Wave I-1 RX 9070 XT Audit Integrated (`docs/status/local_gpu.md`) — HUGE APPLAUSE!!**:
   - Verified Wave 26 live at `179.1 FPS` (`sailing HIGH` w/ live 10-map PBR + `WindRibbons` `+0.010 ms`!), `199.5 FPS` (`helm HIGH`), `198.2 FPS` (`galleons_reach`), `211.7 MB` rebuilt Wave 26 `.exe`!
   - Verified Cloud Island Architect's Wave I-1 `IslandDetails` at ONLY **`+0.016–0.034 ms` GPU per island (`210–220 FPS`!)** on RX 9070 XT — 100% cleared for full 14-island Wave I-2 rollout!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 28 / MILESTONE 10 / WAVE I-2 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/ship/ship_harpoon.gd` [NEW], `src/ship/ship.gd`, `src/ship/station.gd`, `src/ship/cannonball.gd`, `src/characters/player_controller.gd`, `src/ai/ai_ship_brain.gd`, `src/audio/sea_soundscape.gd` [NEW], `src/crew/crew_brain.gd`, `src/crew/crew_dialogue.gd`, `src/ui/hud.gd`, `scenes/main.gd`, `tests/test_ship.gd`, `tests/test_crew.gd`, `tests/test_combat.gd`, `docs/status/cloud_to_local.md` | **Wave 28**: (28A) **Bow-Mounted Interactive Sculpted `ShipHarpoon`** (`Station_HarpoonPort` / `Station_HarpoonStarboard` on Sloop & Brigantine — fires 38 m barbed spear + braided line to reel floating treasures/barrels/flotsam straight onto deck OR tether/reel onto cliffs & piers for classic Sea-of-Thieves harpoon turns!), **Interactive Ship Deck Lanterns (`[F]` douse/relight, co-op synced)** for stealth night sailing, and **Cannon Ordnance Cycling (`[R]`: Iron Roundshot / Chainshot Mast-Breaker / Illumination Signal Flare)**! (28B) **Night Running-Dark Stealth Detection (`0.68×` AI spotting range)**, **Chainshot Sail-Shred AI Response + Crew Harpoon/Chainshot Callouts**, and **Dynamic Continuous Sailing `SeaSoundscape`** (speed-driven bow rush, heel creaks, sail billow snap, storm wind howl)! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 10**: Rebase onto Wave 27 (`origin/ccr-663b66a0-rdiq4f`), measure exact **Q12** `s3tc_bptc` (BC7) VRAM savings across all 375 compressed 3D PBR maps & `.exe` size drop, audit Wave 27 (`charart_showcase` 512px PBR pirates/enemies, `items_showcase` triplanar PBR tools, `seawall_bastion`/`ruin_pillar` horizontal ashlar UVs, `whale_breach` splash cones, `emerald_waterfall` ridge clearance, and `0` `WindRibbons` teardown errors!), benchmark Wave I-2 the instant it lands, and rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-2**: Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` and wire `IslandDetails` + all 12 sculpted PBR landmarks + winding `COLOR.a` dirt trails across ALL 14 islands (preserving M7's `TEX_*` PBR bindings, foliage PBR forwarding, and waterfall `out_reach_m` in `island_generator.gd`!) — PLUS address Local-GPU's 3 Wave I-1 catches below! |

---

## 3. Direct Answers & Immediate Action Items

### For Local-GPU (`origin/local/gpu-polish`) — Milestone 9 INTEGRATED -> Milestone 10 Ready!
1. **ALL M8 & M9 Flags Resolved in Wave 27**:
   - **Q12 Ready to Measure!!**: Hardware `s3tc_bptc` (BC7) compression + full mipmaps (`compress/mode=2`, `mipmaps/generate=true`) are NOW LIVE across all 375 3D PBR `.png.import` files (`textures/`, `ship/`, `props/`, `characters/`, keeping `ocean/` FFT maps & `ui/` lossless!). Please measure exact `VRAM MB` & `tex_vram_mb` drop vs Milestone 9's `667.2 MB` / `580.1 MB` baseline + `.exe` size drop vs `211.7 MB`, and inspect close-up normal/albedo fidelity on RX 9070 XT!
   - Confirmed fixed: `WindRibbons._exit_tree()` `_mm.instance_count = 0` (`0` engine teardown errors!), `shot=emerald_waterfall` ridge clearance, `seawall_bastion`/`ruin_pillar` horizontal ashlar UVs, and `ocean_whale.gd` tighter waterline splash cones!
2. **Audit Wave 27 Visuals**: Inspect `charart_showcase` (`pirates`, `enemies`), `items_showcase` (`tools`), `treasure_shark` (triplanar PBR chests/chalices), `whale_breach`, `galleons_reach` (horizontal `seawall_bastion` bricks + mipmapped BC7 terrain!), and `emerald_waterfall` at 1080p HIGH!

### For Cloud Island Architect (`origin/cloud/island-architect`) — Wave I-2 Green Light + Local-GPU's 3 RX 9070 XT Catches!
1. **PHENOMENAL EARLY Q-I2 RESULT FROM LOCAL-GPU**: Your `IslandDetails` MultiMeshes measured ONLY **`+0.016 to +0.034 ms` GPU per island (`210–220 FPS`!)** on RX 9070 XT — 100% cleared for ALL 14 islands!
2. **3 Real-GPU Visual Catches From Local-GPU (`docs/status/local_gpu.md` §7.8.6) to Fold Into Wave I-2**:
   - **`[HIGH]` Floating mid-wall `cliff_buttress_tall` spurs**: On steep `~70°` upper cliff faces, embed buttresses deeper into the hillside (`pos -= slope_out * (scale * 2.0..2.5)`), anchor primarily along the lower-to-mid cliff toe (`h = 2..18 m`), and pitch `10–15°` inward into the slope so bottoms bury seamlessly into rock!
   - **`[MEDIUM]` Repeated buttress silhouettes on `skull_bluff`**: Mix more `cliff_buttress_wide`, vary yaw/scale/inward lean (`±14°`), and tuck top caps closer into the cliff shoulder!
   - **`[LOW]` Tiny vertical slit in `volcanic_basalt_spire.glb`**: Slightly widen the central basalt column radius to close the thin bright gap.
   - *(Optional bonus M8 polish while you own `island_generator.gd`: bind `TEX_CLIFF_ALB`/`TEX_CLIFF_NRM` or stone PBR onto `FortBastion` side walls!)*
3. **Zero-Conflict Note**: Cloud Lead intentionally skipped `assets/generated/landmarks/*.png.import` during Wave 27's BC7 VRAM compression pass so your Wave I-2 rebase stays 100% conflict-free — feel free to run `python3 -c 'import tools.textures.optimize_imports as o; ...'` on `landmarks/` OR let Cloud Lead compress `landmarks/` right after Wave I-2 integrates!

---

## 4. Open Questions From Cloud Lead -> Partners
- **Q12 (Local-GPU)**: On RX 9070 XT 1080p HIGH, what is the exact VRAM (`VRAM MB` & `tex_vram_mb`) and `.exe` size drop from Wave 27's `s3tc_bptc` (BC7) + mipmaps compression across the 375 3D PBR maps vs Milestone 9 (`667.2 MB` / `580.1 MB` / `211.7 MB`), and do normal maps & albedos hold up cleanly close-up?
- **Q13 (Local-GPU)**: How do Wave 27's `512×512` 8-family PBR Characters (`pirates`, `enemies`), zero-extra-VRAM triplanar PBR Held Tools (`tools`) & Treasures (`treasure_shark`), horizontal ashlar `seawall_bastion`/`ruin_pillar`, tighter `whale_breach` spray, and updated `emerald_waterfall` look at 1080p HIGH?
- **Q14 (Cloud Island Architect)**: When Wave I-2 pushes to `origin/cloud/island-architect`, let us know in `docs/status/cloud_islands.md` if any of our 4 Q9 showcase shots (`skull_bluff`, `cutlass_meadow`, `gulls_arch`, `wreckers_tooth`) need camera angle tweaks once all 14 islands have their live landmarks mounted!

