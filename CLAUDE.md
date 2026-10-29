# beatlog

Connect IQ watch app (Monkey C) for the Venu 4 41mm (`venu441mm`) that runs
an HRV test and writes every beat interval into the activity's FIT file.
`tools/beats.py` reads them back. The app's structure and FIT layout are in
README.md.

## Build, test, install

The SDK is found by glob and the signing key is `~/Downloads/developer_key`
(shared with `~/src/analog-simple`); don't hardcode `/Users/<name>/` paths.

```sh
scripts/build.sh            # bin/beatlog.prg for the watch
scripts/build.sh selftest   # bin/beatlog-selftest.prg, simulator only
scripts/build.sh iq         # bin/beatlog-<AppVersion>.iq, the store package
scripts/install.sh          # sideload over MTP (Garmin Express must not be running)
```

The self-test build layers `selftest.jungle` over `monkey.jungle`, which
swaps the `(:notselftest)` stub for `source/SelfTest.mc`: it starts a
5 s + 20 s test by itself, feeds a fixed beat sequence through
`BeatTest.addBeats` (the path real sensor data takes), and prints every beat
and the final statistics. Verify a change by running it and checking that
`tools/beats.py` recovers exactly the printed beats and the same numbers:

```sh
SDK="$(ls -d "$HOME/Library/Application Support/Garmin/ConnectIQ/Sdks"/connectiq-sdk-mac-* | sort -V | tail -1)"
"$SDK/bin/connectiq" &   # once
java -classpath "$SDK/bin/monkeybrains.jar" com.garmin.monkeybrains.monkeydodeux.MonkeyDoDeux \
  -f bin/beatlog-selftest.prg -d venu441mm -s "$SDK/bin/shell" > selftest.log   # Ctrl-C after "selftest: done"
.venv/bin/python -I tools/beats.py "$(ls "$TMPDIR"/com.garmin.connectiq/GARMIN/Activities/*.fit | tail -1)" --csv beats.csv
```

## Gotchas (learned 2026-10-29)

- Call `MonkeyDoDeux` directly as above: through the `monkeydo` wrapper with
  output redirected, the app's `System.println` lines never arrived.
- macOS App Nap throttles a hidden simulator so badly that timers fire tens
  of seconds late and records go missing. `NSAppSleepDisabled` is set for
  `com.garmin.connectiq.simulator` on this Mac; if timings look stretched,
  check it's still there.
- The simulator writes an all-zero developer application id, so the reader
  finds fields by name, not by app id.
- `FitContributor` is its own manifest permission, separate from `Fit`.
- The simulator's activities go to
  `$TMPDIR/com.garmin.connectiq/GARMIN/Activities/`; a file being recorded
  has a zero data size in its header and won't decode until saved.
- Developer field ids are permanent: add new ids, never renumber.
- The simulator doesn't enforce the watch's execution watchdog, so keep
  per-update work small: `BeatRing` computes each beat's position once, on
  arrival, and `onUpdate` only draws lines.
- Screenshots: File › Save Screen Capture opens a save panel that runs in a
  separate process, which computer use can't drive (nor AppleScript while
  the screen is locked). Crop a 1:1 window capture instead: in the 570×918
  simulator window the 390×390 display sits at (93, 252)–(483, 642).
- If `MonkeyDoDeux` prints nothing (seen after the Mac locked), the
  simulator is wedged: `pkill -f "ConnectIQ.app/Contents/MacOS/simulator"`
  and reopen it.
- The self-test's 20 s ring has only ~24 beats. To see what a full
  five-minute ring looks like, temporarily make `SelfTest.onTick` add 15000
  to `_budget` during `PHASE_MEASURING`; the results screen then shows ~390
  beats. Revert it before checking the FIT file, since 15 beats a second
  overflows the 16-beat record window.

## Open questions

- Whether `heartBeatIntervals` carries the HRM600's intervals when the strap
  is connected, or the wrist sensor's. `tools/beats.py` reports which heart
  rate sources the FIT file lists; check the first real test.
- Whether the Venu 4 writes a record every second for this app. If
  `tools/beats.py` reports missing beats, raise `WINDOW`.

## Commits

Signed through 1Password; in a non-interactive shell `git commit` hangs or
fails with `1Password: failed to fill whole buffer` until the user approves.
Don't use `--no-gpg-sign`: say it's waiting and retry later.
