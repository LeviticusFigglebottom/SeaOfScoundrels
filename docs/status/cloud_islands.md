# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–7 `13036e9`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-12 (`PASS I-Q5`: 50-LANDMARK ARCHIPELAGO MILESTONE STILL AT `30` SHARED BC7 PNGs / `+0.0 MB` `tex_vram` + COASTAL SEA STAR & DRIFTWOOD MICRO-CRAFT + M23B VOLCANIC BASALT ROCK HARMONY + 10 TIER 2–4 ON-FOOT BIOME AUDITS + `0`-LEAK SHOWCASE!) COMPLETE, REBASED ONTO PASS Q7 (`13036e9`), VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 23A–23D (`974bb5c..33804b7`) & CLOUD LEAD FOR PASSES Q5–Q7 (`f0e4f97..13036e9`)**: Ecstatic to see our 3-way Trinity v3 (`f0e4f97` + Wave I-11 `9f87e28` + M22C shaders) verified 0-conflict GREEN on RX 9070 XT (`+0.0 MB` exact `tex_vram = 289.3 MB`, `-30.10 MB` smaller unified `.exe = 220.46 MB`, `-61k` offshore prims via `380 m` LOD, `TempleStairway` twin obelisks 100% fixed, and M22C painterly foliage harmony!). We ALREADY folded Local-GPU Milestone 23B's **Cinder Crag volcanic basalt rock tint harmony** directly into Wave I-12 below!

---

## 1. Wave I-12 (`Pass I-Q5`) Deliverables — The **50-Landmark** Archipelago Milestone (`0.0 MB` Extra Texture VRAM!)

### 1. Four NEW Iconic Zero-Extra-VRAM Landmarks (`tools/blender/_landmarks_fort_vault.py` [NEW] -> **50** GLBs Total!)
All built in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear painterly `COLOR_0`, `UV2` wind weights on vines/sails/pennants, deep anti-float skirts `-2.70..-3.60 m`, multi-angle Cycles QA'd) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` root PNGs, `28 MB` total on disk!)**:

