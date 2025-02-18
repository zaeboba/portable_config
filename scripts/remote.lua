local utils = require "mp.utils"
local msg = require "mp.msg"
local command_file = mp.find_config_file("mpv_cmd.txt")
local python_path = mp.find_config_file("VapourSynth/python.exe")  -- Укажите путь к Python
local server_script = mp.find_config_file("mpv_http_server.py")

if not command_file or not server_script then
    msg.error("Файл mpv_cmd.txt или mpv_http_server.py не найден!")
    return
end

msg.info("Запускаем Python сервер...")

-- Функция для скрытого запуска Python-сервера
local server_process
local function start_server()
    local args = { python_path, server_script }
    server_process = utils.subprocess({ args = args, detach = true })  -- Запускаем в фоне
    if server_process.error then
        msg.error("Ошибка запуска сервера: " .. server_process.error)
    else
        msg.info("Python сервер запущен.")
    end
end

-- Открываем веб-интерфейс в браузере
local function open_browser()
    local url = "http://localhost:1337"
    local browser_cmd = { "cmd", "/c", "start", "", url }  -- Windows (скрыто)
    utils.subprocess({ args = browser_cmd, detach = true })
    msg.info("Открываем веб-интерфейс: " .. url)
end

start_server()
-- mp.add_timeout(2, open_browser)  -- Через 2 секунды открываем браузер

-- Завершаем Python-сервер при выходе из MPV
-- local function stop_server()
--     msg.info("Останавливаем сервер...")
--     local stop_cmd = { python_path, server_script, "stop" }
--     utils.subprocess({ args = stop_cmd, detach = false })  -- Отправляем команду завершения
-- end
-- mp.register_event("shutdown", stop_server)  -- Вызываем при выходе

-- Функция для чтения команд из mpv_cmd.txt
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
    mp.add_timeout(0.5, process_command)  -- Проверяем файл каждые 0.5 сек
end

process_command()

-- ===============================================
-- Новый блок: обновление списка аудио и субтитров
-- ===============================================
local function update_tracks()
    local track_list = mp.get_property_native("track-list")
    if not track_list then return end

    local audio_options = ""
    -- Для субтитров добавляем опцию "Откл." по умолчанию
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

    -- Определяем пути для записи файлов с опциями
    local audio_file_path = mp.find_config_file("mpv_tracks_audio.html") or "mpv_tracks_audio.html"
    local audio_file = io.open(audio_file_path, "w")
    if audio_file then
        audio_file:write(audio_options)
        audio_file:close()
    end

    local sub_file_path = mp.find_config_file("mpv_tracks_sub.html") or "mpv_tracks_sub.html"
    local sub_file = io.open(sub_file_path, "w")
    if sub_file then
        sub_file:write(sub_options)
        sub_file:close()
    end

    msg.info("Обновлены списки аудио и субтитров")
end

-- Обновляем информацию каждые 5 секунд
mp.add_periodic_timer(5, update_tracks)
