--поддержка обрезки, затемнения краёв, патч скрипта autocrop для автообрезки полей, возможность менять параметры подсветки в плеере добавлены SearchDownload

local mp_options = require 'mp.options'
local msg = require 'mp.msg'

local opts = {
    blur_radius = 30,
    blur_power = 5,
    vignette_percent = 0,
    minimum_black_bar_size = 3,
    stretch_factor = 1,
    max_area_for_blur = 30,
    overscan = 2,
    mode = "all",
    active = true,
    reapply_delay = 0.3,
    osd_info = true,
    transfer_filters = true
}
mp_options.read_options(opts)

local options = {
  {keys = {'1', '2'}, option = {'Радиус размытия',       '',    1,  0, 150,       opts.blur_radius,      opts.blur_radius} },
  {keys = {'3', '4'}, option = {'Сила размытия',         '',    1,  0,  50,        opts.blur_power,       opts.blur_power} },
  {keys = {'5', '6'}, option = {'Затемнение краёв',     '%',    1,  0, 100,  opts.vignette_percent, opts.vignette_percent} },
  {keys = {'7', '8'}, option = {'Сжатие областей',      'x', 0.02,  1,   5,    opts.stretch_factor,   opts.stretch_factor} },
  {keys = {'9', '0'}, option = {'Отражение краёв кадра', '',    1, -1,   1,                      0,                     0} },

}

local active = opts.active
local applied = false
local vf_crop = "no"
local vf_list = ""
local c = 0
local n = 0
local prev_w = 0
local prev_h = 0
local autocrop_installed = false
local btn_toggle = "??"
local btn_settings = "??"
local max_radius = -1
local current_area_for_blur = -1
local reason = ""
local menu_active = false


function iff(cond, a, b) if cond then return a else return b end end

function ass_osd(msg, duration)
    if not msg or msg == '' then
        msg = '{}'
        duration = 0
    end
    mp.set_osd_ass(0, 0, msg)
    if osd_timer then
        osd_timer:kill()
        osd_timer = nil
    end
    if duration > 0 then
        osd_timer = mp.add_timeout(duration, ass_osd)  -- ass_osd() просто очищает OSD
    end
end

function rgb(c)  -- цвет в RRGGBB
    return '{\\1c&H' .. c:sub(5, 6) .. c:sub(3, 4) .. c:sub(1, 2) .. '&}'
end

function fsize(s)  -- размер шрифта в %
    return '{\\fscx' .. s .. '\\fscy' .. s ..'}'
end

function updateOSD()
    local msg1 = fsize(70) .. 'Подсветка чёрных полей: ' .. iff(not active, rgb('909090') .. 'Откл', iff(applied, rgb('90FF90') .. 'Вкл', rgb('FFFF90') .. 'Ожидание')) 
        .. iff(active and not applied, iff(reason ~= '', ' (' .. reason .. ')', ''), ' [' .. btn_toggle .. ']')
    local msg2 = fsize(70) .. 'Режим настройки: ' .. iff(not menu_active, rgb('909090') .. 'Откл', rgb('90FF90') .. 'Вкл') .. ' [' .. btn_settings .. ']'
    local msg3 = ''

    for i = 1, #options do
        local name = options[i].option[1]:gsub(' ', '\\h') -- \\h - неразрывный пробел
        local postfix = options[i].option[2]
        local value = options[i].option[6]
        local applied_val = options[i].option[7]
        local col1 = iff(not active, rgb('AAAAAA'), rgb('FFFF90'))
        local col2 = iff(not applied or not active or value ~= applied_val, rgb('53E4E4'), rgb('FFA449'))
        local col3 = iff(not menu_active, rgb('909090'), rgb('90FF90'))
        if i == 1 and max_radius >= 0 and value > max_radius then col2 = rgb('FF6060') end
        if i == 5 then
            col1 = iff(options[5].option[6] == 0 and current_area_for_blur ~= -1, iff(current_area_for_blur < opts.max_area_for_blur, rgb('BBFFBB'), rgb('FFBBBB')), col1)
            col2 = iff(options[5].option[6] == 1 and current_area_for_blur >= 100, rgb('FF6060'), col2)
            value = iff(options[5].option[6] == -1, 'Откл', iff(options[5].option[6] == 0, 'Авто', 'Вкл'))
        end
        local info = col1 .. fsize(60) .. name .. '\\h'
            .. col2 .. fsize(100) .. value .. fsize(60) .. postfix
            .. col3 .. '\\h[' .. options[i].keys[1] .. '/' .. options[i].keys[2] .. ']' .. fsize(100)

        msg3 = msg3 .. info .. '   '
    end
    
    local function line(anchor) return '{\\fscx0\\an' .. anchor .. '}|\n' end -- отступ снизу, чтобы интерфейс плеера не перекрывал OSD
    local buttons = ''
    if menu_active then
        buttons = '\n' .. line(3) .. line(3) .. '{\\an3}' .. fsize(70) .. 'Закрыть\\hменю:\\h' .. rgb('90FF90') .. '[Esc]\n{\\an3}' .. fsize(70) .. 'Применить:\\h' .. rgb('90FF90') .. '[Enter]'
    end

    local msg = line(1) .. '{\\an1}' .. msg3 .. '\n{\\an1}' .. msg2 .. '\n{\\an1}' .. msg1 .. buttons
    local duration = iff(menu_active, -1, 2)
    ass_osd(msg, duration)
