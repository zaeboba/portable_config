--Режим "Картинка в картинке"
--Настройки
pref_width = 480 --размеры уменьшенного окна плеера
pref_heigh = 270  --если соотношение сторон будет не совпадать, размер автоматически подберётся так, чтобы площадь окна плеера была такой же, как при заданных размерах
correct_downscaling = true --качественный даунскейлинг при включённом режиме (потребляет мало ресурсов при небольших размерах окна)
wheelrewind = false --в режиме "Картинка в картинке" включить перемотку видео колёсиком мыши на всей области окна (как при дефолтных настройках управления плеером)
                   --рекомендую также для удобства включить прокручивание неактивных окон в настройках windows
                   --на win10: "Настройки > Устройства > Мышь и сенсорная панель" > тумблер "Прокручивать неактивные окна при наведении на них"
rewsecs = 5 --интервал перемотки (отрицательные значения инвертируют направление перемотки)
hide_minitimeline = true --отключение минимизированной шкалы времени uosc на время использования режима
auto_exit_if_fullscreen = true  --выходить из режима "Картинка в картинке" при попытке перейти в полноэкранный режим
window_pos = "-0-0"  --угол экрана, в который будет смещён плеер (только на mpv версии 0.38+!)
                     -- "+0-0" - левый-нижний "-0-0" - правый-нижний, вместо нулей - расстояние в пикселях от краёв экрана по горизонтали и вертикали





local is_pip_mode = false
local prev_corr = false
local prev_lin = false
local orig_w = 1280
local orig_h = 800
local new_version = false

--проверка версии плеера: на старых версиях geometry сам по себе не изменяет размер плеера, а 2 изменения размера окна одновременно будут конфликтовать друг с другом
if mp.get_property("input-commands") == nil then
    mp.msg.verbose("mpv v0.37-")
else
    new_version = true
    mp.msg.verbose("mpv v0.38+")
end


function set_pip_mode()
    if mp.get_property_bool("fullscreen") then
        mp.set_property_bool("fullscreen", false)
        mp.add_timeout(0.2, set_pip_mode)
        return
    end
    
    test_w, test_h = mp.get_osd_size()
    if test_w > pref_width*1.5 and test_h > pref_heigh*1.5 then orig_w = test_w; orig_h = test_h end
    local w, h = get_video_size()
    if w == nil then
        mp.osd_message("Видео не загружено - нельзя автоматически изменить размер окна")
    else
        local ww = pref_width
        local wh = pref_heigh
        local diff = (w/h) / (ww/wh)
        if diff > 1 then
            diff = 1 / diff
            ww = ww / diff
        else
            wh = wh / diff
        end
        ww = math.floor(ww * math.sqrt(diff) + 0.5)
        wh = math.floor(wh * math.sqrt(diff) + 0.5)
        mp.set_property("geometry", string.format("%dx%d%s", ww, wh, window_pos))
        
        if not new_version then mp.set_property('window-scale', wh / h) end
    end
    mp.register_event("video-reconfig", savesize)
	
    mp.set_property_native("ontop", true)
    mp.set_property('border', 'no')
	
    if correct_downscaling then
        prev_corr = mp.get_property_bool("correct-downscaling")
        prev_lin = mp.get_property_bool("linear-downscaling")
        mp.set_property_bool("correct-downscaling", true)
        mp.set_property_bool("linear-downscaling", true)
    end
	
	if wheelrewind then
		mp.add_forced_key_binding("WHEEL_UP", "wu", function() if mp.get_property_native("mouse-pos")["hover"] then mp.commandv("seek", rewsecs) end end)
		mp.add_forced_key_binding("WHEEL_DOWN", "wd", function() if mp.get_property_native("mouse-pos")["hover"] then mp.commandv("seek", -rewsecs) end end)
	end
    mp.observe_property("fullscreen", "bool", fs_changed)
    
    mp.unregister_script_message("toggle-pip-mode")
    mp.add_timeout(0.2, function() --таймаут, чтобы успели обновиться данные об окне (запрещаем менять положение окна плеера слишком часто во избежание проблем)
        mp.register_script_message("toggle-pip-mode", toggle_pip_mode)
    end)
  
    is_pip_mode = true
end

