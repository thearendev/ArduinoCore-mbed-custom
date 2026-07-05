#!/usr/bin/env bash
#
# Local (non-Docker) convenience build of the customized framework-arduino-mbed
# core. Mirrors docker/build.sh but runs directly on the host, keeping every
# downloaded/generated artifact inside ./workdir (which is gitignored).
#
# NOTE: the Docker build (build_image.sh + run.sh) is the source of truth for
# release artifacts. It pins Python 3.9 and GCC 9-2019-q4 in a clean image.
# This script depends on host tooling and is only correct when that tooling
# matches (see below); use it for iteration, not for producing releases.
#
# Prerequisites on PATH:
#   git, curl, tar, jq, rsync, mercurial (hg), python <=3.11 (mbed-os tools use
#   imp/distutils, removed in 3.12; override with PYTHON_BIN=/path/to/python3.x),
#   arm-none-eabi-gcc == 9-2019-q4 (the version the mbed-os/core patches target;
#   newer GCC miscompiles the STM32H7/WiFi code -> broken PORTENTA build)
# On macOS also: bash 4+ (system bash is 3.2), gsed, gcp, GNU coreutils
#     brew install bash jq rsync hg gnu-sed coreutils python
#     GCC 9-2019-q4: https://developer.arm.com/-/media/Files/downloads/gnu-rm/9-2019q4
#
# Usage: ./build_local.sh [--fresh-venv]
#   --fresh-venv   recreate the Python venv from scratch (otherwise reused)
#
# Output: dist/ArduinoCore-mbed-<CORE_MBED_VERSION>.tar.gz

set -e

FRESH_VENV=0
for arg in "$@"; do
  case "${arg}" in
    --fresh-venv) FRESH_VENV=1 ;;
    -h|--help)
      echo "Usage: $0 [--fresh-venv]"
      echo "  --fresh-venv   recreate the Python venv from scratch (otherwise reused)"
      exit 0 ;;
    *)
      echo "Unknown argument: ${arg}"
      echo "Usage: $0 [--fresh-venv]"
      exit 1 ;;
  esac
done

CORE_MBED_HASH=b4ad4e7218a691989acf6c4479112eae183a5a50
API_HASH=0f4e57e
MBED_OS_VERSION=d723bf9e55415433e108124ee6d36337feddf1b8
CORE_MBED_VERSION="4.6.0"
BUILD_VARIANTS=("NICLA" "ARDUINO_NANO33BLE" "PORTENTA_H7_M7")

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${REPO_DIR}/workdir"
DIST_DIR="${REPO_DIR}/dist"
PATCHES_DIR="${REPO_DIR}/patches"
ARDUINO_PATCHES_DIR="${PATCHES_DIR}/arduino"
MBED_PATCHES_DIR="${PATCHES_DIR}/mbed"

BASE_DIR="${WORKDIR}/ace"
API_DIR="${BASE_DIR}/cores/arduino"
MBED_OS_DIR="${WORKDIR}/mbed-os-program/mbed-os"
VENV_DIR="${WORKDIR}/venv"

# mbed-os-to-arduino hardcodes `cd /tmp/`; we rewrite it to keep the mbed-os
# checkout under ${WORKDIR}. Pick the macOS variant on Darwin.
if [[ "$(uname)" == "Darwin" ]]; then
  M2A_SCRIPT="mbed-os-to-arduino-macos"
else
  M2A_SCRIPT="mbed-os-to-arduino"
fi
M2A_URL="https://raw.githubusercontent.com/arduino/ArduinoCore-mbed/${CORE_MBED_HASH}/${M2A_SCRIPT}"

echo ">> Checking prerequisites..."
MISSING=()
# cmsis-pack-manager installs from a prebuilt wheel on macOS, so cargo/rust is
# not needed here (unlike the Docker/arm64-linux image, which builds it).
REQUIRED=(git curl tar jq rsync hg python3 arm-none-eabi-gcc)
if [[ "$(uname)" == "Darwin" ]]; then
  REQUIRED+=(gsed gcp)
fi
for tool in "${REQUIRED[@]}"; do
  command -v "${tool}" >/dev/null 2>&1 || MISSING+=("${tool}")
