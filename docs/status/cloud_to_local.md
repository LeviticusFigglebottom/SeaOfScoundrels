# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 32 OWNER PRIORITY SHIPPED: First-Launch Live-3D Title Menu, 4 Game Modes, Guided 8-Stage Maiden Voyage Tutorial, High-Seas Naval Skirmish & Pre-Sail Configurator! Launching Wave 33 Immediately!)

### Verified Green Wave 32 Gate
- **`python3 tools/lint.py`**: **PASS — `133 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `214 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes new `tests/test_menus.gd` `4/4` PASS — incl. end-to-end `scenes/main.tscn` TitleMenu -> live 3D Brigantine/Barnacle Haven/Duo/Sunset/Emissary preview -> Maiden Voyage launch -> Return-to-Title -> Naval Skirmish launch — and `tests/test_modes.gd` `2/2` PASS!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (24-wave CPU/GPU parity).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op sync).
- **`scenes/main.tscn --quit-after 5`**: **PASS — `MAIN_QUIT_EXIT=0`, `0` errors, `0` warnings, `0` leaks!**
- **Visual Audits Completed**: `shot=title_menu` (Landing Title Screen over live Port Scoundrel harbour + Brigantine) and `shot=play_setup` (Sunset Pre-Sail Configurator with live Brigantine & raised Emissary Flag).

### What Just Landed on `origin/ccr-663b66a0-rdiq4f` (Wave 32 — Owner Top Priority!)
1. **Wave 32A — Live-3D First-Launch Title Menu, `SessionConfig`, Pre-Sail Configurator, Co-op Lobby & Pause Return-to-Title** (`src/core/session_config.gd` [NEW], `src/ui/title_menu.gd` [NEW], `src/ui/hud.gd`, `scenes/main.gd`, `tests/test_menus.gd` [NEW]):
   - **First-Launch Live-3D Harbour Menu**: Interactive desktop builds (`SeaOfScoundrels.exe`, Godot desktop) now boot directly into a sleek left-anchored parchment-and-brass **Title Menu** floating beside a gentle orbital 3D camera framing your live moored ship on the right 55% of the screen (zero black loading screen; instant drop onto deck on **"SET SAIL!"** — while 100% preserving CLI `shot=`, `host`/`join=`, `skip_menu`, and headless test defaults!).
   - **4 Playable Game Modes**:
     1. **Open-Seas Adventure**: Full 14-island archipelago, Trading Company voyages, *Salt-King's Ledger* story campaign, world events & Emissary Grades.
     2. **Maiden Voyage (Guided Tutorial)**: Hands-on 8-step interactive pirate tutorial from Port Scoundrel to Cutlass Cay.
     3. **High-Seas Naval Skirmish**: Instant open-sea naval combat arena facing 4 escalating enemy armadas up to the Abyssal Leviathan!
     4. **Co-op Crew (Host / Join)**: Dedicated Host LAN/Direct-IP server (`Net.DEFAULT_PORT = 24642`) or Join Friend's Crew lobby with live status/error feedback!
   - **Live 3D Pre-Sail Configurator** (every toggle updates the real 3D world live behind the menu!):
     - **Ship Class & Name**: `Sloop` (`1-2` crew, +30% headwind king) vs `Brigantine` (`2-4` crew, 4 cannons, fastest downwind) + custom Ship Name input & randomizer!
     - **Spawn Outpost**: `Port Scoundrel` (Central Harbour), `Barnacle Haven` (Eastern Shoals), or `Galleon's Reach` (Northern Fjord Capital)!
     - **Crew Roster**: `Solo (0)`, `Duo (Barnaby)`, `Trio (Barnaby & Maren)`, or `Full Crew (All 3)` — live on deck!
     - **Seas & Emissary**: Time of Day (`Dawn / Morning / Sunset / Night`), Weather (`Fair / Choppy / Squall`), Difficulty (`Relaxed / Standard / Cursed`), and Starting Emissary Flag (`None / Compass / Archive / Iron Tide`)!
   - **Full Menu Navigation**: Live Settings & Controls page wired directly to `UserSettings`, Captain Profile summary badge (Gold, Voyages, Chests, Vessel), Pause Menu **"Main Menu"** (`return_to_title_requested`) clean round-trip, compact top-left `ModeObjectiveCard` on `GameHUD`, plus `shot=title_menu` & `shot=play_setup` showcase captures!
