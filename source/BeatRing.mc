import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Room for 200 bpm for the whole five minutes.
const RING_POINTS = 1000;
const RING_TRACK = 0x2A2A2A;
const RING_INSET = 18;
const RING_PX_PER_MS = 0.2;
const RING_SWING = 14;

// The measurement drawn around the edge of the screen. Each beat sits at the
// angle of its moment in the measurement, clockwise from 12 o'clock, so the
// ring closes when the timer runs out. Its distance from the track shows its
// interval against the settling minute's average (slower beats further out),
// so breathing shows up as waves. Artifacts are grey dots on the track.
//
// A beat's position is worked out once, when it arrives. The watch, unlike
// the simulator, kills an app whose onUpdate runs too long, and redoing the
// trigonometry for every beat on every update would grow with the test.
class BeatRing {

    var closed = false;     // the measurement ran its full time
    var reference = null;   // ms; set before the first beat, or the first good beat

    hidden var _span;       // the measurement's length in ms
    hidden var _cx;
    hidden var _cy;
    hidden var _base;       // the track's radius
    hidden var _x;
    hidden var _y;
    hidden var _bad;        // 1 for an artifact
    hidden var _n = 0;
    hidden var _elapsed = 0;

    function initialize(span) {
        var settings = System.getDeviceSettings();
        _cx = settings.screenWidth / 2;
        _cy = settings.screenHeight / 2;
        _base = _cx - RING_INSET;
        _span = span;
        _x = new [RING_POINTS];
        _y = new [RING_POINTS];
        _bad = new [RING_POINTS]b;
    }

    function add(rr, good) {
        _elapsed += rr;
        if (_n == RING_POINTS) {
            return;
        }
        var a = 2 * Math.PI * _elapsed / _span;
        if (a > 2 * Math.PI) {
            a = 2 * Math.PI;
        }
        var r = _base;
        if (good) {
            if (reference == null) {
                reference = rr;
            }
            var swing = (rr - reference) * RING_PX_PER_MS;
            if (swing > RING_SWING) {
                swing = RING_SWING;
            } else if (swing < -RING_SWING) {
                swing = -RING_SWING;
            }
            r += swing;
        }
        _x[_n] = _cx + r * Math.sin(a);
        _y[_n] = _cy - r * Math.cos(a);
        _bad[_n] = good ? 0 : 1;
        _n++;
    }

    // head marks the newest beat.
    function draw(dc, head) {
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        dc.setPenWidth(1);
        dc.setColor(RING_TRACK, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, _base);
        if (_n == 0) {
            return;
        }
        dc.setPenWidth(3);
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < _n; i++) {
            if (_bad[i] == 1) {
                dc.setColor(GREY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(_x[i], _y[i], 3);
                dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            } else if (i > 0 && _bad[i - 1] == 0) {
                dc.drawLine(_x[i - 1], _y[i - 1], _x[i], _y[i]);
            }
        }
        var last = _n - 1;
        if (closed && _bad[0] == 0 && _bad[last] == 0) {
            dc.drawLine(_x[last], _y[last], _x[0], _y[0]);
        }
        if (head && _bad[last] == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_x[last], _y[last], 5);
        }
    }
}
