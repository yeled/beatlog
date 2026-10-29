import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;

// Simulator self-test, only in builds made with selftest.jungle. Runs a
// short test on a made-up beat sequence, printing every beat and the
// results, so the FIT file the simulator saves can be checked beat for beat
// with tools/beats.py. Once a second it hands over the beats that ended
// since the second before, as the watch's sensor does, so beats longer
// than a second leave some seconds empty. Four beats in the measurement
// are dropped, as the wrist sensor does when the wrist moves, and the
// seconds meanwhile report movement; then one more is dropped on its own,
// as the sensor also does while still. Dropped beats aren't numbered, so
// the printed beat numbers match the FIT file's.
(:selftest)
class SelfTest {

    hidden var _test;
    hidden var _timer;          // once a second, like the sensor
    hidden var _ticks = 0;
    hidden var _beat = 0;       // beats made up so far, dropped or not
    hidden var _delivered = 0;  // beats handed to the test
    hidden var _nextEnd = null; // System.getTimer() when the next beat ends

    function initialize(test) {
        _test = test;
        _test.settleSeconds = 5;
        _test.measureSeconds = 25;
        _test.synthetic = true;
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        System.println("selftest: waiting");
    }

    function onTick() as Void {
        _ticks++;
        if (_ticks == 2) {
            _test.start();
            System.println("selftest: started");
            _nextEnd = System.getTimer() + rrFor(1);
        }
        if (_test.phase == PHASE_DONE) {
            _timer.stop();
            var s = _test.stats;
            System.println("selftest: done rmssd=" + fmt(s.rmssd()) + " sdnn=" + fmt(s.sdnn())
                + " mean_hr=" + fmt(s.meanHr()) + " beats=" + s.count + " artifacts=" + s.artifacts
                + " gaps=" + _test.gaps + " gap_ms=" + _test.gapMs + " moving_s=" + _test.movingSeconds);
            return;
        }
        if (_test.phase == PHASE_READY) {
            return;
        }
        // The beats that ended in the last second, less the dropped ones
        var now = System.getTimer();
        var batch = [];
        var moving = false;
        while (_nextEnd <= now) {
            _beat++;
            var rr = rrFor(_beat);
            if (_beat >= 18 && _beat <= 21) {
                moving = true;
                System.println("drop " + _beat + " " + rr);
            } else if (_beat == 14 || _beat == 24) {
                System.println("drop " + _beat + " " + rr);
            } else {
                _delivered++;
                batch.add(rr);
                System.println("beat " + _delivered + " " + rr + " phase " + _test.phase);
            }
            _nextEnd += rrFor(_beat + 1);
        }
        if (batch.size() == 0) {
            System.println("empty second");
        }
        _test.addMotion(moving ? 120 : 8);
        _test.addBeats(batch);
    }

    // About 61 bpm with a breathing-like swing, so some beats last over a
    // second, some jitter, and two artifacts: a short beat (missed
    // detection) and a long one.
    hidden function rrFor(n) {
        if (n == 12) {
            return 410;
        }
        if (n == 27) {
            return 1650;
        }
        return 980 + (90 * Math.sin(2 * Math.PI * n / 4.5)).toNumber() + (n * 7919) % 41 - 20;
    }

    hidden function fmt(value) {
        return value != null ? value.format("%.3f") : "null";
    }
}