function restore_original_mode(uosc)
	if mp.get_property_bool("fullscreen") then
        mp.set_property_bool("fullscreen", false)
        return
    end
    mp.unregister_event(savesize)
    
    local w, h = get_video_size()
    if w == nil then
        mp.osd_message("Видео не загружено - нельзя автоматически изменить размер окна")
    else
        mp.set_property("geometry", "")
        if not new_version then
            widthscale = orig_w / w
            heightscale = orig_h / h
            local scale = (widthscale < heightscale and widthscale or heightscale)
            mp.set_property('window-scale', scale)
        end
    end
	
    mp.set_property_native("ontop", false)
    mp.set_property('border', 'no')
	
    if correct_downscaling then
        mp.set_property_bool("correct-downscaling", prev_corr)
        mp.set_property_bool("linear-downscaling", prev_lin)
    end
	
    if wheelrewind then
		mp.remove_key_binding("wu")
		mp.remove_key_binding("wd")
	end
    mp.unobserve_property(fs_changed)
    
    mp.unregister_script_message("toggle-pip-mode")
    mp.add_timeout(0.2, function()
        if hide_minitimeline and mp.get_property_bool("fullscreen") == false and uosc then mp.command("script-binding uosc/toggle-progress") end
        mp.register_script_message("toggle-pip-mode", toggle_pip_mode)
    end)
    
    is_pip_mode = false
end

function toggle_pip_mode()
    if is_pip_mode or (mp.get_property_bool("ontop") and not mp.get_property_bool("border")) then
        restore_original_mode(true)
    else
        set_pip_mode()
    end
end

mp.register_event("file-loaded", function()
	if is_pip_mode == false and (mp.get_property_bool("ontop") and not mp.get_property_bool("border")) then
		restore_original_mode()
	end
end)

function savesize()
    local ww, wh = mp.get_osd_size()
    if not ww or ww <= 0 or not wh or wh <= 0 or not is_pip_mode then return end
    if ww > pref_width and wh > pref_heigh then return end
    local w, h = get_video_size()
    if not w then return end
    local diff = (w/h)/(ww/wh)
    if math.abs(diff - 1) < 0.01 and mp.get_property("geometry") ~= "" then return end
    if diff > 1 then -- постоянная площадь окна плеера при переключениях видео
        diff = 1 / diff
        ww = ww / diff
    else
        wh = wh / diff
    end
    ww = math.floor(ww * math.sqrt(diff) + 0.5)
    wh = math.floor(wh * math.sqrt(diff) + 0.5)
    mp.set_property("geometry", string.format("%dx%d%s", ww, wh, window_pos))
end

function get_video_size()       -- фактически отображаемый в плеере размер видео с учётом анаморфа и обрезки
    local w = mp.get_property("video-out-params/w")
    if not w then return end
    local h = mp.get_property("video-out-params/h")
    local par = mp.get_property("video-out-params/par")
    if par == nil then par = 1 end
    local vf = mp.get_property("vf")
    if string.find(vf, "crop=") then
        vf_crop1 = string.find(vf, "crop=")
		vf_crop2 = string.find(vf, ",", vf_crop1)
		if vf_crop2 == nil then vf_crop = string.sub(vf, vf_crop1)
		else vf_crop = string.sub(vf, vf_crop1, vf_crop2-1) end
        vf_crop = vf_crop .. ":"
        w = tonumber(string.sub(vf_crop, string.find(vf_crop, "w=")+2, string.find(vf_crop, ":", string.find(vf_crop, "w="))-1))
        h = tonumber(string.sub(vf_crop, string.find(vf_crop, "h=")+2, string.find(vf_crop, ":", string.find(vf_crop, "h="))-1))
    end
    w = w * par
    return w, h
end

function fs_changed(k, fullscreen)
    if fullscreen and auto_exit_if_fullscreen then
        mp.unobserve_property(fs_changed)
        mp.set_property_bool("fullscreen", false)
        mp.add_timeout(0.1, restore_original_mode)
    elseif fullscreen == false and hide_minitimeline then
        mp.add_timeout(0.2, function() mp.command("script-binding uosc/toggle-progress") end)
    end
end

mp.register_script_message("toggle-pip-mode", toggle_pip_mode)


