-- What Glimpse shows for Furnish. A preview of a WMO at the pointer is handed over as data through
-- Glimpse's preview door where the Glimpse installed has one. A WMO's picture is read from
-- Glimpse's WMO pictures, for the window to draw. With neither installed nothing is shown and
-- every call answers so.
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

--- Glimpse's WMO pictures, where they are installed with the door that finds one; nil otherwise.
local function pictures()
	local addon = _G.Glimpse_WMO
	if type(addon) == "table" and type(addon.Picture) == "function" then
		return addon
	end
	return nil
end

--- Whether Glimpse's WMO pictures are installed, so a WMO's picture may be asked for.
function Previews.Pictured()
	return pictures() ~= nil
end

--- A WMO's picture, as Glimpse's WMO pictures have it: found by its gob entry where they know the
-- entry, and otherwise by its name.
-- @param entry a gob entry, or nil
-- @param name the WMO's file name, as Client.ModelName gives it, or nil
-- @return the picture's texture path; nil where the pictures are not installed, have none of the
--   WMO, or have it as drawing nothing from outside
function Previews.Picture(entry, name)
	local addon = pictures()
	if not addon then
		return nil
	end
	local ok, path = pcall(addon.Picture, entry, name)
	if ok and type(path) == "string" then
		return path
	end
	return nil
end
