# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–17 `0a78cd3`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-19 (`PASS I-Q12`: `78` ZERO-VRAM LANDMARKS STILL AT `30` SHARED BC7 PNGs / `+0.0 MB` `tex_vram` + CLOUD LEAD `Q35` `EmeraldCanyonWaterfall` FREE-FALLING CANYON HEADWALL & RECESSED PLUNGE POOL FIX (`+5.06 m` MIN CLEARANCE, `0` CLIPPING!) + 100% `disable_fog = true` STORM HARDENING ACROSS ALL ISLAND ADDITIVE VFX + `367`-TRI SPIRAL QUEEN CONCH & 5-PETAL SAND-DOLLAR `ShorePebblesShells` (`+0` DCs) + `309/309` GROUNDED LANDMARKS + `63`-SHOT SHOWCASE INCL. GOLDEN-HOUR `17.4 h` SUNSET & SHELL CLOSE-UP!) COMPLETE, REBASED ONTO PASS Q17 (`0a78cd3`), VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 43–45 (`9d1df84..c684db7`) & CLOUD LEAD FOR PASSES Q16–Q17 (`bd4d940..0a78cd3`)**:
>   - Electrified to see **3-Way Studio Trinity v10 (Milestone 43)** (`24ff6b1` + Wave I-18 `a74105d` + M41) signed off 1000/10 on RX 9070 XT at **`MERGE_RC=0`**, exact **`+0.0 MB` `tex_vram` (`296.5 MB`, `-37.6 MB` savings!)**, **`-4 DC` net offshore (`1,678 DC`)**, **`231.57 MB` unified `.exe` (`-26.63 MB` smaller!)**, and **100% ZERO fog-ghosts across all `309` storm-hardened `LandmarkLanternHalos`** in `w18_title_storm.png`!
>   - **Cloud Lead `Q35` Emerald Canyon Waterfall Tip — 100% RESOLVED & REGRESSION-TESTED!!**: Carved a dramatic sheer rock headwall amphitheater + recessed emerald plunge basin on `twin_spires` (`src/world/island_generator.gd`) and anchored BOTH `EmeraldCanyonWaterfall` (`720` mid-fall verts, **`min_clearance = +5.06 m`**, `clipping = 0`, foam apron `0.00 m` on recessed pool!) and `CitadelWaterfall` (`720` mid-fall verts, **`min_clearance = +4.45 m`**, `clipping = 0`!) — ready to pair with Pass Q15's `WaterfallMistRainbow` & Local-GPU M41's waterfall shader!
>   - **100% Island-System Storm-Fog `disable_fog = true` Sweep**: Extended our Wave I-18 `disable_fog = true` hardening across ALL 3 remaining additive particle systems in `src/world/island_generator.gd` (`BeaconEmberColumn`, `VolcanoEmberPlume`, `IslandFireflies`), locked with automated assertions in `tests/test_island_details.gd`!

---

## 1. Wave I-19 (`Pass I-Q12`) Deliverables — **78** Zero-VRAM Landmarks + Free-Falling Waterfalls + Coastal Shell Craft!

### 1. Four NEW Iconic Zero-Extra-VRAM Frontier Craft Landmarks (`tools/blender/_landmarks_frontier_craft.py` [NEW] -> **78** GLBs Total!)
All authored in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear painterly `COLOR_0`, `UV2` wind weights on flags/pennants/vines/ferns, deep anti-float skirts `-2.80..-3.50 m`, Cycles hero + rear 3/4 QA'd & polished) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` non-shared root PNGs, `0` embedded textures, `41 MB` total on disk!)**:

| New Wave I-19 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (19 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_powder_magazine_bunker.glb` | 3,600 | 484.9 KB | 1 (`_base`) | `Lantern_PowderBunker` | **5 forts, harbours & coves** (`Ironwatch Fort`, `Port Scoundrel`, `Galleon's Reach`, `Sovereign's Bastion`, `Smuggler's Cove`) | Fortified barrel-vaulted keystone sandstone black-powder magazine (`-3.00 m` ashlar skirt) w/ crimson-cream diamond warning plaque, recessed studded iron-banded oak blast door, stacked crimson powder kegs & brass funnel workbench under eaves, iron vent stack, crimson pennant (`UV2`) & warm warning lantern |
| `ancient_coral_leviathan_altar.glb` | 3,404 | 485.2 KB | 1 (`_base`) | `Lantern_CoralAltar` | **5 lagoons, spires & reefs** (`Crescent Atoll`, `Emerald Spire`, `Gull's Arch`, `Cutlass Cay`, `Sovereign's Bastion`) | Overgrown carved coral-and-temple-stone sea-serpent offering altar (`-3.00 m` stepped temple plinth) crowned by twin sweeping fanged leviathan-jaw arches & guardian head reliefs cradling a hovering luminous turquoise pearl orb & glowing basin runes (`skull_glow`), branching fossil coral horns & cascading vines/ferns (`UV2`) |
| `coastal_boatbuilder_slipway_winch.glb` | 3,548 | 475.8 KB | 1 (`_base`) | `Lantern_BoatSlipway` | **5 wharves, shoals & shores** (`Barnacle Haven`, `Port Scoundrel`, `Galleon's Reach`, `Wrecker's Shoal`, `Siren's Tooth`) | Sloped cobble-and-piling coastal boatbuilder's launch slipway (`-2.80 m` foundation) cradling a sculpted half-planked wooden pirate skiff hull w/ exposed curved oak ribs & crimson-cream sheer strakes, hand-turned capstan hauling winch & taut hawser rope, pitch cauldron, shipyard flag (`UV2`) & hanging work lantern |
| `volcanic_obsidian_ember_totem.glb` | 3,612 | 458.7 KB | 1 (`_base`) | `Lantern_EmberTotem` | **4 volcanic & cursed peaks** (**3** on `Cinder Crag` + **1** on `Skull Bluff`) | Towering `6.52 m` jagged obsidian & dark-basalt pirate-tiki skull fire totem (`-3.50 m` magma-cracked hexagonal basalt pedestal) w/ angular carved brow ridges, blazing molten orange-amber mouth/eye cavities (`glass` only — zero `skull_glow`!), iron restraining chains & spiked magma-crown fire bowl |

- **Offshore GPU Budget Preserved (`VIS_RANGE_MID := 295.0 m`)**: ALL 4 new Wave I-19 GLBs are registered in `MID_RANGE_FILES` (**52** mid-scale ground/cove GLBs total), preserving exact **`+0 DC`** offshore daytime overhead!

### 2. Cloud Lead `Q35` Free-Falling Waterfalls & 100% Additive `disable_fog = true` Hardening (`src/world/island_generator.gd`)
- **`EmeraldCanyonWaterfall` (`twin_spires`)**: Carved a sheer vertical canyon headwall amphitheater + recessed emerald plunge pool (`v = 10.2..19.5 * scale_r`, `|u| < 10.5 * scale_r`), gated mid-slope strata out of the chute, and anchored `reach_e = 17.94 m`, `drop_h = 27.55 m` cleanly onto the exact plunge pool floor (`-14.18 m` buried BEFORE -> **`+5.06 m` min real-mesh mid-fall clearance, `0` clipping** AFTER, foam apron `0.00 m` flush on the recessed pool!).
- **`CitadelWaterfall` (`grand_citadel`)**: Extended `reach_c = 18.12 m`, `drop_h = 25.04 m` cleanly into the level eastern plunge cove (**`+4.45 m` min real-mesh mid-fall clearance, `0` clipping**, foam apron `0.00 m` flush!).
- **100% Storm-Fog Hardening**: Added `.disable_fog = true` to ALL 3 remaining additive particle materials in `src/world/island_generator.gd` (`BeaconEmberColumn`, `VolcanoEmberPlume`, `IslandFireflies`) alongside `LandmarkLanternHalos` (`327` halos in `src/world/island_details.gd`).

### 3. `367`-Tri Spiral Queen Conch & 5-Petal Sand-Dollar `ShorePebblesShells` (`+0` DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
- **`ShorePebblesShells` (`262 -> 367` tris, `+0` DCs, `0` bad normals!)**: Added a sculpted 4-whorl **Spiral Queen Conch / Auger Sea-Snail Shell** (`60` tris, ivory ridges, sand-ochre sutures & rosy-coral flared aperture lip) AND a sculpted **5-Petal Sun-Bleached Tropical Sand-Dollar Medallion** (`45` tris, beveled 10-gon ivory dome with raised 5-petal star rosette) nestled cleanly beside the 5 beveled cobbles, fluted scallop shell & 5-arm coral sea star!
- Registered all 4 Wave I-19 landmark keepout prefixes (`PowderBunker`, `CoralAltar`, `BoatSlipway`, `EmberTotem`) in `_prop_keepout_radius()`.

---

## 2. Verification Gate & **63**-Shot Showcase Audit (Rebased Cleanly Onto Cloud Lead Passes 1–17 `0a78cd3`!)

- **`python3 tools/lint.py`**: **PASS — `142 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **78** GLBs sharing strictly **`30` BC7 PNGs** (`non-shared: 0`, `embedded: 0`, `root_pngs: 0`, `41 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 78 GLBs (non-shared: 0, embedded: 0, root_pngs: 0)`, `pebbles_shells=367`, `powder_bunkers=5 coral_altars=5 boat_slipways=5 ember_totems=4 lantern_halos=327`, **`309 landmarks checked, 0 floating, worst_clearance=-1.23m`**, `EmeraldCanyonWaterfall mid_verts=720 min_clearance=+5.06m clipping=0`, `CitadelWaterfall mid_verts=720 min_clearance=+4.45m clipping=0`, `disable_fog` hardening (`lantern_halos=ok island_fireflies=ok volcano_embers=ok`)!
  - `test_island.gd`: **`23/23 PASS` (`0` leaks)**!
  - `test_beasts.gd`: **`17/17 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
- **Wave I-19 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` expanded `59 -> 63` shots: `18` galleries + `14` islands + `14` day on-foot + `14` dusk on-foot + `3` sunset & shell close-ups, `0` leaks on exit!)**:
  - `gallery_frontier_craft` (`KEY_C`): All 4 Wave I-19 GLBs (`PowderBunker`, `CoralAltar`, `BoatSlipway`, `EmberTotem`) crisp, bold & flush-grounded on the sunlit sandbar!
  - `onfoot_emerald_sunset` (`17.4 h` golden-hour canyon view): Full free-falling `EmeraldCanyonWaterfall` plunging cleanly from the sheer carved headwall into the turquoise plunge pool behind Pass Q15's 7-band `WaterfallMistRainbow` with zero hillside clipping!
  - `onfoot_port_sunset` (`17.4 h` golden-hour harbour overlook): Foreground `570`-tri fiddlehead ferns, `392`-tri wildflowers & `286`-tri sea-oat grass overlooking Port Scoundrel Tavern, pier, crane, cliffside watchpost & erupting Cinder Crag!
  - `onfoot_cutlass_shells` (`13.8 h` low shoreline close-up): Crystal-clear tide-line framing of all 5 cobbles, fluted scallop, 5-arm coral sea star, NEW 4-whorl Spiral Queen Conch & NEW 5-petal Sand-Dollar beside foamy turquoise surf!

---

## 3. Direct Sync With Cloud Lead (`Q35`) & Local-GPU (`Q-I20`)!

- **Direct Answer to Cloud Lead `Q35` — EMERALD WATERFALL FIXED + READY FOR INSTANT 3-WAY TRINITY MERGE ONTO `ccr-663b66a0-rdiq4f` (`0a78cd3`)!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–17 (`0a78cd3`)** with **16 clean commits (`Wave I-4` .. `Wave I-19`)** touching ONLY exclusive island-architect files (`0` overlap with Passes Q1–Q18 or Local-GPU `c684db7`!).
  - Next up right now in **Wave I-20 (`Pass I-Q13`)**: **THE HISTORIC `82`-LANDMARK MILESTONE (surpassing 80 zero-VRAM landmarks STILL at strictly `30` shared BC7 PNGs!)** + `TidalOutcrops` barnacle/mussel/anemone micro-craft (`+0` DCs) + golden-hour sunset audits of Sovereign's Bastion `CitadelWaterfall` & Cinder Crag!
- **Open Question `Q-I20` (for Local-GPU Milestone 46 / 3-Way Trinity v11)**:
  - Once **Wave I-19 (`78` GLBs, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q17 (`0a78cd3`)** + your **Milestone 41 golden-hour waterfall & foliage rim shaders (`c684db7`)** run together on RX 9070 XT:
    1. Does our **78-Landmark Fleet (`74 -> 78` GLBs)** continue holding exact **`+0.0 MB` extra landmark `tex_vram` (`296.5 MB`)** and exact **`+0 DC`** daytime offshore overhead (`VIS_RANGE_MID := 295 m` across 52 mid-scale GLBs)?
    2. How does our newly carved free-falling **`EmeraldCanyonWaterfall` + recessed plunge basin** (`onfoot_emerald_sunset` & `shot=emerald_waterfall`) read paired with Pass Q15's `WaterfallMistRainbow` and your Milestone 41 cool-emerald / golden-foam waterfall shader, plus our **4 new Frontier Craft landmarks** (`gallery_frontier_craft`), **`367`-tri Spiral Conch & Sand-Dollar `ShorePebblesShells`** (`onfoot_cutlass_shells`), and **`onfoot_port_sunset`** backlit golden-hour foliage on real RDNA4 hardware?
