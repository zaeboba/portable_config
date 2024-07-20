-- Script is patched for working with blur_edges (also works on mpv v0.35.1)

--[[
This script uses the lavfi cropdetect filter and the video-crop property to
automatically crop the currently playing video with appropriate parameters.

It automatically crops the video when playback starts.

You can also manually crop the video by pressing the "C" (shift+c) key.
Pressing it again undoes the crop.

The workflow is as follows: First, it inserts the cropdetect filter. After
<detect_seconds> (default is 1) seconds, it then sets video-crop based on the
vf-metadata values gathered by cropdetect. The cropdetect filter is removed
after video-crop is set as it is no longer needed.

Since the crop parameters are determined from the 1 second of video between
inserting the cropdetect filter and setting video-crop, the "C" key should be
pressed at a position in the video where the crop region is unambiguous (i.e.,
not a black frame, black background title card, or dark scene).

If non-copy-back hardware decoding is in use, hwdec is temporarily disabled for
the duration of cropdetect as the filter would fail otherwise.

These are the default options. They can be overridden by adding
script-opts-append=autocrop-<parameter>=<value> to mpv.conf.
--]]
local options = {
    -- Whether to automatically apply crop at the start of playback. If you
    -- don't want to crop automatically, add
    -- script-opts-append=autocrop-auto=no to mpv.conf.
    auto = false,
    -- Delay before starting crop in auto mode. You can try to increase this
    -- value to avoid dark scenes or fade ins at beginning. Automatic cropping
    -- will not occur if the value is larger than the remaining playback time.
    auto_delay = 4,
    -- Black threshold for cropdetect. Smaller values will generally result in
    -- less cropping. See limit of
    -- https://ffmpeg.org/ffmpeg-filters.html#cropdetect
    detect_limit = "24/255",
    -- The value which the width/height should be divisible by. Smaller
    -- values have better detection accuracy. If you have problems with
    -- other filters, you can try to set it to 4 or 16. See round of
    -- https://ffmpeg.org/ffmpeg-filters.html#cropdetect
    detect_round = 2,
    -- The ratio of the minimum clip size to the original. A number from 0 to
    -- 1. If the picture is over cropped, try adjusting this value.
    detect_min_ratio = 0.5,
    -- How long to gather cropdetect data. Increasing this may be desirable to
    -- allow cropdetect more time to collect data.
    detect_seconds = 0.5,
    -- How many attempts perform to gather cropdetect data
    attempts = 5,
    -- Whether the OSD shouldn't be used when cropdetect and video-crop are
    -- applied and removed.
    suppress_osd = false,
}

require "mp.options".read_options(options)

local cropdetect_label = mp.get_script_name() .. "-cropdetect"
local attempt = 0
local silent = false
local addcrop = 0

timers = {
    auto_delay = nil,
    detect_crop = nil
}

local hwdec_backup

local command_prefix = 'no-osd'

function is_enough_time(seconds)

    -- Plus 1 second for deviation.
    local time_needed = seconds + 1
    local playtime_remaining = mp.get_property_native("playtime-remaining")

    return playtime_remaining and time_needed < playtime_remaining
end

function is_cropable(time_needed)
    if mp.get_property_native('current-tracks/video/image') ~= false then
        mp.msg.warn("autocrop only works for videos.")
        return false
    end

    if not is_enough_time(time_needed) then
        mp.msg.warn("Not enough time to detect crop.")
        return false
    end

    return true
end

function remove_cropdetect()
    for _, filter in pairs(mp.get_property_native("vf")) do
        if filter.label == cropdetect_label then
            mp.command(
                string.format("%s vf remove @%s", command_prefix, filter.label))

            return
        end
    end
end

function restore_hwdec()
    if hwdec_backup then
        mp.set_property("hwdec", hwdec_backup)
        hwdec_backup = nil
    end
end

function cleanup()
    remove_cropdetect()

    -- Kill all timers.
    for index, timer in pairs(timers) do
        if timer then
            timer:kill()
            timers[index] = nil
        end
    end

    restore_hwdec()
