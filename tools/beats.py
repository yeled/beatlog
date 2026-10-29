"""Pull every heartbeat interval out of a Beat Log FIT file.

Each record carries the newest 16 intervals ("rr") and the number of the
newest beat ("rr_beat"), so beats are placed by number: a beat repeated in
several records lands once, and a skipped record costs nothing unless more
than 16 beats went by. Each lap carries the same pair ("lap_rr",
"last_beat"), which saves the last second's beats and splits settling from
the measurement.

The wrist sensor drops beats it can't place, as when the wrist moves. The
watch notices the time they leave unaccounted for and records it: "gap_ms"
is the running total and "gap_beat" the last beat before the latest gap.
"motion" is the wrist's movement over each second, in milli-g.

    .venv/bin/python -I tools/beats.py ACTIVITY.fit                 # summary
    .venv/bin/python -I tools/beats.py ACTIVITY.fit --csv out.csv   # every beat
"""
import argparse
import csv
import math
import statistics
import sys

from garmin_fit_sdk import Decoder, Stream

RR_INVALID = 0xFFFF
MOVE_LIMIT = 50  # mg, as in source/BeatTest.mc


def developer_keys(messages, wanted):
    """Map our field names to their developer field keys. Fields are found
    by name within one developer data index, because the simulator writes
    an all-zero application id."""
    by_index = {}
    for fd in messages.get("field_description_mesgs", []):
        by_index.setdefault(fd["developer_data_index"], {})[fd["field_name"]] = fd["key"]
    for fields in by_index.values():
        if wanted <= fields.keys():
            return fields
    return None


def collect_beats(messages, keys):
    windows = [(m.get("developer_fields", {}), "rr", "rr_beat") for m in messages.get("record_mesgs", [])]
    windows += [(m.get("developer_fields", {}), "lap_rr", "last_beat") for m in messages.get("lap_mesgs", [])]
    beats, conflicts = {}, 0
    for dev, rr_name, beat_name in windows:
        window, newest = dev.get(keys.get(rr_name)), dev.get(keys[beat_name])
        if not window or not newest:
            continue
        if not isinstance(window, list):
            window = [window]
        for back, rr in enumerate(reversed(window)):
            n = newest - back
            if n < 1 or rr is None or rr == RR_INVALID:
                continue
            if beats.setdefault(n, rr) != rr:
                conflicts += 1
    return beats, conflicts


def collect_gaps(messages, keys):
    """The watch's gaps as {last beat before the gap: (ms, record timestamp)},
    from the steps in the running gap_ms total. Files from before 0.2.0 have
    no gap fields."""
    if "gap_ms" not in keys:
        return {}
    gaps, total = {}, 0
    for r in messages.get("record_mesgs", []):
        dev = r.get("developer_fields", {})
        running = dev.get(keys["gap_ms"])
        if running is not None and running > total:
            gaps[dev.get(keys["gap_beat"])] = (running - total, r.get("timestamp"))
            total = running
    return gaps


class RrStats:
    """The watch's filter (source/RrStats.mc), so the numbers can be compared."""

    def __init__(self):
        self.count = self.artifacts = 0
        self.rrs, self.diffs = [], []
        self.last, self.chained, self.outlier_run = None, False, 0

    def add(self, rr):
        if rr is None:  # missing from the file: break the chain, not an artifact
            self.chained = False
            return
        if not 300 <= rr <= 2000:
            return self.reject()
        if self.last is not None and abs(rr - self.last) > self.last * 0.2 and self.outlier_run < 2:
            self.outlier_run += 1
            return self.reject()
        self.outlier_run = 0
        if self.chained:
            self.diffs.append(rr - self.last)
        self.count += 1
        self.rrs.append(rr)
        self.last, self.chained = rr, True

    def gap(self):
        self.chained = False
        self.last, self.outlier_run = None, 0

    def reject(self):
        self.artifacts += 1
        self.chained = False

    def rmssd(self):
        return math.sqrt(sum(d * d for d in self.diffs) / len(self.diffs)) if len(self.diffs) > 1 else None

    def sdnn(self):
        n = len(self.rrs)
        if n < 2:
            return None
        mean = sum(self.rrs) / n
        return math.sqrt(sum((r - mean) ** 2 for r in self.rrs) / (n - 1))

    def mean_hr(self):
        return 60000 / (sum(self.rrs) / len(self.rrs)) if self.rrs else None


