# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 29 + Local-GPU Milestone 11 VERIFIED & INTEGRATED! Launching Wave 30 Immediately!)

### Verified Green Wave 29 + Milestone 11 Gate
- **`python3 tools/lint.py`**: **PASS — `122 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `203 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes new `test_wave29_ship_supply_barrels_geometry_fill_tiers_and_one_press_restock`, `test_wave29_compass_map_pin_bearing_toggle_and_hud_hint`, `test_rowboat_sculpted_geometry_pbr_and_zero_primitives`, and `test_rowboat_stern_docking_launch_oar_rowing_cargo_and_crew_callouts`!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (`max |dh| = 0.0117 m`, `|dn.y| = 0.0005`, `|dvx/z| = 0.0156` across all 24 Gerstner waves with Local-GPU Milestone 11 `ocean.gdshader` & `island_shader.gdshader`!).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op probe synced cleanly).
- **`scenes/main.tscn --quit-after 5`**: **PASS — `MAIN_QUIT_EXIT=0`, `0` errors, `0` warnings, `0` leaks!**

### What Just Landed in Wave 29 + Local-GPU Milestone 11 (`82d973e..1680a64`)
1. **Wave 29A — Lower-Deck Sculpted One-Press `ShipSupplyBarrels` & Tactical Map-Pin Compass Bearing** (`src/ship/ship_supply_barrels.gd` [NEW], `src/ship/ship.gd`, `src/items/{map_table_view,inventory}.gd`, `src/ui/hud.gd`, `tests/{test_ship,test_items}.gd`):
   - **3 Sculpted Coopered-Oak Port-Bulkhead Hold Barrels (`3,084` sculpted tris, 0 primitives, 0 extra VRAM via BC7 ship PBR maps!)**:
     - `CannonballBarrel` (forged-iron hoops + live tiered roundshot stack reflecting `cannonballs_remaining`, one-press `[F]` refill),
     - `PlankBarrel` (forged-iron hoops + live jutting oak repair planks reflecting `planks_remaining`, one-press `[F]` refill),
     - `RationsBarrel` (turned brass hoops + brass tap spigot & drip mug, one-press `[F]` heals `+25 HP` & refills grog!).
   - **Tactical Map-Pin Compass Bearing**: Holding Brass Compass + `[LMB]` toggles between **True North** and **Chart Pin Tracking** (smoothly swinging the damped magnetic spring needle toward your active `MapTableView` pin!), with live strict-ASCII `"Pin: NNE 310 m"` readout on the HUD chip & `&"rowboat_oars"` station hint!
2. **Wave 29B — Sculpted Stern-Docked Rowable `Rowboat` & Crew Callouts** (`src/ship/rowboat.gd` [NEW], `src/crew/{crew_dialogue,crew_brain}.gd`, `scenes/main.gd`, `scenes/showcase/ship_showcase.gd`, `tests/test_rowboat.gd` [NEW]):
   - **`5,496`-tri Sculpted Clinker Oak Dinghy (0 primitives, 0 extra VRAM via BC7 ship PBR maps!)**: Hangs broadside on braided hemp davit slings cleanly **below `ShipNameplate`** on both Sloop & Brigantine (`SLOOP_DOCK_LOCAL`, `BRIG_DOCK_LOCAL`), complete with flared clinker strakes, duckboards, 3 thwarts, twin articulated ash oars (`PortOarPivot` / `StarboardOarPivot`), stern brass boat lantern (synced to `mother_ship.lanterns_lit`), and **4-slot bow cargo thwart** for hauling chests from shallow lagoons & sea caves!
   - **Sea-of-Thieves Oar Rowing & 4-Point 24-Wave Ocean Buoyancy**: `[F]` launch/dock within `8.5 m` of stern davits; `[W]` double-oar surge (`4.83 m/s`), `[A]`/`[D]` crisp port/starboard oar turns (`±1.35 rad/s`), `[S]` backwater brake (`4.83 -> 0.43 m/s`), wake foam, oar splash SFX, and strict-ASCII Barnaby/Maren/Pip `&"rowboat_launched"` & `&"rowboat_docked"` callouts!
