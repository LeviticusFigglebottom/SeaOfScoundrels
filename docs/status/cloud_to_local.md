# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 0. URGENT ALL-STUDIO QUALITY OVERHAUL MANDATE FROM LIVE USER PLAYTEST (2026-11-26 — TOP PRIORITY FOR ALL 3 SESSIONS!!)

The Owner just playtested the live build and flagged **6 concrete quality gaps** that take **#1 PRIORITY OVER ALL NEW SIDE FEATURES** across ALL THREE environments until every single one passes an A+ live bar:

1. **Island Terrain Fidelity, Texture Depth, Logical Pathing, Flora & Fauna (ALL 3 SESSIONS!)**:
   - Owner feedback: *"overall graphical fidelity and texture depth still lacks (just colored mesh terrain, not true detail, logical pathing, flora and fauna, trees look low poly)"*.
   - **ACTION FOR LOCAL-GPU (`origin/local/gpu-polish` — EXCLUSIVE OWNER OF `.gdshader` FILES!)**:
     * **URGENT `src/world/island_shader.gdshader` TEXTURE DEPTH & MICRO-RELIEF OVERHAUL**: Right now our island terrain still reads too much like vertex-tinted smooth mesh rather than rich tactile ground & rock! Please significantly amplify true surface texture depth:
       1. Crank up **crisp near/mid-range triplanar PBR normal & albedo micro-detail** across ALL 4 biomes (distinct wind-rippled beach sand with washed coral pebbles & wet dark-sand tide sheen; rich layered lush grass/clover/loam turf with dark soil patches rather than flat green; dramatic high-contrast fractured sedimentary cliff rock with sharp crevice AO, strata ledges, & deep normal bump; crisp cobblestone/pebbled worn dirt trails wherever `1.0 - COLOR.a` is painted so paths pop unmistakably!).
       2. Push `src/world/foliage_wind.gdshader` to showcase rich veined leaflet translucency, sunlit frond-tip rim backlight, and shaded canopy underside AO so trees never look flat plastic!
   - **ACTION FOR CLOUD ISLAND ARCHITECT (`origin/cloud/island-architect` — EXCLUSIVE OWNER OF `island_generator.gd`, `island_details.gd`, `island_landmarks.gd`, `island_trails.gd`, `archipelago.gd`!)**:
     * **URGENT ISLAND TERRAIN DETAIL, LOGICAL PATHING, FLORA & FAUNA OVERHAUL** (alongside the urgent shared landmark PBR dedup `231 -> ~33` maps!):
       1. **Terrain Detail & Micro-Relief**: Break up smooth rounded colored mesh slopes with sharper terraced rock benches, coastal tide-shelf ledges, eroded gullies, and richer rocky outcrops embedded flush into slopes.
       2. **Logical Storytelling Pathing (`island_trails.gd`)**: Ensure every major island trail forms a **clear, continuous, logical navigable route** from the landing beach/pier -> campsite/lantern posts -> vista overlooks -> fort/ruins/caves/dig clearings, with wider high-contrast `COLOR.a` trail painting, stepping stones/plank bridges across uneven ground, and trail-edge rocks/tufts framing the path!
       3. **Denser Layered Flora & Living Island Fauna (`island_details.gd`, `island_generator.gd`)**: Significantly enrich multi-height island ecology (tall curved palms + lush banyan canopies + dense undergrowth fern/hibiscus clusters + driftwood/tidepool shore props) AND boost visible island fauna (active beach crabs, circling gulls, shoreline seabirds, butterflies/fireflies in lush glades)!
   - **ACTION FOR CLOUD LEAD (`ccr-663b66a0-rdiq4f`)**:
     * Upgrading ALL shared Blender tropical tree & flora props (`tools/blender/gen_props.py` -> `palm_tall.glb`, `palm_curved.glb`, `jungle_banyan.glb`, `bush_fern.glb` + BC7 PBR maps!) from low-poly blocky shapes to **high-detail curved fibrous ringed palm trunks, clustered coconuts, 15–18 deeply-notched pinnate arched palm fronds, multi-buttressed aerial-root banyans with rich layered leaf clusters, and lush multi-tier hibiscus ferns**!
2. **Player & AI Crew Clipping / Back-and-Forth Jittering (Cloud Lead Pass Q1B)**:
   - Enabling Godot 4.8 native **`physics/common/physics_interpolation=true`** + `Pawn` post-`Ship` `physics_process_priority`, fixing `CrewBrain._tick_idle()`'s zero-hysteresis `2.0 m` personal-space oscillation loop (enter `< 1.70 m` / exit `> 2.35 m` + `1.2 s` settle pause + smooth `lerp_angle` turning + main-deck mast/capstan obstacle routing)!
3. **Sailing Speed & Handling Way Too Fast / Twitchy (Cloud Lead Pass Q1A)**:
   - Re-tuning `src/ship/ship.gd` to authentic weighty tall-ship Sea-of-Thieves pacing (Sloop `~10.5–11 kt`, Brigantine `~12.8–13.5 kt`), ~`2x` longer acceleration & gliding coast momentum, slower weighty rudder & wheel turning, and tactile physical sail-hoist / yard-trim pacing!
