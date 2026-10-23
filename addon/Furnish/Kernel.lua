-- The kernel: spawn a collection of placements at an anchor, grouped. Final values only.
--
-- A set is nothing but an unordered collection of placements, so the kernel takes rows and
-- never asks where they came from; a surface unions, subtracts and picks before calling.
-- Likewise the anchor is a position, a rotation and a scale, whatever gave them, and the
-- group is a word or a GUID. The kernel turns each row into a world pose, each pose into a
-- spawn line, adds the joins the group needs, and hands the lines to a run.
--
-- Who leads is decided by the replies, never in advance: the first command that answers a
-- GUID leads. Under Pivot that is the marker, and when the marker is refused the first
-- doodad leads, which is exactly what First does from the start.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish

local Transform = Furnish.Transform
local Commands = Furnish.Commands
local Run = Furnish.Run

--- The ways a spawned collection may be grouped. Any value that is not one of these is
-- taken as the GUID of an existing object whose group the collection joins.
Furnish.Group = {
	Pivot = "pivot", -- an invisible marker at the anchor leads
	First = "first", -- the first doodad spawned leads
	None = "none", -- loose objects, no group
}
local Group = Furnish.Group

local function isWord(group)
	return group == Group.Pivot or group == Group.First or group == Group.None
end

--- A placement at the anchor itself, which is where the marker stands.
local ORIGIN = { x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 }

local function check(rows, position, rotation, scale, group, send)
	if type(rows) ~= "table" or #rows == 0 then
		return "nothing to spawn: the rows are empty"
	end
	for i, row in ipairs(rows) do
		if type(row.display) ~= "number" or row.display <= 0 then
			return ("row %d has no display id"):format(i)
		end
	end
	if type(position) ~= "table" or not (position.x and position.y and position.z) then
		return "the anchor position needs x, y and z"
	end
	if rotation ~= nil and type(rotation) ~= "table" then
		return "the anchor rotation is { roll, pitch, turn } in degrees, or nil for level"
	end
	if scale ~= nil and (type(scale) ~= "number" or scale <= 0) then
		return ("the anchor scale must be a positive number, not %s"):format(tostring(scale))
	end
	if not isWord(group) and not tonumber(group) then
		return ("the group must be Furnish.Group.Pivot, First or None, or a leader GUID, not %s"):format(
			tostring(group)
		)
	end
	if type(send) ~= "function" then
		return "send must be the function that delivers a command"
	end
	return nil
end

--- The GUID that leads: the one given, else the first reply that named one.
local function leaderOf(group, results)
	if not isWord(group) then
		return tostring(group)
	end
	for i = 1, #results do
		local result = results[i]
		if result and result.success then
			local guid = Commands.GuidIn(result.messages)
			if guid then
				return guid
			end
		end
	end
	return nil
end

