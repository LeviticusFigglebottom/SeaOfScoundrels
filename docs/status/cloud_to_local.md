# Cloud Lead -> Local-GPU Satellite Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - Cloud Lead checks `origin/local/gpu-polish` after every single wave, reads `docs/status/local_gpu.md`, merges clean GPU/shader polish onto `ccr-663b66a0-rdiq4f`, answers every question & request here, and refreshes the task queue below.

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 24 + M5/M6 Integrated + Godot 4.7/4.8 Compat Hotfix!)

### Integrated From Local-GPU Milestones 5 & 6 (`0f3e07c` + `bbcc6e1`) — THANK YOU!!
- Merged `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, and `docs/status/local_gpu.md` cleanly into `ccr-663b66a0-rdiq4f`! Your RX 9070 XT empirical mega-island benchmark (`+0.101 ms` per 175 m `128×128` island, `2.167 ms` / `209.2 FPS` for 3× mega-islands + 720 shadow-casting palms!) and pre-flight highland plateau / volcanic ash-scrub / MultiMesh `MODEL_MATRIX[3].xyz` wind-phase upgrades were huge!
- **Wired & Addressed Right Inside Wave 24**:
  1. **Wave 24 Biome Uniforms Wired (`IslandGenerator._create_terrain_material`)**: Every archetype now drives your exact Milestone 5/6 uniforms (`volcanic_amount = 1.0` & `cliff_strata_scale = 0.72` on `volcano_crag`; `lush_jungle_amount = 0.92` on `twin_spires`; `lush_jungle_amount = 0.76` & `ruin_moss_amount = 0.58` & `cliff_strata_scale = 0.74` on `grand_citadel`; `lush_jungle_amount = 0.68` & `path_warmth = 0.68` on `grand_outpost`; `cliff_strata_scale = 1.32` on `sea_stack`, etc.).
  2. **Finding #8 (`CoralReef` Mega-Island Culling)**: Fixed! `CoralReef.populate_for_island()` now scales `visibility_range_end = maxf(VISIBILITY_RANGE_END, island.seabed_radius + 110.0)` so 166–182 m flagship islands never cull reefs along their outer beaches (`test_beasts.gd` updated to verify!).
  3. **Finding #6 (Global Hero Crosshair Hide)**: Fixed! `_apply_hero_shot()` now hides `Crosshair` globally across all showcase shots!
  4. **Finding #2 (`shot=hold` Brigantine Mainmast Occlusion)**: Fixed! Shifted `cam_local_hold` to `Vector3(1.15, 0.48, 0.45)`.
  5. **Finding #4 (`shot=fishing` Equipped Cutlass)**: Fixed! Holstered Captain's weapon cleanly during `shot=fishing`.
  6. **URGENT Owner Hotfix — Godot `4.7.2.stable` + `4.8-beta5` Dual Compatibility**: Owner opened the project in Godot `4.7.2.stable` and hit `Parser Error: Function "get_velocity_at_position()" not found in base self` at `src/ship/ship.gd:3172`. Replaced with cross-version `linear_velocity + angular_velocity.cross(world_p - com_world)` in `ship.gd` AND made `Trail3D` / `PhysicsIntersectRayResult3D` / `intersect_ray_into` in `src/ship/cannonball.gd` and `src/combat/combat_component.gd` dynamically dispatch via `ClassDB` with clean Godot 4.7 fallbacks! **Zero parser errors in BOTH Godot `4.7.2.stable` AND `4.8-beta5`!**

### Landed in Cloud Lead Wave 24 (Massive Varied 14-Island Archipelago Overhaul!)
- **`24A` (`tools/blender/gen_props.py` — 24 Total Stylized Props)**: Added 7 new sculpted Blender props (`jungle_banyan.glb`, `ruin_arch.glb` walkable, `ruin_pillar.glb`, `timber_bridge.glb` walkable 3-ramp arch, `harbour_warehouse.glb`, `seawall_bastion.glb`, `watchtower_wood.glb`).
- **`24B` (Live Dynamic Landmarks)**: Added animated cliffside **`IslandWaterfall`** (`src/world/island_waterfall.gd` + `src/world/waterfall.gdshader`, 472 sculpted tris, `0` primitives, `CULL_DIST = 240 m`) and active **`VolcanicFumarole`** (`src/world/island_fumarole.gd`, 162 sculpted tris, periodic steam/ember eruptions, `CULL_DIST = 190 m`) + `tests/test_island_features.gd`.
- **`24C` (14-Island 4-Tier Massive Archipelago & Adaptive Sculpted Topography)**:
  - **14 islands** across 4 dramatic scale tiers (`38.0 m .. 182.0 m` radius = **`76 m` to `364 m` wide!**), all **91 pairwise channels > 320 m** (`min_channel = 353.5 m`):
    - **Tier 1 (`38–54 m`)**: `sirens_tooth` (`sea_stack`, `38 m` / `54 m` peak), `wreckers_shoal` (`46 m`), `cutlass_cay` (`54 m`).
    - **Tier 2 (`78–96 m`)**: `port_scoundrel` (Outpost 0, `82 m`), `barnacle_haven` (Outpost 1, `78 m`), `gulls_arch` (`82 m`), `ironwatch_fort` (`92 m`), `smugglers_cove` (`96 m`).
    - **Tier 3 (`124–138 m`)**: `skull_bluff` (`124 m`), `crescent_atoll` (`134 m`), `emerald_spire` (`138 m`, `98 m` peak + waterfall!).
    - **Tier 4 (`166–182 m` MASSIVE Flagships)**: `cinder_crag` (`176 m`, `132 m` peak + 4 active `VolcanicFumarole` vents!), `sovereigns_bastion` (`grand_citadel`, `182 m`, `96 m` peak + `FortBastion` + `FortVault` + 4 `FortBattery` cannons + `IslandWaterfall` + ruins/bastions!), `galleons_reach` (`grand_outpost`, Outpost 2, `166 m`, `76 m` peak + warehouses/watchtower/bridge/coral reef!).
  - Adaptive `grid_res` (`72 -> 88 -> 104 -> 120`), ridged massifs, geological cliff terraces, 2-ring crevice AO, area-scaled vegetation & radius-scaled `Island` culling.
- **`24D` (Voyage & Showcase Wiring)**: Full 14-island `VoyageComposer` roster + 4 new Wave 24 showcase cameras (`shot=sovereigns_bastion`, `shot=galleons_reach`, `shot=emerald_waterfall`, `shot=archipelago_panorama`).

---

## 2. NEW HIGHEST-PRIORITY OWNER DIRECTIVE — Wave 25 Architecture (Cloud + Local-GPU Joint Push!)

The owner just gave us a crystal-clear, super-impactful artistic directive:
1. **Detailed, In-Depth, Non-Copy-Pasted PBR Textures Across ALL Assets**:
   - Ship wood/oak hull planks, deck planking, trim scrollwork, iron & brass (currently tiny `256×256` 3-sine-wave wood with NO normal/roughness maps and `None` on paint/iron/brass/rope!).
   - Terrain grass, dirt paths, beach sand, limestone cliff strata, volcanic basalt (rich painterly brushwork + micro-normal relief with **ZERO repeating copy-paste tiling**!).
   - Trees (ringed palm bark, deeply furrowed banyan bark, veined painterly tropical fronds) & architecture (weathered mossy ashlar masonry, cedar shingles, timber planks, plaster, thatch) with per-piece UV offsets!
2. **Sea-of-Thieves-Class Choppy, Deep, Vast, Non-Segmented Ocean Water**:
   - Currently our 16 Gerstner waves cluster the 4 primary swells within `0.42 rad` (`24°`) and `detail_tex` is `512×512` pure sines, making mid-distance water read as slightly segmented parallel bands AND making wave troughs too bright/flat (lacking abyssal volumetric depth!).
   - **Cloud Lead Wave 25A (launching immediately!)** is overhauling the water to Sea-of-Thieves standards:
     - **2D Inverse-FFT JONSWAP/Phillips Directional Ocean Spectrum (`tools/textures/gen_ocean.py`)**: generating seamless `1024×1024` FFT choppy normal + ridge-height + Jacobian-fold cascade textures sampled at **3 rotated irrational prime scales (`17.3 m`, `43.7 m`, `113.9 m`)** + `283 m` macro breakup -> **ZERO segmentation, ZERO tiling!**
     - **24-Wave Golden-Angle Chaotic Gerstner Spectrum (`src/ocean/sea.gd`)**: wider directional crossing swells + steep `5.7–39 m` choppy wavelets (`sum(k*A*steepness) < 0.94`, CPU-GPU parity `< 0.02 m`!).
     - **True Volumetric Optical Depth (`src/ocean/ocean.gdshader`)**: deep bottomless abyssal sapphire-indigo troughs & shadowed backs contrasting boldly against luminous backlit emerald-turquoise thin crests & FFT choppy ridges, crisp Beer-Lambert turquoise-to-emerald-to-abyssal coastal depth gradient, and reactive wake/crest foam!

### Cloud Lead Wave 25 Active Ownership (4 Parallel Disjoint Subagents Launching Immediately!)
- **`25A` (Ocean Overhaul)**: `tools/textures/gen_ocean.py`, `assets/generated/ocean/*`, `src/ocean/sea.gd`, `src/ocean/waves.gdshaderinc`, `src/ocean/ocean.gdshader`, `src/ocean/ocean.gd`, `tests/test_sea.gd`.
- **`25B` (1024×1024 PBR Texture Generator + Sloop/Brigantine Overhaul + Finding #1)**: `tools/textures/gen_world_textures.py` [NEW], `assets/generated/textures/*` (full Albedo + Normal + Roughness sets for ships, props, AND terrain!), `tools/blender/gen_sloop.py`, `tools/blender/gen_brigantine.py` (binding full PBR Albedo+Normal+Roughness maps + adding hemp suspension clew ropes to crew hammocks & clearing `shot=cabin` per Local-GPU Finding #1!).
- **`25C` (24-Prop Tree Bark / Leaf / Masonry PBR Upgrade)**: `tools/blender/gen_props.py` -> re-export all 24 `.glb` props with dedicated `1024×1024` Albedo + Normal + Roughness maps (separate palm bark, banyan bark, oak wood, chiseled mossy stone, veined tropical foliage, cedar shingle/thatch, forged iron/brass — ZERO copy-paste look!).
- **`25D` (Remaining Local-GPU Milestone 5 Polish Sweep)**:
  - Finding #3: `FortBastion` weathered stone masonry texture/albedo contrast + grounded threshold apron (`src/world/fort_battery.gd` / `src/world/island_generator.gd`) + `shot=fort_siege` Brigantine framing (`scenes/main.gd`).
  - Finding #5: `FlotsamCluster` asymmetric organic broken planks (`src/world/flotsam_cluster.gd`).
  - Finding #6: bolder `OceanWhale` `BreachSprayCurtain` (`src/world/ocean_whale.gd`), dry Pier Quartermaster crate (`src/world/outpost.gd`), Hurdy-Gurdy lower hand clearance (`src/characters/animation_driver.gd`), `rainbow` cloud-edge check (`src/sky/sky_clouds.gdshaderinc`).
  - Finding #7: clean `_exit_tree()` static cache drain in `scenes/main.gd` (`0` resources leaked on `--quit-after`!).

---

## 3. Exclusive Local-GPU PC Owned Files & Milestone 7 Queue (ZERO Conflict With Cloud Wave 25!)

- **Exclusive Local-GPU Ownership Right Now (Cloud Lead will NOT touch these during Wave 25!)**:
  1. `src/world/island_shader.gdshader`
  2. `src/world/foliage_wind.gdshader`
  3. `src/world/waterfall.gdshader` *(NEW — handed off to Local-GPU for real RX 9070 XT look-dev!)*
  4. `docs/status/local_gpu.md`

### Milestone 7 — Start Immediately After Rebasing Onto Wave 24!

1. **Task 7A — Wave 24 Massive 14-Island Archipelago 1080p HIGH Real-GPU Audit & Benchmark**:
   - Capture, visually inspect, and profile all 4 brand-new Wave 24 mega-island showcases + updated shots at `1920x1080` `quality=high`:
     - `shot=sovereigns_bastion ship=brigantine quality=high` (`182 m` Grand Citadel + FortBastion + Waterfall + ruins!)
     - `shot=galleons_reach ship=brigantine quality=high` (`166 m` Grand Capital Outpost + warehouses + bridge + watchtower!)
     - `shot=emerald_waterfall ship=brigantine quality=high` (`138 m` lush jungle cliff + cascading `IslandWaterfall`!)
     - `shot=archipelago_panorama ship=brigantine quality=high` (4.4 km multi-tier archipelago vista!)
     - `shot=cinder_crag`, `shot=harbour_plaza`, `shot=hold` (verify Finding #2 fixed!), `shot=fishing` (verify Finding #4 fixed!), `shot=coral_reef` (verify Finding #8 dynamic reef visibility!).
   - Tune `src/world/waterfall.gdshader`, `src/world/island_shader.gdshader`, and `src/world/foliage_wind.gdshader` on live RX 9070 XT Vulkan for 15/10 visual cohesion across noon, sunset, night, and storm!

2. **Task 7B — Pre-Wire Non-Repeating Stochastic PBR Terrain Texture Sampling in `src/world/island_shader.gdshader` [HIGHEST IMPACT FOR OWNER'S TEXTURE DIRECTIVE!]**:
   - Cloud Lead `25B` is generating `1024×1024` seamless hand-painted PBR texture sets under `assets/generated/textures/`:
     - `terrain_grass_albedo.png` + `terrain_grass_normal.png`
     - `terrain_dirt_albedo.png` + `terrain_dirt_normal.png`
     - `terrain_sand_albedo.png` + `terrain_sand_normal.png`
     - `terrain_cliff_albedo.png` + `terrain_cliff_normal.png`
     - `terrain_volcanic_albedo.png` + `terrain_volcanic_normal.png`
   - Please add **backward-compatible stochastic texture sampling** right into `src/world/island_shader.gdshader`:
     - Uniforms: `uniform bool use_terrain_textures = false;` (default `false` so Wave 24 stays 100% compatible until Cloud binds the PNGs in Wave 25/26!) plus `sampler2D` uniforms `tex_grass_albedo`, `tex_grass_normal`, `tex_dirt_albedo`, `tex_dirt_normal`, `tex_sand_albedo`, `tex_sand_normal`, `tex_cliff_albedo`, `tex_cliff_normal`, `tex_volcanic_albedo`, `tex_volcanic_normal` (`repeat_enable, filter_linear_mipmap_anisotropic`).
     - Implement a fast **zero-tiling stochastic Voronoi/hex-grid dual-offset rotated sampler** (or 2-tap domain-warped irrational-scale rotated blend) + **triplanar projection on steep cliffs (`abs(smooth_n)`)** so grass blades, roots/pebbles on dirt trails, rippled shell sand, chipped stratified limestone, and cracked volcanic basalt NEVER look copy-pasted or stretched on steep cliff walls, and stay within `< +0.15 ms` GPU on RX 9070 XT!
   - The second you push Milestone 7 AND Cloud finishes Wave 25B, Cloud will wire all 10 `1024×1024` PNGs + `use_terrain_textures = true` in `IslandGenerator._create_terrain_material()` with ZERO conflicts!

3. **Task 7C — Rebuilt Wave 24 Windows Desktop `.exe` Export & 14-Island Sailing/Flyover Soak**:
   - Export `build/SeaOfScoundrels.exe`, run live multi-island RX 9070 XT smoke test across the new 4.4 km 14-island archipelago, record FPS / GPU ms / VRAM / `EXIT=0`, and report in `docs/status/local_gpu.md`.

### Preview of Milestone 8 (Right After Cloud Pushes Wave 25!)
- Cloud will hand off `src/ocean/ocean.gdshader` to Local-GPU for **Milestone 8 real RX 9070 XT look-dev** on our brand-new **Sea-of-Thieves Multi-Cascade FFT Choppy Ocean**, PLUS full 1080p HIGH close-up & mid-range inspection of ALL Wave 25 `1024×1024` PBR Ship Wood, Terrain Grass/Dirt/Cliff, and Tree/Prop textures!

---

## 4. Open Questions From Cloud Lead -> Local-GPU
- **Q4**: On RX 9070 XT 1080p HIGH, how does the full 14-island Wave 24 archipelago (with `120×120` flagships, `IslandWaterfall`, `VolcanicFumarole`, and 7 new props) measure in GPU ms, draw calls, and VRAM across `sovereigns_bastion`, `galleons_reach`, `emerald_waterfall`, and `archipelago_panorama`?
- **Q5**: For `island_shader.gdshader` stochastic PBR sampling (Task 7B), does 2-tap rotated hex/grid breakup + triplanar cliffs keep `Archipelago` GPU cost comfortably under `0.45 ms` on RX 9070 XT (preserving massive GTX 1660 headroom)?
- **Q6**: Any visual polish tweaks needed on `sovereigns_bastion` (FortBastion/Waterfall placement), `galleons_reach` (harbour warehouses/bridge/watchtower), or `emerald_waterfall`?
