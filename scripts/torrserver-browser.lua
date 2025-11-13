--[[
MPV TorrServer Browser

Скрипт для просмотра и воспроизведения торрентов с TorrServer прямо в MPV.

Created by: zaeboba
License: 🖕
Version: 13.11.2025
--]]

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'
local opt = require 'mp.options'

-- --- НАСТРОЙКИ ---
local opts = {
    torrserver_url = "http://10.10.1.28:8090",
    open_key = "M"
}
opt.read_options(opts, mp.get_script_name())

-- --- КОНСТАНТЫ ---
local OSD_VIEWPORT_SIZE = 15

-- --- СОСТОЯНИЕ СКРИПТА ---
local state = {
    is_visible = false,
    current_items = {},
    selected_index = 1,
    scroll_offset = 0,
    osd_overlay = nil,
    current_view_type = "torrents",
    current_torrent_hash = nil,
    history = {}
}

-- --- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ---

-- Функция для парсинга M3U контента
local function parse_m3u(m3u_content)
    local items = {}
    if not m3u_content then return items end

    local lines = {}
    for line in m3u_content:gmatch("([^\n\r]+)") do
        table.insert(lines, line)
    end

    local i = 1
    while i <= #lines do
        local line = lines[i]
        if line:match("^#EXTINF") then
            local name = line:match(".-,(.+)")

            -- Ищем следующую строку, которая является URL-адресом, пропуская другие теги
            local j = i + 1
            while j <= #lines and not lines[j]:match("^http") do
                j = j + 1
            end

            if j <= #lines then
                local url_line = lines[j]
                local item = { name = name, stream_link = url_line }
                local hash = url_line:match("link=([a-fA-F0-9]+)")
                if hash then
                    item.hash = hash
                end
                table.insert(items, item)
                i = j -- Продолжаем поиск со строки после URL
            end
        end
        i = i + 1
    end
    return items
end

-- --- ОСНОВНЫЕ ФУНКЦИИ ---

