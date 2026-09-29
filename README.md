<h1 align="center">Crazy Climber Hardware FPGA Core</h1>

<p align="center">
  Arcade hardware implementation for MiSTer FPGA
</p>

---

## Overview

FPGA implementation of the **Nichibutsu Crazy Climber hardware (1980)** and the boards derived from it, in a single core.

Every board family in MAME's `cclimber.cpp` driver is supported, including the TMS5110 speech of Le Bagnard and the separate sound boards of Swimmer, Guzzler, Yamato and Tangram Q.

This core targets MiSTer FPGA and aims for accurate gameplay behavior, video timing, and sound reproduction.

---

## Supported Games

| Hardware | Games |
|----------|-------|
| Crazy Climber | Crazy Climber and clones |
| Crazy Kong | Crazy Kong, Crazy Kong Part II, Le Bagnard (with speech), and clones |
| Other cclimber boards | River Patrol, Cannon Ball, Swimmer, Guzzler, Au, Tangram Q, Yamato, Top Roller |

Clones and regional versions are in `releases/_alternatives/`.

---

## Controls

Default MiSTer gamepad mapping (button names are set per game by its `.mra`):

| Input | Action |
|-------|--------|
| D-Pad / Joystick | Move (Crazy Climber: left hand) |
| A | Button 1 |
| Y | Button 2 |
| B | Button 3 |
| X | Button 4 |
| Select | Insert Coin |
| Start | 1 Player Start |
| Right Shoulder | 2 Player Start |
| Left Shoulder | Pause |

**Crazy Climber** uses two joysticks, one per hand. The right hand is the right analog stick, or A / Y / B / X as right / left / down / up.

---

## Features

- One core for every supported board, selected by the `.mra`
- Arcade-accurate CPU timing
- AY-3-8910 sound, Crazy Climber sample playback hardware and TMS5110 speech
- Encrypted sets decoded in hardware, as the original boards did
- High score saving support (37 sets)
- DIP switches for every set, taken from MAME
- CRT and HDMI flip, pause, and scandoubler options
- MiSTer-compatible .mra provided
- Verified ROM definitions with checksums

---

## ROM Requirements

ROM files are **not included**.

To use this arcade core, you must provide legally obtained ROM files.

To simplify setup:

- `.mra` files are provided in the **Releases** section.
- The `.mra` specifies all required ROM files along with checksums.
- The ROM `.zip` filename corresponds to the naming convention used by the MAME project.

For setup instructions and environment configuration, refer to:

MiSTer Arcade ROM guide:  
https://github.com/MiSTer-devel/Main_MiSTer/wiki/Arcade-Roms

---

## Installation

1. Copy the core `.rbf` file to your MiSTer `/_Arcade/cores` folder.
2. Copy the `.mra` files (including the `_alternatives` folder) to your MiSTer `/_Arcade` folder.
3. Place the appropriate ROM `.zip` files in your `/games/mame` directory.
4. Launch the core from the MiSTer Arcade menu.

---

## Legal Notice

This project contains **no copyrighted game data**.

Users are responsible for obtaining and using ROM files in accordance with applicable laws.

Do not request ROM files in issues or discussions.

---

## Credits

FPGA core development: RodimusFVC  
Video pipeline derived from Crazy Climber FPGA by Dar (darfpga)  
Memory maps, sound and speech per the MAME project (Nicola Salmoria, hap and contributors)  
T80 CPU core: Daniel Wallner, with updates by Sorgelig  
JT49 sound core: Jose Tejada (jotego)  
Hiscore, pause and NVRAM modules: Jim Gregory and Alan Steremberg  
Audio filters: Gregory Hogan (Soltan_G42)  
Original arcade games © Nichibutsu and their respective owners

---
