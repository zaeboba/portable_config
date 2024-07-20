-- Tested on Anime4K version v4.0.1 and mpv-x86_64-20211219-git-fd63bf3
--
-- Automatically turn on Anime4K depending on video resolution
local createhidden = false --create a hidden file (useless if you enabled "show hidden files and folders")
-- Now, you can create indicator file with your manually choosed Anime4K shaders to automatically turn on it later

--Only for backward compatibility
local quality = "Fast" -- Fast or HQ
local alwaysenabled = false --Turn on Anime4K globally, instead of use indicator file
local disableres = 1200 --Ignore, or send user command
local Ares = 800 -- ~ disableres: Mode A
local Bres = 540 -- ~ under A: Mode B
-- Under Bres: Mode C

-- Use namespace "_jbgyampcwu" to avoid possible conflicts
-- Rely on mp.utils functions, they may be removed in future mpv versions
--
-- Class reference: https://www.lua.org/pil/16.1.html



--
-- BEGIN Class
--

-- Define Class: UserInput
-- Override built-in Anime4K command for either early access to new version Anime4K
-- or temporary workaround a discovered bug without waiting for AnimeAnyK to fix it
UserInput_jbgyampcwu = {
    -- Turn on Anime4K globally, instead of use indicator file
    AlwaysOn = alwaysenabled,
    -- Toggle user command mode
    UseUserInputCommand = false,

    -- If you have your own string, paste it here
    --
    -- For complex primary mode (AA or BB or CA, etc)
    -- also paste it here and edit manually for customization.
    UserCommand2160P = "",
    UserCommand1440P = "",
    UserCommand1080P = "",
    UserCommand720P = "",
    UserCommand480P = "",

    -- Optional: Clamp_Highlights
    -- https://github.com/bloc97/Anime4K/blob/master/GLSL_Instructions.md#best-practices
    UseClampHighlights = true
}
local playlisted = false
local auto_applied = false
local k = 0

-- Define Class: PlatformInformation
-- Determine OS type and provide corresponding variable value
PlatformInformation_jbgyampcwu = {
    -- Linux/Unix is ":", Windows is ";".
    -- https://mpv.io/manual/stable/#string-list-and-path-list-options
    --
    -- There is difference between path list separator and
    -- "send multiple command at once" command separator.
    -- Command separator is always ";".
    -- https://mpv.io/manual/stable/#input-conf-syntax
    PathListSeparator = nil
}
function PlatformInformation_jbgyampcwu:new (o, pathListSeparator)
    o = o or {}
    setmetatable(o, self)
    self.__index = self

    local osEnv = os.getenv("OS")
    -- osEnv = ""

    -- Windows 10
    if osEnv == "Windows_NT"
    then
        self.PathListSeparator = pathListSeparator or ";"
    -- All other OS goes here
    else
        self.PathListSeparator = pathListSeparator or ":"
    end

    return o
end

-- Define Class: Core
Core_jbgyampcwu = {
}

-- Get video height as int
function Core_jbgyampcwu.GetVideoHeightInt()
    local videoHeightString = mp.get_property("height")
    local videoHeightInt = tonumber(videoHeightString)

    return videoHeightInt
end

-- Return indicator file exist or not, and indicator file full path
--
-- Return value:
--     bool: indicatorFileExist
--     string: indicatorFileFullPath
function Core_jbgyampcwu.GetIndicatorFileStatus()
    -- Require
    local mpUtils = require 'mp.utils'
    GetShadersInfo()
    -- Const
    local indicatorFileName = "Anime4K_jbgyampcwu.i" -- deprecated old stupid filename
    local indicatorFileName2 = "Anime4K.i"

    -- Get file path
    local fileName = mp.get_property("path")
    local fileParentFolder, _ = mpUtils.split_path(fileName)

    -- Fill parent folder
    local indicatorFileFullPath = mpUtils.join_path(fileParentFolder, indicatorFileName)
    local indicatorFileExist, _ = mpUtils.file_info(indicatorFileFullPath)
    if indicatorFileExist == nil then
         indicatorFileFullPath = mpUtils.join_path(fileParentFolder, indicatorFileName2)
    end
    
    -- When AlwaysOn enabled, assume shader already loaded
    -- Report true on first press (should clear GLSL at this time)
    --
    -- Remove "always on" status at same time
    --     so 2nd and future request could cycle as usual (should be able to add GLSL back)
    if UserInput_jbgyampcwu.AlwaysOn
    then
        UserInput_jbgyampcwu.AlwaysOn = false
        return true, indicatorFileFullPath
    end

    -- Try indicator file exist
    local indicatorFileExist, _ = mpUtils.file_info(indicatorFileFullPath)
    if indicatorFileExist == nil
    then
        return false, indicatorFileFullPath
    else
        local file_object = io.open(indicatorFileFullPath, 'r')
        local s = file_object:read()

        -- Ignore possible close error (happens on read only file system)
        local closeResult, err = pcall(function () file_object:close() end)
        return true, indicatorFileFullPath, s
    end