--- Spawn rows at an anchor, grouped as asked.
-- @param rows a list of { display, x, y, z, qx, qy, qz, qw, scale }, relative to the anchor
-- @param position { x, y, z } of the anchor
-- @param rotation { roll, pitch, turn } of the anchor in degrees, or nil for level
-- @param scale the anchor's scale, or nil for 1
-- @param group a Furnish.Group value, or the GUID of the object whose group to join
-- @param send function(text, callback(success, messages)), the door to the server
-- @param hooks { progress = function(done, total), finished = function(outcome) }, optional.
--   The outcome carries total, spawned (GUIDs), refused ({ display, messages }), unjoined
--   ({ display, guid, messages }: spawned, but the join was refused), leader, joined (how
--   many objects besides the leader are in its group), pivot, aborted and, after a cleanup,
--   deleted; a messages list is the server's reply lines as sent.
-- @return a handle with Abort(cleanup), Done() and total, or nil and the reason
function Furnish.Spawn(rows, position, rotation, scale, group, send, hooks)
	local wrong = check(rows, position, rotation, scale, group, send)
	if wrong then
		return nil, wrong
	end
	local settings = Furnish.Settings
	local marker = group == Group.Pivot and settings.marker or nil
	local joins = group ~= Group.None

	-- Positions in the series: spawns[i] is the display spawned at i, joined[i] the spawn
	-- a join at i acts for.
	local commands, spawns, joined = {}, {}, {}
	local function spawn(display, pose)
		local line = Commands.Spawn(display, pose)
		if #line > Commands.LIMIT then
			return ("a spawn line is %d characters, over the %d the server takes: %s"):format(
				#line,
				Commands.LIMIT,
				line
			)
		end
		local index = #commands + 1
		spawns[index] = display
		commands[index] = { text = line }
		-- The join goes as its own command after the spawn, since the server takes no join
		-- on a spawn line, and acts on the selection the spawn left.
		if joins then
			joined[index + 1] = index
			commands[index + 1] = {
				needs = { index },
				text = function(results)
					local own = Commands.GuidIn(results[index].messages)
					local leader = leaderOf(group, results)
					if not own or not leader or leader == own then
						return nil
					end
					return Commands.Join(leader)
				end,
			}
		end
		return nil
	end

	if marker then
		local long = spawn(marker, Transform.Place(position, rotation, 1, ORIGIN))
		if long then
			return nil, long
		end
	end
	for _, row in ipairs(rows) do
		local long = spawn(row.display, Transform.Place(position, rotation, scale, row))
		if long then
			return nil, long
		end
	end

	local cleanup = false

	local function outcome(ended)
		local spawned, refused, unjoined = {}, {}, {}
		for index = 1, #commands do
			local result = ended.results[index]
			local display, spawnAt = spawns[index], joined[index]
			if display and result and result.success then
				spawned[#spawned + 1] = Commands.GuidIn(result.messages)
			elseif display and result and not result.skipped then
				refused[#refused + 1] = { display = display, messages = result.messages or {} }
			elseif spawnAt and result and not result.skipped and not result.success then
				unjoined[#unjoined + 1] = {
					display = spawns[spawnAt],
					guid = Commands.GuidIn(ended.results[spawnAt].messages),
					messages = result.messages or {},
				}
			end
		end
		local first = ended.results[1]
		local leader = joins and leaderOf(group, ended.results) or nil
		local members = 0
		for _, guid in ipairs(spawned) do
			if tostring(guid) ~= tostring(leader) then
				members = members + 1
			end
		end
		return {
			total = #rows,
			spawned = spawned,
			refused = refused,
			unjoined = unjoined,
			leader = leader,
			joined = leader and members - #unjoined or 0,
			pivot = marker and first and first.success and Commands.GuidIn(first.messages) or nil,
			aborted = ended.aborted,
		}
	end

	local function finished(ended)
		local result = outcome(ended)
		local pending = #result.spawned
		if not cleanup or pending == 0 then
			if hooks and hooks.finished then
				hooks.finished(result)
			end
			return
		end
		result.deleted = 0
		for _, guid in ipairs(result.spawned) do
			send(Commands.Delete(guid), function(success)
				pending = pending - 1
				if success then
					result.deleted = result.deleted + 1
				end
				if pending == 0 and hooks and hooks.finished then
					hooks.finished(result)
				end
			end)
		end
	end

	-- The run counts joins too; the surface is told in doodads, the marker left out.
	local progress, settled = hooks and hooks.progress, 0
	local run, reason = Run.Start(commands, send, {
		progress = progress and function(_, _, index)
			if spawns[index] and not (marker and index == 1) then
				settled = settled + 1
				progress(settled, #rows)
			end
		end,
		finished = finished,
	}, joins and 1 or settings.inFlight)
	if not run then
		return nil, reason
	end

	local handle = { total = #rows }

	--- Stop sending. With cleanup, delete what was spawned once the commands in flight have
	-- answered; the outcome then carries `deleted`. A cleanup once asked for stays asked
	-- for, so a second abort that gives up on a reply still deletes.
	function handle.Abort(withCleanup)
		cleanup = cleanup or withCleanup == true
		run.Abort()
	end

	function handle.Done()
		return run.Done()
	end

	return handle
end
