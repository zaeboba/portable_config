mp.register_script_message("sleep", function(minutes)
    mp.osd_message("Set Sleep Timer for "..minutes.." minutes",5)
    mp.add_timeout(minutes * 60, function() mp.command("quit") end)
end)