local duration = mp.get_property('image-display-duration')

mp.add_key_binding(nil, 'reset-image-display-duration', function ()
    mp.set_property('image-display-duration reset to 1.5x', duration)
end)