end

function set_reason(text, silent)
    reason = text
    if menu_active or (opts.osd_info and (not silent or wait_reason)) then updateOSD() end
end

function update_key_binding(enable, key, fn, mode)
    local name = 'blur-' .. key
    if enable then
        mp.add_forced_key_binding(key, name, fn, mode)
    else
        mp.remove_key_binding(name)
    end
end

function getBind(option, delta)
    return function()  -- при нажатии клавиши настройки
        option[6] = option[6] + delta
        if option[6] > option[5] then
            option[6] = option[5]
        end
        if option[6] < option[4] then
            option[6] = option[4]
        end
        updateOSD()
    end
end

function toggle_bindings()
    for i = 1, #options do
        local keys = options[i].keys
        local delta = options[i].option[3]
        update_key_binding(menu_active, keys[1], getBind(options[i].option, -delta), 'repeatable')
        update_key_binding(menu_active, keys[2], getBind(options[i].option,  delta), 'repeatable')
    end
    update_key_binding(menu_active, 'Enter', reapply_blur)
    update_key_binding(menu_active, 'Esc', function() menu_active = false toggle_bindings() ass_osd() end)
end

function toggle_settings()
    menu_active = not menu_active
    toggle_bindings()
    updateOSD()
end


function set_lavfi_complex(filter)
    if not filter and mp.get_property("lavfi-complex") == "" then return end
    local force_window = mp.get_property("force-window")
    local sub = mp.get_property("sub")
    mp.set_property("force-window", "yes")
    if not filter then
        mp.set_property("lavfi-complex", "")
        mp.set_property("vid", "1")
    else
        mp.set_property("vid", "no")
        mp.set_property("lavfi-complex", filter)
    end
    mp.set_property("sub", "no")
    mp.set_property("force-window", force_window)
    mp.set_property("sub", sub)
end