-- Функция для отображения интерфейса
local function render_osd()
    if not state.is_visible then
        if state.osd_overlay then
            state.osd_overlay:remove()
            state.osd_overlay = nil
        end
        return
    end

    if not state.osd_overlay then
        state.osd_overlay = mp.create_osd_overlay("ass-events")
    end

    local ass = "{\\an7}{\\fs24}"
    ass = ass .. "{\\b1}Браузер TorrServer{\\b0}\\N\\N"

    if state.current_view_type == "files" and #state.history > 0 then
        ass = ass .. "{\\i1}Торрент: " .. (state.history[#state.history].name or "Неизвестно") .. "{\\i0}\\N"
    end
    ass = ass .. "\\N"

    if #state.current_items == 0 then
        ass = ass .. "Загрузка или нет данных...\\N"
    else
        ass = ass .. "{\\fs20}(" .. state.selected_index .. " / " .. #state.current_items .. ")\\N\\N"

        if state.scroll_offset > 0 then
            ass = ass .. "  ↑...\\N"
        end

        local start_index = state.scroll_offset + 1
        local end_index = math.min(#state.current_items, state.scroll_offset + OSD_VIEWPORT_SIZE)

        for i = start_index, end_index do
            local item = state.current_items[i]
            local line = ""
            if i == state.selected_index then
                line = "{\\c&H00FFFF&}▶ "
            else
                line = "  "
            end
            line = line .. (item.name or "Без имени") .. "{\\c&HFFFFFF&}\\N"
            ass = ass .. line
        end

        if state.scroll_offset + OSD_VIEWPORT_SIZE < #state.current_items then
            ass = ass .. "  ↓...\\N"
        end
    end

    state.osd_overlay.data = ass
    state.osd_overlay:update()
end

-- Функция для загрузки элементов
local function load_items(view_type, data)
    state.current_view_type = view_type
    state.current_items = {}
    state.selected_index = 1
    state.scroll_offset = 0

    local url = ""
    if view_type == "torrents" then
        url = opts.torrserver_url .. "/playlistall/all.m3u"
        state.current_torrent_hash = nil
    elseif view_type == "files" and data then
        url = data -- Используем переданный URL напрямую
        local hash = data:match("link=([a-fA-F0-9]+)")
        state.current_torrent_hash = hash
    else
        msg.error("Неверный вызов load_items.")
        render_osd()
        return
    end

    render_osd()

    -- Возвращаем асинхронную версию, так как синхронная не решила проблему, но вызывала зависание
    local args = { "curl", "-s", "-L", url }
    msg.debug("TorrServer Browser: Executing curl command: " .. table.concat(args, " "))

    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        args = args,
        capture_stdout = true,
        capture_stderr = true
    }, function(success, result, error)
        if not success then
            msg.error("TorrServer Browser: Failed to execute curl command: " .. (error or "unknown"))
            state.current_items = { { name = "Ошибка выполнения команды" } }
            render_osd()
            return
        end

        if result.stderr and result.stderr ~= "" then
            msg.error("TorrServer Browser: Curl stderr: " .. result.stderr)
        end
        if result.stdout and result.stdout ~= "" then
            local lines = {}
            for line in result.stdout:gmatch("([^\n\r]+)") do
                table.insert(lines, line)
            end

            local max_log_lines = 30
            if #lines > max_log_lines then
                local truncated_lines = {}
                for i = 1, max_log_lines do
                    table.insert(truncated_lines, lines[i])
                end
                local partial_log = table.concat(truncated_lines, "\n")
                msg.debug("TorrServer Browser: Curl stdout (first " .. max_log_lines .. "/" .. #lines .. " lines):\n" .. partial_log .. "\n...")
            else
                msg.debug("TorrServer Browser: Curl stdout (" .. #lines .. " lines):\n" .. result.stdout)
            end
        end

        local m3u_content = result.stdout or ""
        local parsed_items = parse_m3u(m3u_content)

        if #parsed_items == 0 then
            msg.warn("Не удалось получить элементы или M3U пуст.")
            state.current_items = { { name = "Нет элементов или ошибка парсинга M3U" } }
            render_osd()
            return
        end

        state.current_items = parsed_items
        table.sort(state.current_items, function(a, b) return (a.name or "") < (b.name or "") end)
        render_osd()
    end)
end

-- Функция для обработки нажатий клавиш

local function handle_key_press(key)

    if #state.current_items == 0 then return end



    if key == "UP" then

        state.selected_index = state.selected_index - 1

        if state.selected_index < 1 then state.selected_index = #state.current_items end

    elseif key == "DOWN" then

        state.selected_index = state.selected_index + 1

        if state.selected_index > #state.current_items then state.selected_index = 1 end

    elseif key == "RIGHT" or key == "ENTER" then

        local selected_item = state.current_items[state.selected_index]

        if not selected_item then return end



        if state.current_view_type == "torrents" then

            if selected_item.stream_link then

                table.insert(state.history, {

                    view_type = state.current_view_type,

                    selected_index = state.selected_index,

                    name = selected_item.name,

                    items = state.current_items -- Сохраняем весь список

                })

                load_items("files", selected_item.stream_link)

            else

                msg.warn("Не удалось получить ссылку для торрента: " .. selected_item.name)

            end

        elseif state.current_view_type == "files" then

            if selected_item.stream_link then

                state.is_loading_playlist = true -- Устанавливаем флаг перед загрузкой



                -- Запускаем выбранный файл, заменяя текущий

                mp.commandv("loadfile", selected_item.stream_link, "replace")



                -- Добавляем остальные файлы в плейлист

                for i = state.selected_index + 1, #state.current_items do

                    local item_to_add = state.current_items[i]

                    if item_to_add and item_to_add.stream_link then

                        mp.commandv("loadfile", item_to_add.stream_link, "append")

                    end

                end

                -- OSD теперь закроется по событию file-loaded

            else

                msg.warn("Нет ссылки на поток для файла: " .. selected_item.name)

            end

        end

    elseif key == "LEFT" or key == "BS" then

        if #state.history > 0 then

            local prev_state = table.remove(state.history)

            state.current_view_type = prev_state.view_type

            state.current_items = prev_state.items

            state.selected_index = prev_state.selected_index

            state.scroll_offset = math.max(0, prev_state.selected_index - math.floor(OSD_VIEWPORT_SIZE / 2))

            if #state.history > 0 then

                state.current_torrent_hash = state.history[#state.history].hash

            else

                state.current_torrent_hash = nil

            end

        else

            toggle_browser()

        end

    end



    -- Логика прокрутки

    if state.selected_index < state.scroll_offset + 1 then

        state.scroll_offset = state.selected_index - 1

    elseif state.selected_index > state.scroll_offset + OSD_VIEWPORT_SIZE then

        state.scroll_offset = state.selected_index - OSD_VIEWPORT_SIZE

    end



    if state.selected_index == 1 then

        state.scroll_offset = 0

    elseif state.selected_index == #state.current_items then

        state.scroll_offset = math.max(0, #state.current_items - OSD_VIEWPORT_SIZE)

    end



    render_osd()

end



-- Функция для переключения видимости браузера

local function toggle_browser()

    state.is_visible = not state.is_visible

    msg.info("TorrServer Browser: " .. (state.is_visible and "ON" or "OFF"))



    if state.is_visible then

        mp.add_forced_key_binding("UP", "torr-nav-up", function() handle_key_press("UP") end, { repeatable = true })

        mp.add_forced_key_binding("DOWN", "torr-nav-down", function() handle_key_press("DOWN") end, { repeatable = true })

        mp.add_forced_key_binding("LEFT", "torr-nav-left", function() handle_key_press("LEFT") end)

        mp.add_forced_key_binding("RIGHT", "torr-nav-right", function() handle_key_press("RIGHT") end)

        mp.add_forced_key_binding("ENTER", "torr-nav-enter", function() handle_key_press("ENTER") end)

        mp.add_forced_key_binding("BS", "torr-nav-back", function() handle_key_press("BS") end)



        if #state.current_items == 0 then

            state.history = {}

            load_items("torrents")

        else

            render_osd()

        end

    else

        mp.remove_key_binding("torr-nav-up")

        mp.remove_key_binding("torr-nav-down")

        mp.remove_key_binding("torr-nav-left")

        mp.remove_key_binding("torr-nav-right")

        mp.remove_key_binding("torr-nav-enter")

        mp.remove_key_binding("torr-nav-back")

        render_osd()

    end

end



-- --- РЕГИСТРАЦИЯ ГОРЯЧИХ КЛАВИШ И СОБЫТИЙ ---

mp.add_key_binding(opts.open_key, "torrserver-browser-toggle", toggle_browser)



-- Обработчик для безопасного закрытия OSD после начала воспроизведения

mp.register_event("file-loaded", function()

    if state.is_visible and state.is_loading_playlist then

        state.is_loading_playlist = false

        toggle_browser()

    end

end)



msg.info("Скрипт TorrServer Browser загружен. Нажмите '" .. opts.open_key .. "' для открытия.")
