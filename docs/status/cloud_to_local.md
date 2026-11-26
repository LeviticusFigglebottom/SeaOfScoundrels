# Cloud Lead -> Local-GPU Satellite Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - Cloud Lead checks `origin/local/gpu-polish` after every single wave, reads `docs/status/local_gpu.md`, merges/cherry-picks clean GPU/shader polish onto `ccr-663b66a0-rdiq4f`, answers every question here, and refreshes the task queue below.

---

## 1. Current Cloud Lead Status (2026-11-26)
- **Latest pushed Cloud Lead commit on `origin/ccr-663b66a0-rdiq4f`**: `44b9c18` (**Wave 22**, GitHub Actions CI `45801136777` **GREEN** across Linux, Windows `.exe`, macOS Universal; `177/177` headless tests **0 ObjectDB / 0 resource leaks**, `3/3` GPU shader tests **0 leaks**, `CLIENT RESULT PASS`, `107/0/0` lint, `164` audio files `0` flagged, **0 remaining 3D gameplay/prop/beast/boss/ordnance/particle primitives across `src/`**!).
- **Currently building in Cloud Lead (4 parallel subagents, landing in ~5 min as Wave 23)**:
  - `23A`: Climbable mainmast `Ladder_CrowsNest` + sculpted `CrowsNestRungs` + co-op `ship_name` replication (`src/ship/ship.gd`).
  - `23B`: Sculpted Mariner's Celebration `VictoryFlare` rocket (`src/world/victory_flare.gd`) + `shot=deck_duel` quarterdeck-rail baluster clearance fix (`scenes/main.gd`).
  - `23C`: 4th `"Captain's Log"` discovery & standing tab in `ShipwrightMenu` + `Profile` lifetime stats (`src/core/profile.gd`, `src/ui/shipwright_menu.gd`).
  - `23D`: `MapTableView` custom ship name cartouche, wind-knot medallion & Outpost lighthouse stars (`src/items/map_table_view.gd`).
- **Next Major Cloud Lead Initiative (Waves 24–27 — Owner Priority Directive!)**:
  - **Massive Archipelago & Island Graphical + Mechanical Depth Overhaul**:
    - Expanding the world from uniform `52–68 m` islands into a dramatic **~4.4 km × 4.4 km archipelago of 14+ islands across 4 distinct size tiers** (`38–44 m` tiny cays/sea-stacks -> `78–92 m` medium ports/forts/coves -> `122–132 m` large lagoons/bluffs/jungles -> **`165–185 m` radius / `330–370 m` diameter MASSIVE flagship islands**!).
    - Eliminating blocky triangular pyramid mountains with adaptive-resolution multi-octave ridged coastal strata, terraced highlands, walkable inland trails, lush batched jungle canopies, ancient stone ruins, wooden bridges, **live animated cliffside Waterfalls & plunge pools**, active volcanic lava rivers & steam fumaroles on massive `Cinder Crag`, sprawling multi-level sea forts (`Ironwatch Fort` + massive `Sovereign's Bastion`), and grand tiered capital outposts (`Port Scoundrel` + massive `Galleon's Reach`)!
    - Cloud Lead owns Blender prop generation (`tools/blender/gen_props.py`), `archipelago.gd`, `island_generator.gd`, `outpost.gd`, and new island landmark/waterfall scripts.

---

## 2. Exclusive Local-GPU PC Owned Files & Active Work Queue (NO Conflict With Cloud!)

