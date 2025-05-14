-- thumbfast.lua
--
-- High-performance on-the-fly thumbnailer
--
-- Built for easy integration in third-party UIs.

-- Storyboard thumbnailer was added by SearchDownload

local assdraw = require 'mp.assdraw'
local msg = require 'mp.msg'
local opt = require 'mp.options'
local utils = require 'mp.utils'

local options = {
    -- Socket path (leave empty for auto)
    socket = "",

    -- Thumbnail path (leave empty for auto)
    thumbnail = "",

    -- Maximum thumbnail size in pixels (scaled down to fit)
    -- Values are scaled when hidpi is enabled
    max_height = 200,
    max_width = 200,

    -- Apply tone-mapping, no to disable
    tone_mapping = "auto",

    -- Overlay id
    overlay_id = 42,

    -- Spawn thumbnailer on file load for faster initial thumbnails
    spawn_first = false,

    -- Close thumbnailer process after an inactivity period in seconds, 0 to disable
    quit_after_inactivity = 0,

    -- Enable on network playback when storyboard is unavailable
    -- Note that network cache of the current mpv instance will not be used, as the video is reopened by thumbnailer, so thumbnailing may be slow and unreliable
    network = false,

    -- Enable on audio playback
    audio = false,

    -- Enable hardware decoding
    hwdec = false,

    -- Windows only: use native Windows API to write to pipe (requires LuaJIT)
    direct_io = false,

    -- Custom path to the mpv executable
    mpv_path = "mpv",

    -- Apply currently used video filters to the resulting thumbnail (thumbfast's default: yes)
    -- May increase likelihood that thumbnailer will hang, as well as increase latency before the actual thumbnail is displayed
    -- To display thumbnails when using lavfi-complex filters like blur-edges, this feature must be disabled
    apply_video_filters = false,

    
    ------------------------------------
    -- Storyboard thumbnailer options --
    ------------------------------------

    -- Enable storyboards (requires yt-dlp in PATH or in the same folder as mpv's executable). Currently only supports YouTube, Twitch and Rutube VoDs
    storyboard_enable = true,
    
    -- Number of storyboard thumbnail generation threads
    -- When set to "auto", the number of threads will be within 75% of the number of CPU cores, but no more than 8 threads to avoid rate-limiting
    thumbnailing_threads = "auto",
    
    -- Max thumbnails for storyboards. It only skips processing some of the downloaded thumbnails and doesn't make it much faster
    storyboard_max_thumbnail_count = 960,
    
    -- Rutube offers a thumbnail for every second of video. You can reduce the number of downloaded thumbnails to the specified interval between them in seconds,
    -- as well as set a minimum target number of thumbnails to increase their density for shorter videos
    rutube_thumbnail_interval = 10,
    rutube_min_thumbnail_target = 100,

    -- Most storyboard thumbnails are 160x90 or 320x180. Enabling this allows upscaling them up during processing, but it will result in wasted disk space
    -- Since mpv v0.38, thumbnails can be scaled directly in the player, so there is no need to save enlarged thumbnails; therefore, this option will have no effect
    storyboard_upscale = false,
    
    -- yt-dlp sometimes gives slightly incorrect storyboard dimensions, which completely breaks thumbnails
    -- This option enables rechecking storyboard dimensions by mpv to obtain accurate values
    -- This usually takes less than half a second but slows down the initialization of thumbnails for that duration
    recheck_storyboard_dimensions = true,
    
    -- By default, the storyboard is requested from yt-dlp only for those sites where it is known to be supported, in order to avoid unnecessary yt-dlp calls
    -- You can disable this to try to obtain storyboards for any http(s) videos if you feel lucky
    -- Note that for videos for which a storyboard has been requested, on-the-fly thumbnailer will not be used, even with the option network=yes
    use_url_whitelist = true,

    -- A list of website domains separated by space for which to try to obtain storyboards
    url_whitelist = "youtube.com youtu.be youtube-nocookie.com twitch.tv rutube.ru",
    
    -- Use ffmpeg to generate thumbnails instead of mpv (requires ffmpeg in PATH)
    -- ffmpeg can be slightly faster and less resource-intense than mpv
    prefer_ffmpeg = false,
    
    -- The thumbnail directory
    cache_directory = "",
    
    -- Automatically clears thumbnail cache for videos that have not been opened for the specified number of days
    -- 0 to clear entire cache immediately after closing the video for which storyboard was displayed
    -- -1 to disable automatic cache clearing
    clear_cache_timeout = 3.0,

    -- Do not display the thumbnailing progress bar
    hide_progress = false,
    
    -- Display progress bar above the thumbnail at a specified distance in pixels
    vertical_offset = 4,
    
    -- Background color in BBGGRR
    background_color = "000000",
    -- Alpha: 0 - fully opaque, 255 - transparent
    background_alpha = 80,
    text_alpha = 20,
    
    -- Output debug logs to <thumbnail_path>.log, ala <cache_directory>/<video_filename>/000000.bgra.log
    -- The logs are removed after successful encodes, unless you set mpv_keep_logs below
    mpv_logs = true,
    -- Keep all mpv logs, even the succesfull ones
    mpv_keep_logs = false
}
opt.read_options(options, "thumbfast")

local properties = {}
local pre_0_30_0 = mp.command_native_async == nil
local pre_0_33_0 = true

local video_loaded = false
local storyboard_requested = false
local displaying_size_w = 0
local displaying_size_h = 0
local osc_thumb_state = {}
local progress_bar = mp.create_osd_overlay("ass-events")
local prev_thumb_count = 0
local antistuck_attempt = 0
local url_table = {}
local mpv_0_38_above = false -- mpv v0.38+ with support of scaling image overlays using overlay-add
if mp.get_property("input-commands") ~= nil then
    mpv_0_38_above = true
end

-- Determine if the platform is Windows --
ON_WINDOWS = (package.config:sub(1,1) ~= '/')
local default_cache_base = ON_WINDOWS and os.getenv("TEMP") or (os.getenv("XDG_CACHE_HOME") or "/tmp/")

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

-- Removes all keys from a table, without destroying the reference to it
function clear_table(target)
  for key, value in pairs(target) do
    target[key] = nil
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

function get_processor_count()
  local proc_count

  if ON_WINDOWS then
    proc_count = tonumber(os.getenv("NUMBER_OF_PROCESSORS"))
  else
    local cpuinfo_handle = io.open("/proc/cpuinfo")
    if cpuinfo_handle then
      local cpuinfo_contents = cpuinfo_handle:read("*a")
      local _, replace_count = cpuinfo_contents:gsub('processor', '')
      proc_count = replace_count
    end
  end

  if proc_count and proc_count > 0 then
      return proc_count
  end
end

-- End of helper functions


if options.thumbnailing_threads == "auto" or options.thumbnailing_threads == "" then
    local cpu_cores = get_processor_count()
    if cpu_cores then
        options.thumbnailing_threads = math.min(math.floor(cpu_cores * 0.75), 8)
        msg.verbose("Number of CPU cores: " .. cpu_cores .. ", using " .. options.thumbnailing_threads .. " threads for thumbnailing")
    else
        msg.warn("Unable to get number of CPU cores, generating thumbnails only in one thread")
    end
end
options.thumbnailing_threads = tonumber(options.thumbnailing_threads) or 1

if options.cache_directory == "" then
    options.cache_directory = join_paths(default_cache_base, "mpv_thumbs_cache")
end
if ON_WINDOWS then
    options.cache_directory = options.cache_directory:gsub("/", "\\")
end

for domain in options.url_whitelist:gmatch("[^%s]+") do
    url_table[domain:lower():gsub("^https?://", "")] = true
end

local Thumbnailer = {
    cache_directory = options.cache_directory,

    state = {
        ready = false,
        available = false,
        enabled = false,

        thumbnail_template = nil,

        thumbnail_delta = nil,
        thumbnail_count = 0,

        thumbnail_size = nil,

        finished_thumbnails = 0,

        -- List of thumbnail states (from 1 to thumbnail_count)
        -- ready: 1
        -- in progress: 0
        -- not ready: -1
        thumbnails = {},

        -- Extra options for the workers
        worker_extra = {},

        -- Storyboard urls
        storyboard = nil,
    },
    -- Set in register_client
    worker_register_timeout = nil,
    -- A timer used to wait for more workers in case we have none
    worker_wait_timer = nil,
    workers = {},
}

function subprocess(args, async, callback)
    callback = callback or function() end

    if not pre_0_30_0 then
        if async then
            return mp.command_native_async({name = "subprocess", playback_only = true, args = args}, callback)
        else
            return mp.command_native({name = "subprocess", playback_only = false, capture_stdout = true, args = args})
        end
    else
        if async then
            return utils.subprocess_detached({args = args}, callback)
        else
            return utils.subprocess({args = args})
        end
    end
end

local winapi = {}
if options.direct_io then
    local ffi_loaded, ffi = pcall(require, "ffi")
    if ffi_loaded then
        winapi = {
            ffi = ffi,
            C = ffi.C,
            bit = require("bit"),
            socket_wc = "",

            -- WinAPI constants
            CP_UTF8 = 65001,
            GENERIC_WRITE = 0x40000000,
            OPEN_EXISTING = 3,
            FILE_FLAG_WRITE_THROUGH = 0x80000000,
            FILE_FLAG_NO_BUFFERING = 0x20000000,
            PIPE_NOWAIT = ffi.new("unsigned long[1]", 0x00000001),

            INVALID_HANDLE_VALUE = ffi.cast("void*", -1),

            -- don't care about how many bytes WriteFile wrote, so allocate something to store the result once
            _lpNumberOfBytesWritten = ffi.new("unsigned long[1]"),
        }
        -- cache flags used in run() to avoid bor() call
        winapi._createfile_pipe_flags = winapi.bit.bor(winapi.FILE_FLAG_WRITE_THROUGH, winapi.FILE_FLAG_NO_BUFFERING)

        ffi.cdef[[
            void* __stdcall CreateFileW(const wchar_t *lpFileName, unsigned long dwDesiredAccess, unsigned long dwShareMode, void *lpSecurityAttributes, unsigned long dwCreationDisposition, unsigned long dwFlagsAndAttributes, void *hTemplateFile);
            bool __stdcall WriteFile(void *hFile, const void *lpBuffer, unsigned long nNumberOfBytesToWrite, unsigned long *lpNumberOfBytesWritten, void *lpOverlapped);
            bool __stdcall CloseHandle(void *hObject);
            bool __stdcall SetNamedPipeHandleState(void *hNamedPipe, unsigned long *lpMode, unsigned long *lpMaxCollectionCount, unsigned long *lpCollectDataTimeout);
            int __stdcall MultiByteToWideChar(unsigned int CodePage, unsigned long dwFlags, const char *lpMultiByteStr, int cbMultiByte, wchar_t *lpWideCharStr, int cchWideChar);
        ]]

        winapi.MultiByteToWideChar = function(MultiByteStr)
            if MultiByteStr then
                local utf16_len = winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, MultiByteStr, -1, nil, 0)
                if utf16_len > 0 then
                    local utf16_str = winapi.ffi.new("wchar_t[?]", utf16_len)
                    if winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, MultiByteStr, -1, utf16_str, utf16_len) > 0 then
                        return utf16_str
                    end
                end
            end
            return ""
        end

    else
        options.direct_io = false
    end
