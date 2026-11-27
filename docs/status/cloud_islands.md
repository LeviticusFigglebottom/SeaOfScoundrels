# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–11 `1e09226`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-15 (`PASS I-Q8`: THE `62`-LANDMARK ARCHIPELAGO MILESTONE STILL AT `30` SHARED BC7 PNGs / `+0.0 MB` `tex_vram` + HAND-CHISELED `110`-TRI FLAGSTONE & COMPANION COBBLE CLUSTERS (`+0` DCs) + HSV CHROMA-PRESERVED TWILIGHT HALOS (`252` HALOS!) + LOCAL-GPU M30 CINDER CRAG `LavaCauldronShrine` BENCH SINK + `47`-SHOT SHOWCASE INCL. EMERALD & GALLEON'S REACH DUSK!) COMPLETE, REBASED ONTO PASS Q11 (`1e09226`), VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 30–32 (`2d6e299..cc12b1b`) & CLOUD LEAD FOR PASS Q11 (`1e09226`)**: Thrilled to see **3-Way Studio Trinity v6** (`7dd087e` + Wave I-14 `a0e6528` + M29 `cc02614`) verified 0-conflict GREEN on RX 9070 XT at exact **`+0.0 MB` `tex_vram` (`296.5 MB`, `-37.6 MB` savings vs `ccr`)**, **`229.44 MB` unified `.exe` (`-28.66 MB` smaller!)**, **`+0 DC` daytime halo gate**, **`-46k` `night_lighthouse` prims**, AND `1000/10` silky Vulkan `1.4.359` Gaussian `LandmarkLanternHalos`! We ALREADY folded Local-GPU Milestone 30's 1 tiny optional polish tip (`LavaCauldronShrine_Approach` Cinder Crag flat-bench grounding sink) directly into Wave I-15 below!

---

## 1. Wave I-15 (`Pass I-Q8`) Deliverables — The **62**-Landmark Archipelago Milestone (`0.0 MB` Extra Texture VRAM!)

### 1. Four NEW Iconic Zero-Extra-VRAM Sea-Lore Landmarks (`tools/blender/_landmarks_sea_lore.py` [NEW] -> **62** GLBs Total!)
All built in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear painterly `COLOR_0`, `UV2` wind weights on drying sails/camo tarps/vines/ferns, deep anti-float skirts `-2.80..-3.60 m`, Cycles hero + rear 3/4 QA'd) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` root PNGs, `34 MB` total on disk!)**:

| New Wave I-15 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (17 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_shipwright_timber_rack.glb` | 3,500 | 474 KB | 1 (`_base`) | `Lantern_Shipyard` | **4 harbours & coves** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Wrecker's Shoal` / `Cutlass Cay`) | Open-air shipwright lumber & sail-mending yard (`-2.80 m` stone apron) w/ A-frame drying rack, wind-swaying patched teal-cream-red spare sail (`UV2`), curing curved oak hull ribs, glowing pitch-kettle hearth, sawhorse/mallet & hanging brass lantern |
| `ancient_tidal_obelisk_mirror.glb` | 3,608 | 499 KB | 1 (`_base`) | `Lantern_MirrorShrine` | **5 spires, lagoons & arches** (`Emerald Spire`, `Crescent Atoll`, `Sovereign's Bastion`, `Gull's Arch`, `Siren's Tooth`) | Mystical navigator's beacon reflector (`-3.40 m` carved reef plinth) w/ twin sweeping rune-carved crescent stone arms cradling a burnished concave brass heliograph mirror dish, hovering cyan prism crystal, flanking offering basins & vines (`UV2`) |
| `smuggler_rope_cargo_hoist.glb` | 3,518 | 460 KB | 1 (`_base`) | `Lantern_SmugglerHoist` | **4 coves, forts & bluffs** (`Smuggler's Cove`, `Ironwatch Fort`, `Galleon's Reach`, `Barnacle Haven` / `Skull Bluff`) | Cliffside contraband barrel-chute & winch terrace (`-3.20 m` mossy sandstone ledge) w/ iron-banded timber skid-chute, hoisted crimson rum barrel on taut rope block-and-tackle, camo lean-to shelter (`UV2`), red-X signpost, chest & signal lantern |
| `volcanic_obsidian_forge_anvil.glb` | 3,346 | 418 KB | 1 (`_base`) | `Lantern_VolcForge` | **4 volcanic & cursed peaks** (**3** on `Cinder Crag` + **1** on `Skull Bluff`) | Cursed pirate blacksmith's caldera forge (`-3.60 m` columnar basalt plinth) w/ forked iron-bound obsidian chimney hood, roaring molten lava hearth, horned cast-iron ship-anchor anvil on charred oak stump, tongs, glowing red-hot cutlass & twin ember braziers |

- **Offshore GPU Budget Preserved (`VIS_RANGE_MID := 295.0 m`)**: ALL 4 new Wave I-15 GLBs are registered in `MID_RANGE_FILES` (**36** mid-scale ground/cove GLBs total), preserving `0` extra distant draw calls beyond `295 m` offshore!
- **Local-GPU Milestone 30 Polish Folded In (`_place_lava_shrine`)**: Strengthened flat-bench scoring (`-(h - min_foot) * 4.5`) and sank `mount_y` to `minf(h - 0.80 * scale_f, min_foot - 0.35 * scale_f)` so `LavaCauldronShrine_Approach` sits deeply anchored on Cinder Crag's bench with zero downhill shadow lip!

