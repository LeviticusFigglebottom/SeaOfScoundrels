# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 31 + Local-GPU Milestone 13 INTEGRATED & VERIFIED! Launching Wave 32 Owner Priority: First-Launch Title Menu, Game Modes, Maiden Voyage Tutorial & Pre-Sail Configurator!)

### Verified Green Wave 31 + Milestone 13 Gate
- **`python3 tools/lint.py`**: **PASS — `127 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `208 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes Wave 31A `test_wave31_emissary_grades_stern_flag_payout_multiplier_risk_and_cashout`, Wave 31B `test_wave31_firebomb_ordnance_spreading_ship_fire_bucket_douse_and_crew_firefighting`, and `test_wave31_ship_fire_scorches_pawns_spreads_and_storm_rain_extinguishes`!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (24-wave CPU/GPU parity).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op sync).
- **`scenes/main.tscn --quit-after 5`**: **PASS — `MAIN_QUIT_EXIT=0`, `0` errors, `0` warnings, `0` leaks!**

### What Just Landed on `origin/ccr-663b66a0-rdiq4f`
1. **Wave 31A — Sea-of-Thieves Trading Company Emissary Grades (`I -> V`) & Sculpted Stern `ShipEmissaryFlag`** (`src/voyage/emissary_ledger.gd` [NEW], `src/ship/ship_emissary_flag.gd` [NEW], `src/voyage/voyage_manager.gd`, `src/voyage/world_director.gd`, `src/ui/shipwright_menu.gd`, `src/ui/hud.gd`, `scenes/main.gd`, `tests/test_voyage.gd`):
   - **Host-authoritative `EmissaryLedger`**: Raise an Emissary Flag for `Gilded Compass`, `Sunken Archive`, or `Iron Tide` at any Outpost's **Trading Company Emissary Desk** (`ShipwrightMenu`), earn XP from digging/boarding/selling treasure, defeating enemies, and completing voyage stages, climb **Grades `I -> V`** with escalating **`1.0x -> 1.33x -> 1.67x -> 2.0x -> 2.5x`** gold & renown multipliers, cash out at an Outpost for **`+500g..+5,000g`** & **`+25..+250`** renown, while raising `WorldDirector` hunter risk (`+0.00..+0.55`) and snapping into a floating salvageable **Broken Emissary Flag** if sunk!
   - **Sculpted Starboard-Quarter Stern `ShipEmissaryFlag` (`1,308` tris, 0 primitives, 0 extra VRAM via WeakRef BC7 ship PBR maps!)**: Tapered `2.55 m` oak flagstaff on beveled taffrail socket clamp, turned brass straps & spearhead finial, company swallowtail banner with raised heraldic centerpiece, and **5 stepped gilded brass Grade Pennant Ribbons** billowing dynamically with `Weather.wind_heading`!
   - **Strict-ASCII Gilded Emissary HUD Badge** inside `VoyageWhisper` (`"GILDED COMPASS EMISSARY III (1.67x)"`) + showcase support (`ship_showcase.tscn -- shot=emissary ship=brigantine`).
2. **Wave 31B — Sea-of-Thieves `Firebomb` 4th Cannon Ordnance, Spreading Sculpted `ShipFire` Deck Flames, Water-Bucket Dousing & Crew Fire-Fighting** (`src/combat/ship_fire.gd` [NEW], `src/ship/cannonball.gd`, `src/ship/ship.gd`, `src/items/inventory.gd`, `src/crew/{crew_dialogue,crew_brain}.gd`, `tests/{test_combat,test_ship}.gd`):
   - **Sculpted Amber-Glass `Firebomb` (`704` tris, 0 primitives, 0 extra VRAM)**: `[R]` cycles `Iron -> Chainshot -> Firebomb -> Flare`; direct impacts ignite target decks with ember flare burst!
   - **Sculpted Multi-Tongue Spreading `ShipFire` (`672` tris per flame cluster, 6 deck/hold zones per hull, 0 extra VRAM, single shared flickering unshadowed `OmniLight3D`)**: Spreads organically between adjacent zones, scorches nearby pawns (`3 dmg / 0.5 s`), slowly chars hull planks into real water breaches if unchecked (`18 s`), replicates cleanly over ENet via 6-bit `fire_mask`, and extinguishes naturally in heavy rainstorms (`storm > 0.55`)!
   - **Interactive Dousing & Crew AI**: Full Water Bucket splash (`Inventory.use_bucket()` / `splash_bucket_forward()`) extinguishes flames within `4.5 m`, and AI Crewmates call out `&"fire_aboard"` / `&"fire_doused"` and prioritize `&"douse_fire"` (below critical `>= 0.65` bail survival)! Showcase support (`ship_showcase.tscn -- shot=fire ship=sloop`).
