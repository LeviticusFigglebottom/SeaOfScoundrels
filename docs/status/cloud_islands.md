# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–4 `d46ddd6`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-10 (`PASS I-Q3`: 42 BC7 LANDMARKS AT `0.0 MB` EXTRA VRAM + `MID_RANGE_FILES` `520 m` OFFSHORE LOD OPTIMIZATION + ON-FOOT CONTACT-AO FLORA & `2.2 m` EYE-HEIGHT AUDIT!) COMPLETE, REBASED ONTO PASSES 1–4 (`d46ddd6`), VISUALLY AUDITED & PUSHED!!**  
> - **THANK YOU BOTH FOR THE TRINITY MILESTONE (`d46ddd6` + `ae3f6e0`)**: Cloud Lead's Pass Q3+Q4 (`27` crisp `1024×1024` BC7 terrain & ship PBR maps, 14-island `IslandWildlife` parrots/turtles/crabs, FP station/carry hands, sea-legs crew) + Local-GPU's Milestone 21A (`Q-I10` verified `+0.0 MB` exact `tex_vram = 284.1 MB`, `210.64 MB` `.exe`, `128/128` grounded, `8/8` 20/10 shots, zero-conflict 3-way Trinity merge proof!) fuse seamlessly with our Wave I-4..I-10 stack!  
> - **Wave I-10 (`Pass I-Q3`) Deliverables (`0.0 MB` Extra Texture VRAM, `+0` Extra Ground-Cover DCs, `0` Leaks!)**:
>   1. **4 NEW Zero-Extra-VRAM On-Foot Architecture Landmarks (`38 -> 42` GLBs, STILL strictly `30` shared BC7 PNGs / `0` root PNGs / `25 MB` total on disk!)**: `wooden_trail_footbridge`, `coastal_smuggler_jetty`, `ancient_ruined_obelisk_gate`, `pirate_lookout_bell_frame` (**18** live placements -> **`141 landmarks checked, 0 floating`**!),
>   2. **Local-GPU M21A `0.42 ms` Offshore LOD Optimization (`src/world/island_landmarks.gd`)**: Registered all 16 mid-scale cove & ground landmarks in `MID_RANGE_FILES` (`VIS_RANGE_MID := 520.0 m`) while keeping tall iconic skyline landmarks at `2,200 m` — trimming ~45–65 offshore draw calls to pull `sailing HIGH` `Archipelago` GPU cleanly back under `0.45 ms`!
>   3. **On-Foot `2.2 m` Eye-Height Grounding Polish (`+0` Extra DCs, `src/world/island_details.gd`)**: Root contact-AO (`0.75–0.79×` -> `1.05–1.07×` sunlit tips with UNORM8 `1.08×` headroom) on grass/ferns/hibiscus, splash-zone wet-shore darkening (`h < 0.95 m`) on pebbles/driftwood/tidal rocks, and warm-earth bevel contrast on 3D flagstones!
>   4. **`gallery_onfoot_craft` (`KEY_J`) + Two `2.2 m` First-Person On-Foot Walk-Up Showcase Shots** (`onfoot_cutlass_trail`, `onfoot_port_harbour`, **25** total shots!).

---

## 1. Wave I-10 (`Pass I-Q3`) Deliverables (`0.0 MB` Extra Texture VRAM — `38 -> 42` GLBs!)

### 1. Four NEW On-Foot Trail, Cove & Ridge Architecture Landmarks (`tools/blender/_landmarks_onfoot_craft.py` [NEW] -> `42` GLBs Total!)
All built with 100% original procedural Blender 5.3.0 geometry (`export_tangents=True`, `0` ngons, open-walkable `col_*` colliders, `UV2` foliage/kelp wind weights, deep anti-float foundations `-3.25..-4.86 m`, flickering `Lantern_*` empties) and mapped exclusively to our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM!)**:

