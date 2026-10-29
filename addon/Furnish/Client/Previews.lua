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

--- Show a WMO's preview at the pointer while it rests on what names the WMO: its picture, found
-- by the WMO file's name.
-- @param name the file's name, as the client's catalogue spells it, whole or as a line shows it
-- @return true where something was shown
function Previews.PeekWmo(name)
	return Previews.Peek({ kind = "wmo", id = 0, name = name })
end

--- Take down a preview Peek showed.
function Previews.Unpeek()
	local addon = glimpse()
	if addon and type(addon.Unpeek) == "function" then
		pcall(addon.Unpeek)
	end
end

--- The first Glimpse release whose WMO pictures carry the door read here, `Picture(id, name)`
-- answering a texture path, false for a WMO that draws nothing from outside, or nil.
Previews.PICTURES_SINCE = { 0, 3 }

--- A release's version as numbers, "v0.4" or "0.3.1" read as { 0, 4 } or { 0, 3, 1 }; nil for
-- one with no number, as a copy run from Glimpse's source carries its unstamped token.
local function versionOf(text)
	if type(text) ~= "string" or not text:match("^v?%d") then
		return nil
	end
	local numbers = {}
	for number in text:gmatch("%d+") do
		numbers[#numbers + 1] = tonumber(number)
	end
	return numbers
end

--- Whether a version is the least one given or later, a missing part counting as nought.
local function atLeast(version, least)
	for i = 1, math.max(#version, #least) do
		local mine, theirs = version[i] or 0, least[i] or 0
		if mine ~= theirs then
			return mine > theirs
		end
	end
	return true
end

--- Glimpse's WMO pictures, where a release that carries the door is installed; nil otherwise. A
-- copy whose version is unstamped is read as current, since it is run from Glimpse's source.
local function pictures()
	local addon = _G.Glimpse_WMO
	if not (type(addon) == "table" and type(addon.Picture) == "function") then
		return nil
	end
	local metadata = _G.GetAddOnMetadata
	local version = metadata and versionOf(metadata("Glimpse_WMO", "Version"))
	if version and not atLeast(version, Previews.PICTURES_SINCE) then
		return nil
	end
	return addon
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
