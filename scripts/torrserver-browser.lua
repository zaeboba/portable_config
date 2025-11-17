--[[
MPV TorrServer Browser

Скрипт для просмотра и воспроизведения торрентов с TorrServer прямо в MPV.

Created by: zaeboba
License: 🖕
Version: 16.11.2025
--]]

local mp = require("mp")
local msg = require("mp.msg")
local utils = require("mp.utils")
local opt = require("mp.options")

package.path = mp.command_native({ "expand-path", "~~/script-modules/?.lua;" }) .. package.path
local input_success, input = pcall(require, "user-input-module")

if not input_success then
	local function get_script_path()
		local info = debug.getinfo(1, "S")
		if info and info.source then
			local source = info.source
			if source:sub(1, 1) == "@" then
				source = source:sub(2)
			end
			local path = utils.split_path(source)
			return path
		end
		return nil
	end

	local script_path = get_script_path()
	if script_path then
		package.path = script_path .. "?.lua;" .. package.path
		input_success, input = pcall(require, "user-input-module")
	end
end

if not input_success then
	msg.warn("user-input-module не найден, используем встроенную версию")

	local input_mod = {}
	local input_name = mp.get_script_name()
	local input_counter = 1

	local function pack(...)
		local t = { ... }
		t.n = select("#", ...)
		return t
	end

	local request_mt = {}

	local function format_options(options, response_string)
		return {
			response = response_string,
			version = "0.1.0",
			id = input_name .. "/" .. (options.id or ""),
			source = input_name,
			request_text = ("[%s] %s"):format(
				options.source or input_name,
				options.request_text or options.text or "requesting user input:"
			),
			default_input = options.default_input,
			cursor_pos = tonumber(options.cursor_pos),
			queueable = options.queueable and true,
			replace = options.replace and true,
		}
	end

	function request_mt:cancel()
		if self.uid then
			mp.commandv("script-message-to", "user_input", "cancel-user-input/uid", self.uid)
		end
	end

	function input_mod.get_user_input(fn, options, ...)
		options = options or {}
		local response_string = input_name .. "/__user_input_request/" .. input_counter
		input_counter = input_counter + 1

		local request = {
			uid = response_string,
			passthrough_args = pack(...),
			callback = fn,
			pending = true,
		}

		mp.register_script_message(response_string, function(response)
			mp.unregister_script_message(response_string)
			request.pending = false

			local parsed = utils.parse_json(response)
			if parsed then
				request.callback(
					parsed.line,
					parsed.err,
					unpack(request.passthrough_args, 1, request.passthrough_args.n)
				)
			else
				request.callback(nil, "Failed to parse response")
			end
		end)

		options = utils.format_json(format_options(options, response_string))
		mp.commandv("script-message-to", "user_input", "request-user-input", options)

		return setmetatable(request, { __index = request_mt })
	end

	input = input_mod
	input_success = true
end

-- --- НАСТРОЙКИ ---
local opts = {
	torrserver_url = "http://10.10.1.28:8090",
	open_key = "M",
}
opt.read_options(opts, mp.get_script_name())

local OSD_VIEWPORT_SIZE = 29 -- как в jellyfin.lua

local state = {
	is_visible = false,
	current_items = {},
	selected_index = 1,
	scroll_offset = 0,
	osd_overlay = nil,
	current_view_type = "torrents", -- "torrents", "files", "search"
	current_torrent_hash = nil,
	history = {},
	is_loading_playlist = false,
	search_query = "",
}

-- --- НАСТРОЙКИ OSD ---
local align_x = 1 -- 1 = left, 2 = center, 3 = right
local align_y = 4 -- 4 = top, 8 = center, 0 = bottom
local align_main = "{\\a0}"
local align_other = "{\\a7}"

-- Цвета как в jellyfin.lua
local colour_default = "FFFFFF"
local colour_selected = "00FFFF"
local colour_watched = "A0A0A0"

local function line_break(str, flags, space)
	if str == nil then
		return ""
	end
	local text = flags
	local n = 0
	for i = 1, #str do
		local c = str:sub(i, i)
		if (c == " " and i - n > space) or c == "\n" then
			text = text .. str:sub(n, i - 1) .. "\n" .. flags
			n = i + 1
		end
	end
	text = text .. str:sub(n, -1)
	return text
end

local function set_align()
	align_other = "{\\a" .. ((4 - align_x) + align_y) .. "}"
end

local function align_x_change(name, data)
	if data == "right" then
		align_x = 3
	elseif data == "center" then
		align_x = 2
	else
		align_x = 1
	end
	set_align()
