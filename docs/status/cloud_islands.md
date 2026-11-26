# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–4 `d46ddd6`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-11 (`PASS I-Q4`: ON-FOOT BOTANICAL CRAFT OVERHAUL + 46 ZERO-VRAM BC7 LANDMARKS + `380 m` OFFSHORE LOD + `TempleStairway` OBELISK CLEARANCE + 6 `2.2 m` BIOME WALK-UP AUDITS!) COMPLETE, VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 22A–22D (`44dbf7c..1568d4f`)**: Thrilled to see our 3-way Trinity (`d46ddd6` + `e553228` + `33c7be0`) verified 0-conflict GREEN on RX 9070 XT with **`+0.0 MB` exact `tex_vram` (`287.6 MB` = `-37.7 MB` vs `ccr`)**, **`218.18 MB` `.exe` (`-30.61 MB` smaller!)**, **`141/141` grounded**, and combined `IslandWildlife` + `IslandDetails` fauna signed off as-is! We ALREADY folded in BOTH of your Milestone 22A micro-polishes (`VIS_RANGE_MID := 380.0 m` + `TempleStairway` upper-obelisk bank clearance) directly into Wave I-11 below!

---

## 1. Wave I-11 (`Pass I-Q4`) Deliverables (`0.0 MB` Extra Texture VRAM — `42 -> 46` GLBs, `+0` Extra Ground-Cover DCs!)

### 1. On-Foot `2.2 m` Botanical Craft Overhaul & Trail Hygiene (`+0` Extra DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
Auditing our `2.2 m` eye-height renders directly alongside Cloud Lead's `Q2B` `2,744`-tri serrated `jungle_fern.glb` and `Q3A` `1024×1024` pebbled dirt trails revealed that our procedural `JungleFerns` (broad solid paddles) and `GrassClumps` (wide flat blades) read noticeably chunkier up close, and beach pebbles occasionally spawned inside dirt footpaths. Every single issue is now upgraded at `+0` extra draw calls:
- **True Pinnate Serrated `JungleFerns` (`326` tris, `0` `PrimitiveMesh`)**: Grounded dark fibrous rosette heart (`0.75–0.79×` root AO) + **10 arching pinnate fronds in 2 tiers** (6 lower spreading + 4 inner crown), each sculpted with a slender curved central rachis stem lined with **5 pairs of distinct V-cupped lance pinnae separated by real open air gaps** + pointed terminal leaflet (`UV2` wind-sway + `1.08×` UNORM8 sunlit tip headroom) — harmonizing seamlessly with `Q2B` `jungle_fern.glb` AND Local-GPU M22C's painterly `foliage_wind.gdshader` ground-flora smoothing!
- **Slender Multi-Tuft Arching `GrassClumps` + Golden Seed Plumes (`194` tris)**: **28 slender gracefully tapering curved grass blades** (`base_half_w = 0.026..0.042 m`) across 3 organic sub-tufts PLUS **3 tall sunlit golden-ochre plumed coastal seed-stalks** (`0.80..0.96 m` tall) — banishing banana-wide grass silhouettes forever!
- **Layered Botanical `HibiscusShrubs` (`254` tris)**: **16 sleek multi-tiered serrated glossy leaves** + **6 vibrant cupped 5-petal blossoms** with protruding golden stamen stalks!
- **Shore Pebble Trail Exclusion & Warm Sandstone Cobbles**: Passed `trail_ctx` into `_place_shore_pebbles()` (verified **`0` pebbles on walkable trails** across all 14 islands; `get_placed_pebble_positions()` exposed for automated tests!) and warmed cobble #2 from cool blue-grey to weathered coral-sandstone ochre.
- **Complete Wave I-4..I-11 Landmark Keepouts (`_prop_keepout_radius`)**: Registered all 26 Wave I-4..I-11 landmark prefixes (intentionally leaving `ObeliskGate` and `TrailFootbridge` open so stepping stones flow straight through!) so foliage & pebbles never clip decks, shrines, huts, carts, or plazas.

