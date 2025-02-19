local utils = require "mp.utils"
local msg = require "mp.msg"

-- ===============================================
-- CONFIGURATION:
-- Если хотите, чтобы скрипт запускался автоматически (как в исходном варианте),
-- оставьте auto_mode = true.
-- Если же предпочитаете, чтобы скрипт не запускался до нажатия F7 (ручной режим),
-- установите auto_mode = false.
local auto_mode = false  -- по умолчанию: автоматический режим
-- ===============================================

-- Получаем путь к текущей папке скрипта
local script_path = debug.getinfo(1, "S").source:sub(2)
local script_dir = script_path:match("(.+[/\\])") or "./"

-- Файлы находятся в папке скрипта
local command_file = script_dir .. "mpv_cmd.txt"
local python_path = mp.find_config_file("VapourSynth/python.exe")  -- Укажите корректный путь к python.exe
local server_script = script_dir .. "mpv_http_server.py"

if not server_script then
    msg.error("Файл mpv_http_server.py не найден!")
    return
end

-- Глобальная переменная для хранения процесса сервера
local server_process = nil

-- Переменная состояния скрипта (включен/выключен)
-- Если auto_mode = true, то скрипт включён автоматически
local active = auto_mode

-- Переменная для хранения таймера обновления прогресса
local update_progress_timer = nil

----------------------------------------------------------------
-- Функция для запуска Python-сервера в фоне
----------------------------------------------------------------
local function start_server()
    if server_process and server_process.pid then
        msg.warn("Сервер уже запущен!")
        return
    end

    local args = { python_path, server_script }
    server_process = utils.subprocess({ args = args, detach = true })
    if server_process.error then
        msg.error("Ошибка запуска сервера: " .. server_process.error)
        server_process = nil
    else
        msg.info("Python сервер запущен.")
    end
end

----------------------------------------------------------------
-- Функция для остановки сервера
----------------------------------------------------------------
local function stop_server()
    if server_process and server_process.pid then
        msg.info("Останавливаем Python сервер...")
        local success
        if package.config:sub(1,1) == "\\" then
            success = os.execute("taskkill /PID " .. server_process.pid .. " /F")
        else
            success = os.execute("kill " .. server_process.pid)
        end
        if success then
            msg.info("Сервер успешно остановлен.")
        else
            msg.warn("Не удалось остановить сервер.")
        end
        server_process = nil
    else
        msg.warn("Сервер не запущен.")
    end
end

----------------------------------------------------------------
-- Функции обновления временных файлов
----------------------------------------------------------------
local function update_tracks()
    if not active then return end  -- Обновление происходит только когда скрипт активен
    local track_list = mp.get_property_native("track-list")
    if not track_list then return end

    local audio_options = ""
    local sub_options = '<option value="no">Откл.</option>'

    for _, track in ipairs(track_list) do
        if track.type == "audio" then
            local title = track.title or ("Аудио " .. tostring(track.id))
            local selected = track.selected and "selected" or ""
            audio_options = audio_options .. string.format('<option value="%s" %s>%s</option>', tostring(track.id), selected, title)
        elseif track.type == "sub" then
            local title = track.title or ("Субтитры " .. tostring(track.id))
            local selected = track.selected and "selected" or ""
            sub_options = sub_options .. string.format('<option value="%s" %s>%s</option>', tostring(track.id), selected, title)
        end
    end

    local audio_file_path = script_dir .. "mpv_tracks_audio.js"
    local audio_file = io.open(audio_file_path, "w")
    if audio_file then
        audio_file:write(audio_options)
        audio_file:close()
    end

    local sub_file_path = script_dir .. "mpv_tracks_sub.js"
    local sub_file = io.open(sub_file_path, "w")
    if sub_file then
        sub_file:write(sub_options)
        sub_file:close()
    end

    msg.debug("Обновлены списки аудио и субтитров")
end

local function update_current_file()
    if not active then return end
    local filename = mp.get_property("filename") or "Нет файла"
    local current_file_path = script_dir .. "mpv_current_file.js"
    local f = io.open(current_file_path, "w")
    if f then
        f:write(filename)
        f:close()
    end
end

local function update_progress()
    if not active then return end
    local time_pos = mp.get_property_number("time-pos") or 0
    local duration = mp.get_property_number("duration") or 0
    local progress_path = script_dir .. "mpv_progress.js"
    local f = io.open(progress_path, "w")
    if f then
        f:write(time_pos .. "/" .. duration)
        f:close()
    end
end