end

local file = nil
local file_bytes = 0
local spawned = false
local disabled = false
local force_disabled = false
local spawn_waiting = false
local spawn_working = false
local script_written = false

local dirty = false

local x = nil
local y = nil
local last_x = x
local last_y = y

local last_seek_time = nil

local effective_w = options.max_width
local effective_h = options.max_height
local real_w = nil
local real_h = nil
local last_real_w = nil
local last_real_h = nil

local script_name = nil

local show_thumbnail = false

local filters_reset = {["lavfi-crop"]=true, ["crop"]=true}
local filters_runtime = {["hflip"]=true, ["vflip"]=true}
local filters_all = {["hflip"]=true, ["vflip"]=true, ["lavfi-crop"]=true, ["crop"]=true}

local tone_mappings = {["none"]=true, ["clip"]=true, ["linear"]=true, ["gamma"]=true, ["reinhard"]=true, ["hable"]=true, ["mobius"]=true}
local last_tone_mapping = nil

local last_vf_reset = ""
local last_vf_runtime = ""

local last_rotate = 0

local par = ""
local last_par = ""

local last_has_vid = 0
local has_vid = 0
local vid_off = false -- support for thumbnais when lavfi-complex filter (e.g. blur-edges) is active

local file_timer = nil
local file_check_period = 1/60

local allow_fast_seek = true