done
if [ ${#MISSING[@]} -ne 0 ]; then
  echo "ERROR: missing required tools: ${MISSING[*]}"
  echo "See the header of this script for install hints."
  exit 1
fi

# The mbed-os/core patches target GCC 9-2019-q4. A newer toolchain silently
# miscompiles (e.g. STM32H7 WiFi code) and yields a broken/incorrect libmbed.a,
# so refuse to proceed unless the version matches (override with ALLOW_ANY_GCC=1).
GCC_MAJOR="$(arm-none-eabi-gcc -dumpversion 2>/dev/null | cut -d. -f1)"
if [ "${GCC_MAJOR}" != "9" ] && [ "${ALLOW_ANY_GCC:-0}" != "1" ]; then
  echo "ERROR: arm-none-eabi-gcc is $(arm-none-eabi-gcc --version 2>/dev/null | head -1)"
  echo "       This build requires GCC 9-2019-q4 (newer versions miscompile the core)."
  echo "       Install it and put it first on PATH, or set ALLOW_ANY_GCC=1 to override."
  echo "       Download: https://developer.arm.com/-/media/Files/downloads/gnu-rm/9-2019q4"
  exit 1
fi

# mbed-os-to-arduino uses associative arrays (declare -A), which require Bash 4+.
# macOS ships Bash 3.2, so find a newer interpreter (e.g. from Homebrew) and use
# it explicitly to run the script instead of relying on its shebang/PATH.
BASH_BIN=""
for cand in "$(command -v bash)" \
            "$(brew --prefix 2>/dev/null)/bin/bash" \
            /opt/homebrew/bin/bash /usr/local/bin/bash; do
  if [ -x "${cand}" ] && "${cand}" -c '((BASH_VERSINFO[0] >= 4))' 2>/dev/null; then
    BASH_BIN="${cand}"
    break
  fi
done
if [ -z "${BASH_BIN}" ]; then
  echo "ERROR: need Bash 4+ to run mbed-os-to-arduino (macOS ships 3.2)."
  echo "Install a newer one: brew install bash"
  exit 1
fi
echo ">> Using Bash for mbed-os-to-arduino: ${BASH_BIN} ($(${BASH_BIN} -c 'echo $BASH_VERSION'))"

# The mbed-os tools (make.py, toolchains) use imp/distutils, which were removed
# in Python 3.12, so `mbed compile` fails on 3.12+ (the Docker build uses 3.9).
# Pick a compatible interpreter (newest first, capped at 3.11). Override with
# PYTHON_BIN=... .
if [ -z "${PYTHON_BIN:-}" ]; then
  for py in python3.11 python3.10 python3.9; do
    if command -v "${py}" >/dev/null 2>&1; then PYTHON_BIN="$(command -v "${py}")"; break; fi
  done
fi
if [ -z "${PYTHON_BIN:-}" ]; then
  echo "ERROR: need Python <=3.11 for the mbed-os tools (default python3 is $(python3 --version 2>&1))."
  echo "Install one, e.g.: brew install python@3.11  (or set PYTHON_BIN=/path/to/python3.x)"
  exit 1
fi
echo ">> Using Python: ${PYTHON_BIN} ($(${PYTHON_BIN} --version 2>&1))"

if [ "${FRESH_VENV}" -eq 1 ]; then
  echo ">> --fresh-venv: removing existing venv..."
  rm -rf "${VENV_DIR}"
fi

# Rebuild the venv if it exists but was created with a different Python version.
if [ -d "${VENV_DIR}" ]; then
  CUR_PYVER="$("${VENV_DIR}/bin/python" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null)"
  WANT_PYVER="$("${PYTHON_BIN}" -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
  if [ "${CUR_PYVER}" != "${WANT_PYVER}" ]; then
    echo ">> Existing venv uses Python ${CUR_PYVER:-unknown}; rebuilding with ${WANT_PYVER}..."
    rm -rf "${VENV_DIR}"
  fi
fi

echo ">> Cleaning ${WORKDIR} (keeping venv)..."
mkdir -p "${WORKDIR}" "${DIST_DIR}"
# Remove everything except the venv so it can be reused across runs.
find "${WORKDIR}" -mindepth 1 -maxdepth 1 ! -path "${VENV_DIR}" -exec rm -rf {} +

if [ -d "${VENV_DIR}" ]; then
  echo ">> Reusing existing Python venv..."
  export PATH="${VENV_DIR}/bin:${PATH}"
  VENV_EXISTS=1
else
  echo ">> Creating Python venv..."
  "${PYTHON_BIN}" -m venv "${VENV_DIR}"
  export PATH="${VENV_DIR}/bin:${PATH}"
  pip install --upgrade pip wheel setuptools >/dev/null
  pip install mbed-cli
  VENV_EXISTS=0
fi

echo ">> Fetching ArduinoCore-mbed (${CORE_MBED_HASH})..."
mkdir -p "${BASE_DIR}"
curl -sSL "https://github.com/arduino/ArduinoCore-mbed/tarball/${CORE_MBED_HASH}" \
  | tar --strip-components 1 -x -z -C "${BASE_DIR}"

echo ">> Fetching ArduinoCore-API (${API_HASH})..."
curl -sSL "https://github.com/arduino/ArduinoCore-API/tarball/${API_HASH}" \
  | tar --strip-components 1 -x -z -C "${API_DIR}" "arduino-ArduinoCore-API-${API_HASH}/api"

if [ "${VENV_EXISTS}" -eq 0 ]; then
  REQ_FILE="${WORKDIR}/mbed-requirements.txt"
  curl -sSL "https://github.com/ARMmbed/mbed-os/raw/${MBED_OS_VERSION}/requirements.txt" -o "${REQ_FILE}"
  if [[ "$(uname)" == "Darwin" ]]; then
    # The hidapi version pinned by mbed-os requirements (>=0.7.99,<0.8.0) fails
    # to build on macOS. Install a known-good prebuilt wheel and relax the pin
    # so pip keeps it instead of trying to build the old one.
    echo ">> Installing hidapi==0.15.0 and relaxing mbed-os hidapi pin (macOS)..."
    pip install hidapi==0.15.0
    sed -i.bak 's/^hidapi.*/hidapi/' "${REQ_FILE}" && rm -f "${REQ_FILE}.bak"
  fi
  # cmsis-pack-manager 0.2.x lists an unpinned setuptools_scm in setup_requires.
  # When built from source (e.g. on Apple Silicon, where no prebuilt wheel
  # exists) under pip's build isolation, setuptools' easy_install fetches
  # setuptools_scm 9+/10+ but not its new 'vcs-versioning' dependency, so the
  # build fails with "No module named 'vcs_versioning'". Pre-install the build
  # deps and build it without isolation so it uses them instead of easy_install.
  echo ">> Pre-building cmsis-pack-manager (vcs_versioning workaround)..."
  pip install "setuptools_scm<8" setuptools_scm_git_archive milksnake cffi
  pip install --no-build-isolation "cmsis-pack-manager>=0.2.3,<0.3.0"
  echo ">> Installing mbed-os python requirements..."
  pip install -r "${REQ_FILE}"
else
  echo ">> Reusing venv: skipping mbed-os python requirements install."
fi

echo ">> Downloading ${M2A_SCRIPT} and pointing it at ${WORKDIR}..."
curl -sSL "${M2A_URL}" -o "${BASE_DIR}/mbed-os-to-arduino"
# Redirect the hardcoded `cd /tmp/` to our workdir so the whole build stays local.
sed -i.bak "s#cd /tmp/#cd \"${WORKDIR}\"#" "${BASE_DIR}/mbed-os-to-arduino"
rm -f "${BASE_DIR}/mbed-os-to-arduino.bak"
chmod 755 "${BASE_DIR}/mbed-os-to-arduino"

cd "${BASE_DIR}"

echo ">> Bootstrapping mbed-os checkout (${MBED_OS_VERSION})..."
set +e
"${BASH_BIN}" ./mbed-os-to-arduino -b "${MBED_OS_VERSION}" -a NOPE:NOPE
set -e

echo ">> Applying Arduino core patches..."
for p in $(ls "${ARDUINO_PATCHES_DIR}"); do
  patch -p1 -i "${ARDUINO_PATCHES_DIR}/${p}"
done

echo ">> Applying mbed-os patches..."
cd "${MBED_OS_DIR}"
for p in $(ls "${MBED_PATCHES_DIR}"); do
  patch -p1 -i "${MBED_PATCHES_DIR}/${p}"
done
cd "${BASE_DIR}"

for v in "${BUILD_VARIANTS[@]}"; do
  echo ">> Compiling variant ${v}..."
  "${BASH_BIN}" ./mbed-os-to-arduino "${v}:${v}"
done

echo ">> Writing package.json..."
cat <<EOF > "${BASE_DIR}/package.json"
{
  "name": "framework-arduino-mbed",
  "version": "${CORE_MBED_VERSION}",
  "description": "Arduino framework supporting mbed-enabled boards",
  "keywords": [
    "framework",
    "arduino",
    "mbed"
  ],
  "homepage": "https://www.arduino.cc/reference/en",
  "repository": {
    "type": "git",
    "url": "https://github.com/arduino/ArduinoCore-mbed"
  }
}
EOF

echo ">> Packaging..."
tar -c -C "${WORKDIR}" ace | gzip -9 - > "${DIST_DIR}/ArduinoCore-mbed-${CORE_MBED_VERSION}.tar.gz"

echo ">> Done: ${DIST_DIR}/ArduinoCore-mbed-${CORE_MBED_VERSION}.tar.gz"
