local utils = require 'mp.utils'
local subprocess_handle_1 = nil
local subprocess_handle_2 = nil

-- Функция для поиска программы
function find_program_path(program_relative_path)
    local mpv_cwd = mp.command_native({"expand-path", "~~/"})
    local program_path = utils.join_path(mpv_cwd, program_relative_path)

    -- Проверка существования файла
    local file_info = utils.file_info(program_path)
    if file_info then
        return program_path
    else
        return nil
    end
end

-- Функция запуска первой программы (TorrServer)
function run_program_1()
    if subprocess_handle_1 == nil then
        local program_path = find_program_path("TorrServer/tsl.exe")

        if program_path == nil then
            return
        end

        -- Запуск программы
        local command = 'cmd /c start "" /B "' .. program_path .. '"'
        local result = os.execute(command)

        if result == 0 then
            subprocess_handle_1 = true  -- Помечаем, что программа запущена
        else
            subprocess_handle_1 = nil
        end
    end
end

-- Функция запуска второй программы (замените путьдо/программы.exe на свой путь)
function run_program_2()
    if subprocess_handle_2 == nil then
        local program_path = find_program_path("AceStream/engine/ace_engine.exe")  -- Замените на путь к папке и файл второй программы

        if program_path == nil then
            return
        end

        -- Запуск программы
        local command = 'cmd /c start "" /B "' .. program_path .. '"'
        local result = os.execute(command)

        if result == 0 then
            subprocess_handle_2 = true  -- Помечаем, что программа запущена
        else
            subprocess_handle_2 = nil
        end
    end
end

-- Функция для закрытия первой программы через taskkill
function kill_program_1_on_exit()
    local command = 'cmd /c start /B taskkill /IM TorrServer-windows-amd64.exe /F'
    os.execute(command)
end

-- Функция для закрытия второй программы через taskkill (замените на имя процесса второй программы)
function kill_program_2_on_exit()
    local command = 'cmd /c start /B taskkill /IM another_program_process.exe /F'  -- Замените на имя процесса второй программы
    os.execute(command)
end

-- Функция для открытия ссылки в браузере по умолчанию
function open_url_TorrServer()
    local url = "http://localhost:8090/"  -- Замените на нужный URL
    local command = 'cmd /c start "" "' .. url .. '"'
    os.execute(command)
end

-- Функция для открытия ссылки в браузере по умолчанию
function open_url_addon_firefox()
    local url = "https://addons.mozilla.org/ru/firefox/addon/torrserver-adder/"  -- Замените на нужный URL
    local command = 'cmd /c start "" "' .. url .. '"'
    os.execute(command)
end

-- Функция для открытия ссылки в браузере по умолчанию
function open_url_addon_chrome()
    local url = "https://chromewebstore.google.com/detail/torrserver-adder/ihphookhabmjbgccflngglmidjloeefg"  -- Замените на нужный URL
    local command = 'cmd /c start "" "' .. url .. '"'
    os.execute(command)
end

-- Привязываем запуск первой программы к клавише 
mp.add_key_binding("", "run_torrserver", run_program_1)
mp.add_key_binding("", "run_acestream", run_program_2)

-- Привязываем открытие ссылки в браузере к клавише (замените на любую другую клавишу)
mp.add_key_binding("", "open_url_TorrServer", open_url_TorrServer)
mp.add_key_binding("", "open_url_addon_firefox", open_url_addon_firefox)
mp.add_key_binding("", "open_url_addon_chrome", open_url_addon_chrome)

-- Добавляем обработчик выхода из MPV для завершения программ, которые были запущены
function kill_programs_on_exit()
    kill_program_1_on_exit()
    kill_program_2_on_exit()
end

-- mp.register_event("shutdown", kill_programs_on_exit)

-- я не знаю как сделать проверку запускались ли проги чтобы при закрытии вызывать убийство процесса, если расскоментировать строчку выше
-- они будут "убиваться" даже если небыли запущены, а это выглядит уёбищно
-- если вы пограмист и гений, почините скрипт за меня, пожалуйста.

-- I don't know how to check if the programs were running so that when closing, it calls for killing the process. If I uncomment the line above,
-- they will be "killed" even if they weren't started, and that looks terrible.
-- If you are a programmer and a genius, please fix the script for me.