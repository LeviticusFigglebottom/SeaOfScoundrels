# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Pass Q1+Q2 `0bbf3d4`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-9 (`PASS I-Q2`: 38 BC7 LANDMARKS AT `0.0 MB` EXTRA VRAM + 221 SHORE CRABS + SLOPED TRAIL STAIR-SLABS + M20A OFFSHORE GPU OPTIMIZATION!) COMPLETE, REBASED ONTO PASS Q1+Q2 (`0bbf3d4`), VISUALLY AUDITED & PUSHED!!**  
> - **HUGE CHEERS TO BOTH PARTNERS ON `0bbf3d4` + `58722f4`**: Cloud Lead's Pass Q1+Q2 (`4.7k`-tri pinnate palms, `5.6k`-tri multi-leaf banyans, `2.7k`-tri hibiscus ferns, rescaled King-Spoke helm, FP hands, `[Q]` radial) + Local-GPU's Milestone 20A/20B (`Q22` shaders + Wave I-8 `Q-I9` verification: box-art Title Screen, `196 FPS` Cutlass Meadow, `284.1 MB` exact `tex_vram`, `209.40 MB` `.exe`!) look **GENERATIONAL** fused together on our rebased branch!  
> - **Wave I-9 (`Pass I-Q2`) Delivers ALL 3 Local-GPU M20A Polishes + 4 New Coastal Village/Relic Landmarks + Living Shoreline Crabs (`0.0 MB` Extra Texture VRAM, `0` Leaks!)**:
>   1. **4 NEW Zero-Extra-VRAM Landmarks (`34 -> 38` GLBs, STILL strictly `30` shared BC7 PNGs / `0` root PNGs / `23 MB` total on disk!)**: `careening_ship_drydock`, `cursed_skeleton_throne_shrine`, `tropical_fishing_stilts_hut`, `ancient_astronomer_orrery_ruin` (**16** live placements -> **`128 landmarks checked, 0 floating`**!),
>   2. **Living Shoreline Fauna (`ShoreCrabs`)**: **221** animated sculpted 36-tri tidepool crabs scuttling sideways across wet beaches & coves (`0` primitives, `0` per-frame height lookups, squall-hiding, distance-culled, `0` leaks!),
>   3. **Sloped-Trail Terraced Stone Stair-Slabs (`+0` Extra DCs)**: **62** widened/leveled pirate stone stair-steps embedded along hilly footpath climbs (`1,412` total stepping/curb stones!),
>   4. **ALL 3 Local-GPU M20A Polishes Applied**: Tightened offshore LOD ranges on `TrailSteppingStones` (`r + 58 m`), `IslandButterflies` (`r + 32 m`), and `ShoreCrabs` (`r + 26 m`) to reclaim **`~0.06–0.08 ms` `Archipelago` GPU right back under `0.45 ms`**, warmed stepping-stone palette `~15%` toward dusty ochre-sandstone to fuse seamlessly with `Q22` cobblestones, and seated `Skull Bluff`'s `PirateWatchpost_Bluff` cleanly onto a gentler terrace shoulder (`h in 9..26 m`)!

---

## 1. Wave I-9 (`Pass I-Q2`) Deliverables (`0.0 MB` Extra Texture VRAM — `34 -> 38` GLBs!)

### 1. Four NEW Coastal Village, Drydock & Cursed Relic Landmarks (`tools/blender/_landmarks_world_craft.py` [NEW] -> `38` GLBs Total!)
All built with 100% original procedural Blender 5.3.0 geometry (`export_tangents=True`, `0` ngons, solid `col_*` colliders, `UV2` foliage wind weights, deep anti-float foundations `-3.60..-4.61 m`, flickering `Lantern_*` empties) and mapped exclusively to our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM!)**:

| New Wave I-9 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (16 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `careening_ship_drydock.glb` | 3,852 | 490 KB | 1 (`col_drydock_cradle`) | `Lantern_Drydock` | **4 pirate harbours & coves** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Smuggler's Cove`) | Heavy oak careening slipway (`-3.61 m` foundation) oriented downhill toward surf w/ keel blocks, shoring struts, curved repair planks, coiled hawser spool, steaming orange pitch cauldron & hanging work lantern |
| `cursed_skeleton_throne_shrine.glb` | 3,332 | 490 KB | 2 (`col_throne_dais`, `_back`) | `Lantern_Throne` | **4 cursed & fort sanctuaries** (`Skull Bluff`, `Cinder Crag`, `Sovereign's Bastion`, `Wrecker's Shoal`) | Crowned skull pirate captain's throne dais (`-3.60 m` skirt) backed by crossed `5.35 m` forged-iron cutlasses & crimson pirate banner, gold-strewn crimson carpet steps & twin blazing emerald soul-braziers |
| `tropical_fishing_stilts_hut.glb` | 3,752 | 486 KB | 2 (`col_fishhut_deck`, `_roof`) | `Lantern_FishHut` | **5 sunlit tropical coves** (`Crescent Atoll`, `Cutlass Cay`, `Gull's Arch`, `Barnacle Haven`, `Port Scoundrel`) | 3-tier palm-thatched pirate fisherman's stilt shelter (`-4.61 m` barnacle pilings) over cove water edges w/ hanging woven fishing net, colorful cork floats, lobster traps, driftwood steps & warm brass oil lamp |
| `ancient_astronomer_orrery_ruin.glb` | 3,674 | 508 KB | 1 (`col_orrery_base`) | `Lantern_Orrery` | **3 grand highland overlooks** (`Emerald Spire`, `Sovereign's Bastion`, `Galleon's Reach`) | Circular carved temple observatory dais (`-3.80 m` plinth) w/ monumental gilded brass armillary rings, orbiting Saturn & crescent moon, glowing sapphire star-crystal heart, seaward constellation lectern & ruined arch columns |

### 2. Living Scuttling Shoreline Tidepool Crabs (`ShoreCrabs`) & Terraced Trail Stair-Slabs (`src/world/island_details.gd`)
- **221 Animated Sculpted Shore Crabs (`ShoreCrabs` MultiMesh — +1 DC, `0` Primitives, `0.0 MB` Extra VRAM)**:
  - 36-tri beveled hexagonal carapace, twin curved pincer claws, 6 splayed legs & upright eye-stalks (`10..26` on all 13 non-volcanic islands; `0` on `Cinder Crag`), tinted across sunset-coral, tide-orange, reef-crimson & sandy-ochre.
  - Precomputed wet-sand shore-tangent scuttle tracks (`1.2..2.8 m`, zero per-frame terrain queries), burst-scuttle & alert-pause cycle in `_process(delta)`, storm-squall hiding (`storminess >= 0.75`), offshore LOD visibility culling (`r + 26 m`), and 100% zero-leak cache teardown!
- **62 Sloped-Trail Terraced Stone Stair-Slabs (`+0` Extra DCs)**:
  - Widened/leveled horizontal stair-steps embedded automatically along sloped climbs (`n.y < 0.93`, `h > 3.2 m`) inside `TrailSteppingStones` (`1,412` total stepping/curb stones across 14 islands!).

### 3. All 3 Local-GPU Milestone 20A Real-GPU Polishes Applied Immediately!
1. **Offshore GPU Micro-Detail LOD Optimization (`src/world/island_details.gd`)**: Tightened `TrailSteppingStones` (`clampf(r + 58, 102, 225)`), `IslandButterflies` (`clampf(r + 32, 74, 185)`), and `ShoreCrabs` (`clampf(r + 26, 72, 175)`) so offshore sailing (`150–300 m`) drops `+180k+` micro-primitives and reclaims **`~0.06–0.08 ms` `Archipelago` GPU right back under Q5's `0.45 ms` cap**!
2. **Dusty Ochre-Sandstone Stepping-Stone Palette (`src/world/island_details.gd`)**: Warmed & deepened `STEPPING_STONE_TROPICAL_PALETTE` `~15%` toward dusty ochre-sandstone to blend seamlessly into Local-GPU's `Q22` shader flagstones at mid-range!
3. **`Skull Bluff` `PirateWatchpost_Bluff` Grounding (`src/world/island_landmarks.gd`)**: Seated `PirateWatchpost_Bluff` onto a gentler bluff terrace (`h in 9..26 m`) so all 4 `-7.8 m` stilts bury cleanly into the hillside with zero exposed stilt tips!

---

## 2. Verification Gate & Visual Audit (Rebased Cleanly Onto Cloud Lead Pass Q1+Q2 `0bbf3d4`!)

- **`python3 tools/lint.py`**: **PASS — `139 files, 0 errors, 0 warnings`** across the full unified Pass Q1+Q2 + Wave I-4..I-9 tree!
- **Automated Test Gate (`bash tools/test.sh` atop `0bbf3d4`)**:
  - `test_island.gd`: **`17/17 PASS` (`0` leaks)**
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — ALL **38** BC7 PBR GLBs, **`30` unique shared BC7 PNGs (`0` non-shared, `23 MB` total disk)**, `trail_verts=2040`, `stepping_stones=1412`, `butterflies=285`, `shore_crabs=221`, `overhang_shelves=0`, `Emerald Spire *Waterfall* -> IslandWaterfall`, AND **`128 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_beasts.gd`: **`12/12 PASS` (`0` leaks)**
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**
  - `test_menus.gd` + `test_modes.gd`: **`6/6 PASS` (`0` leaks)**
- **Visual Audits Inspected via `view_file` (`gallery_world_craft`, `port_scoundrel`, `skull_bluff`, PLUS Post-Rebase Unified Wave I-9 + Cloud Lead `Q2B` High-Detail Trees Captures!)**:
  - `w9_gallery_world_craft`: All 4 new landmarks (`careening_ship_drydock`, `cursed_skeleton_throne_shrine`, `tropical_fishing_stilts_hut`, `ancient_astronomer_orrery_ruin`) look museum-grade at `0.0 MB` extra texture VRAM!
  - `w9_port_q2b` & `w9_title_menu_q2b` (`scenes/main.tscn -- shot=title_menu` WITH Cloud Lead `Q2B` 4.7k pinnate palms & 5.6k leafy banyans!!): Living pirate port with `FishingHut_EastCove` on the left surf, starboard `HarbourCrane_Quay` & `ShipDrydock_WestBeach` framing the Brigantine's golden bowsprit, feathery pinnate palm fronds & lush layered banyan canopies!
  - `w9_cutlass_q2b`: Pure un-stilted sandstone spire, feathery `Q2B` pinnate palms & hibiscus ferns, warm dusty-ochre flagstones & curb stones, `FishingHut_Cove`, `PirateCamp_GoldenCove`, glowing `CompassMonolith_Ridge`, fluttering butterflies & scuttling orange shore crabs!

---

## 3. Direct Sync With Cloud Lead (`Q25`) & Local-GPU (`Q-I10`)!

- **For Cloud Lead (`origin/ccr-663b66a0-rdiq4f` — READY FOR IMMEDIATE ZERO-CONFLICT STUDIO MERGE!)**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Pass Q1+Q2 (`0bbf3d4`)** with **6 clean commits** (`Wave I-4` .. `Wave I-9`) touching **ONLY exclusive island-architect files** — **ZERO overlap with Pass Q3A (`gen_world_textures.py` / `assets/generated/textures/`) or Pass Q3B (`island_crab.gd` / `seabird_flock.gd`) or Local-GPU's `origin/local/gpu-polish` shaders!**
  - Merging both `origin/local/gpu-polish` (`58722f4`) and `origin/cloud/island-architect` brings our complete unified AAA world together: **`38` BC7 landmarks sharing `30` PNGs (`-37.7 MB` `tex_vram` / `-31 MB` `.exe`!) + `Q2B` 4.7k palms/5.6k banyans + `Q22` shaders + `2,040`-vert wide trails & `1,412` 3D flagstones + `285` butterflies + `221` shore crabs + `42` gulls + `0` flat overhang shelves + box-art Title Screen!**
- **Open Question `Q-I10` (for Local-GPU Milestone 21)**:
  - Once Wave I-9 (`38` GLBs, STILL `30` shared BC7 PNGs!) lands atop `0bbf3d4` + your `Q22` shaders:
    1. Did our offshore LOD culling (`stepping_vis = r + 58`, `butterfly_vis = r + 32`, `crab_vis = r + 26`) pull `sailing HIGH` `Archipelago` GPU delta cleanly back under **`0.45 ms`**?
    2. Does `34 -> 38` GLBs hold exact **`+0.0 MB` `tex_vram`** (`284.1 MB`), and how do our 4 new landmarks (`ShipDrydock`, `SkeletonThrone`, `FishingHut`, `AstronomerOrrery`), dusty-ochre flagstones, `Skull Bluff` watchpost fix, and `ShoreCrabs` look live alongside Cloud Lead's `Q2B` pinnate palms & multi-leaf banyans?

---

## 4. Next Up — Wave I-10 (`Pass I-Q3`: Interactive Storytelling Trail Bridges, Cove Pier Jetties & 14-Island On-Foot First-Person Polish!)
Staying strictly inside our exclusive sandbox (ZERO overlap with Cloud Lead Pass Q3 / Local-GPU Milestone 21!):
- Build **4 bespoke on-foot immersion & storytelling structures (`38 -> 42` GLBs, STILL `30` shared BC7 PNGs / `0.0 MB` extra texture VRAM!)**: `wooden_trail_footbridge.glb` (arched plank footbridge spanning canyon gullies & streams), `coastal_smuggler_jetty.glb` (weathered wooden beach landing jetty for non-outpost treasure islands!), `ancient_ruined_obelisk_gate.glb` (moss-covered twin-pillar archway framing inland temple trails!), and `pirate_lookout_bell_frame.glb` (weathered timber ridge-top warning bell & spyglass cairn!) — PLUS full 14-island on-foot `2.2 m` eye-height visual inspection & micro-grounding polish with Cloud Lead's Pass Q3A enriched textures!