function set_blur(reappl)
    if applied then return end
    
    vf_list = mp.get_property("vf") 
    if string.find(vf_list, "@autocrop") then mp.add_timeout(opts.reapply_delay, set_blur) return end 
    if string.find(vf_list, "@fail") then
        toggle()
        mp.osd_message("Не удалось получить данные для автообрезки")
        return
    end
    
    if not mp.get_property("video-out-params") then mp.add_timeout(opts.reapply_delay, set_blur) return end
    if not mp.get_property_bool("fullscreen") then set_reason("работает только в полноэкранном режиме", reappl) return end

    local ww, wh = mp.get_osd_size()
    local par = mp.get_property_number("video-params/par")
    if par == nil then par = 1 end
    local height = mp.get_property_number("video-params/h")
    local width = mp.get_property_number("video-params/w")
    if not height or not width then mp.add_timeout(opts.reapply_delay, set_blur) return end
    
    local colorlevels = mp.get_property("video-params/colorlevels")
    local colormatrix = mp.get_property("video-params/colormatrix")
    local gamma = mp.get_property("video-params/gamma")
    
    vf_list = vf_list:gsub(",?vapoursynth=[^,]*", ""):gsub(",?lavfi=[^,]*", ""):gsub("^,", "")
    if string.find(vf_list, "crop=") then
        vf_crop = vf_list:match("crop=[^,]*")    
    end
    if vf_crop == "no" or vf_list == "" then
        crop_w = width
        crop_h = height
        crop_x = 0
        crop_y = 0
    else
        crop_w = vf_crop:match("w=[%d%.]*"):sub(3)
        crop_h = vf_crop:match("h=[%d%.]*"):sub(3)
        crop_x = vf_crop:match("x=[%d%.]*"):sub(3)
        crop_y = vf_crop:match("y=[%d%.]*"):sub(3)
    end

    video_aspect = par * crop_w/crop_h
    if math.abs(ww/wh - video_aspect) < 0.05 then set_reason("не требуется для текущего видео", reappl) return end
    if opts.mode == "horizontal" and ww/wh < video_aspect then set_reason("подсветка вертикальных полей отключена", reappl) return end
    if opts.mode == "vertical" and ww/wh > video_aspect then set_reason("подсветка горизонтальных полей отключена", reappl) return end
    
    local split = "[vid1] split=3 [a] [v] [b]"
    local crop_format = "crop=%s:%s:%s:%s"
    local scale_format = "scale=w=%s:h=%s:flags=bilinear"
    local darkening1 = ""
    local darkening2 = ""
    local k = 1

    local stack_direction, cropped_scaled_1, cropped_scaled_2, blur_size
    
    local rnd = 0
    if options[3].option[6] ~= 0 then
        rnd = n % 7 - 3 --небольшой последовательный сдвиг при использовании виньетки, где иногда при абсолютно случайных сочетаниях разрешения она багается
        mp.msg.info("Сдвиг: " .. rnd)
    end

    if ww/wh > video_aspect then --pillarbox
        if vf_crop == "no" then
            crop_w = crop_w - opts.overscan*2
            crop_x = crop_x + opts.overscan
        end
        crop_h = crop_h - crop_h%2 --с нечётной обрезкой не сработает фильтр

        blur_size = math.floor((ww / wh * crop_h / par - crop_w) / 2 + 0.5)

        local height_with_maximized_width = crop_h / crop_w * ww
        current_area_for_blur = math.floor(blur_size * par / crop_w / par * 100)
        if current_area_for_blur >= 100 and options[5].option[6] == 1 then 
            options[5].option[6] = 0 --невозможно включить отражение краёв кадра
        elseif (options[5].option[6] == 1) or (options[5].option[6] == 0 and blur_size * par < math.floor(crop_w * par * opts.max_area_for_blur/100)) then
            height_with_maximized_width = wh * par + 1
        end
        local visible_height = math.floor(crop_h * par * wh / height_with_maximized_width)
        local visible_width = math.floor(blur_size * wh / height_with_maximized_width / options[4].option[6] + rnd)
        
        local k_corr = 1
        if blur_size > crop_h/3 then k_corr = blur_size * 3 / crop_h end
            --уменьшение разрешения области размытия для оптимизации (при сильном блюре не будет заметно, а при слабом даунскейлинга нет)
        if options[1].option[6] > 0 and options[2].option[6] > 0 then k = visible_width / math.min(visible_width, 80 * 5 * k_corr / math.min(options[2].option[6], 5)) end
        local scaled_pre = string.format(scale_format, math.floor(visible_width / k), math.floor(visible_height / k))
        local scaled_vignette = "" --виньетка плохо работает при большой разнице в ширине и высоте кадра, увеличиваем короткую сторону при необходимости (потом пропорции восстановятся)
        if blur_size < crop_h/3 then scaled_vignette = "," .. string.format(scale_format, math.floor(blur_size / k * math.min(crop_h / blur_size/3, 5)), math.floor(crop_h / k)) end
        scaled_final = string.format("scale=w=%s:h=%s", blur_size, crop_h)
        
        local cropped_1 = string.format(crop_format, visible_width, visible_height, crop_x, math.floor((crop_h - visible_height)/2 + crop_y))
        if options[3].option[6] ~= 0 then darkening1 = scaled_vignette .. ",vignette=angle=PI*" .. 0.5*(options[3].option[6]/100) .. ":x0=w/1.1:y0=h/2:aspect=1/20" end
        cropped_scaled_1 = cropped_1 .. "," .. scaled_pre

        local cropped_2 = string.format(crop_format, visible_width, visible_height, -visible_width+crop_w+crop_x, math.floor((crop_h - visible_height)/2 + crop_y))
        if options[3].option[6] ~= 0 then darkening2 = scaled_vignette .. ",vignette=angle=PI*" .. 0.5*(options[3].option[6]/100) .. ":x0=0.1*w:y0=h/2:aspect=1/20" end
        cropped_scaled_2 = cropped_2 .. "," .. scaled_pre
        stack_direction = "h"
        
        corr = visible_height/k / 1080 --постоянный относительный уровень размытия для разных разрешений
        mindim = visible_width/k
        crop_apply = ""
        if opts.transfer_filters then
            if vf_list ~= "" then
                crop_apply = vf_list
                if vf_crop == "no" then crop_apply = crop_apply .. "," end
            end
            if vf_crop == "no" then crop_apply = crop_apply .. crop_format:format(crop_w, crop_h, crop_x, crop_y) end
            mp.msg.info("Применённые фильтры: " .. crop_apply)
        else
            crop_apply = crop_apply .. crop_format:format(crop_w, crop_h, crop_x, crop_y)
        end
    else --letterbox
        if vf_crop == "no" then
            crop_h = crop_h - opts.overscan*2
            crop_y = crop_y + opts.overscan
        end
        crop_w = crop_w - crop_w%2

        blur_size = math.floor((wh / ww * crop_w * par - crop_h) / 2 + 0.5)
        blur_size = blur_size - blur_size%2 --с нечётной обрезкой по вертикали может вылететь плеер

        local width_with_maximized_height = crop_w / crop_h * wh
        current_area_for_blur = math.floor(blur_size * par / crop_h / par * 100)
        if current_area_for_blur >= 100 and options[5].option[6] == 1 then
            options[5].option[6] = 0
        elseif (options[5].option[6] == 1) or (options[5].option[6] == 0 and blur_size * par < math.floor(crop_h * par * opts.max_area_for_blur/100)) then
            width_with_maximized_height = ww * par + 1
        end
        local visible_width = math.floor(crop_w * ww / width_with_maximized_height)
        local visible_height = math.floor(blur_size * ww / width_with_maximized_height / options[4].option[6] + rnd)
        
        if options[1].option[6] > 0 and options[2].option[6] > 0 then k = visible_height / math.min(visible_height, 60 * 5 / math.min(options[2].option[6], 5)) end
        local scaled_pre = string.format(scale_format, math.floor(visible_width / k), math.floor(visible_height / k))
        local scaled_vignette = "," .. string.format(scale_format, math.floor(crop_w / k), math.floor(blur_size / k * math.min(crop_w / blur_size/3, 5)))
        scaled_final = string.format("scale=w=%s:h=%s", crop_w, blur_size)

        local cropped_1 = string.format(crop_format, visible_width, visible_height, math.floor((crop_w - visible_width)/2) + crop_x, crop_y)
        if options[3].option[6] ~= 0 then darkening1 = scaled_vignette .. ",vignette=angle=PI*" .. 0.5*(options[3].option[6]/100) .. ":x0=w/2:y0=h*1.1:aspect=20" end
        cropped_scaled_1 = cropped_1 .. "," .. scaled_pre

        local cropped_2 = string.format(crop_format, visible_width, visible_height, math.floor((crop_w - visible_width)/2) + crop_x, -visible_height + crop_h + crop_y)
        if options[3].option[6] ~= 0 then darkening2 = scaled_vignette .. ",vignette=angle=PI*" .. 0.5*(options[3].option[6]/100) .. ":x0=w/2:y0=-0.1*h:aspect=20" end
        cropped_scaled_2 = cropped_2 .. "," .. scaled_pre
        stack_direction = "v"
        
        corr = visible_width/k / 1920 * 9 / 16 * (ww / wh)
        mindim = visible_height/k
        crop_apply = ""
        if opts.transfer_filters then
            if vf_list ~= "" then
                crop_apply = vf_list
                if vf_crop == "no" then crop_apply = crop_apply .. "," end
            end
            if vf_crop == "no" then crop_apply = crop_apply .. crop_format:format(crop_w, crop_h, crop_x, crop_y) end
            mp.msg.info("Применённые фильтры: " .. crop_apply)
        else
            crop_apply = crop_apply .. crop_format:format(crop_w, crop_h, crop_x, crop_y)
        end
    end

    if blur_size < math.max(1, opts.minimum_black_bar_size) then set_reason("не требуется согласно настройкам", reappl) return end
    
    applied = true
    mp.commandv("vf", "clr", "")
    
    local lr = math.min(math.floor(options[1].option[6] * corr + 0.5), math.floor(mindim/2 + 0.5) - 1)
    local cr = math.min(math.floor(options[1].option[6] * corr + 0.5), math.floor(mindim/4 + 0.5) - 1)
    local blur = string.format("boxblur=lr=%i:lp=%i:cr=%i:cp=%i", lr, options[2].option[6], cr, options[2].option[6])

    zone_1 = string.format("[a] %s,%s%s,%s [a_fin]", cropped_scaled_1, blur, darkening1, scaled_final)
    zone_2 = string.format("[b] %s,%s%s,%s [b_fin]", cropped_scaled_2, blur, darkening2, scaled_final)

    local par_fix = "setsar=ratio=" .. tostring(par) .. ":max=10000"
    
    stack = string.format("[a_fin] [v_fin] [b_fin] %sstack=3,%s [vo]", stack_direction, par_fix)
    filter = string.format("%s;%s;[v] %s [v_fin]; %s;%s", split, zone_1, crop_apply, zone_2, stack)
    
    max_radius = math.floor(mindim/2/corr + 0.5) - 1
    if math.floor(options[1].option[6] + 0.5) > max_radius then
        options[1].option[6] = max_radius
    end
    for i = 1, #options do
        options[i].option[7] = options[i].option[6]
    end
    if opts.osd_info or menu_active then updateOSD() end
    
    local orig_value_hwdec = mp.get_property("hwdec")
    mp.set_property("hwdec", "no") --во время активации lavfi-complex должен быть выключено HW-декодирование
    set_lavfi_complex(filter)
    mp.set_property("hwdec", orig_value_hwdec) --плеер не включит HW во время работы подсветки, а после конца работы включит автоматически
    
    if colorlevels and colormatrix and gamma then   --для работы преобразования HDR в SDR при вкл подсветке (но цвета всё равно могут немного исказиться), на производительность не влияет 
        mp.command("no-osd vf add format=colorlevels=" .. colorlevels .. ":colormatrix=" .. colormatrix .. ":gamma=" .. gamma)
    end
