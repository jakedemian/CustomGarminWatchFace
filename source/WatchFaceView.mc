import Toybox.ActivityMonitor;
import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

class WatchFaceView extends WatchUi.WatchFace {

    // Trailing tracking baked into each glyph's xadvance by tools/gen_font.py.
    const TIME_TRACKING = 4;
    // Space between the hours and minutes groups (no colon).
    const TIME_GAP = 12;
    const ACCENT = 0xFF0000;
    const STEPS_COLOR = 0x00C8A0;

    // Always-on mode: drift everything a few pixels each minute so no pixel stays lit.
    const BURN_IN_SHIFTS = [[0, 0], [3, 0], [3, 3], [0, 3], [-3, 3], [-3, 0], [-3, -3], [0, -3], [3, -3]];

    private var _hoursFont as WatchUi.FontResource?;
    private var _minutesFont as WatchUi.FontResource?;
    // Below FONT_XTINY (~31px on fr970); vector fonts allow arbitrary pixel sizes.
    const BATTERY_FONT_PX = 27;
    private var _batteryFont as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_XTINY;
    // A hair below FONT_SMALL (~45px on fr970).
    const DATE_FONT_PX = 41;
    private var _dateFont as Graphics.VectorFont or Graphics.FontDefinition = Graphics.FONT_SMALL;
    private var _sleeping as Boolean = false;
    private var _burnInProtection as Boolean = false;

    function initialize() {
        WatchFace.initialize();
        var settings = System.getDeviceSettings();
        _burnInProtection = (settings has :requiresBurnInProtection) && settings.requiresBurnInProtection;
    }