### 2. Four NEW Zero-Extra-VRAM Story-Craft Landmarks (`tools/blender/_landmarks_story_craft.py` [NEW] -> `46` GLBs Total!)
All built in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear `COLOR_0`, deep buried anti-float foundation skirts `-2.65..-3.80 m`, `col_*` colliders, flickering `Lantern_*` empties, Cycles turnaround QA'd) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` root PNGs, `26 MB` total on disk!)**:

| New Wave I-11 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (18 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_tavern_supply_cart.glb` | 3,252 | 387 KB | 1 (`_body`) | `Lantern_Cart` | **5 bustling harbours & camps** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Smuggler's Cove`, `Cutlass Cay`) | Weathered 10-spoke iron-rimmed wooden harbour cargo handcart atop `-2.65 m` cobbled apron loaded with rum casks, chest, tarp, coiled rope & warm lantern |
| `sunken_anchor_memorial.glb` | 3,356 | 443 KB | 2 (`_base`, `_shank`) | `Lantern_Anchor` | **5 coastal shoals & points** (`Wrecker's Shoal`, `Siren's Tooth`, `Gull's Arch`, `Port Scoundrel`, `Barnacle Haven`) | `7.1 m` salt-crusted iron galleon anchor impaled diagonally into mossy limestone pedestal (`-3.60 m`), interlocking forged chains, wind-whipped crimson pennant (`UV2`) & storm lantern |
| `ancient_sun_dial_plaza.glb` | 3,254 | 453 KB | 2 (`_dais`, `_gnomon`) | `Lantern_Sundial` | **4 sunlit temple & ridge vistas** (`Emerald Spire`, `Sovereign's Bastion`, `Crescent Atoll`, `Cutlass Cay`) | Stepped octagonal mossy temple dais (`-3.40 m` skirt), golden brass sunburst compass inlays, turquoise sun-rune gnomon, draped wind-swaying vines (`UV2`) & altar brazier |
| `volcanic_obsidian_fissure_vent.glb` | 3,108 | 395 KB | 2 (`_base`, `_chimney`) | `Lantern_MagmaVent` | **4 volcanic & cursed flanks** (**3** on `Cinder Crag` ridges/approach + **1** on `Skull Bluff` hollow) | `6.0 m` jagged columnar black-basalt chimney (`-3.80 m` skirt) split by a recessed blazing molten-orange magma fissure core, sulfur-encrusted rims & iron warning chains |

### 3. Local-GPU Milestone 22A Micro-Polishes & Cutlass Cay Cliff-Foot Sculpting (`src/world/island_landmarks.gd`)
1. **`VIS_RANGE_MID := 380.0` (20 Mid-Scale Ground/Cove GLBs in `MID_RANGE_FILES`!)**: Tightened offshore culling from `520 m -> 380 m` per Local-GPU M22A's exact GPU diagnosis AND added all 4 new Wave I-11 GLBs to `MID_RANGE_FILES` — keeping tall iconic skyline landmarks crisp at `2,200 m` while trimming nearby offshore island cove props to pull `Archipelago` GPU cleanly under **`~0.42–0.43 ms`** (`< 0.45 ms` cap!).
2. **`TempleStairway` Upper-Landing Twin-Obelisk Bank Clearance (`_place_temple_stairway`)**: Added left/right bank-height validation at `top_p +- side_dir * 3.4 * scale_f` fixing Local-GPU M22A's `t2_emerald_wf` catch so both twin obelisk pillars stand cleanly clear of Emerald Spire's curving canyon bank!
3. **Cutlass Cay Trail-Wall Cliff Foot Sculpting**: Added grounded `CliffButtressWide_TrailWall` + `MossyBoulderCluster_TrailFoot` breaking up the bare sandstone wall foot behind Cutlass Cay's Golden Cove trail!

---

## 2. Verification Gate & Visual Audit (Rebased Cleanly Onto Cloud Lead Passes 1–4 `d46ddd6`!)

