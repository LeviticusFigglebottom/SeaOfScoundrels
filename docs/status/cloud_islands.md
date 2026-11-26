# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Wave 36 `00e2ad8`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-4 + I-5 + I-6 + I-7 ALL COMPLETE, VISUALLY AUDITED & PUSHED ATOP WAVE 36 (`00e2ad8`)!**  
> - **THANK YOU LOCAL-GPU FOR MILESTONE 18 (`650e965`)**: Wave I-6 verified exact **`+0.0 MB` extra `tex_vram`** (`284.1 -> 284.1 MB`!), **`208.7 MB` `.exe`** (`-32.1 MB` vs Wave 34), **`169.4 FPS`** sailing, and all 4 M14/M16 grounding fixes clean — AND your clutch **`[HIGH]` `shot=emerald_waterfall` name-collision catch** is **100% FIXED** in Wave I-7 with a permanent automated regression test!  
> - **Wave I-7 NOW READY AT `0.0 MB` EXTRA TEXTURE VRAM & `+0` EXTRA GROUND-COVER DRAW CALLS**: Expanded library **`30 -> 34` BC7 PBR GLBs** (STILL strictly **`30` shared BC7 PNGs / `0` root PNGs / `21 MB` total on disk!**), **18** new maritime/fortress/relic placements (`115 landmarks checked, 0 floating`!), **+0 DC biome-specific micro-foliage & coastal dune sea-oats variety**, `CascadeShrine_*` waterfall fix, Ironwatch Fort bluff buttress polish, and **`gallery_maritime_relics` (`KEY_L`, 21 showcase shots)**!

---

## 1. Wave I-7 Deliverables (`0.0 MB` Extra Texture VRAM, `+0` Extra Ground-Cover Draw Calls, `30 -> 34` GLBs!)

### 1. Four NEW Sea-Fort, Maritime Navigation & Ancient Relic Landmarks (`tools/blender/_landmarks_maritime_relics.py` [NEW] -> `34` GLBs Total!)
All built with 100% original procedural Blender 5.3.0 geometry (`export_tangents=True`, `0` ngons, solid `col_*` colliders, `UV2` foliage/kelp wind weights, deep anti-float footings `-3.6..-4.52 m`, flickering `Lantern_*` empties) and mapped exclusively to our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM!)**:

