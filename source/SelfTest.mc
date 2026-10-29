import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;

// Simulator self-test, only in builds made with selftest.jungle. Runs a
// short test on a made-up beat sequence, printing every beat and the
// results, so the FIT file the simulator saves can be checked beat for beat
// with tools/beats.py. Each beat arrives as it ends, which is how the
// watch's sensor behaves: its batches account for the time since the
// previous one to within a few hundred ms. Four beats in the measurement
// are dropped, as the wrist sensor does when the wrist moves, and the
// seconds meanwhile report movement; then one more is dropped on its own,
// as the sensor also does while still. Dropped beats aren't numbered, so
// the printed beat numbers match the FIT file's.
(:selftest)
class SelfTest {

    hidden var _test;
    hidden var _timer;          // once a second: start, movement, done
    hidden var _beatTimer;      // once a beat
    hidden var _ticks = 0;
    hidden var _beat = 0;       // beats made up so far, dropped or not
    hidden var _delivered = 0;  // beats handed to the test
    hidden var _moving = false;

    function initialize(test) {
        _test = test;
        _test.settleSeconds = 5;
        _test.measureSeconds = 20;
        _test.synthetic = true;
        _timer = new Timer.Timer();
        _beatTimer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
        System.println("selftest: waiting");
    }

    function onTick() as Void {
        _ticks++;
        if (_ticks == 2) {
            _test.start();
            System.println("selftest: started");
            _beatTimer.start(method(:onBeat), rrFor(1), false);
        }
        if (_test.phase == PHASE_DONE) {
            _timer.stop();
            _beatTimer.stop();
            var s = _test.stats;
            System.println("selftest: done rmssd=" + fmt(s.rmssd()) + " sdnn=" + fmt(s.sdnn())
                + " mean_hr=" + fmt(s.meanHr()) + " beats=" + s.count + " artifacts=" + s.artifacts
                + " gaps=" + _test.gaps + " gap_ms=" + _test.gapMs + " moving_s=" + _test.movingSeconds);
            return;
        }
        if (_test.phase != PHASE_READY) {
            _test.addMotion(_moving ? 120 : 8);
        }
    }

    // The beat now ending: hand it over, or drop it, then wait for the next.
    function onBeat() as Void {
        if (_test.phase == PHASE_DONE) {
            return;
        }
        _beat++;
        var rr = rrFor(_beat);
        _moving = _beat >= 18 && _beat <= 21;
        if (_moving || _beat == 24) {
            System.println("drop " + _beat + " " + rr);
        } else {
            _delivered++;
            System.println("beat " + _delivered + " " + rr + " phase " + _test.phase);
            _test.addBeats([ rr ]);
        }
        _beatTimer.start(method(:onBeat), rrFor(_beat + 1), false);
    }

    // About 75 bpm with a breathing-like swing, some jitter, and two
    // artifacts: a short beat (missed detection) and a long one.
    hidden function rrFor(n) {
        if (n == 12) {
            return 410;
        }
        if (n == 27) {
            return 1650;
        }
        return 800 + (45 * Math.sin(2 * Math.PI * n / 4.5)).toNumber() + (n * 7919) % 41 - 20;
    }

    hidden function fmt(value) {
        return value != null ? value.format("%.3f") : "null";
    }
}
