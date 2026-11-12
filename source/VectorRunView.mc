import Toybox.Activity;
import Toybox.ActivityMonitor;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.Weather;
import Toybox.WatchUi;

// Retro vector-graphics watch face with three styles:
//   0 = orbit tracker  (planet edge, moon travels the orbit each hour)
//   1 = targeting      (wireframe trench, countdown = steps left to goal)
//   2 = radar          (sweep, hour/minute blips, notifications as contacts)
// Layout is designed for 454x454 (Forerunner 965) and scales with screen width.

// Orbit style: the moon travels straight across the planet's face, from
// MOON_X0 (far left, 454 px design units) at :00 until it has fully cleared
// the planet's edge at :60. MOON_R is its radius.
const MOON_X0 = 30;
// Planet centre sits this far left of the screen centre (radius 400), so its
// edge crosses the middle of the screen at x = 227 - 447 + 400 = 180.
const PLANET_OFFSET = 447;
const MOON_R = 20;

class VectorRunView extends WatchUi.WatchFace {

    private var _awake as Boolean = true;
    private var _seg as Array<Number> = [] as Array<Number>;   // seven-segment masks 0-9
    // planet cloud bands: radius, start deg, end deg (0 = 3 o'clock, CCW)
    private var _bands as Array<Number> = [] as Array<Number>;
    private var _w as Number = 454;
    private var _cx as Number = 227;
    private var _cy as Number = 227;
    private var _k as Float = 1.0;        // scale relative to 454 px design

    // settings, read once and again whenever $.settingsDirty is set
    private var _style as Number = 0;
    private var _f1 as Number = 0;
    private var _f2 as Number = 1;
    private var _f3 as Number = 8;
    private var _showSec as Boolean = false;
    private var _crt as Boolean = false;      // CRT glow + scanlines option
    private var _slant as Number = 0;         // digit slant in percent (0 or 13)
    // orbit starfield: x, y, brightness level (454 px design units)
    private var _stars as Array<Number> = [] as Array<Number>;

    // colours (set from settings in applyTheme)
    private var _main as Number = 0x33FF66;
    private var _dim as Number = 0x0E5522;
    private var _accent as Number = 0xFF3B30;
    private var _planetRim as Number = 0xFF3B30;
    private var _planetBand as Number = 0xBF2C24;
    private var _planetInner as Number = 0x731A15;
    private var _planetFill as Number = 0x230806;
    private var _planetNight as Number = 0x0C0302;
    private var _planetNightBand as Number = 0x4C110E;

    // slow-changing data, refreshed once a minute
    private var _cacheMin as Number = -1;
    private var _bodyBattery as Number? = null;
    private var _stress as Number? = null;
    private var _temp as Number? = null;      // in the watch's temperature units
    private var _cond as Number? = null;      // Weather.CONDITION_* value
    private var _dayFactor as Float = 1.0;    // 0 = night, 1 = solar noon
    private var _moonPhase as Float = 0.0;    // 0 = new, 0.5 = full
    private var _sunNext as Number? = null;   // next sunrise / sunset (epoch s), null = no location
    private var _sunIsRise as Boolean = true;
    private var _altitude as Number? = null;  // in the watch's elevation units
    private var _orbitStacked as Boolean = false;   // orbit fields 1/2 on separate lines
    private var _rowY as Array<Number> = [0, 0, 0] as Array<Number>;   // orbit field rows (screen px)
    private var _rowH as Number = 31;
    private var _radarBottomX as Array<Number> = [0, 0] as Array<Number>;   // radar field 3 / weather centres (screen px)

    // translated text, loaded once (resources/strings, resources-pol/strings)
    private var _lblShort as Array<String> = [] as Array<String>;
    private var _lblLong as Array<String> = [] as Array<String>;
    private var _txt as Dictionary<Symbol, String> = {} as Dictionary<Symbol, String>;

    function initialize() {
        WatchFace.initialize();
        // bits: a=1 top, b=2 top-right, c=4 bottom-right, d=8 bottom,
        //       e=16 bottom-left, f=32 top-left, g=64 middle
        // 10 and 11 are the letters A and P (12-hour marker)
        _seg = [0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F, 0x77, 0x73];
        $.settingsDirty = true;
        _stars = [
            338, 49, 1, 309, 44, 0, 332, 261, 4, 271, 243, 2, 257, 246, 3, 329, 225, 1,
            293, 162, 2, 194, 222, 3, 371, 257, 1, 248, 164, 1, 169, 58, 2, 232, 179, 0,
            422, 167, 1, 187, 122, 1, 230, 191, 1, 217, 220, 1, 426, 301, 1, 333, 45, 3,
            314, 242, 2, 223, 163, 0, 433, 218, 0, 196, 29, 2, 176, 370, 0, 307, 228, 2,
            215, 234, 0, 325, 162, 2, 378, 157, 2, 264, 186, 2, 196, 431, 4, 340, 165, 0,
            211, 227, 1, 225, 193, 4, 410, 294, 2, 295, 240, 0, 403, 341, 0, 199, 216, 2,
            303, 219, 2, 162, 60, 0, 296, 232, 1, 279, 192, 1, 194, 316, 0, 177, 386, 3,
            196, 198, 1, 272, 167, 4, 277, 27, 2, 182, 400, 3
        ];
        loadText();
        _bands = [
            372, 324, 340,  372, 346, 10,   372, 16, 34,
            352, 330, 354,  352, 2, 22,     352, 27, 38,
            326, 322, 336,  326, 342, 358,  326, 6, 30,
            298, 334, 4,    298, 10, 24,
            280, 340, 352,  280, 358, 18
        ];
    }

    function onLayout(dc as Dc) as Void {
        _w = dc.getWidth();
        _cx = _w / 2;
        _cy = dc.getHeight() / 2;
        _k = _w / 454.0;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        if ($.settingsDirty) {
            loadSettings();
            $.settingsDirty = false;
        }
        var clock = System.getClockTime();
        var style = _style;

        // the always-on view shows none of the slow data, so skip reading it
        if (!_awake) {
            drawAlwaysOn(dc, clock, style);
            return;
        }
        if (clock.min != _cacheMin) {
            refreshSlowData();
            _cacheMin = clock.min;
        }

        var data = readData();
        if (style == 0) {
            drawOrbit(dc, clock, data);
        } else {
            drawStepBezel(dc, data[:progress] as Float);
            drawDate(dc, _cx, s(40));
            drawTime(dc, clock, _cx, s(64), s(30), s(52), s(5), _showSec);
            if (style == 2) {
                drawRadar(dc, clock, data);
            } else {
                drawTargeting(dc, clock, data);
            }
        }
        if (_crt) {
            drawScanlines(dc);
        }
    }

    // CRT option: a black line across every fourth row.
    private function drawScanlines(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        var h = _cy * 2;
        for (var y = 3; y < h; y += 4) {
            dc.drawLine(0, y, _w, y);
        }
    }

    function onExitSleep() as Void {
        _awake = true;
        _cacheMin = -1;         // re-read weather, Body Battery etc. on wake
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        // AMOLED screens (like the 965) need a sparse always-on face.
        var ds = System.getDeviceSettings();
        var burnIn = (ds has :requiresBurnInProtection) && ds.requiresBurnInProtection;
        _awake = !burnIn;
        WatchUi.requestUpdate();
    }

    // Which readout is at screen point (x, y): a FIELD_* value,
    // TARGET_WEATHER, or null. Used by VectorRunDelegate.
    function hitTest(x as Number, y as Number) as Number? {
        var px = x / _k;
        var py = y / _k;
        var style = _style;
        var f1 = _f1;
        var f2 = _f2;
        var f3 = _f3;

        if (style == 0) {
            if (_temp != null && inBox(px, py, 330, 118, 425, 154)) { return $.TARGET_WEATHER; }
            // field rows as laid out by drawOrbit (screen px -> design units)
            var r0 = _rowY[0] / _k;
            var hh = _rowH / _k / 2.0;
            if (_orbitStacked) {
                if (inBox(px, py, 180, (r0 - hh).toNumber(), 410, (r0 + hh).toNumber())) { return f1; }
                if (inBox(px, py, 180, (r0 + hh).toNumber(), 410, (r0 + 3 * hh).toNumber())) { return f2; }
                if (inBox(px, py, 180, (r0 + 3 * hh).toNumber(), 400, (r0 + 5 * hh).toNumber())) { return f3; }
            } else {
                if (inBox(px, py, 190, (r0 - hh).toNumber(), 304, (r0 + hh).toNumber())) { return f1; }
                if (inBox(px, py, 304, (r0 - hh).toNumber(), 425, (r0 + hh).toNumber())) { return f2; }
                if (inBox(px, py, 190, (r0 + hh).toNumber(), 400, (r0 + 3 * hh).toNumber())) { return f3; }
            }
            return null;
        }
        var fy = (style == 2) ? 261 : 229;
        var fx = (style == 2) ? (_radarBottomX[0] / _k).toNumber() : 110;
        var wx = (style == 2) ? (_radarBottomX[1] / _k).toNumber() : 344;
        if (inBox(px, py, 0, fy - 45, 112, fy + 45)) { return f1; }
        if (inBox(px, py, 342, fy - 45, 454, fy + 45)) { return f2; }
        if (inBox(px, py, fx - 40, 318, fx + 40, 378)) { return f3; }
        if (_temp != null && inBox(px, py, wx - 40, 318, wx + 40, 378)) { return $.TARGET_WEATHER; }
        if (style == 1 && inBox(px, py, 165, 325, 290, 402)) { return $.FIELD_STEPS; }
        if (style == 2) {
            // the radar disc (contacts are notifications) or the CONTACTS text
            var rdx = px - 227;
            var rdy = py - 261;
            if (rdx * rdx + rdy * rdy <= 118 * 118 || inBox(px, py, 110, 368, 345, 440)) {
                return $.FIELD_NOTIFICATIONS;
            }
        }
        return null;
    }

