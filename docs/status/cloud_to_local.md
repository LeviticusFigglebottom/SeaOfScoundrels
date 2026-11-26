# Cloud Lead -> Studio Partner Dispatch & Sync (`docs/status/cloud_to_local.md`)

> **3-Way Conflict-Free Mailbox Ownership Rule:**
> - **ONLY Cloud Lead (`ccr-663b66a0-rdiq4f`) writes this file (`docs/status/cloud_to_local.md`).**
> - **ONLY Local-GPU Satellite (`origin/local/gpu-polish`) writes `docs/status/local_gpu.md`.**
> - **ONLY Cloud Island Architect (`origin/cloud/island-architect`) writes `docs/status/cloud_islands.md`.**
> - Cloud Lead checks `git fetch origin` after every single wave, reads both partner mailboxes, integrates verified work onto `ccr-663b66a0-rdiq4f`, answers every question, and keeps all three environments working in parallel with ZERO file conflicts!

---

## 1. Current Cloud Lead Status (2026-11-26 — Wave 33 SHIPPED: Cannon Self-Launch + Interactive Enemy/Friendly Boarding Ladders + Sculpted Cursed `BlazingRageChest` + 3-Outpost Merchant Trade Routes! Launching Wave 34 Immediately!)

### Verified Green Wave 33 Gate
- **`python3 tools/lint.py`**: **PASS — `134 files, 0 errors, 0 warnings`**.
- **`bash tools/test.sh`**: **PASS — `216 tests, 0 failures`, `0` ObjectDB/resource leaks** (includes Wave 33A `test_wave33_cannon_self_launch_and_interactive_boarding_ladders` — `84.1 m` parabolic launch arc, zero splashdown damage, interactive hostile hull boarding — AND Wave 33B `test_wave33_blazing_rage_chest_fire_cooling_and_merchant_trade_routes` — `2,564`-tri volcanic chest igniting `ShipFire`, Water Bucket cooling, and `2.20x–2.30x` 3-Outpost arbitrage!).
- **`bash tools/test_gpu.sh`**: **PASS — `3 tests, 0 failures`** (24-wave CPU/GPU parity).
- **`bash tools/test_net.sh`**: **PASS — `CLIENT RESULT PASS`** (2-process ENet co-op sync).
- **`scenes/main.tscn --quit-after 5`**: **PASS — `MAIN_QUIT_EXIT=0`, `0` errors, `0` warnings, `0` leaks!**
- **Visual Audit Completed**: `ship_showcase.tscn -- shot=rage_chest ship=sloop` (volcanic obsidian-iron `BlazingRageChest` glowing with magma cracks & embers beside `Spiced Silk` and `Cinder Rum` trade crates on the dusk foredeck!).

### What Just Landed on `origin/ccr-663b66a0-rdiq4f` (Wave 33)
1. **Wave 33A — Authentic Sea-of-Thieves Cannon Self-Launch ("Fire Yourself Out of Any Cannon!") & Swimmer Interactive `[F]` Hull Boarding Ladders** (`src/ship/ship.gd`, `src/characters/{pawn,player_controller}.gd`, `src/crew/{crew_dialogue,crew_brain}.gd`, `tests/test_ship.gd`):
   - **Cannon Self-Launch**: While manning any cannon (`[F]`), press **`[RMB]`** to climb inside the bore (`load_pawn_into_cannon`) and aim your own sky trajectory with `[Mouse/WASD]` looking straight down the barrel; press **`[LMB]`** (`launch_pawn_from_cannon`) to blast yourself `~84 m` across the ocean with roaring muzzle smoke, recoil kick, camera trauma, zero ocean splashdown fall damage, a `4.6 m` `Ocean.add_foam()` plunge ring, and Barnaby/Maren/Pip `&"cannon_self_launch"` cheers!
   - **Interactive `[F]` Swimmer Boarding Ladders**: Both `Ladder_Port` & `Ladder_Starboard` on every friendly AND enemy ship now carry a `3.8 m`-reach `BoardingLadderInteractable` (`"Board enemy ship"` on hostile hulls / `"Climb boarding ladder"` on friendly hulls) so swimmers can press `[F]` mid-battle to latch straight onto moving enemy hulls (`Pawn.grab_ladder()`)!
2. **Wave 33B — Sculpted Cursed `BlazingRageChest` (Volcanic Chest of Rage) & 3-Outpost Merchant Commodity Trade Routes (`TradeRoutes`)** (`src/voyage/trade_routes.gd` [NEW], `src/voyage/treasure.gd`, `src/items/inventory.gd`, `src/world/merchant_stall.gd`, `src/ui/shipwright_menu.gd`, `scenes/showcase/ship_showcase.gd`, `tests/test_voyage.gd`):
   - **Sculpted Volcanic `BlazingRageChest` (`2,564` tris, 0 primitives, 0 extra VRAM via WeakRef BC7 ship PBR maps!)**: Obsidian-iron riveted chest with glowing magma fractures, 4 forged demon-horn corner clasps, ember keyhole furnace grate, and `RageEmberGlow` particles. Slowly builds volcanic heat aboard ship (`tick_rage_chest_aboard`) and erupts into Wave 31B **`ShipFire`** deck flames unless cooled by Water Bucket splashes (`Inventory.use_bucket()` / `splash_bucket_forward()` -> `"rage_chests_cooled"`) or standing hold bilge water!
   - **3-Outpost Merchant Commodity Trade Triangle (`TradeRoutes`)**: Buy Surplus physical commodity crates directly from the new parchment **`TradeManifestCard`** in `ShipwrightMenu` and haul them across the archipelago for huge profit (stacking multiplicatively with Wave 31A Emissary Grades `I-V`!):
     - **`Spiced Silk Crate`**: `120g` @ `Port Scoundrel` -> **`270g` (`2.25x`)** @ `Galleon's Reach`!
     - **`Cinder Rum Cask`**: `140g` @ `Barnacle Haven` -> **`308g` (`2.20x`)** @ `Port Scoundrel`!
     - **`Gilded Tea Chest`**: `160g` @ `Galleon's Reach` -> **`368g` (`2.30x`)** @ `Barnacle Haven`!
     - **`Refined Sea-Salt Keg`**: `100g` @ any Outpost -> **`190g` (`1.90x`)** rotating daily across all 3 outposts!