end

-- Get Anime4K Command
-- Different video resolution leads to different command results
function Core_jbgyampcwu.GetAnime4KCommand(videoHeightInt)
    -- Anime4K profile preset
    -- See "Best Practices" section
    -- https://github.com/bloc97/Anime4K/blob/master/GLSL_Instructions.md
	restoreCnnQuality = "M"
	restoreCnnSoftQuality = "M"
	upscaleCnnX2Quality_2 = "S"
	if quality == "HQ" or quality == "hq" then
		restoreCnnQuality = "VL"
		restoreCnnSoftQuality = "VL"
		upscaleCnnX2Quality_2 = "M"
	end
    local upscaleCnnX2Quality = "M"
    local upscaleDenoiseCnnX2Quality = "M"

    --
    -- BEGIN Const
    --
    local platformInformation = PlatformInformation_jbgyampcwu:new()
    local pathListSeparator = platformInformation.PathListSeparator
    local commandPrefixConst = "no-osd change-list glsl-shaders set "
    local commandShowTextConst = "; show-text "
    local commandShowTextContentConst = "Anime4K: auto-enabled"

    -- Shader path
    local clampHighlightsPath = "~~/shaders/Anime4K_Clamp_Highlights.glsl" .. pathListSeparator
    local restoreCnnPath = "~~/shaders/Anime4K_Restore_CNN_" .. restoreCnnQuality .. ".glsl" .. pathListSeparator
    local restoreCnnSoftPath = "~~/shaders/Anime4K_Restore_CNN_Soft_" .. restoreCnnSoftQuality .. ".glsl" .. pathListSeparator
    local upscaleCnnX2Path = "~~/shaders/Anime4K_Upscale_CNN_x2_" .. upscaleCnnX2Quality .. ".glsl" .. pathListSeparator
    local upscaleCnnX2Path_2 = "~~/shaders/Anime4K_Upscale_CNN_x2_" .. upscaleCnnX2Quality_2 .. ".glsl" .. pathListSeparator
    local upscaleDenoiseCnnX2Path = "~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_" .. upscaleDenoiseCnnX2Quality .. ".glsl" .. pathListSeparator
    local autoDownscalePreX2Path = "~~/shaders/Anime4K_AutoDownscalePre_x2.glsl" .. pathListSeparator
    local autoDownscalePreX4Path = "~~/shaders/Anime4K_AutoDownscalePre_x4.glsl" .. pathListSeparator

    --
    -- END Cosnt
    --

    -- Primary mode combinations
    function getPrimaryModeString()
        -- Mode A
        if videoHeightInt >= Ares
        then
            return restoreCnnPath .. upscaleCnnX2Path .. autoDownscalePreX2Path .. autoDownscalePreX4Path .. upscaleCnnX2Path_2, " A (" .. quality ..")"
        end

        -- Mode B
        if videoHeightInt >= Bres
        then
            return restoreCnnSoftPath .. upscaleCnnX2Path .. autoDownscalePreX2Path .. autoDownscalePreX4Path .. upscaleCnnX2Path_2, " B (" .. quality ..")"
        end

        -- Mode C
        if videoHeightInt < Bres
        then
            return upscaleDenoiseCnnX2Path .. autoDownscalePreX2Path .. autoDownscalePreX4Path .. upscaleCnnX2Path_2, " C (" .. quality ..")"
        end
    end

    -- Get primary mode string
    local primaryModeString, modeName = getPrimaryModeString()

    -- Add ClampHighlights if possible
    if UserInput_jbgyampcwu.UseClampHighlights
    then
        primaryModeString = clampHighlightsPath .. primaryModeString
    end

    -- Remove last semicolon
    primaryModeString = primaryModeString:sub(1, -2)

    -- Combine other parts together
    primaryModeString = commandPrefixConst .. "\"" .. primaryModeString .. "\"" .. commandShowTextConst .. "\"" .. commandShowTextContentConst .. modeName .. "\""

    -- DEBUG
    --print(primaryModeString)
    return primaryModeString
