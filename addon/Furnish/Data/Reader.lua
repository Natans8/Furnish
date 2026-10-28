-- The reader over Furnish_Data: the sets a root file offers, the root a gameobject entry
-- spawns, the placements of a set, the sets a map placement draws, and the model file a
-- display draws. A set's placements are decoded the first time they are
-- asked for and kept; nothing is decoded at load.
--
-- This file ships with the code, never with the data. Furnish_Data is the folder players
-- download least often, so it holds nothing that could change without the data changing:
-- one table and a format number. The reader loads it on demand and refuses any other
-- format, so a player on an old data folder is told once rather than fed wrong rows.
--
-- A set blob is LibDeflate's printable encoding of a raw deflate stream: a version byte,
-- a varint row count, a delta-coded varint list of display ids, then per row the model
-- index as a varint, x y z as float32, a flags byte, the quaternion as four float32 under
-- flag 1, and the scale as a float32 under flag 2. Nothing is rounded: the numbers are the
-- WMO file's own. The Python side of this is furnish/codec.py.

local _, Furnish = ...
local FORMAT = 7
--- The sets decoded, by id, kept only while something holds their rows, so a session that looks
-- at many sets does not keep them all.
local decoded = setmetatable({}, { __mode = "v" })

local Reader = {}
Furnish.Reader = Reader
local Data

--- The data addon's name, which the client loads it by.
local DATA = "Furnish_Data"

--- Load Furnish_Data and check its format. Answers true, or false and a reason.
function Reader.Load()
	if Data then
		return true
	end
	local loaded, reason = _G.LoadAddOn(DATA)
	if not loaded then
		return false,
			("%s could not load (%s): install it beside %s and enable it in the addon list"):format(
				DATA,
				tostring(reason):lower(),
				Furnish.NAME
			)
	end
	if type(_G.FurnishData) ~= "table" then
		return false, DATA .. " loaded but declared no data"
	end
	if _G.FurnishData.format ~= FORMAT then
		return false,
			("%s is format %s and this %s reads format %d: update the one that is behind"):format(
				DATA,
				tostring(_G.FurnishData.format),
				Furnish.NAME,
				FORMAT
			)
	end
	Data = _G.FurnishData
	return true
end

local VERSION = 1

local function data()
	if not Data then
		error("Furnish: call Furnish.Reader.Load() before asking for data")
	end
	return Data
end

local function deflate()
	local lib = _G.LibStub and _G.LibStub:GetLibrary("LibDeflate", true)
	if not lib then
		error(DATA .. ": LibDeflate is not loaded")
	end
	return lib
end

local function decodeBlob(text)
	local lib = deflate()
	-- The exporter breaks a long set's string across lines, and the encoding has no line
	-- break in its alphabet, so the breaks go before it is decoded.
	local printable = lib:DecodeForPrint((text:gsub("\n", "")))
	if not printable then
		error(DATA .. ": a set's string does not decode; reinstall " .. DATA)
	end
	local bytes = lib:DecompressDeflate(printable)
	local at = 1

	local function u8()
		local value = bytes:byte(at)
		at = at + 1
		return value
	end

	local function varint()
		local value, shift = 0, 0
		while true do
			local byte = u8()
			value = value + (byte % 128) * 2 ^ shift
			if byte < 128 then
				return value
			end
			shift = shift + 7
		end
	end

	-- A little-endian IEEE 754 single, by arithmetic: Lua 5.1 has no string.unpack.
	local function f32()
		local b1, b2, b3, b4 = bytes:byte(at, at + 3)
		at = at + 4
		local sign = b4 >= 128 and -1 or 1
		local exponent = (b4 % 128) * 2 + math.floor(b3 / 128)
		local mantissa = (b3 % 128) * 65536 + b2 * 256 + b1
		if exponent == 0 then
			return sign * mantissa * 2 ^ -149
		elseif exponent == 255 then
			return mantissa == 0 and sign * math.huge or 0 / 0
		end
		return sign * (1 + mantissa / 8388608) * 2 ^ (exponent - 127)
	end

	if u8() ~= VERSION then
		error(DATA .. ": unknown set blob version")
	end
	local count = varint()
	local models, previous = {}, 0
	for i = 1, varint() do
		previous = previous + varint()
		models[i] = previous
	end
	local rows = {}
	for i = 1, count do
		local row = { display = models[varint() + 1] }
		row.x, row.y, row.z = f32(), f32(), f32()
		local flags = u8()
		if flags % 2 >= 1 then
			row.qx, row.qy, row.qz, row.qw = f32(), f32(), f32(), f32()
		else
			row.qx, row.qy, row.qz, row.qw = 0, 0, 0, 1
		end
		if flags % 4 >= 2 then
			row.scale = f32()
		else
			row.scale = 1
		end
		rows[i] = row
	end
	return rows
end

--- The sets a WMO root offers, or nil when the data has none for it. Load first.
-- @param file the root's file id, as a selected object reports it
-- @return a list of { index, set, name, count }, in index order; the default set's name is ""
function Reader.Sets(file)
	return data().wmo[file]
end

--- Whether a root's own doodads are blanked, every one at scale 0, so it draws none of its
-- sets itself; its sets are the WMO's it was emptied from. Load first.
-- @param file the root's file id
function Reader.IsBlank(file)
	return data().blank[file] == true
end

--- The placements of a set, decoded once and kept.
-- @param set a set id from Sets or MapSets
-- @return a list of { display, x, y, z, qx, qy, qz, qw, scale }, positions in yards
function Reader.Placements(set)
	local rows = decoded[set]
	if rows == nil then
		local blob = data().blobs[set]
		if blob == nil then
			return nil
		end
		rows = decodeBlob(blob)
		decoded[set] = rows
	end
	return rows
end

--- The root file a gameobject entry's object is, or nil: no such object, or one whose root
-- has no sets. Load first.
-- @param entry a gameobject entry, as a lookup line prints it
function Reader.FileOfEntry(entry)
	return data().entries[entry]
end

--- The sets beyond its base a WMO placed on a map draws, or nil when the data has none for
-- it, which it has not for one that draws only its base. Load first.
-- @param map the map id the client reports
-- @param uid the placement's unique id, as .doodad near prints it
-- @return a list of set ids
function Reader.MapSets(map, uid)
	local byMap = data().maps[map]
	return byMap and byMap[uid]
end

--- The model file a display draws, the id a model frame renders and the client's catalogue names,
-- or nil for a display no placement spawns. Load first.
-- @param display a display id, as a placement carries it
function Reader.ModelFile(display)
	return data().models[display]
end

--- Every display a placement spawns and the model file it draws, as one table. Load first.
function Reader.ModelFiles()
	return data().models
end

--- Every root the data has sets for, keyed by its file id, each its sets as Sets gives them.
-- Load first.
function Reader.Roots()
	return data().wmo
end

--- The lowest gameobject entry of each root, gathered the first time one is asked for.
local lowest

--- The lowest gameobject entry whose object is a root, or nil where no entry is. Several
-- entries may draw one root, and any of them reads the same sets. Load first.
-- @param file the root's file id
function Reader.EntryOfFile(file)
	if not lowest then
		lowest = {}
		for entry, root in pairs(data().entries) do
			if not lowest[root] or entry < lowest[root] then
				lowest[root] = entry
			end
		end
	end
	return lowest[file]
end
