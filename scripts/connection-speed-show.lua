-- Показ информации о скорости подключения к видео-серверу при проигрывании видео по сети (скрывается вместе с остальным интерфейсом при отсутствии движений мыши)
-- Отображение в полупрозрачном курсиве - значит кэш заполнен и наполняется на скорости потока видео
-- Настройки
local enabled = true --включено ли отображение по умолчанию (для видео по сети)
local prec = 2 --точность отображения в числе знаков после запятой(точки)
local showzero = false --показывать ли нулевую скорость
local showk = false --показывать ли соотношение скорости к битрейту
local duration = 2 --длительность отображения в секундах (желательно, чтобы значение совпадало со временем до скрытия интерфейса)
local y_adjust = 0 --коррекция высоты отображения при необходимости (положительные значения опускают надписи, и наоборот)
local scale_factor = 1.0 --множитель масштаба надписей





local sleep = false
local osd_timer = nil
local timer_update = mp.add_periodic_timer(1, function() updateNetworkSpeed() end)
local timer_clear = mp.add_timeout(duration, function() timer_update:kill(); ass_osd() end)
timer_update:kill()
timer_clear:kill()
local dur = 0.9
if duration - 0.1 < dur then dur = duration - 0.1 end
local prevspeed = 0
local repcount = 0
local initial = false

function updateNetworkSpeed()
	if enabled then
		cachespeed = mp.get_property_number("cache-speed")
		bitrate = mp.get_property_number("video-bitrate")
        abitrate = mp.get_property_number("audio-bitrate")
        if abitrate then
            if bitrate then bitrate = bitrate + abitrate
            elseif mp.get_property("vid") == "no" then bitrate = abitrate end
        end
        if cachespeed == prevspeed then
            repcount = repcount + 1
        else
            repcount = 0
        end
        prevspeed = cachespeed
        if repcount > 5 then cachespeed = 0 end --если скорость долго не обновляется, значит потеряна связь с сервером (то есть скорость 0)
		if (cachespeed ~= nil) and (cachespeed > 0 or showzero) then
			csfloat = cachespeed / 1000000.0 * 8 -- байт/с -> Мбит/с
			if bitrate ~= nil and showk then 
				k = csfloat / (bitrate / 1000000.0)
				PrintASS(string.format("%." .. prec .. "f Мбит/с", csfloat), string.format("k = %." .. prec .. "f", k))
			else
				PrintASS(string.format("%." .. prec .. "f Мбит/с", csfloat), "")
			end
		end
	end
end

function Toggle()
	enabled = not enabled
	if enabled then
		if showk then
			mp.osd_message("Включено отображение скорости соединения для видео по сети\nk - соотношение скорости к битрейту")
		else
			mp.osd_message("Включено отображение скорости соединения для видео по сети")
		end
	else
		mp.osd_message("Отображение скорости соединения выключено", 2)
		ass_osd()
	end	
end

mp.register_event("file-loaded",  function()
	hidpi = mp.get_property("display-hidpi-scale")
	if hidpi == nil then hidpi = 1 end
    hidpi = hidpi * scale_factor
	local path = mp.get_property_native('path') or ""
    if string.find(path, '://') then
        mp.observe_property("mouse-pos", "native", onMouseMove)
        initial = true
	else
        mp.unobserve_property(onMouseMove)
	end
end)

function onMouseMove(k, v)
    if not enabled then return end
    if initial then
        initial = false
        return
    end
    timer_clear:kill()
    local w, h = mp.get_osd_size()
    if v["hover"] == false then
        timer_update:kill()
        ass_osd()
        sleep = false
        return
	elseif not (v and v["x"] < w*0.12 and v["y"] > h*0.86) then
        timer_clear:resume()
    end
	if sleep == false then
		sleep = true         -- позиция курсора в плеере может обновляться до 125 раз в секунду - ограничиваем частоту расчёта скорости соединения
		timer_update:kill()
		updateNetworkSpeed()
		timer_update:resume()    
		mp.add_timeout(dur, function() sleep = false end)
	end
end

function PrintASS(text1, text2)
	local _, res = mp.get_osd_size()
	local res = 1 - res / 1080
	local msg1 = fsize(50*hidpi) .. text1
	local msg2 = fsize(50*hidpi) .. text2
	local cachefilled = ""
	if mp.get_property_bool("demuxer-cache-idle") then cachefilled = "\\i1\\alpha&H33" end
    local msg = "{\\pos(6,".. 250 - 38*(hidpi-1) - res*20 + y_adjust .. ")"..cachefilled.."}"..msg2 .. "\n" .. "{\\pos(6," .. 257 - 32*(hidpi-1) - res*20 + y_adjust .. ")"..cachefilled.."}" .. msg1
	ass_osd(msg, 1.05)
end
function fsize(s)  -- 100 is the normal font size
  return '{\\fscx' .. s .. '\\fscy' .. s ..'\\bord0.4}'
end

function ass_osd(msg, duration)  -- empty or missing msg -> just clears the OSD
  if not msg or msg == '' then
    msg = '{}'  -- the API ignores empty string, but '{}' works to clean it up
    duration = 0
  end
  mp.set_osd_ass(0, 0, msg)
  if osd_timer then
    osd_timer:kill()
    osd_timer = nil
  end
  if duration > 0 then
    osd_timer = mp.add_timeout(duration, ass_osd)  -- ass_osd() clears without a timer
  end
end

mp.register_script_message("toggle-cs", Toggle)
mp.register_script_message("toggle-connection-speed", Toggle) -- более информативное




