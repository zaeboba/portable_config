-- A simple script to show multiple shaders running, in a clean list. Also hides osd messages of shader changes.

data = ""

function slist(input, forced)
    if input == nil then data = "No shaders loaded." return end
    local only_a4k = true
    local fileNames = {}
    local paths = {}
	if input ~= '' then
		for path in input:gmatch("[^,;]+") do
			table.insert(paths, path)
		end

		for _, path in ipairs(paths) do
			local fileName = path:match(".+/(.+)$") or path:match(".+\\(.+)$")
			if fileName then
				table.insert(fileNames, fileName)
			end
		end
		
		local listString = "Shaders loaded:"
		for i, fileName in ipairs(fileNames) do
			listString = listString .. "\n" .. i .. ") " .. fileName
            if fileName:find("Anime4K") == nil then only_a4k = false end
		end
        if only_a4k and not forced then
            data = ""
		else
            data = listString
        end
	else
		data = "No shaders loaded."
	end
end


function update_list(k, glsl)
	slist(glsl)
    if glsl ~= "" and data ~= "" then mp.osd_message(data) end
end

function show_list()
	slist(mp.get_property('glsl-shaders'), true)
    mp.osd_message(data)
end

function clear_shaders()
	if mp.get_property('glsl-shaders') ~= '' then
		mp.command('change-list glsl-shaders clr all')
	end
end

mp.add_key_binding(nil, 'shader-view', show_list)
mp.add_key_binding(nil, 'shader-clear', clear_shaders)
mp.observe_property('glsl-shaders', "string", update_list)