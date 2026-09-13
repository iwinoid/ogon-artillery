# ОГОНЬ! (Ogon!) — Artillery Fire Direction Game

[简体中文](README.zh_CN.md)

[![standard-readme compliant](https://img.shields.io/badge/readme%20style-standard-brightgreen?style=for-the-badge)](https://github.com/RichardLitt/standard-readme)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](https://spdx.org/licenses/MIT.html)
[![powered by DeepSeek](https://img.shields.io/badge/powered_by-DeepSeek-4D6BFE?style=for-the-badge&logo=deepseek&logoColor=white)](https://deepseek.com)
[![powered by dsh](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=for-the-badge&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
[![R ≥ 4.2](https://img.shields.io/badge/R-%E2%89%A5%204.2-276DC3?style=for-the-badge&logo=r&logoColor=white)](https://www.r-project.org/)

Turn-based artillery fire direction game in base R: mils, charge tables, observer corrections, five historical guns.

The Russian word «Огонь!» means «Fire!». The repository name is `ogon-artillery`. You act as a battery commander. You compute firing data, give fire commands, and correct the fall of shot from observer reports. The game uses base R graphics and has no runtime dependencies.

## Screenshots

|               Map, photo style               |                  Map, tactical style                  |             Trajectory side view              |
| :------------------------------------------: | :---------------------------------------------------: | :-------------------------------------------: |
| ![Photo map](image/README/map-photo.png) | ![Tactical map](image/README/map-tactical.png) | ![Trajectory](image/README/trajectory.png) |

The screenshots show the Leningrad scenario on real terrain (64×44 km).

## Table of Contents

- [Background](#background)
- [Install](#install)
  - [Dependencies](#dependencies)
  - [From Source](#from-source)
  - [Uninstall](#uninstall)
- [Usage](#usage)
- [Features](#features)
- [Map Styles](#map-styles)
- [Architecture](#architecture)
- [Known Limitations](#known-limitations)
- [API](#api)
- [Maintainers](#maintainers)
- [Thanks](#thanks)
- [Contributing](#contributing)
- [Changelog](#changelog)
- [License](#license)

## Background

Artillery fire direction is a small closed loop. You compute the firing data, you fire, an observer reports the fall of shot, and you correct the data. This project turns that loop into a game. You play it in the R console.

The numbers come from a real model. Each shell follows a point-mass trajectory with square-law air drag. The drag coefficient of each gun is calibrated against its historical maximum range. The dispersion of each gun follows its probability error. Wind and terrain height change the impact point.

The game speaks Chinese in the console. The tutorial and the manual are in Chinese.

Developed by DeepSeek V4 via [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness).

## Install

### Dependencies

- R ≥ 4.2. No R package is necessary at run time.
- Optional, for real terrain: `terra` and `png` (Leningrad scenario), or `elevatr` and `terra` (any area). These packages need network access.

### From Source

```bash
git clone https://github.com/iwinoid/ogon-artillery.git
cd ogon-artillery
Rscript main.R
```

In RStudio, open `main.R` and click **Source**. The game finds its own directory, thus the working directory does not matter.

### Uninstall

Delete the directory. The game writes only to `docs/` (map frames and playthrough logs).

## Usage

1. Start the game. The main menu appears.
2. Select `1` (start battle). The submenu offers a random campaign, a historical scenario, or the tutorial.
3. Select the tutorial first. The target is large and the wind is zero.
4. Enter `诸元 target` (compute firing data). The calculator gives azimuth, elevation, and charge.
5. Enter `射击 <azimuth> <elevation> <charge> 1` (fire one round).
6. Read the observer report. Enter `修正 <range error> <deflection error>` (correct the data).
7. Enter `急促 <azimuth> <elevation> <charge>` (three-round burst) or `效力` (fire for effect).
8. Enter `结束` (end the mission) and read the score.

Command line options:

| Option | Function |
| --- | --- |
| `--mode arcade\|std\|hard` | Difficulty. Arcade adds suggestions and reduces dispersion. Hard removes the calculator. |
| `--gun D20\|M46\|M109\|B4\|B37` | Select the gun. |
| `--seed N` | Fix the random seed. The same seed reproduces the same battle. |
| `--scenario leningrad` | Start the historical scenario. |
| `--map FILE` | Load a DEM cache for real terrain. |
| `--test FILE --pngdir DIR` | Run a scripted battle and write map frames. |
| `--nocolor` | Disable ANSI color. |

The full tutorial is in [TUTORIAL.md](TUTORIAL.md) (Chinese).

## Features

- **Ballistics**: point mass, square-law drag, RK4 integration at 0.2 s steps, wind, and terrain height. The drag coefficient of each gun matches its historical maximum range.
- **Mils**: a 6000 mil circle. Azimuth and elevation use mils. The game selects the charge and interpolates the range table.
- **Fire direction calculator** (`诸元`): azimuth, wind drift, site correction, and an iterative solution on real terrain.
- **Observer reports**: over, short, left, and right in meters. The `修正` command converts them to mils.
- **Five guns**: 152 mm D-20, 130 mm M-46, 155 mm M109A6, 203 mm B-4, and 406 mm B-37, with approximate historical data.
- **Campaign**: four target types, random positions, random weather, limits on ammunition and fire commands, and an S–C rating.
- **Historical scenario**: the Siege of Leningrad, 1942. A 406 mm B-37 gun fires at seven historical targets on a 64×44 km real-terrain map.
- **Reconnaissance error**: in a campaign, the reported target coordinates differ from the true position by 5 m to 15 m. Trial fire removes the error.
- **Tutorial mission** and three difficulty modes.
- **Reproducible battles**: `--seed` fixes terrain, targets, weather, and impacts.

## Map Styles

The game draws two map styles. Switch with the `地图样式` command or with item 4 of the main menu.

| Style | Look |
| --- | --- |
| Photo | Elevation bands of 25 m with hillshade, blue water, and a wide canvas |
| Tactical | Paper base, smoothed contour lines with index labels, and pale blue water |

The map also adapts to the map size. The canvas follows the map aspect ratio, and the grid spacing follows the map width.

## Architecture

The game is a set of R modules. `main.R` sources them in this order.

| File | Function |
| --- | --- |
| `main.R` | Entry point. Parses the options, finds the game directory, and starts the menu or a scripted battle. |
| `config.R` | Gun data, world constants, difficulty modes, and gun positions. |
| `ballistics.R` | Trajectory integration, dispersion, range tables, drag calibration, and the side view. |
| `map.R` | Terrain generation, DEM loading, and map rendering. |
| `fdc.R` | Fire direction calculator. |
| `mission.R` | Mission generation, observer reports, and scoring. |
| `ui.R` | Console panels, help text, and the in-game tutorial. |
| `game.R` | State machine, fire execution, command dispatch, and the main loop. |
| `tools/` | DEM download tools, the range-table generator, and a scenario render helper. |
| `tests/` | Test scripts and the AI playthrough. |

Data flow of one shot:

```
command (射击 / 急促 / 效力)
  → fire_volley (game.R)
    → trajectory (ballistics.R: RK4, wind, terrain)
    → disperse_impact (ballistics.R: probability error)
  → observer_report (mission.R: over/short, left/right)
  → check_destroyed (mission.R: true target position)
  → draw_state (game.R → map.R)
```

## Known Limitations

- The trajectory is a point-mass model. It has no spin stabilization and no Magnus effect.
- The drag coefficient is calibrated at one point, the 45° maximum-range shot.
- The game does not mask line of sight. A target behind a ridge is still visible to direct fire.
- Dispersion is an independent normal model in range and deflection.
- The Leningrad DEM has a resolution of 150 m. The map shows tile-seam artifacts: a diagonal line in the Gulf of Finland and a vertical line near x = 55 km.
- The default free map is 20×20 km. The 27 km M-46 and the 45.5 km B-37 need a larger map.
- The map rendering is under revision. Colors, labels, and terrain resolution change between versions.

## API

The game commands are the interface. Chinese and English names are equivalent.

| Command | Aliases | Function |
| --- | --- | --- |
| `帮助` | `help` | Show the command list. |
| `教程` | `tutorial` | Show the short tutorial. |
| `任务` | `mission` | Show the mission brief. |
| `地图` | `map` | Redraw the map. |
| `情况` | `status` | Show status, ammunition, and wind. |
| `炮位` / `选择 <n>` | `guns` / `sel` | List the gun positions. Switch position. |
| `射表 [charge]` | `table` | Show the range table. |
| `诸元 <x> <y>` or `诸元 target` | `calc` | Compute the firing data. |
| `射击 <az> <el> <charge> [rounds]` | `fire` | Fire 1 to 6 rounds. |
| `急促 <az> <el> <charge>` | `rapid` | Fire a three-round burst. |
| `效力 <az> <el> <charge>` | `eff` | Fire for effect, up to six rounds. Stop after a hit. |
| `修正 <range error> <deflection error>` | `corr` | Convert an observer report to mils. |
| `弹道 [n]` | `traj` | Show the side view of shot n. |
| `气象` | `wind` | Show the wind. |
| `地图样式 [战术/照片]` | `style` | Switch the map style. |
| `成绩` | `score` | Show the current score. |
| `结束` | `end` | End the mission and show the result. |
| `退出` | `quit` | Quit the game. |

## Maintainers

- [Iwinoid](https://github.com/iwinoid) — iwinoid@outlook.com

## Thanks

- The [R project](https://www.r-project.org/) and its base graphics.
- [AWS Terrain Tiles](https://registry.opendata.aws/terrain-tiles/) for the Leningrad elevation data.
- Wikipedia for the town coordinates along the Neva river.

## Contributing

Bug reports and questions are welcome on the [GitHub Issues](https://github.com/iwinoid/ogon-artillery/issues) page. Pull requests are accepted.

Development happens in a local working tree. This repository receives snapshots. If you send a pull request, keep the tests green:

```bash
Rscript tests/test_ballistics.R
Rscript tests/test_map.R
Rscript tests/test_scenario.R
Rscript tests/test_game.R
```

## Changelog

- **0.1.0** — 2026-09-13 — first public snapshot: ballistic model with drag calibration, mils and range tables, fire direction calculator, observer reports, five guns, random campaign, Leningrad scenario with real terrain, tutorial mission, three difficulty modes, reconnaissance error, two map styles, and the test suite.

## License

[MIT](LICENSE) © Iwinoid
