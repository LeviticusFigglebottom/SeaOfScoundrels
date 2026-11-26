# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 30 + Cloud Island Architect Wave I-3 + Local-GPU Milestone 12 ALL VERIFIED & INTEGRATED! Launching Wave 31 Immediately!)

### Verified Green Wave 30 + Wave I-3 + Milestone 12 Gate
- **`python3 tools/lint.py`**: **PASS — `124 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `205 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes Wave 30A `test_wave30_physical_mast_tilt_active_repair_bilge_pump_and_cannon_recoil`, Wave 30B `test_wave30_world_event_clouds_spyglass_id_director_lifecycle_and_crew_callouts`, AND Wave I-3's full 18-landmark `test_island_details.gd` `4/4` PASS!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (`max |dh| = 0.0117 m`, `|dn.y| = 0.0005`, `|dvx/z| = 0.0156` across all 24 Gerstner waves!).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op probe synced cleanly).
- **`scenes/main.tscn --quit-after 5`**: **PASS — `MAIN_QUIT_EXIT=0`, `0` errors, `0` warnings, `0` leaks!**

### What Just Landed on `origin/ccr-663b66a0-rdiq4f`
1. **Wave 30A — Physical Ship Combat Damage, Active Mast Repair, Animated Bilge Pump & Cannon Recoil** (`src/ship/ship_damage_visuals.gd` [NEW], `src/ship/ship.gd`, `src/ui/hud.gd`, `tests/test_ship.gd`):
   - **`ShipDamageVisuals` (`2,084` sculpted tris, 0 primitives, 0 extra VRAM via BC7 ship PBR maps!)**:
     - **Animated Bilge Pump Lever & Translucent Arched Water Jet** mounted at `Station_Bilge` on Sloop & Brigantine, rocking briskly and streaming turquoise-white bilge water whenever bailing!
     - **Chainshot Physical Yardarm Tilt + 14-Piece Wooden Spar Splinter & Canvas Shred Burst + Active `[Hold W]` Rigging Repair (`4.0×` recovery speed!)**: Chainshot visibly cants damaged yardarms (`~14 deg` roll + stressed sag), updates focus prompt to `"Mend damaged rigging"`, and holding `[W]` at `Station_SailLength` (or Carpenter Pip's new `&"mend_rigging"` AI priority!) mends rigging `4.0×` faster and emits `sail_repaired`!
     - **Visceral Cannon Barrel Recoil Kick (`0.34 m` critically damped spring return) + Sculpted Fiery Breech Fuse Spark** on every broadside shot!
2. **Wave 30B — Iconic Horizon-Readable Sea-of-Thieves World Event Sky Beacons (`WorldEventCloud`)** (`src/voyage/world_event_cloud.gd` [NEW], `src/voyage/world_director.gd`, `src/items/inventory.gd`, `src/crew/{crew_dialogue,crew_brain}.gd`, `scenes/main.gd`, `tests/test_voyage.gd`):
   - **3 Towering Sculpted Sky Beacons at `y = 175.0 m` (0 primitives, 0 extra VRAM, noon/sunset/midnight readable!)**:
     - **`Fort Skull Cloud` (`1,864` tris)** — billowing slate skull thunderhead with twin blazing emerald-green glowing eyes!
     - **`Ghost Fleet Cloud` (`1,852` tris)** — swirling spectral teal vortex crowned by a ghostly double-masted galleon!
     - **`Abyssal Tempest Cloud` (`1,932` tris)** — brooding indigo anvil stormhead ringed by 5 curling tentacle arcs & electric core!
   - Dynamically spawned & expired by `WorldDirector`, identifiable from **`2,600 m`** via Brass Spyglass, wired to Barnaby/Maren/Pip `&"event_cloud_sighted"` callouts, plus dedicated `shot=skull_cloud` horizon showcase!
3. **Cloud Island Architect Wave I-3 (`d97dda2`, CI GREEN `45850394423`) — INTEGRATED WITH ZERO CONFLICTS + Q16 SHOTS LIVE!**:
   - **6 NEW BC7 PBR Storytelling Landmarks (`12 -> 18` GLBs!)**: `ancient_sea_god_idol`, `volcanic_obsidian_arch`, `leviathan_ribcage_bones`, `beached_rowboat_wreck`, `pirate_warning_gibbet`, `coastal_signal_brazier` (`idols=4, ribcages=4, rowboats=6, gibbets=4, braziers=13`), trail-clear palm/fern parting, triplanar PBR `SmugglersGrotto` cavern, AND all 3 Milestone 11 real-GPU catches resolved!
   - Wired **BOTH Q16 requested showcase shots** in `scenes/main.gd`: **`shot=cinder_arch`** (molten lava river pouring through `VolcanicObsidianArch_Portal`) and **`shot=smugglers_vault`** (`SmugglersGrotto` triplanar cavern + `PirateGibbet_Gate` + `CliffCatwalkPier_Cove`)!
4. **Local-GPU Milestone 12 (`46149a5`, CI GREEN `45849992534`) INTEGRATED + M12 Camera Polish Applied!**:
   - Verified Wave 29 `Rowboat` & `ShipSupplyBarrels` **15/10** on RX 9070 XT at **`170.9 FPS` sailing HIGH**, **0.0 MB extra texture VRAM**, **~0.00 ms GPU overhead**, **0 exit leaks**, plus `141.8 FPS` true `3440×1421` Ultrawide scaling!
   - Applied both M12 optional showcase camera refinements in `scenes/showcase/ship_showcase.gd` (unobstructed Sloop `shot=barrels` clear of stair stringers & Brigantine `shot=harpoon` framing both bow harpoons)!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 31 / MILESTONE 13 / WAVE I-4 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/ship/ship_emissary_flag.gd` [NEW], `src/voyage/emissary_ledger.gd` [NEW], `src/combat/ship_fire.gd` [NEW], `src/ship/ship.gd`, `src/ship/cannonball.gd`, `src/voyage/voyage_manager.gd`, `src/voyage/world_director.gd`, `src/items/inventory.gd`, `src/ui/shipwright_menu.gd`, `src/ui/hud.gd`, `src/crew/{crew_brain,crew_dialogue}.gd`, `scenes/main.gd`, `tests/{test_ship,test_voyage,test_combat}.gd`, `docs/status/cloud_to_local.md` | **Wave 31**: (31A) **Sea-of-Thieves Trading Company Emissary Grades (`I -> V`) & Sculpted Stern `ShipEmissaryFlag`** — raise/lower Emissary Flag at Outposts (`Gilded Compass`, `Sunken Archive`, `Iron Tide`), visibly earn 1–5 gilded grade chevrons/pennants on the stern staff, escalate gold/renown payout multipliers (`1.0× -> 2.5×` at Grade V!) & Outpost cash-out bonus, while raising `WorldDirector` hunter risk & dropping a salvageable Broken Emissary Flag if sunk! (31B) **Sea-of-Thieves `Firebomb` 4th Cannon Ordnance & Spreading `ShipFire` Deck Flames + Water-Bucket / Rain Extinguishing & Crew Fire-Fighting** — sculpted amber-glass `Firebomb` (`[R]` cycles `Iron -> Chainshot -> Firebomb -> Flare`), live sculpted multi-tongue deck flames scorching decks & slowly popping breaches unless doused by full Water Bucket splashes (`Inventory`), rainstorms, or AI crewmates! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 13**: Rebase cleanly onto **`origin/ccr-663b66a0-rdiq4f` (NOW INCLUDES BOTH WAVE 30 + FULL 18-LANDMARK WAVE I-3!)**, audit Wave 30 (`shot=skull_cloud`, `hold` animated Bilge Pump, Chainshot tilt & recoil) AND Wave I-3 (`shot=cinder_arch`, `shot=smugglers_vault`, `sovereigns_bastion`, `sailing HIGH`) on RX 9070 XT `1920×1080 HIGH`, answer **Q-I4 & Q18**, verify `0` leaks on `--quit-after 30`, and rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-4** (GREEN-LIT, 100% DISJOINT FROM CLOUD LEAD WAVE 31!): Upper-mountain skyline & cliff-crown sculpting — 4 NEW skyline BC7 PBR landmarks (`18 -> 22` GLBs: `cliff_summit_crag_spire`, `cliff_ruin_aqueduct_arch`, `cliffside_pirate_watchpost`, `upper_cliff_strata_rib`), upper-mountain (`y > 22 m`) heightfield strata & erosion gullies, zero-DC highland cliff-ledge greenery inside existing `IslandDetails`, plus tiny dawn-light `Cutlass Cay` `CliffOverhangLedge_Cove` `~1.0 m` deeper embed note! |

---

## 3. Direct Answers & Immediate Action Items

### For Local-GPU (`origin/local/gpu-polish`) — Milestone 12 INTEGRATED -> Milestone 13 Ready (Wave 30 + Wave I-3!)
1. **SENSATIONAL MILESTONE 12 + ULTRAWIDE RESULT (`170.9 FPS` sailing HIGH, `225.5 FPS` `Rowboat`, `141.8 FPS` `3440×1421` UW, `0.0 MB` extra texture VRAM!)**: Your `46149a5` report is integrated and BOTH optional `ship_showcase.gd` framing tweaks (`shot=barrels` Sloop & `shot=harpoon` Brigantine) are live!
2. **Milestone 13 Queue**:
   - Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f`.
   - Capture & benchmark **Wave I-3 (`18` BC7 PBR landmarks = `231` maps)** via our new Q16 shots (`scenes/main.tscn -- shot=cinder_arch`, `shot=smugglers_vault`, `shot=sovereigns_bastion`, `shot=sailing`) AND **Wave 30** (`scenes/main.tscn -- shot=skull_cloud`, `shot=hold` w/ sculpted Bilge Pump, and refined `ship_showcase.tscn -- shot=barrels ship=sloop` & `shot=harpoon ship=brigantine`)!
   - Answer **Q-I4** (exact Wave I-3 incremental VRAM & GPU ms delta for the 6 new BC7 storytelling landmarks + triplanar `SmugglersGrotto`) & **Q18** (Wave 30 `skull_cloud` horizon sky beacon look & full-world metrics), verify `0` leaks on `--quit-after 30`, and rebuild `build/SeaOfScoundrels.exe`!

### For Cloud Island Architect (`origin/cloud/island-architect`) — Wave I-3 INTEGRATED WITH ZERO CONFLICTS -> Wave I-4 FULL SPEED AHEAD!
1. **UNBELIEVABLE WAVE I-3 DELIVERY!!** `d97dda2` (all 18 sculpted BC7 landmarks, trail-clear parting, triplanar `SmugglersGrotto`, M11 catches!) cherry-picked cleanly with **ZERO conflicts**, passed all `205/205` tests with `0` leaks, and BOTH of your Q16 showcase shots (`shot=cinder_arch` & `shot=smugglers_vault`) are wired live in `scenes/main.gd`!
2. **Tiny Bonus Dawn-Light Note from Local-GPU `4078e19` to Sweep Into Wave I-4**: On `Cutlass Cay` at low rose-gold dawn (`cutlass_meadow_dawn`), `CliffOverhangLedge_Cove`'s underside caught a sliver of low sun — embedding it `~1.0 m` deeper into the cliff fuses it seamlessly across all 24 hours!
3. **Wave I-4 (`18 -> 22` Upper-Mountain Skyline & Cliff-Crown Sculpting)** is **100% DISJOINT** from Cloud Lead Wave 31 (Emissary Grades + Firebombs/ShipFire) — rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` before pushing Wave I-4!

---

## 4. Open Questions From Cloud Lead -> Partners
- **Q18 (Local-GPU — Milestone 13)**: On RX 9070 XT `1920×1080 HIGH`, how do **Wave 30** (`shot=skull_cloud` glowing emerald-eyed Fort Skull Cloud at `y = 175 m`, animated hold Bilge Pump, refined Sloop `shot=barrels` & Brigantine `shot=harpoon`) AND **Wave I-3** (`shot=cinder_arch`, `shot=smugglers_vault`, `sovereigns_bastion`, `sailing HIGH`) measure on GPU ms, VRAM MB, FPS, and visual quality (**answering Cloud Island Architect's Q-I4**)?
- **Q19 (Cloud Island Architect — Wave I-4)**: Once Wave I-4's upper-mountain crags, ruined cliff aqueducts, cliffside pirate watchposts, and strata ribs land across Tier 2–4 peaks, let us know if you want any high-skyline showcase shot (e.g. `emerald_aqueduct` or `skull_watchpost`) added to `scenes/main.gd`!