3. **Local-GPU Milestone 13 (`7407b76`, CI GREEN `45854938963`) INTEGRATED + Both M13 Polish Notes Applied!**:
   - **OUTSTANDING M13 NUMBERS (`164.3 FPS` `skull_cloud`, `210.5 FPS` `cinder_arch`, `187.0 FPS` `smugglers_vault`, `147.3 FPS` 600-frame live soak with `0` leaks, `+0.023 ms` GPU for all 6 Wave I-3 landmarks, `240.5 MB` Windows `.exe`)!**
   - Applied BOTH M13 polish notes immediately:
     - `src/voyage/world_event_cloud.gd`: Outer skull/tempest cloud puffs now smoothly warm toward golden-hour dawn/sunset horizon tones (`_golden_hour_factor()`) while preserving blazing emerald/spectral eye glow!
     - `scenes/showcase/ship_showcase.gd`: Brigantine `shot=harpoon` moved cleanly forward of `MAST_FORE_Z = -4.60` to `z = -4.95` with `fov = 78.0` so BOTH Brigantine bow harpoons are 100% unobstructed!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 32 / MILESTONE 14 / WAVE I-4..I-5 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/core/session_config.gd` [NEW], `src/ui/title_menu.gd` [NEW], `src/voyage/tutorial_director.gd` [NEW], `src/voyage/skirmish_director.gd` [NEW], `src/ui/hud.gd`, `src/crew/crew_dialogue.gd`, `scenes/main.gd`, `tests/{test_menus,test_modes}.gd` [NEW], `docs/status/cloud_to_local.md` | **Wave 32 (OWNER TOP PRIORITY — First-Launch Menus, Game Modes, Maiden Voyage Tutorial & Pre-Sail Configurator!)**: (32A) **Live 3D First-Launch Title & Main Menu (`TitleMenu` + `SessionConfig`)** booting directly into an animated camera orbiting Port Scoundrel & your live ship with **4 Game Modes** (`Open-Seas Adventure`, `Maiden Voyage Tutorial`, `High-Seas Naval Skirmish`, `Co-op Crew Host/Join`), full **Pre-Sail Setup** (Ship Class `Sloop/Brigantine` + Custom Ship Name, Spawn Outpost `Port Scoundrel / Barnacle Haven / Galleon's Reach`, Crew Roster `Solo / Duo / Trio / Full Crew`, Time of Day, Sea/Weather Preset, Difficulty, Starting Emissary Flag), Settings access, Captain Profile card, and Pause Menu `"Return to Main Menu"` (100% preserving CLI `-- shot=`, `-- role=`, `--skip-menu`, and headless test defaults!). (32B) **Interactive Guided 8-Stage `TutorialDirector` (Maiden Voyage)** detecting real Sea-of-Thieves actions (Compass -> Map Table Pin -> Capstan Anchor -> Sails & Wind Trim -> Helm -> Cannon -> Rowboat/Landing -> Dig & Sell + `+500g` graduation!) AND **`SkirmishDirector`** escalating naval combat waves (`Drowned Sloop` -> `Twin Sloops` -> `Corsair Brig + Ghost Ship` -> `Abyssal Leviathan`)! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 14**: Rebase cleanly onto **`origin/ccr-663b66a0-rdiq4f` (Wave 31!)**, audit Wave 31 (`ship_showcase.tscn -- shot=emissary ship=brigantine`, `ship_showcase.tscn -- shot=fire ship=sloop`, refined `shot=harpoon ship=brigantine`, golden-hour warmed `main.tscn -- shot=skull_cloud`), benchmark full-world `sailing HIGH` + `storm HIGH` + 600-frame soak (`0` leaks), and rebuild `build/SeaOfScoundrels.exe`! (Then Milestone 15 will audit Wave 32 `shot=title_menu` & `shot=play_setup` + Wave I-4 skyline sculpting!) |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-4 -> I-5 (URGENT VRAM/SIZE WIN FROM LOCAL-GPU M13!)**: Finish Wave I-4 upper-mountain skyline sculpting (`18 -> 22` GLBs) AND **URGENTLY prioritize Shared Landmark PBR Texture Deduplication (`231 -> ~33` BC7 maps in `assets/generated/landmarks/shared/lm_*.png`)** caught by Local-GPU Milestone 13! Reclaims **`~37–40 MB` GPU VRAM** AND shrinks `.exe` by **`~25–30 MB`**! |

---

## 3. Direct Answers & Immediate Action Items

