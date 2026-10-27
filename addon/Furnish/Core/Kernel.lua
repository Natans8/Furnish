-- The kernel: spawn a collection of placements at an anchor, grouped. Final values only.
--
-- A set is nothing but a collection of placements, spawned in the order given, so the kernel
-- takes rows and never asks where they came from; a surface unions, subtracts and picks
-- before calling.
-- Likewise the anchor is a position, a rotation and a scale, whatever gave them, and the
-- group is a word or a GUID. The kernel turns each row into a world pose, each pose into a
-- spawn line, adds the joins the group needs, and hands the lines to a run.
--
-- Who leads is decided by the replies, never in advance: of the first two spawns, the first
-- that answers a GUID leads. Under Pivot that is the pivot, and when the pivot is refused
-- the first doodad leads, which is exactly what First does from the start. When both are
-- refused nothing leads, and the rest stand loose.
--
-- A join is glued to its spawn and acts on the selection the spawn leaves, since the server
-- takes no join on a spawn line. Glued, the two leave in the same breath: EpsilonLib answers
-- every join by reselecting the group, and a reselect landing between a spawn and its join
-- would leave the join acting on the leader. A pair waits for the two that may lead and for
-- nothing else, so a spawn never waits on the reply to the one before it.

local _, Furnish = ...

local Transform = Furnish.Transform
local Commands = Furnish.Commands
local Run = Furnish.Run

--- The ways a spawned collection may be grouped. Any value that is not one of these is
-- taken as the GUID of an existing object whose group the collection joins.
Furnish.Group = {
	Pivot = "pivot", -- the pivot Settings names, at the anchor, leads
	First = "first", -- the first doodad spawned leads
	None = "none", -- loose objects, no group
}
local Group = Furnish.Group

local function isWord(group)
	return group == Group.Pivot or group == Group.First or group == Group.None
end

--- A placement at the anchor itself, which is where the pivot stands.
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

--- The GUID that leads: the one given, else the first of these positions to answer one.
local function leaderOf(group, results, positions)
	if not isWord(group) then
		return tostring(group)
	end
	for _, index in ipairs(positions) do
		local result = results[index]
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
--   The outcome carries total, spawned (GUIDs), refused ({ display, pivot, messages }, the
--   pivot's display being the setting as `.gob spawn` takes it), unjoined
--   ({ display, guid, messages }: spawned, but the join was refused), leader, joined (how
--   many objects joined the leader's group), pivot, placed (how many of the rows stood, the
--   pivot left out), aborted and, after a cleanup, deleted; a messages list is the server's
--   reply lines as sent.
-- @return a handle with Abort(cleanup), Done() and total, or nil and the reason
function Furnish.Spawn(rows, position, rotation, scale, group, send, hooks)
	local wrong = check(rows, position, rotation, scale, group, send)
	if wrong then
		return nil, wrong
	end
	local settings = Furnish.Settings
	local marker = group == Group.Pivot and settings.pivot or nil
	local joins = group ~= Group.None

	-- Positions in the series: spawns[i] is the display spawned at i, or the pivot as the
	-- setting names it, joined[i] the spawn a join at i acts for, and leads the spawns that may
	-- lead, the first two under a word.
	local commands, spawns, joined, leads = {}, {}, {}, {}
	local leader
	local function spawn(display, line)
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
		if not joins then
			return nil
		end
		if isWord(group) and #leads < 2 then
			leads[#leads + 1] = index
		end
		-- The first that may lead leads if it stands, so it never joins.
		if index == leads[1] then
			return nil
		end
		local needs = {}
		for _, lead in ipairs(leads) do
			if lead < index then
				needs[#needs + 1] = lead
			end
		end
		joined[index + 1] = index
		commands[index + 1] = {
			glued = true,
			needs = needs,
			text = function(results)
				-- Once one answers, it leads every join after, so its reply is read once.
				leader = leader or leaderOf(group, results, needs)
				if not leader then
					return nil
				end
				return Commands.Join(leader)
			end,
		}
		return nil
	end

	local place = Transform.Placer(position, rotation, scale)
	if marker then
		-- Turned and scaled with the set, so the pivot stays in proportion to what it leads.
		local long = spawn(marker, Commands.SpawnObject(marker, place(ORIGIN)))
		if long then
			return nil, long
		end
	end
	for _, row in ipairs(rows) do
		local long = spawn(row.display, Commands.Spawn(row.display, place(row)))
		if long then
			return nil, long
		end
	end

	local cleanup = false

	local function outcome(ended)
		local results = ended.results
		local spawned, refused, unjoined, members = {}, {}, {}, 0
		for index = 1, #commands do
			local result, display, spawnAt = results[index], spawns[index], joined[index]
			-- A join speaks for its spawn only when that spawn stood; behind a refused one it
			-- acted on the object before, which is in the group already.
			local own = spawnAt and results[spawnAt]
			if result and not result.skipped then
				if display and result.success then
					spawned[#spawned + 1] = Commands.GuidIn(result.messages)
				elseif display then
					refused[#refused + 1] = {
						display = display,
						pivot = marker ~= nil and index == 1,
						messages = result.messages or {},
					}
				elseif own and own.success and result.success then
					members = members + 1
				elseif own and own.success then
					unjoined[#unjoined + 1] = {
						display = spawns[spawnAt],
						guid = Commands.GuidIn(own.messages),
						messages = result.messages or {},
					}
				end
			end
		end
		local first = results[1]
		local pivot = marker and first and first.success and Commands.GuidIn(first.messages) or nil
		return {
			total = #rows,
			spawned = spawned,
			refused = refused,
			unjoined = unjoined,
			leader = joins and leaderOf(group, results, leads) or nil,
			joined = members,
			pivot = pivot,
			placed = #spawned - (pivot and 1 or 0),
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

	-- The run counts joins too; the surface is told in doodads, the pivot left out.
	local progress, settled = hooks and hooks.progress, 0
	local run, reason = Run.Start(commands, send, {
		progress = progress and function(_, _, index)
			if spawns[index] and not (marker and index == 1) then
				settled = settled + 1
				progress(settled, #rows)
			end
		end,
		finished = finished,
	}, settings.inFlight)
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
