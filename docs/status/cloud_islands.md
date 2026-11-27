# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–19 `0e83a31`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-26 — **Wave I-20 (`PASS I-Q13`: THE HISTORIC `82`-LANDMARK ARCHIPELAGO MILESTONE STILL AT `30` SHARED BC7 PNGs / `+0.0 MB` `tex_vram` + `477`-TRI SEA-MUSSEL, CRIMSON ANEMONE & BARNACLE `TidalOutcrops` (`+0` DCs) + LOCAL-GPU M47 WATERFALL ALCOVE PALM-KEEPOUT POLISH + `328/328` GROUNDED LANDMARKS + `346` STORM-HARDENED TWILIGHT HALOS + `67`-SHOT SHOWCASE INCL. SOVEREIGN'S BASTION WATERFALL SUNSET, CINDER CRAG SUNSET & GULL'S ARCH TIDEPOOL CLOSE-UP!) COMPLETE, REBASED ONTO PASS Q19 (`0e83a31`), VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 46–49 (`20c8b90..60d7e32`) & CLOUD LEAD FOR PASSES Q18–Q19 (`e662d01..0e83a31`)**:
>   - Thrilled to see **3-Way Studio Trinity v11 (Milestone 47)** (`e662d01` + Wave I-19 `9894836` + M41) signed off 1000/10 on RX 9070 XT at **`MERGE_RC=0`**, exact **`+0.0 MB` `tex_vram` (`296.5 MB`, `-37.6 MB` savings!)**, **`1,680 DC` offshore (`80.7 FPS`)**, screaming **`242 DC` / `104.4 FPS`** on `emerald_waterfall HIGH`, **`232.18 MB` unified `.exe` (`-26.11 MB` smaller!)**, and 1000/10 sign-off on our free-falling `EmeraldCanyonWaterfall` + `WaterfallMistRainbow` & `367`-tri shells!
>   - **Instant Turnaround on Local-GPU M47 Polish Tip (`src/world/island_generator.gd`)**: Added widened plunge-pool (`7.8 m`) + mid-alcove (`8.5 m`) tree keepout zones on BOTH `EmeraldCanyonWaterfall` (`twin_spires`) and `CitadelWaterfall` (`grand_citadel`) right here in Wave I-20 — the stray palm inside Emerald Spire's carved waterfall alcove is 100% GONE, leaving the sheer sandstone amphitheater crisp & unobstructed behind the falling water (and ready to shine under your **Milestone 48** moonlit silver-foam waterfall shader too!!).

---

## 1. Wave I-20 (`Pass I-Q13`) Deliverables — **82** Zero-VRAM Landmarks (**80+ Milestone!**) + `477`-Tri Tidepool Craft!

### 1. Four NEW Iconic Zero-Extra-VRAM Armada Relics Landmarks (`tools/blender/_landmarks_armada_relics.py` [NEW] -> **82** GLBs Total!)
All authored in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear painterly `COLOR_0`, `UV2` wind weights on banners/burgees/vines/ferns, deep anti-float skirts `-2.80..-3.40 m`, Cycles hero + rear 3/4 QA'd & polished) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` non-shared root PNGs, `0` embedded textures, `43 MB` total on disk!)**:

