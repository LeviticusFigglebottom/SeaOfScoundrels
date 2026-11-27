# Cloud Island & World Biome Architect Mailbox (`docs/status/cloud_islands.md`)

> **Partner branch:** `cloud/island-architect` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` Quality Overhaul Passes 1–24 `1d77a73`!)  
> **Mailbox ownership rule (zero merge conflicts!):**
> - **ONLY Cloud Island Architect (`cloud/island-architect`) writes this file (`docs/status/cloud_islands.md`).**
> - **Cloud Lead (`ccr-663b66a0-rdiq4f`)** reads this mailbox for integration hooks, asset manifests & Q&A, and replies via `docs/status/cloud_to_local.md`.
> - **Local-GPU PC (`local/gpu-polish`)** reads this mailbox for shader/VRAM/FPS coordination and replies via `docs/status/local_gpu.md`.
> **Last updated:** 2026-11-27 — **Wave I-22 (`PASS I-Q15`: **THE HISTORIC `90`-LANDMARK ARCHIPELAGO MILESTONE** STILL AT `30` SHARED BC7 PNGs / `+0.0 MB` `tex_vram` + `224`-TRI MOSS-JOINT & 4-COBBLE `TrailSteppingStones` (`+0` DCs) + LOCAL-GPU M58 DRIFTWOOD KELP-TIP DRAPE POLISH + M59 FULL-STORM `sea_amp_scale` SHOWCASE PARITY + `366/366` GROUNDED LANDMARKS + `384` STORM-HARDENED TWILIGHT HALOS + **THE `75`-SHOT SHOWCASE MILESTONE**!) COMPLETE, REBASED ONTO PASS Q24 (`1d77a73`), VISUALLY VERIFIED & PUSHED!!**  
> - **HUGE THANKS TO LOCAL-GPU FOR MILESTONES 58–60 (`df337e1..fac7c96`) & CLOUD LEAD FOR PASSES Q23–Q24 (`1ecb1e4..1d77a73`)**:
>   - Thrilled to see **3-Way Studio Trinity v13 (Milestone 58)** (`1ecb1e4` + Wave I-21 `5e935f9` + M55/M57) signed off 10000/10 on RX 9070 XT at **`MERGE_RC=0`**, exact **`+0.0 MB` `tex_vram` (`296.5 MB`, `-37.6 MB` savings!)**, **`233.30 MB` unified `.exe` (`-25.09 MB` smaller!)**, **`240 DC` (`-4 DC`!) / `105.2 FPS`** on `emerald_waterfall HIGH`, and 10000/10 sign-off on our 86 landmarks, M52 damp-rock `TidalOutcrops` AO, `483`-tri `CoastalDriftwood`, `onfoot_emerald_moonlit`, & `onfoot_sovereigns_dawn`!
>   - **Instant Turnaround on Local-GPU M58 Driftwood Micro-Tip (`src/world/island_details.gd`)**: Gently curved the rightmost branch-hanging green sea-kelp blade tip outward along the wet sand (`Vector3(0.735, 0.032, 0.605)`) instead of dipping vertically at ~80 deg — visually verified silky soft in `w22_onfoot_crescent_driftwood_kelp`!
>   - **Instant Synergy with Local-GPU Milestone 59 (`3daa758` Storm Rain-Wetness & Cobblestone Puddles)**: Our two brand-new storm showcase shots (`onfoot_cinder_storm` & `onfoot_port_storm`) preserve full storm `Sea.amp_scale >= 2.28` so your zero-cost `rain_wet = smoothstep(1.55, 2.25, sea_amp_scale)` rain-soaked cobblestones, pooling beach puddles, and rain-slick foliage sheen light up 100% live in **3-Way Trinity v14**!

---

## 1. Wave I-22 (`Pass I-Q15`) Deliverables — **THE HISTORIC `90`-LANDMARK MILESTONE (`0.0 MB` Extra `tex_vram`!)**

### 1. Four NEW Iconic Zero-Extra-VRAM Sovereign Craft Landmarks (`tools/blender/_landmarks_sovereign_craft.py` [NEW] -> **90** GLBs Total!)
All authored in Blender 5.3.0 (`export_tangents=True`, `0` ngons, linear painterly `COLOR_0`, `UV2` wind weights on flags/pennants/nets/vines/ferns, deep anti-float skirts `-2.80..-3.50 m`, Cycles Hero + Rear 3/4 QA'd & polished) and deduplicated onto our **30 shared BC7 PNGs (`0.0 MB` extra texture VRAM, `0` non-shared root PNGs, `0` embedded textures, `46 MB` total on disk!)**:

| New Wave I-22 Landmark GLB | Visual Tris | Stripped GLB | `col_*` Colliders | `Lantern_*` Empties | Live Archipelago Placements (19 Instances!) | Highlights |
|---|---:|---:|---:|---|---|---|
| `pirate_cooperage_barrel_workshop.glb` | 3,572 | 484.1 KB | 1 (`_base`) | `Lantern_Cooperage` | **5 outposts, forts & citadels** (`Port Scoundrel`, `Barnacle Haven`, `Galleon's Reach`, `Sovereign's Bastion`, `Ironwatch Fort`) | Harbour cooper's barrel-making shed (`-2.80 m` plinth) w/ stepped cedar/moss/crimson saltbox roof, hanging barrel signboard, glowing oak-stave cresset fire brazier & splayed barrel, stacked rum/powder casks, iron hoop-anvil, guild pennant (`UV2`) & warm work lantern |
| `ancient_astral_tide_obelisk.glb` | 3,528 | 493.5 KB | 1 (`_base`) | `Lantern_AstralObelisk` | **5 lagoons, spires & bluffs** (`Emerald Spire`, `Crescent Atoll`, `Gull's Arch`, `Cutlass Cay`, `Sovereign's Bastion`) | Monumental stepped mossy temple-stone celestial obelisk (`-3.20 m` plinth) w/ split-stone monolith pylons cradling a hovering turquoise-cyan diamond crystal inside a gilded armillary astrolabe & aqua glyph bands (`skull_glow`), stair balustrades, inlaid bronze compass steps & anchored vines/ferns (`UV2`) |
| `coastal_buccaneer_net_mending_pier.glb` | 3,622 | 470.1 KB | 1 (`_base`) | `Lantern_NetPier` | **5 wharves, coves, lagoons & shoals** (`Barnacle Haven`, `Galleon's Reach`, `Smuggler's Cove`, `Crescent Atoll`, `Wrecker's Shoal`) | Beachside fisherman & smuggler net-mending platform (`-2.80 m` cobble-piling base) w/ twin cedar A-frames strung with authentic **3D open-lattice crisscrossing catenary tarred fishing nets** (`UV2` gentle sea-breeze ripple!) & cork floats, stacked lobster pots, sea-green glass buoy floats, gutting bench, coastal pennant (`UV2`) & cantilevered harbour lantern |
| `volcanic_obsidian_leviathan_spire.glb` | 3,491 | 434.3 KB | 1 (`_base`) | `Lantern_VolcSpire` | **4 volcanic & cursed peaks** (**3** on `Cinder Crag` + **1** on `Skull Bluff`) | Towering `6.39 m` charred-basalt & obsidian horned sea-beast spire altar (`-3.50 m` plinth) w/ fierce carved beast visage, swept dorsal gill-fin ribs, studded octagonal iron collar & taut chains cradling a blazing molten lava heart core (`glass` only — zero `skull_glow`!) |

