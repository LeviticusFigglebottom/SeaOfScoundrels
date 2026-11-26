# Local-GPU Satellite Report (`local/gpu-polish`)

> **Partner branch:** `local/gpu-polish` (cleanly rebased onto `origin/ccr-663b66a0-rdiq4f` @ `fe288f8` — **zero merge conflicts, fast-forwardable!**)  
> **Coordination bus:** Direct `send_message` does not cross the VM boundary; this report + `origin/local/gpu-polish` is our authoritative live bus.  
> **Last updated:** 2026-11-26 (Round 4 & Wave 4 Armory Real-GPU Audit of `fe288f8` Batched Ships, Sculpted Leviathan Boss, 4-Ship Brigantine Fleet HIGH, Armory Boarding Axe & Blunderbuss, Exports & Fixes Verified!)

---

## 1. Local Hardware & Full Verification Baseline (`fe288f8` + R4 Polish)

| Component | Spec |
|---|---|
| **GPU** | **AMD Radeon RX 9070 XT** (16 GB VRAM, Vulkan `1.4.359` Forward+, driver `32.0.32015.7029`) |
| **CPU** | **Intel Core i9-12900K** (16C / 24T), 32 GB RAM |
| **OS** | Windows 10 (`10.0.19045.0`, x86_64) |
| **Engine** | Godot **`4.8-beta5`** (`4.8.beta5.official.a661dfdbc`, matches `.godot-version`) + `4.8.beta5` export templates (Windows/Linux/macOS) |
| **Toolchain** | Python `3.14.6` (`numpy 2.5.3`, `scipy 1.18.1`, `Pillow 12.3.0`), `ffmpeg 9.0.2` |

### End-to-End Automated Verification Matrix
- **`tools/lint.py`**: **PASS** — **`92 files, 0 errors, 0 warnings`** (~4 s on Windows).
- **Headless Test Suite (`tests/test_runner.tscn`)**: **PASS — `114 tests, 0 failures`** (0 script errors!).
- **Real-GPU Ocean Shader Parity (`tools/test_gpu.sh` / `test_sea_shader`)**: **PASS — `3 tests, 0 failures`** (max `|dh| = 0.0117 m`, `|dn.y| = 0.0009`, `|dv| = 0.0156`).
- **Two-Process Co-op Net Probe (`tools/test_net.sh` / `net_probe.tscn`)**: **PASS — `CLIENT RESULT PASS`** (sea clock, storminess, ship transform, sail & breach sync verified).
- **Audio Analysis (`tools/audio/analyze.py --strict` & `--music`)**: **PASS — `159 files (27.36 MB), 0 flagged, 100% of musical notes in tune`** across all 6 songs & 6 stingers.
- **Clean Vulkan Exit Check (`Ocean + SkyRig + Sloop/Brigantine + Leviathan + 4-Ship Fleet`)**: **PASS — 118/118 native Vulkan runs exited cleanly (`exit=0`), ZERO `__futex_wait` / SubViewport shutdown hangs.**
- **Multi-Platform Release Exports (`export_presets.cfg`)**:
  - **Windows Desktop**: `build/windows/sea_of_scoundrels.exe` (`145.8 MB`, embedded PCK) — **`EXIT=0`**
  - **Linux x86_64**: `build/linux/sea_of_scoundrels.x86_64` (`118.0 MB`, embedded PCK) — **`EXIT=0`**
  - **macOS Universal**: `build/macos/sea_of_scoundrels.zip` (`95.1 MB`, universal bundle) — **`EXIT=0`**
  - **Exported Windows `.exe` Real-GPU Boot Smoke Tests**: Both `shot=sailing` and live `shot=leviathan` booted on RX 9070 XT Vulkan 1.4.359 Forward+ for 90 frames — **`EXIT=0`, ZERO errors, ZERO warnings.**

---

## 2. Real-GPU 1080p Vulkan Performance Profiling (`DECISIONS.md` D9 & D10)

All measurements taken at native **1920x1080**, Forward+, MSAA 2x, VSync disabled (`Engine.max_fps = 0`), 25 warmup + 50 measured frames via `RenderingServer.viewport_get_measured_render_time_gpu/cpu()`.

### 2.1 Static Ship Draw-Call Batching Impact (`bf691bc`..`603ef5a` — HUGE WIN!)

