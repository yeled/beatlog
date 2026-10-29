#!/usr/bin/env bash
#
# Build the PRG for the Venu 4 41mm.
#
#   scripts/build.sh            # -> bin/beatlog.prg, for the watch
#   scripts/build.sh selftest   # -> bin/beatlog-selftest.prg, simulator only:
#                               #    runs a short test on made-up beats by itself
#   scripts/build.sh iq         # -> bin/beatlog-<AppVersion>.iq, the store
#                               #    package for every device in the manifest
#
# The SDK is found by glob so an SDK Manager update doesn't break the build.
set -euo pipefail

cd "$(dirname "$0")/.."

SDK="$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-* | sort -V | tail -1)"
KEY="${KEY:-$HOME/Downloads/developer_key}"
DEVICE="${DEVICE:-venu441mm}"

case "${1:-watch}" in
  watch)    OUT=bin/beatlog.prg;          JUNGLE="monkey.jungle" ;;
  selftest) OUT=bin/beatlog-selftest.prg; JUNGLE="monkey.jungle;selftest.jungle" ;;
  iq)
    VERSION="$(sed -n 's/.*id="AppVersion">\([^<]*\)<.*/\1/p' resources/strings/strings.xml)"
    OUT="bin/beatlog-$VERSION.iq"
    mkdir -p bin
    java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
      -o "$OUT" -f monkey.jungle -y "$KEY" -e -w
    echo "Done: $OUT"
    exit 0
    ;;
  *)        echo "usage: $0 [watch|selftest|iq]" >&2; exit 2 ;;
esac

mkdir -p bin
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o "$OUT" -f "$JUNGLE" -y "$KEY" -d "$DEVICE" -w
echo "Done: $OUT (device=$DEVICE)"
