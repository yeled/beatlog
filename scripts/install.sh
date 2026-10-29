#!/usr/bin/env bash
#
# Copy bin/beatlog.prg onto the watch over USB. The Venu 4 is an MTP device,
# not a disk, so this goes through Homebrew's libmtp. Garmin Express holds the
# USB connection while it runs, so it has to be quit first.
#
#   scripts/build.sh && scripts/install.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if pgrep -f "Garmin Express" >/dev/null; then
  echo "Quit Garmin Express first: it holds the watch's USB connection." >&2
  exit 1
fi

# Remove the previous copy, so the watch doesn't end up with two
for id in $(mtp-files 2>/dev/null | awk '/File ID:/ { id = $3 } /Filename: BEATLOG.PRG$/ { print id }'); do
  mtp-delfile -n "$id"
done
mtp-sendfile -q bin/beatlog.prg /Garmin/Apps/BEATLOG.PRG
echo "Installed. Unplug the watch; Beat Log appears in its apps list."
