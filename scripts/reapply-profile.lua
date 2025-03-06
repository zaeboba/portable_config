local filter_active = true

-- Функция применения профиля в зависимости от количества аудиоканалов
local function apply_profile(chan)
    if chan == 1 then
        mp.commandv("apply-profile", "MonoTo5.1")
    elseif chan == 2 then
        mp.commandv("apply-profile", "Stereo")
    elseif chan == 6 then
        mp.commandv("apply-profile", "5.1")
    elseif chan == 8 then
        mp.commandv("apply-profile", "7.1")
    end
end

-- Наблюдатель за изменением количества аудиоканалов
mp.observe_property("audio-params/channel-count", "number", function(name, value)
    if filter_active and value then
        apply_profile(value)
    end
end)

-- При смене файла сбрасываем фильтры
mp.register_event("file-loaded", function()
    mp.set_property("af", "")
end)

-- Функция переключения фильтра по горячей клавише
function toggle_filter()
    filter_active = not filter_active
    if filter_active then
        mp.osd_message("Фильтр включен")
        local chan = mp.get_property_number("audio-params/channel-count", 0)
        if chan then
            apply_profile(chan)
        end
    else
        mp.osd_message("Фильтр выключен")
        mp.set_property("af", "")
    end
end

-- Привязка горячей клавиши Ctrl+F3 к переключению фильтра
mp.add_key_binding("Ctrl+F3", "toggle_filter", toggle_filter)
