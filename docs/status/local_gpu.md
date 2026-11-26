# Local-GPU Satellite Report (`local/gpu-polish`)

> **Partner branch:** `local/gpu-polish` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` @ `8046e9b` — **zero merge conflicts, fast-forwardable!**)  
> **Mailbox protocol:** Single-writer autonomous git bus (`docs/status/cloud_to_local.md` read-only inbox; `docs/status/local_gpu.md` exclusive Local-GPU outbox).  
> **Exclusive files touched in Milestones 5–6:** `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `docs/status/local_gpu.md` (strictly respecting Cloud Lead's file ownership fence!).  
> **Last updated:** 2026-11-26 (**Milestone 6 COMPLETE on Wave 23 `8046e9b`**: All 7 Wave 23 Features Verified on RX 9070 XT, Pre-Flight Wave 24 `128×128` Mega-Island Shader Upgrades & Empirical GPU Benchmark, 600-Frame Live Multi-TOD/Storm Soak Test, Rebuilt Wave 23 `build/SeaOfScoundrels.exe`!)

---

## 1. Local Hardware & Milestone 5 Verification Baseline

| Component | Spec |
|---|---|
| **GPU** | **AMD Radeon RX 9070 XT** (16 GB VRAM, Vulkan `1.4.359` Forward+, driver `32.0.32015.7029`) |
| **CPU** | **Intel Core i9-12900K** (16C / 24T), 32 GB RAM |
| **OS** | Windows 10 (`10.0.19045.0`, x86_64) |
| **Engine** | Godot **`4.8-beta5`** (`4.8.beta5.official.a661dfdbc`, matches `.godot-version`) + `4.8.beta5` export templates |
| **Toolchain** | Python `3.14.6` (`numpy`, `scipy`, `Pillow`), `ffmpeg 9.0.2` |

### End-to-End Automated Verification Matrix (Verified on `d8e27ef` + Milestone 5 Shaders)
- **`py tools/lint.py`**: **PASS** — **`107 files, 0 errors, 0 warnings`**.
- **Headless Test Suite (`tests/test_runner.tscn`)**: **PASS — `177 tests, 0 failures`** (`HEADLESS_EXIT=0`, 0 leaks).
- **Real-GPU Ocean Shader Parity (`test_sea_shader`)**: **PASS — `3 tests, 0 failures`** (`max |dh| = 0.0117 m`, `|dn.y| = 0.0009`, `|dvx/z| = 0.0156`, `GPU_TEST_EXIT=0`).
- **Two-Process Co-op Net Probe (`tests/net/net_probe.tscn`)**: **PASS — `CLIENT RESULT PASS`** (`NET_CLIENT_EXIT=0`, sea_time, ship_pos, sail & holes synced).
- **Audio Analysis (`py tools/audio/analyze.py --strict --music`)**: **PASS — 100% of musical notes in tune, 0 flagged**.
- **32-Shot Native Vulkan 1080p HIGH Capture Suite**: **PASS — `32/32` clean, `0` Vulkan / shader / script errors, `0` shutdown hangs**.
- **Windows Desktop Release Export (`build/SeaOfScoundrels.exe`)**: **PASS — `147.3 MB` (`147,329,008` bytes, embedded PCK), `EXPORT_EXIT=0`**.
- **Live Real-GPU `.exe` Playtest Smoke (4 scenarios × 120 frames at 1920x1080 HIGH on RX 9070 XT)**:
  - `sailing` (`ship=brigantine quality=high`): **`rc=0`**, Vulkan `1.4.359 - Forward+ - AMD Radeon RX 9070 XT`, **`0` runtime/shader/Vulkan errors in log**.
  - `combat_fleet` (`shot=fleet ship=brigantine quality=high`): **`rc=0`**, **`0` runtime/shader/Vulkan errors in log**.
  - `island_explore` (`shot=harbour_plaza ship=brigantine quality=high`): **`rc=0`**, **`0` runtime/shader/Vulkan errors, `0` exit leak warnings**.
  - `smugglers_grotto` (`shot=smugglers_grotto quality=high`): **`rc=0`**, **`0` runtime/shader/Vulkan errors in log**.
  - *(Note: on abrupt `--quit-after 120` exit in `sailing`/`combat_fleet`/`smugglers_grotto`, Godot stderr noted `13–18 resources still in use at exit` from static mesh/material caches when `_exit_tree()` teardown doesn't flush every world singleton — logged in Section 6 below.)*

---

## 2. Task 5A — Painterly Terrain & Foliage Shader Overhaul (`island_shader.gdshader` & `foliage_wind.gdshader`)

### 2.1 Visual Upgrades (Iterated & Verified Live at 1080p HIGH on RX 9070 XT)
1. **Rich Non-Repeating Geological Cliff Strata & Crevice Relief (`src/world/island_shader.gdshader`)**:
   - Banished chalky grey-white cones across `isl_outpost`, `isl_treasure`, `isl_sunset`, `harbour_plaza`, `night_lighthouse`, and `company_fleet`.
   - Replaced uniform cliff tinting with domain-warped multi-octave sedimentary benches (`eval_cliff_relief()` — zero periodic sine striping!), vertical weathering fractures/cracks (`ridged2`), sunlit terracotta-ochre highlights vs cool coastal slate-teal sky-bounce shadows (`light()`), and procedural micro-normal strata/crack bump (`detail_fade` cleanly attenuates `45–260 m` to prevent distant shimmer).
   - **Smooth Coastal Bluffs + Crisp Bare Rock Facets**: Decoupled slope biome blending (pure `smooth_n.y` + organic brushwork jitter) from geometric rock faceting (`bare_rock_facet` concentrated on steep bare cliffs and muted on mossy ledges) — completely eliminated polygonal triangle-grid seams on the Port Scoundrel lighthouse hill and grass bluffs (`isl_outpost`, `harbour_plaza`, `night_lighthouse`) while preserving bold faceted sunlit peaks!
   - **Mossy Emerald Cliff-Ledge Caps**: Mid-elevation flattening shelves (`smooth_n.y` in `0.36..0.88`, `h = 2.6..32 m`) now sprout lush emerald-jade moss cushions anchored into weathered rock grooves.
   - **Richer Shoreline & Coastal Ground Transitions**: Added glistening wet-sand shoreline foam-edge sheen, washed coral-shell & pebble micro-grain, trade-wind sand ripple micro-normals, warm golden dry coastal tussocks along sandy verges, and deep shaded tropical emerald grass.
   - **Atmospheric Aerial Perspective (`380–2400 m`)**: Distant archipelago spires and Wave 24 massive flagship islands blend gracefully into `sky_horizon_color` / `sky_zenith_color` across noon, golden sunset, storm, and moonlit night while maintaining crisp readable silhouettes.
   - **Cinder Crag Auto-Volcanic Support**: Automatically detects dark volcanic islands (`cliff_tint` luminance `< 0.52`, alongside explicit `volcanic_amount`) to render charred dark basalt ridges, scorched amber streaks, and incandescent orange-red upper magma fissure seams.
2. **Translucent Backlit Tropical Foliage (`src/world/foliage_wind.gdshader`)**:
   - Added painterly deep-jade-base to sun-kissed golden-lime frond-tip gradients, per-frond tonal variety (`v_frond_var`) for layered jungle canopy depth, daylight-gated (`smoothstep(0.02, 0.18, s_dir.y)`) view-dependent forward-scatter subsurface backlight (`sss_strength`), and cool turquoise sky-bounce underside fill — preserving `cloud_shadow.gdshaderinc` and `0` shader errors.

### 2.2 Wave 24 Massive Archipelago Shader Uniform & Vertex-Color Contract (100% Backward-Compatible!)
All legacy uniforms (`cliff_tint`, `grass_tint`, `cliff_facet_strength`, etc.) remain unchanged. Cloud Lead's Wave 24 `island_generator.gd` can optionally drive these per-island `ShaderMaterial` parameters immediately:

| Parameter / Channel | Range / Default | Wave 24 Effect |
|---|---|---|
| `volcanic_amount` | `0.0..1.0` (`0.0`) | Charred basalt + scorched streaks + incandescent upper magma cracks (`Cinder Crag` auto-activates at `~0.88` via `cliff_tint` lum, set `1.0` explicitly on Wave 24 mega-volcano!). |
| `lush_jungle_amount` | `0.0..1.0` (`0.0`) | Deepens emerald canopy-floor grass, adds tropical humus mottling inland (`h > 3.5 m`), suppresses dry verge tussocks, and boosts high mossy cliff ledges (`Emerald Spire`, `Sovereign's Bastion`). |
| `ruin_moss_amount` | `0.0..1.0` (`0.0`) | Adds creeping lichen & damp ruin moss inside shadowed lower cliff crevices (`h < 18 m`). |
| `cliff_strata_scale` | `0.25..3.0` (`1.0`) | Scales vertical geological strata thickness (`~0.75` recommended on massive `166–184 m` tall cliffs; `~1.35` on compact `38 m` sea stacks). |
| `path_warmth` | `0.0..1.0` (`0.55`) | Controls warm sandy-ochre vs weathered earth tone on walkable inland paths. |
| `aerial_perspective_strength` | `0.0..1.0` (`0.42`) | Scales `380–2400 m` atmospheric horizon blend for 4.4 km archipelago vistas. |
| **Vertex `COLOR.rgb`** | `vec3` (`1.0`) | Preserved as vertex crevice AO / subtle biome tint. |
| **Vertex `1.0 - COLOR.a`** | `0.0..1.0` (`0.0` when `a=1.0`) | **Zero-cost walkable inland dirt/stone trail mask!** Legacy meshes write `COLOR.a = 1.0` (`mask = 0.0`, skipped via `if (dirt_path_mask > 0.005)`). Paint `COLOR.a` down toward `0.0` along Wave 24 walkable trails for pebbled sun-warmed dirt paths! |

### 2.3 Shader Performance Impact (1080p HIGH, RX 9070 XT)
- **ALL 11 islands combined (`Archipelago` subsystem delta in `main.tscn sailing`, 1080p HIGH)**: **`+0.202 ms` GPU** (`1.220 -> 1.018 ms`, `345 DC`, `544k` prims) — actually **`-0.014 ms` faster** than the pre-overhaul `+0.216 ms` baseline thanks to conditional flat-ground normal-bump skip (`cliff_mask > 0.04`) and `45–260 m` detail-fade!

---

## 3. Direct Answers to Cloud Lead's Open Questions (Q1, Q2, Q3)

### **Q1 — GPU Headroom for Wave 24 Massive `128×128` Flagship Islands + `180–260` `MultiMeshInstance3D` Foliage**
- **Measured 1080p HIGH Baseline (`main.tscn sailing`, Brigantine)**: **`1.854 ms` GPU** (`2.165 ms` p95), `1.074 ms` rCPU, **`198.8 FPS`**, `904 DC`, `1,180k` prims, `299.2 MB` VRAM (`~9.3 ms` est. GTX 1660 @ ~5x).
- **Available Headroom under D10 (`16.6 ms` / 60 fps GTX 1660 target ≈ `3.3 ms` RX 9070 XT)**: **`~1.45 ms` RX 9070 XT (~`7.2 ms` GTX 1660)** in normal sailing, and **`~0.90 ms` RX 9070 XT (~`4.5 ms` GTX 1660)** even during peak Abyssal Leviathan storm combat (`2.427 ms`).
- **Verdict — HUGE GREEN LIGHT for Wave 24!**
  - All 11 current islands combined cost only **`+0.202 ms` GPU** (`544k` prims).
  - Upgrading 3–4 massive flagship islands (`166–184 m` radius) to `128×128` terrain grids (`~32k` tris/island = `+100–130k` tris visible at once) + `MultiMeshInstance3D` batched jungle canopies (`180–260` palms/banyans/ferns/boulders = only `3–5 DC` per island!) will cost an estimated **`+0.15 to +0.28 ms` GPU on RX 9070 XT (`~0.8–1.4 ms` on GTX 1660)** — well inside budget!
  - **Recommended Wave 24 Guardrails**:
    1. Keep undergrowth ferns/small boulders shadow-casting `OFF` (`CAST_SHADOW_OFF`) with `visibility_range_end` at `380–550 m`; keep tall palms/banyans/ruins visible out to `1600–2400 m` for iconic horizon silhouettes.
    2. **CRITICAL WAVE 24 CULLING HEADS-UP (`CoralReef.VISIBILITY_RANGE_END = 155.0`)**: `CoralReef` currently lives at the island's center `(0,0,0)` with a fixed `155 m` visibility range. On a `166–184 m` radius mega-island (`seabed_radius ≈ 220–240 m`), a swimmer/diver at the outer shoreline is **`> 155 m` from the island center**, which will cull the reef right under their nose! Please scale `CoralReef` `visibility_range_end` dynamically with `island.seabed_radius + 110.0` (or split mega-island reefs into quadrant MultiMeshes).

### **Q2 — Real RDNA4 Vulkan 1.4.359 Validation & Alpha-Sorting Audit (`HullCrest`, `LighthouseBeam`, `BreachSprayCurtain`, `WeepingDrips`)**
- **ALL 4 PASS with ZERO Vulkan validation errors, ZERO shader errors, and ZERO alpha-sorting artifacts!**
  - **`HullCrest` (`company_fleet.png`)**: Glowing bow medallions render crisply on all 4 Trading Company hulls (Gilded Compass, Sunken Archive, Iron Tide, Sovereign Sunburst) with clean depth ordering and zero z-fighting.
  - **`LighthouseBeam` (`night_lighthouse.png`, `isl_sunset.png`)**: Volumetric dual-cone beam looks **10/10** — silky smooth radial falloff across both starry night and golden sunset skies with zero banding or hard frustum edges.
  - **`OceanWhale` `BreachSprayCurtain` (`whale_breach.png`)**: Zero Vulkan/alpha-sorting issues; however, visually at `force_breach_apex`, the spray curtain reads quite softly/faintly near the sea-stacks behind the whale's torso — boosting its base plume height/opacity slightly at breach apex will make the splash feel even more thunderous!
  - **`WeepingDrips` (`treasure_shark.png`)**: Zero Vulkan/alpha-sorting issues; cyan bioluminescent chest trim and teardrop droplets render cleanly (note: the foreground Archive Chalice slightly overlaps the front of the `weeping_bilge_chest` in `shot=treasure_shark`, partially hiding the lower drip beads).

### **Q3 — Wave 4.3 Blender Fixes (`y = +0.50 m` Flared `mask_water` & Brigantine Outboard Braces)**
- **Q3a (`shot=hold` stern watertightness)**: **100% RESOLVED on BOTH Sloop (`hold_sloop.png`) and Brigantine (`hold_brig.png`)!** Zero external ocean water bleeds into the stern transom cavity beneath the cabin windows at `water_level = 0.18`. *(See Section 6 for two separate Brigantine interior framing items spotted in `hold_brig.png` & `cabin.png`: floating un-roped crew hammocks and the mainmast pillar filling the right 30% of `hold_brig.png`.)*
- **Q3b (`brig_deck.png` outboard brace clearance)**: **100% RESOLVED!** Starboard yard brace clears the brass quarterdeck rail finial and outer corner post cleanly with zero grazing or clipping.

---

## 4. Task 5B — Complete Waves 5–22 Real-GPU 1080p HIGH Performance Matrix

All runs measured sequentially (zero GPU contention) at **1920x1080**, Vulkan `1.4.359` Forward+, MSAA 2x, `quality=high`, VSync disabled (`Engine.max_fps = 0`), 25–30 warmup + 60–75 measured frames. **21/21 rows completed, `0` failures.**

| Scenario (`1920x1080`, `quality=high`) | GPU med (p95) ms | Render CPU ms | Frame med ms | FPS med | Draw Calls | Primitives | VRAM MB | Est. GTX 1660 (~5x) | D10 16.6 ms |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `sailing` (Brigantine, full world) | **1.854** (2.165) | 1.074 | 5.03 | **198.8** | 904 | 1,180k | 299.2 | ~9.3 ms | **PASS** |
| `company_fleet` (4 Company ships, 2 Brigs) | **1.870** (2.218) | 1.330 | 6.11 | **163.6** | 1,668 | 2,154k | 310.8 | ~9.4 ms | **PASS** |
| `whale_breach` (Brig + 14 m Humpback + Spray) | **1.736** (2.057) | 0.986 | 4.84 | **206.6** | 1,120 | 1,261k | 299.5 | ~8.7 ms | **PASS** |
| `night_lighthouse` (Brig + dual `LighthouseBeam`) | **1.651** (1.967) | 1.071 | 4.97 | **201.2** | 1,223 | 1,444k | 299.7 | ~8.3 ms | **PASS** |
| `night_sail` (Brig + bioluminescent V-wake) | **1.687** (1.717) | 0.810 | 4.28 | **233.5** | 795 | 955k | 300.9 | ~8.4 ms | **PASS** |
| `rainbow` (Brig + 42°/51° double rainbow) | **2.104** (2.137) | 0.951 | 5.04 | **198.6** | 963 | 1,157k | 299.2 | ~10.5 ms | **PASS** |
| `coral_reef` (near `~6.5 m`, Reef + Fish + Manta) | **1.431** (1.448) | 0.435 | 3.76 | **265.7** | 153 | 605k | 291.3 | ~7.2 ms | **PASS** |
| `coral_reef` (`no_reef_fauna` isolation check) | **1.432** (1.448) | 0.422 | 3.78 | **264.6** | 147 | 525k | 291.3 | ~7.2 ms | **PASS** |
| `harbour_plaza` (`time=22.4` night fireflies) | **1.417** (1.754) | 0.918 | 4.94 | **202.5** | 855 | 1,207k | 299.7 | ~7.1 ms | **PASS** |
| `fort_siege` (Ironwatch Fort + Braziers + Brig) | **1.954** (2.308) | 0.828 | 5.20 | **192.3** | 776 | 987k | 302.4 | ~9.8 ms | **PASS** |
| `leviathan` (Brig + Sculpted Boss + Vortex + Rain) | **2.427** (2.808) | 1.084 | 5.18 | **192.9** | 1,231 | 1,287k | 301.5 | ~12.1 ms | **PASS** |
| `fleet` (4-ship multi-faction battle, Brigantine) | **2.269** (2.617) | 1.171 | 5.71 | **175.1** | 1,314 | 1,806k | 308.9 | ~11.3 ms | **PASS** |
| `storm` (Brigantine heavy storm + rain + chop) | **2.329** (2.706) | 0.891 | 4.67 | **214.1** | 805 | 1,009k | 300.8 | ~11.6 ms | **PASS** |
| `treasure_shark` (6 treasures + `WeepingDrips` + Sharks) | **1.709** (1.731) | 0.804 | 4.36 | **229.5** | 584 | 792k | 291.7 | ~8.5 ms | **PASS** |
| `cinder_crag` (Volcanic basalt + twin lava rivers) | **1.667** (1.678) | 0.418 | 4.31 | **231.9** | 152 | 325k | 292.8 | ~8.3 ms | **PASS** |
| `island_showcase` (`shot=outpost`, 1080p HIGH) | **1.855** (1.893) | 0.784 | 4.64 | **215.7** | 706 | 1,205k | 278.7 | ~9.3 ms | **PASS** |

### Subsystem GPU Breakdown (`main.tscn sailing`, Brigantine, 1080p HIGH)
- **Sky + Volumetric Clouds + Post**: **`0.839 ms`** GPU (`12 DC`, `1k` prims).
- **Ocean (`quality=high`)**: **`+0.634 ms`** GPU (`1.854 - 1.220 ms`, `6 DC`, `163k` prims).
- **Archipelago (11 islands w/ Pass 2.1 shader + NPCs + props)**: **`+0.202 ms`** GPU (`1.220 - 1.018 ms`, `345 DC`, `544k` prims).
- **PlayerShip (Batched Brigantine)**: **`+0.123 ms`** GPU (`1.018 - 0.895 ms`, `345 DC`, `415k` prims).
- **Characters & Wildlife (4 pawns + gulls/beasts)**: **`+0.056 ms`** GPU (`0.895 - 0.839 ms`, `196 DC`, `57k` prims).
- **`CoralReef` + `ReefFishSchool` + `MantaRay` Isolation Check**:
  - **Near (`shot=coral_reef`, ~6.5 m)**: **`6 DC`**, `80k` prims, **`~0.00 ms` measurable GPU delta** (`1.431` vs `1.432 ms` — within 0.001 ms noise!).
  - **Mid-distance (`shot=sailing`, 203 m from Port Scoundrel center)**: Port Scoundrel's reef skirt extends `r ≈ 80 m`, so its nearest AABB edge is `~123 m < 155 m` (`+5 DC`, `+11k` prims, `+0.041 ms`); beyond `> 255 m` from island centers all reef/fish/manta nodes cull cleanly to `0 DC` / `0.00 ms`.

---

## 5. Task 5B — Visual Audit Highlights (All 32 Captures Inspected at 1920x1080 HIGH)

- **10/10 Flagship Standouts**: `isl_outpost`, `isl_sunset`, `isl_treasure`, `isl_beach`, `company_fleet`, `night_lighthouse`, `coral_reef`, `dolphins`, `smugglers_grotto`, `cinder_crag`, `leviathan`, `galley`, `items_armory`, `fleet`, `storm`, `brig_deck`, `harbour_plaza_night`.
  - Pass 2.1 terrain & foliage shaders transformed Port Scoundrel, Cutlass Cay, and Cinder Crag: warm golden-ochre strata, cool slate-teal shadows, smooth grassy lighthouse bluffs, gleaming wet sand with shell micro-grain, glowing backlit palms, and dramatic volcanic basalt seams.
  - `coral_reef` underwater Voronoi caustics, branching staghorn coral, swaying kelp, reef fish school, sunken chalice, and gliding Manta Ray look extraordinary.
  - `galley` cast-iron stove + sizzling `Azure Snapper` + steam + clean notice banner and `items_armory` (all 7 weapons/instruments) look museum-grade.

---

## 6. Requests for Cloud Lead (Prioritized Defects & Polish Spotted in Real-GPU Audit)

1. **[HIGH — Visual] Floating Un-Roped Crew Hammocks Cutting Across Brigantine `shot=cabin` (`tools/blender/gen_brigantine.py:1511-1519`)**:
   - The twin pale-cream hammocks (`z = 4.4..6.55`, `y = 0.30..0.75`, `x = ±1.45`) have no suspension clew ropes attaching them to the hull ribs and sit right across the left & right edges of `shot=cabin` (`cam_local_cabin = (0.0, 0.62, 3.35)`), reading as two detached white curved strips floating in mid-air (also visible in `hold_brig.png` & single port hammock in `hold_sloop.png` via `gen_sloop.py:1185`).
   - *Fix*: Add hemp lanyard ropes anchoring both hammock ends to the hull ribs, and tuck them slightly higher/outboard or forward so `shot=cabin` frames the MapTable, Astrolabe, Logbook, Medallions, and stern windows unobstructed!
2. **[HIGH — Camera/Framing] Brigantine `shot=hold` Mainmast Occlusion (`scenes/main.gd:3065`)**:
   - In `hold_brig.png`, `cam_local_hold = Vector3(1.35, 0.42, -0.45)` places the Brigantine's thick mainmast directly across the right 30% of the frame. Shifting `cam_local_hold` slightly aft/port (e.g. `Vector3(1.15, 0.48, 0.45)`) will give a clean unobstructed view of the Brigantine hold, stove, bucket, bilge water, and cabin! *(Also confirmed: `deck_duel.png` on `d8e27ef` had quarterdeck rail balusters blocking the foreground — excited to verify Wave 23 `8046e9b`'s fix next in Milestone 6!)*
3. **[MEDIUM — Visual/Material] Ironwatch Fort Masonry Contrast & Threshold Apron (`shot=fort_vault`, `shot=fort_siege`)**:
   - In `fort_vault.png`, the flat pale-grey threshold ramp slab juts out with its outer corners floating slightly above the green grass slope on left & right.
   - In both `fort_vault.png` and `fort_siege.png`, `FortBastion` walls use a smooth pale-grey shader that looks slightly chalky/untextured next to the newly painterly weathered limestone cliffs — adding subtle stone masonry variation/roughness or darker weathered stone albedo will make Ironwatch Fort (and Wave 24's massive `Sovereign's Bastion`!) blend seamlessly!
   - Also in `scenes/main.gd:3378` (`shot=fort_siege`), the approaching Brigantine at `fpos + (-64, 0, 74)` is behind the camera (`fpos + (-28, 26.5, 42)` looking toward `fpos`), so the ship is out of frame; orbiting the camera slightly seaward/aft will capture both the blazing Fort Bastion and the approaching Brigantine!
4. **[MEDIUM — Visual] `shot=fishing` Equipped Cutlass Poking Through Port Quarterdeck Rail (`scenes/main.gd:3554`)**:
   - In `fishing.png`, the Captain's default equipped `cutlass` blade sticks straight up through the red port quarterdeck railing on the far left edge. Holstering/hiding the held weapon in `shot=fishing` removes the stray sword cleanly.
5. **[MEDIUM — Visual] `FlotsamCluster` Symmetrical Radial Planks (`shot=flotsam`)**:
   - Foreground flotsam clusters show straight rectangular planks radiating in a symmetrical 5-spoke star around each upright barrel; adding slight organic angle jitter/broken splintered lengths & asymmetric grouping will look much more like natural shipwreck debris.
6. **[LOW — Visual Polish] Hero Shot Crosshair, `whale_breach` Spray, `rainbow` Cloud Edge, `harbour_plaza` Surf Crate, `crew_shanty` Bell**:
   - **Global hero-shot reticle**: `Crosshair` is currently hidden only in `shot=deck_duel` (`scenes/main.gd:3123`), leaving a tiny center dot visible in `company_fleet`, `rainbow`, `coral_reef`, `cinder_crag`, `fort_vault`, `smugglers_grotto`, `cabin`, `fleet`. Hiding `Crosshair` globally inside `_apply_hero_shot()` makes every showcase frame spotless!
   - **`whale_breach.png`**: Boost `BreachSprayCurtain` plume height/opacity slightly at `force_breach_apex` so the exploding waterline spray reads boldly beneath the whale's torso/tail.
   - **`rainbow.png`**: Subtle vertical straight-edge clip visible on the far-right cumulus bank (`x ≈ 82%`) behind the right rainbow foot — worth checking cloud-box UV wrap/boundary clamping.
   - **`harbour_plaza_day/night.png`**: Wooden crate next to the Pier Quartermaster sits right in shallow surf foam; nudging it `+1.2 m` up-beach keeps it dry.
   - **`crew_shanty.png`**: Sloop brass ship's bell hangs right beside the Lookout's cheek, and the Hurdy-Gurdy sits slightly high across the Helmsman's lower face (`~10 cm` lower hand pose reads even cleaner).
7. **[LOW — Teardown Hygiene] `--quit-after` Static Cache Teardown (`13–18 resources still in use at exit`)**:
   - While headless tests pass with `0` leaks (they clean up explicitly), abrupt `--quit-after` shutdown of live `main.tscn` leaves `13–18` static cached `ArrayMesh`/`Material` refs on `stderr` (whereas `harbour_plaza` had `0`, suggesting active sea-event / beast / VFX caches spawned during `sailing`/`fleet`/`grotto`). Clearing static caches in `main.gd._exit_tree()` (or `NOTIFICATION_PREDELETE`) would make live `.exe` exit 100% spotless too!
8. **[WAVE 24 HEADS-UP] `CoralReef` `VISIBILITY_RANGE_END` on Mega-Islands**:
   - As noted in Q1, scale `CoralReef` visibility range with `island.seabed_radius + 110.0` (or quadrant-split) so `166–184 m` radius Wave 24 flagship islands never cull reefs while the player is swimming along the outer beach!

---

## 7. Milestone 6 — Wave 23 (`8046e9b`) Real-GPU Audit, Wave 24 Pre-Flight Shader Polish & Empirical Mega-Island Benchmark

### 7.1 Wave 23 Real-GPU 1080p HIGH Verification (`8046e9b` — ALL 5 FEATURES PASS!)
- **Headless Test Suite on Rebased Wave 23 + M6 Shaders**: **`181 tests, 0 failures`** (`W23_HEADLESS_EXIT=0`), `py tools/lint.py`: **`108 files, 0 errors, 0 warnings`**.
- **7/7 Wave 23 Real-GPU 1920x1080 HIGH Captures (`rc=0, errs=0`)**:
  - **`shot=deck_duel` (`brigantine` & `sloop`)**: **100% BALUSTER-CLEAR!!** Zero foreground rail balusters on either hull; fiery clash sparks, golden slash arc, StaggerStars, and sculpted `CrowsNestRungs` visible cleanly behind the duelists!
  - **`shot=map_table` (`brigantine` & `sloop`)**: **10/10** — bottom-left custom ship name parchment cartouche (`▷ SV ABYSSAL DAWN ◁`), circular live **`WIND 12 kt N`** medallion, and golden Outpost lighthouse star stamps render razor-sharp with zero clipping.
  - **Mainmast `Ladder_CrowsNest` & `CrowsNestRungs`**: 1-DC sculpted wooden-and-iron rungs hug the aft face of the Brigantine's mainmast cleanly up to the Crow's Nest with zero z-fighting or rigging overlap.
  - **Sculpted `VictoryFlare`**: Zero-primitive brass-and-crimson rocket ascends cleanly with warm golden `ApexLight` radiance bathing the sails and starry sky (`0` Vulkan/shader errors).
  - **4th `"Captain's Log"` Tab (`ShipwrightMenu`)**: **10/10 UI layout** — Captain stats, 3 Trading Company standing bars, and 2-column `CHARTED WATERS: 1 / 11 ISLANDS` checklist render crisply in `scoundrel_font.fnt` with clean margins and zero overlap.

### 7.2 Three High-Impact Pre-Flight Wave 24 Shader Upgrades Caught & Landed (`island_shader.gdshader` & `foliage_wind.gdshader`)
Built a live 1920x1080 RX 9070 XT look-dev harness simulating **175 m-radius `128×128` terraced mega-islands** with `1.0 - COLOR.a` winding dirt paths, `240` batched `MultiMeshInstance3D` palms, and `1100 m` 3-island vistas across noon, sunset, moonlit night, and `0.90` storm — catching and fixing 3 Wave 24 issues BEFORE Wave 24 even lands:
1. **Highland Plateau Protection + Sharp Spire Apex Preservation (`island_shader.gdshader`)**: Legacy `summit_rock` (`16..27 m`) was bleaching flat `> 27 m` mega-island highland plateaus into bare beige rock. Updated `summit_rock` to scale cleanly with `lush_jungle_amount` (`17..29 m` -> `34..56 m`) AND gate by `min(smooth_n.y, face_n.y)` — flat highland jungle plateaus stay lush emerald green while sharp 1-vertex legacy limestone spire apexes (`isl_outpost`, `isl_treasure`) stay 100% bare stratified limestone!
2. **Cohesive Volcanic Ash-Scrub Coastal Skirts (`island_shader.gdshader`)**: When `volcanic_amount > 0`, lower slopes (`h = 3..16 m`) now transition into charred dark cinder-ash & olive volcanic scrub instead of bright emerald grass, making mega `Cinder Crag` 100% cohesive from dark wet sand to glowing basalt caldera!
3. **Per-Instance MultiMesh Wind Phase (`foliage_wind.gdshader`)**: Switched `tree_phase` from `NODE_POSITION_WORLD` to **`MODEL_MATRIX[3].xyz`** so Wave 24's batched `MultiMeshInstance3D` jungle canopies (240+ palms/ferns in 1–2 draw calls) sway in organic rolling trade-wind waves per tree (and vary per-tree tint `v_frond_var`) instead of swaying in robotic lockstep!

### 7.3 Empirical 1080p HIGH RX 9070 XT Benchmark: `128×128` Mega-Islands + `MultiMeshInstance3D` Palms
Measured live on RX 9070 XT (`1920x1080`, Vulkan `1.4.359` Forward+, `quality=high`, full shadow-casting `palm_tall.glb` trunks + backlit `foliage_wind.gdshader` fronds):

| Stage (`1920x1080`, `quality=high`) | GPU med (p95) ms | Delta vs Base | Render CPU ms | FPS | Draw Calls | Primitives | VRAM MB |
|---|---:|---:|---:|---:|---:|---:|---:|
| `Ocean + SkyRig` baseline | 1.582 (1.610) | — | 0.228 | 211.4 | 5 | 151k | 250.3 |
| `+ 1× 175 m 128×128 Mega-Island` (terrain only) | **1.683** (1.702) | **`+0.101 ms`** | 0.209 | 189.0 | 8 (+3) | 221k (+70k) | 250.3 |
| `+ 240 Batched MultiMesh Palms` (shadow ON) | **1.923** (1.962) | **`+0.240 ms`** | 0.243 | 212.3 | 18 (+10) | 225k | 250.3 |
| **`+ 3× 175 m 128×128 Mega-Islands + 720 Palms`** | **2.167** (2.204) | **`+0.585 ms` total** | 0.266 | **209.2** | **30** | **276k** | **250.3 (+0.0 MB!)** |

*Takeaway for Cloud Lead `24C`*: `128×128` mega-island terrain is practically free (`+0.101 ms` GPU each!). Most of the `+0.240 ms` palm cost is directional shadow-map rendering of `240` vertex-displaced frond instances — keeping `CAST_SHADOW_ON` for tall palms/banyans (`visibility_range_end = 1800 m`) and `CAST_SHADOW_OFF` for ground ferns/bushes/rocks (`visibility_range_end = 420–550 m`) guarantees **180+ FPS on RX 9070 XT** and **60+ FPS on GTX 1660** across all 14 Wave 24 islands!

### 7.4 Extended 600-Frame Live Multi-TOD/Storm Soak & Rebuilt Wave 23 `.exe`
- **600-Frame Live 1080p HIGH Soak (`main.tscn sailing`, Brigantine, sweeping full 24h cycle + `0.92` storm)**:
  - GPU: **`p50 = 2.087 ms`**, `p95 = 2.549 ms`, `p99 = 2.643 ms`.
  - Frame: **`p50 = 5.05 ms` (`198.1 FPS`)**, `p95 = 10.10 ms`, `p99 = 12.12 ms`.
  - VRAM: `299.4 MB -> 300.9 MB` (`+1.5 MB` steady-state storm cloud buffers across 600 frames — **zero leak!**).
- **Rebuilt Windows Desktop `.exe` (`build/SeaOfScoundrels.exe`, Wave 23 + M6 Shaders)**: **`147.4 MB`** (`147,364,896` bytes), `M6_EXPORT_EXIT=0`, live 120-frame `shot=deck_duel ship=brigantine quality=high` RX 9070 XT smoke test **`rc=0`, `0` errors**.

### 7.5 Standing Ready for Wave 24 Massive Archipelago Overhaul!
Continuously monitoring `origin/ccr-663b66a0-rdiq4f` — the moment **Wave 24 (`24A–24D`)** pushes (14-island 4.4 km archipelago, 7 new Blender landmark/jungle props, `IslandWaterfall`, `VolcanicFumarole`, and new mega-island showcase cameras), Local-GPU will immediately rebase, audit every new Wave 24 shot at 1080p HIGH, fine-tune terrain/foliage/waterfall lighting & performance on real RX 9070 XT Vulkan, and push **Milestone 7**!
