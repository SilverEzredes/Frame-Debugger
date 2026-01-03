--/////////////////////////////////////--
local modName =  "Frame Debugger"

local modAuthor = "SilverEzredes"
local modUpdated = "01/03/2026"
local modVersion = "v1.0.02"
local modCredits = "alphaZomega; praydog"
local modNotes = "Required _ScriptCore version: 1.2.00+"
local modChangeLog = "v1.0.02\n- UI changes\n\nv1.0.01\n - Small UI changes\n\nv1.0.00\n - Initial release"

--/////////////////////////////////////--
local func = require("_SharedCore/Functions")
local ui = require("_SharedCore/Imgui")
local hk = require("Hotkeys/Hotkeys")

local changed = false
local wc = false

local appSingelton = sdk.get_native_singleton("via.Application")
local appType = sdk.find_type_definition("via.Application")
local frameTimePeak = 0.0
local frameTimeRecord = {}
local frameDebuggerDefaultSettings = {
    maxFrameTime = 0.0,
    currFrame = 0,
    deltaTime = 0.0,
    OS = "",
    frameTimeCritical = 33.334,
    frameTimeWarningThreshold = 0.75,
    deltaTimeBaseLine = 2.0,
    historyMaxSize = 50,
    capturedFrameCount = 0,
    recordMaxSize = 100000,
    frameTimeHistory = {},
    deltaTimeHistory = {},
    isNewWindow = false,
    showFrameTime = true,
    showFrameRecord = true,
    showDeltaTime = false,
    ["isRecFrameTime"] = false,
}
local frameDebuggerSettings = hk.merge_tables({}, frameDebuggerDefaultSettings) and hk.recurse_def_settings(json.load_file("SILVER/_Debug/FrameDebuggerSettings.json") or {}, frameDebuggerDefaultSettings)

local function add_ToHistory(value, tbl, maxSize, key)
    if key then
        tbl[key] = value
    else
        table.insert(tbl, value)
    end

    if not key and #tbl > maxSize then
        table.remove(tbl, 1)
    elseif key then
        local count = 0
        for _ in pairs(tbl) do
            count = count + 1
        end
        if count > maxSize then
            local oldestKey = nil
            for k in pairs(tbl) do
                if not oldestKey or k < oldestKey then
                    oldestKey = k
                end
            end
            tbl[oldestKey] = nil
        end
    end
end
local function lua_TableToCSV(tbl)
    local csv = {}

    local keys = {}
    for key, _ in pairs(tbl) do
        table.insert(keys, key)
    end
    table.insert(csv, table.concat(keys, ","))

    local values = {}
    for _, value in pairs(tbl) do
        table.insert(values, value)
    end
    table.insert(csv, table.concat(values, ","))

    return csv
end
local function get_GameAppData()
    if appSingelton == nil then return end
    frameDebuggerSettings.maxFrameTime = sdk.call_native_func(appSingelton, appType, "get_FrameTimeMillisecond")
    add_ToHistory(frameDebuggerSettings.maxFrameTime, frameDebuggerSettings.frameTimeHistory, frameDebuggerSettings.historyMaxSize)

    frameDebuggerSettings.deltaTime = sdk.call_native_func(appSingelton, appType, "get_DeltaTime")
    add_ToHistory(frameDebuggerSettings.deltaTime, frameDebuggerSettings.deltaTimeHistory, frameDebuggerSettings.historyMaxSize)

    frameDebuggerSettings.currFrame = sdk.call_native_func(appSingelton, appType, "get_FrameCount")
    frameDebuggerSettings.OS = sdk.call_native_func(appSingelton, appType, "get_OperatingSystemDesc")
end
local function record_FrameTime()
    if not frameDebuggerSettings["isRecFrameTime"] then return end

    frameDebuggerSettings.maxFrameTime = sdk.call_native_func(appSingelton, appType, "get_FrameTimeMillisecond")
    add_ToHistory(frameDebuggerSettings.maxFrameTime, frameTimeRecord, frameDebuggerSettings.recordMaxSize, frameDebuggerSettings.currFrame)
end

