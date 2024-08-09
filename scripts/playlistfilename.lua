local msg = require 'mp.msg'

function main()
    local filename = mp.get_property("filename")
    msg.error("filename: ", filename)

    -- Set force-media-title option to the filename value
    mp.set_property("options/force-media-title", filename)
end

mp.add_hook("on_preloaded", 50, main)