end

-- Send Anime4K command to mpv
function Core_jbgyampcwu.SendAnime4kCommand()
    local videoHeightInt = Core_jbgyampcwu.GetVideoHeightInt()

    -- Prepare final command, will send to mpv
    local finalCommand

    -- Enable different Anime4K combinations by video height
    if UserInput_jbgyampcwu.UseUserInputCommand
    then
        if videoHeightInt >= 2160
        then
            finalCommand = UserInput_jbgyampcwu.UserCommand2160P
            mp.command(finalCommand)

            return
        end

        if videoHeightInt >= 1440
        then
            finalCommand = UserInput_jbgyampcwu.UserCommand1440P
            mp.command(finalCommand)

            return
        end

        if videoHeightInt >= 1080
        then
            finalCommand = UserInput_jbgyampcwu.UserCommand1080P
            mp.command(finalCommand)

            return
        end

        if videoHeightInt >= 720
        then
            finalCommand = UserInput_jbgyampcwu.UserCommand720P
            mp.command(finalCommand)

            return
        end

        if videoHeightInt < 720
        then
            finalCommand = UserInput_jbgyampcwu.UserCommand480P
            mp.command(finalCommand)

            return
        end
    -- If no user command requested, then do nothing on 2160p
    -- Treat <2160p as 1080p(no built-in command) for now
    else
        if videoHeightInt < disableres
        then
            finalCommand = Core_jbgyampcwu.GetAnime4KCommand(videoHeightInt)
            mp.command(finalCommand)
            auto_applied = true
        end
    end

    --
    -- End Analyze video
    --
end

--
-- END Class
--



--
-- BEGIN Event
--

-- Video loaded event
function videoLoadedEvent_jbgyampcwu(event)
    if UserInput_jbgyampcwu.AlwaysOn
    then
        Core_jbgyampcwu.SendAnime4kCommand()
        return
    end   
    if playlisted then
        if k == 0 then
            mp.observe_property("playlist/0/filename", "native", ResetPL)
            mp.observe_property("playlist-count", "native", ResetPL)
        end
        return 
    end

    local indicatorFileExist, _, s = Core_jbgyampcwu.GetIndicatorFileStatus()
    if indicatorFileExist == false
    then
        if indicatorFileExist == false and auto_applied and string.find(mp.get_property("glsl-shaders"), "Anime4K") then mp.command("no-osd change-list glsl-shaders clr \"\"; show-text \"Anime4K shaders disabled\"") end
        auto_applied = false
    else
        if s == "" or s == nil then
            Core_jbgyampcwu.SendAnime4kCommand()
        else
            ApplyShaders(s)
        end
    end
end

-- Toggle on/off event
function inputCommandEvent_jbgyampcwu()
    -- Get indicator file status
    local indicatorFileExist, indicatorFileFullPath = Core_jbgyampcwu.GetIndicatorFileStatus()

    if indicatorFileExist == false
    then
        if string.find(indicatorFileFullPath, "://") then
            mp.osd_message("Can't create indicator file for network videos!\nBut you can save playlist with applied shaders to achieve same auto-enabling behavior")
            return
        end
        local info = GetShadersInfo()
        if info == "" then
            mp.osd_message("First, turn on Anime4K shaders you want to be auto-enabled!")
            return
        end
        -- Create file
        local file_object = io.open(indicatorFileFullPath, 'w')
		if createhidden then
			mp.command("run attrib +h '" .. indicatorFileFullPath .. "'")
		end
        
        file_object:write(info)

        -- Ignore possible close error (happens on read only file system)
        local closeResult, err = pcall(function () file_object:close() end)

        -- Trigger scripted Anime4K
        ApplyShaders(info)
    else
        -- Delete exist file, ignore possible delete error (happens on read only file system)
        local deleteResult, err = pcall(function () os.remove(indicatorFileFullPath) end)

        -- Clear glsl
        mp.command("no-osd change-list glsl-shaders clr ''; show-text \"Auto-Anime4k disabled\"")
    end
