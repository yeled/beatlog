import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class BeatLogApp extends Application.AppBase {

    private var _test = null;
    private var _selfTest = null;

    function initialize() {
        AppBase.initialize();
    }

    // Sensors start with the app so the ready screen already shows whether
    // beats are arriving before a test begins.
    function onStart(state) {
        _test = new BeatTest();
        _test.startSensors();
        startSelfTest();
    }

    (:selftest)
    hidden function startSelfTest() {
        _selfTest = new SelfTest(_test);
    }

    (:notselftest)
    hidden function startSelfTest() {
    }

    // Leaving the app mid-test keeps what was recorded rather than losing it.
    function onStop(state) {
        if (_test != null) {
            _test.finish();
            _test.stopSensors();
        }
    }

    function getInitialView() {
        return [ new BeatLogView(_test), new BeatLogDelegate(_test) ];
    }
}
