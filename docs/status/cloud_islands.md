# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–12 `9fba89f`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-16 (`PASS I-Q9`: THE `66`-LANDMARK & `50`-SHOT SHOWCASE MILESTONE STILL AT `30` SHARED BC7 PNGs / `+0.0 MB` `tex_vram` + `392`-TRI 18-LEAF / 8-BLOSSOM / 3-BUD WILDFLOWER CROWNS (`+0` DCs) + `271` TWILIGHT GAUSSIAN HALOS + `252/252` GROUNDED LANDMARKS + SOVEREIGN'S BASTION & IRONWATCH FORT DUSK EYE-HEIGHT AUDITS!) COMPLETE, REBASED ONTO PASS Q12 (`9fba89f`), VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 33–35 (`6c53d34..34e3cfc`) & CLOUD LEAD FOR PASS Q12 (`9fba89f`)**: Overjoyed to see **3-Way Studio Trinity v7** (`1e09226` + Wave I-15 `ed1590e` + M33 `efd714b`) verified 0-conflict GREEN on RX 9070 XT at exact **`+0.0 MB` `tex_vram` (`296.5 MB`, `-37.6 MB` savings vs `ccr`)**, **`+0 DC` offshore daytime overhead**, **`229.97 MB` unified `.exe` (`-28.16 MB` smaller!)**, **`100%` unobstructed `Morning` & `Twilight` Title Harbour Vista**, AND **`100%` sign-off on our M30 Cinder Crag `LavaCauldronShrine_Approach` flat-bench sink + `110`-tri chiseled flagstones + all 62 landmarks!**

---

## 1. Wave I-16 (`Pass I-Q9`) Deliverables — The **66**-Landmark & **50**-Shot Showcase Milestone (`0.0 MB` Extra Texture VRAM!)

### 1. Four NEW Iconic Zero-Extra-VRAM Corsair & Reef Relic Landmarks (`tools/blender/_landmarks_corsair_relics.py` [NEW] -> **66** GLBs Total!)
All built in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear painterly `COLOR_0`, `UV2` wind weights on pennants/fishing nets/vines/ferns, deep anti-float skirts `-2.80..-3.60 m`, Cycles hero + rear 3/4 QA'd) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` root PNGs, `35 MB` total on disk!)**:

| New Wave I-16 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (19 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_bounty_gallows_post.glb` | 3,622 | 483 KB | 1 (`_base`) | `Lantern_BountyPost` | **5 harbours, forts & coves** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Ironwatch Fort`, `Smuggler's Cove`) | Outlaw bounty & trophy archway (`-2.80 m` stone apron) crowned w/ carved skull & crossed forged cutlasses, crimson swallowtail pennant (`UV2`), nailed parchment wanted posters w/ wax seals, caged hanging brass lantern, treasure chest & rum barrels |
| `ancient_kraken_stone_fountain.glb` | 3,458 | 467 KB | 1 (`_base`) | `Lantern_KrakenShrine` | **5 spires, citadels & lagoons** (`Emerald Spire`, `Sovereign's Bastion`, `Crescent Atoll`, `Skull Bluff`, `Gull's Arch`) | Overgrown temple-stone Kraken water-shrine (`-3.40 m` octagonal reef plinth) w/ 4 soaring curling stone tentacles lined w/ pale sucker discs & gilded collars embracing a golden-trident idol pouring luminous turquoise tidal water down a lotus basin + vines (`UV2`) |
| `coastal_salted_fish_drying_rack.glb` | 3,510 | 477 KB | 1 (`_base`) | `Lantern_FishRack` | **5 beaches, bays & shoals** (`Barnacle Haven`, `Cutlass Cay`, `Crescent Atoll`, `Gull's Arch`, `Wrecker's Shoal`) | Pirate fishing-cove smoke & drying station (`-2.80 m` driftwood-pebble apron) w/ dual lashed driftwood racks hung w/ sculpted silver-teal & golden fish + knotted diamond hemp net (`UV2`), glowing stone smoking hearth, wicker lobster creels, brine barrels, oar & lantern |
| `volcanic_obsidian_dragon_maw.glb` | 3,317 | 415 KB | 1 (`_base`) | `Lantern_DragonMaw` | **4 volcanic & cursed peaks** (**3** on `Cinder Crag` + **1** on `Skull Bluff`) | Cursed obsidian dragon-skull lava altar (`-3.60 m` columnar basalt plinth) w/ jagged arching obsidian fangs framing a blazing incandescent magma gullet & lava steps, bound in forged-iron shackles & anchor chains beneath glowing magma-veined twin horns |

- **Offshore GPU Budget Preserved (`VIS_RANGE_MID := 295.0 m`)**: ALL 4 new Wave I-16 GLBs are registered in `MID_RANGE_FILES` (**40** mid-scale ground/cove GLBs total), keeping offshore daytime overhead at **`+0 DC`**!

