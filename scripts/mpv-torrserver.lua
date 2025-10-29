-- Install [Torrserver](https://github.com/YouROK/TorrServer)

local opts = {
	server = "http://localhost:8090",
}

(require("mp.options")).read_options(opts)

local function post_torrent(url)
	local curl_cmd = {
		"curl",
		"-X",
		"POST",
		opts.server .. "/torrent/upload",
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

	return (require("mp.utils")).parse_json(res.stdout)
end

function string:endswith(suffix)
	return self:sub(-#suffix) == suffix
end

mp.add_hook("on_load", 5, function()
	local url = mp.get_property("stream-open-filename")

	if url:endswith(".torrent") then
		local res, err = post_torrent(url)

		if err then
			mp.msg.error(err)
			return
		end

		mp.set_property("stream-open-filename", opts.server .. "/stream?m3u&link=" .. res.hash)
	end

	if url:find("magnet:") == 1 then
		mp.set_property("stream-open-filename", opts.server .. "/stream?m3u&link=" .. url)
	end
end)
