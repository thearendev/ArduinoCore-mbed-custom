#!/usr/bin/env bash

CORE_MBED_HASH=321c2fbac9c71f086148ecac9d407632db4978df
API_HASH=0c853c5
MBED_OS_VERSION=baf6a3022a328b91713e03fd88f65126a9a53f01

set -e

BASE_DIR=`pwd`
API_DIR="${BASE_DIR}/cores/arduino"
PATCHES_DIR="/patches"
ARDUINO_PATCHES_DIR="${PATCHES_DIR}/arduino"
MBED_PATCHES_DIR="${PATCHES_DIR}/mbed"
BUILD_VARIANTS=("NICLA" "ARDUINO_NANO33BLE" "PORTENTA_H7_M7")
CORE_MBED_VERSION="4.1.1"
MBED_OS_DIR="/tmp/mbed-os-program/mbed-os"

curl -sSL "https://github.com/arduino/ArduinoCore-mbed/tarball/${CORE_MBED_HASH}" | tar --strip-components 1 -x -z
curl -sSL "https://github.com/arduino/ArduinoCore-API/tarball/${API_HASH}" | tar --strip-components 1 -x -z -C "${API_DIR}" "arduino-ArduinoCore-API-${API_HASH}/api"

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