end

function detect_crop()
    osd_info("Поиск чёрных полей...")
    local time_needed = options.detect_seconds

    if not is_cropable(time_needed) then
        return
    end

    local hwdec_current = mp.get_property("hwdec-current")
    if mp.get_property("hwdec"):find("-copy") == nil and hwdec_current ~= "no" and
       hwdec_current ~= "crystalhd" and hwdec_current ~= "rkmpp" then
        hwdec_backup = mp.get_property("hwdec")
        mp.set_property("hwdec", "no")
    end

    -- Insert the cropdetect filter.
    local limit = options.detect_limit
    local round = options.detect_round
    
    if string.find(mp.get_property("vf"), "@autocrop") == nil then
        mp.command(
            string.format(
                '%s vf pre @%s:cropdetect=limit=%s:round=%d:reset=0',
                command_prefix, cropdetect_label, limit, round
            )
        )
    end

    -- Wait to gather data.
    timers.detect_crop = mp.add_timeout(time_needed, detect_end)
end

function detect_end()
    attempt = attempt + 1

    -- Get the metadata and remove the cropdetect filter.
    local cropdetect_metadata = mp.get_property_native(
        "vf-metadata/" .. cropdetect_label)
    
    -- Remove the timer of detect crop.
    if timers.detect_crop then
        timers.detect_crop:kill()
        timers.detect_crop = nil
    end

    restore_hwdec()

    local meta = {}

    -- Verify the existence of metadata.
    if cropdetect_metadata then
        meta = {
            w = cropdetect_metadata["lavfi.cropdetect.w"],
            h = cropdetect_metadata["lavfi.cropdetect.h"],
            x = cropdetect_metadata["lavfi.cropdetect.x"],
            y = cropdetect_metadata["lavfi.cropdetect.y"],
        }
    else
        remove_cropdetect()
        mp.msg.error("No crop data.")
        mp.msg.info("Was the cropdetect filter successfully inserted?")
        mp.msg.info("Does your version of FFmpeg support AVFrame metadata?")
        osd_info("Не удалось получить данные для обрезки")
        attempt = 0
        return
    end

    -- Verify that the metadata meets the requirements and convert it.
    if meta.w and meta.h and meta.x and meta.y then
        local width = mp.get_property_native("width")
        local height = mp.get_property_native("height")

        meta = {
            w = tonumber(meta.w),
            h = tonumber(meta.h),
            x = tonumber(meta.x),
            y = tonumber(meta.y),
            min_w = width * options.detect_min_ratio,
            min_h = height * options.detect_min_ratio,
            max_w = width,
            max_h = height
        }
    elseif attempt <= options.attempts then
        mp.msg.info("Got empty crop data. Trying again (attempt " .. attempt .. "/" .. options.attempts .. ")")
        detect_crop()
        return
    else
        remove_cropdetect()
        mp.msg.error("Got empty crop data.")
        mp.msg.info("You might need to increase detect_seconds.")
        osd_info("Не удалось получить данные для обрезки")
        mp.command("no-osd vf add @fail:eq")
        mp.add_timeout(1, function() mp.command("no-osd vf remove @fail") end)
        attempt = 0
        return
    end
    
    apply_crop(meta)
end