local function setup_FrameDebugger()
    ui.textButton_ColoredValue("OS:", frameDebuggerSettings.OS, func.convert_rgba_to_ABGR(ui.colors.cerulean))
    imgui.same_line()
    ui.textButton_ColoredValue("Current Frame:", frameDebuggerSettings.currFrame, func.convert_rgba_to_ABGR(ui.colors.gold))
    
    imgui.spacing()

    if frameDebuggerSettings.showFrameTime then
        if frameDebuggerSettings.maxFrameTime >= frameDebuggerSettings.frameTimeCritical * frameDebuggerSettings.frameTimeWarningThreshold then
            ui.progressBar_DynamicColor(string.format("Frame Time: %.3fms", frameDebuggerSettings.maxFrameTime), false, 0, func.convert_rgba_to_ABGR(ui.colors.white), func.convert_rgba_to_ABGR(ui.colors.red), func.convert_rgba_to_ABGR(ui.colors.orange), func.convert_rgba_to_ABGR(ui.colors.REFgray), frameDebuggerSettings.frameTimeCritical, frameDebuggerSettings.maxFrameTime, 100.0, 300.0, 5.0)
        else
            ui.progressBar_DynamicColor(string.format("Frame Time: %.3fms", frameDebuggerSettings.maxFrameTime), false, 0, func.convert_rgba_to_ABGR(ui.colors.white), func.convert_rgba_to_ABGR(ui.colors.red), func.convert_rgba_to_ABGR(ui.colors.green), func.convert_rgba_to_ABGR(ui.colors.REFgray), frameDebuggerSettings.frameTimeCritical, frameDebuggerSettings.maxFrameTime, 100.0, 300.0, 5.0)
        end
        if frameDebuggerSettings.maxFrameTime >= 100.0 then
            frameTimePeak = frameDebuggerSettings.maxFrameTime
        end
        
        imgui.text(string.format("Last Major Peak: %.3fms", frameTimePeak))
        
        if frameDebuggerSettings.showFrameRecord then
            ui.button_CheckboxStyle("[ REC ]", frameDebuggerSettings, "isRecFrameTime", func.convert_rgba_to_ABGR(ui.colors.REFgray), func.convert_rgba_to_ABGR(ui.colors.deepRed), func.convert_rgba_to_ABGR(ui.colors.deepRed))
            
            imgui.same_line()
            frameDebuggerSettings.capturedFrameCount = func.get_table_size(frameTimeRecord)
            ui.textButton_ColoredValue("Captured Frame Count: ", frameDebuggerSettings.capturedFrameCount, func.convert_rgba_to_ABGR(ui.colors.deepRed))
            if imgui.button("Clear Captured Frames") then
                frameTimeRecord = {}
            end
            imgui.same_line()
            if imgui.button("Save Recording") then
                json.dump_file("SILVER/_Debug/FrameTime/frameTimeREC.json", lua_TableToCSV(frameTimeRecord))
            end
        end

        if imgui.tree_node("Frame Time History") then
            imgui.indent(-20)
            for i = #frameDebuggerSettings.frameTimeHistory, 1, -1 do
                local frameTime = frameDebuggerSettings.frameTimeHistory[i]
                if frameTime >= frameDebuggerSettings.frameTimeCritical * frameDebuggerSettings.frameTimeWarningThreshold then
                    ui.progressBar_DynamicColor(string.format("%d Frame Time: %.3fms", i, frameTime), false, 0, func.convert_rgba_to_ABGR(ui.colors.white), func.convert_rgba_to_ABGR(ui.colors.red), func.convert_rgba_to_ABGR(ui.colors.orange), func.convert_rgba_to_ABGR(ui.colors.REFgray), frameDebuggerSettings.frameTimeCritical, frameTime, 100.0, 300.0, 5.0, true)
                else
                    ui.progressBar_DynamicColor(string.format("%d Frame Time: %.3fms", i, frameTime), false, 0, func.convert_rgba_to_ABGR(ui.colors.white), func.convert_rgba_to_ABGR(ui.colors.red), func.convert_rgba_to_ABGR(ui.colors.green), func.convert_rgba_to_ABGR(ui.colors.REFgray), frameDebuggerSettings.frameTimeCritical, frameTime, 100.0, 300.0, 5.0, true)
                end
            end
            imgui.indent(20)
            imgui.spacing()
            imgui.tree_pop()
        end
    end
    if frameDebuggerSettings.showDeltaTime then
        ui.progressBar_DynamicColor(string.format("Delta Time: %.3fms", frameDebuggerSettings.deltaTime), false, 0, func.convert_rgba_to_ABGR(ui.colors.safetyYellow), func.convert_rgba_to_ABGR(ui.colors.red), func.convert_rgba_to_ABGR(ui.colors.green), func.convert_rgba_to_ABGR(ui.colors.REFgray), frameDebuggerSettings.deltaTimeBaseLine, frameDebuggerSettings.deltaTime, 4.0, 300.0, 5.0)
        if imgui.tree_node("Delta Time History") then
            for i = #frameDebuggerSettings.deltaTimeHistory, 1, -1 do
                local deltaT = frameDebuggerSettings.deltaTimeHistory[i]
                ui.progressBar_DynamicColor(string.format("%d Delta Time: %.3fms", i, deltaT), false, 0, func.convert_rgba_to_ABGR(ui.colors.safetyYellow), func.convert_rgba_to_ABGR(ui.colors.red), func.convert_rgba_to_ABGR(ui.colors.green), func.convert_rgba_to_ABGR(ui.colors.REFgray), frameDebuggerSettings.deltaTimeBaseLine, deltaT, 4.0, 300.0, 5.0, true)
            end
            imgui.spacing()
            imgui.tree_pop()
        end
    end
    if changed or wc then
        json.dump_file("SILVER/_Debug/FrameDebuggerSettings.json", frameDebuggerSettings)
        changed = false
        wc = false
    end