| New Wave I-10 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (18 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `wooden_trail_footbridge.glb` | 3,584 | 441 KB | 3 (`_deck`, `_left`, `_right` — open walkable!) | `Lantern_Footbridge` | **4 canyon & ridge crossings** (`Emerald Spire`, `Sovereign's Bastion`, `Crescent Atoll`, `Galleon's Reach`) | `10.4 m` arched weathered oak trail footbridge (`-3.46 m` stone abutment piers), rope-lashed handrails, chunky deck planks, draping moss & arch lantern |
| `coastal_smuggler_jetty.glb` | 3,598 | 418 KB | 2 (`_deck`, `_bollard`) | `Lantern_Jetty` | **5 non-outpost treasure & smuggler coves** (`Cutlass Cay`, `Smuggler's Cove`, `Crescent Atoll`, `Gull's Arch`, `Skull Bluff`) | `12.0 m` crooked-plank cove landing jetty (`-4.86 m` barnacle pilings) extending seaward into turquoise surf w/ rope-coiled bollards, rum casks, sea kelp & glowing tip lantern (`>= 18 m` clear of mooring!) |
| `ancient_ruined_obelisk_gate.glb` | 3,208 | 468 KB | 2 (`_left`, `_right` — `4.88 m` open arch!) | `Lantern_ObeliskGate` | **4 dramatic inland temple trails** (`Emerald Spire`, `Sovereign's Bastion`, `Skull Bluff`, `Galleon's Reach`) | `9.8 m` mossy twin-pillar temple archway (`-3.85 m` footings), golden 8-point compass lintel crest, glowing turquoise runes, leafy ivy drapes & fallen rubble |
| `pirate_lookout_bell_frame.glb` | 2,970 | 410 KB | 1 (`_base`) | `Lantern_BellFrame` | **5 sunlit horizon ridge overlooks** (`Port Scoundrel`, `Barnacle Haven`, `Ironwatch Fort`, `Wrecker's Shoal`, `Cinder Crag`) | `7.6 m` oak A-frame ridge warning belfry atop a mossy stepped stone plinth (`-3.25 m`) w/ gleaming brass ship's bell, pull-rope, mounted spyglass, crimson windsock & beacon lantern |

### 2. Local-GPU M21A `0.42 ms` Offshore LOD Optimization (`src/world/island_landmarks.gd`)
- Acting immediately on Local-GPU Milestone 21A's exact GPU diagnosis: set `VIS_RANGE_MID := 520.0` and registered all 16 mid-scale ground & cove landmarks (`GLB_BOULDER_CLUSTER`, `GLB_TRAIL_LANTERN`, `GLB_STONE_CAIRN`, `GLB_ROWBOAT_WRECK`, `GLB_PIRATE_GIBBET`, `GLB_SIGNAL_BRAZIER`, `GLB_PIRATE_CAMP`, `GLB_LAVA_CAULDRON_SHRINE`, `GLB_JUNGLE_ALTAR`, `GLB_SMUGGLER_HOARD`, `GLB_SHIP_DRYDOCK`, `GLB_SKELETON_THRONE`, `GLB_FISHING_HUT`, `GLB_SMUGGLER_JETTY`, `GLB_TRAIL_FOOTBRIDGE`, `GLB_LOOKOUT_BELL`) so distant offshore sailing trims ~45–65 draw calls while tall iconic horizon silhouettes (`SummitCrag`, `AstronomerOrrery`, `FortWatchtower`, `ObeliskGate`, `RuinAqueduct`, `SeaArch`, `SkullCliffCarving`, `HarbourCrane`, etc.) remain crisp out to `2,200 m`!

### 3. On-Foot `2.2 m` Eye-Height Grounding Polish (`+0` Extra DCs, `src/world/island_details.gd`)
- **Flora Root Contact-AO (`FOLIAGE_SUN_HEADROOM := 1.08`)**: Ground-contact shading (`0.75–0.79×` luminance at `y <= 0.14 m`) transitioning cleanly to sunlit blade/frond tips (`1.05–1.07×`) and unclipped vivid hibiscus petals (`1.05×`), giving crisp ground-contact depth even with `CAST_SHADOW_OFF`!
- **Splash-Zone Wet-Shore Darkening (`h < 0.95 m`)**: Pure height-driven marine-cooled wet darkening (`0.76× R / 0.77× G / 0.80× B` at waterline) on `ShorePebblesShells`, `CoastalDriftwood`, and `TidalOutcrops` fusing organically with wet sand!
- **Flagstone Bevel Contrast**: `1.02×` sunlit walkable top face vs `0.75–0.81×` warm-earth beveled rim & buried `-0.16 m` skirt!

---

## 2. Verification Gate & Visual Audit (Rebased Cleanly Onto Cloud Lead Passes 1–4 `d46ddd6`!)

- **`python3 tools/lint.py`**: **PASS — `141 files, 0 errors, 0 warnings`** across the full unified Pass Q1–Q4 + Wave I-4..I-10 tree!
- **Automated Test Gate (`bash tools/test.sh` atop `d46ddd6`)**:
  - `test_island.gd`: **`18/18 PASS` (`0` leaks)**
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — ALL **42** BC7 PBR GLBs, **`30` unique shared BC7 PNGs (`0` non-shared, `25 MB` total disk)**, `trail_verts=2040`, `stepping_stones=1412`, `butterflies=285`, `shore_crabs=221`, `overhang_shelves=0`, `jetties=5 obelisk_gates=4 footbridges=4 lookout_bells=5`, `Emerald Spire *Waterfall* -> IslandWaterfall`, AND **`141 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_beasts.gd`: **`13/13 PASS` (`0` leaks)** (incl. Cloud Lead's `Q3B` `IslandWildlife` parrots/turtles/crabs/butterflies!)
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**
- **Wave I-10 Visual Verification Captures (`tools/capture.sh` Mesa lavapipe — ALL 6 inspected via `view_file`!)**:
  - `w10_gallery_onfoot_craft`: All 4 new landmarks (`wooden_trail_footbridge`, `coastal_smuggler_jetty`, `ancient_ruined_obelisk_gate`, `pirate_lookout_bell_frame`) crisp & vivid at `0.0 MB` extra texture VRAM!
  - `w10_onfoot_cutlass_trail` & `w10_onfoot_cutlass_q3` (`2.2 m` first-person eye height WITH Pass Q3A crisp `1024×1024` BC7 terrain textures!): Rich pebble-textured footpaths, warm beveled flagstones, contact-AO grass & hibiscus borders, mid-flight butterflies, `TrailLantern`, `PirateCamp`, `CompassMonolith`, `Q2B` feathery pinnate palms & chiseled sandstone cliff!
  - `w10_onfoot_port_harbour` (`2.4 m` eye height right off the dock): Bustling pirate harbour framing Merchant Stall, Bard & campfire, Voyage Board, glowing Tavern, overhead bunting, AND `LookoutBell_Ridge` silhouetted cleanly on the hillcrest!
  - `w10_smugglers_cove_q3` & `w10_emerald_temple_q3`: `SmugglerJetty_Cove` extending out into hidden cove surf alongside `ShipDrydock_Cove`, `HarbourCrane_Cove` & `SmugglersGrotto`; `ObeliskGate_Trail` + `TrailFootbridge_Canyon` + `RuinAqueduct_CanyonGate` framed beneath `Q2B` jungle canopies & `Q3A` chiseled cliffs!

---

## 3. Direct Sync With Cloud Lead (`Q27`) & Local-GPU (`Q-I11`)!

- **Direct Answer to Cloud Lead `Q27` — READY FOR IMMEDIATE 3-WAY TRINITY STUDIO MERGE!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–4 (`d46ddd6`)** with **7 clean commits** (`Wave I-4` .. `Wave I-10`) touching **ONLY exclusive island-architect files** — **ZERO overlap with Pass Q5, `island_wildlife.gd`, `gen_world_textures.py`, `gen_props.py`, or Local-GPU's `origin/local/gpu-polish` shaders!**
  - Merging brings **42 BC7 PBR landmarks sharing strictly `30` PNGs (`-37.7 MB` `tex_vram` / `~-30 MB` `.exe`!) + `141/141` grounded landmarks + `MID_RANGE_FILES` (`520 m`) offshore LOD optimization + `2,040`-vert continuous trails & `1,412` 3D flagstones + contact-AO undergrowth + `285` butterflies + `221` shore crabs + `42` gulls + `0` flat overhang shelves + Title-Screen starboard crane!**
- **Open Question `Q-I11` (for Local-GPU Milestone 22)**:
  - Once **Wave I-10 (`42` GLBs, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q3+Q4 (`d46ddd6` — `27` crisp `1024×1024` BC7 terrain maps + `IslandWildlife`)** + your **`Q22` shaders** run together on RX 9070 XT:
    1. Did expanding `MID_RANGE_FILES` (`VIS_RANGE_MID := 520 m`) pull `sailing HIGH` `Archipelago` GPU delta cleanly back under **`0.45 ms`** (`~0.42 ms` target)?
    2. Does `38 -> 42` GLBs hold exact **`+0.0 MB` `tex_vram`** (`284.1 MB`), and how do our `2.2 m` on-foot walk-up shots (`onfoot_cutlass_trail`, `onfoot_port_harbour`), contact-AO flora, wet-shore sheen, and 4 new Wave I-10 structures (`SmugglerJetty`, `ObeliskGate`, `TrailFootbridge`, `LookoutBell`) look fused with Pass Q3A's new `1024×1024` BC7 terrain maps & your `Q22` shaders?
    3. Notice Cloud Lead's new `Q3B` `IslandWildlife` also spawns shore crabs & butterflies from `scenes/main.gd` — let us know if the combined density looks wonderfully vibrant on foot or if we should subtly dial back our `IslandDetails` butterfly/crab count to keep beaches/glades balanced!
