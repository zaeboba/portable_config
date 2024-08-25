-- Название: shutdown_timer.lua
-- Описание: Скрипт для MPV, который устанавливает таймер на выключение компьютера.

-- Функция для выполнения команды на выключение компьютера
function shutdown_computer()
    local shutdown_command
    if package.config:sub(1,1) == '\\' then
        -- Если система Windows
        shutdown_command = "shutdown /s /t 0"
    else
        -- Для Unix-подобных систем (Linux, macOS)
        shutdown_command = "shutdown -h now"
    end

    -- Выполнение команды на выключение
    local result = os.execute(shutdown_command)
    if result ~= 0 then
        mp.msg.error("Failed to execute shutdown command")
    else
        mp.msg.info("Shutdown command executed successfully")
    end
end

-- Функция, вызываемая при нажатии клавиши для установки таймера
function set_shutdown_timer(minutes)
    -- Проверка, что значение минут в пределах от 5 до 120
    if minutes < 5 or minutes > 120 then
        mp.msg.error("Please enter a value between 5 and 120 minutes")
        return
    end

    local seconds = minutes * 60
    mp.msg.info("Computer will shutdown in " .. minutes .. " minutes")
    mp.add_timeout(seconds, shutdown_computer)
end

-- Добавляем команду и горячие клавиши для установки таймера на разные времена
mp.add_key_binding("", "shutdown-in-5-minutes", function() set_shutdown_timer(5) end)
mp.add_key_binding("", "shutdown-in-10-minutes", function() set_shutdown_timer(10) end)
mp.add_key_binding("", "shutdown-in-20-minutes", function() set_shutdown_timer(20) end)
mp.add_key_binding("", "shutdown-in-30-minutes", function() set_shutdown_timer(30) end)
mp.add_key_binding("", "shutdown-in-60-minutes", function() set_shutdown_timer(60) end)
mp.add_key_binding("", "shutdown-in-90-minutes", function() set_shutdown_timer(90) end)
mp.add_key_binding("", "shutdown-in-120-minutes", function() set_shutdown_timer(120) end)
