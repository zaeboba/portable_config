mp.observe_property("audio-params/channel-count", "number", function(name, value)
    if value then
        if value == 1 then
            mp.commandv("apply-profile", "MonoTo5.1")
        elseif value == 2 then
            mp.commandv("apply-profile", "Stereo")
        elseif value == 6 then
            mp.commandv("apply-profile", "5.1")
        elseif value == 8 then
            mp.commandv("apply-profile", "7.1")
        end
    end
end)

-- Сбрасываем фильтры при смене файла
mp.register_event("file-loaded", function()
    mp.set_property("af", "")
end)