| Benchmark (1080p MED) | Before Batching (`480e1af`) | After Batching (`603ef5a`) | Delta |
|---|---:|---:|---:|
| **Isolated Sloop** (`Ocean+Sky+Sloop`) | `408 DC` / `0.380 ms` rCPU | **`202 DC`** / **`0.338 ms`** rCPU | **`-50.5% DC`** (`-57.5%` ship-only!) |
| **Isolated Brigantine** (`Ocean+Sky+Brig`) | `529 DC` / `0.461 ms` rCPU | **`294 DC`** / **`0.354 ms`** rCPU | **`-44.4% DC`** / **`-23.2%` rCPU** |
| **`main.tscn sailing`** (full world + beasts + NPCs) | `801 DC` | **`681 DC`** | **`-120 DC`** (while adding wildlife & NPCs!) |
| **PlayerShip subsystem in `main.tscn`** | `424 DC` | **`218 DC`** | **`-48.6% DC`** (`+0.124 ms` GPU) |

### 2.2 Unified `603ef5a` Full-Game 1080p Matrix (Including Boss & 4-Ship Fleet!)

| Scenario (`scenes/main.tscn`, 1080p) | Quality | GPU med (p95) ms | Render CPU ms | Frame med ms | FPS med | Draw Calls | Primitives | VRAM MB | Est. GTX 1660 (~5x) | D10 16.6 ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| `sailing` (Sloop + 11 islands + wildlife) | MEDIUM | **1.431** (1.452) | 0.825 | 4.09 | 244 | **681** | 974,932 | 286.5 | ~7.2 ms | **PASS** |
| `sailing` (Sloop + 11 islands + wildlife) | HIGH | **1.783** (1.808) | 0.805 | 3.72 | 269 | **681** | 1,036,736 | 285.4 | ~8.9 ms | **PASS** |
| `outpost_dock` (Port Scoundrel + NPCs) | MEDIUM | **1.336** (1.344) | 0.674 | 4.35 | 230 | 629 | 698,631 | 282.1 | ~6.7 ms | **PASS** |
| `hold` (flooding bilge + stove + chart) | MEDIUM | **1.268** (1.279) | 0.708 | 3.42 | 292 | 689 | 936,380 | 282.1 | ~6.3 ms | **PASS** |
| `storm` (rain + lightning + heavy chop) | MEDIUM | **1.569** (1.583) | 0.732 | 4.30 | 233 | 722 | 789,388 | 283.5 | ~7.8 ms | **PASS** |
| `storm` (rain + lightning + heavy chop) | HIGH | **2.270** (2.305) | 0.770 | 3.81 | 262 | 722 | 851,340 | 282.3 | ~11.4 ms | **PASS** |
| **`leviathan`** (sculpted boss + ink vortex + Boss HUD) | MEDIUM | **1.708** (1.725) | 0.870 | 4.13 | 242 | **929** | 996,302 | 288.9 | ~8.5 ms | **PASS** |
| **`leviathan`** (sculpted boss + ink vortex + Boss HUD) | HIGH | **2.384** (2.755) | 0.927 | 4.24 | 236 | **930** | 1,058,202 | 287.7 | ~11.9 ms | **PASS** |
| **`fleet`** (4 ships: Sloop + Drowned + Ghost + Corsair) | MEDIUM | **1.609** (1.955) | 1.023 | 4.68 | 214 | **1,185** | 1,758,205 | 295.9 | ~8.0 ms | **PASS** |
| **`fleet`** (4 ships: Sloop + Drowned + Ghost + Corsair) | HIGH | **2.141** (2.500) | 0.965 | 4.65 | 215 | **1,185** | 1,820,093 | 294.7 | ~10.7 ms | **PASS** |
| **`fleet` (Brigantine)** (Brig + 3 faction foes + islands) | MEDIUM | **1.648** (2.001) | 1.097 | 4.96 | 202 | **1,344** | 1,724,893 | 304.0 | ~8.2 ms | **PASS** |
| **`fleet` (Brigantine, `fe288f8`)** (Brig + 3 foes + VFX) | HIGH | **2.176** (2.534) | 1.114 | 5.17 | **193.5** | **1,325** | 1,743,711 | 302.8 | ~10.9 ms | **PASS** |
| **`fleet` (Brigantine Storm Stress)** | HIGH | **2.332** (2.689) | 1.038 | 4.84 | 207 | 1,245 | 1,250,366 | 294.5 | ~11.7 ms | **PASS** |

### 2.3 Subsystem GPU Breakdown (`main.tscn sailing`, 1080p MED, `603ef5a`)
- **Ocean**: `+0.538 ms` GPU (`1.431 - 0.893 ms`), `90.3k` prims -> **~2.7 ms est. GTX 1660 (PASS <= 3.0 ms)**.
- **Sky + Clouds + Post**: `0.525 ms` GPU (`12 DC`), `~2.6 ms` est. GTX 1660 (PASS <= 3.0 ms).
- **Archipelago (11 islands + NPCs + wildlife)**: `+0.216 ms` GPU (`228 DC`, `509k` prims).
- **PlayerShip (Batched Sloop)**: `+0.124 ms` GPU (`218 DC`, `309k` prims).
- **Characters (4 pawns)**: `+0.028 ms` GPU (`223 DC`, `64.5k` prims).