    function onLayout(dc as Dc) as Void {
        _hoursFont = WatchUi.loadResource(Rez.Fonts.TimeHours) as WatchUi.FontResource;
        _minutesFont = WatchUi.loadResource(Rez.Fonts.TimeMinutes) as WatchUi.FontResource;
        var batteryFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => BATTERY_FONT_PX});
        if (batteryFont != null) {
            _batteryFont = batteryFont;
        }
        var dateFont = Graphics.getVectorFont({:face => "RobotoRegular", :size => DATE_FONT_PX});
        if (dateFont != null) {
            _dateFont = dateFont;
        }
    }

    function onUpdate(dc as Dc) as Void {
        var lowPower = _sleeping && _burnInProtection;
        var clock = System.getClockTime();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        if (lowPower) {
            var shift = BURN_IN_SHIFTS[clock.min % BURN_IN_SHIFTS.size()];
            cx += shift[0];
            cy += shift[1];
        }

        // Always-on palette stays dim and avoids white to keep luminance well under 10%.
        var primary = lowPower ? 0x666666 : Graphics.COLOR_WHITE;
        var secondary = lowPower ? 0x444444 : Graphics.COLOR_LT_GRAY;
        var accent = lowPower ? 0x660000 : ACCENT;
        var stepsColor = lowPower ? 0x00503F : STEPS_COLOR;

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        dc.setAntiAlias(true);

        drawTime(dc, cx, cy, clock, primary);

        drawBattery(dc, cx, cy - 175, secondary);
        drawDate(dc, cx, cy - 132, secondary, accent);

        drawFields(dc, cx, cy + 115, primary, accent, stepsColor);
    }

    // Hours (heavier) and minutes (thin) side by side, centered on cx by ink width.
    private function drawTime(dc as Dc, cx as Number, cy as Number, clock as System.ClockTime, color as Number) as Void {
        var hour = clock.hour % 12;
        if (hour == 0) {
            hour = 12;
        }
        var hours = hour.toString();
        var minutes = clock.min.format("%02d");
        var hoursFont = _hoursFont as WatchUi.FontResource;
        var minutesFont = _minutesFont as WatchUi.FontResource;

        var hoursW = dc.getTextWidthInPixels(hours, hoursFont) - TIME_TRACKING;
        var minutesW = dc.getTextWidthInPixels(minutes, minutesFont) - TIME_TRACKING;
        var x = cx - (hoursW + TIME_GAP + minutesW) / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, hoursFont, hours, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(x + hoursW + TIME_GAP, cy, minutesFont, minutes, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // HR above steps. Each row (icon + value) is centered on cx independently.
    private function drawFields(dc as Dc, cx as Number, top as Number, textColor as Number, heartColor as Number, stepsColor as Number) as Void {
        var rowGap = 42;
        drawFieldRow(dc, cx, top, :heart, heartRateText(), textColor, heartColor);
        drawFieldRow(dc, cx, top + rowGap, :steps, stepsText(), textColor, stepsColor);
    }

    private function drawFieldRow(dc as Dc, cx as Number, cy as Number, icon as Symbol, value as String, textColor as Number, iconColor as Number) as Void {
        var font = Graphics.FONT_SMALL;
        var iconW = 22;
        var spacing = 8;
        var left = cx - (iconW + spacing + dc.getTextWidthInPixels(value, font)) / 2;

        dc.setColor(iconColor, Graphics.COLOR_TRANSPARENT);
        if (icon == :heart) {
            drawHeart(dc, left + iconW / 2, cy);
        } else {
            drawSteps(dc, left + iconW / 2, cy);
        }

        dc.setColor(textColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left + iconW + spacing, cy, font, value, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawHeart(dc as Dc, x as Number, y as Number) as Void {
        var r = 5;
        dc.fillCircle(x - r, y - 3, r + 1);
        dc.fillCircle(x + r, y - 3, r + 1);
        dc.fillPolygon([[x - 2 * r - 1, y - 1], [x + 2 * r + 1, y - 1], [x, y + 2 * r]]);
    }

    private function drawSteps(dc as Dc, x as Number, y as Number) as Void {
        // Two offset footprints: sole ellipse + heel dot.
        dc.fillEllipse(x - 5, y - 1, 4, 7);
        dc.fillCircle(x - 5, y + 9, 3);
        dc.fillEllipse(x + 5, y - 7, 4, 7);
        dc.fillCircle(x + 5, y + 3, 3);
    }

    // Battery outline with proportional fill, then the %, centered as a group on cx.
    private function drawBattery(dc as Dc, cx as Number, cy as Number, color as Number) as Void {
        var pct = System.getSystemStats().battery;
        var text = pct.format("%d") + "%";
        var font = _batteryFont;
        var bodyW = 30;
        var bodyH = 14;
        var nubW = 3;
        var spacing = 8;
        var left = cx - (bodyW + nubW + spacing + dc.getTextWidthInPixels(text, font)) / 2;
        var top = cy - bodyH / 2;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        dc.drawRoundedRectangle(left, top, bodyW, bodyH, 3);
        dc.fillRectangle(left + bodyW, cy - 3, nubW, 6);
        var fillW = ((bodyW - 6) * pct / 100).toNumber();
        if (fillW > 0) {
            dc.fillRectangle(left + 3, top + 3, fillW, bodyH - 6);
        }
        dc.drawText(left + bodyW + nubW + spacing, cy, font, text, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // "SAT   OCT 10": weekday, wider gap, then month (accent) + day grouped together.
    private function drawDate(dc as Dc, cx as Number, cy as Number, color as Number, monthColor as Number) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var font = _dateFont;
        var weekday = (info.day_of_week as String).toUpper();
        var month = (info.month as String).toUpper();
        var day = " " + info.day.toString();
        var groupGap = 22;

        var weekdayW = dc.getTextWidthInPixels(weekday, font);
        var monthW = dc.getTextWidthInPixels(month, font);
        var dayW = dc.getTextWidthInPixels(day, font);
        var x = cx - (weekdayW + groupGap + monthW + dayW) / 2;
        var justify = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, font, weekday, justify);
        x += weekdayW + groupGap;
        dc.setColor(monthColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, cy, font, month, justify);
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + monthW, cy, font, day, justify);
    }

    private function heartRateText() as String {
        var hr = null;
        var info = Activity.getActivityInfo();
        if (info != null) {
            hr = info.currentHeartRate;
        }
        if (hr == null) {
            var sample = ActivityMonitor.getHeartRateHistory(1, true).next();
            if (sample != null && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                hr = sample.heartRate;
            }
        }
        return hr == null ? "--" : hr.toString();
    }

    private function stepsText() as String {
        var steps = ActivityMonitor.getInfo().steps;
        if (steps == null) {
            return "--";
        }
        var s = steps.toString();
        var out = "";
        var len = s.length();
        for (var i = 0; i < len; i++) {
            if (i > 0 && (len - i) % 3 == 0) {
                out += ",";
            }
            out += s.substring(i, i + 1);
        }
        return out;
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }
}