local client_script = [=[
#!/usr/bin/env bash
MPV_IPC_FD=0; MPV_IPC_PATH="%s"
trap "kill 0" EXIT
while [[ $# -ne 0 ]]; do case $1 in --mpv-ipc-fd=*) MPV_IPC_FD=${1/--mpv-ipc-fd=/} ;; esac; shift; done
if echo "print-text thumbfast" >&"$MPV_IPC_FD"; then echo -n > "$MPV_IPC_PATH"; tail -f "$MPV_IPC_PATH" >&"$MPV_IPC_FD" & while read -r -u "$MPV_IPC_FD" 2>/dev/null; do :; done; fi
]=]

local function get_os()
    local raw_os_name = ""

    if jit and jit.os and jit.arch then
        raw_os_name = jit.os
    else
        if package.config:sub(1,1) == "\\" then
            -- Windows
            local env_OS = os.getenv("OS")
            if env_OS then
                raw_os_name = env_OS
            end
        else
            raw_os_name = subprocess({"uname", "-s"}).stdout
        end
    end

    raw_os_name = (raw_os_name):lower()

    local os_patterns = {
        ["windows"] = "windows",
        ["linux"]   = "linux",

        ["osx"]     = "darwin",
        ["mac"]     = "darwin",
        ["darwin"]  = "darwin",

        ["^mingw"]  = "windows",
        ["^cygwin"] = "windows",

        ["bsd$"]    = "darwin",
        ["sunos"]   = "darwin"
    }

    -- Default to linux
    local str_os_name = "linux"

    for pattern, name in pairs(os_patterns) do
        if raw_os_name:match(pattern) then
            str_os_name = name
            break
        end
    end

    return str_os_name
end

local os_name = mp.get_property("platform") or get_os()

local path_separator = os_name == "windows" and "\\" or "/"

if options.socket == "" then
    if os_name == "windows" then
        options.socket = "thumbfast"
    else
        options.socket = "/tmp/thumbfast"
    end
end

if options.thumbnail == "" then
    if os_name == "windows" then
        options.thumbnail = os.getenv("TEMP").."\\thumbfast.out"
    else
        options.thumbnail = "/tmp/thumbfast.out"
    end
end

local unique = utils.getpid()

options.socket = options.socket .. unique
options.thumbnail = options.thumbnail .. unique

if options.direct_io then
    if os_name == "windows" then
        winapi.socket_wc = winapi.MultiByteToWideChar("\\\\.\\pipe\\" .. options.socket)
    end

    if winapi.socket_wc == "" then
        options.direct_io = false
    end
end

local mpv_path = options.mpv_path

if mpv_path == "mpv" and os_name == "darwin" and unique then
    -- TODO: look into ~~osxbundle/
    mpv_path = string.gsub(subprocess({"ps", "-o", "comm=", "-p", tostring(unique)}).stdout, "[\n\r]", "")
    if mpv_path ~= "mpv" then
        mpv_path = string.gsub(mpv_path, "/mpv%-bundle$", "/mpv")
        local mpv_bin = utils.file_info("/usr/local/mpv")
        if mpv_bin and mpv_bin.is_file then
            mpv_path = "/usr/local/mpv"
        else
            local mpv_app = utils.file_info("/Applications/mpv.app/Contents/MacOS/mpv")
            if mpv_app and mpv_app.is_file then
                mp.msg.warn("symlink mpv to fix Dock icons: `sudo ln -s /Applications/mpv.app/Contents/MacOS/mpv /usr/local/mpv`")
            else
                mp.msg.warn("drag to your Applications folder and symlink mpv to fix Dock icons: `sudo ln -s /Applications/mpv.app/Contents/MacOS/mpv /usr/local/mpv`")
            end
        end
    end
end

local function vo_tone_mapping()
    local passes = mp.get_property_native("vo-passes")
    if passes and passes["fresh"] then
        for k, v in pairs(passes["fresh"]) do
            for k2, v2 in pairs(v) do
                if k2 == "desc" and v2 then
                    local tone_mapping = string.match(v2, "([0-9a-z.-]+) tone map")
                    if tone_mapping then
                        return tone_mapping
                    end
                end
            end
        end
    end
end

local function vf_string(filters, full)
    local vf = ""
    local vf_table = properties["vf"]

    if options.apply_video_filters and vf_table and #vf_table > 0 then
        for i = #vf_table, 1, -1 do
            if filters[vf_table[i].name] then
                local args = ""
                for key, value in pairs(vf_table[i].params) do
                    if args ~= "" then
                        args = args .. ":"
                    end
                    args = args .. key .. "=" .. value
                end
                vf = vf .. vf_table[i].name .. "=" .. args .. ","
            end
        end
    end

    if (full and options.tone_mapping ~= "no") or options.tone_mapping == "auto" then
        if properties["video-params"] and properties["video-params"]["primaries"] == "bt.2020" then
            local tone_mapping = options.tone_mapping
            if tone_mapping == "auto" then
                tone_mapping = last_tone_mapping or properties["tone-mapping"]
                if tone_mapping == "auto" and properties["current-vo"] == "gpu-next" then
                    tone_mapping = vo_tone_mapping()
                end
            end
            if not tone_mappings[tone_mapping] then
                tone_mapping = "hable"
            end
            last_tone_mapping = tone_mapping
            vf = vf .. "zscale=transfer=linear,format=gbrpf32le,tonemap="..tone_mapping..",zscale=transfer=bt709,"
        end
    end

    if full then
        vf = vf.."scale=w="..effective_w..":h="..effective_h..par..",pad=w="..effective_w..":h="..effective_h..":x=-1:y=-1,format=bgra"
    end

    return vf
end

function get_size(width, height, pref_w, pref_h)
    local w, h
    local scale = properties["display-hidpi-scale"] or 1
    if width / height > pref_w / pref_h then
        w = math.floor(pref_w * scale + 0.5)
        h = math.floor(height / width * w + 0.5)
    else
        h = math.floor(pref_h * scale + 0.5)
        w = math.floor(width / height * h + 0.5)
    end
    return w, h
end

local function calc_dimensions()
    local params = "video-params"
    if options.apply_video_filters then params = "video-out-params" end

    local width = properties[params] and properties[params]["dw"]
    local height = properties[params] and properties[params]["dh"]
    if not width or not height then return end

    effective_w, effective_h = get_size(width, height, options.max_width, options.max_height)

    local v_par = properties["video-out-params"] and properties["video-out-params"]["par"] or 1
    if v_par == 1 then
        par = ":force_original_aspect_ratio=decrease"
    else
        par = ""
    end
end

function check_disabled_video() -- check for disabled video track existance and correct some properties
    if mp.get_property_native("vid") then
        vid_off = false
    else
        local tracks_total = mp.get_property_native("track-list/count")
        for i = 0, tracks_total-1 do
            if mp.get_property_native("track-list/" .. i .. "/type") == "video" then
                has_vid = 1
                if mp.get_property_native("vid") == false then vid_off = true else vid_off = false end
                break
            end
        end
    end
end

local info_timer = nil

local function info(w, h)
    if storyboard_requested then return end

    local rotate = properties["video-params"] and properties["video-params"]["rotate"]
    local image = properties["current-tracks"] and properties["current-tracks"]["video"] and properties["current-tracks"]["video"]["image"]
    local albumart = image and properties["current-tracks"]["video"]["albumart"]

    if not options.apply_video_filters then
        check_disabled_video()
    end
    
    disabled = (w or 0) == 0 or (h or 0) == 0 or
        has_vid == 0 or
        (properties["demuxer-via-network"] and not options.network) or
        (mp.get_property("current-tracks/video/albumart") == "yes" and not options.audio) or
        (image and not albumart) or
        force_disabled

    if info_timer then
        info_timer:kill()
        info_timer = nil
    elseif has_vid == 0 or (rotate == nil and not disabled) then
        info_timer = mp.add_timeout(0.05, function() info(w, h) end)
    end

    local json, err = utils.format_json({width=w, height=h, disabled=disabled, available=true, socket=options.socket, thumbnail=options.thumbnail, overlay_id=options.overlay_id})
    if pre_0_30_0 then
        mp.command_native({"script-message", "thumbfast-info", json})
    else
        mp.command_native_async({"script-message", "thumbfast-info", json}, function() end)
    end
end

local function remove_thumbnail_files()
    if file then
        file:close()
        file = nil
        file_bytes = 0
    end
    os.remove(options.thumbnail)
    os.remove(options.thumbnail..".bgra")
end

local activity_timer

local function spawn(time)
    if disabled or storyboard_requested then return end

    local path = properties["path"]
    if path == nil then return end

    if options.quit_after_inactivity > 0 then
        if show_thumbnail or activity_timer:is_enabled() then
            activity_timer:kill()
        end
        activity_timer:resume()
    end

    local open_filename = properties["stream-open-filename"]
    local ytdl = open_filename and properties["demuxer-via-network"] and path ~= open_filename
    if ytdl then
        path = open_filename
    end

    remove_thumbnail_files()

    local vid = properties["vid"]
    has_vid = vid or 0
    if vid_off then vid = 1 end

    local args = {
        mpv_path, "--no-config", "--msg-level=all=no", "--idle", "--pause", "--keep-open=always", "--really-quiet", "--no-terminal",
        "--load-scripts=no", "--osc=no", "--ytdl=no", "--load-stats-overlay=no", "--load-osd-console=no", "--load-auto-profiles=no",
        "--edition="..(properties["edition"] or "auto"), "--vid="..(vid or "auto"), "--no-sub", "--no-audio",
        "--start="..time, allow_fast_seek and "--hr-seek=no" or "--hr-seek=yes",
        "--ytdl-format=worst", "--demuxer-readahead-secs=0", "--demuxer-max-bytes=128KiB",
        "--vd-lavc-skiploopfilter=all", "--vd-lavc-software-fallback=1", "--vd-lavc-fast", "--vd-lavc-threads=2", "--hwdec="..(options.hwdec and "auto" or "no"),
        "--vf="..vf_string(filters_all, true),
        "--sws-scaler=fast-bilinear",
        "--video-rotate="..last_rotate,
        "--ovc=rawvideo", "--of=image2", "--ofopts=update=1", "--o="..options.thumbnail
    }

    if not pre_0_30_0 then
        table.insert(args, "--sws-allow-zimg=no")
    end

    if os_name == "darwin" and properties["macos-app-activation-policy"] then
        table.insert(args, "--macos-app-activation-policy=accessory")
    end

    if os_name == "windows" or pre_0_33_0 then
        table.insert(args, "--input-ipc-server="..options.socket)
    elseif not script_written then
        local client_script_path = options.socket..".run"
        local script = io.open(client_script_path, "w+")
        if script == nil then
            mp.msg.error("client script write failed")
            return
        else
            script_written = true
            script:write(string.format(client_script, options.socket))
            script:close()
            subprocess({"chmod", "+x", client_script_path}, true)
            table.insert(args, "--scripts="..client_script_path)
        end
    else
        local client_script_path = options.socket..".run"
        table.insert(args, "--scripts="..client_script_path)
    end

    table.insert(args, "--")
    table.insert(args, path)

    spawned = true
    spawn_waiting = true

    subprocess(args, true,
        function(success, result)
            if spawn_waiting and (success == false or (result.status ~= 0 and result.status ~= -2)) then
                spawned = false
                spawn_waiting = false
                options.tone_mapping = "no"
                mp.msg.error("mpv subprocess create failed")
                if not spawn_working then -- notify users of required configuration
                    if options.mpv_path == "mpv" then
                        if properties["current-vo"] == "libmpv" then
                            if options.mpv_path == mpv_path then -- attempt to locate ImPlay
                                mpv_path = "ImPlay"
                                spawn(time)
                            else -- ImPlay not in path
                                if os_name ~= "darwin" then
                                    force_disabled = true
                                    info(real_w or effective_w, real_h or effective_h)
                                end
                                mp.commandv("show-text", "thumbfast: ERROR! cannot create mpv subprocess", 5000)
                                mp.commandv("script-message-to", "implay", "show-message", "thumbfast initial setup", "Set mpv_path=PATH_TO_ImPlay in thumbfast config:\n" .. string.gsub(mp.command_native({"expand-path", "~~/script-opts/thumbfast.conf"}), "[/\\]", path_separator).."\nand restart ImPlay")
                            end
                        else
                            mp.commandv("show-text", "thumbfast: ERROR! cannot create mpv subprocess", 5000)
                            if os_name == "windows" then
                                mp.commandv("script-message-to", "mpvnet", "show-text", "thumbfast: ERROR! install standalone mpv, see README", 5000, 20)
                                mp.commandv("script-message", "mpv.net", "show-text", "thumbfast: ERROR! install standalone mpv, see README", 5000, 20)
                            end
                        end
                    else
                        mp.commandv("show-text", "thumbfast: ERROR! cannot create mpv subprocess", 5000)
                        -- found ImPlay but not defined in config
                        mp.commandv("script-message-to", "implay", "show-message", "thumbfast", "Set mpv_path=PATH_TO_ImPlay in thumbfast config:\n" .. string.gsub(mp.command_native({"expand-path", "~~/script-opts/thumbfast.conf"}), "[/\\]", path_separator).."\nand restart ImPlay")
                    end
                end
            elseif success == true and (result.status == 0 or result.status == -2) then
                if not spawn_working and properties["current-vo"] == "libmpv" and options.mpv_path ~= mpv_path then
                    mp.commandv("script-message-to", "implay", "show-message", "thumbfast initial setup", "Set mpv_path=ImPlay in thumbfast config:\n" .. string.gsub(mp.command_native({"expand-path", "~~/script-opts/thumbfast.conf"}), "[/\\]", path_separator).."\nand restart ImPlay")
                end
                spawn_working = true
                spawn_waiting = false
            end
        end
    )
end

local function run(command)
    if not spawned then return end

    if options.direct_io then
        local hPipe = winapi.C.CreateFileW(winapi.socket_wc, winapi.GENERIC_WRITE, 0, nil, winapi.OPEN_EXISTING, winapi._createfile_pipe_flags, nil)
        if hPipe ~= winapi.INVALID_HANDLE_VALUE then
            local buf = command .. "\n"
            winapi.C.SetNamedPipeHandleState(hPipe, winapi.PIPE_NOWAIT, nil, nil)
            winapi.C.WriteFile(hPipe, buf, #buf + 1, winapi._lpNumberOfBytesWritten, nil)
            winapi.C.CloseHandle(hPipe)
        end

        return
    end

    local command_n = command.."\n"

    if os_name == "windows" then
        if file and file_bytes + #command_n >= 4096 then
            file:close()
            file = nil
            file_bytes = 0
        end
        if not file then
            file = io.open("\\\\.\\pipe\\"..options.socket, "r+b")
        end
    elseif pre_0_33_0 then
        subprocess({"/usr/bin/env", "sh", "-c", "echo '" .. command .. "' | socat - " .. options.socket})
        return
    elseif not file then
        file = io.open(options.socket, "r+")
    end
    if file then
        file_bytes = file:seek("end")
        file:write(command_n)
        file:flush()
    end
end

local function draw(w, h, script)
    if not w or not show_thumbnail then return end
    if x ~= nil then
        if pre_0_30_0 then
            mp.command_native({"overlay-add", options.overlay_id, x, y, options.thumbnail..".bgra", 0, "bgra", w, h, (4*w)})
        else
            mp.command_native_async({"overlay-add", options.overlay_id, x, y, options.thumbnail..".bgra", 0, "bgra", w, h, (4*w)}, function() end)
        end
    elseif script then
        local json, err = utils.format_json({width=w, height=h, x=x, y=y, socket=options.socket, thumbnail=options.thumbnail, overlay_id=options.overlay_id})
        mp.commandv("script-message-to", script, "thumbfast-render", json)
    end
end

local function real_res(req_w, req_h, filesize)
    local count = filesize / 4
    local diff = (req_w * req_h) - count

    if (properties["video-params"] and properties["video-params"]["rotate"] or 0) % 180 == 90 then
        req_w, req_h = req_h, req_w
    end

    if diff == 0 then
        return req_w, req_h
    else
        local threshold = 5 -- throw out results that change too much
        local long_side, short_side = req_w, req_h
        if req_h > req_w then
            long_side, short_side = req_h, req_w
        end
        for a = short_side, short_side - threshold, -1 do
            if count % a == 0 then
                local b = count / a
                if long_side - b < threshold then
                    if req_h < req_w then return b, a else return a, b end
                end
            end
        end
        return nil
    end
end

local function move_file(from, to)
    if os_name == "windows" then
        os.remove(to)
    end
    -- move the file because it can get overwritten while overlay-add is reading it, and crash the player
    os.rename(from, to)
end

local function seek(fast)
    if last_seek_time then
        run("async seek " .. last_seek_time .. (fast and " absolute+keyframes" or " absolute+exact"))
    end
end

local seek_period = 3/60
local seek_period_counter = 0
local seek_timer
seek_timer = mp.add_periodic_timer(seek_period, function()
    if seek_period_counter == 0 then
        seek(allow_fast_seek)
        seek_period_counter = 1
    else
        if seek_period_counter == 2 then
            if allow_fast_seek then
                seek_timer:kill()
                seek()
            end
        else seek_period_counter = seek_period_counter + 1 end
    end
end)
seek_timer:kill()

local function request_seek()
    if seek_timer:is_enabled() then
        seek_period_counter = 0
    else
        seek_timer:resume()
        seek(allow_fast_seek)
        seek_period_counter = 1
    end
end

local function check_new_thumb()
    -- the slave might start writing to the file after checking existance and
    -- validity but before actually moving the file, so move to a temporary
    -- location before validity check to make sure everything stays consistant
    -- and valid thumbnails don't get overwritten by invalid ones
    local tmp = options.thumbnail..".tmp"
    move_file(options.thumbnail, tmp)
    local finfo = utils.file_info(tmp)
    if not finfo then return false end
    spawn_waiting = false
    local w, h = real_res(effective_w, effective_h, finfo.size)
    if w then -- only accept valid thumbnails
        move_file(tmp, options.thumbnail..".bgra")

        real_w, real_h = w, h
        if real_w and (real_w ~= last_real_w or real_h ~= last_real_h) then
            last_real_w, last_real_h = real_w, real_h
            info(real_w, real_h)
        end
        if not show_thumbnail then
            file_timer:kill()
        end
        return true
    end

    return false
end

file_timer = mp.add_periodic_timer(file_check_period, function()
    if check_new_thumb() then
        draw(real_w, real_h, script_name)
    end
end)
file_timer:kill()

local function clear()
    if Thumbnailer.state.available then
        if osc_thumb_state.visible then
            mp.command_native({"overlay-remove", options.overlay_id})
            progress_bar:remove()
            osc_thumb_state.visible = false
        end
    else
        file_timer:kill()
        seek_timer:kill()
        if options.quit_after_inactivity > 0 then
            if show_thumbnail or activity_timer:is_enabled() then
                activity_timer:kill()
            end
            activity_timer:resume()
        end
        last_seek_time = nil
        show_thumbnail = false
        last_x = nil
        last_y = nil
        if script_name then return end
        if pre_0_30_0 then
            mp.command_native({"overlay-remove", options.overlay_id})
        else
            mp.command_native_async({"overlay-remove", options.overlay_id}, function() end)
        end
    end
end

local function quit()
    activity_timer:kill()
    if show_thumbnail then
        activity_timer:resume()
        return
    end
    run("quit")
    spawned = false
    real_w, real_h = nil, nil
    clear()
end

activity_timer = mp.add_timeout(options.quit_after_inactivity, quit)
activity_timer:kill()

local function thumb(time, r_x, r_y, script)
    if disabled or not video_loaded then return end

    time = tonumber(time)
    if time == nil then return end

    if r_x == "" or r_y == "" then
        x, y = nil, nil
    else
        x, y = math.floor(r_x + 0.5), math.floor(r_y + 0.5)
    end

    script_name = script
    if Thumbnailer.state.available then
        display_storyboard_thumbnail(time, x, y, script)
    else
        if last_x ~= x or last_y ~= y or not show_thumbnail then
            show_thumbnail = true
            last_x = x
            last_y = y
            draw(real_w, real_h, script)
        end

        if options.quit_after_inactivity > 0 then
            if show_thumbnail or activity_timer:is_enabled() then
                activity_timer:kill()
            end
            activity_timer:resume()
        end

        if time == last_seek_time then return end
        last_seek_time = time
        if not spawned then spawn(time) end
        request_seek()
        if not file_timer:is_enabled() then file_timer:resume() end
    end
end

local function watch_changes(fully_loaded)
    if not dirty or not properties["video-out-params"] or storyboard_requested then return end
    dirty = false

    local old_w = effective_w
    local old_h = effective_h
    if vid_off == false then
        calc_dimensions()
    end

    local vf_reset = vf_string(filters_reset)
    local rotate = properties["video-rotate"] or 0

    local resized = old_w ~= effective_w or
        old_h ~= effective_h or
        last_vf_reset ~= vf_reset or
        (last_rotate % 180) ~= (rotate % 180) or
        par ~= last_par

    if resized then
        last_rotate = rotate
        info(effective_w, effective_h)
    elseif last_has_vid ~= has_vid and has_vid ~= 0 then
        info(effective_w, effective_h)
    end

    if spawned then
        if resized then
            -- mpv doesn't allow us to change output size
            local seek_time = last_seek_time
            run("quit")
            clear()
            spawned = false
            spawn(seek_time or mp.get_property_number("time-pos", 0))
            file_timer:resume()
        else
            if rotate ~= last_rotate then
                run("set video-rotate "..rotate)
            end
            local vf_runtime = vf_string(filters_runtime)
            if vf_runtime ~= last_vf_runtime then
                run("vf set "..vf_string(filters_all, true))
                last_vf_runtime = vf_runtime
            end
        end
    else
        last_vf_runtime = vf_string(filters_runtime)
    end

    last_vf_reset = vf_reset
    last_rotate = rotate
    last_par = par
    last_has_vid = has_vid

    if not spawned and not disabled and options.spawn_first and fully_loaded then
        spawn(mp.get_property_number("time-pos", 0))
        file_timer:resume()
    end
end

local function update_property(name, value)
    properties[name] = value
end

local function update_property_dirty(name, value)
    properties[name] = value
    dirty = true
    if name == "tone-mapping" then
        last_tone_mapping = nil
    end
end

local function update_tracklist(name, value)
    -- current-tracks shim
    for _, track in ipairs(value) do
        if track.type == "video" and track.selected then
            properties["current-tracks/video/image"] = track.image
            properties["current-tracks/video/albumart"] = track.albumart
            return
        end
    end
end

local function sync_changes(prop, val)
    if not options.apply_video_filters then
        check_disabled_video()
    end
    
    update_property(prop, val)
    if val == nil then return end

    if type(val) == "boolean" then
        if prop == "vid" then
            has_vid = 0
            last_has_vid = 0
            info(effective_w, effective_h)
            clear()
            return
        end
        val = val and "yes" or "no"
    end

    if prop == "vid" then
        has_vid = 1
    end

    if not spawned then return end

    run("set "..prop.." "..val)
    dirty = true
end

local function file_load()
    video_loaded = true
    clear()
    spawned = false
    real_w, real_h = nil, nil
    last_real_w, last_real_h = nil, nil
    last_tone_mapping = nil
    last_seek_time = nil
    if info_timer then
        info_timer:kill()
        info_timer = nil
    end

    if not storyboard_requested then -- don't allow conflict between thumbfast and storyboard thumbnailer
        calc_dimensions()
        info(effective_w, effective_h)
    end
end

local function shutdown()
    run("quit")
    remove_thumbnail_files()
    if os_name ~= "windows" then
        os.remove(options.socket)
        os.remove(options.socket..".run")
    end
end

local function on_duration(prop, val)
    allow_fast_seek = (val or 30) >= 30
end

mp.observe_property("current-tracks", "native", function(name, value)
    if pre_0_33_0 then
        mp.unobserve_property(update_tracklist)
        pre_0_33_0 = false
    end
    update_property(name, value)
end)


mp.observe_property("track-list", "native", update_tracklist)
mp.observe_property("display-hidpi-scale", "native", update_property_dirty)
mp.observe_property("video-out-params", "native", update_property_dirty)
mp.observe_property("video-params", "native", update_property_dirty)
mp.observe_property("vf", "native", update_property_dirty)
mp.observe_property("tone-mapping", "native", update_property_dirty)
mp.observe_property("demuxer-via-network", "native", update_property)
mp.observe_property("stream-open-filename", "native", update_property)
mp.observe_property("macos-app-activation-policy", "native", update_property)
mp.observe_property("current-vo", "native", update_property)
mp.observe_property("video-rotate", "native", update_property)
mp.observe_property("path", "native", update_property)
mp.observe_property("vid", "native", sync_changes)
mp.observe_property("edition", "native", sync_changes)
mp.observe_property("duration", "native", on_duration)

mp.register_script_message("thumb", thumb)
mp.register_script_message("clear", clear)

mp.register_event("file-loaded", file_load)
mp.register_event("shutdown", shutdown)
if options.spawn_first then
    mp.register_event("playback-restart", function()
        -- video is fully loaded at this moment, all properties are actual, so we are ready to spawn a thumbnailer
        if not spawned then
            dirty = true
            watch_changes(true)
        end
    end)
end

mp.register_idle(watch_changes)



local check_generation_progress = mp.add_periodic_timer(3, function()
    local thumbs_ready = Thumbnailer.state.finished_thumbnails
    local thumbs_total = Thumbnailer.state.thumbnail_count
    if thumbs_ready == thumbs_total or not Thumbnailer.state.enabled then
        stop_checking()
        return
    end
    
    if thumbs_ready == prev_thumb_count then
        if antistuck_attempt < 3 then
            antistuck_attempt = antistuck_attempt + 1
            msg.warn("Thumbnailing process was stuck, restarting")
            Thumbnailer:start_worker_jobs()
        else
            local err = "Thumbnailing process was stuck, giving up after 3 retries"
            msg.error(err)
            mp.osd_message(err)
            stop_checking()
        end
    else
        antistuck_attempt = 0
    end
    prev_thumb_count = thumbs_ready
end)
check_generation_progress:kill()

function stop_checking()
    if check_generation_progress:is_enabled() then check_generation_progress:kill() end
    prev_thumb_count = 0
    antistuck_attempt = 0
end

local recently_updated = false
function request_update_thumbnail()
    -- update thumbnail and progress bar after generating a new thumbnail if it was displayed
    if osc_thumb_state.visible and osc_thumb_state.last_time and (not recently_updated or Thumbnailer.state.finished_thumbnails == Thumbnailer.state.thumbnail_count) then
        recently_updated = true -- don't update too often
        osc_thumb_state.visible = false -- forcefully update the thumbnail in the same position
        display_storyboard_thumbnail(osc_thumb_state.last_time, osc_thumb_state.last_x, osc_thumb_state.last_y)
        mp.add_timeout(0.1, function() recently_updated = false end)
    end
end

function Thumbnailer:clear_state()
    clear_table(self.state)
    clear_table(osc_thumb_state)
    self.state.ready = false
    self.state.available = false
    self.state.finished_thumbnails = 0
    self.state.thumbnails = {}
    self.state.worker_extra = {}
    self.state.storyboard = nil
    storyboard_requested = false
end

function Thumbnailer:on_thumb_ready(index)
    self.state.thumbnails[index] = 1

    -- Full recount instead of a naive increment (let's be safe!)
    self.state.finished_thumbnails = 0
    for i, v in pairs(self.state.thumbnails) do
        if v > 0 then
            self.state.finished_thumbnails = self.state.finished_thumbnails + 1
        end
    end
    request_update_thumbnail()
end

function Thumbnailer:on_thumb_progress(index)
    self.state.thumbnails[index] = (self.state.thumbnails[index] == 1) and 1 or 0
    request_update_thumbnail()
end

function Thumbnailer:on_start_file()
    -- Clear state when a new file is being loaded
    self:clear_state()
    
    local path = mp.get_property("path")
    if path and path:find("^https?://") and not self.state.ready and options.storyboard_enable then
        if options.use_url_whitelist then
            local domain = path:match("https?://([^/]+)") or ""
            while domain:find("%.") do -- check both domains and subdomains for existance in the list
                if url_table[domain] then
                    self:request_storyboard(path)
                    break
                end
                domain = domain:gsub("^[^%.]*%.", "")
            end
        else
            self:request_storyboard(path)
        end
    end
end

function Thumbnailer:request_storyboard(initial_path)
    local function on_success()
        if mp.get_property("path") == initial_path and self.state.available then
            self.state.thumbnail_template, self.state.thumbnail_directory = self:get_thumbnail_template()
            self:start_worker_jobs()
        end
    end
    
    msg.info("Trying to get storyboard info...")
    storyboard_requested = true
    local json, err = utils.format_json({width=0, height=0, disabled=true, available=false, socket=options.socket, thumbnail=options.thumbnail, overlay_id=options.overlay_id})
    mp.command_native({"script-message", "thumbfast-info", json}) -- disable availability of the thumbnailer until we get storyboard data
    self.state.ready = true
    if not initial_path:find("https?://[^/]*rutube%.ru") then
        self:check_storyboard_async(on_success)
    else
        -- yt-dlp does not support extracting storyboards for Rutube
        -- however, we can obtain all the necessary data, knowing only the direct stream link and video duration
        local function on_loaded()
            if mp.get_property("path") == initial_path and mp.get_property("duration") then
                self:check_rutube_storyboard(on_success)
            end
            mp.unregister_event(on_loaded)
        end
        
        if mp.get_property("duration") then
            self:check_rutube_storyboard(on_success) -- video has already finished loading
        else
            mp.register_event("file-loaded", on_loaded)
        end
    end
end

function Thumbnailer:obtain_dimensions(url)
    msg.debug("Obtaining accurate dimensions of " .. url .. " using mpv")
    local mpv_args = {
        options.mpv_path, "--no-config", "--video=no", "--audio=no",
        "--user-agent=" .. mp.get_property_native("user-agent"),
        "--referrer=" .. mp.get_property_native("referrer"),
        "--", url
    }
    local res = mp.command_native({
        name = "subprocess",
        args = mpv_args,
        capture_stdout = true,
        capture_stderr = true
    })
    local dimensions = res.stdout:lower():match("%-%-vid=1%s+%(%w+%s+(%d+x%d+)")
    if dimensions then
        local width = tonumber(dimensions:match("(%d+)x"))
        local height = tonumber(dimensions:match("x(%d+)"))
        msg.debug("Received dimensions: " .. width .. "x" .. height .. " from output:\n" .. res.stdout)
        return width, height
    else
        msg.verbose("Failed to get dimensions of " .. url .. "\nstdout: " .. res.stdout .. "\nstderr:" .. res.stderr) -- error will be logged separately
    end
end

-- Check for storyboards existance with yt-dlp and call back on success (may take a long time)
function Thumbnailer:check_storyboard_async(callback)
    local sb_cmd = {"yt-dlp", "--format", "sb0", "--dump-json", "--no-playlist", "--no-warnings",
                    "--extractor-args", "youtube:skip=hls,dash,translated_subs", -- yt speedup
                    "--", mp.get_property_native("path")}
    local ytdl_opts = mp.get_property_native("ytdl-raw-options") or {}
    for param, arg in pairs(ytdl_opts) do -- add ytdl options from mpv.conf
        if param == "extractor-args" and arg and arg:find("^youtube:") then
            sb_cmd[#sb_cmd - 2] = arg .. ";skip=hls,dash,translated_subs" -- try to preserve yt speedup
        else
            table.insert(sb_cmd, 2, "--" .. param)
            if arg and arg ~= "" then
                table.insert(sb_cmd, 3, arg) 
            end
        end
    end
    
    mp.command_native_async({name="subprocess", args=sb_cmd, capture_stdout=true}, function(success, sb_json)
        if success and sb_json.status == 0 then
            local sb = utils.parse_json(sb_json.stdout)
            if sb and sb.duration and sb.width and sb.height and sb.fragments and #sb.fragments > 0 then
                self.state.storyboard = {}
                self.state.storyboard.fragments = sb.fragments
                self.state.storyboard.fragment_base_url = sb.fragment_base_url
                self.state.storyboard.rows = sb.rows or 5
                self.state.storyboard.cols = sb.columns or 5
                
                if options.recheck_storyboard_dimensions then
                    -- yt-dlp sometimes gives slightly incorrect storyboard width with a 1-pixel error, which completely breaks thumbnails
                    -- Examples of "problematic" videos:
                    -- https://www.youtube.com/watch?v=ntpgDg3O6h8 (159 instead of 160)
                    -- https://www.youtube.com/watch?v=DF6W1XD25Dc (120 instead of 119)
                    local sb_w, sb_h = self:obtain_dimensions(sb.fragments[1].url)
                    if sb_w and sb_h then
                        if sb_w % sb.rows == 0 and sb_h % sb.columns == 0 then
                            local actual_w = sb_w / sb.columns
                            local actual_h = sb_h / sb.rows
                            if sb.width - actual_w ~= 0 or sb.height - actual_h ~= 0 then
                                msg.info(string.format("Storyboard dimensions was fixed from %dx%d to %dx%d", sb.width, sb.height, actual_w, actual_h))
                            end
                            sb.width = actual_w
                            sb.heigth = actual_h
                        else
                            msg.warn("Actual storyboard dimensions is not divisible by count of thumbnails for each dimension! Thumbnails might be broken")
                        end
                    else
                        msg.warn("Unable to get actual storyboard dimensions, using approximate data by yt-dlp")
                    end
                end

                if sb.fps then
                    self.state.thumbnail_count = math.floor(sb.fps * sb.duration + 0.5) -- round
                    -- hack: youtube always adds 1 black frame at the end...
                    if sb.extractor == "youtube" then
                        self.state.thumbnail_count = self.state.thumbnail_count - 1
                    end
                else
                    -- estimate the count of thumbnails
                    -- assume first atlas is always full
                    self.state.thumbnail_delta = sb.fragments[1].duration / (self.state.storyboard.rows*self.state.storyboard.cols)
                    self.state.thumbnail_count = math.floor(sb.duration / self.state.thumbnail_delta)
                end
                self.state.original_count = self.state.thumbnail_count

                -- Storyboard upscaling factor
                local scale = 1
                local w, h = get_size(sb.width, sb.height, options.max_width, options.max_height)
                if self.state.storyboard.rows > 1 or self.state.storyboard.cols > 1 then
                    if options.storyboard_upscale and not mpv_0_38_above then
                        -- BUG: sometimes mpv crashes when asked for non-integer scaling and BGRA format (something related to zimg?)
                        -- use integer scaling for now
                        scale = math.max(1, math.floor(h / sb.height))
                    end
                    self.state.thumbnail_size = {w=sb.width*scale, h=sb.height*scale}
                else
                    if h > sb.height and options.storyboard_upscale and not mpv_0_38_above then
                        scale = math.max(1, h / sb.height)
                    elseif h < sb.height then
                        scale = math.max(0.1, h / sb.height)
                    end
                    self.state.thumbnail_size = {w=math.floor(sb.width*scale+0.5), h=math.floor(sb.height*scale+0.5)}
                end
                self.state.storyboard.scale = scale

                local divisor = 1 -- only save every n-th thumbnail
                if options.storyboard_max_thumbnail_count then
                    divisor = math.ceil(self.state.thumbnail_count / options.storyboard_max_thumbnail_count)
                end
                self.state.storyboard.divisor = divisor
                self.state.thumbnail_count = math.floor(self.state.thumbnail_count / divisor)
                self.state.thumbnail_delta = sb.duration / self.state.thumbnail_count

                -- Prefill individual thumbnail states
                self.state.thumbnails = {}
                for i = 1, self.state.thumbnail_count do
                    self.state.thumbnails[i] = -1
                end

                msg.info(string.format("Storyboard info acquired! Using %d of %d thumbnails sized %dx%d", self.state.thumbnail_count, self.state.original_count, sb.width, sb.height))
                self.state.available = true
                callback()
            end
        end
    end)
end

function Thumbnailer:check_rutube_storyboard(on_success)
    local duration = mp.get_property_number("duration")
    local direct_link = mp.get_property("stream-open-filename"):match("https?://[^!]+") or ""
    local base_url = direct_link:match("(.+%.mp4)%.m3u8")
    if base_url then
        local sb_w, sb_h = self:obtain_dimensions(base_url .. "/Sec0.jpg?size=m") -- obtain dimensions of the first thumbnail
        if sb_w and sb_h then
            self.state.storyboard = {}
            self.state.storyboard.rows = 1
            self.state.storyboard.cols = 1
            self.state.storyboard.fragments = {}

            local max_count = options.storyboard_max_thumbnail_count
            if duration / max_count < options.rutube_thumbnail_interval then
                max_count = math.max(math.floor(duration / options.rutube_thumbnail_interval + 0.5), options.rutube_min_thumbnail_target)
            end

            local step = duration / math.min(max_count, duration)
            local thumb_pos = 0
            while math.ceil(thumb_pos) < duration do
                local frag = {}
                frag.duration = step
                frag.url = base_url .. "/Sec" .. math.floor(thumb_pos + 0.5) .. ".jpg?size=m" -- these are the same thumbnails used in the web player
                table.insert(self.state.storyboard.fragments, frag)
                thumb_pos = thumb_pos + step
            end

            self.state.thumbnail_delta = step
            self.state.thumbnail_count = #self.state.storyboard.fragments
            self.state.original_count = math.ceil(duration)
            self.state.storyboard.divisor = 1

            local scale = 1
            local w, h = get_size(sb_w, sb_h, options.max_width, options.max_height)
            if h > sb_h and options.storyboard_upscale and not mpv_0_38_above then
                scale = math.max(1, h / sb_h)
            elseif h < sb_h then
                scale = math.max(0.1, h / sb_h)
            end
            -- Fix washed out colors due to incorrect colorlevels of thumbnails during their processing
            self.state.thumbnail_size = { w=math.floor(sb_w*scale+0.5), h=math.floor(sb_h*scale+0.5), col_corr=":in_range=limited:out_range=full" }
            self.state.storyboard.scale = scale

            self.state.thumbnails = {}
            for i = 1, self.state.thumbnail_count do
                self.state.thumbnails[i] = -1
            end
            
            msg.info(string.format("Storyboard info acquired! Using %d of %d thumbnails sized %dx%d", self.state.thumbnail_count, self.state.original_count, sb_w, sb_h))
            self.state.available = true
            on_success()
        else
            msg.error("Unable to obtain Rutube thumbnail dimensions, or storyboard unavailable")
        end
    else
        msg.error("Unable to extract Rutube storyboard URL")
    end
end

function Thumbnailer:get_thumbnail_template()
    local filename = mp.get_property_native("path")
    if not filename then return end

    filename = filename:gsub('[^a-zA-Z0-9_.%-\' ]', '_')
    if #filename > 128 then 
        filename = filename:sub(1, 128) -- long filenames may approach filesystem limits, so trim the excess part
    end
    filename = filename .. "-" .. self.state.thumbnail_count -- generate a new thumbnails if their count is different from previous count for the same video

    local thumbnail_directory = join_paths(self.cache_directory, filename)
    local file_template = join_paths(thumbnail_directory, "%06d.bgra")
    return file_template, thumbnail_directory
end

function Thumbnailer:get_closest(thumbnail_index)
    -- Given a 1-based index, find the closest available thumbnail and return its 1-based index
   local t = self.state.thumbnails

   -- Look in the neighbourhood
   local dist = 0
   while dist < self.state.thumbnail_count do
       if t[thumbnail_index - dist] and t[thumbnail_index - dist] > 0 then
           return thumbnail_index - dist
       elseif t[thumbnail_index + dist] and t[thumbnail_index + dist] > 0 then
           return thumbnail_index + dist
       end
       dist = dist + 1
   end
end

function Thumbnailer:get_thumbnail_index(time_position)
    -- Returns a 1-based thumbnail index for the given timestamp (between 1 and thumbnail_count, inclusive)
    if self.state.thumbnail_delta and (self.state.thumbnail_count and self.state.thumbnail_count > 0) then
        -- make thumbnail represent the middle of its interval
        return math.min(math.floor((time_position + 0.5 * self.state.thumbnail_delta) / self.state.thumbnail_delta) + 1, self.state.thumbnail_count)
    end
end

function Thumbnailer:get_thumbnail_path(time_position)
    -- Given a timestamp, return:
    --   the closest available thumbnail path (if any)
    --   the 1-based thumbnail index calculated from the timestamp
    --   the 1-based thumbnail index of the closest available (and used) thumbnail
    -- OR nil if thumbnails are not available.

    local thumbnail_index = self:get_thumbnail_index(time_position)
    if not thumbnail_index then return nil end

    local closest = self:get_closest(thumbnail_index)

    if closest then
        return self.state.thumbnail_template:format(closest-1), thumbnail_index, closest
    else
        return nil, thumbnail_index, nil
    end
end

function Thumbnailer:register_client()
    -- Create additional workers to reach the specified number of thumbnailing threads
    -- (Why multiple copies of the same file? mpv gives each script their own thread - easy multithreading!)
    local additional_threads = options.thumbnailing_threads - 1
    if options.storyboard_enable and additional_threads > 0 then
        local worker_script_path = debug.getinfo(1).source:match('@?(.*/)') .. "thumbnail-generator.lua"
        local script_file = io.open(worker_script_path, "r")
        if script_file then
            script_file:close()
            msg.debug("Creating additional " .. additional_threads .. " thumbnail worker(s)")
            for i = 1, additional_threads do
                mp.commandv("load-script", worker_script_path)
            end
        else
            msg.error("Cannot create additional " .. additional_threads .. " thumbnail worker(s)! Script thumbnail-generator.lua is not found at " .. worker_script_path)
        end
    end

    self.worker_register_timeout = mp.get_time() + 2

    mp.register_script_message("mpv_thumbnail_script-ready", function(index, path)
        self:on_thumb_ready(tonumber(index), path)
    end)
    mp.register_script_message("mpv_thumbnail_script-progress", function(index, path)
        self:on_thumb_progress(tonumber(index), path)
    end)

    mp.register_script_message("mpv_thumbnail_script-worker", function(worker_name)
        if not self.workers[worker_name] then
            msg.debug("Registered worker", worker_name)
            self.workers[worker_name] = true
            mp.commandv("script-message-to", worker_name, "mpv_thumbnail_script-slaved")
        end
    end)
end

function Thumbnailer:_create_thumbnail_job_order()
    -- Returns a list of 1-based thumbnail indices in a job order
    local work_frames = {}

    -- Find a step large enough
    local step = 1
    repeat
        step = step * 2
    until step > self.state.thumbnail_count

    -- Fill the table with increasing frequency
    while step > 1 do
        for i = step/2, self.state.thumbnail_count, step do
            table.insert(work_frames, i)
        end
        step = step / 2
    end

    return work_frames
end

function Thumbnailer:start_worker_jobs()
    if not self.state.available or not self.state.thumbnail_directory then return end
    
    -- Create directory for the thumbnails, if needed
    local l, err = utils.file_info(self.state.thumbnail_directory)
    if err then
        msg.debug("Creating thumbnail directory", self.state.thumbnail_directory)
        create_directories(self.state.thumbnail_directory)
    elseif options.clear_cache_timeout > 0 then
        -- (Re)create a file in thumbnail directory to updatr last modified date of the folder
        os.remove(join_paths(self.state.thumbnail_directory, "last_opened.txt"))
        local file = io.open(join_paths(self.state.thumbnail_directory, "last_opened.txt"), "w")
        if file then
            file:write(os.date())
            file:close()
        end
    end
    
    if not check_generation_progress:is_enabled() then check_generation_progress:resume() end

    local worker_list = {}
    for worker_name in pairs(self.workers) do table.insert(worker_list, worker_name) end

    local worker_count = #worker_list

    -- In case we have a worker timer created already, clear it
    if self.worker_wait_timer then
        self.worker_wait_timer:stop()
    end

    if worker_count == 0 then
        local now = mp.get_time()
        if mp.get_time() > self.worker_register_timeout then
            -- Workers have had their time to register but we have none!
            local err = "No thumbnail workers found. Make sure you are not missing a script!"
            msg.error(err)
            mp.osd_message(err, 3)

        else
            -- We may be too early. Delay the work start a bit to try again.
            msg.warn("No workers found. Waiting a bit more for them.")
            -- Wait at least half a second
            local wait_time = math.max(self.worker_register_timeout - now, 0.5)
            self.worker_wait_timer = mp.add_timeout(wait_time, function() self:start_worker_jobs() end)
        end

    else
        -- We have at least one worker. This may not be all of them, but they have had
        -- their time to register; we've done our best waiting for them.
        self.state.enabled = true

        msg.debug( ("Splitting %d thumbnails amongst %d worker(s)"):format(self.state.thumbnail_count, worker_count) )

        local frame_job_order = self:_create_thumbnail_job_order()
        local worker_jobs = {}
        for i = 1, worker_count do worker_jobs[worker_list[i]] = {} end

        -- Split frames amongst the workers
        for i, thumbnail_index in ipairs(frame_job_order) do
            local worker_id = worker_list[ ((i-1) % worker_count) + 1 ]
            table.insert(worker_jobs[worker_id], thumbnail_index)
        end

        local state_json_string, err = utils.format_json(self.state)
        if err then
            msg.warn("JSON converting error, can't start working jobs: " .. err)
            return
        end
        msg.debug("Giving workers state:", state_json_string)

        for worker_name, worker_frames in pairs(worker_jobs) do
            if #worker_frames > 0 then
                local frames_json_string = utils.format_json(worker_frames)
                msg.debug("Assigning job to", worker_name, frames_json_string)
                mp.commandv("script-message-to", worker_name, "mpv_thumbnail_script-job", state_json_string, frames_json_string)
            end
        end
        
        displaying_size_w = self.state.thumbnail_size.w
        displaying_size_h = self.state.thumbnail_size.h
        if mpv_0_38_above then
            displaying_size_w, displaying_size_h = get_size(displaying_size_w, displaying_size_h, options.max_width, options.max_height)
        end
        
        disabled = false
        local json, err = utils.format_json({width=displaying_size_w, height=displaying_size_h, disabled=false, available=true, socket=options.socket, thumbnail=options.thumbnail, overlay_id=options.overlay_id})
        mp.command_native({"script-message", "thumbfast-info", json})
    end
end

mp.register_event("start-file", function() Thumbnailer:on_start_file() end)
mp.register_event("end-file", function()
    video_loaded = false
    clear() -- remove thumbnail if it was displayed
    stop_checking()
end)

Thumbnailer:register_client()

function display_storyboard_thumbnail(target_time, x, y, script)
    -- If thumbnails are not available, bail
    if not (Thumbnailer.state.enabled and Thumbnailer.state.available) then return end

    if not osc_thumb_state.visible or not (osc_thumb_state.last_time == target_time and osc_thumb_state.last_x == x and osc_thumb_state.last_y == y) then
        local thumb_size = Thumbnailer.state.thumbnail_size
        local thumb_path, thumb_index, closest_index = Thumbnailer:get_thumbnail_path(target_time)
        if thumb_path then
            if script then -- NOT TESTED, probably won't work; uosc and default osc don't use this
                local json, err = utils.format_json({width=thumb_size.w, height=thumb_size.h, x=x, y=y, socket=options.socket, thumbnail=thumb_path:gsub("%.bgra$", ""), overlay_id=options.overlay_id})
                mp.commandv("script-message-to", script, "thumbfast-render", json)
            else
                local overlay_add_args = {
                    "overlay-add", options.overlay_id,
                    x, y,
                    thumb_path,
                    0,
                    "bgra",
                    thumb_size.w, thumb_size.h,
                    4 * thumb_size.w
                }
                if mpv_0_38_above then
                    table.insert(overlay_add_args, displaying_size_w)
                    table.insert(overlay_add_args, displaying_size_h)
                end
                mp.command_native(overlay_add_args)

                osc_thumb_state.last_time = target_time
                osc_thumb_state.last_x = x
                osc_thumb_state.last_y = y
                osc_thumb_state.visible = true
            end       
        end
        -- Draw thumbnailing progress bar
        if not options.hide_progress and not script then
            local thumbs_ready = Thumbnailer.state.finished_thumbnails
            local thumbs_total = Thumbnailer.state.thumbnail_count
            if thumbs_ready < thumbs_total then
                progress_bar.res_x = mp.get_property_number("osd-width") or 0
                progress_bar.res_y = mp.get_property_number("osd-height") or 0

                local ass = assdraw.ass_new()
                local scale = properties["display-hidpi-scale"] or 1
                local progress_bar_w = displaying_size_w
                local progress_bar_h = 24 * scale
                local bg_left = x + (displaying_size_w - progress_bar_w) / 2
                local bg_top = y - progress_bar_h - (options.vertical_offset * scale)
                
                -- Draw background
                ass:new_event()
                ass:pos(bg_left, bg_top)
                ass:append(("{\\bord0\\1c&H%s&\\1a&H%X&}"):format(options.background_color, options.background_alpha))
                ass:draw_start()
                ass:round_rect_cw(0, 0, progress_bar_w, progress_bar_h, 2 * scale)
                ass:draw_stop()
                
                -- Scale text to correct size and draw it
                ass:new_event()
                ass:pos(bg_left + progress_bar_w/2, bg_top)
                ass:an(8)
                ass:append(("{\\fs%f\\bord0\\1a&H%X&}"):format(20 * scale, options.text_alpha))
                ass:append(("%d%% - %d/%d"):format(math.floor((thumbs_ready / thumbs_total) * 100), thumbs_ready, thumbs_total))

                -- Draw thumbnailing progress line
                ass:new_event()
                ass:pos(bg_left + (2 * scale), bg_top + progress_bar_h - math.floor(3 * scale + 0.5))
                local estimated_progress = thumbs_ready / thumbs_total -- estimated thumbnailing progress that not equal to count of generated thumbnails if using atlases
                if Thumbnailer.state.storyboard and Thumbnailer.state.storyboard.rows > 1 and Thumbnailer.state.storyboard.cols > 1 then
                    estimated_progress = estimated_progress * Thumbnailer.state.storyboard.rows * Thumbnailer.state.storyboard.cols * 0.9 * (thumbs_total / Thumbnailer.state.original_count)
                end
                ass:append(("{\\bord0\\1c&H70E070&\\1a&H%X&"):format(options.text_alpha))
                ass:draw_start()
                ass:rect_cw(0, 0, math.min(estimated_progress, 1) * (progress_bar_w - (4 * scale)), 2 * scale)
                ass:draw_stop()
                
                progress_bar.data = ass.text
                progress_bar:update()
                osc_thumb_state.visible = true
            else
                progress_bar:remove()
            end
        end
    end
end


if options.clear_cache_timeout >= 0 then
    mp.register_event("end-file", function()
        if not Thumbnailer.state.available then return end -- check saved thumbnail files only if they were generated for previous video
        
        local time = os.time()
        local folders = utils.readdir(options.cache_directory)
        if folders then
            msg.debug("Starting deletion of old folders with saved thumbnails")
            for k,v in pairs(folders) do
                local dir = join_paths(options.cache_directory, v)
                local modtime = utils.file_info(dir)["mtime"]
                if options.clear_cache_timeout == 0 or (modtime and (time - modtime) > (options.clear_cache_timeout * 86400)) then
                    local files = utils.readdir(dir)
                    msg.verbose("Deleting thumbnails cache folder: " .. dir .. " (" .. #files .. " files)")
                    for _, file in pairs(files) do
                        os.remove(join_paths(dir, file))
                    end
                    if ON_WINDOWS then
                        mp.command('run cmd /c rmdir "' .. dir:gsub("\\", "\\\\") .. '"') -- on Windows, os.remove can't delete folders, even empty ones
                    else
                        os.remove(dir) -- this should work on other platforms (not tested)
                    end
                end
            end
            msg.debug("Deletion of old folders with thumbnails is finished")
        else
            msg.warn("Cannot read directory to delete old thumbnails")
        end
    end)
end