- **`python3 tools/lint.py`**: **PASS — `141 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **46** GLBs sharing strictly **`30` BC7 PNGs** (`0` non-shared root PNGs, `26 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 46 GLBs (non-shared: 0)`, `grass=194 / fern=326 / hibiscus=254` tris, `59` Cutlass Cay pebble clusters checked / **`0` on-trail**, `trail_verts=2040`, `stepping_stones=1371`, `butterflies=285`, `shore_crabs=221`, `overhang_shelves=0`, `carts=5 anchors=5 sundials=4 vents=4`, ALL 4 Wave I-11 GLBs verified in `MID_RANGE_FILES`, `Emerald Spire *Waterfall* -> IslandWaterfall`, AND **`159 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_island.gd`: **`19/19 PASS` (`0` leaks)** (incl. `Q2B` flora & `Q3B` `IslandWildlife`)!
  - `test_beasts.gd`: **`12/12 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
- **Wave I-11 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` expanded `25 -> 30` shots — ALL 6 Wave I-11 captures inspected via `view_file`!)**:
  - `w11_gallery_story_craft` (`KEY_H`): All 4 brand-new landmarks crisp, grounded & vivid!
  - `w11_onfoot_cutlass_trail` (`2.2 m` eye height A/B vs Wave I-10): Massive eye-height botanical jump — blocky rosette replaced by feathery pinnate ferns, slender arching grass with golden seed plumes, `0` pebbles on dirt trail, sculpted cliff-foot rocks!
  - `w11_onfoot_emerald_canyon` (`2.2 m` eye height): `TrailFootbridge_Canyon` -> `ObeliskGate_Trail` -> waterfall canyon, `SundialPlaza_Canyon` sunlit to the left, feathery ground cover & slate flagstones!
  - `w11_onfoot_smugglers_cove` (`2.2 m` eye height): `SmugglerJetty_Cove`, `HarbourCrane_Cove`, `BeachedRowboat_Hidden`, `PirateCamp_HiddenCove`, `SmugglersGrotto`, `CliffCatwalkPier_Cove` & pinnate ferns on rippled sand!
  - `w11_onfoot_crescent_lagoon` (`2.2 m` eye height): Slender plumed meadow grass foreground framing `CoastalSeaArch_Lagoon`, `FishingHut_Lagoon`, `TidalCoralArch_LagoonW`, & turquoise lagoon!
  - `w11_onfoot_cinder_caldera` (`2.2 m` eye height): Volcanic approach trail through `VolcanicObsidianArch_Portal` framing blazing lava river, glowing `ObsidianVent_Approach` on left hillside & towering `VolcanicBasaltSpire`s!

---

## 3. Direct Sync With Cloud Lead (`Q27`) & Local-GPU (`Q-I12`)!

- **Ready for Instant 3-Way Studio Merge Onto `ccr-663b66a0-rdiq4f` (`d46ddd6`)**: Clean 8-commit stack (`Wave I-4` .. `Wave I-11`) touching ONLY exclusive island-architect files (`0` conflicts with Cloud Lead or Local-GPU `1568d4f`!).
- **Open Question `Q-I12` (for Local-GPU Milestone 23)**:
  - Once **Wave I-11 (`46` GLBs, STILL `30` shared BC7 PNGs!)** runs fused with your **Milestone 22C painterly `foliage_wind.gdshader`** + **M21B calibrated `island_shader.gdshader`**:
    1. Did tightening `VIS_RANGE_MID` `520 -> 380 m` (with all 20 mid-scale ground/cove GLBs in `MID_RANGE_FILES`) pull `sailing HIGH` `Archipelago` GPU delta comfortably under **`0.45 ms`** (`~0.42–0.43 ms`) even with `159` grounded landmarks?
    2. How do our new **326-tri pinnate `JungleFerns`**, **194-tri slender plumed `GrassClumps`**, and **254-tri `HibiscusShrubs`** look on RX 9070 XT paired with your Milestone 22C painterly normal smoothing & root AO in `onfoot_cutlass_trail`, `onfoot_emerald_canyon`, `onfoot_crescent_lagoon`, and `onfoot_cinder_caldera` — AND did our `TempleStairway` upper-obelisk clearance check seat Emerald Spire's twin obelisks cleanly in `shot=emerald_waterfall`?
    3. Does `42 -> 46` GLBs hold exact **`+0.0 MB` `tex_vram`** (`287.6 MB`)? Any remaining visual seam anywhere across all 14 islands we should polish in **Wave I-12**?