To maximize both machines in true parallel with **zero merge conflicts**, Cloud Lead is reserving the following shader & status files exclusively for `local/gpu-polish` right now:
- **Exclusive Local-GPU Shader Ownership (Cloud Lead will NOT touch these while you polish them!)**:
  1. `src/world/island_shader.gdshader`
  2. `src/world/foliage_wind.gdshader`
  3. `docs/status/local_gpu.md`
  *(If you ever need a fix in a Cloud-owned GDScript or Blender file, log it clearly in `docs/status/local_gpu.md` under `## Requests for Cloud Lead` — or touch a non-conflicting showcase/camera tweak ONLY if Cloud isn't editing that file — and Cloud Lead will land it immediately!)*

### Milestone 5 — Immediate High-Priority Work (Start Right Now After Rebasing Onto `origin/ccr-663b66a0-rdiq4f`!)

1. **Task 5A — Painterly Terrain & Cliff Shader Overhaul (`src/world/island_shader.gdshader` & `src/world/foliage_wind.gdshader`) [HIGHEST VISUAL IMPACT!]**:
   - The owner specifically noted that while the ocean, ships, and lighting look great, **our islands currently look too simple/uniform** (especially sterile grey/white triangular cliff peaks and flat sand-to-grass transitions visible in `harbour_plaza`, `night_lighthouse`, and `company_fleet`).
   - Using your real RX 9070 XT for instant 1080p HIGH Forward+ visual iteration, elevate `src/world/island_shader.gdshader` to flagship painterly beauty (inspired by our 3 concept arts — 100% original procedural GLSL):
     - **Rich Geological Cliff Strata & Warm Sunlit Limestone/Sandstone/Ochre Rock**: add multi-frequency warped sedimentary bands, weathered vertical rock-fracture streaks, crevice darkening, warm golden-ochre sunlit highlights vs cool coastal slate-teal shadows (banish sterile chalky grey-white cones!), and **mossy emerald cliff-ledge caps** where rock faces flatten slightly (`normal.y` in `0.52..0.78`)!
     - **Biome-Responsive Uniform Support**: keep all existing uniforms (`cliff_tint`, `grass_tint`, `cliff_facet_strength`, etc.) 100% backward-compatible while adding optional biome uniforms (with safe defaults!) that Cloud's Wave 24 massive island generator can drive per island: e.g. `volcanic_amount` (charred dark basalt + warm glowing fissure seams on `Cinder Crag`), `lush_jungle_amount` (deep rich emerald-moss soil & dense foliage floor on `Emerald Spire` & `Sovereign's Bastion`), `ruin_moss_amount`, and `cliff_strata_scale`.
     - **Lush Painterly Ground Transitions**: richer wet-sand shoreline foam-sheen + shell/pebble micro-grain, organic grassy coastal tussock transition with warm golden dry grass + deep shaded tropical emerald, and subtle dirt-path blending driven by vertex color `COLOR` channels (`COLOR.rgb` AO/tint preserved!).
     - **Atmospheric Aerial Perspective**: verify distant massive islands (`400–2400 m`) blend gracefully into `sky_horizon_color` with crisp readable silhouettes at noon, golden sunset, storm, and moonlight!
     - **`foliage_wind.gdshader`**: enrich translucent sunlit palm-frond subsurface backlight & warm-gold-to-deep-jade leaf tip gradient so dense tropical jungles pop with painterly depth!
     - Verify `0` shader errors, preserve `cloud_shadow.gdshaderinc`, and benchmark GPU ms at 1080p HIGH on RX 9070 XT!

2. **Task 5B — Complete Waves 5–22 Real-GPU 1080p HIGH Visual & Performance Audit**:
   - Profile & visually inspect all showcase shots on real RX 9070 XT at `1920x1080` `quality=high`:
     - `shot=company_fleet ship=brigantine quality=high` (`HullCrest` glowing bow medallions + 4 Company ships)
     - `shot=whale_breach ship=brigantine quality=high` (breaching 14m Humpback + `BreachSprayCurtain` + stern `ShipNameplate`)
     - `shot=night_lighthouse ship=brigantine quality=high` (volumetric dual-cone `LighthouseBeam` + dark-mahogany gold-leaf `ShipNameplate` + bioluminescent surf)
     - `shot=night_sail ship=brigantine quality=high` (nocturnal bioluminescent wake + Sunken Archive sails)
     - `shot=rainbow ship=brigantine quality=high` (42°/51° analytic double coastal rainbow)
     - `shot=coral_reef quality=high` (`CoralReef` 3-DC + 1-DC `ReefFishSchool` + gliding `MantaRay` — verify `0.00 ms` `> 75/85/155 m`!)
     - `shot=harbour_plaza ship=brigantine quality=high` (day + `time=22.4` night fireflies, `TavernSignboard`, `PierFogBell`, `HarbourBunting`)
     - `shot=cabin`, `shot=flotsam`, `shot=dolphins`, `shot=fort_vault`, `shot=fort_siege`, `shot=smugglers_grotto`, `shot=cinder_crag`, `shot=treasure_shark` (`WeepingDrips` hazard VFX!), `shot=leviathan` (zero-primitive sculpted eyes!), `shot=hold` (watertight `y = +0.50 m` `mask_water`!), `shot=brig_deck` (outboard brace clearance!), `shot=fleet`, `shot=storm` (`LightningImpact`), `items_showcase shot=armory`, `crew_showcase shot=shanty`.
   - Flag EVERY visual flaw, frame-time spike, clipping issue, or lighting defect in `docs/status/local_gpu.md` with exact shot/camera/file details so Cloud Lead fixes every single one immediately!

3. **Task 5C — Updated Windows Desktop `.exe` Release Export & Live Playtest Smoke**:
   - Export `build/SeaOfScoundrels.exe` with Godot `4.8-beta5` Windows export template, run a real-GPU live sailing + combat + island exploration smoke test, and record FPS, VRAM, exit code (`EXIT=0`), and zero-error verification in `docs/status/local_gpu.md`!

---

## 3. Standing Continuous Autonomous Loop (NEVER IDLE!)
After pushing Milestone 5 to `origin/local/gpu-polish`:
1. Wait briefly or move straight to **Milestone 6**: `git fetch origin` -> check if `origin/ccr-663b66a0-rdiq4f` has advanced (Wave 23 + Wave 24 Massive Island Overhaul!).
2. Rebase `local/gpu-polish` cleanly onto `origin/ccr-663b66a0-rdiq4f`, read the updated `docs/status/cloud_to_local.md`, and IMMEDIATELY execute the next GPU/shader/visual/profiling/Windows-export milestone!
3. If `origin/ccr-663b66a0-rdiq4f` has not pushed a new wave yet, proactively run deeper real-GPU visual polish (e.g. ocean crest/shore-foam & sunset/night/storm color grading checks, multi-time-of-day island look-dev sweeps across `noon`, `sunset`, `night`, `storm`, draw-call / shader ALU micro-profiling, or automated long-duration memory/FPS soak tests on `SeaOfScoundrels.exe`), commit & push findings to `origin/local/gpu-polish`, and re-poll `origin/ccr-663b66a0-rdiq4f`!

## 4. Open Questions From Cloud Lead -> Local-GPU
- **Q1**: On real RX 9070 XT Vulkan at 1080p HIGH, how much GPU headroom do we have (in ms) for upgrading our biggest flagship islands (`165–185 m` radius) to `128×128` terrain grids + denser `MultiMeshInstance3D` jungle foliage (`~180–260` palms/ferns/boulders per massive island, distance-culled)?
- **Q2**: Do the new `HullCrest` bow medallions (`shot=company_fleet`), `LighthouseBeam` (`shot=night_lighthouse`), `OceanWhale` `BreachSprayCurtain` (`shot=whale_breach`), and `WeepingDrips` (`shot=treasure_shark`) compile and render cleanly with zero Vulkan validation errors or alpha-sorting artifacts on real RDNA4 AMD drivers?
- **Q3**: Did our Wave 4.3 Blender fixes (`y = +0.50 m` flared `mask_water` on Sloop & Brigantine + outboard Brigantine brace anchors) resolve 100% of the stern water bleed in `shot=hold` and brace clipping in `shot=brig_deck` on real hardware?
