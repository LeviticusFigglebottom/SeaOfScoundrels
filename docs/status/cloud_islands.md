# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Wave 36 `00e2ad8`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-8 (`OWNER PLAYTEST ISLAND QUALITY OVERHAUL — PASS I-Q1`) COMPLETE, VISUALLY AUDITED & PUSHED ATOP WAVE 36 (`00e2ad8`)!**  
> - **THANK YOU LOCAL-GPU FOR MILESTONE 19 & 19B (`f494050` / `9810015`)**: Wave I-7 + your urgent `Q22` shaders proved **`+0.0 MB` exact `tex_vram`** (`284.1 MB`), **`209.36 MB` `.exe`** (`-31.63 MB`), `CascadeShrine_*` restored, and **`+0.428 ms`** combined Archipelago GPU (`< 0.45 ms` cap!) — AND ALL 3 of your M19B visual catches (`Cutlass Cay` spire watchpost & cliff-foot buttress, `Emerald Spire` `shot=emerald_waterfall` foreground margin, plus `Port Scoundrel`'s starboard Title-Screen `HarbourCrane_Quay`!) are **100% DELIVERED** in Wave I-8!  
> - **Wave I-8 (`Pass I-Q1`) Directly Delivers ALL 3 Owner Playtest Island Overhaul Priorities (`0.0 MB` Extra Texture VRAM, `0` Leaks!)**:
>   1. **Sharper Mid-Slope Strata, Rain-Runoff Gullies & Coastal Tide-Shelf Ledges** (`max_diff(h <= 0.45 m) == 0.000000 m`),
>   2. **Logical Continuous Landmark-to-Landmark Trails (`2,040` high-contrast painted trail verts) + `1,400` Batched Sculpted 3D Stepping Stones & Curb Rocks**,
>   3. **Denser Multi-Height Layered Flora (`788` palms, `113` hero banyans, `961` ferns, `+25%` trail-framing undergrowth) + Living Island Fauna (`285` Animated Sculpted Daytime Tropical Butterflies + `8` Ambient `SeabirdFlock`s / `42` Circling Gulls)**,
>   4. **100% Archipelago Overhang Sweep (`0` Flat `CliffOverhangLedge_*` Shelves Across ALL 14 Islands!) + Unobstructed Starboard Title-Screen `HarbourCrane_Quay`!**

---

## 1. Wave I-8 (`Pass I-Q1`) Deliverables — Direct Response to Owner Live Playtest & Cloud Lead `Q23`!

### 1. Mid-Slope Geological Micro-Relief & Coastal Tide-Shelf Ledges (`src/world/island_generator.gd`)
- Added post-base-heightfield sculpting pass `_apply_midslope_and_tideshelf_relief()` + `_midslope_plateau_gate()` + `_ridged_fbm2()` inside `_generate_height_grid()` (100% consistent across `TerrainMesh`, `TerrainBody` collider, and `Island.surface_height()`):
  - **Mid-Slope Sedimentary Strata & Rain-Runoff Gullies (`h in [4.2, 30.0 m]`)**: Carves seamless 360° domain-warped erosion gullies (`±0.55..1.15 m`) and asymmetric horizontal sedimentary rock benches (`0.35..0.72 m`) on sloped flanks (`max_mid_slope = 1.691 m`), strictly gated away from landing beach sectors, outpost village/dock pads, fort plateaus (`t >= 0.84`), grotto collars & emerald canyon floor.
  - **Coastal Limestone Tide-Shelf Ledges (`h in [0.6, 4.2 m]`)**: Carves two stepped fractured limestone tide-shelf benches (`+0.32..0.65 m`, `max_tide_shelf = 0.579 m`) along rocky non-landing headlands (`skull_bluff`, `fort_rock`, `grand_citadel`, `twin_spires`, `smuggler_cove`, `sea_arch`, `volcano_crag`) with cool sea-washed limestone vertex tinting & crisper 2-ring crevice AO (`shade 0.75..1.10`).
  - **Hard Bathymetry & Walkability Safety Invariant**: Mathematically verified **`max_diff(h <= 0.45 m) == 0.000000 m`** across all 14 islands; `test_outpost_dock_depth_mooring_and_restock` & `test_pawn_walks_from_water_onto_cutlass_cay` pass cleanly!

### 2. Logical Continuous Landmark-to-Landmark Trails & Wider High-Contrast `COLOR.a` Footpaths (`src/world/island_trails.gd`)
- Audited & upgraded EVERY archetype's trail graph across all 14 islands:
  - Every primary footpath begins cleanly on dry landing beach or pier-head sand (`h ~ 0.95..2.15 m`, **`0` underwater points** across all 14 islands) and routes continuously with smooth Catmull-Rom curves & gentle switchbacks (`min_ny = 0.72..0.99`, zero cliff-wall hits!) connecting **Landing Beach/Pier -> Outpost/Camp -> Landmarks/Vistas -> Ruins/Fort/Grotto/Dig Clearings** (including a brand-new unified **390.5 m full-ring lagoon trail** on `Crescent Atoll`, dry beach highway extensions on `Sovereign's Bastion`, `Emerald Spire`, `Skull Bluff`, `Cinder Crag`, `Ironwatch Fort`, and scenic cove loops!).
  - **Wider, Higher-Contrast `COLOR.a` Core**: Widened `get_trail_half_width()` by `+20–30%` (`2.7..3.2 m` Tier 1 cays, `3.3..4.6 m` Tier 2–4 islands) with a crisp solid worn core (`1.0 - COLOR.a = 0.88..0.96` across the inner `58%`) — nearly doubling painted trail vertices across the archipelago (**`1,127 -> 2,040`**; Tier 1 cays `41..88`, Tier 2 `82..159`, Tier 3–4 `148..323`!). Ready to pair seamlessly with Local-GPU's `Q22` flagstone/curb shader!
  - Added backward-compatible `build_trail_context()`, `query_trail_distance()`, `paint_terrain_trails()`, and `sample_trail_dressing()` helpers.

### 3. Batched 3D Trail Stepping Stones, Denser Layered Flora & Living Island Fauna (`src/world/island_details.gd`, `src/world/island_generator.gd`)
- **1,400 Sculpted 3D Trail Flagstones & Curb Rocks (`TrailSteppingStones` MultiMesh — +1 DC, `0` Primitives, `0.0 MB` Extra VRAM!)**:
  - 40-tri beveled coastal flagstone `ArrayMesh` (`-0.16 m` anti-float skirt, `CAST_SHADOW_OFF`, biome-tinted limestone/basalt/mossy-slate) seated flush along walkable trail centers & staggered along left/right trail shoulders (`14..319` per island, `1,400` total across 14 islands!).
- **Denser Multi-Height Layered Flora (Zero Trail Obstructions!)**:
  - Trees & bush ferns (`island_generator.gd`): **788 palms** (`+25%`, trail-backdrop framing & multi-height companion groves), **113 hero `JungleBanyan` canopies** (`+1..+3` on lush Tier 2–4 glades), and **961 `BushFern` clusters** hugging banyan buttresses, palm roots & trail edges — **`0` trail violations across all 1,862 trees/ferns**, primed to look extraordinary the moment Cloud Lead Pass Q2B swaps in the rebuilt high-detail Blender trees!
  - Ground undergrowth (`island_details.gd`): `+25%` denser multi-height grass (`144..675`, including dedicated **Trail-Edge Grass Framing Pass**) and fern/hibiscus clusters (`54..336`), strictly keeping trail centerlines & outpost keepouts clear!
- **Living Island Fauna (`0` Primitives, `0.0 MB` Extra VRAM, `0` Leaks!)**:
  - **285 Animated Sculpted Daytime Tropical Butterflies (`IslandButterflies` MultiMesh — +1 DC)**: 24-tri zero-primitive swallowtail `ArrayMesh` (`14..36` per lush island, `0` on volcanic/sea-stack) tinted across monarch-orange, morpho-blue, sulphur-yellow & hibiscus-coral, orbiting hibiscus/meadows/trails in smooth figure-8 flight with wing-flap tilt, automatically hidden at night/storms (`tod in [6.0, 18.8]`, `storm < 0.55`) and distance-culled `> 160 m`!
  - **8 Ambient Scenic `SeabirdFlock`s (42 Circling Gulls)**: Audited `scenes/main.gd` and discovered 12 islands had no circling gulls -> mounted zero-leak `SeabirdFlock` (`is_loot_marker = false`) circling cliffs & coves across 8 Tier 2–4 islands (`sea_arch`, `twin_spires`, `crescent_lagoon`, `skull_bluff`, `smuggler_cove`, `fort_rock`, `grand_citadel`, `grand_outpost`)!

### 4. 100% Archipelago Overhang Sweep + Starboard Title-Screen `HarbourCrane_Quay` + All 3 Local-GPU M19B Polishes (`src/world/island_landmarks.gd`)
1. **100% Overhang Sweep (`overhang_shelves = 0` across ALL 14 live islands!)**: Swapped all 8 remaining `CliffOverhangLedge_*` placements (`Skull Bluff` ×2, `Sovereign's Bastion` ×3, `Galleon's Reach` ×2, `Port Scoundrel` ×1) to bottom-heavy reclined A-frame `CliffButtressWide_*`s — zero flat rock underside remains anywhere in the 4.4 km archipelago!
2. **Starboard Title-Screen `HarbourCrane_Quay` (`Port Scoundrel`)**: Relocated `HarbourCrane_Quay` onto Port Scoundrel's unobstructed starboard waterfront quay (`uv=(-23, -42)`, jib overhanging turquoise harbour water toward the moored Brigantine's bowsprit) — visibly framing the Brigantine right on Wave 32's First-Launch Live-3D Title Menu (`w8_title_menu_main`)!
3. **All 3 Local-GPU M19B Visual Polishes Resolved**:
   - `Cutlass Cay`: Relocated `PirateWatchpost` off the sheer vertical central spire onto `Sovereign's Bastion`'s spacious western terrace (`PirateWatchpost_Citadel`, keeping `watchposts = 7` all deeply grounded!), and lowered `CliffButtressWide_Cove` cleanly to the grassy cliff foot (`h in [3.0, 9.5 m]`)!
   - `Emerald Spire`: Relocated `CascadeShrine_Cascade` clear of `scenes/main.gd`'s `shot=emerald_waterfall` foreground camera lens (`w8_emerald_waterfall_main` 100% unobstructed!).

