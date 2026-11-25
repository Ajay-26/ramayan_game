# Ramayan: The Night of Tataka

A single-level, God of War–style action game prototype inspired by the Ramayana, made in **Godot 4.7** (Compatibility renderer, so it runs in the browser).

Prince Rama protects Sage Vishwamitra's yagna through a forest on a stormy night — sneaking past sentries, fighting through a rakshasa war camp and a ravine of archers, claiming the divine chakra in a ruined shrine — and finally faces the demoness **Tataka**, who rides the storm: a long, five-stage boss fight on the ground and in the sky.

## Play

Open the project in Godot 4.7 and press **F5** (starts at the main menu). **Fight Tataka** on the menu jumps straight to the boss.

| Action | Keyboard / Mouse | Gamepad |
|---|---|---|
| Look / Move | Mouse / WASD | Right stick / Left stick |
| Punch (light) | Left click | X |
| Sword (heavy) | Middle click | Y |
| Aim bow / Shoot (hold to charge) | Right click / Left click | LT / RT |
| Homing chakra (short range) | Q | RB |
| Dodge / Jump / Sneak | Shift / Space / C | B / A / L3 |
| Takedown (from behind) | Left click or F | X |
| Astra (when full) / Pause | R / Esc | LB / Start |

Combos: **L L L**, **L H**, **L L H**, or **H** alone.

## Project layout

- `scenes/` — levels, characters, enemies, props, UI
- `scripts/` — gameplay code (player, enemies, combat, camera, world-building, UI)
- `shaders/` — painterly foliage, bark, stone, rock, muscle-shaded skin, storm sky and clouds, full-screen cinematic grade
- `tools/build_level.py` — generates the level scene and props; then bake navigation with `tools/bake_navmesh.tscn`
- `tools/make_sounds.py` — synthesizes every sound effect, ambience loop and music track into `assets/audio/` (`python3 tools/make_sounds.py`); `scripts/autoload/sfx.gd` plays them
- `tests/` — headless tests (see below)
- `DESIGN.md` — design doc; `CREDITS.md` — third-party assets

## Tests

```
Godot --headless --path . res://tests/level_test.tscn
Godot --headless --path . res://tests/player_moves_test.tscn
Godot --headless --path . res://tests/camera_test.tscn
Godot --headless --path . res://tests/tataka_test.tscn
```

Dev tools (need a window): `tools/screenshot.tscn` saves screenshots at checkpoints (`-- <dir> 0 3 6 6:4`; `6:4` = Tataka fight at stage 4), and `tools/perf_probe.tscn` prints frame times with each visual effect switched off.

## Build

Export presets for **Web** (itch.io) and **Windows Desktop** are included (`export_presets.cfg`); exports go to `build/` (not committed).

```
Godot --headless --path . --export-release "Web" build/web/index.html
Godot --headless --path . --export-release "Windows Desktop" build/windows/Ramayan.exe
```

## Credits

Character model and animations: [Cat's Godot 4 Souls-like Template](https://github.com/catprisbrey/Cats-Godot4-Modular-Souls-like-Template) (Unlicense / CC0). Everything else made for this project — see `CREDITS.md`.
