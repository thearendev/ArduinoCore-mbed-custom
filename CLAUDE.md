# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This repo is **build tooling**, not application source. It produces a customized build of Arduino's `framework-arduino-mbed` core (consumable by PlatformIO) as a `.tar.gz`. It does this by downloading pinned upstream sources, applying a set of local patches, compiling core configuration for three boards, and packaging the result into `dist/`.

The actual C++/config that gets modified lives in upstream repos (ArduinoCore-mbed, ArduinoCore-API, mbed-os) that are downloaded at build time — they are **not** checked into this repo. The only source-of-truth here is the patch set in `patches/` and the pin/version constants in `docker/build.sh`.

## Build workflow

Two steps, run from the repo root. The build runs entirely inside Docker (needs `gcc-arm-none-eabi`, `mbed-cli`, rust, python).

```bash
./build_image.sh      # build the Docker image (build_image.cmd on Windows)
./run.sh              # run the build; writes tarball to dist/ (run.cmd on Windows)
```

`run.sh` bind-mounts `patches/` (read by the build) and `dist/` (where the output tarball lands) into the container, then executes `/build.sh` (a copy of `docker/build.sh`). The output is `dist/ArduinoCore-mbed-<CORE_MBED_VERSION>.tar.gz`. `dist/` is gitignored except for the committed reference tarballs.

There is no test suite, linter, or incremental build — the container rebuilds from the pinned sources every run.

## How the build is pinned and versioned (docker/build.sh)

The top of `docker/build.sh` is the control panel. All meaningful build changes happen here or in `patches/`:

- `CORE_MBED_HASH` — commit of arduino/ArduinoCore-mbed to fetch
- `API_HASH` — commit of arduino/ArduinoCore-API (only its `api/` subdir is fetched into `cores/arduino`)
- `MBED_OS_VERSION` — commit of ARMmbed/mbed-os; also used to fetch that commit's `requirements.txt` for pip
- `CORE_MBED_VERSION` — the output version string; drives both the tarball filename and the generated `package.json` version. **Bumping the released version = editing this line** (and this is what the `4.x.y` git tags/commits track).
- `BUILD_VARIANTS` — the three boards compiled: `NICLA`, `ARDUINO_NANO33BLE`, `PORTENTA_H7_M7`

Build sequence in `docker/build.sh`: fetch sources → `pip install` mbed requirements → run `./mbed-os-to-arduino -b <hash> -a NOPE:NOPE` (bootstraps mbed-os into `/tmp/mbed-os-program/mbed-os`) → apply patches → re-run `./mbed-os-to-arduino <variant>:<variant>` per board → generate `package.json` → tar up `/ace`.

## Patch system

Patches are applied by shell loops that iterate `ls` order, so the **numeric filename prefix determines apply order** — keep the `NNNN-` numbering consistent when adding patches. All are `git format-patch`-style and applied with `patch -p1`.

Two directories, applied against two different working trees:

- `patches/arduino/` — applied from the ArduinoCore-mbed root (`/ace`). These edit the checked-out core: mostly `variants/<BOARD>/conf/mbed_app.json` (BLE `cordio.*` MTU / max-connections tuning, crash-capture flags, CCCD counts) plus `libraries/SocketWrapper/` C++.
- `patches/mbed/` — applied from the mbed-os checkout (`/tmp/mbed-os-program/mbed-os`). These edit mbed-os itself: the STM32H747 linker script (crash-data RAM section) and the lwIP stack (blocking-connect behavior).

To change board config or core behavior, add/modify a patch — do not expect the target files to exist in this repo; they only exist inside the container after the fetch step. When regenerating a patch, produce it against the same upstream commit the build pins.
