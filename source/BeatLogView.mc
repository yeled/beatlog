import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

const GREY = 0x8A8A8A;

class BeatLogView extends WatchUi.View {

    hidden var _test;

    function initialize(test) {
        View.initialize();
        _test = test;
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_test.phase == PHASE_DONE) {
            drawResults(dc);
        } else {
            drawLive(dc);
        }
    }

    hidden function drawLive(dc) {
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var phase = _test.phase;

        var title = "Ready";
        var titleColor = Graphics.COLOR_WHITE;
        var big = _test.heartRate != null ? _test.heartRate.format("%d") : "--";
        var hint = "START to begin";
        if (phase == PHASE_SETTLING) {
            title = "Sit still";
            big = clock(_test.remaining());
            hint = "START skips ahead";
        } else if (phase == PHASE_MEASURING) {
            title = "Recording";
            titleColor = Graphics.COLOR_RED;
            big = clock(_test.remaining());
            hint = "START ends early";
        }

        text(dc, cx, h * 0.20, Graphics.FONT_SMALL, titleColor, title);
        text(dc, cx, h * 0.40, Graphics.FONT_NUMBER_MEDIUM, Graphics.COLOR_WHITE, big);

        var hr = _test.heartRate != null ? _test.heartRate.format("%d") : "--";
        var rr = _test.lastRr != null ? _test.lastRr.format("%d") : "--";
        if (phase == PHASE_READY) {
            text(dc, cx, h * 0.57, Graphics.FONT_TINY, GREY, "bpm");
            text(dc, cx, h * 0.66, Graphics.FONT_TINY, Graphics.COLOR_WHITE, "beat " + rr + " ms");
        } else {
            text(dc, cx, h * 0.60, Graphics.FONT_TINY, Graphics.COLOR_WHITE, hr + " bpm   " + rr + " ms");
        }
        if (phase == PHASE_MEASURING) {
            var rmssd = _test.stats.rmssd();
            var line = "RMSSD " + (rmssd != null ? rmssd.format("%.0f") : "--")
                + "   " + _test.stats.count + " beats";
            text(dc, cx, h * 0.70, Graphics.FONT_TINY, Graphics.COLOR_WHITE, line);
        }
        text(dc, cx, h * 0.82, Graphics.FONT_XTINY, GREY, hint);
    }

    hidden function drawResults(dc) {
        var cx = dc.getWidth() / 2;
        var h = dc.getHeight();
        var stats = _test.stats;
        var rmssd = stats.rmssd();
        var sdnn = stats.sdnn();
        var meanHr = stats.meanHr();

        text(dc, cx, h * 0.17, Graphics.FONT_SMALL, GREY, "RMSSD");
        text(dc, cx, h * 0.35, Graphics.FONT_NUMBER_HOT, Graphics.COLOR_WHITE,
            rmssd != null ? rmssd.format("%.0f") : "--");
        text(dc, cx, h * 0.52, Graphics.FONT_TINY, Graphics.COLOR_WHITE,
            rmssd != null && rmssd > 0 ? "ms   ln " + Math.ln(rmssd).format("%.2f") : "ms");
        text(dc, cx, h * 0.62, Graphics.FONT_TINY, Graphics.COLOR_WHITE,
            "SDNN " + (sdnn != null ? sdnn.format("%.0f") : "--")
            + "   HR " + (meanHr != null ? meanHr.format("%.0f") : "--"));
        text(dc, cx, h * 0.71, Graphics.FONT_XTINY, GREY,
            stats.count + " beats   " + stats.artifacts + " artifacts");
        text(dc, cx, h * 0.81, Graphics.FONT_XTINY, GREY, "Saved   START for another");
    }

    hidden function text(dc, x, y, font, color, str) {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, str, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    hidden function clock(seconds) {
        return (seconds / 60).format("%d") + ":" + (seconds % 60).format("%02d");
    }
}
