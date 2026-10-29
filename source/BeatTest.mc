import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

// Sitting still before the measurement, then the measurement itself.
const SETTLE_SECONDS = 60;
const MEASURE_SECONDS = 300;

const PHASE_READY = 0;
const PHASE_SETTLING = 1;
const PHASE_MEASURING = 2;
const PHASE_DONE = 3;

// Every FIT record carries the newest WINDOW beat intervals plus the number
// of the newest beat. The watch writes records on its own schedule, so a
// beat can appear in several records and a record can be skipped; the
// numbering lets a reader place each beat exactly once. 16 beats cover at
// least 4.8 s even at 200 bpm. Laps carry the window too, because beats
// from the last second before a lap closes may miss every record. Gaps are
// recorded the same way: each record carries the total time of the beats
// the sensor dropped so far, and the number of the last beat before the
// latest gap. Each record also carries the running total of every batch's
// shortfall, gap or not, so a reader can check the gap rule.
const WINDOW = 16;
const RR_INVALID = 0xFFFF;

// The wrist sensor drops beats it can't place, as when the wrist moves:
// they are simply missing, not merged into a long interval. The sensor
// hands over, once a second, the beats that ended since the last time, so
// a beat longer than a second can leave a second with none: a batch can
// fall a whole beat short with nothing dropped. Instead the watch keeps
// track of when the newest beat could have ended: after the previous
// callback and by this one, give or take GAP_JITTER ms. Each batch's beats
// carry that window forward; a gap is when they can't reach this second
// however the window falls.
const GAP_JITTER = 200;

// Movement in milli-g: the accelerometer's spread over each second. Holding
// still leaves only gravity, which doesn't spread. In the first watch test
// the wrist read 13-24 mg held still and 84 mg or more when moving.
const MOVE_LIMIT = 50;
const MOVE_HOLD = 3000;   // ms "Hold still" stays up after moving
const ACCEL_RATE = 25;    // Hz

// FIT developer field ids. Never renumber: old files keep the old meaning.
const FIELD_RR = 0;
const FIELD_RR_BEAT = 1;
const FIELD_LAST_BEAT = 2;
const FIELD_RMSSD = 3;
const FIELD_SDNN = 4;
const FIELD_MEAN_HR = 5;
const FIELD_BEATS = 6;
const FIELD_ARTIFACTS = 7;
const FIELD_LAP_RR = 8;
const FIELD_MOTION = 9;
const FIELD_GAP_BEAT = 10;
const FIELD_GAP_MS = 11;
const FIELD_GAPS = 12;
const FIELD_GAP_SECONDS = 13;
const FIELD_MOVING_SECONDS = 14;
const FIELD_SHORT_MS = 15;

// One HRV test: a settling lap, a measurement lap, and the beat intervals
// from both written into the activity's FIT file.
class BeatTest {

    var phase = PHASE_READY;
    var settleSeconds = SETTLE_SECONDS;
    var measureSeconds = MEASURE_SECONDS;
    var synthetic = false;  // the self-test feeds beats; ignore the sensor's
    var heartRate = null;   // from the once-a-second sensor events
    var lastRr = null;      // newest beat interval, recording or not
    var motion = 0;         // mg, over the latest second
    var stats = null;       // measurement lap only
    var ring = null;        // measurement lap only
    var gaps = 0;           // measurement lap only: times the sensor dropped beats,
    var gapMs = 0;          //   and the time those beats would have covered
    var movingSeconds = 0;  // measurement lap only

    hidden var _session = null;
    hidden var _timer = null;
    hidden var _phaseStart = 0;
    hidden var _window = null;
    hidden var _beat = 0;   // beats since the recording started
    hidden var _lastBatchAt = null;  // System.getTimer() of the last batch with beats
    hidden var _lastCallAt = null;   // ... and of the last callback, with beats or not
    hidden var _endLo = null;        // when the newest beat could have ended, as
    hidden var _endHi = null;        //   System.getTimer() ms
    hidden var _gapTotal = 0;        // ms missing over the whole recording
    hidden var _shortTotal = 0;      // ms: every batch's shortfall, added up
    hidden var _movedAt = null;

