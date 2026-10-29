import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

// Room for 200 bpm for the whole five minutes.
const RING_POINTS = 1000;
const RING_TRACK = 0x2A2A2A;
const RING_INSET = 18;
const RING_PX_PER_MS = 0.1;  // so +-140 ms fits in RING_SWING px
const RING_SWING = 14;
const RING_AVG = 30;         // beats in the average a beat is drawn against

// What each point is, as bits.
const RING_ARTIFACT = 1;
const RING_BREAK = 2;    // the sensor dropped beats just before this one
const RING_MOVING = 4;   // the wrist was moving

// The measurement drawn around the edge of the screen. Each beat sits at the
// angle of its moment in the measurement, clockwise from 12 o'clock, so the
// ring closes when the timer runs out. Its distance from the track shows its
// interval against the average of the RING_AVG beats before it (slower
// beats further out), so breathing shows up as waves and a slow drift in
// heart rate doesn't push the line off the scale. Artifacts are grey dots
// on the track, beats recorded while moving are yellow, beats the sensor
// dropped leave a hole, and a beat with a hole either side is a dot.
//
// A beat's position is worked out once, when it arrives. The watch, unlike
// the simulator, kills an app whose onUpdate runs too long, and redoing the
// trigonometry for every beat on every update would grow with the test.
class BeatRing {

    var closed = false;     // the measurement ran its full time

    hidden var _span;       // the measurement's length in ms
    hidden var _cx;
    hidden var _cy;
    hidden var _base;       // the track's radius
    hidden var _x;
    hidden var _y;
    hidden var _kind;       // RING_* bits per point
    hidden var _n = 0;
    hidden var _elapsed = 0;
    hidden var _break = false;
    hidden var _recent;     // the latest good beats, oldest overwritten first
    hidden var _recentN = 0;
    hidden var _recentAt = 0;
    hidden var _recentSum = 0;

    function initialize(span) {
        var settings = System.getDeviceSettings();
        _cx = settings.screenWidth / 2;
        _cy = settings.screenHeight / 2;
        _base = _cx - RING_INSET;
        _span = span;
        _x = new [RING_POINTS];
        _y = new [RING_POINTS];
        _kind = new [RING_POINTS]b;
        _recent = new [RING_AVG];
    }

    // A good beat from settling: it starts the average off.
    function settle(rr) {
        remember(rr);
    }

    function add(rr, good, moving) {
        _elapsed += rr;
        if (_n == RING_POINTS) {
            return;
        }
        var a = 2 * Math.PI * _elapsed / _span;
        if (a > 2 * Math.PI) {
            a = 2 * Math.PI;
        }
        var r = _base;
        var kind = 0;
        if (good) {
            var swing = _recentN > 0 ? (rr - _recentSum.toFloat() / _recentN) * RING_PX_PER_MS : 0;
            if (swing > RING_SWING) {
                swing = RING_SWING;
            } else if (swing < -RING_SWING) {
                swing = -RING_SWING;
            }
            r += swing;
            if (moving) {
                kind |= RING_MOVING;
            }
            remember(rr);
        } else {
            kind = RING_ARTIFACT;
        }
        if (_break) {
            kind |= RING_BREAK;
            _break = false;
        }
        _x[_n] = _cx + r * Math.sin(a);
        _y[_n] = _cy - r * Math.cos(a);
        _kind[_n] = kind;
        _n++;
    }

    hidden function remember(rr) {
        if (_recentN == RING_AVG) {
            _recentSum -= _recent[_recentAt];
        } else {
            _recentN++;
        }
        _recent[_recentAt] = rr;
        _recentSum += rr;
        _recentAt = (_recentAt + 1) % RING_AVG;
    }

    // ms of beats the sensor dropped: time passes, nothing is drawn.
    function gap(ms) {
        _elapsed += ms;
        _break = true;
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
        var color = null;
        for (var i = 0; i < _n; i++) {
            var kind = _kind[i];
            if ((kind & RING_ARTIFACT) != 0) {
                dc.setColor(GREY, Graphics.COLOR_TRANSPARENT);
                color = GREY;
                dc.fillCircle(_x[i], _y[i], 3);
            } else {
                var want = (kind & RING_MOVING) != 0 ? Graphics.COLOR_YELLOW : Graphics.COLOR_RED;
                if (want != color) {
                    dc.setColor(want, Graphics.COLOR_TRANSPARENT);
                    color = want;
                }
                if (i > 0 && (kind & RING_BREAK) == 0 && (_kind[i - 1] & RING_ARTIFACT) == 0) {
                    dc.drawLine(_x[i - 1], _y[i - 1], _x[i], _y[i]);
                } else if (i == _n - 1 || (_kind[i + 1] & (RING_BREAK | RING_ARTIFACT)) != 0) {
                    // No line in or out
                    dc.fillCircle(_x[i], _y[i], 2);
                }
            }
        }
        var last = _n - 1;
        if (closed && (_kind[0] & RING_ARTIFACT) == 0 && (_kind[last] & RING_ARTIFACT) == 0) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(_x[last], _y[last], _x[0], _y[0]);
        }
        if (head && (_kind[last] & RING_ARTIFACT) == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(_x[last], _y[last], 5);
        }
    }
}