    private function inBox(x as Float, y as Float, x0 as Number, y0 as Number, x1 as Number, y1 as Number) as Boolean {
        return x >= x0 && x <= x1 && y >= y0 && y <= y1;
    }

    // ---------------------------------------------------------------- data

    // Fast data, read every update.
    private function readData() as Dictionary {
        var steps = 0;
        var goal = 0;
        var calories = 0;
        var distance = 0;
        var floors = null;      // stays null on watches without a barometer
        var am = ActivityMonitor.getInfo();
        var v = am.steps;
        if (v != null) { steps = v; }
        v = am.stepGoal;
        if (v != null) { goal = v; }
        v = am.calories;
        if (v != null) { calories = v; }
        v = am.distance;
        if (v != null) { distance = v; }
        if (am has :floorsClimbed) {
            floors = am.floorsClimbed;
        }
        var intensity = null;
        if (am has :activeMinutesWeek) {
            var amw = am.activeMinutesWeek;
            if (amw != null) {
                intensity = amw.total;
            }
        }
        var progress = 0.0;
        if (goal > 0) {
            progress = steps.toFloat() / goal;
            if (progress > 1.0) {
                progress = 1.0;
            }
        }

        var hr = null;
        var act = Activity.getActivityInfo();
        if (act != null) {
            hr = act.currentHeartRate;
        }
        if (hr == null && (ActivityMonitor has :getHeartRateHistory)) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }

