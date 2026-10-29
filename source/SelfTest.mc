import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Timer;

// Simulator self-test, only in builds made with selftest.jungle. Runs a
// short test on a made-up beat sequence, printing every beat and the
// results, so the FIT file the simulator saves can be checked beat for beat
// with tools/beats.py. Beats arrive the way the sensor delivers them: as
// many per second as fit, so some seconds carry none and some two. A few
// beats in the measurement are dropped, as the wrist sensor does when the
// wrist moves, and those seconds report movement; dropped beats aren't
// numbered, so the printed beat numbers match the FIT file's.
(:selftest)
class SelfTest {

    hidden var _test;
    hidden var _timer;
    hidden var _ticks = 0;
    hidden var _beat = 0;       // beats made up so far, dropped or not
    hidden var _delivered = 0;  // beats handed to the test
    hidden var _budget = 0;     // ms elapsed but not yet used up by beats

    function initialize(test) {
        _test = test;
        _test.settleSeconds = 5;
        _test.measureSeconds = 20;
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
        _budget += 1000;
        var beats = [];
        var dropped = false;
        while (rrFor(_beat + 1) <= _budget) {
            _beat++;
            var rr = rrFor(_beat);
            _budget -= rr;
            if (_beat >= 18 && _beat <= 21) {
                dropped = true;
                System.println("drop " + _beat + " " + rr);
                continue;
            }
            _delivered++;
            beats.add(rr);
            System.println("beat " + _delivered + " " + rr + " phase " + _test.phase);
        }
        _test.addMotion(dropped ? 120 : 8);
        _test.addBeats(beats);
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