end

function unset_blur()
    set_lavfi_complex()
    if applied == false then return end
    applied = false
    mp.commandv("vf", "clr", "")
    if opts.transfer_filters then
        if vf_list ~= "" then 
            mp.commandv("vf", "add", vf_list) 
        end
    else
        if vf_crop ~= "no" then
            mp.commandv("vf", "add", vf_crop)
        end
    end
    vf_crop = "no"
    vf_list = ""
    max_radius = -1
    current_area_for_blur = -1
    reason = ""
    wait_reason = mp.add_timeout(1, function() wait_reason = nil end)
end

local reapplication_timer = mp.add_timeout(opts.reapply_delay, function() set_blur(true) end)
reapplication_timer:kill()
local warning = "Не установлен пропатченный скрипт autocrop.lua (идёт вместе со сборкой) для автообрезки чёрных полей"
mp.register_script_message('autocrop-echo', function(echo)
    if echo == "installed" then autocrop_installed = true end
end)
mp.add_timeout(3, function() if not autocrop_installed then mp.msg.warn(warning) end end)

function reset_blur()
    c = c+1
    if c <= 1 then return end
    unset_blur()
    reapplication_timer:kill()
    reapplication_timer:resume()
end

function reapply_blur()
    if applied then
        reset_blur()
        n = n + 1
    elseif not active then
        toggle()
    end