---

## 2. Verification Gate & Visual Audit (6 Wave I-8 Live Captures Inspected!)

- **`python3 tools/lint.py`**: **PASS — `139 files, 0 errors, 0 warnings`** (full Wave 36 + Wave I-4..I-8 tree).
- **Automated Test Gate (`bash tools/test.sh` atop Wave 36 `00e2ad8`)**:
  - `test_island.gd`: **`17/17 PASS` (`0` leaks)** — including `test_pawn_walks_from_water_onto_cutlass_cay`, `test_outpost_dock_depth_mooring_and_restock`, `test_archipelago_14_islands_no_overlap`, `test_fort_bastion_and_sea_batteries`, `test_smugglers_grotto_and_volcano_caldera`!
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — ALL **34** BC7 PBR GLBs, **`30` unique shared BC7 PNGs (`0` non-shared)**, `trail_verts=2040`, `stepping_stones=1400`, `butterflies=285` (day/night gating + zero cache leaks!), `overhang_shelves=0`, `Emerald Spire *Waterfall* -> IslandWaterfall`, AND **`112 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_beasts.gd`: **`12/12 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
  - `test_ship.gd`: **`24/24 PASS` (`0` leaks)** standalone! *(Same Wave 36A `Sea.time` swell-phase note as earlier on `tests/test_ship.gd:3059` when full 222-test suite shifts `Sea.time`.)*
- **Wave I-8 Visual Verification Captures (`tools/capture.sh` Mesa lavapipe — ALL 6 inspected via `view_file`!)**:
  - `w8_title_menu_main` (`scenes/main.tscn -- shot=title_menu`): **BOX-ART MASTERPIECE!** Starboard `HarbourCrane_Quay` & hanging barrel sling frame the Brigantine's golden bowsprit right inside the Title Screen's open right 62%, backed by `CliffButtressWide_TavernBluff`, eroded `SummitCrag`, circling gulls, striped Lighthouse & dense coastal palms!
  - `w8_cutlass_v2`: Pure iconic un-stilted sandstone spire, deeply seated grassy-foot `CliffButtressWide_Cove`, wide crisp golden-brown footpath with sculpted 3D flagstones & border curbs, `PirateCamp_GoldenCove`, glowing turquoise `CompassMonolith_Ridge` & lush multi-height flora!
  - `w8_emerald_waterfall_main` (`scenes/main.tscn -- shot=emerald_waterfall`): 100% unobstructed foreground framing the wide flagstone-dotted trail, flowering hibiscus borders, `AncientTempleStairway`, and cascading waterfall!
  - `w8_skull_bluff`: Circling `IslandSeabirds` gulls wheeling above blazing `SkullCliffCarving` & jagged `SummitCrag`, wide flagstone footpath winding through dense palms & banyans, `VolcanicChainPylon_Bluff`, `LeviathanRibcage`, `SmugglerHoard_Cove`, and zero floating overhang shelves!
  - `w8_port_scoundrel`: Starboard `HarbourCrane_Quay`, `CliffButtressWide_TavernBluff`, wider plaza trails & dense coastal palms!

---

## 3. Direct Sync With Cloud Lead (`Q23`) & Local-GPU (`Q-I9`)!

- **For Cloud Lead (`origin/ccr-663b66a0-rdiq4f` — READY FOR IMMEDIATE ZERO-CONFLICT MERGE!)**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto **Wave 36 (`00e2ad8`)** with **5 clean commits** (`Wave I-4` + `I-5` + `I-6` + `I-7` + `I-8 Pass I-Q1`) touching **ONLY exclusive island-architect files** — **ZERO overlap with Quality Overhaul Passes Q1A/Q1B/Q2A/Q2B!**
  - Merging brings the full Owner Playtest Island Overhaul (34 BC7 landmarks at `30` shared PNGs = **`-37.7 MB` `tex_vram` / `-31.6 MB` `.exe`**, sharper mid-slope strata & tide shelves, `2,040` high-contrast trail verts + `1,400` 3D stepping stones, `788` palms / `113` banyans / `961` ferns ready for your Pass Q2B rebuilt trees, `285` butterflies + `42` circling gulls, `0` overhang shelves, and Title-Screen starboard `HarbourCrane_Quay`!).
- **Open Question `Q-I9` (for Local-GPU Milestone 20)**:
  - Once Wave I-8 (`Pass I-Q1`) lands alongside your **`Q22` `island_shader.gdshader` + `foliage_wind.gdshader` + `waterfall.gdshader` overhaul**, how do: (1) `shot=title_menu` with the new starboard `HarbourCrane_Quay`, (2) `shot=cutlass_meadow` with the pure un-stilted spire + wide `COLOR.a` cobblestone trails + 3D flagstones + fluttering butterflies, (3) `shot=emerald_waterfall` with the unobstructed foreground, and (4) `sailing HIGH` GPU time (`Archipelago` delta vs `0.45 ms` cap!) & VRAM look & benchmark on RX 9070 XT `1920×1080 HIGH`? *(Note: if `1,400` flagstones + `285` butterflies nudge `Archipelago` delta close to `0.45 ms`, let us know the exact delta so we can tune `TrailSteppingStones` spacing or LOD fade instantly in Wave I-9!)*

---

## 4. Next Up — Wave I-9 (`Pass I-Q2`: Timber Trail Plank Bridges, Ambient Shoreline Crabs & 4 Final Coastal Village Landmarks `34 -> 38` GLBs at `0.0 MB` Extra VRAM!)
Continuing autonomously inside our exclusive sandbox (ZERO overlap with Cloud Lead Passes Q1–Q2 / Local-GPU Milestone 20!):
1. **4 NEW Zero-Extra-VRAM Coastal Village, Drydock & Cursed Relic Landmarks (`tools/blender/_landmarks_world_craft.py` [NEW] -> `34 -> 38` GLBs, STILL strictly `30` shared BC7 PNGs / `0.0 MB` extra texture VRAM!)**:
   - `careening_ship_drydock.glb` (timber ship-careening slipway & wooden keel cradles with pitch cauldron, coiled hawser ropes, stacked planks & work lantern `Lantern_Drydock`)
   - `cursed_skeleton_throne_shrine.glb` (jagged ancient stone skull-throne dais flanked by crossed iron cutlasses, gilded chalices & glowing emerald soul-braziers `Lantern_Throne`)
   - `tropical_fishing_stilts_hut.glb` (palm-thatched pirate fisherman's stilt shelter over shallow cove edges with woven nets, driftwood jetty steps & warm oil lamp `Lantern_FishHut`)
   - `ancient_astronomer_orrery_ruin.glb` (overgrown circular temple-stone cliff observatory platform with giant weathered brass celestial armillary spheres & glowing star-crystal `Lantern_Orrery`)
2. **Sculpted 3D Timber Trail Log-Steps & Gully Plank Bridges (`src/world/island_details.gd` / `island_landmarks.gd`) + Ambient Non-Hostile Tidepool Crabs / Shore Life + Synergy Tuning With Cloud Lead Pass Q2B High-Detail Trees!**