local function update_playlist()
    if not active then return end
    local playlist = mp.get_property_native("playlist")
    if not playlist then return end

    local playlist_items = ""
    for i, item in ipairs(playlist) do
        local title = item.title or item.filename or ("Файл " .. tostring(i))
        local is_current = (i - 1 == mp.get_property_number("playlist-pos"))
        if is_current then
            playlist_items = playlist_items .. string.format('<li onclick="playFile(%d)"><strong>%s</strong></li>', i - 1, title)
        else
            playlist_items = playlist_items .. string.format('<li onclick="playFile(%d)">%s</li>', i - 1, title)
        end
    end

    local playlist_file_path = script_dir .. "mpv_playlist.js"
    local playlist_file = io.open(playlist_file_path, "w")
    if playlist_file then
        playlist_file:write(playlist_items)
        playlist_file:close()
    end

    msg.debug("Обновлён плейлист")
end

----------------------------------------------------------------
-- Обработка команды из mpv_cmd.txt (оставляем без изменений)
----------------------------------------------------------------
local function read_command()
    local f = io.open(command_file, "r")
    if f then
        local content = f:read("*all")
        f:close()
        return content
    end
    return nil
end

local function clear_command()
    local f = io.open(command_file, "w")
    if f then
        f:write("")
        f:close()
    end
end

local function process_command()
    local cmd = read_command()
    if cmd and cmd ~= "" then
        msg.info("Выполняем команду: " .. cmd)
        mp.command(cmd)
        clear_command()
    end
    mp.add_timeout(0.5, process_command)
end

process_command()

----------------------------------------------------------------
-- Регистрируем события обновления временных файлов
-- Обработчики срабатывают, но обновление происходит только если active == true
----------------------------------------------------------------
mp.register_event("file-loaded", update_tracks)
mp.register_event("file-loaded", update_current_file)
mp.observe_property("playlist", "native", function() 
    if active then update_playlist() end 
end)

----------------------------------------------------------------
-- Очистка временных файлов при закрытии MPV
----------------------------------------------------------------
local function cleanup()
    local files_to_remove = {
        command_file,
        script_dir .. "mpv_tracks_audio.js",
        script_dir .. "mpv_tracks_sub.js",
        script_dir .. "mpv_current_file.js",
        script_dir .. "mpv_progress.js",
        script_dir .. "mpv_playlist.js"
    }

    for _, file in ipairs(files_to_remove) do
        local success, err = os.remove(file)
        if not success then
            msg.warn("Не удалось удалить файл: " .. file .. ". Ошибка: " .. (err or "неизвестная"))
        else
            msg.info("Удалён файл: " .. file)
        end
    end
end

----------------------------------------------------------------
-- При завершении работы MPV: останавливаем сервер и очищаем временные файлы
----------------------------------------------------------------
mp.register_event("shutdown", function()
    if active then
        stop_server()
    end
    cleanup()
end)

----------------------------------------------------------------
-- Инициализация автоматического режима:
-- Если auto_mode = true (по умолчанию), скрипт запускается автоматически:
-- сервер стартует, временные файлы создаются, а обновление прогресса происходит периодически.
----------------------------------------------------------------
if auto_mode then
    msg.info("Автоматический режим включен: скрипт запущен.")
    start_server()
    update_tracks()
    update_current_file()
    update_playlist()
    update_progress_timer = mp.add_periodic_timer(1, update_progress)
end

----------------------------------------------------------------
-- Ручной режим: переключение работы скрипта по горячей клавише F7.
-- При нажатии F7 происходит переключение состояния:
--   - Если скрипт включён (active = true), он отключается: обновления прекращаются и сервер останавливается.
--   - Если скрипт отключён, он включается: сервер запускается, временные файлы создаются, запускается таймер обновления.
----------------------------------------------------------------
mp.add_key_binding("F7", "toggle_script", function()
    if active then
        active = false
        msg.info("Ручной режим: скрипт отключен.")
        stop_server()
        if update_progress_timer then
            update_progress_timer:kill()
            update_progress_timer = nil
        end
    else
        active = true
        msg.info("Ручной режим: скрипт включен.")
        start_server()
        update_tracks()
        update_current_file()
        update_playlist()
        update_progress_timer = mp.add_periodic_timer(1, update_progress)
    end
end)

-- ===============================================
-- КОММЕНТАРИИ:
--
-- 1. Автоматический режим (как в исходном варианте):
--    • Оставьте auto_mode = true.
--    • Скрипт запустится автоматически при старте MPV:
--         - Сервер запустится.
--         - Временные файлы (аудио, субтитры, текущий файл, плейлист) будут созданы и обновляться автоматически.
--         - Файлы удалятся при закрытии плеера.
--
-- 2. Ручной режим:
--    • Установите auto_mode = false.
--    • В этом случае скрипт не запустится автоматически.
--    • Для его активации нажмите горячую клавишу F7:
--         - При первом нажатии скрипт включится (сервер запустится, файлы создадутся и обновятся).
--         - При повторном нажатии скрипт отключится.
--
-- 3. Горячая клавиша F7 переключает состояние скрипта (включение/выключение), позволяя вам вручную управлять его работой.
-- ===============================================