    hidden var _rrField = null;
    hidden var _rrBeatField = null;
    hidden var _lastBeatField = null;
    hidden var _lapRrField = null;
    hidden var _rmssdField = null;
    hidden var _sdnnField = null;
    hidden var _meanHrField = null;
    hidden var _beatsField = null;
    hidden var _artifactsField = null;
    hidden var _motionField = null;
    hidden var _gapBeatField = null;
    hidden var _gapMsField = null;
    hidden var _gapsField = null;
    hidden var _gapSecondsField = null;
    hidden var _movingField = null;
    hidden var _shortField = null;

    function initialize() {
        stats = new RrStats();
        ring = new BeatRing(measureSeconds * 1000);
    }

    // Both heart rate sources: the watch's own sensor and a paired strap.
    // Beat intervals then come from whichever one the watch is using.
    // SENSOR_HEARTRATE alone means a strap, and setEnabledSensors turns off
    // every type it isn't given, so on the watch that left the wrist sensor
    // dark. enableSensorType leaves the other types alone.
    function startSensors() {
        if (Sensor has :enableSensorType) {
            Sensor.enableSensorType(Sensor.SENSOR_ONBOARD_HEARTRATE);
            Sensor.enableSensorType(Sensor.SENSOR_HEARTRATE);
        } else {
            Sensor.setEnabledSensors([ Sensor.SENSOR_HEARTRATE ]);
        }
        Sensor.enableSensorEvents(method(:onSensor));
        var rate = Sensor.getMaxSampleRate();
        try {
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :accelerometer => { :enabled => true, :sampleRate => rate < ACCEL_RATE ? rate : ACCEL_RATE },
                :heartBeatIntervals => { :enabled => true }
            });
        } catch (e) {
            // Beats matter more than movement
            Sensor.registerSensorDataListener(method(:onSensorData), {
                :period => 1,
                :heartBeatIntervals => { :enabled => true }
            });
        }
    }

    function stopSensors() {
        Sensor.unregisterSensorDataListener();
        Sensor.enableSensorEvents(null);
    }

    function onSensor(info as Sensor.Info) as Void {
        heartRate = info.heartRate;
        WatchUi.requestUpdate();
    }

    function onSensorData(data as Sensor.SensorData) as Void {
        if (synthetic) {
            return;
        }
        var accel = data.accelerometerData;
        if (accel != null) {
            addMotion(spread(accel.x, accel.y, accel.z));
        }
        // An empty second counts too: it narrows when the next beat ended
        var hr = data.heartRateData;
        addBeats(hr != null && hr.heartBeatIntervals != null ? hr.heartBeatIntervals : []);
    }

    // One second's movement in mg. The self-test calls this directly.
    function addMotion(mg) {
        motion = mg;
        if (mg > MOVE_LIMIT) {
            _movedAt = System.getTimer();
            if (phase == PHASE_MEASURING) {
                movingSeconds++;
            }
        }
        if (_session != null) {
            _motionField.setData(mg < RR_INVALID ? mg : RR_INVALID - 1);
        }
    }

    // True for a few seconds after moving too much.
    function moving() {
        return _movedAt != null && System.getTimer() - _movedAt < MOVE_HOLD;
    }

    // One callback's beats, possibly none. The self-test calls this directly.
    function addBeats(intervals) {
        var now = System.getTimer();
        if (intervals.size() > 0) {
            checkForGap(intervals, now);
        }
        _lastCallAt = now;
        var moved = motion > MOVE_LIMIT;
        for (var i = 0; i < intervals.size(); i++) {
            addBeat(intervals[i], moved);
        }
        if (_session != null && intervals.size() > 0) {
            _rrField.setData(_window);
            _rrBeatField.setData(_beat);
        }
        WatchUi.requestUpdate();
    }

    hidden function checkForGap(intervals, now) {
        var covered = 0;
        for (var i = 0; i < intervals.size(); i++) {
            covered += intervals[i];
        }
        if (_lastBatchAt != null && _session != null) {
            _shortTotal += now - _lastBatchAt - covered;
            _shortField.setData(_shortTotal);
        }
        _lastBatchAt = now;

        // The newest beat ended after the previous callback, or it would
        // have come then, and by now
        var after = _lastCallAt != null ? _lastCallAt : now - 1000;
        if (_endHi == null) {
            _endLo = after;
            _endHi = now;
            return;
        }
        var lo = _endLo + covered;
        var hi = _endHi + covered;
        if (hi < after - GAP_JITTER) {
            // Even ending as late as they could, the beats fall short
            gap((after + now) / 2 - (lo + hi) / 2);
            _endLo = after;
            _endHi = now;
        } else if (lo > now + GAP_JITTER) {
            // They run past the clock: the window was off, so start afresh
            _endLo = after;
            _endHi = now;
        } else {
            _endLo = lo > after - GAP_JITTER ? lo : after - GAP_JITTER;
            _endHi = hi < now + GAP_JITTER ? hi : now + GAP_JITTER;
        }
    }

    // The sensor dropped ms worth of beats before the batch now arriving.
    hidden function gap(ms) {
        if (_session == null) {
            return;
        }
        _gapTotal += ms;
        _gapBeatField.setData(_beat);
        _gapMsField.setData(_gapTotal);
        if (phase == PHASE_MEASURING) {
            gaps++;
            gapMs += ms;
            stats.gap();
            ring.gap(ms);
        }
    }

    hidden function addBeat(rr, moved) {
        lastRr = rr;
        if (_session == null) {
            return;
        }
        _beat++;
        for (var i = 0; i < WINDOW - 1; i++) {
            _window[i] = _window[i + 1];
        }
        _window[WINDOW - 1] = rr < RR_INVALID ? rr : RR_INVALID - 1;
        if (phase == PHASE_MEASURING) {
            ring.add(rr, stats.add(rr), moved);
        } else if (rr >= 300 && rr <= 2000) {
            ring.settle(rr);
        }
    }

    function start() {
        if (!(Toybox has :ActivityRecording) || _session != null) {
            return;
        }
        _session = ActivityRecording.createSession({
            :name => "HRV",
            :sport => Activity.SPORT_GENERIC
        });
        _rrField = _session.createField("rr", FIELD_RR, FitContributor.DATA_TYPE_UINT16,
            { :count => WINDOW, :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms" });
        _rrBeatField = _session.createField("rr_beat", FIELD_RR_BEAT, FitContributor.DATA_TYPE_UINT32,
            { :mesgType => FitContributor.MESG_TYPE_RECORD });
        _motionField = _session.createField("motion", FIELD_MOTION, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mg" });
        _gapBeatField = _session.createField("gap_beat", FIELD_GAP_BEAT, FitContributor.DATA_TYPE_UINT32,
            { :mesgType => FitContributor.MESG_TYPE_RECORD });
        _gapMsField = _session.createField("gap_ms", FIELD_GAP_MS, FitContributor.DATA_TYPE_UINT32,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms" });
        _shortField = _session.createField("short_ms", FIELD_SHORT_MS, FitContributor.DATA_TYPE_SINT32,
            { :mesgType => FitContributor.MESG_TYPE_RECORD, :units => "ms" });
        _lastBeatField = _session.createField("last_beat", FIELD_LAST_BEAT, FitContributor.DATA_TYPE_UINT32,
            { :mesgType => FitContributor.MESG_TYPE_LAP });
        _lapRrField = _session.createField("lap_rr", FIELD_LAP_RR, FitContributor.DATA_TYPE_UINT16,
            { :count => WINDOW, :mesgType => FitContributor.MESG_TYPE_LAP, :units => "ms" });
        _rmssdField = _session.createField("rmssd", FIELD_RMSSD, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "ms" });
        _sdnnField = _session.createField("sdnn", FIELD_SDNN, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "ms" });
        _meanHrField = _session.createField("mean_hr", FIELD_MEAN_HR, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm" });
        _beatsField = _session.createField("beats", FIELD_BEATS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION });
        _artifactsField = _session.createField("artifacts", FIELD_ARTIFACTS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION });
        _gapsField = _session.createField("gaps", FIELD_GAPS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION });
        _gapSecondsField = _session.createField("gap_s", FIELD_GAP_SECONDS, FitContributor.DATA_TYPE_FLOAT,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s" });
        _movingField = _session.createField("moving_s", FIELD_MOVING_SECONDS, FitContributor.DATA_TYPE_UINT16,
            { :mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s" });

        _window = new [WINDOW];
        for (var i = 0; i < WINDOW; i++) {
            _window[i] = RR_INVALID;
        }
        _beat = 0;
        stats = new RrStats();
        ring = new BeatRing(measureSeconds * 1000);
        _gapTotal = 0;
        _shortTotal = 0;
        gaps = 0;
        gapMs = 0;
        movingSeconds = 0;
        _rrField.setData(_window);
        _rrBeatField.setData(0);
        _motionField.setData(0);
        _gapBeatField.setData(0);
        _gapMsField.setData(0);
        _shortField.setData(0);

        _session.start();
        enterPhase(PHASE_SETTLING);
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onTick() as Void {
        if (remaining() == 0) {
            if (phase == PHASE_SETTLING) {
                beginMeasuring();
            } else if (phase == PHASE_MEASURING) {
                finish();
            }
        }
        WatchUi.requestUpdate();
    }

    // Seconds left in the settling or measuring phase.
    function remaining() {
        var length = phase == PHASE_SETTLING ? settleSeconds : measureSeconds;
        var left = length - (System.getTimer() - _phaseStart) / 1000;
        return left > 0 ? left : 0;
    }

    // Closes the settling lap; the measurement is the second lap.
    function beginMeasuring() {
        if (phase != PHASE_SETTLING) {
            return;
        }
        setLapFields();
        _session.addLap();
        enterPhase(PHASE_MEASURING);
        vibrate();
    }

    function finish() {
        if (_session == null) {
            return;
        }
        ring.closed = remaining() == 0;
        stopTimer();
        setLapFields();
        setIfKnown(_rmssdField, stats.rmssd());
        setIfKnown(_sdnnField, stats.sdnn());
        setIfKnown(_meanHrField, stats.meanHr());
        _beatsField.setData(stats.count);
        _artifactsField.setData(stats.artifacts);
        _gapsField.setData(gaps);
        _gapSecondsField.setData(gapMs / 1000.0);
        _movingField.setData(movingSeconds);
        _session.stop();
        _session.save();
        _session = null;
        enterPhase(PHASE_DONE);
        vibrate();
    }

    function discard() {
        if (_session == null) {
            return;
        }
        stopTimer();
        _session.stop();
        _session.discard();
        _session = null;
        phase = PHASE_READY;
    }

    // From the results screen back to ready for another test.
    function reset() {
        phase = PHASE_READY;
    }

    hidden function enterPhase(p) {
        phase = p;
        _phaseStart = System.getTimer();
    }

    hidden function stopTimer() {
        if (_timer != null) {
            _timer.stop();
            _timer = null;
        }
    }

    // Each lap records the number of its last beat, so a reader can split
    // the beats by phase, and the newest beats, so none are lost at the end.
    hidden function setLapFields() {
        _lastBeatField.setData(_beat);
        _lapRrField.setData(_window);
    }

    hidden function setIfKnown(field, value) {
        if (value != null) {
            field.setData(value);
        }
    }

    // The spread (standard deviation) of the acceleration vector around its
    // mean over one batch of samples, in mg.
    hidden function spread(x, y, z) {
        if (x == null || y == null || z == null || x.size() < 2) {
            return 0;
        }
        return Math.sqrt(variance(x) + variance(y) + variance(z)).toNumber();
    }

    hidden function variance(a) {
        var n = a.size();
        var sum = 0.0;
        for (var i = 0; i < n; i++) {
            sum += a[i];
        }
        var mean = sum / n;
        var sq = 0.0;
        for (var i = 0; i < n; i++) {
            var d = a[i] - mean;
            sq += d * d;
        }
        return sq / n;
    }

    hidden function vibrate() {
        if (Attention has :vibrate) {
            Attention.vibrate([ new Attention.VibeProfile(75, 400) ]);
        }
    }
}