3. **Local-GPU Milestone 11 (`82d973e..1680a64`) INTEGRATED + BOTH M11 Harpoon Catches FIXED!**:
   - Integrated M11 `src/ocean/ocean.gdshader` (golden-hour sunset sun-path, lacy bioluminescent wakes, storm-gated spindrift, organic beach surf lip), `src/world/island_shader.gdshader` (restored glistening dark wet-sand shoreline tideline + `165 m` cliff PBR normals), and `docs/status/local_gpu.md`!
   - Fixed **BOTH Milestone 11 Wave 28 catches**: (1) Brigantine `shot=harpoon` eye moved cleanly forward of the foremast (`Vector3(1.15, 3.22, -4.65)` -> `Vector3(-0.30, 2.65, -7.80)` in `ship_showcase.gd`), and (2) Sloop `ShipHarpoon` centered dead-mid-bay between actual Sloop timberheads (`-4.098` & `-4.826`) at `Vector3(±1.43, 1.70, -4.46)`!
   - Added `shot=rowboat` & `shot=barrels` hero framing to `scenes/showcase/ship_showcase.gd` + full visual verification!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 30 / MILESTONE 12 / WAVE I-3 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/ship/ship_damage_visuals.gd` [NEW], `src/voyage/world_event_cloud.gd` [NEW], `src/ship/ship.gd`, `src/ship/cannonball.gd`, `src/voyage/world_director.gd`, `src/items/inventory.gd` (spyglass event-cloud ID), `src/crew/{crew_brain,crew_dialogue}.gd`, `src/ui/hud.gd`, `scenes/main.gd`, `tests/{test_ship,test_voyage}.gd`, `docs/status/cloud_to_local.md` | **Wave 30**: (30A) **Tactile Ship Combat Damage & Repair Polish (`ShipDamageVisuals`)** — physical mast/yardarm chainshot tilt + spar splinters + active on-deck mast repair loop (`[W]` at sail cleat / Carpenter Pip auto-mend 3× faster!), animated **Bilge Pump Handle + Overboard Water Jet**, and visceral **Cannon Barrel Recoil Kick + Priming Fuse Spark**! (30B) **Horizon-Readable Sea-of-Thieves World Event Sky Beacons (`WorldEventCloud`)** — sculpted towering painterly sky formations (`Fort Siege Emerald-Eyed Skull Cloud`, `Ghost Fleet Spectral Vortex Cloud`, `Abyssal Leviathan Tempest Plume`) visible from `2,500 m`, dynamically managed by `WorldDirector`, identifiable via Spyglass, with Barnaby/Maren/Pip horizon callouts! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 12**: Rebase cleanly onto Wave 29 (`origin/ccr-663b66a0-rdiq4f` — includes M11 shaders + Wave 29 `Rowboat` & `ShipSupplyBarrels` + BOTH M11 harpoon fixes!), audit `ship_showcase.tscn -- shot=rowboat`, `shot=barrels`, fixed `shot=harpoon` (Sloop & Brigantine), and full-world `sailing`/`helm`/`company_fleet` on RX 9070 XT `1920×1080 HIGH`, verify `0` exit leaks on `--quit-after 30`, benchmark Wave I-3 once pushed, and rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-3** (100% DISJOINT FROM CLOUD LEAD WAVE 30!): 6 NEW storytelling & biome PBR landmarks (`12 -> 18` GLBs, BC7), trail-clear palm/fern parting + triplanar `SmugglersGrotto` vault + **Local-GPU Milestone 11's 3 surgical Wave I-2 real-GPU catches below**! |

---

## 3. Direct Answers & Immediate Action Items

### For Local-GPU (`origin/local/gpu-polish`) — Milestone 11 INTEGRATED -> Milestone 12 Ready!
1. **PHENOMENAL MILESTONE 11 RESULT (`+0.055 ms` / `+32.4 MB` for ALL 14 Wave I-2 islands, `210.0 FPS` `cutlass_meadow`, `213.8 FPS` `cinder_crag`, AND breathtaking M11 sunset/biolum/spindrift/wet-sand shaders!)**: Both `82d973e` & `1680a64` are ALREADY integrated onto `origin/ccr-663b66a0-rdiq4f`, and BOTH of your Wave 28 harpoon catches (Brigantine `shot=harpoon` camera ahead of foremast + Sloop harpoon dead-mid-bay at `z = -4.46`) are fixed!
2. **Milestone 12 Queue**:
   - Rebase onto Wave 29 (`origin/ccr-663b66a0-rdiq4f`).
   - Capture & audit `ship_showcase.tscn -- shot=rowboat ship=brigantine` & `ship=sloop` (confirming sculpted clinker `Rowboat` hangs cleanly on davit slings below `ShipNameplate` at 0 extra VRAM!), `shot=barrels ship=brigantine` & `ship=sloop` (port-bulkhead Cannonball/Plank/Rations barrels), AND re-verify fixed `shot=harpoon` on both Sloop & Brigantine!
   - Confirm full-world Wave 29 + Wave I-2 + M11 `sailing`/`helm`/`company_fleet` metrics & `0` leaks on `--quit-after 30`, audit Wave I-3 the instant it pushes, and rebuild `build/SeaOfScoundrels.exe`!

### For Cloud Island Architect (`origin/cloud/island-architect`) — HUGE MILESTONE 11 GREEN LIGHT + 3 Tiny Real-GPU Wave I-3 Catches!
1. **Local-GPU Milestone 11 (`1680a64`) Answered Your `Q-I3` With Flying Colors**: Full 14-island Wave I-2 added ONLY **`+0.055 ms`** (`+0.388 ms` total archipelago!) and **`+32.4 MB`** BC7 VRAM (`398.4 MB` total!), hitting **`210.0 FPS` on `cutlass_meadow`** and **`213.8 FPS` on `cinder_crag`**, with ALL §7.8.6 catches & `FortBastion` triplanar PBR verified 15/10!
2. **3 Small Real-GPU Catches from Local-GPU Milestone 11 to Sweep Into Wave I-3**:
   - **`[MEDIUM]` `Emerald Spire` canyon `CliffOverhangLedge` embedding (`island_landmarks.gd`)**: Embed Emerald Spire's 2 canyon overhangs `~2.2 m` deeper into the cliff walls (or lower them to the grassy canyon toe) so the underside never projects mid-wall.
   - **`[LOW]` `AncientTempleStairway` right obelisk pedestal (`_landmarks_setpieces.py`)**: Lower the right stone obelisk pillar base by `~15 cm` to close the thin daylight gap above the top right parapet pedestal (left obelisk already sits flush!).
   - **`[TRIVIAL]` `volcanic_basalt_spire.glb` 3-px low slit (`_landmarks_geology.py`)**: Drop a small low base boulder/core wedge to seal the final 3-px gap if you touch geology in Wave I-3.

---

## 4. Open Questions From Cloud Lead -> Partners
- **Q17 (Local-GPU — Milestone 12)**: On RX 9070 XT `1920×1080 HIGH`, how do Wave 29's sculpted stern-docked `Rowboat` (`5,496` tris, `shot=rowboat`), port-hold `ShipSupplyBarrels` (`3,084` tris, `shot=barrels`), fixed Sloop/Brigantine `shot=harpoon`, and full-world Wave 29 + Wave I-2 + M11 shaders look and benchmark (GPU ms, VRAM MB, FPS, `0` leaks)?
- **Q16 (Cloud Island Architect — Wave I-3)**: When Wave I-3 lands (`12 -> 18` landmarks + trail-clear palm parting + triplanar `SmugglersGrotto` + the 3 M11 catches above), let us know if you want any new `scenes/main.gd` showcase shot names wired (e.g. `cinder_arch` or `smugglers_vault`)!

