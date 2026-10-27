import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

// On-watch settings menu. Every item opens a list to pick from.
class VectorSettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => $.str(Rez.Strings.AppName)});
        addEntry(Rez.Strings.StyleTitle, "Style");
        addEntry(Rez.Strings.ThemeTitle, "Theme");
        addEntry(Rez.Strings.AccentTitle, "Accent");
        addEntry(Rez.Strings.PlanetTitle, "Planet");
        addEntry(Rez.Strings.Field1Title, "Field1");
        addEntry(Rez.Strings.Field2Title, "Field2");
        addEntry(Rez.Strings.Field3Title, "Field3");
    }

    private function addEntry(labelId as ResourceId, key as String) as Void {
        var label = $.str(labelId);
        var names = $.namesFor(key);
        var v = $.getProp(key, $.settingDefault(key));
        var sub = (v >= 0 && v < names.size()) ? names[v] : names[0];
        addItem(new WatchUi.MenuItem(label, sub, key, null));
    }
}

class VectorSettingsDelegate extends WatchUi.Menu2InputDelegate {

    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        if (id instanceof String) {
            WatchUi.pushView(new ListPickerMenu(id, item.getLabel()),
                             new ListPickerDelegate(id, item), WatchUi.SLIDE_LEFT);
        }
    }
}

// A list of choices for one setting; the current one is marked.
class ListPickerMenu extends WatchUi.Menu2 {

    function initialize(key as String, title as String) {
        Menu2.initialize({:title => title});
        var names = $.namesFor(key);
        var current = $.getProp(key, $.settingDefault(key));
        var mark = $.str(Rez.Strings.Current);
        for (var i = 0; i < names.size(); i++) {
            addItem(new WatchUi.MenuItem(names[i], i == current ? mark : null, i, null));
        }
        if (current >= 0 && current < names.size()) {
            setFocus(current);
        }
    }
}

class ListPickerDelegate extends WatchUi.Menu2InputDelegate {

    private var _key as String;
    private var _parent as MenuItem;

    function initialize(key as String, parent as MenuItem) {
        Menu2InputDelegate.initialize();
        _key = key;
        _parent = parent;
    }

    function onSelect(item as MenuItem) as Void {
        var idx = item.getId() as Number;
        Application.Properties.setValue(_key, idx);
        _parent.setSubLabel($.namesFor(_key)[idx]);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.requestUpdate();
    }
}

// The list of choices for a setting key.
function namesFor(key as String) as Array<String> {
    if (key.equals("Style")) {
        return $.styleNames();
    } else if (key.find("Field") != null) {
        return $.fieldNames();
    }
    return $.paletteNames();
}