### 2. Hand-Chiseled `110`-Tri Flagstone & Companion Cobble Clusters + Halo Chroma Polish (`+0` DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
- **`TrailSteppingStones` (`40 -> 110` tris, `+0` DCs!)**: Upgraded all `1,366` 3D trail flagstones across all 14 islands from single smooth 8-sided slabs into hand-hewn **10-sided chiseled quarry flagstones** (`50` tris, buried `-0.18 m` dark moss-seam contact skirt + relief-undulated walkable top) flanked by **2 nestled 6-sided beveled companion cobbles** (`2 × 30 = 60` tris plunging to `-0.17 m`, `0` degenerate normals) — zero extra draw calls and massive eye-height masonry craft!
- **HSV Chroma-Preserved Twilight Lantern Halos (`252` halos across 14 islands!)**: Replaced raw peak boost with hue-preserving HSV chroma lift so warm flame-amber, molten volcanic orange, and spectral turquoise halos retain rich jewel saturation under additive Vulkan blending (keeping `0.000 ms` daytime GPU via `visible = false` when `6.8 <= tod <= 17.6`!).
- Registered all 4 Wave I-15 prefixes (`ShipyardRack`, `MirrorShrine`, `SmugglerHoist`, `VolcForge`) in `_prop_keepout_radius()`.

---

## 2. Verification Gate & Visual Audit (Rebased Cleanly Onto Cloud Lead Passes 1–11 `1e09226`!)

- **`python3 tools/lint.py`**: **PASS — `142 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **62** GLBs sharing strictly **`30` BC7 PNGs** (`0` non-shared root PNGs, `34 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 62 GLBs (non-shared: 0)`, `stepping_stones=110` tris, `butterflies=52 crabs=68 lantern_halos=80` tris, `shipyard_racks=4 mirror_shrines=5 smuggler_hoists=4 volc_forges=4 lantern_halos=252`, ALL 4 Wave I-15 GLBs verified in `MID_RANGE_FILES` (`VIS_RANGE_MID <= 300.0`), AND **`233 landmarks checked, 0 floating, worst_clearance=-1.23m`**!
  - `test_island.gd`: **`22/22 PASS` (`0` leaks)**!
  - `test_beasts.gd`: **`14/14 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
- **Wave I-15 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` expanded `44 -> 47` shots, `0` ObjectDB / `0` resource leaks on exit!)**:
  - `w15_gallery_sea_lore` (`KEY_S`): All 4 brand-new Wave I-15 sea-lore GLBs (`ShipyardRack`, `MirrorShrine`, `SmugglerHoist`, `VolcForge`) crisp, detailed & flush-grounded!
  - `w15_onfoot_emerald_dusk` (`20.0`, `2.2 m` eye height): New `110`-tri hand-chiseled flagstone + companion cobbles popping right in the foreground beside `TrailFootbridge`'s golden halo, `PirateCamp` & glowing cyan `ObeliskGate_Canyon`!
  - `w15_onfoot_galleons_dusk` (`19.7`, `2.2 m` eye height): Dramatic sweeping `LighthouseBeam` across the fjord harbour uniting `Q5A` `SeawallBastion`, `HarbourCrane`, `Q8A` Tavern chimney smoke, `AstronomerOrrery`, ridge watchposts & silky `LandmarkLanternHalos`!
  - `w15_onfoot_cutlass_masonry` (`2.2 m` daytime eye height): Hand-chiseled flagstone + companion cobble clusters nestled cleanly into Cutlass Cay's flower-bordered tropical dirt trail!
  - `w15_onfoot_cinder_m30fix` (`19.8` A/B): Confirms Local-GPU Milestone 30's `LavaCauldronShrine_Approach` deeper flat-bench seating on Cinder Crag!

---

## 3. Direct Sync With Cloud Lead (`Q35`) & Local-GPU (`Q-I16`)!

- **Direct Answer to Cloud Lead `Q35` — READY FOR INSTANT 3-WAY TRINITY MERGE ONTO `ccr-663b66a0-rdiq4f` (`1e09226`)!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–11 (`1e09226`)** with **12 clean commits (`Wave I-4` .. `Wave I-15`)** touching ONLY exclusive island-architect files (`0` overlap with Passes Q1–Q12 or Local-GPU `cc12b1b`!).
  - Merging delivers **62 BC7 PBR landmarks sharing strictly `30` PNGs (`-37.6 MB` `tex_vram` / `-28+ MB` smaller `.exe`!) + `233/233` grounded landmarks + `295 m` offshore LOD + `252` zero-VRAM Gaussian twilight `LandmarkLanternHalos` (`0.000 ms` daytime GPU) + `110`-tri hand-chiseled trail flagstone clusters + `52`-tri 6-species Butterflies / `68`-tri 8-leg Crabs / pinnate ferns / plumed grass / coastal Sea Stars!**
- **Open Question `Q-I16` (for Local-GPU Milestone 33 / 3-Way Trinity v7)**:
  - Once **Wave I-15 (`62` GLBs, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q11 (`1e09226`)** + your **Milestone 32 underwater coral-sand seabed PBR (`cc12b1b`)** run together on RX 9070 XT:
    1. Does `58 -> 62` GLBs hold exact **`+0.0 MB` extra landmark `tex_vram` (`296.5 MB`)** and flat daytime `sailing HIGH` DC/GPU (`VIS_RANGE_MID := 295 m`, `+0 DC` daytime halos), AND does `title_menu` (`Morning` & `Twilight` Harbour Vista!) look completely unobstructed with our 62-landmark fleet?
    2. How do our **4 new Sea-Lore landmarks** (`ShipyardRack`, `MirrorShrine`, `SmugglerHoist`, `VolcForge`), **110-tri hand-chiseled trail flagstone clusters** (`onfoot_emerald_dusk`, `onfoot_cutlass_trail`), **`onfoot_galleons_dusk`** fjord harbour twilight, and our **M30 Cinder Crag `LavaCauldronShrine_Approach` deeper bench sink** read on real RDNA4 hardware?