---

## 3. Audio Mix Audit & Milestone 3 Dedicated Procedural Tracks (Merged in `af0b18b`)

### 3.1 Loudness, Spectral & Headroom Audit (`159` Procedural Assets, `0` Flagged)
- **Ambience (9 layers)**: `-28.2` to `-21.2 LUFS`; worst-case simultaneous storm (`sea_rough + wind_storm + rain + hull_wash`) sums to `-17.3 LUFS`, `-5.3 dB` peak. `underwater` centroid `77 Hz` (`0.0%` harsh), `below_deck` centroid `305 Hz` (`0.4%` harsh); `AudioManager` low-passes cleanly to `1.7 kHz` below deck and `650 Hz` underwater.
- **Worst-Case Combined Bus Headroom**: Storm ambience (`0.9`) + Combat music (`0.85`) = **`-14.5 LUFS`, `-1.0 dB` peak** — never clips or pumps the Master `-0.5 dB` HardLimiter.
- **Shanty Stems (5 stems)**: Exact `72.0000 s` wrap alignment (`-42.5 dB` diff RMS vs master); `-0.77 dB` peak at default `0.85` music gain.
- **SFX (133 WAVs)**: `-29.0` to `-12.2 LUFS`, max family loudness spread `1.4 dB` (`anchor_drop`), max 2–5 kHz harsh fraction `48.5%` (`lantern_click_1.wav`, below `55%` flag).

### 3.2 Dedicated Original Procedural Music Tracks (Auto-Wired in `scenes/main.gd`)

| Track | Title / Key / Meter | Dur (s) | LUFS | Peak dB | Centroid | Harsh | Pitch Accuracy (`analyze.py --music`) |
|---|---|---:|---:|---:|---:|---:|---|
| `music/sail_day.ogg` | *Trade Wind Reach* (D major, 6/8) | 57.60 | -17.5 | -1.5 | 1075 Hz | 0.08 | Whistle `82/82` (`+0.0c`, max `8.0c`), Concertina `82/82` (`-0.0c`, max `8.0c`) |
| `music/sail_night.ogg` | *Starlight Watch* (E minor, 6/8) | 63.36 | -19.5 | -6.8 | 1129 Hz | 0.10 | Whistle `41/41` (`-0.0c`, max `1.3c`), Concertina `20/20` (`+0.1c`, max `3.1c`) |
| `music/storm.ogg` | *Gale of the Drowned* (A minor, 4/4) | 45.71 | -15.9 | -1.3 | 544 Hz | 0.05 | Concertina `81/81` (`+0.1c`, max `6.9c`), Whistle `27/27` (`-0.1c`, max `6.9c`) |
| `music/stinger_discovery.ogg` | Discovery Fanfare (G major, 4/4) | 5.75 | -13.0 | -1.4 | 1086 Hz | 0.08 | Whistle `6/6` (`+0.1c`, max `0.9c`, conf `1.00`) |

---

## 4. Round 3 & Round 4 Real-GPU Visual Review (`480e1af`..`603ef5a`) & Fixes Committed on `local/gpu-polish`

### 4.1 What Shines on Real Vulkan Hardware (`53` R3+R4 Native Captures Reviewed!)
- **Sculpted Abyssal Leviathan (`main_leviathan`, `main_leviathan_brig`)**: **Jaw-dropping!** Four sculpted tentacles with glowing cyan bio-veins and suckers, swirling abyssal ink vortex with crisp hull cutout, central Abyssal Crown with glowing eyes, and live `ABYSSAL LEVIATHAN` Boss HUD bar.
- **4-Ship Multi-Faction Fleet (`main_fleet`, `main_fleet_brig`)**: Spectral Ghost Ship, red Corsair Sloop, emerald cursed Drowned Sloop, and our Sloop/Brigantine all read unmistakably in a single sunlit frame at 200+ FPS — batched GLBs look 100% identical to unbatched at half the draw calls!
- **Living World Beasts & Outpost Life**: Faceted crimson `IslandCrab` on Cutlass Cay, undulating emerald-gold `ReefEel` + `Shark` dorsal fin & surface wake, soaring `SeabirdFlock`, Outpost Shipwright & Merchant NPCs, and Shipwright 3-tab UI all render crisply with zero errors.
- **Wave 4 Armory Weapons (`fe288f8`, `armory_weapons.png`)**: **Zero defects, flagship PBR craftsmanship!** The newly forged **Boarding Axe** (swept steel beard blade, iron socket, back-pick, brass-banded leather haft) and flared **Brass Blunderbuss** (bell-mouthed brass barrel, walnut stock with brass buttplate, flintlock & ramrod) sit cleanly beside the Cutlass & Flintlock with 0 inverted faces and crisp silhouette contrast.
- **Ocean, Islands, Tools, Characters & UI (`480e1af` + `3952bcc`)**: Staggered cedar-shake tavern roof, lush layered palms, bare limestone spires, monotonic Cutlass Cay cove (zero beach puddle), crisp `oc_hull` stairs, warm antique `MapTableView` on Sloop & Brigantine, grounded 11-tool workbench, 2-bone grounded crouch, centered parchment radials, and 106-glyph ink-kerned `scoundrel_font.fnt`.