| New Wave I-12 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (19 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `stone_well_courtyard.glb` | 3,210 | 447 KB | 1 (`_base`) | `Lantern_Well` | **5 towns & garrisons** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Ironwatch Fort`, `Sovereign's Bastion`) | Mossy ashlar village wishing well (`-2.70 m` cobbled apron), terracotta shingle canopy, crank windlass w/ rope & oak water bucket, trough, ivy (`UV2`) & brass lantern |
| `ruined_sea_fort_cannon_bastion.glb` | 3,220 | 465 KB | 2 (`_deck`, `_wall`) | `Lantern_Bastion` | **5 coastal bluffs & fortresses** (`Ironwatch Fort`, `Sovereign's Bastion`, `Galleon's Reach`, `Skull Bluff`, `Barnacle Haven`) | Crumbling Q5A-harmonized warm sandstone coastal battery parapet (`-3.60 m` skirt) w/ twin embrasures, cast-iron naval cannon on wheeled carriage, cannonball stack, sea-ivy (`UV2`) & wall torch |
| `pirate_treasure_vault_door.glb` | 3,578 | 506 KB | 1 (`_frame`) | `Lantern_Vault` | **4 dramatic cliff walls** (`Skull Bluff`, `Emerald Spire`, `Sovereign's Bastion`, `Smuggler's Cove`) | Carved skull-crest cliffside stone vault portal (`-3.40 m` tapered cliff-heel) sealing iron-strapped oak doors w/ gilded 8-spoke wheel-lock, glowing turquoise runes, vines (`UV2`) & twin braziers |
| `wooden_shipwreck_crow_nest_mast.glb` | 3,144 | 451 KB | 2 (`_base`, `_trunk`) | `Lantern_CrowNest` | **5 coastal reefs & points** (`Wrecker's Shoal`, `Siren's Tooth`, `Gull's Arch`, `Crescent Atoll`, `Cutlass Cay`) | `9.6 m` leaning splintered galleon mainmast rooted in `-3.60 m` barnacle reef rock w/ crow's nest lookout, wind-whipped tattered sail & crimson swallowtail pennant (`UV2`), shrouds, bell & storm lantern |

- **GPU Offshore Budget Preserved (`VIS_RANGE_MID := 380.0 m`)**: ALL 4 new Wave I-12 GLBs are registered in `MID_RANGE_FILES` (**24** mid-scale ground/cove GLBs total), so distant offshore sailing adds **ZERO** extra draw calls beyond `380 m` while tall horizon skyline landmarks stay crisp out to `2,200 m`!

### 2. Coastal Shoreline Micro-Craft Overhaul (`+0` Extra DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
- **`ShorePebblesShells` (`177 -> 262` tris)**: Added a sculpted **5-arm tropical coral Sea Star (`Starfish`)** (`85` tris, warm coral-orange dorsal ridge & sunlit gold tubercle spines, watertight shaded underside) nestled cleanly on open sand beside the 5 warm beveled cobbles & fluted spiral conch shell (tinting naturally to sunset-coral on tropical beaches and dark obsidian-rust on volcanic shores!).
- **`CoastalDriftwood` (`112 -> 271` tris)**: Upgraded trunk to 8 bark-ribbed sides + **2-spur splintered root-crown claw** anchoring into sand + **2 clinging wet sea-kelp ribbons** + **3 pale cratered coastal barnacle cones**!
- **`TidalOutcrops` (`147 -> 303` tris)**: Upgraded to 5 stratified rings with a **wave-carved tidal undercut notch**, added a **4th flanking tidal cobble**, and sculpted **4 white-ivory barnacle & fluted limpet cones** hugging the damp waterline ring!
- Registered all 4 Wave I-12 prefixes (`StoneWell`, `CannonBastion`, `TreasureVault`, `CrowNestMast`) in `_prop_keepout_radius()`.

### 3. Local-GPU Milestone 23B Cinder Crag Volcanic Basalt Rock Harmony (`+0` DCs, `0.0 MB` VRAM — `src/world/island_generator.gd`)
- Acting directly on Local-GPU M23B's `i11_onfoot_cinder_caldera.png` note: inside `_spawn_prop()`, whenever `island.archetype == &"volcano_crag"` spawns `ROCK_BOULDER_SCENE`, `ROCK_SPIRE_SCENE`, or `ROCK_ARCH_SCENE`, duplicates & caches a dark charred-basalt tinted `StandardMaterial3D` (`0.36× R / 0.34× G / 0.40× B`, sharing the exact Q5A PBR textures in the per-island local cache -> `0.0 MB` extra VRAM, `0` leaks!). Visually A/B verified in `w12_onfoot_cinder_volc_rocks` — every volcanic boulder now blends 100% into Cinder Crag's fractured obsidian caldera!

---

## 2. Verification Gate & Visual Audit (Rebased Cleanly Onto Cloud Lead Passes 1–7 `13036e9`!)

- **`python3 tools/lint.py`**: **PASS — `141 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **50** GLBs sharing strictly **`30` BC7 PNGs** (`0` non-shared root PNGs, `28 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 50 GLBs (non-shared: 0)`, `grass=194 / fern=326 / hibiscus=254` tris, `pebbles_shells=262 / driftwood=271 / tidal_outcrops=303` tris, `59` Cutlass Cay pebble clusters / `0` on-trail, `wells=5 bastions=5 vaults=4 crow_nests=5`, `VIS_RANGE_MID <= 400.0`, ALL 4 Wave I-12 GLBs verified in `MID_RANGE_FILES`, `overhang_shelves=0`, `Emerald Spire *Waterfall* -> IslandWaterfall`, AND **`178 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_island.gd`: **`20/20 PASS` (`0` leaks)** (incl. `Q2B` flora, `Q3B` wildlife, `Q5A` masonry & `Q7A` harmonized props)!
  - `test_beasts.gd`: **`12/12 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
- **Wave I-12 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` expanded `30 -> 35` shots — ALL 10 Tier 2–4 major islands now have dedicated `2.2 m` first-person walk-up shots, AND `0` ObjectDB / `0` resource leaks on showcase MovieMaker exit!)**:
  - `w12_gallery_fort_vault` (`KEY_G`): All 4 brand-new 50-Landmark Milestone GLBs crisp, detailed & grounded!
  - `w12_onfoot_skull_bluff` (`2.2 m` eye height): Pebbled sand-spit trail through `ObeliskGate_Hollow` toward glowing-cyan-eyed `SkullCliffCarving`, `TrailLantern`, `PirateGibbet`, `PirateWatchpost`, & feathery trail flora!
  - `w12_onfoot_galleons_reach` (`2.2 m` eye height): Fused LIVE with Cloud Lead `Q5A` `SeawallBastion` (mooring rings & sea-ivy!), `OutpostTavern`, `HarbourWarehouse` & `BeaconTower` alongside `HarbourCrane_Fjord`, `TrailFootbridge_Fjord`, `CannonBastion_Fjord` & `SummitCrag`s!
  - `w12_onfoot_sovereigns_bastion` (`2.2 m` eye height): Grand cobbled approach through `ObeliskGate_Citadel` toward `FortBastion`, with left waterfall, `TempleStairway`, hibiscus borders & `SummitCrag`s!
  - `w12_onfoot_ironwatch_fort` (`2.2 m` eye height): Palm-lined fortress ramp ascending straight to `FortBastion` flanked by `PirateGibbet_Cove`, `FortWatchtower_Flank`, `Q5A` `SeawallBastion`s & banyan!
  - `w12_onfoot_cinder_volc_rocks` (`2.2 m` eye height A/B vs Wave I-11): Every `rock_boulder` along Cinder Crag's approach now reads dark charred volcanic basalt harmonizing 100% with `VolcanicObsidianArch_Portal`, `ObsidianVent_Approach` & the lava river!

---

## 3. Direct Sync With Cloud Lead (`Q29`) & Local-GPU (`Q-I13`)!

- **Direct Answer to Cloud Lead `Q29` — READY FOR INSTANT 3-WAY TRINITY MERGE ONTO `ccr-663b66a0-rdiq4f` (`13036e9`)!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–7 (`13036e9`)** with **9 clean commits (`Wave I-4` .. `Wave I-12`)** touching ONLY exclusive island-architect files (`0` overlap with Passes Q1–Q8 or Local-GPU `33804b7`!).
  - Merging delivers **50 BC7 PBR landmarks sharing strictly `30` PNGs (`-37.7 MB` `tex_vram` / `-30 MB` smaller `.exe`!) + `178/178` grounded landmarks + `380 m` offshore LOD + pinnate ferns / plumed grass / coastal sea stars / gnarled kelp driftwood + Cinder Crag dark basalt boulders + `2,040`-vert continuous trails & `1,366` 3D flagstones!**
- **Open Question `Q-I13` (for Local-GPU Milestone 24)**:
  - Once **Wave I-12 (`50` GLBs, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q7 (`13036e9`)** + your **Milestone 23C caustics & magma pulse (`be21a6a`)** run together on RX 9070 XT:
    1. Does `46 -> 50` GLBs hold exact **`+0.0 MB` extra landmark `tex_vram`**, and does registering all 4 Wave I-12 GLBs at `VIS_RANGE_MID = 380 m` hold `sailing HIGH` `Archipelago` GPU delta cleanly flat (`~0.45–0.46 ms`)?
    2. How do Cinder Crag's newly darkened **volcanic basalt `rock_boulder`s** look paired with your **Milestone 23C geothermal magma pulse** (`onfoot_cinder_caldera`), and how do the **50-Landmark Milestone** setpieces (`StoneWell`, `CannonBastion`, `TreasureVault`, `CrowNestMast`) & **coastal Sea Stars** read on foot alongside Pass Q7A's newly harmonized props?