end
local function draw_FrameDebugger()
    if imgui.tree_node(modName) then
        imgui.begin_rect()
        imgui.spacing()
        imgui.indent(10)
        
        if not frameDebuggerSettings.isNewWindow then
            setup_FrameDebugger()
        end
        
        imgui.spacing()

        if imgui.tree_node("Settings") then
            imgui.begin_rect()
            imgui.spacing()
            imgui.indent(5)
            if imgui.button("Reset to Defaults") then
                wc = true
                frameDebuggerSettings = hk.recurse_def_settings({}, frameDebuggerDefaultSettings)
            end
            imgui.push_item_width(250)
            imgui.same_line()
            changed, frameDebuggerSettings.isNewWindow = imgui.checkbox("Use Separate Window", frameDebuggerSettings.isNewWindow); wc = wc or changed
            changed, frameDebuggerSettings.showFrameTime = imgui.checkbox("Show Frame Time", frameDebuggerSettings.showFrameTime); wc = wc or changed
            changed, frameDebuggerSettings.showFrameRecord = imgui.checkbox("Show Frame Recorder UI", frameDebuggerSettings.showFrameRecord); wc = wc or changed
            changed, frameDebuggerSettings.frameTimeCritical = ui.imgui_safe_input(imgui.drag_float, frameDebuggerSettings.frameTimeCritical, "Critical Frame Time", frameDebuggerSettings.frameTimeCritical, {0.001, 0.0, 100.0, "%.3fms"}); wc = wc or changed
            ui.tooltip("Frame Times higher than this value will be marked red.")
            local displayThreshold = frameDebuggerSettings.frameTimeWarningThreshold * 100
            changed, displayThreshold = ui.imgui_safe_input(imgui.drag_float, frameDebuggerSettings.frameTimeWarningThreshold, "Frame Time Warning Threshold", displayThreshold, {0.01, 0.0, 100.0, "%.1f%%"}); wc = wc or changed
            ui.tooltip("Frame Times higher than this percentage of the 'Critical Frame Time' value will be marked orange.")
            if changed then
                frameDebuggerSettings.frameTimeWarningThreshold = displayThreshold / 100
            end
            changed, frameDebuggerSettings.showDeltaTime = imgui.checkbox("Show Delta Time", frameDebuggerSettings.showDeltaTime); wc = wc or changed
            changed, frameDebuggerSettings.deltaTimeBaseLine = ui.imgui_safe_input(imgui.drag_float, frameDebuggerSettings.deltaTimeBaseLine, "Delta Time Base Line", frameDebuggerSettings.deltaTimeBaseLine, {0.001, 0.0, 100.0, "%.3fms"}); wc = wc or changed
            changed, frameDebuggerSettings.historyMaxSize = ui.imgui_safe_input(imgui.drag_int, frameDebuggerSettings.historyMaxSize, "History Limit", frameDebuggerSettings.historyMaxSize, {1, 0, 1000}); wc = wc or changed
            changed, frameDebuggerSettings.recordMaxSize = ui.imgui_safe_input(imgui.drag_int, frameDebuggerSettings.recordMaxSize, "Recording Limit", frameDebuggerSettings.recordMaxSize, {10, 0, 1000000}); wc = wc or changed
            imgui.pop_item_width()
            if changed or wc then
                frameDebuggerSettings.deltaTimeHistory = {}
                frameDebuggerSettings.frameTimeHistory = {}
            end
            if imgui.tree_node("Change Log") then
                imgui.text(modChangeLog)
                imgui.tree_pop()
            end
            if imgui.tree_node("Credits and Notes") then
                imgui.text("Credits: " .. modCredits)
                imgui.text("Notes: " .. modNotes)
                imgui.tree_pop()
            end
            imgui.indent(-5)
            imgui.spacing()
            imgui.end_rect()
            imgui.tree_pop()
        end
        
        if changed or wc then
            json.dump_file("SILVER/_Debug/FrameDebuggerSettings.json", frameDebuggerSettings)
            changed = false
            wc = false
        end

        imgui.text_colored(modVersion .. " | " .. modUpdated, func.convert_rgba_to_ABGR(ui.colors.gold));
        imgui.same_line();
        imgui.text("(c) " .. modAuthor .. " ")

        imgui.indent(-10)
        imgui.spacing()
        imgui.end_rect()
        imgui.tree_pop()
    end
    
end
--////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////--
--MARK:On Frame
re.on_frame(function ()
    get_GameAppData()
    record_FrameTime()
    if frameDebuggerSettings.isNewWindow then
        imgui.begin_window(modName)
        imgui.begin_rect()
        imgui.spacing()
        imgui.indent(10)
        
        setup_FrameDebugger()

        imgui.indent(-10)
        imgui.spacing()
        imgui.end_rect()
        imgui.end_window()
    end
end)

re.on_draw_ui(function ()
    draw_FrameDebugger()
end)