end

local function align_y_change(name, data)
	if data == "bottom" then
		align_y = 0
	elseif data == "center" then
		align_y = 8
	else
		align_y = 4
	end
	set_align()
end

local function post_torrent(url)
	local curl_cmd = {
		"curl",
		"-X",
		"POST",
		opts.torrserver_url .. "/torrent/upload",
		"-H",
		"accept: application/json",
		"-H",
		"Content-Type: multipart/form-data",
		"-F",
		'file=@"' .. url .. '"',
	}
	local res, err = mp.command_native({
		name = "subprocess",
		capture_stdout = true,
		playback_only = false,
		args = curl_cmd,
	})

	if err then
		return nil, err
	end

	if not res or not res.stdout then
		return nil, "Empty response from TorrServer"
	end

	local parsed = utils.parse_json(res.stdout)
	if not parsed or not parsed.hash then
		return nil, "Failed to parse TorrServer response"
	end

	return parsed
end

function string:endswith(suffix)
	return suffix and self:sub(-#suffix) == suffix
end

local function format_size(size_str)
	if not size_str or size_str == "" then
		return "N/A"
	end
	if size_str:match("[KMGT]B") then
		return size_str
	end
	local bytes = tonumber(size_str)
	if not bytes then
		return size_str
	end
	local units = { "B", "KB", "MB", "GB", "TB" }
	local unit_index = 1
	while bytes >= 1024 and unit_index < #units do
		bytes = bytes / 1024
		unit_index = unit_index + 1
	end
	return string.format("%.2f%s", bytes, units[unit_index])
end

-- Функция для парсинга результатов поиска
local function parse_search_results(json_content)
	local items = {}
	if not json_content or json_content == "" then
		return items
	end

	local parsed = utils.parse_json(json_content)
	if not parsed then
		msg.warn("TorrServer Browser: Не удалось распарсить JSON ответ")
		return items
	end

	-- Проверяем, что это массив
	if type(parsed) ~= "table" or not parsed[1] then
		msg.warn("TorrServer Browser: JSON ответ не является массивом")
		return items
	end

	for _, result in ipairs(parsed) do
		if type(result) == "table" then
			-- Используем поля с заглавной буквы из JSON (с fallback на маленькие)
			local title = result.Title or result.title or result.Name or result.name or "Без названия"
			local hash = result.Hash or result.hash or ""
			local size_str = result.Size or result.size or ""
			local peer = result.Peer or result.peer or 0
			local seed = result.Seed or result.seed or 0
			local magnet = result.Magnet or result.magnet or ""

			local item = {
				name = title,
				hash = hash,
				size = format_size(size_str),
				peer = tonumber(peer) or 0,
				seed = tonumber(seed) or 0,
				magnet = magnet,
				link = result.Link or result.link or "",
				year = result.Year or result.year or 0,
			}

			-- Формируем stream_link для воспроизведения (используем Hash или Magnet)
			if item.hash and item.hash ~= "" then
				item.stream_link = opts.torrserver_url .. "/stream?m3u&link=" .. item.hash
			elseif item.magnet and item.magnet ~= "" then
				item.stream_link = opts.torrserver_url .. "/stream?m3u&link=" .. item.magnet
			end

			table.insert(items, item)
		end
	end

	return items
end

-- Функция для парсинга M3U контента
local function parse_m3u(m3u_content)
	local items = {}
	if not m3u_content then
		return items
	end

	local lines = {}
	for line in m3u_content:gmatch("([^\n\r]+)") do
		table.insert(lines, line)
	end

	local i = 1
	while i <= #lines do
		local line = lines[i]
		if line:match("^#EXTINF") then
			local name = line:match(".-,(.+)")

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

	local magic_num = OSD_VIEWPORT_SIZE
	if state.selected_index - state.scroll_offset > magic_num then
		state.scroll_offset = state.selected_index - magic_num
	elseif state.selected_index - state.scroll_offset < 0 then
		state.scroll_offset = state.selected_index
	end

	local ass = align_main .. "{\\fs16}"

	if #state.current_items == 0 then
		ass = ass .. "{\\c&H" .. colour_default .. "&}Загрузка...\\N"
	else
		local title = "{\\fs24}{\\b1}Браузер TorrServer{\\b0}"
		if state.current_view_type == "files" and #state.history > 0 then
			title = title
				.. "\\N{\\fs16}{\\i1}Торрент: "
				.. (state.history[#state.history].name or "Неизвестно")
				.. "{\\i0}"
		elseif state.current_view_type == "search" and state.search_query ~= "" then
			title = title .. "\\N{\\fs16}{\\i1}Поиск: " .. state.search_query .. "{\\i0}"
		end
		ass = ass .. align_other .. title .. "\\N\\N"

		local start_index = state.scroll_offset + 1
		local end_index = math.min(#state.current_items, state.scroll_offset + magic_num)

		for i = start_index, end_index do
			if i > #state.current_items then
				break
			end
			local item = state.current_items[i]
			local index = ""

			ass = ass .. "{\\fs16}" .. "{\\c&H"
			if i == state.selected_index then
				ass = ass .. colour_selected
			else
				ass = ass .. colour_default
			end
			ass = ass .. "&}" .. index

			if state.current_view_type == "search" then
				-- Формат: Titles / Size / [Peer/Seed]
				local display_name = item.name or "Без названия"
				local size = item.size or "N/A"
				local peer = item.peer or 0
				local seed = item.seed or 0
				ass = ass .. display_name .. " / " .. size .. " / [" .. peer .. "/" .. seed .. "]"
			else
				ass = ass .. (item.name or "Без имени")
			end

			ass = ass .. "\\N"
		end
	end

	state.osd_overlay.data = ass
	state.osd_overlay:update()
end

-- Функция для загрузки результатов поиска
local function load_search_results(query)
	if not query or query == "" then
		return
	end

	state.current_view_type = "search"
	state.current_items = {}
	state.selected_index = 1
	state.scroll_offset = 0
	state.search_query = query

	render_osd()

	-- URL-кодируем запрос
	local url_query = string.gsub(query, " ", "%%20")
	local url = opts.torrserver_url .. "/search/?query=" .. url_query

	local args = { "curl", "-s", "-L", url }
	msg.debug("TorrServer Browser: Executing search: " .. table.concat(args, " "))

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		args = args,
		capture_stdout = true,
		capture_stderr = true,
	}, function(success, result, error)
		if not success then
			msg.error("TorrServer Browser: Failed to execute search: " .. (error or "unknown"))
			state.current_items = { { name = "Ошибка выполнения поиска" } }
			render_osd()
			return
		end

		if result.stderr and result.stderr ~= "" then
			msg.error("TorrServer Browser: Search stderr: " .. result.stderr)
		end

		local json_content = result.stdout or ""

		-- Отладочная информация
		if json_content == "" then
			msg.warn("TorrServer Browser: Пустой ответ от сервера")
			state.current_items = { { name = "Пустой ответ от сервера" } }
			render_osd()
			return
		end

		local parsed_items = parse_search_results(json_content)

		if #parsed_items == 0 then
			msg.warn(
				"TorrServer Browser: Поиск не дал результатов или ошибка парсинга"
			)
			msg.debug("TorrServer Browser: JSON ответ: " .. json_content:sub(1, 500))
			state.current_items = { { name = "Нет результатов поиска" } }
			render_osd()
			return
		end

		msg.info("TorrServer Browser: Найдено результатов: " .. #parsed_items)

		-- Сортируем результаты поиска по Seed (от большего к меньшему)
		table.sort(parsed_items, function(a, b)
			local seed_a = a.seed or 0
			local seed_b = b.seed or 0
			return seed_a > seed_b
		end)

		state.current_items = parsed_items
		render_osd()
	end)
end

-- Функция для загрузки элементов
local function load_items(view_type, data)
	state.current_view_type = view_type
	state.current_items = {}
	state.selected_index = 1
	state.scroll_offset = 0
	state.search_query = ""

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

	local args = { "curl", "-s", "-L", url }
	msg.debug("TorrServer Browser: Executing curl command: " .. table.concat(args, " "))

	mp.command_native_async({
		name = "subprocess",
		playback_only = false,
		args = args,
		capture_stdout = true,
		capture_stderr = true,
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
				msg.debug(
					"TorrServer Browser: Curl stdout (first "
						.. max_log_lines
						.. "/"
						.. #lines
						.. " lines):\n"
						.. partial_log
						.. "\n..."
				)
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
		table.sort(state.current_items, function(a, b)
			return (a.name or "") < (b.name or "")
		end)
		render_osd()
	end)
end

local function handle_key_press(key)
	if key == "ESC" then
		if state.is_visible then
			toggle_browser(false)
		end
		return
	end

	if #state.current_items == 0 then
		return
	end

	if key == "UP" then
		state.selected_index = state.selected_index - 1

		if state.selected_index < 1 then
			state.selected_index = #state.current_items
		end
	elseif key == "DOWN" then
		state.selected_index = state.selected_index + 1

		if state.selected_index > #state.current_items then
			state.selected_index = 1
		end
	elseif key == "RIGHT" or key == "ENTER" then
		local selected_item = state.current_items[state.selected_index]

		if not selected_item then
			return
		end

		if state.current_view_type == "torrents" then
			if selected_item.stream_link then
				table.insert(state.history, {

					view_type = state.current_view_type,

					selected_index = state.selected_index,

					name = selected_item.name,

					items = state.current_items, -- Сохраняем весь список
				})

				load_items("files", selected_item.stream_link)
			else
				msg.warn(
					"Не удалось получить ссылку для торрента: " .. selected_item.name
				)
			end
		elseif state.current_view_type == "search" then
			if selected_item.stream_link then
				state.is_loading_playlist = true

				-- Запускаем только выбранный файл, заменяя текущий (без добавления остальных)
				mp.commandv("loadfile", selected_item.stream_link, "replace")

				-- OSD закроется автоматически по событию file-loaded
			else
				msg.warn(
					"Не удалось получить ссылку для результата поиска: "
						.. selected_item.name
				)
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
		-- Если мы в режиме поиска, возвращаемся к списку торрентов
		if state.current_view_type == "search" then
			state.current_view_type = "torrents"
			state.search_query = ""
			load_items("torrents")
			return
		end

		-- Обычная логика навигации назад через историю
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
			toggle_browser(false)
		end
	end

	render_osd()
end

-- Функция для поиска
local function search_input()
	if not input_success then
		msg.warn(
			"Модуль user-input-module не найден. Установите его для использования поиска."
		)
		return
	end

	input.get_user_input(function(query, err)
		if query ~= nil and query ~= "" then
			load_search_results(query)
		end
	end)
end

local function toggle_browser(force_state)
	local desired_state
	if force_state == nil then
		desired_state = not state.is_visible
	else
		desired_state = force_state and true or false
	end

	if state.is_visible == desired_state then
		return
	end

	state.is_visible = desired_state

	msg.info("TorrServer Browser: " .. (state.is_visible and "ON" or "OFF"))

	if state.is_visible then
		-- Блокируем все горячие клавиши mpv (используем add_forced_key_binding)
		mp.add_forced_key_binding("UP", "torr-nav-up", function()
			handle_key_press("UP")
		end, { repeatable = true })

		mp.add_forced_key_binding("DOWN", "torr-nav-down", function()
			handle_key_press("DOWN")
		end, { repeatable = true })

		mp.add_forced_key_binding("LEFT", "torr-nav-left", function()
			handle_key_press("LEFT")
		end)

		mp.add_forced_key_binding("RIGHT", "torr-nav-right", function()
			handle_key_press("RIGHT")
		end)

		mp.add_forced_key_binding("ENTER", "torr-nav-enter", function()
			handle_key_press("ENTER")
		end)

		mp.add_forced_key_binding("BS", "torr-nav-back", function()
			handle_key_press("BS")
		end)

		-- Добавляем клавишу поиска
		mp.add_forced_key_binding("f", "torr-search", function()
			search_input()
		end)

		-- Добавляем клавишу ESC для закрытия OSD
		mp.add_forced_key_binding("ESC", "torr-nav-esc", function()
			mp.add_timeout(0, function()
				toggle_browser(false)
			end)
		end)

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

		mp.remove_key_binding("torr-search")

		mp.remove_key_binding("torr-nav-esc")

		render_osd()
	end
end

mp.add_key_binding(opts.open_key, "torrserver-browser-toggle", toggle_browser)

mp.observe_property("osd-align-x", "string", align_x_change)
mp.observe_property("osd-align-y", "string", align_y_change)
set_align()

mp.register_event("file-loaded", function()
	if state.is_visible and state.is_loading_playlist then
		state.is_loading_playlist = false

		toggle_browser(false)
	end
end)

mp.add_hook("on_load", 5, function()
	local url = mp.get_property("stream-open-filename")
	if not url then
		return
	end

	if url:endswith(".torrent") then
		local res, err = post_torrent(url)
		if err then
			msg.error("TorrServer Browser: " .. err)
			return
		end
		mp.set_property("stream-open-filename", opts.torrserver_url .. "/stream?m3u&link=" .. res.hash)
	elseif url:find("magnet:") == 1 then
		mp.set_property("stream-open-filename", opts.torrserver_url .. "/stream?m3u&link=" .. url)
	end
end)

msg.info(
	"Скрипт TorrServer Browser загружен. Нажмите '"
		.. opts.open_key
		.. "' для открытия."
)