end

function toggle()
    if active then
        active = false
        unset_blur()
        if opts.osd_info or menu_active then
            updateOSD()
        else
            mp.command("show-text '${osd-ass-cc/0}{\\alpha&H66}Откл' 700")
        end
        mp.unobserve_property(reset_blur)
    else
        active = true
        if not opts.osd_info and not menu_active then
            mp.command("show-text '${osd-ass-cc/0}{\\alpha&H66}Вкл' 700")
        end
        n = n + 1
        set_blur()
        c = 0
        mp.observe_property("fullscreen", "native", reset_blur)
    end
end
function set_autocrop()
    if not mp.get_property("video-params") then return end
    if not autocrop_installed then
        mp.osd_message(warning)
        return
    end
    if active then
        unset_blur()
    end
    active = true
    set_reason("поиск чёрных полей...")
    if not opts.osd_info and not menu_active then
        mp.command("show-text '${osd-ass-cc/0}{\\alpha&H66}Вкл' 700")
    end
    mp.command("script-message-to autocrop toggle-autocrop clear+silent+addcrop=" .. opts.overscan)
    n = n + 1
    mp.add_timeout(0.6, set_blur)
    c = 0
    mp.observe_property("fullscreen", "native", reset_blur)
end

if active then
    n = n + 1
    set_blur(true)
    c = 0
    mp.observe_property("fullscreen", "native", reset_blur)