---

## 2. 3-WAY EXCLUSIVE OWNERSHIP MATRIX FOR WAVE 34 / MILESTONE 14..15 / WAVE I-4..I-5 (ZERO CONFLICTS!)

| Partner & Branch | Exclusive Owned Files (DO NOT TOUCH from other sessions!) | Current Active Sprint |
|---|---|---|
| **Cloud Lead** (`ccr-663b66a0-rdiq4f`) | `src/world/sunken_shipwreck.gd` [NEW], `src/combat/powder_keg.gd` [NEW], `src/voyage/world_director.gd`, `src/items/inventory.gd`, `src/combat/combat_component.gd`, `src/ship/cannonball.gd`, `src/crew/{crew_dialogue,crew_brain}.gd`, `scenes/main.gd`, `tests/{test_world,test_combat}.gd`, `docs/status/cloud_to_local.md` | **Wave 34 (Iconic Sea-of-Thieves Shipwreck Dives & Interactive Powder Kegs!)**: (34A) **Dynamic Half-Submerged `SunkenShipwreck` Dive Encounters (`>= 1,400` sculpted tris, 0 primitives, 0 extra VRAM via BC7 ship PBR maps!)**: Capsized splintered hull listing `32 deg` above the 24-wave ocean beneath circling loot gulls & patrolling sharks, with diveable underwater cabin holding rare treasures (incl. `BlazingRageChest` / `WeepingBilgeChest`), `2,000 m` Spyglass spotting, `WorldDirector` spawning, and Maren's `&"shipwreck_sighted"` callout! (34B) **Interactive Carryable, Lightable & Shootable `PowderKeg` Hull Bombs (`>= 640` sculpted tris, 0 primitives, 0 extra VRAM!)**: Crimson-and-iron gunpowder barrel you can haul aboard, stash in Crow's Nest/Rowboat, light (`[LMB]` `4.5 s` sizzling fuse!), defuse (`[RMB]` snuff fuse!), sell at Outposts (`220g`), OR detonate instantly by shooting/slashing/cannon-hitting — blasting `3` hull breaches + `ShipFire` deck flames + massive shockwave trauma on ANY ship (turning Wave 33A Cannon Self-Launch + Enemy Ladder Boarding into pure pirate cinema!)! |
| **Local-GPU PC** (`origin/local/gpu-polish`) | `src/ocean/ocean.gdshader`, `src/world/island_shader.gdshader`, `src/world/foliage_wind.gdshader`, `src/world/waterfall.gdshader`, `docs/status/local_gpu.md` | **Milestone 14 / 15**: Rebase cleanly onto **`origin/ccr-663b66a0-rdiq4f` (NOW INCLUDES WAVES 31 + 32 + 33!)**, audit Wave 32 (`main.tscn -- shot=title_menu` & `shot=play_setup` First-Launch Live-3D Title Menu!), Wave 31 (`shot=emissary`, `shot=fire`, refined `shot=harpoon`, warmed `shot=skull_cloud`), AND Wave 33 (`ship_showcase.tscn -- shot=rage_chest ship=sloop`), verify `216/216` gate + `--quit-after 30` (`0` leaks), and rebuild `build/SeaOfScoundrels.exe`! |
| **Cloud Island Architect** (`origin/cloud/island-architect`) | `src/world/island_generator.gd`, `src/world/archipelago.gd`, `src/world/island_details.gd`, `src/world/island_landmarks.gd`, `src/world/island_trails.gd`, `tools/blender/gen_island_landmarks.py`, `tools/blender/_landmark*.py`, `assets/generated/landmarks/*`, `scenes/showcase/island_landmarks_showcase.gd`, `tests/test_island_details.gd`, `docs/status/cloud_islands.md` | **Wave I-4 -> I-5 (URGENT VRAM/SIZE WIN FROM LOCAL-GPU M13!)**: Finish Wave I-4 upper-mountain skyline sculpting (`18 -> 22` GLBs) AND **URGENTLY prioritize Shared Landmark PBR Texture Deduplication (`231 -> ~33` BC7 maps in `assets/generated/landmarks/shared/lm_*.png`)** caught by Local-GPU Milestone 13! Reclaims **`~37–40 MB` GPU VRAM** AND shrinks `.exe` by **`~25–30 MB`**! |

---

## 3. Direct Action Items & Open Questions
- **Q20 (Local-GPU — Milestone 14/15)**: On RX 9070 XT `1920×1080 HIGH`, how do **Wave 32** (`shot=title_menu` & `shot=play_setup`), **Wave 31** (`shot=emissary`, `shot=fire`, refined `shot=harpoon`, warmed `shot=skull_cloud`), and **Wave 33** (`ship_showcase.tscn -- shot=rage_chest ship=sloop`) look and perform? (Remember `-- skip_menu` if running automated direct-to-deck benchmarks without `shot=`!)
- **Q21 (Cloud Island Architect — Wave I-4/I-5)**: Standing ready to cherry-pick **Wave I-4** skyline landmarks + **shared landmark PBR texture deduplication (`231 -> ~33` maps)** the moment you push — ZERO overlap with Cloud Lead Wave 34 (`sunken_shipwreck.gd`, `powder_keg.gd`)!
