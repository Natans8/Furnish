-- The reader over Furnish_Data: the sets a display id offers, the placements of a set, and
-- the sets a map placement draws. A set's placements are decoded the first time they are
-- asked for and kept; nothing is decoded at load.
--
-- This file ships with the code, never with the data. Furnish_Data is the folder players
-- download least often, so it holds nothing that could change without the data changing:
-- one table and a format number. The reader loads it on demand and refuses any other
-- format, so a player on an old data folder is told once rather than fed wrong rows.
--
-- A set blob is LibDeflate's printable encoding of a raw deflate stream over varints:
-- version, row count, a delta-coded list of display ids, then per row the model index,
-- x y z in centimetres, a flags byte, a quaternion in ten-thousandths under flag 1, and a
-- scale in thousandths under flag 2. The Python side of this is furnish/codec.py.

local FORMAT = 1
local decoded = {}

Furnish = Furnish or {}
local Reader = Furnish
local Data

--- Load Furnish_Data and check its format. Answers true, or false and a reason.
function Reader.Load()
  if Data then
    return true
  end
  local loaded, reason = LoadAddOn("Furnish_Data")
  if not loaded then
    return false, "Furnish_Data is " .. tostring(reason):lower()
  end
  if type(FurnishData) ~= "table" then
    return false, "Furnish_Data loaded but declared no data"
  end
  if FurnishData.format ~= FORMAT then
    return false, ("Furnish_Data is format %s; this Furnish reads format %d"):format(tostring(FurnishData.format), FORMAT)
  end
  Data = FurnishData
  return true
end

local VERSION = 1
local POSITION_UNIT, ROTATION_UNIT, SCALE_UNIT = 100, 10000, 1000
local FLAG_ROTATION, FLAG_SCALE = 1, 2

local function deflate()
  local lib = LibStub and LibStub:GetLibrary("LibDeflate", true)
  if not lib then
    error("Furnish_Data: LibDeflate is not loaded")
  end
  return lib
end

local function decodeBlob(text)
  local lib = deflate()
  local bytes = lib:DecompressDeflate(lib:DecodeForPrint(text))
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

  local function zigzag()
    local value = varint()
    if value % 2 == 0 then
      return value / 2
    end
    return -(value + 1) / 2
  end

  if u8() ~= VERSION then
    error("Furnish_Data: unknown set blob version")
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
    row.x, row.y, row.z = zigzag() / POSITION_UNIT, zigzag() / POSITION_UNIT, zigzag() / POSITION_UNIT
    local flags = u8()
    if flags % 2 >= 1 then
      row.qx, row.qy, row.qz, row.qw =
        zigzag() / ROTATION_UNIT, zigzag() / ROTATION_UNIT, zigzag() / ROTATION_UNIT, zigzag() / ROTATION_UNIT
    else
      row.qx, row.qy, row.qz, row.qw = 0, 0, 0, 1
    end
    if flags % 4 >= 2 then
      row.scale = varint() / SCALE_UNIT
    else
      row.scale = 1
    end
    rows[i] = row
  end
  return rows
end

--- The sets a spawned WMO offers, or nil when the data has none for it.
-- @param display the gameobject display id of the WMO
-- @return a list of { index, set, name, count }, in index order; the default set's name is ""
function Reader.Sets(display)
  return Data and Data.wmo[display]
end

--- The placements of a set, decoded once and kept.
-- @param set a set id from Sets or MapSets
-- @return a list of { display, x, y, z, qx, qy, qz, qw, scale }, positions in yards
function Reader.Placements(set)
  local rows = decoded[set]
  if rows == nil then
    local blob = Data and Data.blobs[set]
    if blob == nil then
      return nil
    end
    rows = decodeBlob(blob)
    decoded[set] = rows
  end
  return rows
end

--- The sets a WMO placed on a map draws, or nil when the data has none for it.
-- @param map the map id the client reports
-- @param uid the placement's unique id, as .doodad near prints it
-- @return a list of set ids
function Reader.MapSets(map, uid)
  local byMap = Data and Data.maps[map]
  return byMap and byMap[uid]
end
