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
5 s + 25 s test by itself, feeds a fixed beat sequence through
`BeatTest.addBeats` (the path real sensor data takes), and prints every beat
and the final statistics. Like the watch's sensor, it hands over once a
second the beats that ended since the second before; at about 61 bpm some
seconds are empty, and the 1650 ms artifact makes another. It drops beat 14
on its own, beats 18–21 while reporting 120 mg of movement, and beat 24 on
its own just after. The run should show a gap of about 1 s after beat 13,
about 4 s after beat 16 and 4 s of movement, and no gap for beat 24 (the
timing hasn't narrowed again that soon after a gap), the same on the
watch's side and in `tools/beats.py`, whose time check should come out
about 1 s short (beat 24).
Verify a change by running it and checking that
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
- The self-test's 25 s ring has only ~20 beats. To see a full ring,
  temporarily set `measureSeconds` to 300 in `SelfTest.initialize` (a
  five-minute run).
- The breathing wave lives in a bitmap drawn as beats arrive, not in
  `onUpdate`, so a self-test run exercises it even with the screen locked;
  only its look needs a screenshot.

## Store

The Connect IQ store listing is **"Beat Log beta"**, a beta app (visible
only to the developer account):
https://apps.garmin.com/apps/590aeb1e-d384-4fd2-8d26-e832340c855e. Its id is
the manifest's, so a future public listing needs a new app id (see
analog-simple's `scripts/set-manifest.sh`). Images are in
`screenshots/store/` (500×500, under the store's 150 KB limit).

To release: bump `AppVersion` in `resources/strings/strings.xml`, commit,
`scripts/build.sh iq`, then upload with analog-simple's dashboard tool (its
signed-in Chrome session lives in `~/.config/analog-simple/`):

```sh
cd ~/src/analog-simple/scripts/store-upload
node upload.mjs upload --name "Beat Log beta" --iq ~/src/beatlog/bin/beatlog-<version>.iq \
  --version <version> --notes "What's new" --dry-run   # drop --dry-run to publish
```

The tool's after-submit page doesn't prove the version landed; a second
`--dry-run` shows "Latest app version" on step 1. Tag `v<version>-beta`.

## Open questions

- The gap rule (0.2.4) replaced 0.2.3's "half a beat short", which counted
  every empty second as a gap: at 59 bpm (the 2026-10-29 20:43 test) that
  was 44 gaps and 77.8 s where the time leaves room for about 62.5 s.
  Replayed offline on that test and the 16:38 one, the new rule found
  every long gap on the same beat and came within a second of the time.
  Watch `tools/beats.py`'s time check on real tests: well over a beat
  either way means the rule (or `GAP_JITTER`) needs another look.
- `MOVE_LIMIT` (50 mg) holds: still, the wrist reads 13–24 mg; moving,
  84–786 mg. But most gaps come without movement: nine of the 0.2.1 test's
  eleven (45 s, 15% of the measurement) had none.

- The wrist sensor's beat intervals arrive on the Venu 4 (confirmed with
  0.1.1, once the onboard sensor was enabled). Still open: whether
  `heartBeatIntervals` carries the HRM600's intervals when the strap is
  connected. `tools/beats.py` reports which heart
  rate sources the FIT file lists; check the first real test.
- Whether the Venu 4 writes a record every second for this app. If
  `tools/beats.py` reports missing beats, raise `WINDOW`.

## Commits

Signed through 1Password; in a non-interactive shell `git commit` hangs or
fails with `1Password: failed to fill whole buffer` until the user approves.
Don't use `--no-gpg-sign`: say it's waiting and retry later.
