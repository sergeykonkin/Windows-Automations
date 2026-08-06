-- Renames each replay-buffer save to include the currently captured game's
-- name, read off the "Game Capture" input's "window" setting (the same
-- Title:Class:exe value ObsAutoGameCapture's set-obs-game-capture.ps1 writes
-- to it). No obs-websocket, no scheduled task - OBS_FRONTEND_EVENT_REPLAY_
-- BUFFER_SAVED fires only once the file is fully written, and OBS keeps this
-- script loaded across restarts once added via Tools > Scripts.
--
-- e.g. Replay_2026-08-06_01-13-54.mkv -> Replay_2026-08-06_01-13-54_Counter_Strike_2.mkv

obs = obslua

local input_name = "Game Capture"

function script_description()
    return "Renames each saved replay buffer file to include the name of the currently captured game."
end

function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_text(props, "input_name", "Game Capture input name", obs.OBS_TEXT_DEFAULT)
    return props
end

function script_defaults(settings)
    obs.obs_data_set_default_string(settings, "input_name", "Game Capture")
end

function script_update(settings)
    input_name = obs.obs_data_get_string(settings, "input_name")
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_REPLAY_BUFFER_SAVED then
        tag_last_replay()
    end
end

function tag_last_replay()
    local path = obs.obs_frontend_get_last_replay()
    if not path or path == "" then
        obs.script_log(obs.LOG_WARNING, "ReplayBufferSaved fired but no path was returned")
        return
    end

    local window = get_game_capture_window()
    if not window or window == "" then
        obs.script_log(obs.LOG_INFO, "No game currently captured - leaving " .. path .. " unchanged")
        return
    end

    local game_name = sanitize(parse_game_name(window))
    if game_name == "" then
        obs.script_log(obs.LOG_WARNING, "Could not derive a game name from window value: " .. window)
        return
    end

    local new_path = build_tagged_path(path, game_name)
    if not new_path then
        obs.script_log(obs.LOG_WARNING, "Could not parse replay path: " .. path)
        return
    end

    local ok, err = os.rename(path, new_path)
    if ok then
        obs.script_log(obs.LOG_INFO, "Tagged replay: " .. new_path)
    else
        obs.script_log(obs.LOG_WARNING, "Rename failed (" .. tostring(err) .. "): " .. path .. " -> " .. new_path)
    end
end

-- Reads the "window" setting off the configured input name, falling back to
-- the unique game_capture-kind source if that name isn't found - mirrors
-- Resolve-Targets in set-obs-game-capture.ps1.
function get_game_capture_window()
    local source = obs.obs_get_source_by_name(input_name)
    if source then
        local window = read_window_setting(source)
        obs.obs_source_release(source)
        return window
    end

    local window = nil
    local match_count = 0
    local sources = obs.obs_enum_sources()
    if sources then
        for _, src in ipairs(sources) do
            if obs.obs_source_get_id(src) == "game_capture" then
                match_count = match_count + 1
                window = read_window_setting(src)
            end
        end
        obs.source_list_release(sources)
    end
    if match_count == 1 then
        return window
    end
    return nil
end

function read_window_setting(source)
    local settings = obs.obs_source_get_settings(source)
    local window = obs.obs_data_get_string(settings, "window")
    obs.obs_data_release(settings)
    return window
end

-- window is "Title:Class:exe" with literal colons inside Title/Class already
-- escaped by OBS, so splitting on ':' is unambiguous. Prefers the Title;
-- falls back to the exe (minus ".exe") if the title is blank.
function parse_game_name(window)
    local parts = {}
    for part in (window .. ":"):gmatch("(.-):") do
        table.insert(parts, part)
    end
    local title = parts[1] or ""
    if title ~= "" then
        return title
    end
    local exe = parts[#parts] or ""
    return (exe:gsub("%.[Ee][Xx][Ee]$", ""))
end

-- Collapses any run of non-alphanumeric characters to a single underscore,
-- e.g. "Counter-Strike 2" -> "Counter_Strike_2".
function sanitize(name)
    local s = name:gsub("[^%w]+", "_")
    s = s:gsub("^_+", ""):gsub("_+$", "")
    return s
end

function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

-- Inserts "_<tag>" before the extension, disambiguating with a numeric
-- suffix if two replays land on the same path within the same second.
function build_tagged_path(path, tag)
    local dir, file = path:match("^(.*[\\/])([^\\/]+)$")
    if not file then
        dir = ""
        file = path
    end
    local base, ext = file:match("^(.*)%.([^%.]+)$")
    if not base then
        base = file
        ext = nil
    end

    local function candidate(suffix)
        local name = base .. "_" .. tag .. suffix
        if ext then
            name = name .. "." .. ext
        end
        return dir .. name
    end

    local new_path = candidate("")
    if not file_exists(new_path) then
        return new_path
    end
    for i = 2, 999 do
        new_path = candidate("_" .. i)
        if not file_exists(new_path) then
            return new_path
        end
    end
    return nil
end
