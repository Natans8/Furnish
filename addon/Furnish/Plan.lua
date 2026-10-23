-- Preprocessing: a house, a set and the options become a plan, which is data.
--
-- A plan holds every command the run will send, in order, each with its role, and the
-- counts a window shows before anything is sent. Building one touches no server: it reads
-- the data, checks what can be checked, and does the maths. A plan is also the dry run.
--
-- The house is the target: the object record as the client reports it, reduced to what the
-- maths and the checks need, resolved by whoever calls here.
--   { guid, file, empty, x, y, z, roll, pitch, turn, scale, groupLeader, canEdit }
-- `empty` says the shell is an emptywmo, a hollowed copy that draws no default set of its own. The
-- source is a root file id whose sets are spawned, usually the house's own file, but any
-- root's: a stock original on its emptywmo, or a building's sets on a recolour of it.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Plan = {}
Furnish.Plan = Plan

local Transform = Furnish.Transform

--- The display spawned as a set's invisible leader at the house's origin. A setting, with a
-- default chosen by scanning every gameobject model: of 17,239, six draw nothing, light
-- nothing, emit nothing, sound nothing and collide with nothing, and the hologram base is
-- the one that reads as a word in every list. Spawned by display like every doodad, so no
-- entry is involved, and the record's file tells our pivot from a player's own marker.
Plan.MARKER = 16031

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

--- The placements a set spawns: its own, and the default set's before them on an emptywmo or
-- when asked for, since an emptywmo draws none of the default and any other shell all of it.
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

--- Build the plan for spawning one set of a source root on one house.
-- @param house the target's record, as described at the top of this file
-- @param source the root file id whose sets are spawned
-- @param index the set's position in the source's MODS, as the listing shows it
-- @param options { attach = bool, nopivot = bool, default = bool }, any of them absent
-- @return the plan, or nil and the reason it was refused
function Plan.Build(house, source, index, options)
	options = options or {}
	if house.canEdit == false then
		return nil, "you cannot edit this object"
	end
	local loaded, reason = Furnish.Load()
	if not loaded then
		return nil, reason
	end
	local sets = Furnish.Sets(source)
	if not sets then
		return nil, ("the data has no sets for root %s"):format(tostring(source))
	end
	local chosen = findSet(sets, index)
	if not chosen then
		return nil, ("root %s has no set %d"):format(tostring(source), index)
	end
	local empty = house.empty == true
	if index == DEFAULT and not empty and not options.default then
		return nil, "the shell already draws its default set; say default to spawn it again"
	end
	local leader
	if options.attach then
		leader = "house"
	elseif options.nopivot then
		leader = "first"
	else
		if not Plan.MARKER then
			return nil, "no marker is set for the pivot; say nopivot or attach"
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
		commands[#commands + 1] =
			{ role = "pivot", text = Transform.SpawnCommand(Plan.MARKER, origin) }
	end
	local placements = rows(sets, chosen, empty or options.default)
	for _, row in ipairs(placements) do
		commands[#commands + 1] = {
			role = "doodad",
			display = row.display,
			text = Transform.SpawnCommand(row.display, Transform.Place(pose, row)),
		}
	end

	return {
		house = house,
		source = source,
		set = { index = chosen[1], id = chosen[2], name = chosen[3], count = chosen[4] },
		withDefault = empty or options.default == true,
		leader = leader,
		attach = options.attach == true,
		chainedJoin = Plan.CHAINED_JOIN,
		commands = commands,
		doodads = #placements,
	}
end