def fmt(value, places=1):
    return "--" if value is None or (isinstance(value, float) and math.isnan(value)) else f"{value:.{places}f}"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("path")
    parser.add_argument("--csv", help="write beat, phase, t_s, rr_ms, gap_before_ms, motion_mg to this file")
    args = parser.parse_args()

    messages, errors = Decoder(Stream.from_file(args.path)).read()
    for error in errors:
        print("error:", error, file=sys.stderr)
    keys = developer_keys(messages, {"rr", "rr_beat", "last_beat"})
    if keys is None:
        sys.exit("no Beat Log fields in this file")

    beats, conflicts = collect_beats(messages, keys)
    gaps = collect_gaps(messages, keys)
    laps = [lap.get("developer_fields", {}).get(keys["last_beat"]) for lap in messages.get("lap_mesgs", [])]
    last = max([*beats, *(n for n in laps if n)], default=0)
    missing = [n for n in range(1, last + 1) if n not in beats]
    settle_end = laps[0] if len(laps) > 1 and laps[0] is not None else 0

    session = messages["session_mesgs"][0]
    start = session.get("start_time")
    elapsed = session.get("total_elapsed_time")
    external = [d for d in messages.get("device_info_mesgs", []) if d.get("source_type") not in (None, "local")]
    sources = sorted({f"{d.get('source_type')} {d.get('product_name') or d.get('manufacturer') or ''}".strip() for d in external})

    print(f"{args.path}")
    print(f"  started {start}, {fmt(elapsed, 0)} s, "
          f"heart rate from {', '.join(sources) if sources else 'the wrist sensor only'}")
    print(f"  beats 1-{last} in the file: settling 1-{settle_end}, measurement {settle_end + 1}-{last}; "
          f"missing {len(missing)}, conflicting {conflicts}")
    if missing:
        print(f"  missing beat numbers: {missing[:20]}{' ...' if len(missing) > 20 else ''}")
    covered = sum(beats.values()) / 1000
    print(f"  the beats cover {covered:.1f} s of the {fmt(elapsed, 0)} s recording")

    # Movement per record, and when each beat arrived, to line the two up
    records = messages.get("record_mesgs", [])
    motion_key, beat_key = keys.get("motion"), keys["rr_beat"]
    motion = [(r.get("timestamp"), r.get("developer_fields", {}).get(motion_key)) for r in records] if motion_key else []
    arrived = {}
    for r in records:
        dev = r.get("developer_fields", {})
        newest = dev.get(beat_key)
        if newest:
            for n in range(1, newest + 1):
                arrived.setdefault(n, (r.get("timestamp"), dev.get(motion_key) if motion_key else None))

    if gaps:
        measured = sum(ms for beat, (ms, _) in gaps.items() if beat >= settle_end)
        print(f"  sensor gaps: {len(gaps)}, {sum(ms for ms, _ in gaps.values()) / 1000:.1f} s "
              f"({measured / 1000:.1f} s in the measurement)")
        for beat, (ms, when) in sorted(gaps.items()):
            t = (when - start).total_seconds() if when and start else None
            near = [m for ts, m in motion if m is not None and ts and when
                    and -ms / 1000 - 2 <= (ts - when).total_seconds() <= 0]
            print(f"    after beat {beat}, {ms / 1000:.1f} s, noticed at {fmt(t, 0)} s; "
                  f"movement then up to {max(near) if near else '--'} mg")
    if motion:
        start_measure = messages["lap_mesgs"][1]["start_time"] if len(messages.get("lap_mesgs", [])) > 1 else start
        during = [m for ts, m in motion if m is not None and ts and ts >= start_measure]
        if during:
            print(f"  movement in the measurement: median {statistics.median(during):.0f} mg, "
                  f"max {max(during)} mg, over {MOVE_LIMIT} mg in {sum(m > MOVE_LIMIT for m in during)} records")

    stats = RrStats()
    for n in range(settle_end + 1, last + 1):
        if n - 1 in gaps and n - 1 >= settle_end:
            stats.gap()
        stats.add(beats.get(n))
    dev = session.get("developer_fields", {})
    print(f"  measurement: RMSSD {fmt(stats.rmssd(), 3)}  SDNN {fmt(stats.sdnn(), 3)}  "
          f"mean HR {fmt(stats.mean_hr(), 3)}  beats {stats.count}  artifacts {stats.artifacts}")
    print(f"  watch said:  RMSSD {fmt(dev.get(keys.get('rmssd')), 3)}  SDNN {fmt(dev.get(keys.get('sdnn')), 3)}  "
          f"mean HR {fmt(dev.get(keys.get('mean_hr')), 3)}  beats {dev.get(keys.get('beats'))}  "
          f"artifacts {dev.get(keys.get('artifacts'))}"
          + (f"  gaps {dev.get(keys['gaps'])} ({fmt(dev.get(keys['gap_s']))} s)  moving {dev.get(keys['moving_s'])} s"
             if "gaps" in keys else ""))

    if args.csv:
        with open(args.csv, "w", newline="") as f:
            out = csv.writer(f)
            out.writerow(["beat", "phase", "t_s", "rr_ms", "gap_before_ms", "motion_mg"])
            t = 0
            for n in range(1, last + 1):
                rr = beats.get(n)
                gap = gaps.get(n - 1, (0, None))[0]
                t += gap + (rr or 0)
                phase = "settle" if n <= settle_end else "measure"
                moved = arrived.get(n, (None, None))[1]
                out.writerow([n, phase, f"{t / 1000:.3f}", "" if rr is None else rr, gap or "",
                              "" if moved is None else moved])
        print(f"  wrote {args.csv}")


if __name__ == "__main__":
    main()