4. **Helm Wheel Too Large (Blocks Screen) & Missing Directional Indicator (Cloud Lead Pass Q1A)**:
   - Rebuilding BOTH `sloop.glb` & `brigantine.glb` wheels down to sleek waist-to-chest captain height (top spoke cleanly BELOW eye level!), lowering the binnacle & `Lantern_Helm` clear of forward sightlines, pulling `Stand_Helm` slightly aft, sculpting an **unmistakable gilded brass & crimson King Spoke** at 12 o'clock, and adding a **fixed brass rudder-indicator arch + golden lubber-line arrow & compass dial** right behind the top spoke!
5. **Ship Decor Floating / Clipping / Cluttering (Cloud Lead Pass Q1A)**:
   - Removing cluttered mid-foredeck crates/barrels blocking walkways in `gen_sloop.py` & `gen_brigantine.py`, audit-grounding (`0.000 m` flush) EVERY static & runtime ship prop (`CaptainCabinFurnishings`, `ShipSupplyBarrels`, `CookingStove`, `ShipDamageVisuals`, `ShipHarpoon`, `ShipBell`, hammocks, cannonball racks), and visually auditing first-person helm, foredeck, hold & cabin views!
6. **First-Person Held Pirate Hands + Rich Tool Animations + Prominent `[Q]` Item Radial (Cloud Lead Pass Q2A)**:
   - Sculpting **first-person pirate hands, gripping fingers, stitched leather cuffs, and coat sleeves** holding EVERY tool (including two-handed grips for Map, Shovel, Bucket, Planks, Spyglass, Instruments — ZERO floating tools!), overhauling draw/holster/sway/action animations, binding **Item Radial to `[Q]` & `[Tab]`** (Crew Orders to `[G]`), surfacing crisp **`[Q] Tools  [G] Crew`** HUD keycaps, and upgrading `RadialWheel` clarity!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 36 Wrapping Up, Pivoting Immediately Into Quality Overhaul Passes Q1 & Q2!)

- **Latest Pushed Green Commit**: Wave 35 (`b205608` — `138 files 0/0` lint, `220/220` tests `0` leaks, `SeaMermaid` + `AncientMegalodon` visually audited 10/10).
- **Wave 36 Completing Now**: `Anchorball` & `Ballastball` cursed cannonballs + `LocationBanner` cinematic arrival/encounter nameplate cards + `2,312`-tri brass `SpeakingTrumpet` `[T]` crew hail -> integrating & pushing immediately, followed straight by **Quality Overhaul Passes Q1 & Q2**!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR QUALITY OVERHAUL PASSES Q1–Q2 / MILESTONE 14..15 / WAVE I-4..I-5 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Top-Priority Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `tools/blender/{gen_sloop,gen_brigantine,gen_props}.py`, `assets/generated/{sloop,brigantine}.glb`, `assets/generated/props/*`, `project.godot`, `src/ship/*`, `src/characters/*`, `src/crew/*`, `src/items/*`, `src/ui/*`, `src/core/input_setup.gd`, `scenes/main.gd`, `scenes/showcase/ship_showcase.gd`, `tests/*`, `docs/status/cloud_to_local.md` | **Pass Q1A**: Rescaled Helm Wheel + Bold Brass King-Spoke & Binnacle Lubber Pointer + Ship Decor Unclutter/Flush Audit + Weighty Sea-of-Thieves Sailing Overhaul. **Pass Q1B**: Native 3D `physics_interpolation` + Zero-Jitter `Pawn` & `CrewBrain` Hysteresis/Obstacle Routing. **Pass Q2A**: First-Person Sculpted Pirate Hands Holding All Tools + Fluid Animations + Prominent `[Q]`/`[Tab]` Item Radial. **Pass Q2B**: High-Detail Sculpted Tropical Trees, Pinnate Palm Fronds, Buttressed Banyans & Lush Ferns (`gen_props.py`)! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **URGENT Milestone 14 / 15**: (1) **Overhaul `island_shader.gdshader` & `foliage_wind.gdshader` PBR surface depth** per Owner playtest feedback so terrain reads as rich detailed rock/sand/turf/cobble-trails instead of colored mesh! (2) Audit Waves 31–36 + Quality Overhaul shots (`shot=helm_fp`, `shot=fp_cutlass`, `shot=item_radial`, `shot=title_menu`, `shot=play_setup`, `shot=megalodon`, `shot=mermaid`, `shot=powder_keg`, `shot=shipwreck`), verify full gate & rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **URGENT Wave I-4 -> I-5**: (1) Finish Wave I-4 skyline sculpting + **Shared Landmark PBR Texture Dedup (`231 -> ~33` maps)**, AND (2) **Directly address Owner playtest feedback**: deeper micro-terraced rock/ground relief, logical continuous landmark-to-landmark `IslandTrails` pathing with high-contrast borders, denser multi-height flora composition (paired with Cloud Lead's upcoming high-detail Blender palms/banyans/ferns!), and richer live island fauna! |

---

## 3. Direct Action Items & Open Questions
- **Q22 (Local-GPU)**: Can you immediately push an `island_shader.gdshader` + `foliage_wind.gdshader` surface-detail depth upgrade (crisper triplanar rock fractures, pebbled sand ripples, mottled jungle turf, sharp trail borders, sunlit veined foliage) and report real RX 9070 XT close-up terrain renders alongside Milestone 14/15?
- **Q23 (Cloud Island Architect)**: Standing ready to integrate Wave I-4 + shared landmark PBR dedup (`231 -> ~33` maps) + logical trail/flora/fauna depth immediately on push — ZERO overlap with Cloud Lead's `gen_props.py` high-detail tree rebuilds or Quality Overhaul Passes Q1/Q2!
