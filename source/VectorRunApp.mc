import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class VectorRunApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new VectorRunView();
        return [view, new VectorRunDelegate(view)];
    }

    // Opened from the watch: long-press the face > Watch Face > Customize.
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new VectorSettingsMenu(), new VectorSettingsDelegate()];
    }

    // Called when settings change from the phone (store installs).
    function onSettingsChanged() as Void {
        $.settingsDirty = true;
        WatchUi.requestUpdate();
    }
}

// Set whenever a setting changes; the view re-reads its settings on the
// next update and clears it.
var settingsDirty as Boolean = true;

// "Show seconds" setting (off by default).
function showSeconds() as Boolean {
    return $.getBool("ShowSeconds");
}

// Reads an on/off setting.
function getBool(key as String) as Boolean {
    return Application.Properties.getValue(key) == true;
}

// Reads a numeric setting, falling back to a default.
function getProp(key as String, def as Number) as Number {
    var v = Application.Properties.getValue(key);
    if (v instanceof Number) {
        return v;
    }
    return def;
}
