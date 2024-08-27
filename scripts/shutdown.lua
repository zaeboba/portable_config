-- Объявляем переменные
local shutdown_timeout = nil
local notification_timeout = nil
local countdown_timeout = nil
local time_left = nil
local countdown_started = false

-- Функция для выключения компьютера
local function shutdown_computer()
    mp.osd_message("Выключение компьютера...", 2)
    os.execute("shutdown /s /f /t 0")
end

-- Функция для отмены выключения
local function cancel_shutdown()
    if shutdown_timeout then
        shutdown_timeout:kill()
        shutdown_timeout = nil
    end
    if notification_timeout then
        notification_timeout:kill()
        notification_timeout = nil
    end
    if countdown_timeout then
        countdown_timeout:kill()
        countdown_timeout = nil
    end
    countdown_started = false
    mp.osd_message("Выключение отменено", 2)
end

-- Функция для обновления таймера
local function update_timer()
    if time_left <= 0 then
        shutdown_computer()
        return
    end

    time_left = time_left - 1
    local minutes = math.floor(time_left / 60)
    local seconds = time_left % 60
    local time_display = string.format("%02d:%02d", minutes, seconds)
    
    if countdown_started then
        mp.osd_message("Осталось " .. time_display .. ". Нажмите 'Pause' для отмены.", 1)
    end

    if time_left > 0 then
        countdown_timeout = mp.add_timeout(1, update_timer)
    end
end

-- Функция для показа начального уведомления
local function show_initial_notification()
    local minutes = math.floor(time_left / 60)
    mp.osd_message("Компьютер будет выключен через " .. minutes .. " минут.", 5)
end

-- Функция для запуска таймера и отображения 30-секундного отсчета
local function start_countdown_timer()
    countdown_timeout = mp.add_timeout(30, function()
        countdown_started = true
        time_left = 30
        update_timer()
    end)
end

-- Функция для установки таймера на выключение
local function set_shutdown_timer(minutes)
    cancel_shutdown() -- Отменяем текущий таймер, если есть
    time_left = minutes * 60 -- Переводим минуты в секунды
    -- Показываем начальное уведомление
    show_initial_notification()
    -- Запланируем запуск таймера отсчета за 30 секунд до выключения
    shutdown_timeout = mp.add_timeout((minutes - 0.5) * 60, start_countdown_timer)
end

-- Регистрация команды для установки таймера через script-message
mp.register_script_message("shutdown-timer", function(minutes)
    local num_minutes = tonumber(minutes)
    if num_minutes and num_minutes > 0 then
        set_shutdown_timer(num_minutes)
    else
        mp.osd_message("Неверное значение таймера. Пожалуйста, укажите положительное число минут.", 3)
    end
end)

-- Назначаем горячую клавишу для отмены выключения
mp.add_key_binding("Pause", "cancel-shutdown", cancel_shutdown)
