local translations = { en="avrLiX", de="avrLiX" }

local function name(widget)
    local locale = system.getLocale()
    return translations[locale] or translations.en
end

local function create()
    return {
        sourceValue = 0,
        avgCellVoltage = nil,
        repeatReading = false,
        lowAlarmCallout = false,
        criticalAlarmCallout = false,
        timeReadout = 0,
        timeLowAlarmReadout = 0,
        timeCriticalAlarmReadout = 0,
        lastTimeAlarmCheck = 0
    }
end

local function round(num, dp)
    local mult = 10^(dp or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- =========================
-- PAINT
-- =========================
local function paint(widget)
    if not widget.voltageSource then
    return
end
if not widget.avgCellVoltage then
    lcd.drawText(5, 5, "No telemetry", FONT_S)
    return
end

    local w, h = lcd.getWindowSize()

    if h < 50 then
        lcd.font(FONT_S)
    elseif h < 80 then
        lcd.font(FONT_L)
    elseif h > 170 then
        lcd.font(FONT_XL)
    else
        lcd.font(FONT_STD)
    end

    local _, text_h = lcd.getTextSize("")
    local box_top, box_height = text_h, h - text_h - 4
    local box_left, box_width = 4, w - 8

    lcd.drawText(box_left, 0, widget.voltageSource:name())
    lcd.drawText(box_left + box_width, 0, widget.voltageSource:stringValue(), RIGHT)

    local remaining =
        (widget.avgCellVoltage - widget.minCellVoltage) /
        (widget.maxCellVoltage - widget.minCellVoltage)

    remaining = math.max(0, math.min(1, remaining))

    lcd.color(lcd.RGB(200,200,200))
    lcd.drawFilledRectangle(box_left, box_top, box_width, box_height)

    if widget.avgCellVoltage >= widget.lowAlarmVoltage then
        lcd.color(GREEN)
    elseif widget.avgCellVoltage >= widget.criticalAlarmVoltage then
        lcd.color(YELLOW)
    else
        lcd.color(RED)
    end

    lcd.drawFilledRectangle(
        box_left,
        box_top,
        (box_width - 2) * remaining + 2,
        box_height
    )

    lcd.color(BLACK)
    lcd.font(FONT_L)

    local unit = system.getLocale() == "de" and " V/Zelle" or " V/Cell"
    lcd.drawText(
        box_left + box_width / 2,
        box_top + (box_height - text_h) / 2,
        round(widget.avgCellVoltage, 2) .. unit,
        CENTERED
    )
end

-- =========================
-- WAKEUP
-- =========================
local function wakeup(widget)
    local now = os.time()
    local numCell = widget.numberCells or 1

    -- === TELEMETRIA PORTTI ===
    if not widget.voltageSource then
        widget.avgCellVoltage = nil
        widget.lowAlarmCallout = false
        widget.criticalAlarmCallout = false
        return
    end

    local v = widget.voltageSource:value()
    if not v or v <= 0 then
        widget.avgCellVoltage = nil
        widget.lowAlarmCallout = false
        widget.criticalAlarmCallout = false
        lcd.invalidate()

        return
    end

    local prev = widget.sourceValue

    widget.sourceValue = v
    widget.avgCellVoltage = v / numCell

    if prev ~= v then
    lcd.invalidate()
end

    -- === CALLOUT SWITCH ===
    local sw = widget.calloutSwitch
    if sw and sw:state() then
        if widget.repeatReading then
            system.playNumber(widget.avgCellVoltage, UNIT_VOLT, 2)
            widget.repeatReading = false
        end
        if (now - widget.timeReadout) > widget.repeatSeconds then
            widget.timeReadout = now
            widget.repeatReading = true
        end
    else
        widget.repeatReading = true
        widget.timeReadout = now
    end

    -- === RESET ALARM LATCH ===
    if (now - widget.lastTimeAlarmCheck) >= 6 then
    widget.lowAlarmCallout = false
    widget.criticalAlarmCallout = false
    widget.lastTimeAlarmCheck = now
    end


    -- === LOW ALARM ===
    if widget.avgCellVoltage <= widget.lowAlarmVoltage
        and widget.avgCellVoltage > widget.criticalAlarmVoltage
        and not widget.lowAlarmCallout
    then
        if (now - widget.timeLowAlarmReadout) >= widget.waitSecondsLowAlarm then
            system.playHaptic("- . -")
            widget.lowAlarmCallout = true
            widget.lastTimeAlarmCheck = now
        end
    elseif widget.avgCellVoltage > widget.lowAlarmVoltage then
        widget.lowAlarmCallout = false
        widget.timeLowAlarmReadout = now
    end

    -- === CRITICAL ALARM ===
    if widget.avgCellVoltage <= widget.criticalAlarmVoltage
        and not widget.criticalAlarmCallout
    then
        if (now - widget.timeCriticalAlarmReadout) >= widget.waitSecondsCriticalAlarm then
            system.playHaptic("-.-.-")
            widget.criticalAlarmCallout = true
            widget.lastTimeAlarmCheck = now
        end
    elseif widget.avgCellVoltage > widget.criticalAlarmVoltage then
        widget.criticalAlarmCallout = false
        widget.timeCriticalAlarmReadout = now
    end
end

-- =========================
-- CONFIGURE
-- =========================
local function configure(widget)
    local line, r, field

    line = form.addLine("Source")
    form.addSourceField(line, nil,
        function() return widget.voltageSource end,
        function(v) widget.voltageSource = v end
    )

    line = form.addLine("Callout Switch / Repeat")
    r = form.getFieldSlots(line, {0,0})
    form.addSwitchField(line, r[1],
        function() return widget.calloutSwitch end,
        function(v) widget.calloutSwitch = v end
    )
    field = form.addNumberField(line, r[2], 0, 60,
        function() return widget.repeatSeconds end,
        function(v) widget.repeatSeconds = v end
    )
    field:suffix(" s")
    field:default(30)

    line = form.addLine("Number Cells")
    field = form.addNumberField(line, nil, 1, 20,
        function() return widget.numberCells end,
        function(v) widget.numberCells = v end
    )
    field:suffix(" Cells")
    field:default(1)

    line = form.addLine("min / max Voltage")
    r = form.getFieldSlots(line, {0,0})
    field = form.addNumberField(line, r[1], 10, 50,
        function() return widget.minCellVoltage * 10 end,
        function(v) widget.minCellVoltage = v / 10 end
    )
    field:suffix(" V")
    field:decimals(1)
    field:default(33)

    field = form.addNumberField(line, r[2], 10, 50,
        function() return widget.maxCellVoltage * 10 end,
        function(v) widget.maxCellVoltage = v / 10 end
    )
    field:suffix(" V")
    field:decimals(1)
    field:default(42)

    line = form.addLine("low Alarm V / delay")
    r = form.getFieldSlots(line, {0,0})
    field = form.addNumberField(line, r[1], 10, 50,
        function() return widget.lowAlarmVoltage * 10 end,
        function(v) widget.lowAlarmVoltage = v / 10 end
    )
    field:suffix(" V")
    field:decimals(1)
    field:default(37)

    field = form.addNumberField(line, r[2], 0, 20,
        function() return widget.waitSecondsLowAlarm end,
        function(v) widget.waitSecondsLowAlarm = v end
    )
    field:suffix(" s")
    field:default(1)

    line = form.addLine("critical Alarm V / delay")
    r = form.getFieldSlots(line, {0,0})
    field = form.addNumberField(line, r[1], 10, 50,
        function() return widget.criticalAlarmVoltage * 10 end,
        function(v) widget.criticalAlarmVoltage = v / 10 end
    )
    field:suffix(" V")
    field:decimals(1)
    field:default(35)

    field = form.addNumberField(line, r[2], 0, 20,
        function() return widget.waitSecondsCriticalAlarm end,
        function(v) widget.waitSecondsCriticalAlarm = v end
    )
    field:suffix(" s")
    field:default(1)
end

-- =========================
-- STORAGE
-- =========================
local function read(widget)
    widget.calloutSwitch = storage.read("calloutswitch")
    widget.numberCells = storage.read("numbercells") or 1
    widget.minCellVoltage = storage.read("mincellvoltage") or 3.3
    widget.maxCellVoltage = storage.read("maxcellvoltage") or 4.2
    widget.voltageSource = storage.read("voltagesource")
    widget.repeatSeconds = storage.read("repeatseconds") or 30
    widget.lowAlarmVoltage = storage.read("lowalarmvoltage") or 3.7
    widget.criticalAlarmVoltage = storage.read("criticalalarmvoltage") or 3.5
    widget.waitSecondsLowAlarm = storage.read("waitsecondslowalarm") or 1
    widget.waitSecondsCriticalAlarm = storage.read("waitsecondscriticalalarm") or 1
end

local function write(widget)
    storage.write("calloutswitch", widget.calloutSwitch)
    storage.write("numbercells", widget.numberCells)
    storage.write("mincellvoltage", widget.minCellVoltage)
    storage.write("maxcellvoltage", widget.maxCellVoltage)
    storage.write("voltagesource", widget.voltageSource)
    storage.write("repeatseconds", widget.repeatSeconds)
    storage.write("lowalarmvoltage", widget.lowAlarmVoltage)
    storage.write("criticalalarmvoltage", widget.criticalAlarmVoltage)
    storage.write("waitsecondslowalarm", widget.waitSecondsLowAlarm)
    storage.write("waitsecondscriticalalarm", widget.waitSecondsCriticalAlarm)
end

local function init()
    system.registerWidget{
        key="avrvolt",
        name=name,
        create=create,
        paint=paint,
        wakeup=wakeup,
        configure=configure,
        read=read,
        write=write
    }
end

return { init=init }
