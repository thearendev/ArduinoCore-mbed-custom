#!/usr/bin/env bash

CORE_MBED_HASH=b4ad4e7218a691989acf6c4479112eae183a5a50
API_HASH=0f4e57e
MBED_OS_VERSION=7e16b0044e9e44778f04897343cdc1f631b84d29

set -e

PATH="/venv/bin:$PATH"
BASE_DIR=`pwd`
API_DIR="${BASE_DIR}/cores/arduino"
PATCHES_DIR="/patches"
ARDUINO_PATCHES_DIR="${PATCHES_DIR}/arduino"
MBED_PATCHES_DIR="${PATCHES_DIR}/mbed"
BUILD_VARIANTS=("NICLA" "ARDUINO_NANO33BLE" "PORTENTA_H7_M7")
CORE_MBED_VERSION="4.6.0"
MBED_OS_DIR="/tmp/mbed-os-program/mbed-os"

curl -sSL "https://github.com/arduino/ArduinoCore-mbed/tarball/${CORE_MBED_HASH}" | tar --strip-components 1 -x -z
curl -sSL "https://github.com/arduino/ArduinoCore-API/tarball/${API_HASH}" | tar --strip-components 1 -x -z -C "${API_DIR}" "arduino-ArduinoCore-API-${API_HASH}/api"

# cmsis-pack-manager 0.2.x lists an unpinned setuptools_scm in setup_requires.
# When built from source (e.g. on arm64, where no prebuilt wheel exists) under
# pip's build isolation, setuptools' easy_install fetches setuptools_scm 9+/10+
# but not its new 'vcs-versioning' dependency, so the build fails with
# "No module named 'vcs_versioning'". Pre-install the build deps and build it
# without isolation so it uses them instead of easy_install. On x86_64 a
# prebuilt wheel is used and this is a no-op.
pip install "setuptools_scm<8" setuptools_scm_git_archive milksnake cffi
pip install --no-build-isolation "cmsis-pack-manager>=0.2.3,<0.3.0"

pip install `curl -sSL https://github.com/ARMmbed/mbed-os/raw/${MBED_OS_VERSION}/requirements.txt`

set +e
./mbed-os-to-arduino -b "${MBED_OS_VERSION}" -a NOPE:NOPE
set -e

for p in `ls ${ARDUINO_PATCHES_DIR}`
do
  patch -p1 -i "${ARDUINO_PATCHES_DIR}/${p}"
done

cd "${MBED_OS_DIR}"
for p in `ls ${MBED_PATCHES_DIR}`
do
  patch -p1 -i "${MBED_PATCHES_DIR}/${p}"
done
cd "${BASE_DIR}"

for v in "${BUILD_VARIANTS[@]}"
do
  ./mbed-os-to-arduino "${v}:${v}"
done

cat <<EOF > package.json 
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
tar -c -C / ace | gzip -9 - > "/dist/ArduinoCore-mbed-${CORE_MBED_VERSION}.tar.gz"
