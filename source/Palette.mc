import Toybox.Lang;

// Shared colour palette. Indices are stored in the Theme / Accent / Planet
// settings, so only ever append new colours to the end of these lists.

function paletteColors() as Array<Number> {
    return [
        0x33FF66,   // 0 Green
        0xFFB000,   // 1 Amber
        0x40D8FF,   // 2 Cyan
        0xFF3B30,   // 3 Red
        0xF0F0F0,   // 4 White
        0xFF4FD8,   // 5 Magenta
        0xFFE14D,   // 6 Yellow
        0x5A8CFF,   // 7 Blue
        0xFF7A1A,   // 8 Orange
        0xA05CFF    // 9 Purple
    ];
}

function paletteNames() as Array<String> {
    return [$.str(Rez.Strings.ColorGreen), $.str(Rez.Strings.ColorAmber), $.str(Rez.Strings.ColorCyan),
            $.str(Rez.Strings.ColorRed), $.str(Rez.Strings.ColorWhite), $.str(Rez.Strings.ColorMagenta),
            $.str(Rez.Strings.ColorYellow), $.str(Rez.Strings.ColorBlue), $.str(Rez.Strings.ColorOrange),
            $.str(Rez.Strings.ColorPurple)];
}

function paletteColor(i as Number) as Number {
    var c = $.paletteColors();
    return (i >= 0 && i < c.size()) ? c[i] : c[0];
}

function colorName(i as Number) as String {
    var n = $.paletteNames();
    return (i >= 0 && i < n.size()) ? n[i] : n[0];
}

// Darker version of a colour; f = 0.0 (black) .. 1.0 (unchanged).
function shade(c as Number, f as Float) as Number {
    var r = (((c >> 16) & 0xFF) * f).toNumber();
    var g = (((c >> 8) & 0xFF) * f).toNumber();
    var b = ((c & 0xFF) * f).toNumber();
    return (r << 16) | (g << 8) | b;
}
