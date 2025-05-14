--[[
    Copyright (C) 2017 AMM

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]--
--[[
    mpv_thumbnail_script.lua 0.5.3 - commit 6b42232 (branch master)
    https://github.com/TheAMM/mpv_thumbnail_script
    Built on 2023-10-19 11:12:04
]]--
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

-- Determine if the platform is Windows --
ON_WINDOWS = (package.config:sub(1,1) ~= '/')

-- Determine if the platform is MacOS --
-- local uname = io.popen("uname -s"):read("*l") -- THIS CHECKING OPENS A CMD POPUP FOR A MOMENT AFTER RUNNING MPV ON WINDOWS!
ON_MAC = not ON_WINDOWS and (uname == "Mac" or uname == "Darwin")

-- Some helper functions needed to parse the options --
function isempty(v) return not v or (v == "") or (v == 0) or (type(v) == "table" and not next(v)) end

function divmod (a, b)
  return math.floor(a / b), a % b
end

function join_paths(...)
  local sep = ON_WINDOWS and "\\" or "/"
  local result = "";
  for i, p in pairs({...}) do
    if p ~= "" then
      if is_absolute_path(p) then
        result = p
      else
        result = (result ~= "") and (result:gsub("[\\"..sep.."]*$", "") .. sep .. p) or p
      end
    end
  end
  return result:gsub("[\\"..sep.."]*$", "")
end

-- /some/path/file.ext -> /some/path, file.ext
function split_path( path )
  local sep = ON_WINDOWS and "\\" or "/"
  local first_index, last_index = path:find('^.*' .. sep)

  if not last_index then
    return "", path
  else
    local dir = path:sub(0, last_index-1)
    local file = path:sub(last_index+1, -1)

    return dir, file
  end
end

function is_absolute_path( path )
  local tmp, is_win  = path:gsub("^[A-Z]:\\", "")
  local tmp, is_unix = path:gsub("^/", "")
  return (is_win > 0) or (is_unix > 0)
end

---------------------------
-- More helper functions --
---------------------------

function file_exists(name)
  local f = io.open(name, "rb")
  if f then
    local ok, err, code = f:read(1)
    io.close(f)
    return not code
  else
    return false
  end
end

function path_exists(name)
  local f = io.open(name, "rb")
  if f then
    io.close(f)
    return true
  else
    return false
  end
end

function create_directories(path)
  local cmd
  if ON_WINDOWS then
    cmd = { args = {"cmd", "/c", "mkdir", path} }
  else
    cmd = { args = {"mkdir", "-p", path} }
  end
  utils.subprocess(cmd)
end

-- Find an executable in PATH or CWD with the given name
function find_executable(name)
  local delim = ON_WINDOWS and ";" or ":"

  local pwd = os.getenv("PWD") or utils.getcwd()
  local path = os.getenv("PATH")

  local env_path = pwd .. delim .. path -- Check CWD first

  local result, filename
  for path_dir in env_path:gmatch("[^"..delim.."]+") do
    filename = join_paths(path_dir, name)
    if file_exists(filename) then
      result = filename
      break
    end
  end

  return result
end

local ExecutableFinder = { path_cache = {} }
-- Searches for an executable and caches the result if any
function ExecutableFinder:get_executable_path( name, raw_name )
  name = ON_WINDOWS and not raw_name and (name .. ".exe") or name

  if not self.path_cache[name] then
    self.path_cache[name] = find_executable(name) or false
  end
  return self.path_cache[name]
end

-- Format seconds to HH.MM.SS.sss
function format_time(seconds, sep, decimals)
  decimals = decimals or 3
  sep = sep or "."
  local s = seconds
  local h, s = divmod(s, 60*60)
  local m, s = divmod(s, 60)

  local second_format = string.format("%%0%d.%df", 2+(decimals > 0 and decimals+1 or 0), decimals)

  return string.format("%02d"..sep.."%02d"..sep..second_format, h, m, s)
end


local SCRIPT_NAME = "thumbfast"

local default_cache_base = ON_WINDOWS and os.getenv("TEMP") or (os.getenv("XDG_CACHE_HOME") or "/tmp/")

local thumbnailer_options = {
    -- options from thumbfast.conf
    socket = "",
    thumbnail = "",
    max_height = 200,
    max_width = 200,
    tone_mapping = "auto",
    overlay_id = 42,
    spawn_first = false,
    quit_after_inactivity = 0,
    network = false,
    audio = false,
    hwdec = false,
    direct_io = false,
    mpv_path = "mpv",
    apply_video_filters = false,
    storyboard_enable = true,
    thumbnailing_threads = "auto",
    storyboard_max_thumbnail_count = 960,
    rutube_thumbnail_interval = 10,
    rutube_min_thumbnail_target = 100,
    storyboard_upscale = false,
    recheck_storyboard_dimensions = true,
    use_url_whitelist = true,
    url_whitelist = "youtube.com youtu.be youtube-nocookie.com twitch.tv rutube.ru",
    prefer_ffmpeg = false,
    cache_directory = "",
    clear_cache_timeout = 3.0,
    hide_progress = false,
    vertical_offset = 4,
    background_color = "000000",
    background_alpha = 80,
    text_alpha = 20,
    mpv_logs = true,
    mpv_keep_logs = false,
    
    -- Explicitly disable subtitles on the mpv sub-calls
    mpv_no_sub = false,
    -- Add a "--no-config" to the mpv sub-call arguments
    mpv_no_config = true,
    -- Add a "--profile=<mpv_profile>" to the mpv sub-call arguments
    -- Use "" to disable
    mpv_profile = "",
    -- Hardware decoding
    mpv_hwdec = "no",
    -- High precision seek
    mpv_hr_seek = "yes",
    -- Don't pass given URL to ytdl
    remote_direct_stream = true,
    -- Track state of currently generating thumbnails (currently is useless)
    track_currently_generating_thumbnails = false
}

read_options(thumbnailer_options, SCRIPT_NAME)
if thumbnailer_options.cache_directory == "" then
    thumbnailer_options.cache_directory = join_paths(default_cache_base, "mpv_thumbs_cache")
end
if ON_WINDOWS then
    thumbnailer_options.cache_directory = thumbnailer_options.cache_directory:gsub("/", "\\")
end

function skip_nil(tbl)
    local n = {}
    for k, v in pairs(tbl) do
        table.insert(n, v)
    end
    return n
end

function create_thumbnail_mpv(file_path, timestamp, size, output_path, options)
    options = options or {}

    local ytdl_disabled = not options.enable_ytdl and (mp.get_property_native("ytdl") == false
                                                       or thumbnailer_options.remote_direct_stream)

    local header_fields_arg = nil
    local header_fields = mp.get_property_native("http-header-fields")
    if #header_fields > 0 then
        -- We can't escape the headers, mpv won't parse "--http-header-fields='Name: value'" properly
        header_fields_arg = "--http-header-fields=" .. table.concat(header_fields, ",")
    end

    local profile_arg = nil
    if thumbnailer_options.mpv_profile ~= "" then
        profile_arg = "--profile=" .. thumbnailer_options.mpv_profile
    end

    local log_arg = "--log-file=" .. output_path .. ".log"

    local mpv_command = skip_nil{
        thumbnailer_options.mpv_path,
        -- Hide console output
        "--msg-level=all=no",

        -- Disable ytdl
        (ytdl_disabled and "--no-ytdl" or nil),
        -- Pass HTTP headers from current instance
        header_fields_arg,
        -- Pass User-Agent and Referer - should do no harm even with ytdl active
        "--user-agent=" .. mp.get_property_native("user-agent"),
        "--referrer=" .. mp.get_property_native("referrer"),
        -- User set hardware decoding
        "--hwdec=" .. thumbnailer_options.mpv_hwdec,

        -- Insert --no-config, --profile=... and --log-file if enabled
        (thumbnailer_options.mpv_no_config and "--no-config" or nil),
        profile_arg,
        (thumbnailer_options.mpv_logs and log_arg or nil),

        "--start=" .. tostring(timestamp),
        "--frames=1",
        "--hr-seek=" .. thumbnailer_options.mpv_hr_seek,
        "--no-audio",
        -- Optionally disable subtitles
        (thumbnailer_options.mpv_no_sub and "--no-sub" or nil),

        (options.relative_scale
                and ("--vf=scale=iw*%d:ih*%d%s"):format(size.w, size.h, (size.col_corr or ""))
                or ("--vf=scale=%d:%d%s"):format(size.w, size.h, (size.col_corr or ""))),
        
        "--load-scripts=no",
        "--load-stats-overlay=no",
        "--load-osd-console=no",
        "--load-auto-profiles=no",
        "--osc=no",
        
        "--vf-add=format=bgra",
        "--of=rawvideo",
        "--ovc=rawvideo",
        ("--o=%s"):format(output_path),

        "--",

        file_path,
    }
    return mp.command_native{name="subprocess", args=mpv_command}
end

function create_thumbnail_ffmpeg(file_path, timestamp, size, output_path, options)
    options = options or {}

    local ffmpeg_path = ON_MAC and "/opt/homebrew/bin/ffmpeg" or "ffmpeg"

    local ffmpeg_command = {
        ffmpeg_path,
        "-loglevel", "quiet",
        "-noaccurate_seek",
        "-ss", format_time(timestamp, ":"),
        "-i", file_path,

        "-frames:v", "1",
        "-an",

        "-vf",
        (options.relative_scale
                and ("scale=iw*%d:ih*%d%s"):format(size.w, size.h, (size.col_corr or ""))
                or ("scale=%d:%d%s"):format(size.w, size.h, (size.col_corr or ""))),

        "-c:v", "rawvideo",
        "-pix_fmt", "bgra",
        "-f", "rawvideo",

        "-y", output_path,
    }
    return mp.command_native{name="subprocess", args=ffmpeg_command}
end


function check_output(ret, output_path, is_mpv)
    local log_path = output_path .. ".log"
    local success = true

    if ret.killed_by_us then
        return nil
    else
        if ret.error or ret.status ~= 0 then
            msg.error("Thumbnailing command failed!")
            msg.error("mpv process error:", ret.error)
            msg.error("Process stdout:", ret.stdout)
            if is_mpv and thumbnailer_options.mpv_logs then
                msg.error("Debug log:", log_path)
            end

            success = false
        end

        if not file_exists(output_path) then
            msg.error("Output file missing!", output_path)
            success = false
        end
    end

    if is_mpv and thumbnailer_options.mpv_logs and not thumbnailer_options.mpv_keep_logs then
        -- Remove successful debug logs
        if success and file_exists(log_path) then
            os.remove(log_path)
        end
    end

    return success
end

-- split cols x N atlas in BGRA format into many thumbnail files
function split_atlas(atlas_path, cols, thumbnail_size, output_name)
    local atlas = io.open(atlas_path, "rb")
    if not atlas then
        msg.error("Atlas suddenly disappeared!")
        return
    end
    
    local atlas_filesize = atlas:seek("end")
    local atlas_pictures = math.floor(atlas_filesize / (4 * thumbnail_size.w * thumbnail_size.h))
    local stride = 4 * thumbnail_size.w * math.min(cols, atlas_pictures)
    for pic = 0, atlas_pictures-1 do
        local x_start = (pic % cols) * thumbnail_size.w
        local y_start = math.floor(pic / cols) * thumbnail_size.h
        local filename = output_name(pic)
        if filename then
            local thumb_file = io.open(filename, "wb")
            for line = 0, thumbnail_size.h - 1 do
                atlas:seek("set", 4 * x_start + (y_start + line) * stride)
                local data = atlas:read(thumbnail_size.w * 4)
                if data then
                    thumb_file:write(data)
                end
            end
            thumb_file:close()
        end
    end
    atlas:close()
end

function do_worker_job(state_json_string, frames_json_string)
    msg.debug("Handling given job")
    local thumb_state, err = utils.parse_json(state_json_string)
    if err then
        msg.error("Failed to parse state JSON")
        return
    end

    local thumbnail_indexes, err = utils.parse_json(frames_json_string)
    if err then
        msg.error("Failed to parse thumbnail frame indexes")
        return
    end

    local thumbnail_func = create_thumbnail_mpv
    if thumbnailer_options.prefer_ffmpeg then
        if ExecutableFinder:get_executable_path("ffmpeg") then
            thumbnail_func = create_thumbnail_ffmpeg
        else
            msg.warn("Could not find ffmpeg in PATH! Falling back on mpv.")
        end
    end

    local file_duration = mp.get_property_native("duration")
    if thumb_state.storyboard then file_duration = 0 end
    if file_duration == nil then return end
    local file_path = thumb_state.worker_input_path

    if thumb_state.is_remote and not thumb_state.storyboard then
        if (thumbnail_func == create_thumbnail_ffmpeg) then
            msg.warn("Thumbnailing remote path, falling back on mpv.")
        end
        thumbnail_func = create_thumbnail_mpv
    end

    local generate_thumbnail_for_index = function(thumbnail_index)
        -- Given a 1-based thumbnail index, generate a thumbnail for it based on the thumbnailer state
        local thumb_idx = thumbnail_index - 1
        msg.debug("Starting work on thumbnail", thumb_idx)

        local thumbnail_path = thumb_state.thumbnail_template:format(thumb_idx)
        -- Grab the "middle" of the thumbnail duration instead of the very start, and leave some margin in the end (ignored for storyboards)
        local timestamp = math.min(file_duration - 0.25, (thumb_idx + 0.5) * thumb_state.thumbnail_delta)

        if thumbnailer_options.track_currently_generating_thumbnails then
            mp.commandv("script-message", "mpv_thumbnail_script-progress", tostring(thumbnail_index))
        end

        -- The expected size (raw BGRA image)
        local thumbnail_raw_size = (thumb_state.thumbnail_size.w * thumb_state.thumbnail_size.h * 4)

        local need_thumbnail_generation = false

        -- Check if the thumbnail already exists and is the correct size
        local thumbnail_file = io.open(thumbnail_path, "rb")
        if not thumbnail_file then
            need_thumbnail_generation = true
        else
            local existing_thumbnail_filesize = thumbnail_file:seek("end")
            if existing_thumbnail_filesize ~= thumbnail_raw_size then
                -- Size doesn't match, so (re)generate
                msg.warn("Thumbnail", thumb_idx, "did not match expected size, regenerating")
                need_thumbnail_generation = true
            end
            thumbnail_file:close()
        end

        if need_thumbnail_generation then
            local success
            if thumb_state.storyboard then
                -- get atlas and then split it into thumbnails
                local rows = thumb_state.storyboard.rows
                local cols = thumb_state.storyboard.cols
                local div = thumb_state.storyboard.divisor
                local atlas_idx = math.floor(thumb_idx * div /(cols*rows))
                local atlas_path = thumb_state.thumbnail_template:format(atlas_idx) .. ".atlas"
                if rows == 1 and cols == 1 then atlas_path = thumb_state.thumbnail_template:format(atlas_idx) end
                local url = thumb_state.storyboard.fragments[atlas_idx+1].url
                if not url then
                    url = thumb_state.storyboard.fragment_base_url .. "/" .. thumb_state.storyboard.fragments[atlas_idx+1].path
                end
                local ret
                if rows > 1 or cols > 1 then
                    ret = thumbnail_func(url, 0, { w=thumb_state.storyboard.scale, h=thumb_state.storyboard.scale }, atlas_path, { relative_scale=true })
                else
                    ret = thumbnail_func(url, 0, thumb_state.thumbnail_size, atlas_path)
                end
                success = check_output(ret, atlas_path, thumbnail_func == create_thumbnail_mpv)
                if success and (rows > 1 or cols > 1) then
                    split_atlas(atlas_path, cols, thumb_state.thumbnail_size, function(idx)
                        if (atlas_idx * cols * rows + idx) % div ~= 0 then
                            return nil
                        end
                        return thumb_state.thumbnail_template:format(math.floor((atlas_idx * cols * rows + idx) / div))
                    end)
                    mp.add_timeout(1, function() os.remove(atlas_path) end)
                end
            else
                local ret = thumbnail_func(file_path, timestamp, thumb_state.thumbnail_size, thumbnail_path, thumb_state.worker_extra)
                success = check_output(ret, thumbnail_path, thumbnail_func == create_thumbnail_mpv)
            end

            if not success then
                -- Killed by us, changing files, ignore
                msg.debug("Changing files, subprocess killed")
                return true
            elseif not success then
                -- Real failure
                mp.osd_message("Thumbnailing failed, check console for details", 3.5)
                return true
            end
        else
            msg.debug("Thumbnail", thumb_idx, "already done!")
        end

        -- Verify thumbnail size
        -- Sometimes ffmpeg will output an empty file when seeking to a "bad" section (usually the end)
        thumbnail_file = io.open(thumbnail_path, "rb")

        -- Bail if we can't read the file (it should really exist by now, we checked this in check_output!)
        if not thumbnail_file then
            msg.error("Thumbnail suddenly disappeared!")
            return true
        end

        -- Check the size of the generated file
        local thumbnail_file_size = thumbnail_file:seek("end")
        thumbnail_file:close()

        -- Check if the file is big enough
        local missing_bytes = math.max(0, thumbnail_raw_size - thumbnail_file_size)
        if missing_bytes > 0 then
            msg.warn(("Thumbnail missing %d bytes (expected %d, had %d), padding %s"):format(
              missing_bytes, thumbnail_raw_size, thumbnail_file_size, thumbnail_path
            ))
            -- Pad the file if it's missing content (eg. ffmpeg seek to file end)
            thumbnail_file = io.open(thumbnail_path, "ab")
            thumbnail_file:write(string.rep(string.char(0), missing_bytes))
            thumbnail_file:close()
        end

        msg.debug("Finished work on thumbnail", thumb_idx)
        mp.commandv("script-message", "mpv_thumbnail_script-ready", tostring(thumbnail_index), thumbnail_path)
    end

    msg.debug(("Generating %d thumbnails @ %dx%d for %q"):format(
        #thumbnail_indexes,
        thumb_state.thumbnail_size.w,
        thumb_state.thumbnail_size.h,
        file_path or mp.get_property("path")))

    for i, thumbnail_index in ipairs(thumbnail_indexes) do
        local bail = generate_thumbnail_for_index(thumbnail_index)
        if bail then return end
    end

end

-- Set up listeners and keybinds

-- Job listener
mp.register_script_message("mpv_thumbnail_script-job", do_worker_job)


-- Register this worker with the master script
local register_timer = nil
local register_timeout = mp.get_time() + 1.5

local register_function = function()
    if mp.get_time() > register_timeout and register_timer then
        msg.error("Thumbnail worker registering timed out")
        register_timer:stop()
    else
        msg.debug("Announcing self to master...")
        mp.commandv("script-message", "mpv_thumbnail_script-worker", mp.get_script_name())
    end
end

register_timer = mp.add_periodic_timer(0.1, register_function)

mp.register_script_message("mpv_thumbnail_script-slaved", function()
    msg.debug("Successfully registered with master")
    register_timer:stop()
end)
