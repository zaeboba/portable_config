local utils = require "mp.utils"
local msg = require "mp.msg"

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

msg.info("Запускаем Python сервер...")

-- Глобальная переменная для хранения процесса сервера
local server_process = nil

-- Функция для запуска Python-сервера в фоне
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

-- Автоматический запуск сервера при старте MPV
start_server()

-- Добавляем возможность запуска сервера по горячей клавише (по умолчанию закомментировано)
--[[
mp.add_key_binding("F7", "start_python_server", function()
    start_server()
end)
]]

-- Функция для остановки сервера
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

-- Очистка временных файлов
local function cleanup()
    local files_to_remove = {
        command_file,
        script_dir .. "mpv_tracks_audio.js",
        script_dir .. "mpv_tracks_sub.js",
        script_dir .. "mpv_current_file.js",
        script_dir .. "mpv_progress.js"
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

-- Если нужно, можно добавить открытие браузера через mp.add_timeout
-- Функция для чтения команды из mpv_cmd.txt
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
-- Обновление списков аудио и субтитров (сохраняем в .js файлы)
----------------------------------------------------------------
local function update_tracks()
    local track_list = mp.get_property_native("track-list")
    if not track_list then return end

    local audio_options = ""
    local sub_options = '<option value="no">Откл.</option>'

    for _, track in ipairs(track_list) do
        if track.type == "audio" then
            local title = track.title or ("Аудио " .. tostring(track.id))
            audio_options = audio_options .. string.format('<option value="%s">%s</option>', tostring(track.id), title)
        elseif track.type == "sub" then
            local title = track.title or ("Субтитры " .. tostring(track.id))
            sub_options = sub_options .. string.format('<option value="%s">%s</option>', tostring(track.id), title)
        end
    end

    -- Сохраняем данные в файлы
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

    msg.info("Обновлены списки аудио и субтитров")
end

-- Вызываем update_tracks только при загрузке нового файла
mp.register_event("file-loaded", update_tracks)

----------------------------------------------------------------
-- Обновление текущего файла и прогресса воспроизведения
----------------------------------------------------------------
local function update_current_file()
    local filename = mp.get_property("filename") or "Нет файла"
    local current_file_path = script_dir .. "mpv_current_file.js"
    local f = io.open(current_file_path, "w")
    if f then
        f:write(filename)
        f:close()
    end
end

mp.register_event("file-loaded", update_current_file)

local function update_progress()
    local time_pos = mp.get_property_number("time-pos") or 0
    local duration = mp.get_property_number("duration") or 0
    local progress_path = script_dir .. "mpv_progress.js"
    local f = io.open(progress_path, "w")
    if f then
        f:write(time_pos .. "/" .. duration)
        f:close()
    end
end

mp.add_periodic_timer(1, update_progress)

----------------------------------------------------------------
-- Остановка Python сервера и очистка временных файлов при закрытии MPV
----------------------------------------------------------------
mp.register_event("shutdown", function()
    -- Пытаемся остановить сервер
    pcall(stop_server)  -- Используем pcall, чтобы игнорировать ошибки при остановке сервера
    -- Всегда выполняем очистку файлов
    cleanup()
end)