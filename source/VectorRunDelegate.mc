import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

// Set to false once tapping works; while true, every tap shows a short
// diagnostic line at the bottom of the face for 4 seconds.
const TAP_DEBUG = false;

// Touch handling: tapping a readout opens the matching system widget.
class VectorRunDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as VectorRunView;

    function initialize(view as VectorRunView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var where = "TAP " + xy[0].format("%d") + "," + xy[1].format("%d");
        var target = _view.hitTest(xy[0], xy[1]);
        if (target == null) {
            debug(where + " MISS");
            return false;
        }
        where = where + " T" + target.format("%d");
        var type = $.complicationFor(target);
        if (type == null) {
            debug(where + " NO WIDGET");
            return false;
        }
        if (!(Complications has :exitTo)) {
            debug(where + " NO EXITTO");
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            debug(where + " SENT");
            return true;
        } catch (e) {
            var m = e.getErrorMessage();
            debug(where + " ERR " + (m == null ? "?" : m));
            return false;
        }
    }

    private function debug(msg as String) as Void {
        if ($.TAP_DEBUG) {
            _view.reportTap(msg);
        }
    }
}