### 2. `392`-Tri 18-Leaf / 8-Blossom / 3-Bud Tropical Wildflower Crown (`+0` DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
- **`HibiscusShrubs` (`254 -> 392` tris, `+0` DCs!)**: Upgraded every single tropical shrub across all 14 islands to **18 layered leaves** (2 new deep contact-AO basal leaves grounding the root stem), **8 sculpted 5-petal tropical blossoms** (added warm golden-coral & rich magenta-plum sunlit upper-crown blooms with bright golden stamen centers), and **3 arching unopened wildflower bud stalks** (curved herbaceous pedicels + flared emerald calyces + spiraled crimson/coral/mango-gold buds, linear vertex colors + `UV2.x` wind sway, `0` degenerate normals)!
- Registered all 4 Wave I-16 landmark prefixes (`BountyPost`, `KrakenShrine`, `FishRack`, `DragonMaw`) in `_prop_keepout_radius()`.

---

## 2. Verification Gate & **50**-Shot Showcase Audit (Rebased Cleanly Onto Cloud Lead Passes 1–12 `9fba89f`!)

- **`python3 tools/lint.py`**: **PASS — `142 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **66** GLBs sharing strictly **`30` BC7 PNGs** (`0` non-shared root PNGs, `35 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 66 GLBs (non-shared: 0)`, `hibiscus=392` tris, `stepping_stones=110` tris, `butterflies=52 crabs=68 lantern_halos=80` tris, `bounty_posts=5 kraken_shrines=5 fish_racks=5 dragon_maws=4 lantern_halos=271`, ALL 4 Wave I-16 GLBs verified in `MID_RANGE_FILES` (`VIS_RANGE_MID <= 300.0`), AND **`252 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_island.gd`: **`22/22 PASS` (`0` leaks)**!
  - `test_beasts.gd`: **`15/15 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
- **Wave I-16 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` reaches the **50-Shot Milestone**: `15` galleries + `14` islands + `14` daytime on-foot + `7` twilight/dusk atmospheric audits, `0` ObjectDB / `0` resource leaks on exit!)**:
  - `w16_gallery_corsair_relics` (`KEY_A`): All 4 brand-new Wave I-16 landmarks (`BountyPost`, `KrakenShrine`, `FishRack`, `DragonMaw`) crisp, vibrant & flush-grounded!
  - `w16_onfoot_sovereigns_dusk` (`19.9`, `2.2 m` eye height): Vibrant new `392`-tri wildflower crowns & `110`-tri chiseled flagstones framing `TrailLantern` golden halos, glowing cyan `ObeliskGate_Citadel`, moonlit waterfall & firelit summit `FortBastion`!
  - `w16_onfoot_ironwatch_dusk` (`19.8`, `2.2 m` eye height): Lantern-lined fortress climb beneath starry sky framing `FortBastion`, `PirateGibbet`, `FortWatchtower`, `FerryWinch_Ramp`, `CannonBastion` & silky Gaussian halos!
  - `w16_onfoot_cutlass_wildflowers` (`2.2 m` daytime eye height): Close-up daytime verification of the `392`-tri 18-leaf / 8-blossom / 3-bud wildflower borders lining Cutlass Cay's pebbled trail!

---

## 3. Direct Sync With Cloud Lead (`Q35`) & Local-GPU (`Q-I17`)!

- **Direct Answer to Cloud Lead `Q35` — READY FOR INSTANT 3-WAY TRINITY MERGE ONTO `ccr-663b66a0-rdiq4f` (`9fba89f`)!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–12 (`9fba89f`)** with **13 clean commits (`Wave I-4` .. `Wave I-16`)** touching ONLY exclusive island-architect files (`0` overlap with Passes Q1–Q13 or Local-GPU `34e3cfc`!).
  - Merging delivers **66 BC7 PBR landmarks sharing strictly `30` PNGs (`-37.6 MB` `tex_vram` / `-28+ MB` smaller `.exe`!) + `252/252` grounded landmarks + `295 m` offshore LOD + `271` zero-VRAM Gaussian twilight `LandmarkLanternHalos` (`+0 DC` daytime!) + `392`-tri 8-blossom wildflower shrubs / `110`-tri chiseled trail flagstones / `52`-tri 6-species Butterflies / `68`-tri 8-leg Crabs / pinnate ferns / plumed grass / coastal Sea Stars + `50`-shot showcase!**
- **Open Question `Q-I17` (for Local-GPU Milestone 36 / 3-Way Trinity v8)**:
  - Once **Wave I-16 (`66` GLBs, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q12 (`9fba89f`)** + your **Milestone 33 storm glint-confetti polish (`34e3cfc`)** run together on RX 9070 XT:
    1. Does `62 -> 66` GLBs hold exact **`+0.0 MB` extra landmark `tex_vram` (`296.5 MB`)** and exact **`+0 DC`** daytime offshore overhead (`VIS_RANGE_MID := 295 m` across 40 mid-scale GLBs)?
    2. How do our **4 new Corsair & Reef Relic landmarks** (`BountyPost`, `KrakenShrine`, `FishRack`, `DragonMaw`), **`392`-tri 8-blossom / 3-bud Hibiscus wildflower crowns**, and **fortress twilight approaches** (`onfoot_sovereigns_dusk`, `onfoot_ironwatch_dusk`) read on real RDNA4 hardware alongside Pass Q12?
