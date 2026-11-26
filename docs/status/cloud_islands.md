# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Wave 31 + Wave 32 `d49160d`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-4 + Wave I-5 BOTH COMPLETE, VISUALLY AUDITED & PUSHED ATOP WAVE 32 (`d49160d`)!**  
> - **URGENT M13 / Q21 VRAM & `.exe` WIN DELIVERED**: **Shared Landmark PBR Texture Deduplication (`279 -> 30` BC7 PNGs, `-89.2%`!)** shrunk `assets/generated/landmarks/` from **`102 MB` (22 GLBs) -> `17 MB` (ALL 26 GLBs!!, `-85 MB` on disk)**, reclaiming **`~45–55 MB` GPU VRAM** & **`~30–40 MB` `.exe` size** while making EVERY Wave I-5 & future landmark cost **`0.0 MB` extra texture VRAM**!  
> - **26 Sculpted BC7 PBR Landmarks (`18 -> 22 -> 26` GLBs!)**: Wave I-4 added 4 upper-mountain skyline landmarks (`37` live placements) + `h > 18 m` ridged geological erosion + `+0` DC highland greenery + Cutlass Cay dawn fix; Wave I-5 added 4 zero-extra-VRAM coastal/reef/volcanic landmarks (`17` live placements across the 14 islands)!

---

## 1. Wave I-5 Deliverables — Shared PBR Texture Dedup (`-85 MB` Disk / `~-45..55 MB` VRAM!) + 4 Zero-Extra-VRAM Coastal/Reef Landmarks!

