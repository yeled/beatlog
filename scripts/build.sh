#!/usr/bin/env bash
#
# Build the PRG for the Venu 4 41mm.
#
#   scripts/build.sh            # -> bin/beatlog.prg, for the watch
#   scripts/build.sh selftest   # -> bin/beatlog-selftest.prg, simulator only:
#                               #    runs a short test on made-up beats by itself
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
  *)        echo "usage: $0 [watch|selftest]" >&2; exit 2 ;;
esac

mkdir -p bin
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o "$OUT" -f "$JUNGLE" -y "$KEY" -d "$DEVICE" -w
echo "Done: $OUT (device=$DEVICE)"
