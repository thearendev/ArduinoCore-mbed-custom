# ArduinoCore-mbed-custom

Build tooling that produces a **customized build of Arduino's `framework-arduino-mbed` core** as a `.tar.gz` package, ready to be consumed by PlatformIO.

The build downloads pinned upstream sources ([ArduinoCore-mbed](https://github.com/arduino/ArduinoCore-mbed), [ArduinoCore-API](https://github.com/arduino/ArduinoCore-API), [mbed-os](https://github.com/ARMmbed/mbed-os)), applies a set of local patches, compiles the core configuration for three boards, and packages the result. Everything runs inside Docker, so the only local requirement is Docker itself.

## Supported boards

- Arduino Nicla (`NICLA`)
- Arduino Nano 33 BLE (`ARDUINO_NANO33BLE`)
- Arduino Portenta H7 / M7 (`PORTENTA_H7_M7`)

## What the patches change

- **BLE tuning** — larger ATT MTU (`cordio.desired-att-mtu` / `rx-acl-buffer-size`), constrained `max-connections`, and increased CCCD / characteristic-authorisation counts on the H7.
- **Crash capture** — enables mbed crash-capture, auto-reboot on fatal error, and reserves a dedicated crash-data RAM section in the STM32H747 linker script.
- **Networking** — non-blocking lwIP socket connect, and exposing the mbed HTTP/HTTPS request helpers through `SocketWrapper`.

See [patches/](patches/) for the full set. Patches under `patches/arduino/` apply to the ArduinoCore-mbed tree; those under `patches/mbed/` apply to the mbed-os tree.

## Usage

Requires Docker. Run from the repository root.

**1. Build the Docker image**

```bash
./build_image.sh      # Windows: build_image.cmd
```

**2. Run the build**

```bash
./run.sh              # Windows: run.cmd
```

This bind-mounts `patches/` (read by the build) and `dist/` (output) into the container and runs the build. The resulting package is written to:

```
dist/ArduinoCore-mbed-<version>.tar.gz
```

## Configuration

All build parameters live at the top of [docker/build.sh](docker/build.sh):

| Variable | Purpose |
| --- | --- |
| `CORE_MBED_HASH` | Pinned commit of `arduino/ArduinoCore-mbed` |
| `API_HASH` | Pinned commit of `arduino/ArduinoCore-API` |
| `MBED_OS_VERSION` | Pinned commit of `ARMmbed/mbed-os` |
| `CORE_MBED_VERSION` | Output version — sets the tarball filename and `package.json` version |
| `BUILD_VARIANTS` | Boards compiled by the build |

To release a new version, bump `CORE_MBED_VERSION`. To change board configuration or core behavior, add or edit a patch in `patches/` (numeric filename prefixes determine apply order).

## Repository layout

```
docker/          Dockerfile and the in-container build script
patches/arduino/ Patches applied to the ArduinoCore-mbed tree
patches/mbed/    Patches applied to the mbed-os tree
dist/            Build output (gitignored, except reference tarballs)
build_image.*    Build the Docker image
run.*            Run the build
```
