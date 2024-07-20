local Element = require('elements/Element')
local loading = false

---@class BufferingIndicator : Element
local BufferingIndicator = class(Element)

function BufferingIndicator:new() return Class.new(self) --[[@as BufferingIndicator]] end
function BufferingIndicator:init()
	Element.init(self, 'buffer_indicator', {ignores_curtain = true, render_order = 2})
	self.enabled = false
	self:decide_enabled()
end

function BufferingIndicator:decide_enabled()
	local cache = false
	loading = false
	if mp.get_property('cache-buffering-state') == nil and mp.get_property("path") and string.find(mp.get_property("path"), "://") then
		self.enabled = false
		loading = true
	else
		if tonumber(state.cache_buffering) then cache = state.cache_underrun or state.cache_buffering and state.cache_buffering < 100 end
	end
	local player = (state.core_idle and not state.eof_reached) and state.cache_buffering
	if self.enabled then
		if not player or (state.pause and not cache) then self.enabled = false end
	elseif (player and cache and state.uncached_ranges) or loading then
		self.enabled = true
	end
end

function BufferingIndicator:on_prop_pause() self:decide_enabled() end
function BufferingIndicator:on_prop_core_idle() self:decide_enabled() end
function BufferingIndicator:on_prop_eof_reached() self:decide_enabled() end
function BufferingIndicator:on_prop_uncached_ranges() self:decide_enabled() end
function BufferingIndicator:on_prop_cache_buffering() self:decide_enabled() end
function BufferingIndicator:on_prop_cache_underrun() self:decide_enabled() end

function BufferingIndicator:render()
	local ass = assdraw.ass_new()
	if not loading then
		ass:rect(0, 0, display.width, display.height, {color = bg, opacity = config.opacity.buffering_indicator})
		size = round(30 + math.min(display.width, display.height) / 10)
	else
		ass:rect(0, 0, display.width, display.height, {color = bg, opacity = 1-(1-config.opacity.buffering_indicator)/2.0})
		size = round(30 + math.min(display.width, display.height) / 8)
	end 
	local opacity = (Elements.menu and Elements.menu:is_alive()) and 0.3 or 0.8
	ass:spinner(display.width / 2, display.height / 2, size, {color = fg, opacity = opacity})
	if loading then ass:append("\n{\\alpha&HFF\\an5\\fscy" .. 330*display.height/(display.height-70)  .. "} 1 \n{\\alpha&H33\\an5\\fscx80\\fscy80}Воспроизведение...") end
	return ass
end

return BufferingIndicator