end

mp.register_script_message("toggle-blur", toggle)
mp.register_script_message("autocrop-blur", set_autocrop)
mp.register_script_message("toggle-blur-settings", toggle_settings)
mp.register_script_message("reapply-blur", reapply_blur)


local isvid = false
mp.add_hook('on_preloaded', 100, function() --иначе может случиться ситуация, что видео загрузилось, а неподходящий фильтр не успеет отключиться
    local allcount = mp.get_property_native("track-list/count")
    isvid = false
    for i = 0, allcount do
        if mp.get_property_native("track-list/" .. i .. "/type") == "video" then
            isvid = true
            prev_w = new_w  --если у соседних видео одинаковое разрешение (иначе фильтр пересчитывать обязательно), оставляем фильтр для бесшовного переключения между видео
            prev_h = new_h
            new_w = mp.get_property_number("track-list/" .. i .. "/demux-w")
            new_h = mp.get_property_number("track-list/" .. i .. "/demux-h")
            break
        end
    end
    if isvid then
        if applied and new_w == prev_w and new_h == prev_h then
            orig_value_hwdec = mp.get_property("hwdec")
            mp.set_property("hwdec", "no")
            msg.info("Фильтр подсветки сохранён")
        elseif active then
            vf_crop = "no"
            vf_list = ""
            reset_blur()
        end
    elseif applied then
        unset_blur()
    end
end)
mp.register_event("file-loaded", function()
    if isvid and mp.get_property_native("vid") == false and applied == false then --исправление запоминания плеером выбора пустой видеодорожки
        mp.set_property("vid", 1)
        msg.info('Загрузка видео-дорожки')
    end
    if orig_value_hwdec then
        mp.set_property("hwdec", orig_value_hwdec)
        orig_value_hwdec = nil
    end
end)


local bindings = mp.get_property_native("input-bindings") 
for k,v in pairs(bindings) do  --ищем, на какие клавиши назначены команды скрипта в input.conf для отображения в инфо-панели
    if btn_toggle == "??" and v["cmd"]:find(" toggle%-blur") then
        btn_toggle = v["key"]
    end
    if btn_settings == "??" and v["cmd"]:find(" toggle%-blur%-settings") then
        btn_settings = v["key"]
    end
end