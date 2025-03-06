local hibernate_timer = nil
local countdown_timer = nil

-- Функция для перевода компьютера в гибернацию
local function hibernate_computer()
    os.execute("shutdown /h")
end

-- Функция для отображения обратного отсчета
local function start_countdown()
    local seconds_left = 30

    -- Функция для обновления обратного отсчета
    local function update_timer()
        if seconds_left > 0 then
            mp.osd_message("Гибернация через " .. seconds_left .. " секунд, нажмите PAUSE для отмены", 1)
            seconds_left = seconds_left - 1
            countdown_timer = mp.add_timeout(1, update_timer)
        else
            hibernate_computer()
        end
    end

    -- Запускаем обратный отсчёт
    update_timer()
end

-- Функция для установки таймера
local function set_hibernate_timer(minutes)
    mp.osd_message("Компьютер перейдет в гибернацию через " .. minutes .. " минут.", 5)
    hibernate_timer = mp.add_timeout((minutes * 60) - 30, start_countdown)
end

-- Функция для отмены таймера гибернации и обратного отсчёта
local function cancel_hibernate()
    if hibernate_timer then
        hibernate_timer:kill()
        hibernate_timer = nil
    end
    if countdown_timer then
        countdown_timer:kill()
        countdown_timer = nil
    end
    mp.osd_message("Гибернация отменена", 2)
end

-- Регистрация команды для установки таймера через script-message
mp.register_script_message("hibernate-timer", function(minutes)
    local num_minutes = tonumber(minutes)
    if num_minutes and num_minutes > 0 then
        set_hibernate_timer(num_minutes)
    else
        mp.osd_message("Неверное значение таймера. Пожалуйста, укажите положительное число минут.", 3)
    end
end)

-- Назначаем горячую клавишу для отмены таймера
mp.add_key_binding("Pause", "cancel-hibernate", cancel_hibernate)
