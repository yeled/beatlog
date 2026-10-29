#!/usr/bin/env bash
#
# Build the PRG for the Venu 4 41mm.
#
#   scripts/build.sh            # -> bin/beatlog.prg
#
# The SDK is found by glob so an SDK Manager update doesn't break the build.
set -euo pipefail

cd "$(dirname "$0")/.."

SDK="$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-* | sort -V | tail -1)"
KEY="${KEY:-$HOME/Downloads/developer_key}"
DEVICE="${DEVICE:-venu441mm}"

mkdir -p bin
java -Xms1g -Dapple.awt.UIElement=true -jar "$SDK/bin/monkeybrains.jar" \
  -o bin/beatlog.prg -f monkey.jungle -y "$KEY" -d "$DEVICE" -w
echo "Done: bin/beatlog.prg (device=$DEVICE)"