function apply_crop(meta)

    -- Verify if it is necessary to crop.
    local is_effective = meta.w and meta.h and meta.x and meta.y and
                         (meta.x > 0 or meta.y > 0
                         or meta.w < meta.max_w or meta.h < meta.max_h)

    -- Verify it is not over cropped.
    if is_effective and (meta.w < meta.min_w or meta.h < meta.min_h) then
        mp.msg.info("The area to be cropped is too large.")
        mp.msg.info("You might need to decrease detect_min_ratio.")
        
        remove_vf("crop=")
        if attempt <= options.attempts then
            mp.msg.info("Trying again (attempt " .. attempt .. "/" .. options.attempts .. ")")
            detect_crop()
            return
        else
            remove_cropdetect()
            osd_info("Полученная область для обрезки слишком большая (скорее всего, получены неправильные данные для обрезки)")
            mp.command("no-osd vf add @fail:eq")
            mp.add_timeout(1, function() mp.command("no-osd vf remove @fail") end)
            attempt = 0
            return
        end
    end
    remove_cropdetect()
    attempt = 0

    if not is_effective then
        -- Clear any existing crop.
        remove_vf("crop=")
        osd_info("Обрезка полей не требуется")
        mp.msg.info("Cropping is not needed")
        return
    end
    meta.w = meta.w - (addcrop*2 - addcrop*2 % options.detect_round)
    meta.h = meta.h - (addcrop*2 - addcrop*2 % options.detect_round)
    meta.x = meta.x + (addcrop - addcrop % options.detect_round)
    meta.y = meta.y + (addcrop - addcrop % options.detect_round)


    -- Apply crop.
    mp.command(string.format("%s vf add crop=w=%s:h=%s:x=%s:y=%s",
                             command_prefix, meta.w, meta.h, meta.x, meta.y))
    osd_info("Чёрные поля обрезаны")
    mp.msg.info(string.format("Video is cropped (w=%s, h=%s, x=%s, y=%s)", meta.w, meta.h, meta.x, meta.y))
end

function on_start()

    -- Clean up at the beginning.
    cleanup()

    -- If auto is not true, exit.
    if not options.auto then
        return
    end

    -- If it is the beginning, wait for detect_crop
    -- after auto_delay seconds, otherwise immediately.
    local playback_time = mp.get_property_native("playback-time")
    local is_delay_needed = playback_time
        and options.auto_delay > playback_time
        
    local time_needed = 1

    if is_delay_needed then

        -- Verify if there is enough time for autocrop.
        time_needed = options.auto_delay + options.detect_seconds
    end
    if not is_cropable(time_needed) then
        return
    end

    timers.auto_delay = mp.add_timeout(time_needed,
        function()
            detect_crop()

            -- Remove the timer of auto delay.
            timers.auto_delay:kill()
            timers.auto_delay = nil
        end
    )
end

function on_toggle(msg)
    -- If it is during auto_delay, kill the timer.
    if timers.auto_delay then
        timers.auto_delay:kill()
        timers.auto_delay = nil
    end
    
    if msg and string.find(msg, "clear") then
        remove_vf("crop=")
    end
    if msg and string.find(msg, "silent") then
        silent = true
    else
        silent = false
    end
    if msg and string.find(msg, "addcrop=%d+") then
        addcrop = string.sub(msg, string.find(msg, "addcrop=%d+")+8)
    else
        addcrop = 0
    end

    -- Cropped => Remove it.
    if string.find(mp.get_property("vf"), "crop=") ~= nil then
        remove_vf("crop=")
        osd_info("Обрезка видео убрана")
        return
    end

    -- Detecting => Leave it.
    if timers.detect_crop then
        mp.msg.warn("Already cropdetecting!")
        return
    end

    -- Neither => Detect crop.
    detect_crop()
end

function osd_info(text)
    if not options.suppress_osd and not silent then mp.osd_message(text) end
end

function remove_vf(name)
	local vf_list = mp.get_property("vf")
	local start_pos = 0
	while string.find(vf_list, name, start_pos) do
		vf_start = string.find(vf_list, name, start_pos)
		start_pos = vf_start + 3	
		vf_end = string.find(vf_list, ",", vf_start)
		if vf_end == nil then vf_del = string.sub(vf_list ,vf_start)
		else vf_del = string.sub(vf_list ,vf_start, vf_end-1) end
		mp.commandv("vf", "remove", vf_del)
	end
end

mp.add_timeout(0.5, function()
    mp.commandv('script-message', 'autocrop-echo', "installed")
end)

mp.register_script_message("toggle-autocrop", on_toggle)
mp.register_event("end-file", cleanup)
mp.register_event("file-loaded", on_start)
