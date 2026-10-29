import Toybox.Lang;
import Toybox.WatchUi;

class BeatLogDelegate extends WatchUi.BehaviorDelegate {

    hidden var _test;

    function initialize(test) {
        BehaviorDelegate.initialize();
        _test = test;
    }

    // Only the START button drives the test: there's no onSelect, so a stray
    // tap on the screen can't end a measurement.
    function onKey(evt) {
        if (evt.getKey() != WatchUi.KEY_ENTER) {
            return false;
        }
        var phase = _test.phase;
        if (phase == PHASE_READY) {
            _test.start();
        } else if (phase == PHASE_SETTLING) {
            _test.beginMeasuring();
        } else if (phase == PHASE_MEASURING) {
            _test.finish();
        } else {
            _test.reset();
        }
        WatchUi.requestUpdate();
        return true;
    }

    function onBack() {
        var phase = _test.phase;
        if (phase == PHASE_SETTLING || phase == PHASE_MEASURING) {
            WatchUi.pushView(new WatchUi.Confirmation("Discard this test?"),
                new DiscardDelegate(_test), WatchUi.SLIDE_IMMEDIATE);
            return true;
        }
        return false;
    }
}

class DiscardDelegate extends WatchUi.ConfirmationDelegate {

    hidden var _test;

    function initialize(test) {
        ConfirmationDelegate.initialize();
        _test = test;
    }

    function onResponse(response) {
        if (response == WatchUi.CONFIRM_YES) {
            _test.discard();
        }
        return true;
    }
}