end

--
-- END Event
--

function GetShadersInfo()
    local s = ""
    local glsl = mp.get_property("glsl-shaders")
    if glsl == nil then return end
    if string.find(glsl, "Restore_CNN_M.glsl") then s = "1" end
    if string.find(glsl, "Restore_CNN_Soft_M.glsl") then s = "2" end
    if string.find(glsl, "Upscale_Denoise_CNN_x2_M.glsl") then s = "3" end
    if string.find(glsl, "Restore_CNN_S.glsl") and string.find(glsl, "Restore_CNN_M.glsl") then s = "4" end
    if string.find(glsl, "Restore_CNN_Soft_S.glsl") then s = "5" end
    if string.find(glsl, "Restore_CNN_S.glsl") and string.find(glsl, "Upscale_Denoise_CNN_x2_M.glsl") then s = "6" end
    if string.find(glsl, "Restore_CNN_VL.glsl") then s = "7" end
    if string.find(glsl, "Restore_CNN_Soft_VL.glsl") then s = "8" end
    if string.find(glsl, "Upscale_Denoise_CNN_x2_VL.glsl") then s = "9" end
    if string.find(glsl, "Restore_CNN_M.glsl") and string.find(glsl, "Restore_CNN_VL.glsl") then s = "0" end
    if string.find(glsl, "Restore_CNN_Soft_M.glsl") and string.find(glsl, "Restore_CNN_Soft_VL.glsl") then s = "-" end
    if string.find(glsl, "Restore_CNN_M.glsl") and string.find(glsl, "Upscale_Denoise_CNN_x2_VL.glsl") then s = "=" end
    return s
end

function ApplyShaders(s)
    if s == "1" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"; show-text "Anime4K: auto-enabled Mode A (Fast)"') end
    if s == "2" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"; show-text "Anime4K: auto-enabled Mode B (Fast)"') end
    if s == "3" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"; show-text "Anime4K: auto-enabled Mode C (Fast)"') end
    if s == "4" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_Restore_CNN_S.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"; show-text "Anime4K: auto-enabled Mode A+A (Fast)"') end
    if s == "5" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Restore_CNN_Soft_S.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"; show-text "Anime4K: auto-enabled Mode B+B (Fast)"') end
    if s == "6" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Restore_CNN_S.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_S.glsl"; show-text "Anime4K: auto-enabled Mode C+A (Fast)"') end
    if s == "7" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_VL.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: auto-enabled Mode A (HQ)"') end
    if s == "8" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_Soft_VL.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: auto-enabled Mode B (HQ)"') end
    if s == "9" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: auto-enabled Mode C (HQ)"') end
    if s == "0" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_VL.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: auto-enabled Mode A+A (HQ)"') end
    if s == "-" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Restore_CNN_Soft_VL.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_VL.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Restore_CNN_Soft_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: auto-enabled Mode B+B (HQ)"') end
    if s == "=" then mp.command('no-osd change-list glsl-shaders set "~~/shaders/Anime4K_Clamp_Highlights.glsl;~~/shaders/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl;~~/shaders/Anime4K_AutoDownscalePre_x2.glsl;~~/shaders/Anime4K_AutoDownscalePre_x4.glsl;~~/shaders/Anime4K_Restore_CNN_M.glsl;~~/shaders/Anime4K_Upscale_CNN_x2_M.glsl"; show-text "Anime4K: auto-enabled Mode C+A (HQ)"') end
    auto_applied = true
end

function ResetPL()
    k=k+1
    if k <= 2 then return end
    
    playlisted = false
    k = 0
    mp.unobserve_property(ResetPL)
end
function CheckPlaylist()
    local ext = string.match(mp.get_property("path"), "%.([^%.]+)$" )
    if ext == "m3u" or ext == "m3u8" or ext == "pls" then
        local a4k = string.match(mp.get_property("filename/no-ext"), "%[A4K.-%]$")
        if a4k then 
            playlisted = true
            ApplyShaders(string.sub(a4k, 5, 5))
        end
    end
end


mp.register_event("file-loaded", videoLoadedEvent_jbgyampcwu)
mp.register_event("start-file", CheckPlaylist)
mp.register_script_message("toggle-anime4k", inputCommandEvent_jbgyampcwu)