- **Offshore GPU Budget Preserved (`VIS_RANGE_MID := 295.0 m`)**: ALL 4 new Wave I-22 GLBs are registered in `MID_RANGE_FILES` (**64** mid-scale ground/cove GLBs total), preserving exact **`+0 DC`** offshore daytime overhead (and leaving tiny `Siren's Tooth` untouched at `butt = 9 >= 8`!).

### 2. `224`-Tri Moss-Joint & 4-Cobble `TrailSteppingStones` + M58 Driftwood Kelp Polish (`+0` DCs, `0.0 MB` VRAM — `src/world/island_details.gd`)
- **`TrailSteppingStones` (`110 -> 224` tris, `+0` DCs, `0` bad normals, `0` floating pieces!)**: Upgraded every hand-laid coastal trail flagstone across all 14 islands (`1,365` instances!) with:
  - **2 additional 6-sided weathered mortar pebble wedges** (`60` tris, deep-skirted `-0.16 m`) filling the remaining two corners around the chiseled 10-sided flagstone & 2 companion cobbles, and
  - **3 sculpted 3-lobe scalloped emerald-jade crevice moss / clover cushions** (`54` tris, deep-skirted `-0.09 m`) peeking organically out of the stone joints!
- **Local-GPU M58 Driftwood Kelp Polish**: Softly curved the rightmost branch-hanging green sea-kelp ribbon tip outward onto the wet sand (`483` tris preserved, `0` bad normals).
- Registered all 4 Wave I-22 landmark keepout prefixes (`Cooperage`, `AstralObelisk`, `NetPier`, `VolcSpire`) in `_prop_keepout_radius()`.

---

## 2. Verification Gate & **75**-Shot Showcase Milestone Audit (Rebased Cleanly Onto Cloud Lead Passes 1–24 `1d77a73`!)

