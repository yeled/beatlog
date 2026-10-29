import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

// Room for 200 bpm for the whole five minutes.
const RING_POINTS = 1000;
const RING_TRACK = 0x2A2A2A;
const RING_PX_PER_MS = 0.2;
const RING_SWING = 14;

// The measurement drawn around the edge of the screen. Each beat sits at the
// angle of its moment in the measurement, clockwise from 12 o'clock, so the
// ring closes when the timer runs out. Its distance from the track shows its
// interval against the average (slower beats further out), so breathing
// shows up as waves. Artifacts are grey dots on the track.
class BeatRing {

    var closed = false;  // the measurement ran its full time

    hidden var _rr;      // interval per beat, negative for an artifact
    hidden var _at;      // ms from the start of the measurement to the beat
    hidden var _n = 0;
    hidden var _elapsed = 0;
    hidden var _goodSum = 0;
    hidden var _good = 0;

    function initialize() {
        _rr = new [RING_POINTS];
        _at = new [RING_POINTS];
    }

    function add(rr, good) {
        _elapsed += rr;
        if (_n == RING_POINTS) {
            return;
        }
        _rr[_n] = good ? rr : -rr;
        _at[_n] = _elapsed;
        _n++;
        if (good) {
            _goodSum += rr;
            _good++;
        }
    }

    // span is the measurement's length in ms; head marks the newest beat.
    function draw(dc, span, head) {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var base = cx - 18;
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setPenWidth(1);
        dc.setColor(RING_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, base);
        if (_n == 0) {
            return;
        }
        // A full measurement closes exactly, whatever the beats added up to
        if (closed) {
            span = _elapsed;
        }
        var mean = _good > 0 ? _goodSum.toFloat() / _good : 0.0;
        var firstX = null;
        var firstY = null;
        var lastX = null;
        var lastY = null;
        var x = 0.0;
        var y = 0.0;
        dc.setPenWidth(3);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < _n; i++) {
            var a = 2 * Math.PI * _at[i] / span;
            if (a > 2 * Math.PI) {
                a = 2 * Math.PI;
            }
            var rr = _rr[i];
            if (rr < 0) {
                dc.setColor(GREY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(cx + base * Math.sin(a), cy - base * Math.cos(a), 3);
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
                lastX = null;
                continue;
            }
            var swing = (rr - mean) * RING_PX_PER_MS;
            if (swing > RING_SWING) {
                swing = RING_SWING;
            } else if (swing < -RING_SWING) {
                swing = -RING_SWING;
            }
            x = cx + (base + swing) * Math.sin(a);
            y = cy - (base + swing) * Math.cos(a);
            if (i == 0) {
                firstX = x;
                firstY = y;
            }
            if (lastX != null) {
                dc.drawLine(lastX, lastY, x, y);
            }
            lastX = x;
            lastY = y;
        }
        if (closed && lastX != null && firstX != null) {
            dc.drawLine(lastX, lastY, firstX, firstY);
        }
        if (head && lastX != null) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(lastX, lastY, 5);
        }
    }
}
