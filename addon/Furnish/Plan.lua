-- Preprocessing: a house, a set and the options become a plan, which is data.
--
-- A plan holds every command the run will send, in order, each with its role, and the
-- counts a window shows before anything is sent. Building one touches no server: it reads
-- the data, checks what can be checked, and does the maths. A plan is also the dry run.
--
-- The house is the object record as the client reports it, reduced to what the maths and
-- the checks need; whoever calls here resolves a GUID or a selection into that record.
--   { guid, file, twinOf, x, y, z, roll, pitch, turn, scale, groupLeader, canEdit }
-- `file` is the root's file id and `twinOf` the original's when the file is an emptywmo
-- twin, both resolved by the caller through the client's display table.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Plan = {}
Furnish.Plan = Plan

local Transform = Furnish.Transform

--- The gameobject entry spawned as a set's invisible leader at the house's origin.
-- TODO: the entry Epsilon builders use as a marker; until it is set, a plan that needs a
-- pivot is refused.
Plan.MARKER = nil

--- Whether `gobject group add` may be chained onto a spawn, which lets the spawns go out
-- several at a time. Until it is seen to work in game, each doodad is spawned and then
-- added, one at a time, since the add acts on the selection the spawn left behind.
Plan.CHAINED_JOIN = false

local DEFAULT = 0

local function findSet(sets, index)
	for _, entry in ipairs(sets) do
		if entry[1] == index then
			return entry
		end
	end
	return nil
end

--- The placements a set spawns: its own, and the default set's before them on a twin or
-- when asked for, since a twin draws none of the default and a stock shell all of it.
local function rows(sets, chosen, withDefault)
	local out = {}
	if withDefault and chosen[1] ~= DEFAULT then
		local default = findSet(sets, DEFAULT)
		if default then
			for _, row in ipairs(Furnish.Placements(default[2])) do
				out[#out + 1] = row
			end
		end
	end
	for _, row in ipairs(Furnish.Placements(chosen[2])) do
		out[#out + 1] = row
	end
	return out
end

--- Build the plan for spawning one set on one house.
-- @param house the object record, as described at the top of this file
-- @param index the set's position in the root's MODS, as the listing shows it
-- @param options { attach = bool, nopivot = bool, default = bool }, any of them absent
-- @return the plan, or nil and the reason it was refused
function Plan.Build(house, index, options)
	options = options or {}
	if house.canEdit == false then
		return nil, "you cannot edit this object"
	end
	local loaded, reason = Furnish.Load()
	if not loaded then
		return nil, reason
	end
	local sets = Furnish.Sets(house.twinOf or house.file)
	if not sets then
		return nil, "the data has no sets for this WMO"
	end
	local chosen = findSet(sets, index)
	if not chosen then
		return nil, ("this WMO has no set %d"):format(index)
	end
	local twin = house.twinOf ~= nil
	if index == DEFAULT and not twin and not options.default then
		return nil, "the shell already draws its default set; say default to spawn it again"
	end
	local leader
	if options.attach then
		leader = "house"
	elseif options.nopivot then
		leader = "first"
	else
		if not Plan.MARKER then
			return nil, "no marker entry is set for the pivot; say nopivot or attach"
		end
		leader = "pivot"
	end

	local pose = {
		x = house.x,
		y = house.y,
		z = house.z,
		roll = house.roll,
		pitch = house.pitch,
		turn = house.turn,
		scale = house.scale,
	}
	local commands = {}
	if leader == "pivot" then
		local origin = Transform.Place(
			pose,
			{ x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 }
		)
		origin.scale = 1
		commands[#commands + 1] = {
			role = "pivot",
			text = Transform.SpawnCommand(Plan.MARKER, origin):gsub("spawn %-", "spawn ", 1),
		}
	end
	local placements = rows(sets, chosen, twin or options.default)
	for _, row in ipairs(placements) do
		commands[#commands + 1] = {
			role = "doodad",
			display = row.display,
			text = Transform.SpawnCommand(row.display, Transform.Place(pose, row)),
		}
	end

	return {
		house = house,
		set = { index = chosen[1], id = chosen[2], name = chosen[3], count = chosen[4] },
		withDefault = twin or options.default == true,
		leader = leader,
		attach = options.attach == true,
		chainedJoin = Plan.CHAINED_JOIN,
		commands = commands,
		doodads = #placements,
	}
end
