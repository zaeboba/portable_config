function cycle_repeat_mode()
    local loop_file = mp.get_property("loop-file")
    local loop_playlist = mp.get_property("loop-playlist")

    mp.msg.info("Current loop-file: " .. loop_file)
    mp.msg.info("Current loop-playlist: " .. loop_playlist)

    if loop_file == "inf" then
        mp.set_property("loop-file", "no")
        mp.set_property("loop-playlist", "inf")
        mp.osd_message("Повтор плейлиста включен")
        mp.msg.info("Switched to loop-playlist")
    elseif loop_playlist == "inf" then
        mp.set_property("loop-playlist", "no")
        mp.osd_message("Повтор отключен")
        mp.msg.info("Switched to no-repeat")
    else
        mp.set_property("loop-file", "inf")
        mp.osd_message("Повтор файла включен")
        mp.msg.info("Switched to loop-file")
    end
end

mp.register_script_message("cycle-repeat-mode", cycle_repeat_mode)

-- -- scripts/cycle-loop-modes.lua

-- local loop_modes = {"no", "inf", "file"}
-- local current_mode = 1

-- mp.register_script_message("cycle-loop-modes", function()
--     current_mode = current_mode + 1
--     if current_mode > #loop_modes then
--         current_mode = 1
--     end
    
--     local mode = loop_modes[current_mode]
    
--     if mode == "no" then
--         mp.set_property("loop-file", "no")
--         mp.set_property("loop-playlist", "no")
--         mp.osd_message("Повтор выключен")
--     elseif mode == "inf" then
--         mp.set_property("loop-file", "no")
--         mp.set_property("loop-playlist", "inf")
--         mp.osd_message("Повтор плейлиста")
--     elseif mode == "file" then
--         mp.set_property("loop-file", "inf")
--         mp.set_property("loop-playlist", "no")
--         mp.osd_message("Повтор файла")
--     end
-- end)

-- function cycle_repeat_mode()
--     local loop_file = mp.get_property("loop-file")
--     local loop_playlist = mp.get_property("loop-playlist")

--     if loop_file == "inf" then
--         mp.set_property("loop-file", "no")
--         mp.set_property("loop-playlist", "inf")
--         mp.osd_message("Повтор плейлиста включен")
--     elseif loop_playlist == "inf" then
--         mp.set_property("loop-playlist", "no")
--         mp.osd_message("Повтор отключен")
--     else
--         mp.set_property("loop-file", "inf")
--         mp.osd_message("Повтор файла включен")
--     end
-- end

-- mp.register_script_message("cycle-repeat-mode", cycle_repeat_mode)

-- function cycle_repeat_mode()
--     local loop_file = mp.get_property("loop-file")
--     local loop_playlist = mp.get_property("loop-playlist")

--     if loop_file == "inf" then
--         mp.set_property("loop-file", "no")
--         mp.set_property("loop-playlist", "inf")
--         mp.osd_message("Повтор плейлиста включен")
--     elseif loop_playlist == "inf" then
--         mp.set_property("loop-playlist", "no")
--         mp.osd_message("Повтор отключен")
--     else
--         mp.set_property("loop-file", "inf")
--         mp.osd_message("Повтор файла включен")
--     end
-- end

-- mp.register_script_message("cycle-repeat-mode", cycle_repeat_mode)