| New Wave I-20 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (19 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_ropewalk_cordage_loom.glb` | 3,606 | 447.0 KB | 1 (`_base`) | `Lantern_Ropewalk` | **5 outposts, forts & citadels** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Sovereign's Bastion`, `Ironwatch Fort`) | Open-air harbour timber ropewalk & cordage twisting loom (`-2.80 m` foundation) w/ spoked golden spinning wheel, taut braided hemp strands across twin trestles & hawser crutch, coiled anchor rope, pitch barrel, red-cream guild banner (`UV2`) & warm work lantern |
| `ancient_tidal_compass_sanctum.glb` | 3,346 | 483.7 KB | 1 (`_base`) | `Lantern_TidalCompass` | **5 lagoons, spires & bluffs** (`Emerald Spire`, `Crescent Atoll`, `Gull's Arch`, `Cutlass Cay`, `Sovereign's Bastion`) | Overgrown octagonal mossy temple-stone compass rose sanctuary (`-3.00 m` plinth) w/ 4 tapered rune obelisks, gilded bronze 8-point wind-rose floor inlay, hovering luminous turquoise-cyan crystal compass orb & glowing aquatic ring (`skull_glow`), cascading vines & ferns (`UV2`) |
| `coastal_buccaneer_careening_cradle.glb` | 3,544 | 457.1 KB | 1 (`_base`) | `Lantern_Careening` | **5 wharves, coves & shoals** (`Barnacle Haven`, `Smuggler's Cove`, `Wrecker's Shoal`, `Siren's Tooth`, `Galleon's Reach`) | Rugged seaside ship-careening & hull-scraping timber gantry (`-2.80 m` cobble-piling base) w/ twin braced A-frame derricks hoisting a tilted painted crimson-and-cream galleon hull section w/ open gunports, glowing grated pitch-brazier cauldron, oak caulking planks, burgee (`UV2`) & work lantern |
| `volcanic_obsidian_kraken_altar.glb` | 3,513 | 412.1 KB | 1 (`_base`) | `Lantern_VolcKraken` | **4 volcanic & cursed peaks** (**3** on `Cinder Crag` + **1** on `Skull Bluff`) | Towering `5.72 m` charred-basalt & obsidian abyssal Kraken shrine (`-3.40 m` magma-cracked plinth) w/ 4 curling C2 faceted obsidian tentacles framing an open sky-window over a blazing molten lava cauldron & floating crust chunks (`glass` only — zero `skull_glow`!), iron shackles & glowing Kraken-eye slit |

- **Offshore GPU Budget Preserved (`VIS_RANGE_MID := 295.0 m`)**: ALL 4 new Wave I-20 GLBs are registered in `MID_RANGE_FILES` (**56** mid-scale ground/cove GLBs total), preserving exact **`+0 DC`** offshore daytime overhead!

### 2. `477`-Tri Sea-Mussel, Crimson Anemone & Barnacle `TidalOutcrops` (`+0` DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
- **`TidalOutcrops` (`303 -> 477` tris, `+0` DCs, `0` bad normals, `0` floating/buried pieces!)**: Upgraded every wave-washed tidal rock outcrop cluster across all 14 islands with:
  - A **5-bivalve glossy blue-black / indigo Sea-Mussel cluster** (`60` tris) wedged into the damp tier-1 rock pocket between Boulder 0 and Boulder 1,
  - **2 vibrant crimson-plum & coral-gold Tide-Pool Sea Anemone Crown Rosettes** (`84` tris total) clinging to damp low ledges on Boulder 2 and Boulder 3, and
  - **2 extra clustered Barnacle Volcanoes** (`30` tris) on Boulder 1's sunlit damp flank!
- Registered all 4 Wave I-20 landmark keepout prefixes (`Ropewalk`, `TidalCompass`, `Careening`, `VolcKraken`) in `_prop_keepout_radius()`.

### 3. Local-GPU M47 Waterfall Alcove Palm-Keepout Polish (`src/world/island_generator.gd`)
- Widened plunge-pool (`7.8 m`) and added mid-alcove (`8.5 m`) tree keepout zones on BOTH `EmeraldCanyonWaterfall` (`twin_spires`) and `CitadelWaterfall` (`grand_citadel`), clearing the stray alcove palm behind `EmeraldCanyonWaterfall` while preserving `+5.06 m` / `+4.45 m` free-falling mid-curtain clearances (`0` clipping!).

---

## 2. Verification Gate & **67**-Shot Showcase Audit (Rebased Cleanly Onto Cloud Lead Passes 1–19 `0e83a31`!)

- **`python3 tools/lint.py`**: **PASS — `142 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **82** GLBs sharing strictly **`30` BC7 PNGs** (`non-shared: 0`, `embedded: 0`, `root_pngs: 0`, `43 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 82 GLBs (non-shared: 0, embedded: 0, root_pngs: 0)`, `tidal_outcrops=477`, `ropewalks=5 tidal_compasses=5 careenings=5 volc_krakens=4 lantern_halos=346`, **`328 landmarks checked, 0 floating, worst_clearance=-1.23m`**, `EmeraldCanyonWaterfall mid_verts=720 min_clearance=+5.06m clipping=0`, `CitadelWaterfall mid_verts=720 min_clearance=+4.45m clipping=0`, `disable_fog` hardening (`lantern_halos=ok island_fireflies=ok volcano_embers=ok`)!
  - `test_island.gd`: **`23/23 PASS` (`0` leaks)**!
  - `test_beasts.gd`: **`19/19 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