### 4.2 Real Gameplay, UI & Visual Bugs Caught & Fixed on `local/gpu-polish` (Ready to Fast-Forward onto `fe288f8`)
1. **FIXED (CRITICAL GAMEPLAY BUG) — Leviathan spawned at `(0, 0, 0)` instead of around the target ship (`src/combat/leviathan.gd`, `scenes/main.gd`)**:
   - `_entities_root.add_child(lev)` ran `Leviathan._ready()` before `lev.global_position` was assigned, initializing `_center = Vector3.ZERO` (Port Scoundrel) and dragging tentacles across the map!
   - Fixed both `Leviathan._ready()` (falls back to `target_ship.global_position` if `global_position` is zero) and `scenes/main.gd` (`_on_director_spawn_leviathan()` + `shot=leviathan` set `lev.position` prior to `add_child()`). (Note: `fe288f8` also added `is_defeated()` + `get_health_ratio()` for `_tick_boss_hud()`, cleanly synced with zero conflicts!)
2. **FIXED (HIGH UI BUG) — Long top-center notice banners overlapped top-right Voyage Whisper / Gold card (`src/ui/hud.gd`)**:
   - Added symmetric `340 px` side margins on `BannerHolder`, automatic `AUTOWRAP_WORD_SMART` (`560 px` max width) for notices `> 54` chars while keeping short callouts snug, and shifted `BossBarHolder` `12 px` lower for clean vertical breathing room. Verified visually on `closeup_crab_banner_fix.png` & `leviathan_brig_high.png`!
3. **FIXED (HIGH VISUAL/CAMERA) — `scenes/main.gd` `map_table`, `hold` & Sloop `fleet` cameras**:
   - Moved `map_table` shot camera aft of the table (`table_local + Vector3(0, table_y + 0.88, 0.72)`) via `_enable_ship_track_shot()` so companionway stairs never occlude the chart on either Sloop or Brigantine.
   - Shifted `hold` shot camera clear of the vertical mast and widened Sloop `fleet` framing (`fsc = 1.24`) so all 4 faction ships (including the Ghost Ship on the left) fit comfortably in frame.
4. **FIXED (MEDIUM SHADER) — Cloud raymarch LOD/headroom & warm wet sand (`src/sky/cloud_field.gdshaderinc`, `src/sky/sky_rig.gd`, `src/sky/sky_body.gdshaderinc`, `src/world/island_shader.gdshader`)**:
   - Switched `cloud_map`/`cloud_volume` reads inside the divergent raymarch loop to explicit `textureLod(..., 0.0)` (proper Vulkan GPU practice preventing 2×2 quad derivative mip spikes), raised `slab_top` headroom (`1.80x`, capped `6200 m`) with a soft `340 m` upper density taper (`+0.003 ms`), and warmed grazing beach wet sand (`vec3(0.71, 0.56, 0.31)`, roughness `0.28..0.40`, specular `0.44`) to eliminate cool lavender sky glare on `isl_beach`.

### 4.3 Minor Read-Only Observations Left for Cloud Lead (Fenced Blender Generators)
1. **`tools/blender/gen_brigantine.py`**: In `brig_deck`, one tan starboard brace line still lightly grazes the outer corner brass rail finial on the quarterdeck.
2. **`tools/blender/gen_sloop.py` (`mask_water`)**: Because `mask_water` is traced at `y = 0.0`, a small pale water triangle can peek into the flared stern transom cavity above the waterline when the hull pitches with `water_level > 0` (`main_hold`). Expanding `mask_water` slightly aft/outboard at `y = +0.5` would make the stern hold 100% watertight at every pitch angle.

---

## 5. Ready for Final Fast-Forward Merge!
- Branch **`origin/local/gpu-polish`** is cleanly based on `fe288f8` with **zero merge conflicts** and **zero fenced-file edits**.
- All checks green (`lint: 92 files 0/0`, `114/114` headless tests, `3/3` GPU shader parity, `CLIENT RESULT PASS` co-op net probe, `159/159` audio files `0 flagged` & `100%` in tune, Win/Linux/macOS exports `EXIT=0`, Windows `.exe` 90-frame sailing & live Leviathan Vulkan smoke tests `EXIT=0`).
- Local-GPU partner remains ready to profile/review any further flagship passes Cloud Lead lands!