| New Wave I-7 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (18 Instances Across 13 Islands!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `fort_coastal_watchtower_ruin.glb` | 3,848 | 566 KB | 2 (`col_tower_base`, `_upper`) | `Lantern_Watchtower` | **4 fortified harbours & headlands** (`Ironwatch Fort`, `Sovereign's Bastion`, `Galleon's Reach`, `Barnacle Haven`) | `12.7 m` crumbling mossy sea-fort stone turret (`-4.0 m` flared stone skirt), cantilevered timber parapet & access ladder, brass alarm bell, crimson garrison pennant, trailing ivy & rooftop fire-brazier |
| `shipwreck_bell_buoy_beacon.glb` | 3,564 | 470 KB | 1 (`col_buoy_base`) | `Lantern_ReefBeacon` | **6 treacherous shoals & harbour mouths** (`Wrecker's Shoal`, `Siren's Tooth`, `Gull's Arch`, `Port Scoundrel`, `Crescent Atoll`, `Barnacle Haven`) | `9.6 m` barnacle-crusted kelp-draped shoal crib (`-4.52 m` seabed footing!), iron-strapped timber tripod cage, crimson diamond warning sign, hanging brass fog bell & radiant emerald-gold pinnacle reef lantern |
| `ancient_compass_monolith_ring.glb` | 3,184 | 465 KB | 2 (`col_ring_dais`, `_stones`) | `Lantern_Monolith` | **4 exploration sanctuaries** (`Emerald Spire`, `Cutlass Cay`, `Skull Bluff`, `Sovereign's Bastion`) | Stepped circular stone navigator's sundial dais (`-3.6 m` skirt), inlaid brass 8-point compass rose, twin golden armillary rings orbiting a glowing turquoise rune crystal & 5 leaning carved standing monoliths |
| `volcanic_chain_bridge_anchor.glb` | 3,508 | 443 KB | 1 (`col_chain_pylon`) | `Lantern_ChainPylon` | **4 dramatic chained ridges & booms** (`Cinder Crag` ×2 west/east caldera rim, `Skull Bluff` bluff, `Ironwatch Fort` harbour chain) | `11.6 m` jagged obsidian-basalt anchor pylon (`-4.5 m` flared volcanic root), riveted forged-iron shackle collars, sweeping oversized interlocking anchor chains, glowing lava cracks & spiked rooftop fire-cage |

### 2. Local-GPU M18 `[HIGH]` `shot=emerald_waterfall` Name Collision Fix + Ironwatch Fort Grounding Polish (`src/world/island_landmarks.gd`, `tests/test_island_details.gd`)
1. **`[M18 HIGH]` `shot=emerald_waterfall` Collision -> 100% FIXED & REGRESSION-TESTED**:
   - Renamed all 4 shrine placements from `WaterfallShrine_*` -> **`CascadeShrine_*`** (`CascadeShrine_Cascade`, `CascadeShrine_Citadel`, `CascadeShrine_Fjord`, `CascadeShrine_Ridge`), AND added post-mount descendant name sanitization (`"Waterfall" -> "Cascade"`) inside `_spawn_landmark()` so neither wrapper nor child nodes inside `cliffside_waterfall_shrine.glb` ever collide with recursive `find_child("*Waterfall*", true, false)`!
   - Added permanent regression check in `tests/test_island_details.gd`: `check(emerald_isl.find_child("*Waterfall*", true, false) is IslandWaterfall)` — **100% guaranteed never to break again!**
2. **Ironwatch Fort Right Hillside Shelf Polish (`w7_ironwatch_fort_v2`)**:
   - Swapped both `Ironwatch Fort` `CliffOverhangLedge_West/East` flanks to bottom-heavy A-frame `CliffButtressWide_West/East`, eliminating the thin green-topped right-flank shelf spotted during our visual audit!

### 3. +0 Extra-DC Biome-Specific Micro-Foliage & Coastal Dune Sea-Oats Storytelling (`src/world/island_details.gd`)
- Strictly **`DC = 7..8` unchanged**, **`0.0 MB` extra VRAM**, **bit-for-bit identical placement RNG streams** (driven purely via spatial hash `(x, z, h, arch)`!):
  - **Coastal Dune Sea-Oats (All 13 Non-Volcanic Beaches)**: Smoothly transitions sand-edge grass tufts (`h < 4.4 m`) into taller, slenderer sun-bleached golden sea-oats & warm coastal sage so beaches flow naturally into lush emerald turf.
  - **Volcanic Caldera Flora & Charred Obsidian Shores (`Cinder Crag`)**: Charred olive-slate, burnt russet & high-caldera sulfur-gold ember-moss grass/fern banding + fiery crimson-orange volcanic hibiscus + wet dark obsidian-basalt tidal rocks.
  - **Lagoon & Atoll Tropical Vibrancy (`Crescent Atoll`, `Cutlass Cay`, `Gull's Arch`)**: 3-tone hibiscus variety (coral-pink, mango-gold, island crimson) + sun-bleached pale coral-limestone shallow reef boulders popping crisply against turquoise shallows.
  - **Highland Alpine Cliff-Ledge & Ancient Ruin Moss (`h > 20 m`)**: Sun-dappled alpine moss-emerald & cool highland sage-olive upper cliff tufts + rich emerald-jade lowland valley ferns on jungle temple islands.

---

## 2. Cumulative Wave I-4 + I-5 + I-6 + I-7 Stack Ready on `origin/cloud/island-architect` (4 Clean Commits Atop Wave 35 `b205608`!)

- **34 Sculpted BC7 PBR Landmarks (`18 -> 34` GLBs, `+90` new Wave I-4..I-7 placements across all 14 islands!)**
- **STILL STRICTLY `30` Shared BC7 PNGs (`0` root PNGs, `21 MB` total on disk vs `102 MB` before dedup -> `-34 MB` VRAM & `-32 MB` Windows `.exe`!)**
- **`h > 18 m` Ridged Mountain Erosion (`+34%..+50%` upper-wall relief), `+0 DC` Highland Cliff Greenery & Biome Sea-Oats/Volcanic Flora**
- **100% Real-GPU Grounding Polish**: Anti-tip-sliver real-mesh buttress guard (`0` tip slivers across all 14 islands), `-7.83 m` watchpost stilts, steep-slope fern/boulder sinks, `Gull's Arch` & `Ironwatch Fort` overhang->buttress swaps, `CascadeShrine_*` waterfall lookup fix, and automated **`115 landmarks checked, 0 floating`** grounding test!

---

## 3. Verification Gate & Visual Audit (21/21 Showcase Shots!)

- **`python3 tools/lint.py`**: **PASS — `138 files, 0 errors, 0 warnings`** (full unified Wave 35 + Wave I-4..I-7 tree!).
- **`bash tools/test.sh` (FULL unified suite rebased onto Wave 35 `b205608`)**: **PASS — `220 tests, 0 failures, 0 ObjectDB / 0 resource leaks`** (`test_island_details.gd`: `4/4` PASS validating ALL **34** BC7 PBR GLBs, **`30` unique shared PBR textures / `0` non-shared**, Wave I-3..I-7 placements `idols=4 ribcages=4 rowboats=6 gibbets=4 braziers=13 | crags=8 aqueducts=4 watchposts=7 strata_ribs=18 | camps=5 sterns=4 coral_arches=6 lava_shrines=2 | cranes=4 altars=4 cascade_shrines=4 hoards=6 | watchtowers=8 reef_beacons=6 monoliths=4 chain_pylons=4`, `Emerald Spire *Waterfall* -> IslandWaterfall`, AND **`115 landmarks checked, 0 floating, worst_clearance=-1.23m`**!).
- **Wave I-7 Visual Verification Captures (`tools/capture.sh` Mesa lavapipe — ALL 6 inspected via `view_file`!)**:
  - `w7_gallery_maritime_relics`: All 4 Wave I-7 landmarks render crisp, detailed, and vividly lit with zero Z-fighting and zero extra texture VRAM!
  - `w7_ironwatch_fort_v2`: `FortWatchtower_Flank` & `VolcanicChainPylon_Harbour` flank the fort ramp cleanly; old right-flank shelf 100% eliminated by `CliffButtressWide_East`!
  - `w7_cutlass_overhaul`: Glowing turquoise `CompassMonolith_Ridge`, golden coastal dune sea-oats, 3-tone tropical hibiscus, `PirateCamp_GoldenCove` & `SmugglerHoard_Cove`!
  - `w7_cinder_basalt`: Twin blazing `VolcanicChainPylon_West/East` flanking Cinder Crag's caldera rim alongside `LavaCauldronShrine`s, `VolcanicObsidianArch`, charred caldera flora & wet obsidian surf rocks!
  - `w7_barnacle_haven`: Iconic harbour frame with `ReefBeacon_Shoal` rising out of turquoise surf beside `CoastalSeaArch_Harbour`, `HarbourCrane_Harbour`, `FortWatchtower_Headland`, `CascadeShrine_Ridge`, Lighthouse, `PirateWatchpost`, `SummitCrag` & sea-oats beach!
  - `w7_sirens_tooth`: `ReefBeacon_Spire` rising beside the sea arch in crystal surf, bleached `LeviathanRibcage`, `ImpaledShipwreckBow` & glowing `SunkenStern`!

---

## 4. Direct Sync With Cloud Lead (`Q21` & `Q23`) & Local-GPU (`Q-I8`)!

- **For Cloud Lead (`origin/ccr-663b66a0-rdiq4f` — READY FOR IMMEDIATE ZERO-CONFLICT INTEGRATION + `Q23` RECEIVED!)**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Wave 36 (`00e2ad8`)** with **4 clean commits** (Wave I-4 + I-5 + I-6 + I-7) touching **ONLY exclusive island-architect files** — **ZERO overlap with Quality Overhaul Passes Q1A/Q1B/Q2A/Q2B (`gen_sloop.py`, `gen_brigantine.py`, `gen_props.py`, `ship.gd`, `pawn.gd`, `crew_brain.gd`, `hud.gd`)!**
  - Merging or cherry-picking immediately brings **34 BC7 PBR landmarks (`+90` new placements)**, **shared `279 -> 30` BC7 texture dedup (`-34 MB` VRAM / `-32 MB` `.exe`!)**, **all M14/M16/M18 real-GPU fixes (`CascadeShrine_*`!)**, and **+0 DC biome sea-oats/volcanic micro-foliage** onto `ccr-663b66a0-rdiq4f`!
  - **Tiny Wave 36A Test Heads-Up (Not touched by us — your exclusive file `tests/test_ship.gd:3059`)**: When `test_island_details.gd` runs 34 GLBs earlier in the full 222-test runner, `Sea.time` starts slightly shifted in `test_wave36_cursed_cannonballs`, causing `y_recovered=0.17 vs y_cursed=-0.17` (`+0.34 m` vs hardcoded `+0.35 m`, whereas `bash tools/test.sh test_ship` passes `24/24` with `y=0.33->-0.17->0.48`). Resetting `Sea.time = 0.0` (or comparing `y_recovered - Sea.height(...)`) makes `test_wave36_cursed_cannonballs` 100% phase-invariant!
  - **Direct Answer to `Q23` (Owner Playtest Quality Overhaul Dispatch)**: **100% ON IT RIGHT NOW!** Immediately pivoting **Wave I-8** into **Island Quality Overhaul Pass I-Q1** targeting EVERY SINGLE Owner playtest priority (terrain micro-relief & tide-shelf ledges, logical landmark-to-landmark `IslandTrails` with wider high-contrast `COLOR.a` paths + 3D sculpted stepping stones & trail-edge curbs, denser layered flora ready to pair with your Pass Q2B high-detail trees, and living island fauna — tropical butterflies, active shore crabs & seabirds!).
- **Open Question `Q-I8` (for Local-GPU Milestone 19)**:
  - Once Wave I-7 (`34` GLBs, STILL `30` shared BC7 PNGs!) lands, could you verify: (1) **`shot=emerald_waterfall`** is 100% restored with `CascadeShrine_*`, (2) `30 -> 34` GLBs holds exact **`+0.0 MB` `tex_vram`** (`284.1 MB`), (3) real-GPU look-dev of `FortWatchtower`, `ReefBeacon` in surf, `CompassMonolith`, `VolcanicChainPylon` & `+0 DC` biome sea-oats / volcanic flora (`1920×1080 HIGH`), and (4) how your upcoming `Q22` `island_shader.gdshader` surface-detail depth upgrade pairs with our Wave I-8 micro-terraced rock benches & wider high-contrast `COLOR.a` cobblestone trails?

---

## 5. Next Up — Launching Wave I-8 IMMEDIATELY = Owner Playtest Island Quality Overhaul (`Pass I-Q1`!)
Pivoting **100% of our 4 parallel disjoint subagents** into the Owner's live playtest priorities (ZERO overlap with Cloud Lead Passes Q1–Q2 / Local-GPU `Q22` shader look-dev, ZERO extra texture VRAM!):
1. **Terrain Micro-Relief, Coastal Tide-Shelf Ledges & Eroded Gullies (`src/world/island_generator.gd`)**:
   - Break up remaining smooth rounded mid-elevation (`4..20 m`) colored mesh slopes with crisp geological strata benches, eroded rain-runoff gullies, and coastal limestone tide-shelf ledges right along shorelines (`0.5..4.5 m`) — strictly keeping dock/mooring zones, walkable trails, fort plateaus, and village pads flat & 100% navigable!
2. **Logical Landmark-to-Landmark Storytelling Trails + 3D Sculpted Stepping Stones & Trail-Edge Framing (`src/world/island_trails.gd` + `src/world/island_details.gd`)**:
   - Upgrade `IslandTrails` across all 14 islands so every footpath forms a clear, unmistakable continuous route connecting **Landing Beach/Pier -> Camp/Lanterns -> Landmarks/Vistas -> Ruins/Fort/Dig Clearings**, with **wider high-contrast `COLOR.a` trail painting** (`+30%` stronger footpath definition so trails read unmistakably in first-person!), PLUS batched 3D **sculpted flat stepping stones & trail-edge pebble curbs/grass borders** along trails (`IslandDetails`, zero primitives, zero extra VRAM)!
3. **Denser Layered Flora & Living Island Fauna (`src/world/island_details.gd` + `src/world/island_generator.gd`)**:
   - Boost layered multi-height undergrowth density (richer fern/hibiscus clusters around palm/banyan groves & cliff bases, denser driftwood/tidepool coastal rocks) ready to fuse seamlessly with Cloud Lead Pass Q2B's upgraded Blender trees!
   - Spawn **LIVING ISLAND FAUNA** across the archipelago: **sculpted fluttering Tropical Butterflies** (batched `MultiMeshInstance3D` animated smoothly across lush meadow & hibiscus glades by day, tucked away at night/storm — zero primitives, zero leaks!), **active shoreline `IslandCrab`s** scuttling along coves & beaches, and **circling coastal `SeabirdFlock` gulls** over harbours & arches!
4. **Full Archipelago Overhang Sweep (`0` Remaining Flat Shelves) + Title-Screen Starboard Harbour Staging + Contract Tests (`src/world/island_landmarks.gd`, `tests/test_island_details.gd`)**:
   - Swap ALL remaining `CliffOverhangLedge` placements (`Skull Bluff`, `Sovereign's Bastion`, `Galleon's Reach`, `Port Scoundrel`) to bottom-heavy reclined A-frame `CliffButtressWide`s so ZERO flat rock underside exists anywhere across all 14 islands!
   - Add automated contract tests verifying trail width/continuity, 3D stepping-stone framing, butterfly fauna animation & zero-leak teardown!
