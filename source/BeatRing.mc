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

// The breathing wave under the line: the same swings three times over,
// easing off towards BLUE_OUT px outward (the screen's edge) and BLUE_IN
// px inward. Its blue is 55% of 0x2A7FFF over black: everything under the
// wave is black, and the track, line and text draw over it, so solid looks
// the same as see-through and costs nothing per update.
const BLUE_GAIN = 3;
const BLUE_OUT = 17;
const BLUE_IN = 45;
const RING_BLUE = 0x17468C;

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
// Under the line a blue wave exaggerates the same swings, so each breath
// shows as a lobe; it's curved through the beats (Catmull-Rom) rather than
// averaged, since a breath takes only 3-6 beats.
//
// A beat's position is worked out once, when it arrives. The watch, unlike
// the simulator, kills an app whose onUpdate runs too long, and redoing the
// trigonometry for every beat on every update would grow with the test.
// The wave is drawn once into a bitmap, a beat behind (the curve needs the
// next beat), and only drawn again if the system reclaims the bitmap.
class BeatRing {

    var closed = false;     // the measurement ran its full time

    hidden var _span;       // the measurement's length in ms
    hidden var _cx;
    hidden var _cy;
    hidden var _base;       // the track's radius
    hidden var _x;
    hidden var _y;
    hidden var _kind;       // RING_* bits per point
    hidden var _a;          // angle per point
    hidden var _br;         // the wave's radius per point
    hidden var _blue = null;    // BufferedBitmapReference for the wave
    hidden var _blueUpTo = 0;   // the wave is drawn up to this point
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
        _a = new [RING_POINTS];
        _br = new [RING_POINTS];
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
        var br = _base;
        var kind = 0;
        if (good) {
            var swing = _recentN > 0 ? (rr - _recentSum.toFloat() / _recentN) * RING_PX_PER_MS : 0;
            var wave = swing * BLUE_GAIN;
            var limit = wave > 0 ? BLUE_OUT : BLUE_IN;
            br += wave / Math.sqrt(1 + (wave / limit) * (wave / limit));
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
        _a[_n] = a;
        _br[_n] = br;
        _n++;
        drawWave(_n - 1);
    }

    // The measurement is over: the last stretch of wave needs no next beat.
    function flush() {
        drawWave(_n);
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

    // Draws the wave up to point upTo - 1, whose neighbour is now known.
    hidden function drawWave(upTo) {
        var bmp = waveBitmap();
        if (bmp != null && upTo > 1) {
            segment(bmp.getDc(), upTo - 1);
        }
        _blueUpTo = upTo;
    }

    // The bitmap the wave is drawn in, made again (and the wave so far
    // redrawn) if the system has reclaimed it.
    hidden function waveBitmap() {
        var bmp = _blue != null ? _blue.get() : null;
        if (bmp == null && Graphics has :createBufferedBitmap) {
            _blue = Graphics.createBufferedBitmap({
                :width => _cx * 2,
                :height => _cy * 2,
                :palette => [ Graphics.COLOR_BLACK, RING_BLUE ]
            });
            bmp = _blue.get();
            if (bmp != null) {
                var dc = bmp.getDc();
                dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
                dc.clear();
                for (var i = 1; i < _blueUpTo; i++) {
                    segment(dc, i);
                }
            }
        }
        return bmp;
    }

    // The wave between points i - 1 and i, if the line joins them, as a
    // polygon from the curve back along the track.
    hidden function segment(dc, i) {
        if (!joined(i)) {
            return;
        }
        var p0 = joined(i - 1) ? i - 2 : i - 1;
        var p3 = joined(i + 1) ? i + 1 : i;
        var pts = new [6];
        for (var k = 0; k < 4; k++) {
            var t = k / 3.0;
            var a = spline(_a[p0], _a[i - 1], _a[i], _a[p3], t);
            var r = spline(_br[p0], _br[i - 1], _br[i], _br[p3], t);
            pts[k] = [ _cx + r * Math.sin(a), _cy - r * Math.cos(a) ];
        }
        pts[4] = [ _cx + _base * Math.sin(_a[i]), _cy - _base * Math.cos(_a[i]) ];
        pts[5] = [ _cx + _base * Math.sin(_a[i - 1]), _cy - _base * Math.cos(_a[i - 1]) ];
        dc.setColor(RING_BLUE, RING_BLUE);
        dc.fillPolygon(pts);
    }

    // Whether the line runs from point i - 1 to point i.
    hidden function joined(i) {
        return i > 0 && i < _n && (_kind[i] & (RING_BREAK | RING_ARTIFACT)) == 0
            && (_kind[i - 1] & RING_ARTIFACT) == 0;
    }

    hidden function spline(p0, p1, p2, p3, t) {
        return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
            + (3 * p1 - p0 - 3 * p2 + p3) * t * t * t);
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
        if (_n > 0) {
            var bmp = waveBitmap();
            if (bmp != null) {
                dc.drawBitmap(0, 0, bmp);
            }
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
                if (joined(i)) {
                    dc.drawLine(_x[i - 1], _y[i - 1], _x[i], _y[i]);
                } else if (!joined(i + 1)) {
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
