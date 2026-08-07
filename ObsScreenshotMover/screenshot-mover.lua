-- Moves each OBS screenshot out of the recording/streaming output folder
-- (where OBS saves screenshots by default, alongside video) into a separate
-- destination folder, defaulting to the Windows "Pictures\Screenshots"
-- folder. OBS_FRONTEND_EVENT_SCREENSHOT_TAKEN fires only once the file is
-- fully written, and OBS keeps this script loaded across restarts once
-- added.
--
-- e.g. D:\Captures\Raw\Screenshot_2026-08-07_12-34-56.png
--      -> C:\Users\<user>\Pictures\Screenshots\Screenshot_2026-08-07_12-34-56.png

obs = obslua

local dest_dir = ""

function script_description()
    return "Moves each OBS screenshot out of the video output folder into a separate destination folder (default: Pictures\\Screenshots)."
end

function script_properties()
    local props = obs.obs_properties_create()
    obs.obs_properties_add_path(props, "dest_dir", "Destination folder", obs.OBS_PATH_DIRECTORY, nil, nil)
    return props
end

-- Only resolves (and shells out to PowerShell for) the default destination
-- once - setting a real value here, not just a default, so OBS persists it
-- and obs_data_has_user_value is true on every later startup. Without this,
-- default_dest_dir() (and its console-flashing PowerShell call) would rerun
-- on every OBS launch forever, since a default alone is never saved to disk.
function script_defaults(settings)
    if not obs.obs_data_has_user_value(settings, "dest_dir") then
        obs.obs_data_set_string(settings, "dest_dir", default_dest_dir())
    end
end

function script_update(settings)
    dest_dir = obs.obs_data_get_string(settings, "dest_dir")
end

function script_load(settings)
    obs.obs_frontend_add_event_callback(on_event)
end

function script_unload()
    obs.obs_frontend_remove_event_callback(on_event)
end

function on_event(event)
    if event == obs.OBS_FRONTEND_EVENT_SCREENSHOT_TAKEN then
        move_last_screenshot()
    end
end

-- Windows' default location for app-saved screenshots, honoring the
-- Pictures library's configured location (Properties > Location tab) rather
-- than assuming %USERPROFILE%\Pictures - that only holds when the library
-- hasn't been redirected (e.g. to a D: drive).
function default_dest_dir()
    local pictures = query_pictures_folder()
    if pictures and pictures ~= "" then
        return pictures .. "\\Screenshots"
    end

    local profile = os.getenv("USERPROFILE")
    if not profile or profile == "" then
        return ""
    end
    return profile .. "\\Pictures\\Screenshots"
end

function query_pictures_folder()
    local handle = io.popen('powershell -NoProfile -Command "[Environment]::GetFolderPath(\'MyPictures\')"')
    if not handle then
        return nil
    end
    local result = handle:read("*a")
    handle:close()
    if not result then
        return nil
    end
    result = result:gsub("^%s+", ""):gsub("%s+$", "")
    if result == "" then
        return nil
    end
    return result
end

function move_last_screenshot()
    local path = obs.obs_frontend_get_last_screenshot()
    if not path or path == "" then
        obs.script_log(obs.LOG_WARNING, "ScreenshotTaken fired but no path was returned")
        return
    end

    if dest_dir == "" then
        obs.script_log(obs.LOG_WARNING, "No destination folder configured - leaving " .. path .. " unchanged")
        return
    end

    local file = path:match("^.*[\\/]([^\\/]+)$") or path
    local new_path = build_dest_path(dest_dir, file)
    if not new_path then
        obs.script_log(obs.LOG_WARNING, "Could not find a free destination filename for: " .. path)
        return
    end
    if new_path == path then
        return
    end

    ensure_dir(dest_dir)

    local ok, err = move_file(path, new_path)
    if ok then
        obs.script_log(obs.LOG_INFO, "Moved screenshot: " .. new_path)
    else
        obs.script_log(obs.LOG_WARNING, "Move failed (" .. tostring(err) .. "): " .. path .. " -> " .. new_path)
    end
end

function ensure_dir(dir)
    os.execute('if not exist "' .. dir .. '" mkdir "' .. dir .. '"')
end

function file_exists(path)
    local f = io.open(path, "rb")
    if f then
        f:close()
        return true
    end
    return false
end

-- Disambiguates with a numeric suffix if a file of the same name already
-- exists at the destination (e.g. two screenshots taken across sessions
-- with a stale/clock-rolled-back filename).
function build_dest_path(dir, file)
    local clean_dir = dir:gsub("[\\/]+$", "")
    local base, ext = file:match("^(.*)%.([^%.]+)$")
    if not base then
        base = file
        ext = nil
    end

    local function candidate(suffix)
        local name = base .. suffix
        if ext then
            name = name .. "." .. ext
        end
        return clean_dir .. "\\" .. name
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

-- os.rename (C rename()) fails moving across drives on Windows, so fall
-- back to a copy + delete when it does.
function move_file(src, dst)
    local ok = os.rename(src, dst)
    if ok then
        return true
    end

    local ok2, err2 = copy_file(src, dst)
    if not ok2 then
        return false, err2
    end

    local removed, rerr = os.remove(src)
    if not removed then
        return false, "copied but failed to remove source: " .. tostring(rerr)
    end
    return true
end

function copy_file(src, dst)
    local inp = io.open(src, "rb")
    if not inp then
        return false, "could not open source"
    end
    local out = io.open(dst, "wb")
    if not out then
        inp:close()
        return false, "could not open destination"
    end

    while true do
        local chunk = inp:read(1024 * 1024)
        if not chunk then
            break
        end
        out:write(chunk)
    end

    inp:close()
    out:close()
    return true
end
