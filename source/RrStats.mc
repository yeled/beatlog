import Toybox.Lang;
import Toybox.Math;

// Running beat-interval statistics. A beat outside 300-2000 ms, or more than
// 20% away from the last good beat, counts as an artifact and breaks the run
// of successive differences, so one missed or doubled beat doesn't swamp
// RMSSD. The FIT file keeps every raw beat; this is only what the watch shows.
class RrStats {

    var count = 0;
    var artifacts = 0;

    hidden var _mean = 0.0;      // Welford: 32-bit floats can't afford sum-of-squares
    hidden var _m2 = 0.0;
    hidden var _diffSqSum = 0.0;
    hidden var _diffs = 0;
    hidden var _last = null;     // last good beat
    hidden var _chained = false; // was the previous beat good?
    hidden var _outlierRun = 0;

    function initialize() {
    }

    function add(rr) {
        if (rr < 300 || rr > 2000) {
            reject();
            return;
        }
        if (_last != null) {
            var jump = rr - _last;
            if (jump < 0) {
                jump = -jump;
            }
            // Three outliers in a row means the rhythm itself moved, or the
            // reference beat was the bad one, so start again from this beat.
            if (jump > _last * 0.2 && _outlierRun < 2) {
                _outlierRun++;
                reject();
                return;
            }
        }
        _outlierRun = 0;
        if (_chained) {
            var d = rr - _last;
            _diffSqSum += d * d;
            _diffs++;
        }
        count++;
        var delta = rr - _mean;
        _mean += delta / count;
        _m2 += delta * (rr - _mean);
        _last = rr;
        _chained = true;
    }

    hidden function reject() {
        artifacts++;
        _chained = false;
    }

    function rmssd() {
        return _diffs > 1 ? Math.sqrt(_diffSqSum / _diffs) : null;
    }

    function sdnn() {
        return count > 1 ? Math.sqrt(_m2 / (count - 1)) : null;
    }

    function meanHr() {
        return count > 0 ? 60000.0 / _mean : null;
    }
}