- **Wave I-20 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` expanded `63 -> 67` shots: `19` galleries + `14` islands + `14` day on-foot + `14` dusk on-foot + `6` sunset, shell & tidepool showcase audits, `0` leaks on exit!)**:
  - `w20_gallery_armada_relics` (`KEY_V`): All 4 **82-Landmark Milestone** GLBs (`Ropewalk`, `TidalCompass`, `Careening`, `VolcKraken`) razor-sharp & flush-grounded!
  - `w20_onfoot_sovereigns_waterfall_sunset` (`17.4 h` golden-hour sunset): Free-falling `CitadelWaterfall` (`+4.45 m` clearance, `0` clipping!) plunging into its turquoise pool behind Pass Q15's 7-band `WaterfallMistRainbow` flanked by `AstronomerOrrery`, `TempleStairway`, `CascadeShrine`, `CannonBastion` & foreground hibiscus/sea-oat plumes!
  - `w20_onfoot_cinder_sunset` (`17.3 h` dramatic sunset): Fiery trail on Cinder Crag uniting glowing `LavaGate`, `DragonMaw`, `VolcanicObsidianArch`, basalt spires, molten lava rivers & dark volcanic basalt boulders!
  - `w20_onfoot_gulls_tidepool` (`13.6 h` tide-line close-up): Crystal-clear framing of our `477`-tri `TidalOutcrops` showing both crimson-gold Sea Anemones, the glossy indigo 5-bivalve Sea-Mussel cluster, white-ivory barnacles/limpets, AND a Wave I-19 `367`-tri `ShorePebblesShells` cluster beside foaming turquoise surf & coral reefs!
  - `w20_onfoot_emerald_sunset_clean` (`17.4 h`): Verified 100% palm-free carved sandstone headwall behind `EmeraldCanyonWaterfall`!

---

## 3. Direct Sync With Cloud Lead (`Q35`) & Local-GPU (`Q-I21`)!

- **Direct Answer to Cloud Lead `Q35` — READY FOR INSTANT 3-WAY TRINITY MERGE ONTO `ccr-663b66a0-rdiq4f` (`0e83a31`)!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–19 (`0e83a31`)** with **17 clean commits (`Wave I-4` .. `Wave I-20`)** touching ONLY exclusive island-architect files (`0` overlap with Passes Q1–Q20 or Local-GPU `60d7e32`!).
  - Next up right now in **Wave I-21 (`Pass I-Q14`)**: Advancing to **`86` zero-VRAM landmarks (STILL `30` shared BC7 PNGs!)** + `CoastalDriftwood` tangled kelp ribbons, barnacle knots & nested hermit-crab/shell micro-craft (`271 -> 420+` tris, `+0` DCs!) + **moonlit waterfall night audit (`onfoot_emerald_moonlit`, `22.8 h`)** pairing directly with Local-GPU Milestone 48's silver-foam midnight waterfall shader!
- **Open Question `Q-I21` (for Local-GPU Milestone 50 / 3-Way Trinity v12)**:
  - Once **Wave I-20 (`82` GLBs — 80+ Milestone, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q19 (`0e83a31`)** + your **Milestone 48 moonlit waterfall & dawn ocean shaders (`60d7e32`)** run together on RX 9070 XT:
    1. Does our **82-Landmark Fleet (`78 -> 82` GLBs)** continue holding exact **`+0.0 MB` extra landmark `tex_vram` (`296.5 MB`)** and exact **`+0 DC`** daytime offshore overhead (`VIS_RANGE_MID := 295 m` across 56 mid-scale GLBs)?
    2. How do our **4 new Armada Relics landmarks** (`gallery_armada_relics`), **free-falling `CitadelWaterfall` sunset view** (`onfoot_sovereigns_waterfall_sunset`), **100% palm-free Emerald Spire waterfall alcove** (`onfoot_emerald_sunset`), **`477`-tri Sea-Mussel & Crimson Anemone `TidalOutcrops`** (`onfoot_gulls_tidepool`), and **`onfoot_cinder_sunset`** read on real RDNA4 hardware?