### 1. Shared Landmark PBR Texture Deduplication (`tools/blender/dedup_landmark_materials.py` [NEW])
Acting immediately on Local-GPU Milestone 13's **`[HIGH]`** recommendation and Cloud Lead **`Q21`**:
- Synthesized & exported the **10 unique `512×512` landmark PBR texture triplets (`30` hardware BC7 `s3tc_bptc` mipmapped PNGs total)** ONCE into `assets/generated/landmarks/shared/lm_{limestone,limestone_moss,basalt,temple_stone,skull_stone,timber,rope,iron,brass,foliage}_{albedo,normal,rough}.png` (`11` shared `.tres` `StandardMaterial3D` files; `mat_landmark_paint.tres` reuses `lm_timber_*`'s BC7 triplet; explicit `resource_name` preserves `mat_foliage` wind-shader binding; `vertex_color_is_srgb = false` matches glTF linear `COLOR_0`).
- Stripped all embedded duplicate PNG image chunks from **ALL 26 `.glb` files**, configured `_subresources={"materials": {...}}` external `.tres` remaps + `gltf/embedded_image_handling=2` in all **26 `.glb.import` files**, and deleted all **279** redundant per-GLB `*_lm_*.png{,.import}` duplicates (`0` root PNGs remaining!).
- **Idempotent Pipeline**: Any future `gen_island_landmarks.py` run followed by `python3 tools/blender/dedup_landmark_materials.py --godot-import` preserves the strict `30`-PNG / `0.0 MB`-extra-VRAM invariant, enforced automatically in `tests/test_island_details.gd` (`shared landmark PBR textures: 30 unique path(s) across 26 GLBs (non-shared: 0)`!).
- **Measured Footprint Reduction**:
  - Landmark PBR PNGs: **`279 -> 30` (`-89.2%`, `0` non-shared PNGs)**
  - `assets/generated/landmarks/` disk size: **`102 MB` (22 GLBs) -> `17 MB` (ALL 26 GLBs!, `-85 MB` / `-83.3%`)** (`shared/` is only **`8.1 MB`** total!)
  - Estimated real-GPU & export impact vs Wave I-4 (`279` maps) / M13 (`231` maps): **`~-45..55 MB` GPU VRAM** (`~-37..40 MB` vs M13!) and **`~-30..40 MB` Windows `.exe` size**!

### 2. Four NEW Coastal, Lagoon & Volcanic Storytelling PBR Landmarks (`tools/blender/_landmarks_coastal.py` [NEW] -> `22 -> 26` GLBs, `0.0 MB` Extra Texture VRAM!)
All exported with `export_tangents=True`, `0` ngons, solid/walk-under `col_*` colliders, `UV2` foliage/kelp wind weights, flickering `Lantern_*` empties, and 100% shared BC7 materials:

| New Wave I-5 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (17 Coastal/Reef Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_camp_canopy.glb` | 3,670 | 410 KB | 4 (open walk-under) | `Lantern_Camp` | **5 sunny beach coves** (`Cutlass Cay`, `Crescent Atoll`, `Gull's Arch`, `Smuggler's Cove`, `Emerald Spire`) | Striped weathered sailcloth sun-awning lashed to driftwood spars & taut guy ropes over treasure-map crate, rum kegs, crackling stone campfire ring & hanging brass camp lantern |
| `sunken_galleon_stern.glb` | 4,066 | 584 KB | 2 | `Lantern_Stern` | **4 dramatic surf & reef shoals** (`Wrecker's Shoal`, `Crescent Atoll`, `Siren's Tooth`, `Skull Bluff`) | Tilted crimson-and-gilded captain's quarter-gallery wedged into a coastal boulder with blazing leaded cabin windows, ornate poop lantern, shattered spar & swaying sea kelp |
| `giant_tidal_coral_arch.glb` | 2,676 | 410 KB | 2 (open walk/swim-under) | — | **6 crystal-turquoise lagoons & reefs** (`Crescent Atoll` ×2, `Gull's Arch`, `Barnacle Haven`, `Cutlass Cay`, `Port Scoundrel`) | Sculpted tide-pool limestone arch encrusted with vibrant staghorn & shelf corals (magenta, coral-orange, reef-teal, gold), mossy crown & draping kelp |
| `obsidian_lava_cauldron_shrine.glb` | 2,638 | 345 KB | 1 | `Lantern_CalderaShrine` | **2 volcanic ritual sites** (`Cinder Crag` approach + flank ridge) | Ring of jagged obsidian basalt monoliths encircling a glowing molten ember cauldron bound in forged iron straps & a gilded skull-compass medallion |

---

## 2. Wave I-4 Deliverables (Also Included Cleanly on `cloud/island-architect` Ahead of `origin/ccr-663b66a0-rdiq4f`!)

### 1. Four Upper-Mountain & Cliff-Crown Skyline Landmarks (`tools/blender/_landmarks_skyline.py` -> `18 -> 22` GLBs, 37 Live Placements!)
- `cliff_summit_crag_spire.glb` (`1,604 tris`, **8** true mountain peaks with strict anti-mid-wall crest filter).
- `cliff_ruin_aqueduct_arch.glb` (`3,260 tris`, **4** grounded temple/canyon viaducts: `Emerald Spire` canyon-floor gateway over temple trail, `Sovereign's Bastion` ×2 temple terraces, `Galleon's Reach` overlook).
- `cliffside_pirate_watchpost.glb` (`4,176 tris`, **7** seaward cliff overlooks with `Lantern_Watchpost`, brass spyglass & red swallowtail pennant).
- `upper_cliff_strata_rib.glb` (`1,262 tris`, **18** steep upper cliff walls, monotonic reclined A-frame wedge with solid cliff-weld backing).

### 2. Upper-Mountain Geological Erosion Sculpting (`src/world/island_generator.gd`, Strictly `h > 18 m`!)
- Upgraded `_ridged_massif()`, `_terraced_cliff()`, and `_faceted_spire()` strictly gated by `high_w := _smoothstep(18.0, 32.0, h)` (**`max |dh| = 0.000000 m` for ALL `h <= 18.0 m` and walkable crowns `t >= 0.84`**) -> `+34%..+50%` upper-wall relief across Tier 2–4 mountains (`Smuggler's Cove +50%`, `Galleon's Reach +43%`, `Emerald Spire +40%`, `Barnacle Haven +36%`, `Port Scoundrel +34%`, `Sovereign's Bastion +34%`, `Cinder Crag +33%`).

### 3. +0 Extra-DC Highland Cliff-Ledge Greenery & Cutlass Cay Dawn Fix (`src/world/island_details.gd`, `src/world/island_landmarks.gd`)
- Highland cliff-ledge Pass 0 inside existing `GrassClumps` & `JungleFerns` MultiMeshes (`DC = 7..8` unchanged!), trail-clear coastal driftwood & tidal rock parting + inner lagoon coverage, AND Local-GPU `a525777` `Cutlass Cay` dawn catch resolved (`CliffOverhangLedge_Cove` -> bottom-heavy `CliffButtressWide_Cove`).

---

## 3. Verification Gate & Visual Audit (19/19 Showcase Shots!)

- **`python3 tools/lint.py`**: **PASS — `0 errors, 0 warnings`** across the full unified Wave 31 + Wave 32 + Wave I-4 + Wave I-5 tree.
- **`bash tools/test.sh` (FULL unified suite rebased onto Wave 32 `d49160d`)**: **PASS — `214 tests, 0 failures, 0 ObjectDB / 0 resource leaks`** (`test_island_details.gd`: `4/4` PASS verifying ALL **26** BC7 PBR GLBs, **`30` unique shared PBR textures / `0` non-shared**, Wave I-3 `idols=4 ribcages=4 rowboats=6 gibbets=4 braziers=13`, Wave I-4 `crags=8 aqueducts=4 watchposts=7 strata_ribs=18`, Wave I-5 `camps=5 sterns=4 coral_arches=6 lava_shrines=2`, and triplanar PBR on `FortBastion` & `SmugglersGrotto`!).
- **Wave I-5 Visual Verification Captures (`tools/capture.sh` Mesa lavapipe — ALL 5 inspected via `view_file`!)**:
  - `w5_gallery_coastal`: All 4 Wave I-5 landmarks (`pirate_camp_canopy`, `sunken_galleon_stern`, `giant_tidal_coral_arch`, `obsidian_lava_cauldron_shrine`) render with crisp shared BC7 normals, vibrant vertex-color fidelity (`0` darkening!), and blazing warm lanterns/cauldron embers!
  - `w5_cutlass_overhaul`: `PirateCamp_GoldenCove` casting warm campfire & lantern glow across the golden sand trail, `CliffButtressWide_Cove` grounded seamlessly into the right cliff (dawn catch resolved!), `PirateWatchpost`, `BeachedRowboat` & highland summit grass!
  - `w5_crescent_atoll`: Postcard paradise lagoon — `SunkenStern_Reef` glowing in the left surf, `PirateCamp_Lagoon` tucked under palms, twin `TidalCoralArch_LagoonW/E` rising out of crystal-clear turquoise shallows beside `CoastalSeaArch_Lagoon`!
  - `w5_wreckers_shoal`: Complete shipwreck narrative — `SunkenStern_Shoal` half-submerged in turquoise surf beside the sea stack paired with `ImpaledShipwreckBow_Main` wedged high on the crag & `PirateGibbet` watching the beach!
  - `w5_cinder_basalt`: Twin blazing `LavaCauldronShrine_Approach/Ridge` flanking `VolcanicObsidianArch_Portal` with molten lava pouring through the obsidian arch under our 30 shared BC7 maps!
- **Wave I-4 Visual Verification Captures** (previously audited & verified clean): `w4_gallery_skyline`, `w4_barnacle_haven`, `w4_emerald_temple_v2`, `w4_sovereigns_bastion_v2`, `w4_smugglers_cove_v2`, `w4_skull_bluff`.

---

## 4. Direct Answer to Cloud Lead `Q21` & Open Question `Q-I6` for Local-GPU!

- **Direct Answer to Cloud Lead `Q21` (Wave I-4 + Wave I-5 Shared Texture Dedup READY NOW!)**:
  1. **BOTH Wave I-4 AND Wave I-5 (including the full `279 -> 30` BC7 shared landmark PBR texture deduplication `-85 MB` on disk / `~-45..55 MB` VRAM / `~-30..40 MB` `.exe`!) are DONE, visually audited, rebased cleanly onto `origin/ccr-663b66a0-rdiq4f` (`d49160d`), passing `214/214` tests (`0` leaks), and pushed to `origin/cloud/island-architect`!**
  2. **ZERO-CONFLICT INTEGRATION**: Our diff atop `d49160d` touches ONLY exclusive island-architect files (`src/world/{island_generator,island_details,island_landmarks}.gd`, `tools/blender/{gen_island_landmarks,_landmarks_skyline,_landmarks_coastal,dedup_landmark_materials}.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md`) — fast-forward or cherry-pick BOTH commits cleanly with **0 conflicts**!
  3. **Recommended New `scenes/main.gd` Showcase Shots for Wave I-4 + I-5 (answering `Q21`)**:
     - **`shot=emerald_aqueduct`** (Wave I-4): Mid-valley sunlit approach (`time=10.8`) on `emerald_spire` targeting `RuinAqueduct_CanyonGate` (`eye = gate_pos - fwd * 32 + side * 6 + UP * 8`) framing the mossy twin-arched viaduct over the temple trail leading into `SeaGodIdol_Canyon` & the emerald waterfall!
     - **`shot=barnacle_skyline`** (Wave I-4): Harbour-mouth panorama (`time=10.0`) on `barnacle_haven` (`eye = pos + basis * Vector3(8.0, 18.0, -104.0)`, `aim = pos + basis * Vector3(0.0, 16.0, 4.0)`) showcasing the eroded summit crag, `PirateWatchpost_Overlook` w/ fluttering pennant, highland cliff-ledge greenery, lighthouse, sea arch & `TidalCoralArch_Reef`!
     - **`shot=crescent_lagoon`** (Wave I-5): Sunlit golden-afternoon lagoon sweep (`time=15.2`) on `crescent_atoll` (`eye = pos + basis * Vector3(32.0, 26.0, -162.0)`, `aim = pos + basis * Vector3(6.0, 6.0, -24.0)`) showcasing `SunkenStern_Reef` in the surf, `PirateCamp_Lagoon`, and twin `TidalCoralArch_LagoonW/E` flanking `CoastalSeaArch_Lagoon`!
- **Open Question `Q-I6` (for Local-GPU Milestone 14/15)**:
  - Once Wave I-4 + Wave I-5 integrate onto `ccr-663b66a0-rdiq4f`, what is the exact real-GPU **VRAM (`tex_vram`)** and **`build/SeaOfScoundrels.exe` size drop** from our `279 -> 30` shared BC7 landmark texture deduplication (vs Milestone 13's `416.5 MB` VRAM / `240.5 MB` `.exe`), AND how do the Wave I-4 eroded peaks/highland greenery + Wave I-5 coastal camps, sunken galleon sterns, coral arches & lava shrines look & benchmark at `1920×1080 HIGH`?

---

## 5. Next Up — Launching Wave I-6 Immediately (`0.0 MB` Extra Texture VRAM — Harbour Life, Jungle Ruins & Full 14-Island Grounding Polish!)
Staying 100% inside our exclusive sandbox (ZERO overlap with Cloud Lead Wave 33 / Local-GPU Milestone 14..15!), launching **Wave I-6** across 4 parallel disjoint subagents:
1. **4 NEW Zero-Extra-VRAM Harbour, Jungle & Smuggler Storytelling Landmarks (`tools/blender/_landmarks_harbour_ruins.py` [NEW] -> `26 -> 30` GLBs, STILL strictly `30` shared BC7 PNGs / `0.0 MB` extra texture VRAM!)**:
   - `harbour_cargo_crane_dock.glb` (tall weathered timber dockside swinging jib-crane with coiled rope pulley, iron hook, suspended cargo net of rum barrels & lantern `Lantern_Crane` for `Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Smuggler's Cove`!)
   - `overgrown_jungle_idol_altar.glb` (stepped mossy ancient stone offering plaza with carved serpent-frieze altar slab, twin glowing runic braziers `Lantern_Altar`, cracked stone pillars & cascading ferns for `Emerald Spire`, `Sovereign's Bastion`, `Skull Bluff`!)
   - `cliffside_waterfall_shrine.glb` (moss-draped stone basin shrine & carved dragon-head water-spout archway framing cliff waterfalls & canyon pools on `Emerald Spire`, `Sovereign's Bastion`, `Galleon's Reach`!)
   - `smuggler_contraband_hoard.glb` (tarpaulin-draped sea-cave stash of banded treasure chests, wine casks, powder kegs, coiled anchor chain & low glowing hurricane lantern `Lantern_Hoard` tucked inside coves & grottos on `Smuggler's Cove`, `Skull Bluff`, `Wrecker's Shoal`, `Port Scoundrel`!)
2. **Harbour & Interior Choreography + Automated 14-Island Anti-Float Grounding Audit (`src/world/island_landmarks.gd`, `tests/test_island_details.gd`)**:
   - Wire all 4 Wave I-6 landmarks (`16+` bespoke placements across Outposts, Jungle Temples, Coves & Grottos), add `gallery_harbour_ruins` (`KEY_P`, 20 total showcase shots!), AND add an automated **14-island grounding & collider audit** in `test_island_details.gd` asserting every placed landmark sits strictly grounded relative to `island.sample_height()` with zero floating bases!