        return {
            :steps => steps,
            :goal => goal,
            :progress => progress,
            :calories => calories,
            :distance => distance,
            :floors => floors,
            :intensity => intensity,
            :hr => hr,
            :battery => System.getSystemStats().battery.toNumber(),
            :notifs => System.getDeviceSettings().notificationCount
        };
    }

    // Slow data: Body Battery, stress, weather, sun and moon. Once a minute.
    private function refreshSlowData() as Void {
        _bodyBattery = null;
        _stress = null;
        if ((Toybox has :SensorHistory) && (SensorHistory has :getBodyBatteryHistory)) {
            var bb = SensorHistory.getBodyBatteryHistory({:period => 1}).next();
            if (bb != null && bb.data != null) {
                _bodyBattery = (bb.data as Numeric).toNumber();
            }
        }
        if ((Toybox has :SensorHistory) && (SensorHistory has :getStressHistory)) {
            var st = SensorHistory.getStressHistory({:period => 1}).next();
            if (st != null && st.data != null) {
                _stress = (st.data as Numeric).toNumber();
            }
        }

        _temp = null;
        _cond = null;
        var loc = null;
        if (Toybox has :Weather) {
            var cc = Weather.getCurrentConditions();
            if (cc != null) {
                var t = cc.temperature;
                if (t != null) {
                    var tf = t.toFloat();
                    if (System.getDeviceSettings().temperatureUnits == System.UNIT_STATUTE) {
                        tf = tf * 9.0 / 5.0 + 32.0;
                    }
                    _temp = Math.round(tf).toNumber();
                }
                _cond = cc.condition as Number?;
                loc = cc.observationLocationPosition;
            }
        }

        // Day/night: 0 at sunrise and sunset, 1 at solar noon, 0 at night.
        // Falls back to 06:00-18:00 when the watch has no location yet.
        var now = Time.now().value();
        var midnight = Time.today().value();
        var sunrise = midnight + 6 * 3600;
        var sunset = midnight + 18 * 3600;
        var haveSun = false;
        var nextRise = sunrise + 86400;
        if (loc != null && (Weather has :getSunrise) && (Weather has :getSunset)) {
            var m = Time.now();
            var a = Weather.getSunrise(loc, m);
            var b = Weather.getSunset(loc, m);
            if (a != null && b != null) {
                sunrise = a.value();
                sunset = b.value();
                haveSun = true;
                var c = Weather.getSunrise(loc, m.add(new Time.Duration(86400)));
                nextRise = (c != null) ? c.value() : sunrise + 86400;
            }
        }
        // next sun event for the sunrise/sunset field
        _sunNext = null;
        if (haveSun) {
            if (now < sunrise) {
                _sunNext = sunrise;
                _sunIsRise = true;
            } else if (now < sunset) {
                _sunNext = sunset;
                _sunIsRise = false;
            } else {
                _sunNext = nextRise;
                _sunIsRise = true;
            }
        }
        _dayFactor = 0.0;
        if (sunset > sunrise && now > sunrise && now < sunset) {
            _dayFactor = Math.sin(Math.PI * (now - sunrise) / (sunset - sunrise)).toFloat();
        }

        // Altitude: live reading if there is one, else the last history sample.
        _altitude = null;
        var alt = null;
        var ai = Activity.getActivityInfo();
        if (ai != null) {
            alt = ai.altitude;
        }
        if (alt == null && (Toybox has :SensorHistory) && (SensorHistory has :getElevationHistory)) {
            var el = SensorHistory.getElevationHistory({:period => 1}).next();
            if (el != null && el.data != null) {
                alt = el.data;
            }
        }
        if (alt != null) {
            var af = (alt as Numeric).toFloat();
            if (System.getDeviceSettings().elevationUnits != System.UNIT_METRIC) {
                af = af * 3.28084;
            }
            _altitude = Math.round(af).toNumber();
        }

        // Moon phase from a known new moon (2000-01-06 18:14 UTC).
        var cycles = (now - 947182440) / 86400.0 / 29.530588853;
        _moonPhase = (cycles - Math.floor(cycles)).toFloat();
    }

    private function loadSettings() as Void {
        _style = $.getProp("Style", 0);
        _f1 = $.getProp("Field1", $.settingDefault("Field1"));
        _f2 = $.getProp("Field2", $.settingDefault("Field2"));
        _f3 = $.getProp("Field3", $.settingDefault("Field3"));
        _showSec = $.showSeconds();
        _crt = $.getBool("CrtGlow");
        _slant = $.getBool("SlantDigits") ? 13 : 0;
        applyTheme();
    }

    // Colours come from the palette; dim lines and planet shading are derived.
    private function applyTheme() as Void {
        _main = $.paletteColor($.getProp("Theme", 0));
        _dim = $.shade(_main, 0.4);
        _accent = $.paletteColor($.getProp("Accent", 3));
        var p = $.paletteColor($.getProp("Planet", 3));
        _planetRim = p;
        _planetBand = $.shade(p, 0.75);
        _planetInner = $.shade(p, 0.45);
        _planetFill = $.shade(p, 0.14);
        _planetNight = $.shade(p, 0.05);
        _planetNightBand = $.shade(p, 0.3);
    }

    // ------------------------------------------------------------- fields

    private function isMetric() as Boolean {
        return System.getDeviceSettings().distanceUnits == System.UNIT_METRIC;
    }

    private function loadText() as Void {
        var hr = $.str(Rez.Strings.LblHr);
        var kcal = $.str(Rez.Strings.LblKcal);
        var steps = $.str(Rez.Strings.LblSteps);
        var longSteps = $.str(Rez.Strings.LongSteps);
        var sec = $.str(Rez.Strings.LblSec);
        // indexed by FIELD_* (distance, sunrise/sunset and altitude have
        // changing labels and are handled in fieldLabel)
        _lblShort = [hr, $.str(Rez.Strings.LblBat), $.str(Rez.Strings.LblBody), $.str(Rez.Strings.LblStress),
                     kcal, "", $.str(Rez.Strings.LblFloors), $.str(Rez.Strings.LblMsgs), steps, "", sec,
                     "", $.str(Rez.Strings.LblInt), ""];
        _lblLong = [hr, $.str(Rez.Strings.LongBat), $.str(Rez.Strings.LongBody), $.str(Rez.Strings.LongStress),
                    kcal, "", $.str(Rez.Strings.LongFloors), $.str(Rez.Strings.LongMsgs), longSteps, "", sec,
                    "", $.str(Rez.Strings.LongInt), ""];
        _txt = {
            :batPct => $.str(Rez.Strings.LblBatPct),
            :km => $.str(Rez.Strings.LblKm),
            :mi => $.str(Rez.Strings.LblMi),
            :rise => $.str(Rez.Strings.LblRise),
            :set => $.str(Rez.Strings.LblSet),
            :longRise => $.str(Rez.Strings.LongRise),
            :longSet => $.str(Rez.Strings.LongSet),
            :alt => $.str(Rez.Strings.LblAlt),
            :m => $.str(Rez.Strings.LblM),
            :ft => $.str(Rez.Strings.LblFt),
            :f3 => $.str(Rez.Strings.Field3Pattern),
            :inRange => $.str(Rez.Strings.InRange),
            :now => $.str(Rez.Strings.Now),
            :min => $.str(Rez.Strings.MinPattern),
            :toGoal => $.str(Rez.Strings.ToGoal),
            :locked => $.str(Rez.Strings.Locked),
            :cNone => $.str(Rez.Strings.ContactsNone),
            :cOne => $.str(Rez.Strings.ContactsOne),
            :cFew => $.str(Rez.Strings.ContactsFew),
            :cMany => $.str(Rez.Strings.ContactsMany)
        } as Dictionary<Symbol, String>;
    }

    private function txt(key as Symbol) as String {
        var v = _txt[key];
        return v == null ? "" : v;
    }

    // "1 CONTACT", "3 KONTAKTY", "5 KONTAKTÓW"... (Polish plural rules; the
    // English few/many strings are identical)
    private function contactsText(n as Number) as String {
        if (n == 0) {
            return txt(:cNone);
        } else if (n == 1) {
            return txt(:cOne);
        }
        var m10 = n % 10;
        var m100 = n % 100;
        var few = m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14);
        return Lang.format(few ? txt(:cFew) : txt(:cMany), [n]);
    }

    // Short label used next to values ("BB 54", stacked readouts).
    private function fieldLabel(type as Number) as String {
        if (type == $.FIELD_DISTANCE) {
            return isMetric() ? txt(:km) : txt(:mi);
        }
        if (type == $.FIELD_SUN) {
            return _sunIsRise ? txt(:rise) : txt(:set);
        }
        if (type == $.FIELD_ALTITUDE) {
            var metricElev = System.getDeviceSettings().elevationUnits == System.UNIT_METRIC;
            return txt(:alt) + " " + (metricElev ? txt(:m) : txt(:ft));
        }
        return (type >= 0 && type < _lblShort.size()) ? _lblShort[type] : "";
    }

    // Longer label for the single-field line in the orbit style.
    private function fieldLongLabel(type as Number) as String {
        if (type == $.FIELD_DISTANCE || type == $.FIELD_ALTITUDE) {
            return fieldLabel(type);
        }
        if (type == $.FIELD_SUN) {
            return _sunIsRise ? txt(:longRise) : txt(:longSet);
        }
        return (type >= 0 && type < _lblLong.size()) ? _lblLong[type] : "";
    }

    // withPercent = false drops the "%" from battery where space is tight.
    private function fieldValue(type as Number, data as Dictionary, withPercent as Boolean) as String {
        if (type == $.FIELD_HR) {
            var hr = data[:hr];
            return hr == null ? "--" : (hr as Number).format("%d");
        }
        if (type == $.FIELD_BATTERY) {
            // no "%" at 100: the extra character would change the layout
            var bat = data[:battery] as Number;
            return bat.format("%d") + (withPercent && bat < 100 ? "%" : "");
        }
        if (type == $.FIELD_BODY_BATTERY) { return numOrDash(_bodyBattery); }
        if (type == $.FIELD_STRESS) { return numOrDash(_stress); }
        if (type == $.FIELD_CALORIES) { return (data[:calories] as Number).format("%d"); }
        if (type == $.FIELD_DISTANCE) {
            var cm = data[:distance] as Number;
            return (cm / (isMetric() ? 100000.0 : 160934.4)).format("%.1f");
        }
        if (type == $.FIELD_FLOORS) { return numOrDash(data[:floors] as Number?); }
        if (type == $.FIELD_NOTIFICATIONS) { return (data[:notifs] as Number).format("%d"); }
        if (type == $.FIELD_STEPS) { return (data[:steps] as Number).format("%d"); }
        if (type == $.FIELD_SECONDS) { return System.getClockTime().sec.format("%02d"); }
        if (type == $.FIELD_SUN) { return sunText(); }
        if (type == $.FIELD_INTENSITY) { return numOrDash(data[:intensity] as Number?); }
        if (type == $.FIELD_ALTITUDE) { return numOrDash(_altitude); }
        return "";
    }

    // Time of the next sunrise or sunset ("18:42"), or "--" without a location.
    private function sunText() as String {
        var at = _sunNext;
        if (at == null) {
            return "--";
        }
        var info = Gregorian.info(new Time.Moment(at), Time.FORMAT_SHORT);
        var h = info.hour;
        if (System.getDeviceSettings().is24Hour) {
            return h.format("%02d") + ":" + info.min.format("%02d");
        }
        h = h % 12;
        if (h == 0) {
            h = 12;
        }
        return h.format("%d") + ":" + info.min.format("%02d");
    }

    // Battery turns to the accent colour at 15% or below.
    private function fieldColor(type as Number, data as Dictionary) as Number {
        return (type == $.FIELD_BATTERY && (data[:battery] as Number) <= 15) ? _accent : _main;
    }

    private function numOrDash(v as Number?) as String {
        return v == null ? "--" : v.format("%d");
    }

    // Label above, value below. Draws nothing for FIELD_NONE.
    private function drawFieldStack(dc as Dc, x as Number, y as Number, type as Number, data as Dictionary) as Void {
        if (type == $.FIELD_NONE) {
            return;
        }
        // label-to-value distance from the real font heights (min 30 px at
        // 454), so accents such as the hook under Ę clear the value below
        var gap = ((dc.getFontHeight(Graphics.FONT_XTINY) + dc.getFontHeight(Graphics.FONT_TINY)) * 0.42).toNumber();
        if (gap < s(30)) {
            gap = s(30);
        }
        var up = gap * 8 / 15;
        dc.setColor(fieldColor(type, data), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y - up, Graphics.FONT_XTINY, type == $.FIELD_BATTERY ? txt(:batPct) : fieldLabel(type),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x, y - up + gap, Graphics.FONT_TINY, fieldValue(type, data, stackPct(type, data)),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Width of a side readout: its label or value, whichever is wider.
    private function stackWidth(dc as Dc, type as Number, data as Dictionary) as Number {
        if (type == $.FIELD_NONE) {
            return 0;
        }
        var a = dc.getTextWidthInPixels(type == $.FIELD_BATTERY ? txt(:batPct) : fieldLabel(type), Graphics.FONT_XTINY);
        var b = dc.getTextWidthInPixels(fieldValue(type, data, stackPct(type, data)), Graphics.FONT_TINY);
        return a > b ? a : b;
    }

    // In a side readout the battery's "%" is normally part of the label
    // (BAT%). Where a translation's label has no "%" (German AKKU), it goes
    // after the number instead - except at 100, which is as wide as the
    // spot allows without the sign.
    private function stackPct(type as Number, data as Dictionary) as Boolean {
        return type == $.FIELD_BATTERY && txt(:batPct).find("%") == null && (data[:battery] as Number) < 100;
    }

    // Free width between the screen edge and `inner` for a side readout.
    private function sideRoom(inner as Number, leftSide as Boolean) as Number {
        return leftSide ? inner - s(16) : _w - inner - s(16);
    }

    // Centre x for a side readout of width w: its usual spot (56 px from the
    // edge) if that fits between the progress ring and `inner` (the graphic it
    // sits next to); otherwise moved to fit. A readout wider than that space
    // stays clear of the graphic and runs toward the edge instead.
    private function sideX(w as Number, inner as Number, leftSide as Boolean) as Number {
        var m = s(6);       // gap to the graphic on the inner side
        var e = s(10);      // clear of the progress ring
        // work on the left side; the right side is its mirror image
        var hi = (leftSide ? inner : _w - inner) - m;
        var x = s(56);
        if (w > hi - e) {
            x = hi - w / 2;
            if (x - w / 2 < s(8)) {
                x = s(8) + w / 2;
            }
        } else if (x + w / 2 > hi) {
            x = hi - w / 2;
        } else if (x - w / 2 < e) {
            x = e + w / 2;
        }
        return leftSide ? x : _w - x;
    }

    // ------------------------------------------------------- shared parts

    // Scale a design value (454 px screen) to this screen. Positive values only.
    private function s(v as Numeric) as Number {
        var r = (v * _k).toNumber();
        return r < 1 ? 1 : r;
    }

    // Thin ring at the very edge: a dim full circle with a bright arc that
    // grows clockwise from 12 o'clock as steps approach the daily goal.
    private function drawStepBezel(dc as Dc, progress as Float) as Void {
        var r = _cx - s(5);
        dc.setPenWidth(1);
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, r);
        if (progress <= 0.0) {
            return;
        }
        dc.setPenWidth(s(2));
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        if (progress >= 1.0) {
            dc.drawCircle(_cx, _cy, r);
            return;
        }
        var sweep = (progress * 360).toNumber();
        if (sweep >= 1) {
            dc.drawArc(_cx, _cy, r, Graphics.ARC_CLOCKWISE, 90, 90 - sweep);
        }
    }

    private function drawDate(dc as Dc, x as Number, y as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var txt = info.day_of_week.toString().toUpper() + " " + info.day.format("%02d");
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, txt,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // HH:MM in seven-segment digits, centred on x, top edge at y. With
    // withSec, HH:MM shrinks a little and small seconds follow it, sharing
    // its bottom edge, so nothing below the time moves. In 12-hour mode the
    // leading zero is dropped and a small A or P follows.
    private function drawTime(dc as Dc, clock as System.ClockTime, x as Number, y as Number,
                              dw as Number, dh as Number, pen as Number, withSec as Boolean) as Void {
        if (_crt && _awake) {
            // glow: the same digits first, a little wider and dim
            drawTimePass(dc, clock, x, y, dw, dh, pen, withSec, s(3), $.shade(_main, 0.2));
        }
        drawTimePass(dc, clock, x, y, dw, dh, pen, withSec, 0, _main);
    }

    // extra = added stroke width (glow pass), col = stroke colour.
    private function drawTimePass(dc as Dc, clock as System.ClockTime, x as Number, y as Number,
                                  dw as Number, dh as Number, pen as Number, withSec as Boolean,
                                  extra as Number, col as Number) as Void {
        var is24 = System.getDeviceSettings().is24Hour;
        var hour = clock.hour;
        var pm = hour >= 12;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) {
                hour = 12;
            }
        }
        var blankLead = !is24 && hour < 10;
        if (withSec) {
            var dh2 = dh * 9 / 10;
            y += dh - dh2;
            dh = dh2;
            dw = dw * 4 / 5;
        }
        // small glyphs after HH:MM: seconds, then A / P
        var sw = dw * 2 / 3;
        var sh = dh * 3 / 5;
        var sGap = sw / 2 > s(5) ? sw / 2 : s(5);
        var sLead = s(12);
        // gap before the A / P marker: wide enough that it does not read as
        // part of a "1" beside it
        var apGap = withSec ? sGap + s(12) : s(20);
        var sPen = pen * 4 / 5;
        if (sPen < 2) {
            sPen = pen < 2 ? pen : 2;
        }
        var gap = dw / 2;
        var total = dw * 4 + gap * 4;
        if (blankLead) {
            total -= dw + gap;
        }
        if (withSec) {
            total += sLead + sw * 2 + sGap;
        }
        if (!is24) {
            total += apGap + sw;
        }
        var px = x - total / 2;

        dc.setPenWidth(pen + extra);
        dc.setColor(col, Graphics.COLOR_TRANSPARENT);
        if (!blankLead) {
            drawDigit(dc, px, y, dw, dh, hour / 10, pen);
            px += dw + gap;
        }
        drawDigit(dc, px, y, dw, dh, hour % 10, pen);
        px += dw + gap;
        dc.fillRectangle(px - pen / 2 - 1, y + dh * 3 / 10 - pen / 2, pen + 1, pen + 1);
        dc.fillRectangle(px - pen / 2 - 1, y + dh * 7 / 10 - pen / 2, pen + 1, pen + 1);
        px += gap;
        drawDigit(dc, px, y, dw, dh, clock.min / 10, pen);
        px += dw + gap;
        drawDigit(dc, px, y, dw, dh, clock.min % 10, pen);
        px += dw;

        var sy = y + dh - sh;
        dc.setPenWidth(sPen + extra);
        if (withSec) {
            px += sLead;
            drawDigit(dc, px, sy, sw, sh, clock.sec / 10, sPen);
            px += sw + sGap;
            drawDigit(dc, px, sy, sw, sh, clock.sec % 10, sPen);
            px += sw;
        }
        if (!is24) {
            px += apGap;
            drawDigit(dc, px, sy, sw, sh, pm ? 11 : 10, sPen);
        }
    }

    // One seven-segment glyph (0-9, 10 = A, 11 = P); uses the current colour
    // and pen width. `pen` is only the gap left at the segment ends. With the
    // slanted-digits option the top leans right and the bottom left.
    private function drawDigit(dc as Dc, x as Number, y as Number, w as Number, h as Number,
                               d as Number, pen as Number) as Void {
        var m = _seg[d];
        var g = pen;
        var hh = h / 2;
        var o = hh * _slant / 100;              // sideways shift at the top edge
        var og = (hh - g) * _slant / 100;       // ... and at a segment end near it
        var oc = g * _slant / 100;              // ... and at a segment end near the middle
        if ((m & 0x01) != 0) { dc.drawLine(x + g + o, y, x + w - g + o, y); }
        if ((m & 0x02) != 0) { dc.drawLine(x + w + og, y + g, x + w + oc, y + hh - g); }
        if ((m & 0x04) != 0) { dc.drawLine(x + w - oc, y + hh + g, x + w - og, y + h - g); }
        if ((m & 0x08) != 0) { dc.drawLine(x + g - o, y + h, x + w - g - o, y + h); }
        if ((m & 0x10) != 0) { dc.drawLine(x - oc, y + hh + g, x - og, y + h - g); }
        if ((m & 0x20) != 0) { dc.drawLine(x + og, y + g, x + oc, y + hh - g); }
        if ((m & 0x40) != 0) { dc.drawLine(x + g, y + hh, x + w - g, y + hh); }
    }

    // Tiny seven-segment number with leading zeros (decorative counters).
    private function drawTinyNumber(dc as Dc, x as Number, y as Number, value as Number, digits as Number) as Void {
        var w = s(7);
        var h = s(11);
        var step = w + s(4);
        dc.setPenWidth(s(2));
        var px = x + step * (digits - 1);
        for (var i = 0; i < digits; i++) {
            drawDigit(dc, px, y, w, h, value % 10, 0);
            value /= 10;
            px -= step;
        }
    }

    // ------------------------------------------------------------ weather

    // 0 clear, 1 partly cloudy, 2 cloudy, 3 rain, 4 snow, 5 storm, 6 fog
    // (numbers are Weather.CONDITION_* values)
    private function weatherKind(c as Number) as Number {
        if (c == 0 || c == 22 || c == 23 || c == 40) { return 0; }
        if (c == 1 || c == 52) { return 1; }
        if (c == 6 || c == 12 || c == 28 || c == 32 || c == 36 || c == 41 || c == 42) { return 5; }
        if (c == 4 || c == 7 || c == 10 || c == 16 || c == 17 || c == 18 || c == 19 || c == 21 ||
            c == 34 || c == 43 || c == 44 || c == 46 || c == 47 || c == 48 || c == 49 ||
            c == 50 || c == 51) { return 4; }
        if (c == 3 || c == 11 || c == 13 || c == 14 || c == 15 || c == 24 || c == 25 ||
            c == 26 || c == 27 || c == 31 || c == 45) { return 3; }
        if (c == 8 || c == 9 || c == 29 || c == 30 || c == 33 || c == 35 || c == 37 ||
            c == 38 || c == 39) { return 6; }
        return 2;
    }

    // Small vector weather icon centred on (x, y), roughly 2r wide.
    private function drawWeatherIcon(dc as Dc, x as Number, y as Number, r as Number, cond as Number) as Void {
        var kind = weatherKind(cond);
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        if (kind == 0) {
            drawSun(dc, x, y, r);
        } else if (kind == 1) {
            drawSun(dc, x - r * 3 / 10, y - r * 3 / 10, r * 7 / 10);
            dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
            drawCloud(dc, x + r / 5, y + r / 4, r * 8 / 10 + s(2));
            dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
            drawCloud(dc, x + r / 5, y + r / 4, r * 8 / 10);
        } else if (kind == 6) {
            dc.drawLine(x - r, y - r / 2, x + r * 6 / 10, y - r / 2);
            dc.drawLine(x - r * 6 / 10, y, x + r, y);
            dc.drawLine(x - r, y + r / 2, x + r * 6 / 10, y + r / 2);
        } else if (kind == 2) {
            drawCloud(dc, x, y, r);
        } else {
            drawCloud(dc, x, y - r / 3, r);
            var by = y + r / 2;
            if (kind == 3) {
                for (var i = -1; i <= 1; i++) {
                    dc.drawLine(x + i * r / 2, by, x + i * r / 2 - r / 4, by + r / 2);
                }
            } else if (kind == 4) {
                for (var j = -1; j <= 1; j++) {
                    dc.fillCircle(x + j * r / 2, by + r / 4, s(2));
                }
            } else {
                dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(x + r / 6, by - r / 6, x - r / 6, by + r / 4);
                dc.drawLine(x - r / 6, by + r / 4, x + r / 6, by + r / 4);
                dc.drawLine(x + r / 6, by + r / 4, x - r / 6, by + r * 2 / 3);
            }
        }
    }

    private function drawSun(dc as Dc, x as Number, y as Number, r as Number) as Void {
        dc.drawCircle(x, y, r * 45 / 100);
        for (var i = 0; i < 8; i++) {
            var a = i * Math.PI / 4.0;
            dc.drawLine(x + r * 0.68 * Math.cos(a), y + r * 0.68 * Math.sin(a),
                        x + r * Math.cos(a), y + r * Math.sin(a));
        }
    }

    // Filled cloud in the current colour.
    private function drawCloud(dc as Dc, x as Number, y as Number, r as Number) as Void {
        dc.fillCircle(x - r * 4 / 10, y + r / 10, r * 35 / 100);
        dc.fillCircle(x + r * 15 / 100, y - r / 10, r / 2);
        dc.fillCircle(x + r * 55 / 100, y + r * 15 / 100, r * 3 / 10);
        dc.fillRectangle(x - r * 4 / 10, y + r / 10, r * 95 / 100, r * 35 / 100);
    }

    private function tempText() as String {
        return _temp == null ? "" : (_temp as Number).format("%d") + "°";
    }

    // Icon above, temperature below (targeting and radar).
    private function drawWeatherStack(dc as Dc, x as Number, y as Number) as Void {
        if (_temp == null || _cond == null) {
            return;
        }
        drawWeatherIcon(dc, x, y - s(12), s(12), _cond as Number);
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y + s(14), Graphics.FONT_XTINY, tempText(),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // Field 3 in the lower corner (targeting and radar).
    // Width of a field-3 readout (label or value, both small font).
    // Centre x of the Targeting bottom-left field: its usual spot, moved
    // right when a wide value (a five-digit step count) would reach the
    // bezel ticks.
    private function targetField3X(dc as Dc, type as Number, data as Dictionary) as Number {
        var x = s(110);
        if (type == $.FIELD_NONE) {
            return x;
        }
        var half = dc.getTextWidthInPixels(fieldValue(type, data, true), Graphics.FONT_XTINY) / 2;
        var dy = s(354) + s(14) + dc.getFontHeight(Graphics.FONT_XTINY) * 35 / 100 - _cy;   // value's lower edge
        var r = _cx - s(14);                                                                // inside the ticks
        if (dy < r) {
            var minX = _cx - Math.sqrt(r * r - dy * dy).toNumber() + s(4) + half;
            if (x < minX) {
                x = minX;
            }
        }
        // ... but never so far that the label or value reaches the countdown digits
        var maxX = s(165) - s(8) - smallWidth(dc, type, data) / 2;
        if (x > maxX) {
            x = maxX;
        }
        return x;
    }

    private function smallWidth(dc as Dc, type as Number, data as Dictionary) as Number {
        if (type == $.FIELD_NONE) {
            return 0;
        }
        var a = dc.getTextWidthInPixels(fieldLabel(type), Graphics.FONT_XTINY);
        var b = dc.getTextWidthInPixels(fieldValue(type, data, true), Graphics.FONT_XTINY);
        return a > b ? a : b;
    }

    private function drawSmallField(dc as Dc, x as Number, y as Number, type as Number, data as Dictionary) as Void {
        if (type == $.FIELD_NONE) {
            return;
        }
        dc.setColor(fieldColor(type, data), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y - s(12), Graphics.FONT_XTINY, fieldLabel(type),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x, y + s(14), Graphics.FONT_XTINY, fieldValue(type, data, true),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // --------------------------------------------------------- orbit style
    //
    // A gas giant curves in from the left edge, with a day/night terminator
    // that follows the sun. Each hour a hollow wireframe moon (showing
    // tonight's real phase) crosses the planet's face from the far left; IN
    // RANGE counts the minutes until it has fully cleared the planet's edge
    // at the range marker (the top of the hour).

    // Moon centre x for a fraction f (0..1) of the hour; y is always _cy.
    private function moonX(f as Float) as Float {
        var x0 = s($.MOON_X0);
        var x1 = (_cx - s($.PLANET_OFFSET)) + s(400) + s($.MOON_R) + s(2);   // just clear of the rim
        return x0 + (x1 - x0) * f;
    }

    private function drawOrbit(dc as Dc, clock as System.ClockTime, data as Dictionary) as Void {
        var px = _cx - s($.PLANET_OFFSET);   // planet centre, off-screen to the left
        var py = _cy;
        var pr = s(400);
        // :00 is the "in range" minute: the moon sits locked on the marker.
        // From :01 to :59 it crosses the planet.
        var locked = clock.min == 0;
        var t = locked ? 1.0 : (clock.min - 1 + clock.sec / 60.0) / 59.0;
        var ex = moonX(1.0);          // range marker: moon fully clear of the planet
        var ey = _cy;

        // starfield: fixed stars in the empty black; a few twinkle each second
        var starCols = [$.shade(_main, 0.3), $.shade(_main, 0.45), $.shade(_main, 0.7),
                        $.shade(_main, 0.6), $.shade(_main, 0.9)];
        for (var si = 0; si + 2 < _stars.size(); si += 3) {
            var lv = _stars[si + 2];
            var big = lv >= 3;
            if ((si / 3 + clock.sec) % 7 == 0 && lv != 2 && lv != 4) {
                lv += 1;                          // twinkle: one step brighter
            }
            dc.setColor(starCols[lv] as Number, Graphics.COLOR_TRANSPARENT);
            var sz = big ? s(3) : s(2);
            dc.fillRectangle(s(_stars[si]), s(_stars[si + 1]), sz, sz);
        }

        // planet: night side inside the terminator radius, lit crescent outside
        var rT = pr - s(10) - (s(130) * _dayFactor).toNumber();
        dc.setColor(_planetFill, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(px, py, pr);
        dc.setColor(_planetNight, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(px, py, rT);

        dc.setPenWidth(s(2));
        dc.setColor(_planetInner, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(px, py, pr - s(12));
        dc.setPenWidth(s(3));
        for (var i = 0; i + 2 < _bands.size(); i += 3) {
            var br = s(_bands[i]);
            dc.setColor(br > rT ? _planetBand : _planetNightBand, Graphics.COLOR_TRANSPARENT);
            dc.drawArc(px, py, br, Graphics.ARC_COUNTER_CLOCKWISE, _bands[i + 1], _bands[i + 2]);
        }

        // dashed terminator line
        dc.setPenWidth(s(2));
        dc.setColor(_planetInner, Graphics.COLOR_TRANSPARENT);
        for (var a = -42; a < 42; a += 6) {
            var a0 = (a + 360) % 360;
            dc.drawArc(px, py, rT, Graphics.ARC_COUNTER_CLOCKWISE, a0, (a0 + 3) % 360);
        }

        if (_crt) {
            dc.setColor($.shade(_planetRim, 0.3), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(11));
            dc.drawCircle(px, py, pr);
        }
        dc.setColor(_planetRim, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(4));
        dc.drawCircle(px, py, pr);

        // track: solid where the moon has been, dashed ahead of it
        var n = 30;
        dc.setPenWidth(s(2));
        for (var j = 0; j < n; j++) {
            var ta = j.toFloat() / n;
            var tb = (j + 1).toFloat() / n;
            var draw = true;
            if (tb <= t) {
                dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
            } else if (j % 2 == 0) {
                dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            } else {
                draw = false;
            }
            if (draw) {
                dc.drawLine(moonX(ta), ey, moonX(tb), ey);
            }
        }

        // 5-minute ticks below the track
        for (var k = 0; k <= 12; k++) {
            var kx = moonX(k / 12.0);
            var len = (k % 3 == 0) ? s(10) : s(5);
            dc.setColor(k / 12.0 <= t ? _main : _dim, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(kx, ey + s($.MOON_R) + s(4), kx, ey + s($.MOON_R) + s(4) + len);
        }

        var mr = s($.MOON_R);
        if (locked) {
            // in range: filled disc with an accent cross
            dc.setColor($.shade(_main, 0.6), Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(ex, ey, mr);
            dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(2));
            dc.drawCircle(ex, ey, mr);
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(5));
            dc.drawLine(ex - mr * 7 / 10, ey, ex + mr * 7 / 10, ey);
            dc.drawLine(ex, ey - mr * 7 / 10, ex, ey + mr * 7 / 10);
        } else {
            // range marker: faint target ring with an accent cross, just clear
            // of the planet's edge
            dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(2));
            dc.drawCircle(ex, ey, mr);
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(ex - s(7), ey, ex + s(7), ey);
            dc.drawLine(ex, ey - s(7), ex, ey + s(7));

            // hollow wireframe moon, drawn over the planet; the planet's bands
            // stay visible through it
            drawGlobe(dc, moonX(t), ey, mr, clock.sec);
        }

        // time, date and weather
        drawTime(dc, clock, s(290), s(64), s(26), s(48), s(5), _showSec);
        if (_temp != null && _cond != null) {
            drawDate(dc, s(280), s(136));
            drawWeatherIcon(dc, s(354), s(136), s(11), _cond as Number);
            dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
            dc.drawText(s(370), s(136), Graphics.FONT_XTINY, tempText(),
                Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        } else {
            drawDate(dc, s(290), s(136));
        }

        // Lower text block: IN RANGE, minutes, then the data fields. The 454 px
        // design positions are minimums; on watches whose fonts are larger
        // relative to the screen (390 / 360 px) the lines are pushed apart
        // using the real font heights, and the whole block is lifted if it
        // would run off the bottom.
        var font = Graphics.FONT_XTINY;
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var hX = dc.getFontHeight(font);
        var hT = dc.getFontHeight(Graphics.FONT_TINY);
        var gapXT = ((hX + hT) * 0.4).toNumber();      // ~80% of the half-heights
        var line = s(31) > (hX * 0.85).toNumber() ? s(31) : (hX * 0.85).toNumber();

        var f1 = _f1;
        var f2 = _f2;
        var f3 = _f3;
        var t1 = inlineField(f1, data);
        var t2 = inlineField(f2, data);
        var joined = t1 + ((t1.length() > 0 && t2.length() > 0) ? " " : "") + t2;
        _orbitStacked = dc.getTextWidthInPixels(joined, font) > s(218);

        var yIR = s(278);
        var yMin = yIR + gapXT > s(316) ? yIR + gapXT : s(316);
        var y1 = yMin + gapXT > s(343) ? yMin + gapXT : s(343);
        var rows = _orbitStacked ? 3 : 2;
        if (f3 == $.FIELD_NONE) {
            rows -= 1;
        }
        var yLast = y1 + line * (rows - 1);
        var limit = _cy * 2 - s(30) - (hX * 0.4).toNumber();

        var lift = yLast - limit;
        var maxLift = yIR - (s(250) + (hX * 0.45).toNumber());   // keep clear of the grid
        if (lift > maxLift) {
            lift = maxLift;
        }
        if (lift > 0) {
            yIR -= lift;
            yMin -= lift;
            y1 -= lift;
        }
        _rowY = [y1, y1 + line, y1 + line * 2];
        _rowH = line;

        // "+" field; one column lights up per second like a scan. Rows end
        // at y 244 so taller translated text (W ZASIĘGU) has room below.
        var scan = clock.sec % 6;
        var lim = s(200) * s(200);
        dc.setPenWidth(s(2));
        for (var c = 0; c < 6; c++) {
            var gx = s(252 + c * 32);
            for (var r = 0; r < 4; r++) {
                var gy = s(166 + r * 26);
                var dx = gx - _cx;
                var dy = gy - _cy;
                if (dx * dx + dy * dy < lim) {
                    dc.setColor(c == scan ? _main : _dim, Graphics.COLOR_TRANSPARENT);
                    dc.drawLine(gx - s(5), gy, gx + s(5), gy);
                    dc.drawLine(gx, gy - s(5), gx, gy + s(5));
                }
            }
        }

        // countdown
        var minsLeft = 60 - clock.min;
        var minText = locked ? txt(:now) : Lang.format(txt(:min), [minsLeft]);
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        // a long caption (IN REICHWEITE) is nudged right so it keeps a clear
        // gap to the planet's edge
        var irX = s(290);
        var irDy = yIR - _cy;
        var irMin = (_cx - s($.PLANET_OFFSET)) + Math.sqrt(pr * pr - irDy * irDy).toNumber() + s(18)
                    + dc.getTextWidthInPixels(txt(:inRange), font) / 2;
        if (irX < irMin) {
            irX = irMin;
        }
        dc.drawText(irX, yIR, font, txt(:inRange), just);
        dc.setColor(locked || minsLeft <= 5 ? _accent : _main, Graphics.COLOR_TRANSPARENT);
        // a long word (French MAINTENANT) would run into the planet at this
        // size, so it drops to the smaller font and keeps a gap to the edge
        var minFont = Graphics.FONT_TINY;
        var minDy = yMin - _cy;
        var minRim = (_cx - s($.PLANET_OFFSET)) + Math.sqrt(pr * pr - minDy * minDy).toNumber() + s(18);
        if (s(290) - dc.getTextWidthInPixels(minText, minFont) / 2 < minRim) {
            minFont = font;
        }
        var minX = s(290);
        var minLeft = minRim + dc.getTextWidthInPixels(minText, minFont) / 2;
        if (minX < minLeft) {
            minX = minLeft;
        }
        dc.drawText(minX, yMin, minFont, minText, just);

        // fields 1 and 2 share a line when it fits between the planet and the
        // screen edge; otherwise each gets its own line. Field 3 goes last.
        var c1 = fieldColor(f1, data);
        var c2 = fieldColor(f2, data);
        var y = y1 + line;
        if (_orbitStacked) {
            var tx1 = orbitTextX(dc, t1, font, s(292), y1);
            var tx2 = orbitTextX(dc, t2, font, s(285), y1 + line);
            dc.setColor(c1, Graphics.COLOR_TRANSPARENT);
            dc.drawText(tx1, y1, font, t1, just);
            dc.setColor(c2, Graphics.COLOR_TRANSPARENT);
            dc.drawText(tx2, y1 + line, font, t2, just);
            y = y1 + line * 2;
        } else {
            var xj = orbitTextX(dc, joined, font, s(305), y1);
            if (c1 == c2) {
                dc.setColor(c1, Graphics.COLOR_TRANSPARENT);
                dc.drawText(xj, y1, font, joined, just);
            } else {
                // two colours on one line: draw each half from its own end
                var jw = dc.getTextWidthInPixels(joined, font);
                var jx = xj - jw / 2;
                dc.setColor(c1, Graphics.COLOR_TRANSPARENT);
                dc.drawText(jx, y1, font, t1, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
                dc.setColor(c2, Graphics.COLOR_TRANSPARENT);
                dc.drawText(jx + jw, y1, font, t2, Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
            }
        }
        if (f3 != $.FIELD_NONE) {
            var v3 = fieldValue(f3, data, true);
            var t3 = Lang.format(txt(:f3), [v3, fieldLongLabel(f3)]);
            var tx3 = orbitTextX(dc, t3, font, _orbitStacked ? s(280) : s(292), y);
            dc.setColor(fieldColor(f3, data), Graphics.COLOR_TRANSPARENT);
            dc.drawText(tx3, y, font, t3, just);
        }
    }

    // "HR 62" style text, or "" for FIELD_NONE.
    // Centre x for a line of orbit-style text: its usual spot, moved left if
    // the right end would cross the round screen edge (checked at the line's
    // top and bottom, where the circle is narrower), but never into the planet.
    private function orbitTextX(dc as Dc, text as String, font as Graphics.FontDefinition, pref as Number, y as Number) as Number {
        var w = dc.getTextWidthInPixels(text, font);
        var h = dc.getFontHeight(font) * 4 / 10;      // visible half-height of the glyphs
        var dy = y - _cy;
        if (dy < 0) {
            dy = -dy;
        }
        var far = dy + h;                             // the narrower of top / bottom edge
        var r = _cx - s(6);
        var half = far < r ? Math.sqrt(r * r - far * far).toNumber() : 0;
        var x = pref;
        if (x + w / 2 > _cx + half) {
            x = _cx + half - w / 2;
        }
        // planet rim at this height, plus a small gap
        var pdy = y - _cy;
        var pr = s(400);
        var rim = (_cx - s($.PLANET_OFFSET)) + Math.sqrt(pr * pr - pdy * pdy).toNumber() + s(6);
        if (x - w / 2 < rim) {
            x = rim + w / 2;
        }
        return x;
    }

    private function inlineField(type as Number, data as Dictionary) as String {
        if (type == $.FIELD_NONE) {
            return "";
        }
        return fieldLabel(type) + " " + fieldValue(type, data, true);
    }

    // Hollow wireframe sphere: nothing is filled, so whatever is behind it
    // (the planet) shows through. The real moon phase is shown by a thick
    // lit limb and a thin terminator curve; the meridian ellipse narrows and
    // widens with the seconds.
    private function drawGlobe(dc as Dc, x as Numeric, y as Numeric, r as Number, sec as Number) as Void {
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        dc.drawCircle(x, y, r);

        var c = Math.cos(sec * Math.PI / 10.0);
        if (c < 0) {
            c = -c;
        }
        var a = (r * c).toNumber();
        if (a < 1) {
            a = 1;
        }
        dc.drawEllipse(x, y, a, r);
        dc.drawLine(x, y - r, x, y + r);
        dc.drawLine(x - r, y, x + r, y);
        var half = r * 0.866;
        dc.drawLine(x - half, y - r / 2, x + half, y - r / 2);
        dc.drawLine(x - half, y + r / 2, x + half, y + r / 2);

        // moon phase
        var k = Math.cos(2 * Math.PI * _moonPhase);
        var lit = (1.0 - k) / 2.0;                       // 0 new .. 1 full
        if (lit > 0.97) {
            dc.setPenWidth(s(4));
            dc.drawCircle(x, y, r);
        } else if (lit > 0.03) {
            var side = _moonPhase < 0.5 ? 1 : -1;        // waxing lit on the right
            dc.setPenWidth(s(4));
            if (side > 0) {
                dc.drawArc(x, y, r, Graphics.ARC_COUNTER_CLOCKWISE, 270, 90);
            } else {
                dc.drawArc(x, y, r, Graphics.ARC_COUNTER_CLOCKWISE, 90, 270);
            }
            dc.setPenWidth(s(2));
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            var prevX = x;
            var prevY = y - r;
            for (var i = 1; i <= 8; i++) {
                var th = -Math.PI / 2 + Math.PI * i / 8.0;
                var nx = x + side * k * r * Math.cos(th);
                var ny = y + r * Math.sin(th);
                dc.drawLine(prevX, prevY, nx, ny);
                prevX = nx;
                prevY = ny;
            }
        }
    }

    // ----------------------------------------------------- targeting style

    private function drawTargeting(dc as Dc, clock as System.ClockTime, data as Dictionary) as Void {
        var vx = _cx;                 // vanishing point
        var vy = _cy + s(2);
        var left = s(128);
        var right = _w - s(128);
        var top = s(142);
        var bottom = s(318);

        if (_crt) {
            // glow under the trench outline
            dc.setPenWidth(s(8));
            dc.setColor($.shade(_main, 0.25), Graphics.COLOR_TRANSPARENT);
            drawTrenchRails(dc, vx, vy, left, top, right, bottom);
            drawTrenchSection(dc, vx, vy, left, top, right, bottom, 1.0);
        }

        // trench cross-sections rushing toward you (one step per second),
        // with short panel lines on the floor and walls between them. The
        // panel pattern is keyed to the section, so it travels with it.
        var phase = (clock.sec % 4) / 4.0;
        var cycle = (clock.min * 60 + clock.sec) / 4;
        var floorU = [12, 46, 82,  22, 58, 90,  34, 70, 16,  28, 52, 76];   // % across the floor
        var wallV = [20, 60,  40, 80,  30, 70,  20, 80];                    // % down the walls
        var segA = [0.15, 0.30, 0.10];                                      // where each floor line starts ...
        var segB = [0.70, 0.90, 0.60];                                      // ... and ends, between two sections
        dc.setPenWidth(s(2));
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        var ka = 1.0;
        for (var i = 0; i < 6; i++) {
            var z = i + 1.0 - phase;
            var f = 1.0 / (1.0 + z * 0.8);
            drawTrenchSection(dc, vx, vy, left, top, right, bottom, f);
            var pat = (i + cycle) % 4;
            for (var q = 0; q < 3; q++) {
                var fx = left + (right - left) * (floorU[pat * 3 + q] as Number) / 100;
                var k1 = ka - (ka - f) * (segA[q] as Float);
                var k2 = ka - (ka - f) * (segB[q] as Float);
                dc.drawLine(vx + (fx - vx) * k1, vy + (bottom - vy) * k1, vx + (fx - vx) * k2, vy + (bottom - vy) * k2);
            }
            for (var q2 = 0; q2 < 2; q2++) {
                var wy = top + (bottom - top) * (wallV[pat * 2 + q2] as Number) / 100;
                var pk1 = ka - (ka - f) * 0.2;
                var pk2 = ka - (ka - f) * 0.75;
                dc.drawLine(vx + (left - vx) * pk1, vy + (wy - vy) * pk1, vx + (left - vx) * pk2, vy + (wy - vy) * pk2);
                dc.drawLine(vx + (right - vx) * pk1, vy + (wy - vy) * pk1, vx + (right - vx) * pk2, vy + (wy - vy) * pk2);
            }
            ka = f;
        }

        // rails from the near opening to the far end
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        drawTrenchRails(dc, vx, vy, left, top, right, bottom);
        drawTrenchSection(dc, vx, vy, left, top, right, bottom, 1.0);
        dc.drawLine(left - s(26), top, left, top);
        dc.drawLine(right, top, right + s(26), top);

        // decorative counters above the trench corners, ticking every second
        var tick = (clock.hour * 3600 + clock.min * 60 + clock.sec) % 10000;
        var tickR = (tick * 7 + 2203) % 10000;
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        drawTinyNumber(dc, left - s(40), top - s(20), tick, 4);
        drawTinyNumber(dc, right + s(2), top - s(20), tickR, 4);

        // side scales: left = step goal progress, right = battery
        // side readouts measure themselves; a side scale is left out if its
        // readout (e.g. Polish TĘTNO on a 390 px watch) would not fit beside it
        var f1 = _f1;
        var f2 = _f2;
        var w1 = stackWidth(dc, f1, data);
        var w2 = stackWidth(dc, f2, data);
        var ladL = left - s(14);
        var ladR = right + s(14);
        var innerL = ladL - s(14);
        var innerR = ladR + s(14);
        if (w1 > sideRoom(innerL, true) || w2 > sideRoom(innerR, false)) {
            // hide both scales so the face stays symmetrical
            innerL = left - s(6);
            innerR = right + s(6);
        } else {
            drawLadder(dc, ladL, top, bottom, data[:progress] as Float, 1);
            drawLadder(dc, ladR, top, bottom, (data[:battery] as Number) / 100.0, -1);
        }

        // reticle, with a pulsing burst once the goal is reached
        var steps = data[:steps] as Number;
        var goal = data[:goal] as Number;
        var remaining = goal - steps;
        if (remaining < 0) {
            remaining = 0;
        }
        var locked = (goal > 0 && remaining == 0);
        if (locked) {
            drawBurst(dc, vx, vy, clock.sec);
        }
        drawReticle(dc, vx, vy, locked);
        if (!locked && goal > 0) {
            // outer brackets close in on the reticle as the goal gets nearer
            var br = s(18) + (s(40) * (1.0 - (data[:progress] as Float))).toNumber();
            dc.setPenWidth(s(2));
            drawBrackets(dc, vx, vy, br, s(10));
        }

        // countdown: steps remaining to goal
        if (remaining > 99999) {
            remaining = 99999;
        }
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        if (!locked) {
            dc.setColor(remaining < 1000 ? _accent : _main, Graphics.COLOR_TRANSPARENT);
            var dw = s(16);
            var dh = s(28);
            var gap = s(8);
            var pen = s(3);
            dc.setPenWidth(pen);
            var px = _cx - (dw * 5 + gap * 4) / 2;
            var div = 10000;
            for (var k = 0; k < 5; k++) {
                drawDigit(dc, px, s(334), dw, dh, (remaining / div) % 10, pen);
                px += dw + gap;
                div /= 10;
            }
            dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
            // a wide caption would run into field 3's value and the
            // temperature beside it, so it drops below them
            var capY = s(388);
            if (dc.getTextWidthInPixels(txt(:toGoal), Graphics.FONT_XTINY) > s(150)) {
                capY = s(398);
            }
            dc.drawText(_cx, capY, Graphics.FONT_XTINY, txt(:toGoal), just);
        } else {
            // Goal reached: the 00000 digits are replaced by the caption, which
            // sits between field 3 and the weather - on one line if it fits,
            // otherwise split onto two (TARGET / LOCKED).
            var cap = txt(:locked);
            var f3l = _f3;
            var w3 = smallWidth(dc, f3l, data);
            var ww = dc.getTextWidthInPixels(tempText(), Graphics.FONT_XTINY);
            if (ww < s(26)) {
                ww = s(26);
            }
            var leftEdge = (w3 > 0 ? targetField3X(dc, f3l, data) + w3 / 2 : s(60)) + s(8);
            var rightEdge = (_temp != null ? s(344) - ww / 2 : _w - s(60)) - s(8);
            var avail = rightEdge - leftEdge;
            var cx = (leftEdge + rightEdge) / 2;
            var hX = dc.getFontHeight(Graphics.FONT_XTINY);
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            var sp = cap.find(" ");
            if (dc.getTextWidthInPixels(cap, Graphics.FONT_XTINY) <= avail || sp == null) {
                dc.drawText(cx, s(356), Graphics.FONT_XTINY, cap, just);
            } else {
                var line = (hX * 0.85).toNumber();
                dc.drawText(cx, s(356) - line / 2, Graphics.FONT_XTINY, cap.substring(0, sp), just);
                dc.drawText(cx, s(356) + line / 2, Graphics.FONT_XTINY, cap.substring(sp + 1, cap.length()), just);
            }
        }

        // readouts
        drawFieldStack(dc, sideX(w1, innerL, true), vy, f1, data);
        drawFieldStack(dc, sideX(w2, innerR, false), vy, f2, data);
        // field 3 and weather sit wide of the countdown digits
        drawSmallField(dc, targetField3X(dc, _f3, data), s(354), _f3, data);
        drawWeatherStack(dc, s(344), s(354));
    }

    // U-shaped trench cross-section scaled toward the vanishing point by f.
    private function drawTrenchSection(dc as Dc, vx as Number, vy as Number, left as Number, top as Number,
                                       right as Number, bottom as Number, f as Float) as Void {
        var x0 = vx + (left - vx) * f;
        var x1 = vx + (right - vx) * f;
        var yt = vy + (top - vy) * f;
        var yb = vy + (bottom - vy) * f;
        dc.drawLine(x0, yt, x0, yb);
        dc.drawLine(x0, yb, x1, yb);
        dc.drawLine(x1, yb, x1, yt);
    }

    private function drawTrenchRails(dc as Dc, vx as Number, vy as Number, left as Number, top as Number,
                                     right as Number, bottom as Number) as Void {
        var cxs = [left, left, right, right];
        var cys = [top, bottom, bottom, top];
        for (var j = 0; j < 4; j++) {
            var x0 = cxs[j] as Number;
            var y0 = cys[j] as Number;
            dc.drawLine(x0, y0, vx + (x0 - vx) * 0.1, vy + (y0 - vy) * 0.1);
        }
    }

    // Vertical tick scale with a marker. dir = 1 ticks point right, -1 left.
    private function drawLadder(dc as Dc, x as Number, top as Number, bottom as Number,
                                value as Float, dir as Number) as Void {
        dc.setPenWidth(s(2));
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x, top, x, bottom);
        for (var i = 0; i <= 8; i++) {
            var y = top + (bottom - top) * i / 8;
            var len = (i % 4 == 0) ? s(10) : s(5);
            dc.drawLine(x, y, x + dir * len, y);
        }
        if (value > 1.0) {
            value = 1.0;
        }
        var my = bottom - (bottom - top) * value;
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([
            [x - dir * s(3), my],
            [x - dir * s(13), my - s(6)],
            [x - dir * s(13), my + s(6)]
        ]);
    }

    // Wireframe burst around the reticle; pulses with the seconds.
    private function drawBurst(dc as Dc, x as Number, y as Number, sec as Number) as Void {
        var pulse = sec % 4;
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(2));
        for (var i = 0; i < 16; i++) {
            var a = i * Math.PI / 8.0 + pulse * 0.1;
            var r0 = s(24 + pulse * 6);
            var r1 = r0 + s(14 + (i % 2) * 12);
            dc.drawLine(x + r0 * Math.cos(a), y + r0 * Math.sin(a), x + r1 * Math.cos(a), y + r1 * Math.sin(a));
        }
        dc.setPenWidth(1);
        dc.drawCircle(x, y, s(20 + pulse * 16));
    }

    private function drawReticle(dc as Dc, x as Number, y as Number, locked as Boolean) as Void {
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(s(3));
        drawBrackets(dc, x, y, locked ? s(10) : s(18), s(7));
        dc.fillCircle(x, y, locked ? s(4) : s(2));
    }

    // Four corner brackets, r from the centre, in the current colour and pen.
    private function drawBrackets(dc as Dc, x as Number, y as Number, r as Number, arm as Number) as Void {
        dc.drawLine(x - r, y - r, x - r + arm, y - r);
        dc.drawLine(x - r, y - r, x - r, y - r + arm);
        dc.drawLine(x + r, y - r, x + r - arm, y - r);
        dc.drawLine(x + r, y - r, x + r, y - r + arm);
        dc.drawLine(x - r, y + r, x - r + arm, y + r);
        dc.drawLine(x - r, y + r, x - r, y + r - arm);
        dc.drawLine(x + r, y + r, x + r - arm, y + r);
        dc.drawLine(x + r, y + r, x + r, y + r - arm);
    }

    // --------------------------------------------------------- radar style
    //
    // Sweep turns once a minute. The hour blip sits on the inner ring, the
    // minute blip on the outer ring, and each unread notification shows as
    // a contact that brightens as the sweep passes over it.

    private function drawRadar(dc as Dc, clock as System.ClockTime, data as Dictionary) as Void {
        var rx = _cx;
        var ry = _cy + s(34);
        var rr = s(110);

        if (_crt) {
            var sg = clock.sec * Math.PI / 30.0;
            dc.setColor($.shade(_main, 0.22), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(8));
            dc.drawCircle(rx, ry, rr);
            dc.drawLine(rx, ry, rx + rr * Math.sin(sg), ry - rr * Math.cos(sg));
        }

        // rings, cross and bearing ticks
        dc.setPenWidth(s(2));
        dc.setColor(_dim, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(rx, ry, rr);
        dc.drawCircle(rx, ry, rr * 2 / 3);
        dc.drawCircle(rx, ry, rr / 3);
        dc.drawLine(rx - rr, ry, rx + rr, ry);
        dc.drawLine(rx, ry - rr, rx, ry + rr);
        for (var i = 0; i < 36; i++) {
            var a = i * Math.PI / 18.0;
            var len = (i % 3 == 0) ? s(9) : s(4);
            dc.drawLine(rx + rr * Math.sin(a), ry - rr * Math.cos(a),
                        rx + (rr - len) * Math.sin(a), ry - (rr - len) * Math.cos(a));
        }

        // sweep with a fading trail
        var sweepDeg = clock.sec * 6;
        for (var j = 8; j >= 0; j--) {
            var sa = (sweepDeg - j * 4) * Math.PI / 180.0;
            dc.setColor(j == 0 ? _main : $.shade(_main, 0.55 - j * 0.055), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(j == 0 ? s(3) : s(2));
            dc.drawLine(rx, ry, rx + rr * Math.sin(sa), ry - rr * Math.cos(sa));
        }

        // contacts = unread notifications (up to 8, fixed positions)
        var angles = [35, 140, 250, 300, 80, 200, 330, 110];
        var dists = [0.62, 0.32, 0.78, 0.5, 0.88, 0.55, 0.36, 0.72];
        var notifs = data[:notifs] as Number;
        var shown = notifs > 8 ? 8 : notifs;
        for (var c = 0; c < shown; c++) {
            var deg = angles[c] as Number;
            var ca = deg * Math.PI / 180.0;
            var cd = rr * (dists[c] as Float);
            var behind = (sweepDeg - deg + 360) % 360;    // degrees since the sweep passed
            var fresh = behind < 90;
            dc.setColor(fresh ? _main : _dim, Graphics.COLOR_TRANSPARENT);
            var sz = fresh ? s(7) : s(5);
            dc.fillRectangle(rx + cd * Math.sin(ca) - sz / 2, ry - cd * Math.cos(ca) - sz / 2, sz, sz);
        }

        // hour blip (inner) and minute blip (outer)
        var ha = ((clock.hour % 12) + clock.min / 60.0) * Math.PI / 6.0;
        dc.setColor(_main, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(rx + rr * 0.45 * Math.sin(ha), ry - rr * 0.45 * Math.cos(ha), s(6));
        var ma = (clock.min + clock.sec / 60.0) * Math.PI / 30.0;
        var mx = rx + rr * 0.82 * Math.sin(ma);
        var my = ry - rr * 0.82 * Math.cos(ma);
        dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(mx, my, s(4));
        dc.setPenWidth(s(2));
        dc.drawCircle(mx, my, s(9));

        // contact count
        dc.setColor(notifs > 0 ? _accent : _main, Graphics.COLOR_TRANSPARENT);
        var label = contactsText(notifs);
        dc.drawText(_cx, s(394), Graphics.FONT_XTINY, label,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // readouts
        var rf1 = _f1;
        var rf2 = _f2;
        drawFieldStack(dc, sideX(stackWidth(dc, rf1, data), rx - rr - s(4), true), ry, rf1, data);
        drawFieldStack(dc, sideX(stackWidth(dc, rf2, data), rx + rr + s(4), false), ry, rf2, data);
        // field 3 and weather sit wide of the radar ring: each is measured and
        // slid outward if its top corner would touch the ring
        var f3 = _f3;
        var by = s(350);
        var hX = dc.getFontHeight(Graphics.FONT_XTINY);
        var topY = by - s(12) - hX / 2;
        var ddy = topY - ry;
        var reach = rr * rr - ddy * ddy;
        var ringHalf = reach > 0 ? Math.sqrt(reach).toNumber() : 0;
        var botY = by + s(14) + hX / 2;
        var cdy = botY - _cy;
        var chord = _cx * _cx - cdy * cdy;
        var chordHalf = chord > 0 ? Math.sqrt(chord).toNumber() : 0;

        var w3 = smallWidth(dc, f3, data);
        var x3 = s(100);
        if (x3 + w3 / 2 > rx - ringHalf - s(8)) {
            x3 = rx - ringHalf - s(8) - w3 / 2;
        }
        if (x3 - w3 / 2 < _cx - chordHalf + s(4)) {
            x3 = _cx - chordHalf + s(4) + w3 / 2;
        }
        var ww = dc.getTextWidthInPixels(tempText(), Graphics.FONT_XTINY);
        if (ww < s(26)) {
            ww = s(26);
        }
        var xw = s(354);
        if (xw - ww / 2 < rx + ringHalf + s(8)) {
            xw = rx + ringHalf + s(8) + ww / 2;
        }
        if (xw + ww / 2 > _cx + chordHalf - s(4)) {
            xw = _cx + chordHalf - s(4) - ww / 2;
        }
        _radarBottomX = [x3, xw];
        drawSmallField(dc, x3, by, f3, data);
        drawWeatherStack(dc, xw, by);
    }

    // ------------------------------------------------------ always-on mode

    // Thin digits plus outlines of the current style, all nudged a few pixels
    // sideways and up/down every minute (25 positions) to avoid burn-in. Outlines are full-colour 2-3 px lines;
    // the total stays around 2% lit pixels, far below the 10% AMOLED limit.
    private function drawAlwaysOn(dc as Dc, clock as System.ClockTime, style as Number) as Void {
        var dx = (((clock.min % 5) - 2) * 6 * _k).toNumber();
        var dy = ((((clock.min * 2 + clock.min / 5) % 5) - 2) * 6 * _k).toNumber();
        var line = $.shade(_main, 0.85);
        dc.setPenWidth(s(2));

        if (style == 0) {
            var px = _cx - s($.PLANET_OFFSET) + dx;
            var py = _cy + dy;
            var pr = s(400);
            // planet edge
            dc.setColor($.shade(_planetRim, 0.75), Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(3));
            dc.drawCircle(px, py, pr);
            // dotted track
            dc.setColor($.shade(_main, 0.6), Graphics.COLOR_TRANSPARENT);
            for (var i = 0; i <= 12; i++) {
                dc.fillCircle(moonX(i / 12.0) + dx, _cy + dy, s(1) + 1);
            }
            // moon ring with cross-hairs
            var mx = moonX(clock.min == 0 ? 1.0 : (clock.min - 1) / 59.0) + dx;
            var my = _cy + dy;
            var mr = s(16);
            dc.setColor(line, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(s(2));
            dc.drawCircle(mx, my, mr);
            dc.drawLine(mx - mr, my, mx + mr, my);
            dc.drawLine(mx, my - mr, mx, my + mr);
            drawTime(dc, clock, s(304) + dx, _cy - s(26) + dy, s(26), s(52), s(2), false);
        } else if (style == 1) {
            dc.setColor(line, Graphics.COLOR_TRANSPARENT);
            var vx = _cx + dx;
            var vy = _cy + s(2) + dy;
            var left = s(128) + dx;
            var right = _w - s(128) + dx;
            var top = s(142) + dy;
            var bottom = s(318) + dy;
            drawTrenchRails(dc, vx, vy, left, top, right, bottom);
            drawTrenchSection(dc, vx, vy, left, top, right, bottom, 1.0);
            drawTime(dc, clock, _cx + dx, s(64) + dy, s(30), s(52), s(2), false);
        } else {
            dc.setColor(line, Graphics.COLOR_TRANSPARENT);
            var rx = _cx + dx;
            var ry = _cy + s(34) + dy;
            dc.drawCircle(rx, ry, s(110));
            dc.drawCircle(rx, ry, s(55));
            // minute blip on the outer ring
            var ma = clock.min * Math.PI / 30.0;
            dc.setColor(_accent, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(rx + s(90) * Math.sin(ma), ry - s(90) * Math.cos(ma), s(5));
            drawTime(dc, clock, _cx + dx, s(64) + dy, s(30), s(52), s(2), false);
        }
    }
}