### URGENT FOR CLOUD ISLAND ARCHITECT (`origin/cloud/island-architect`) — HUGE M13 VRAM & `.exe` WIN!
1. **Local-GPU Milestone 13 (`7407b76`) Audited Wave I-3 on Real RX 9070 XT — INCREDIBLE `+0.023 ms` GPU & 12/12 CLEAN VISUALS, PLUS 2 ACTIONABLE ITEMS**:
   - **`[HIGH PRIORITY — HUGE WIN]` Shared Landmark PBR Texture Deduplication (`231 -> ~33` BC7 files)**: Each of the 18 landmark GLBs currently exports its own duplicate copy of `lm_{brass,iron,timber,paint,rope,limestone,limestone_moss,foliage,basalt,skull_stone,temple_stone}_{albedo,normal,rough}.png` (`+44 MB` VRAM across Wave I-2 + I-3, and pushed `SeaOfScoundrels.exe` from `226.1 -> 240.5 MB`). Pointing all landmark materials in `tools/blender/gen_island_landmarks.py` / `island_landmarks.gd` to **one shared `assets/generated/landmarks/shared/lm_*.png` texture set** (matching `assets/generated/ship/`!) will reclaim **`~37–40 MB` GPU VRAM** AND shrink the `.exe` by **`~25–30 MB`** before/as Wave I-4 adds 4 more skyline GLBs! Please tackle this either in Wave I-4 or immediately in Wave I-5!
   - **`[LOW — Dawn Lighting]` `Cutlass Cay` `CliffOverhangLedge_Cove`**: At low dawn sun (`time=6.15`), `cliff_overhang_ledge.glb`'s flat front underside still catches a sliver of direct horizontal light — swapping `Cutlass Cay`'s cove ledge to bottom-heavy `CliffButtressWide` (or tapering its underside skirt into the slope) seals it at all 24 hours.
   - **HUGE +1 from Local-GPU on Wave I-4**: Confirmed on `sovereigns_bastion`, `barnacle_haven`, and `smugglers_cove` that the rounded `25..95 m` rear mountain domes are the ONLY remaining island visual frontier — Wave I-4's crag spires, cliff aqueducts, pirate watchposts & erosion gullies will make every silhouette iconic!
2. **100% Zero-Conflict Fence**: Cloud Lead's **Wave 32** (First-Launch Title Menu, Game Modes, Tutorial, Skirmish) touches ZERO world/island/landmark files (`archipelago.gd` is read-only for us!). Push Wave I-4 whenever ready and Cloud Lead will cherry-pick it immediately!

### FOR LOCAL-GPU (`origin/local/gpu-polish`) — Milestone 13 INTEGRATED -> Milestone 14 Ready (Wave 31!)
1. **PHENOMENAL MILESTONE 13 AUDIT (`164.3 FPS` `skull_cloud`, `210.5 FPS` `cinder_arch`, `187.0 FPS` `smugglers_vault`, `147.3 FPS` 600-frame soak, `0` leaks!)**: Your `7407b76` report is integrated, your urgent landmark texture dedup catch has been escalated directly to Cloud Island Architect above, AND both of your optional polish notes (`WorldEventCloud` golden-hour sunset puff warming + Brigantine `shot=harpoon` `z = -4.95`, `fov = 78.0`) are already live!
2. **Milestone 14 Queue**:
   - Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` (**Wave 31**!).
   - Capture & visually audit:
     - `scenes/showcase/ship_showcase.tscn -- shot=emissary ship=brigantine` (sculpted stern `ShipEmissaryFlag` + 5 gilded Grade V pennants, 0 extra VRAM)
     - `scenes/showcase/ship_showcase.tscn -- shot=fire ship=sloop` (sculpted multi-tongue `ShipFire` deck flames + flickering `OmniLight3D` at dusk, 0 extra VRAM)
     - `scenes/showcase/ship_showcase.tscn -- shot=harpoon ship=brigantine` (confirm M13 foremast occlusion 100% fixed!)
     - `scenes/main.tscn -- shot=skull_cloud` (confirm golden-hour sunset warming on `Fort Skull Cloud` outer puffs!)
   - Run full `208/208` gate + 24-wave GPU parity + `--quit-after 30` zero-leak check + `sailing HIGH` benchmark & rebuild `build/SeaOfScoundrels.exe`!

---

## 4. Open Questions From Cloud Lead -> Partners
- **Q20 (Local-GPU — Milestone 14)**: On RX 9070 XT `1920×1080 HIGH`, how do **Wave 31** (`ShipEmissaryFlag` stern Grade V banner & pennants, `ShipFire` multi-tongue dusk flames + dynamic `OmniLight3D`, refined Brigantine `shot=harpoon`, and sunset-warmed `Fort Skull Cloud`) read visually and perform in GPU ms / VRAM MB?
- **Q21 (Cloud Island Architect — Wave I-4 / I-5)**: Can we fold Local-GPU M13's **shared `assets/generated/landmarks/shared/lm_*.png` deduplication (`231 -> ~33` maps, `-37–40 MB` VRAM / `-25–30 MB` `.exe`)** right into Wave I-4 or immediate Wave I-5? Also let us know which Wave I-4 high-skyline showcase shots you'd like wired in `scenes/main.gd`!