2. **Wave 32B — Guided 8-Stage `TutorialDirector` (Maiden Voyage) & Escalating 4-Wave `SkirmishDirector`** (`src/voyage/tutorial_director.gd` [NEW], `src/voyage/skirmish_director.gd` [NEW], `src/crew/crew_dialogue.gd`, `tests/test_modes.gd` [NEW]):
   - **Maiden Voyage (`TutorialDirector`)**: Detects 8 real Sea-of-Thieves actions (`1. Equip Brass Compass` -> `2. Check Below-Deck Map Table` -> `3. Heave Anchor Capstan` -> `4. Drop & Trim Sails` -> `5. Take Helm & Sail 45 m` -> `6. Fire Broadside Cannon/Harpoon` -> `7. Approach Cutlass Cay or Launch Rowboat` -> `8. Dig & Sell First Chest`), awards `+500g` + `+100` Renown graduation bonus with celebratory `VictoryFlare`, supports `"Skip Step"` / skip-all, and seamlessly continues into Open-Seas Adventure!
   - **Naval Skirmish (`SkirmishDirector`)**: 4 escalating open-sea combat waves (`Drowned Vanguard` -> `Corsair Pincer` -> `Spectral Armada` -> `Wrath of the Abyss` Leviathan + escort) with 6 s between-wave auto-restock (`+20` cannonballs, `+12` planks, bilge relief), difficulty/payout scaling, live Wave/Score HUD objective card, and crew battle-cry callouts (`&"tutorial_step"`, `&"skirmish_wave"`, `&"skirmish_victory"`)!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 33 / MILESTONE 14..15 / WAVE I-4..I-5 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/ship/ship.gd`, `src/characters/pawn.gd`, `src/characters/player_controller.gd`, `src/voyage/trade_routes.gd` [NEW], `src/voyage/treasure.gd`, `src/world/merchant_stall.gd`, `src/ui/shipwright_menu.gd`, `src/ui/hud.gd`, `src/crew/{crew_brain,crew_dialogue}.gd`, `scenes/main.gd`, `tests/{test_ship,test_voyage}.gd`, `docs/status/cloud_to_local.md` | **Wave 33 (Peak Sea-of-Thieves Emergent Sandbox Magic!)**: (33A) **Cannon Self-Launch ("Fire Yourself Out of Any Cannon!") & Enemy Ship Boarding Ladders** — press `[RMB]` at any cannon to climb inside the bore & aim your own sky arc, `[LMB]` blasts you out with roaring muzzle smoke, zero ocean splashdown damage, huge `Ocean.add_foam()` plunge ring, crew `&"cannon_self_launch"` cheers, plus swimmers able to climb side rope ladders onto enemy hulls! (33B) **Cursed Sculpted `BlazingRageChest` (Volcanic Chest of Rage) & 3-Outpost Merchant Commodity Trade Routes (`TradeRoutes`)** — glowing magma-veined Chest of Rage heats up aboard ship and erupts into Wave 31 `ShipFire` deck flames unless cooled by Water Bucket splashes, PLUS buy/sell Merchant Commodity Crates (`Spiced Silk`, `Cinder Rum`, `Gilded Tea`, `Smuggler's Salt`) across Port Scoundrel, Barnacle Haven & Galleon's Reach at live `1.8x–2.4x` arbitrage profit! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 14 / 15**: Rebase cleanly onto **`origin/ccr-663b66a0-rdiq4f` (NOW INCLUDES BOTH WAVE 31 + WAVE 32!)**, audit Wave 31 (`ship_showcase.tscn -- shot=emissary ship=brigantine`, `shot=fire ship=sloop`, refined `shot=harpoon ship=brigantine`, warmed `main.tscn -- shot=skull_cloud`) AND Wave 32 (`main.tscn -- shot=title_menu` & `shot=play_setup` First-Launch Live-3D Title Menu & Pre-Sail Configurator!), verify `214/214` gate + `--quit-after 30` (`0` leaks), and rebuild `build/SeaOfScoundrels.exe` (which now launches straight into the live-3D Title Menu for the Owner!!)! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-4 -> I-5 (URGENT VRAM/SIZE WIN FROM LOCAL-GPU M13!)**: Finish Wave I-4 upper-mountain skyline sculpting (`18 -> 22` GLBs) AND **URGENTLY prioritize Shared Landmark PBR Texture Deduplication (`231 -> ~33` BC7 maps in `assets/generated/landmarks/shared/lm_*.png`)** caught by Local-GPU Milestone 13! Reclaims **`~37–40 MB` GPU VRAM** AND shrinks `.exe` by **`~25–30 MB`**! |

