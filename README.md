# Beat Log

An HRV test for the Venu 4 41mm that keeps every beat interval. The watch's
own tools (Health Snapshot, HRV Status) and the store apps tried so far only
save a final number; this saves the beats themselves in the activity's FIT
file, so RMSSD, SDNN or anything else can be worked out later.

## Using it

1. Put the HRM600 on and sit down. Open Beat Log; the screen shows heart rate
   and the latest beat interval, so you can see beats are arriving.
2. Press START. One minute of "Sit still" settles your heart rate, then five
   minutes of recording. The watch vibrates at each change. START skips the
   settling, or ends the recording early. BACK (or swiping right) asks
   whether to discard the test.
3. The results screen shows RMSSD (and its natural log), SDNN, mean HR, and
   how many beats and artifacts were counted. The activity is already saved;
   START begins another test.

While it records, the beats are drawn around the edge of the screen: each
one at its moment in the five minutes, clockwise from 12 o'clock, further
out for a slower beat and further in for a faster one, so breathing shows up
as waves. Artifacts are grey dots. The ring closes when the timer runs out
and stays on the results screen; ending early leaves it open.

The screen's numbers drop beats outside 300–2000 ms or more than 20% away
from the previous good beat. The FIT file keeps every raw beat.

## What's in the FIT file

The activity is a normal one ("HRV", generic sport) with two laps: settling,
then the measurement. Beat Log adds developer fields:

| Message | Field | Meaning |
| --- | --- | --- |
| record | `rr` (16 × ms) | the newest 16 beat intervals, oldest first; unused slots 65535 |
| record | `rr_beat` | the number of the newest beat in `rr` |
| lap | `lap_rr`, `last_beat` | the same pair at the moment the lap closed |
| session | `rmssd`, `sdnn`, `mean_hr`, `beats`, `artifacts` | what the results screen showed |

The watch writes records on its own schedule, so the same beat can appear in
several records and the last second of a lap can miss them all. Numbering
the beats lets a reader place each one exactly once; the laps catch the
tail.

## Reading a file

```
python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt
.venv/bin/python -I tools/beats.py ACTIVITY.fit                # summary
.venv/bin/python -I tools/beats.py ACTIVITY.fit --csv out.csv  # every beat
```

It prints where heart rate came from (strap or wrist), the beat ranges for
each phase, any missing beats, and the measurement's statistics next to what
the watch said.

## Building and installing

```
scripts/build.sh               # bin/beatlog.prg
scripts/install.sh             # copy it to the watch over USB (quit Garmin Express first)
scripts/build.sh selftest      # simulator build that runs a test on made-up beats by itself
```

Activities land in the watch's `Garmin/Activity` folder; copy them off with
`mtp-getfile` as described in `~/src/watch-files`.
