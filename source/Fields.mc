import Toybox.Complications;
import Toybox.Lang;
import Toybox.WatchUi;

// Data field types used by the Field1 / Field2 / Field3 settings.
// The numbers are stored in settings, so add new types at the end and keep
// fieldNames() and resources/settings/settings.xml in the same order.
const FIELD_HR = 0;
const FIELD_BATTERY = 1;
const FIELD_BODY_BATTERY = 2;
const FIELD_STRESS = 3;
const FIELD_CALORIES = 4;
const FIELD_DISTANCE = 5;
const FIELD_FLOORS = 6;
const FIELD_NOTIFICATIONS = 7;
const FIELD_STEPS = 8;
const FIELD_NONE = 9;

// Tap target for the weather readout (not a selectable field).
const TARGET_WEATHER = 100;

// Loads a translated string (resources/strings, resources-pol/strings).
function str(id as ResourceId) as String {
    return WatchUi.loadResource(id) as String;
}

function fieldNames() as Array<String> {
    return [$.str(Rez.Strings.FieldHr), $.str(Rez.Strings.FieldBattery), $.str(Rez.Strings.FieldBody),
            $.str(Rez.Strings.FieldStress), $.str(Rez.Strings.FieldCalories), $.str(Rez.Strings.FieldDistance),
            $.str(Rez.Strings.FieldFloors), $.str(Rez.Strings.FieldNotifications), $.str(Rez.Strings.FieldSteps),
            $.str(Rez.Strings.FieldNone)];
}

function styleNames() as Array<String> {
    return [$.str(Rez.Strings.StyleOrbit), $.str(Rez.Strings.StyleTarget), $.str(Rez.Strings.StyleRadar)];
}

function styleName(v as Number) as String {
    var n = $.styleNames();
    return (v >= 0 && v < n.size()) ? n[v] : n[0];
}

function fieldName(v as Number) as String {
    var n = $.fieldNames();
    return (v >= 0 && v < n.size()) ? n[v] : n[0];
}

// Default value for each setting key.
function settingDefault(key as String) as Number {
    if (key.equals("Accent") || key.equals("Planet")) {
        return 3;               // red
    } else if (key.equals("Field2")) {
        return $.FIELD_BATTERY;
    } else if (key.equals("Field3")) {
        return $.FIELD_STEPS;
    }
    return 0;                   // Theme green, Field1 heart rate, Style orbit
}

// Which system widget to open when a readout is tapped (null = none).
function complicationFor(target as Number) {
    if (!(Toybox has :Complications)) {
        return null;
    }
    if (target == $.FIELD_HR) {
        return Complications.COMPLICATION_TYPE_HEART_RATE;
    } else if (target == $.FIELD_BATTERY) {
        return Complications.COMPLICATION_TYPE_BATTERY;
    } else if (target == $.FIELD_BODY_BATTERY) {
        return Complications.COMPLICATION_TYPE_BODY_BATTERY;
    } else if (target == $.FIELD_STRESS) {
        return Complications.COMPLICATION_TYPE_STRESS;
    } else if (target == $.FIELD_CALORIES) {
        return Complications.COMPLICATION_TYPE_CALORIES;
    } else if (target == $.FIELD_FLOORS) {
        return Complications.COMPLICATION_TYPE_FLOORS_CLIMBED;
    } else if (target == $.FIELD_NOTIFICATIONS) {
        return Complications.COMPLICATION_TYPE_NOTIFICATION_COUNT;
    } else if (target == $.FIELD_STEPS) {
        return Complications.COMPLICATION_TYPE_STEPS;
    } else if (target == $.TARGET_WEATHER) {
        return Complications.COMPLICATION_TYPE_CURRENT_WEATHER;
    }
    return null;
}
