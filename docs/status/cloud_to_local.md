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

## 1. Current Cloud Lead Status (2026-11-26 — QUALITY OVERHAUL PASSES 1–8 COMPLETE, VISUALLY AUDITED & PUSHED!!)

- **ALL 8 Quality Overhaul Passes (`Q1A`–`Q8B`) Shipped & Visually Audited (`141 files 0/0` lint, `242/242` PASS, `0` leaks, `3/3` GPU parity, `CLIENT RESULT PASS`, `MAIN_QUIT_EXIT=0`!)**:
  1. **`Q1A` + `Q1B` (Helm, Decor, Weighty Sailing, Zero-Jitter Physics & Crew)**: Rescaled Sloop/Brigantine wheels below eye line + 12-o'clock crimson/brass King Spoke + fixed brass rudder-indicator arch & binnacle compass, flush-grounded/uncluttered deck/hold/cabin props (hidden legacy floating mast `Bell`), weighty tall-ship sailing (`Sloop 10.9 kt`, `Brigantine 13.7 kt`), native Godot 4.8 `physics/common/physics_interpolation=true`, `0.0000 mm` storm-deck station lock, `0` crew reversals & `0` yaw flips over `3.0 s`, and main-deck/hold obstacle routing.
  2. **`Q2A` + `Q4A` + `Q5B` (100% First-Person Hand Presence Across EVERY State + Tactile Animations + Discoverable `[Q]`/`[Tab]` Radial)**: Zero-primitive, zero-extra-VRAM sculpted pirate hands (`1,822` tris/hand) across **all 16 held tools**, **all 6 interactive stations**, **all carried cargo**, **swimming**, and **ladder climbing**; multi-phase animations + look/ship-roll inertia + reload dip; **`[Q]`/`[Tab]` Item Radial** (hold-and-release + quick-tap toggle) + `[G]` Crew Wheel + persistent HUD keycaps; plus 8-spoke wooden helm clicks, sail-hoist rope creaks & shore bird ambiance!
  3. **`Q2B` + `Q3A` + `Q3B` + `Q4B` + `Q5A` + `Q7A` (100% Archipelago Cohesive Prop Craft, `1024×1024` BC7 PBR Textures, Living Wildlife & Crew Sea-Legs)**:
     - **ALL 24 shared island & outpost GLBs harmonized (`318/318` prop `.png.import` files BC7 VRAM compressed, ZERO legacy icosphere blobs or cold-grey rocks!)**: Q2B pinnate palms/banyans/hibiscus ferns, Q5A sandstone `seawall_bastion`/rocks/pier/tavern/warehouse/beacon, AND Q7A `ruin_arch`/`ruin_pillar`, `campfire` (iron cooking tripod + pirate stew cauldron + driftwood bench), `outpost_stall`, `notice_board`, `shipwreck_hulk`, `chest_treasure`, `watchtower_wood`, `timber_bridge` & `dig_mound`!
     - **`Q3A` + `Q3B` + `Q4B`**: All 27 world & ship PBR maps rebuilt at `1024×1024` BC7; living 14-island `IslandWildlife` (`42` Parrots, `27` Sea Turtles, `60` Sand-Crabs, `77` Butterflies/Fireflies); expressive third-person crew lowered helm grip, seated rowing, sea-legs counter-balance & Captain head-glancing.
  4. **`Q6A` + `Q6B` + `Q7B` + `Q8A` + `Q8B` (Living Outpost & Ship Night Atmosphere, Crew Watch HUD, Bell Rally, Ship-Following Seabirds, Combat Juice & Nautical Cartography)**:
     - Warm dusk/night atmospheric lantern halos across BOTH ships (`5`/vessel) & all 3 Outposts (`5`/harbour + `1800 m` beacon glow), dancing `70`-tri campfire flames + rising ember sparks, wind-drifting Tavern chimney woodsmoke, expressive Harbour NPC approach greetings, AND daylight/nocturnal-bioluminescent waterline bow-wave foam ribbons!
     - Interactive Ship's Bell crew rally & 6-tier live ship-status callouts, dynamic ship-following coastal seabird slipstream escorts (`SeabirdFlock`), live top-left **`CREW WATCH`** HUD card, Trading Company renown progress bars & Sloop/Brigantine spec strip, 9-slot strict-ASCII rudder bar, `DirectionalDamageOverlay` threat arcs + parry flash, AND `A-H / 1-8` Ship's Map Table grid + course ray + Pin rhumb line + coastal wave-hatch Treasure Maps!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR QUALITY OVERHAUL PASS Q9 / MILESTONE 14..15 / WAVE I-4..I-5 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Top-Priority Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `tools/blender/{gen_sloop,gen_brigantine,gen_props}.py`, `tools/textures/gen_world_textures.py`, `assets/generated/{ship,props,textures}/*`, `project.godot`, `src/ship/*`, `src/characters/*`, `src/crew/*`, `src/items/*`, `src/ui/*`, `src/core/*`, `src/combat/*`, `src/audio/*`, `src/world/{outpost,island_wildlife,seabirds,sunken_shipwreck,sea_mermaid}.gd`, `scenes/main.gd`, `scenes/showcase/{ship,items,island}_showcase.gd`, `tests/*`, `docs/status/cloud_to_local.md` | **Passes Q1–Q8 DONE & PUSHED (`242/242`, `0` leaks!)** -> **Pass Q9** (Surface-aware `Pawn` footsteps/wading/landing/ladder/swim audio + wading ripples; held-lantern atmospheric halo, damped magnetic compass needle physics & flintlock barrel smoke wisps) + instant zero-conflict integration of Local-GPU & Cloud Island Architect pushes! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **URGENT Milestone 14 / 15**: Pull `origin/ccr-663b66a0-rdiq4f` (Passes Q1–Q8 live!), tune `island_shader.gdshader` & `foliage_wind.gdshader` PBR relief/backlighting on RX 9070 XT for our `Q3A` terrain maps & `Q2B`/`Q5A`/`Q7A` props, audit ALL Quality Overhaul showcase shots (`outpost` dusk & day, `helm_fp`, `carry_chest`, `map_table`, `night_sail`, `beach`), verify `242/242` gate & rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **URGENT Wave I-4 -> I-5**: Finish Wave I-4 skyline sculpting + **Shared Landmark PBR Texture Dedup (`231 -> ~33` maps)** + micro-terraced terrain relief & continuous logical landmark-to-landmark `IslandTrails` pathing (now pairing directly with Cloud Lead's `Q3A` stepping-stone trail PBR, `Q2B`/`Q5A`/`Q7A` props, `Q3B` living `IslandWildlife`, and `Q8A` living outposts!). |

---

## 3. Direct Action Items & Open Questions
- **Q30 (Local-GPU)**: Pull `origin/ccr-663b66a0-rdiq4f` — ALL Pass Q1–Q8 upgrades (`242/242` green, living dusk outposts with chimney smoke & campfire flames, all 24 props harmonized & BC7-compressed!) are live! Ready for RX 9070 XT shader depth polish (`island_shader.gdshader` + `foliage_wind.gdshader`), real-GPU visual audit across all Q1–Q8 shots, and a fresh `build/SeaOfScoundrels.exe`!
- **Q31 (Cloud Island Architect)**: Standing ready to integrate Wave I-4 + shared landmark PBR dedup (`231 -> ~33` maps) + terraced terrain & continuous logical `IslandTrails` pathing immediately on push — zero file overlap with Passes Q1–Q9!
