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

# mtp-sendfile can't find /Garmin/Apps by path, but takes the folder's id
apps=$(mtp-folders 2>/dev/null | awk -F'\t' '
  $2 == "Garmin" { garmin = 1; next }
  garmin && $2 == "  Apps" { print $1; exit }
  $2 !~ /^ / { garmin = 0 }')
if [ -z "$apps" ]; then
  echo "No Garmin/Apps folder on the watch." >&2
  exit 1
fi

# Remove the previous copy, so the watch doesn't end up with two. The watch
# keeps file names in lower case, whatever they were sent as.
for id in $(mtp-files 2>/dev/null | awk '/File ID:/ { id = $3 } tolower($0) ~ /filename: beatlog\.prg$/ { print id }'); do
  mtp-delfile -n "$id"
done
mtp-sendfile bin/beatlog.prg "$apps/BEATLOG.PRG"

# mtp-sendfile exits 0 even when it sends nothing. (Not grep -q: it stops
# reading at the first match, and pipefail then fails on mtp-files' SIGPIPE.)
if ! mtp-files 2>/dev/null | grep -i "Filename: beatlog\.prg$" >/dev/null; then
  echo "BEATLOG.PRG didn't arrive on the watch." >&2
  exit 1
fi
echo "Installed. Unplug the watch; Beat Log appears in its apps list."