---

## 3. Direct Action Items & Open Questions

### For Local-GPU (`origin/local/gpu-polish`) — Milestone 14/15 Combined Wave 31 + Wave 32 Audit!
1. Rebase cleanly onto `origin/ccr-663b66a0-rdiq4f` — includes BOTH **Wave 31** (Emissary Grades `I-V` + handrail-mounted `ShipEmissaryFlag` + `Firebomb`/`ShipFire` + M13 harpoon & sunset-cloud polish) AND **Wave 32** (First-Launch Live-3D `TitleMenu`, 4 Game Modes, 8-Stage `TutorialDirector`, 4-Wave `SkirmishDirector`, Pre-Sail Configurator)!
2. **Capture & Visually Audit at `1920×1080 HIGH`**:
   - Wave 32: `scenes/main.tscn -- shot=title_menu` and `scenes/main.tscn -- shot=play_setup` (confirm crisp strict-ASCII parchment UI layout, zero overlap/clipping, live 3D Brigantine gleaming cleanly on the right 55%!).
   - Wave 31: `ship_showcase.tscn -- shot=emissary ship=brigantine`, `ship_showcase.tscn -- shot=fire ship=sloop`, refined `shot=harpoon ship=brigantine`, and sunset-warmed `main.tscn -- shot=skull_cloud`.
3. **Important CLI Note for Benchmark Automation**: When running automated `scenes/main.tscn` runs without `shot=`, pass `-- skip_menu` if you want direct-to-deck spawn (headless & `shot=` bypass the title menu automatically, while interactive desktop launch opens the live-3D Title Menu!).
4. Rebuild `build/SeaOfScoundrels.exe` so the Owner can immediately experience the new First-Launch Live-3D Title Menu, Maiden Voyage Tutorial, Naval Skirmish, and Pre-Sail Configurator!

### For Cloud Island Architect (`origin/cloud/island-architect`) — Wave I-4 & Urgent Shared Landmark Texture Dedup!
1. **ZERO-CONFLICT GUARANTEE**: Cloud Lead Wave 32 & Wave 33 touch ZERO island-architect files (`archipelago.gd` is read-only for us!). Push Wave I-4 whenever ready and Cloud Lead will cherry-pick it immediately!
2. **URGENT M13 VRAM/SIZE WIN (`Q21`)**: Please fold Local-GPU Milestone 13's **Shared Landmark PBR Texture Deduplication (`231 -> ~33` BC7 files in `assets/generated/landmarks/shared/lm_*.png`)** into Wave I-4 or immediate Wave I-5 (`~37–40 MB` VRAM reclaimed + `~25–30 MB` smaller `.exe`!).

### Open Questions
- **Q20 (Local-GPU — Milestone 14/15)**: On RX 9070 XT `1920×1080 HIGH` (and `1440p`/Ultrawide if sampled), how do **Wave 32** (`shot=title_menu` & `shot=play_setup`) AND **Wave 31** (`shot=emissary`, `shot=fire`, refined `shot=harpoon`, warmed `shot=skull_cloud`) look and perform?
- **Q21 (Cloud Island Architect — Wave I-4/I-5)**: ETA on Wave I-4 skyline sculpting + shared `assets/generated/landmarks/shared/lm_*.png` deduplication, and which Wave I-4 skyline showcase shots would you like wired in `scenes/main.gd`?
