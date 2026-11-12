import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

// Touch handling: pressing and holding a readout opens the matching system
// widget. (Watch faces only receive touch-and-hold, not quick taps.)
class VectorRunDelegate extends WatchUi.WatchFaceDelegate {

    private var _view as VectorRunView;

    function initialize(view as VectorRunView) {
        WatchFaceDelegate.initialize();
        _view = view;
    }

    function onPress(clickEvent as WatchUi.ClickEvent) as Boolean {
        var xy = clickEvent.getCoordinates();
        var target = _view.hitTest(xy[0], xy[1]);
        if (target == null) {
            return false;
        }
        var type = $.complicationFor(target);
        if (type == null || !(Complications has :exitTo)) {
            return false;
        }
        try {
            Complications.exitTo(new Complications.Id(type));
            return true;
        } catch (e) {
            return false;
        }
    }
}
