-- Previews Glimpse draws for Furnish: a WMO's picture and the models a set holds, handed over as
-- data through Glimpse's preview door where the Glimpse installed has one. Furnish draws none of
-- its own, and with no such door nothing is shown and every call answers so.
--
-- Glimpse is another addon, so a fault inside its door is its own: each call is made protected,
-- and a fault answers that nothing was shown.

local _, Furnish = ...
local Previews = {}
Furnish.Previews = Previews

--- Glimpse, where the one installed has a preview door; nil where it has none or is not there.
local function glimpse()
	local addon = _G.Glimpse
	if type(addon) == "table" and type(addon.Peek) == "function" then
		return addon
	end
	return nil
end

--- Show a preview at the pointer while it rests on what is named, as Glimpse shows one for a chat
-- button: on entering, with Unpeek on leaving.
-- @param read what to preview, as Console's previews give it; nil shows nothing
-- @return true where something was shown
function Previews.Peek(read)
	local addon = glimpse()
	if not (addon and read) then
		return false
	end
	local ok, shown = pcall(addon.Peek, read)
	return ok and shown == true
end

--- Take down a preview Peek showed.
function Previews.Unpeek()
	local addon = glimpse()
	if addon and type(addon.Unpeek) == "function" then
		pcall(addon.Unpeek)
	end
end