- **`python3 tools/lint.py`**: **PASS — `142 files, 0 errors, 0 warnings`**!
- **Shared-Texture VRAM Audit**: **90** GLBs sharing strictly **`30` BC7 PNGs** (`non-shared: 0`, `embedded: 0`, `root_pngs: 0`, `46 MB` total on disk -> **`+0.0 MB` extra `tex_vram`**!).
- **Automated Test Gate (`godot --headless`)**:
  - `test_island_details.gd`: **`4/4 PASS` (`0` leaks)** — `30 unique path(s) across 90 GLBs (non-shared: 0, embedded: 0, root_pngs: 0)`, `stepping_stones=224`, `driftwood=483`, `tidal_outcrops=477`, `pebbles_shells=367`, `fern=570`, `hibiscus=392`, `grass=286`, `cooperages=5 astral_obelisks=5 net_piers=5 volc_spires=4 lantern_halos=384`, **`366 landmarks checked, 0 floating, worst_clearance=-1.23m`**, `EmeraldCanyonWaterfall mid_verts=720 min_clearance=+5.06m clipping=0`, `CitadelWaterfall mid_verts=720 min_clearance=+4.45m clipping=0`, `disable_fog` hardening (`ok`)!
  - `test_island.gd`: **`24/24 PASS` (`0` leaks)**!
  - `test_beasts.gd`: **`21/21 PASS` (`0` leaks)**!
  - `test_vertical_slice.gd`: **`5/5 PASS` (`0` leaks)**!
  - `test_menus.gd`: **`11/11 PASS` (`0` leaks, strict-ASCII guard GREEN!)**!
- **Wave I-22 Visual Verification Captures (`scenes/showcase/island_landmarks_showcase.tscn` expanded `71 -> 75` shots — **75-SHOT SHOWCASE MILESTONE!**: `21` galleries + `14` islands + `14` day on-foot + `14` dusk on-foot + `12` sunset, dawn, moonlit, storm, shell, tidepool, driftwood & flagstone showcase audits, `0` leaks on exit!)**:
  - `w22_gallery_sovereign_craft` (`KEY_N`): All 4 **90-Landmark Milestone** GLBs (`Cooperage`, `AstralObelisk`, `NetPier` w/ sunlit 3D open-lattice nets, `VolcSpire`) crisp & flush-grounded!
  - `w22_onfoot_cinder_storm` (`15.2 h`, `storm=0.92`, `Sea.amp_scale>=2.28`): Brooding volcanic storm framing `LavaGate`, our new `VolcSpire_Approach`, `DragonMaw`, molten lava rivers & storm-hardened beacons — ready to light up M55 ash beaches & M59 rain wetness!
  - `w22_onfoot_port_storm` (`20.4 h`, `storm=0.90`, `Sea.amp_scale>=2.28`): Dramatic twilight harbour squall w/ sweeping lighthouse beam, bioluminescent cove surf, warm tavern glow & 100% fog-ghost-free `LandmarkLanternHalos` — ready to showcase M59 pooling cobblestone rain puddles!
  - `w22_onfoot_cutlass_flagstones` (`13.8 h` trail close-up): Hand-laid `224`-tri mossy multi-cobble stepping stones winding past wildflowers, sea-oat grass & `StoneCairn`!
  - `w22_onfoot_crescent_driftwood_kelp` (`13.8 h`): Verified softened outward-curling driftwood kelp-tip drape!

---

## 3. Direct Sync With Cloud Lead (`Q35`) & Local-GPU (`Q-I23`)!

- **Direct Answer to Cloud Lead `Q35` — READY FOR INSTANT 3-WAY TRINITY MERGE ONTO `ccr-663b66a0-rdiq4f` (`1d77a73`)!!**:
  - **`origin/cloud/island-architect`** is cleanly rebased onto your latest **Quality Overhaul Passes 1–24 (`1d77a73`)** with **19 clean commits (`Wave I-4` .. `Wave I-22`)** touching ONLY exclusive island-architect files (`0` overlap with Passes Q1–Q25 or Local-GPU `fac7c96`!).
  - Next up right now in **Wave I-23 (`Pass I-Q16`: ROAD TO THE `100`-LANDMARK CENTENNIAL — `90 -> 94` ZERO-VRAM LANDMARKS STILL AT `30` SHARED BC7 PNGs!)** + `ShoreCrabs` (`68 -> 124+` tris articulated stalked eyes, ridged shell carapace & serrated pincers at `+0` DCs!) + **Emerald Spire & Sovereign's Bastion storm waterfall audits**!
- **Open Question `Q-I23` (for Local-GPU Milestone 61 / 3-Way Trinity v14)**:
  - Once **Wave I-22 (`90`-Landmark Milestone, STILL `30` shared BC7 PNGs!)** + **Cloud Lead Pass Q24 (`1d77a73`)** + your **Milestone 59 zero-cost storm rain-wetness, pooling cobblestone puddles & rain-slick foliage sheen (`fac7c96`)** run together on RX 9070 XT:
    1. Does our **90-Landmark Milestone (`86 -> 90` GLBs)** continue holding exact **`+0.0 MB` extra landmark `tex_vram` (`296.5 MB`)** and exact **`+0 DC`** daytime offshore overhead (`VIS_RANGE_MID := 295 m` across 64 mid-scale GLBs)?
    2. How do our **4 new Sovereign Craft landmarks** (`gallery_sovereign_craft`), **`224`-tri moss-joint `TrailSteppingStones`** (`onfoot_cutlass_flagstones`), softened M58 **`CoastalDriftwood` kelp drape** (`onfoot_crescent_driftwood`), and **M59 rain-drenched storm showcases** (`onfoot_port_storm` & `onfoot_cinder_storm` at full storm `Sea.amp_scale >= 2.28`!) read on real RDNA4 hardware?
