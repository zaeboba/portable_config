--Скрипт с авто-деинтерлейсингом + авто-деблокинг для старых кодеков + Autoplay при открытии видео + отключение перемотки по ключевым кадрам только для внешнего аудио
-- Настройки
flash_timeline_on_pause = true -- отображение на короткое время шкалы времени uosc и названия видео при нажатии на паузу (при снятии с паузы показываться не будут)
autodeint = true -- авто-деинтерлейсинг
autodeblock = true -- авто-деблокинг для старых кодеков (MPEG-1, MPEG-2, Xvid, DivX)
autoplay = true -- автоплей при открытии видео (иначе плеер не снимется с паузы при выборе другого видео, как во всех других плеерах)
reset_crop = true -- сброс фильтров обрезки и де-лого, если у соседних видео разное разрешение (то есть, уже не подходящие из-за других размеров видео)
auto_change_seekstyle = true -- отключение перемотки по ключевым кадрам только во время просмотра с внешней аудиодорожкой, при необходимости (работает при --hr-seek=default)
                             -- (необходимо из-за бага плеера: рассинхрон внешнего аудио при перемотке https://github.com/mpv-player/mpv/issues/1824)
fix_no_choosed_audio = true -- исправление неприятной особенности плеера: если в предыдущем видео была вручную выбрана аудиодорожка с номером, которого нет в текущем видео,
                            -- а для текущего видео нет запомненной дорожки, то не будет выбрана ни одна аудиодорожка
console_info = true -- вывод информации об изменении параметров скриптом в консоль плеера





local old_w = 0
local old_h = 0
local seekstyle = mp.get_property("hr-seek")

function info(text)
    if console_info then mp.msg.info(text) end
end

-- AUTOPLAY
if autoplay then mp.register_event("start-file", function()
    mp.set_property_bool("pause", false)
end) end

mp.register_event("file-loaded", function()
    if autodeint then
        mp.unobserve_property(deint)
        mp.observe_property("video-frame-info/interlaced", "bool", deint)
    end
	
	if reset_crop then
        h = mp.get_property_number("video-params/h")
        w = mp.get_property_number("video-params/w")
        if w ~= old_w or h ~= old_h then remove_vf("crop="); remove_vf("delogo=") end
        old_w = w
        old_h = h
    end
	
	-- авто-деблокинг для старых кодеков: mpeg4 (MPEG-4 part 2) - Xvid или DivX, mpeg2video (MPEG-2 video) - MPEG-2, mpeg1video (MPEG-1 video) - MPEG-1
	if autodeblock then autodeblocking() end
    
    if fix_no_choosed_audio and mp.get_property("aid") == "no" then
        allcount = mp.get_property_native("track-list/count")
        for i = 0, allcount do
            if mp.get_property_native("track-list/" .. i .. "/type") == "audio" then
                mp.set_property("aid", "1")
                info("Исправление автовыбора пустой аудиодорожки")
                break
            end
        end
    end
	
	-- отключение деинтерлейсинга, когда он не нужен
	local deinterlace = mp.get_property_native("deinterlace")
	if autodeint and deinterlace == true then
		mp.set_property_native("deinterlace", "no")
	end

end)


function deint(name, value)
    if value then
		local deinterlace = mp.get_property_native("deinterlace")
		if deinterlace == false then
			mp.set_property_native("deinterlace", "yes")
			info("Чересстрочная развёртка - включён деинтерлейсинг")
		end
    end
end

function manualdeint()
	mp.unobserve_property(deint)
end

function autodeblocking()
	remove_vf("deblock")
	local codec = mp.get_property("video-codec")
    if codec and (string.match(codec, "MPEG.4 part 2") or string.match(codec, "MPEG.2 video") or string.match(codec, "MPEG.1 video")) then
        mp.commandv("vf", "pre", "deblock") -- деблок для правильной работы должен идти перед остальными фильтрами (обязательно до обрезки)
		info("Старый кодек - включён deblocking")
    end
end

function remove_vf(name)
	local vf_list = mp.get_property("vf")
    for filter in vf_list:gmatch(name .. "[^,]*") do
        mp.commandv("vf", "remove", filter)
    end
end

function flashpause(name, value)
	if value == true then mp.command("script-message-to uosc flash-elements timeline,top_bar") end
end

function changeseekstyle(name, value)
    if value == true and mp.get_property("hr-seek") ~= "yes" then
        mp.set_property("hr-seek", "yes")
        info("Внешняя аудиодорожка - включена точная перемотка")
    elseif value == false and mp.get_property("hr-seek") ~= seekstyle then
        mp.set_property("hr-seek", seekstyle)
        info("Встроенная аудиодорожка - перемотка по ключевым кадрам")
    end
end

if flash_timeline_on_pause then mp.observe_property("pause", "bool", flashpause) end

if auto_change_seekstyle and seekstyle ~= "yes" and seekstyle ~= "always" then
    mp.observe_property("current-tracks/audio/external", "bool", changeseekstyle)
end

function toggle_fs(bottom_area)
    local wh = mp.get_property_number("osd-height")
    if not wh then return end
    if bottom_area == nil then bottom_area = 80 end
    local hidpi = mp.get_property("display-hidpi-scale")
	if hidpi == nil then hidpi = 1 end
    bottom_area = bottom_area * hidpi
    if mp.get_property_bool("fullscreen") or mp.get_property_bool("window-maximized") then bottom_area = bottom_area * 1.3 end
    if mp.get_property_native("mouse-pos")["y"] < wh - bottom_area then
        mp.command("cycle fullscreen")
    end
end


mp.register_script_message("autodeblock", autodeblocking) --автодеблок в любой момент по требованию
mp.register_script_message("manualdeint", manualdeint)
mp.register_script_message("safe-toggle-fullscreen", toggle_fs) -- отключение перехода в полноэкранный режим при двойных кликах в нижней части экрана с элементами управления плеером uosc
                                                                -- на вход число пикселей от низа окна плеера, при кликах в области которых не переходить в полноэкранный режим