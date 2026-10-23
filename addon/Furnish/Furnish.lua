-- The door: the core driven by a GUID, for a test from /run.
--
--   /run Furnish.Spawn(guid, 1)                      set 1 of that WMO's own root, on it
--   /run Furnish.Spawn(guid, 1, { from = 817579 })   set 1 of another object's root, by entry
--   /run Furnish.Spawn(Furnish.Selected(), 1)        the selected object's GUID
--   /run Furnish.Abort(true)                         stop the run, delete what it spawned
--
-- The target is a GUID and the source is a root: the target's own by default, the original
-- behind an emptywmo when the target is one, or the root of the gameobject entry `from` names,
-- so a building's sets can go on a recolour of it. An entry becomes a root through the
-- server's own `gobject info`, which prints the display, and the data's display table. A GUID becomes a record by selecting the object, since
-- EpsilonLib keeps no record by id, only the one the server pushes for the selection.
-- Nothing here parses text or draws anything; a command and a window come later and call
-- the same functions.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish

local send
local running

local SELECT_TRIES = 30
local SELECT_INTERVAL = 0.1

local function sender()
	if send then
		return send
	end
	local lib = _G.EpsilonLib
	if not (lib and lib.AddonCommands) then
		return nil, "EpsilonLib is not loaded"
	end
	local ok, registered = pcall(lib.AddonCommands.Register, "Furnish", false)
	if ok and registered then
		send = registered
	else
		send = function(text, callback)
			lib.AddonCommands.Send("Furnish", text, callback, false)
		end
	end
	return send
end

local function say(text)
	print("|cff66ccffFurnish:|r " .. text)
end

--- A function that prints its fault instead of dying in silence. Every boundary a command
-- reply or a timer crosses is wrapped, since AddonCommands swallows an error thrown inside
-- its callback and /run shows one only while script errors are on.
local function guarded(fn)
	return function(...)
		local ok, fault = pcall(fn, ...)
		if not ok then
			say("fault: " .. tostring(fault))
		end
	end
end

--- The selected object's GUID, or nil.
function Furnish.Selected()
	local lib = _G.EpsilonLib
	local object = lib and lib.GameObject and lib.GameObject:GetSelected()
	return object and object.guid
end

--- The model name a record carries, as the data spells it: the file's base name, lower
-- case, without the folder, the extension or the carriage return the client appends.
local function modelName(name)
	name = tostring(name or ""):gsub("[\r\n]", ""):lower()
	name = name:match("([^/\\]+)$") or name
	return (name:gsub("%.wmo$", ""))
end

--- The root a name stands for, through the client's own display table, or nil.
-- @param name a model name, with or without folder and extension
-- @return the file id, or nil and the reason
function Furnish.Find(name)
	local epsilon = _G.C_Epsilon
	if not (epsilon and epsilon.GODI_Search and epsilon.GODI_RetrieveSearch) then
		return nil, "the client has no object search"
	end
	local wanted = modelName(name)
	local seen
	for i = 0, (epsilon.GODI_Search(wanted) or 0) - 1 do
		local row = epsilon.GODI_RetrieveSearch(i)
		if row and modelName(row.name) == wanted then
			seen = row.fileid
			if Furnish.Sets(row.fileid) then
				return row.fileid
			end
		end
	end
	if seen then
		return nil, ("the data has no sets for %s"):format(wanted)
	end
	return nil, ("no object is named %s"):format(wanted)
end

--- The plan's house record from EpsilonLib's object record.
-- The rotation is EpsilonLib's own reading of the record, roll on x, pitch on y, turn on z,
-- with the server's orientation standing in for the turn where the record carries none.
function Furnish.HouseOf(object)
	local rotation = object.transform and object.transform.rotation or {}
	local position = object.transform and object.transform.position or {}
	local turn = rotation.z or 0
	if turn == 0 and object.orientation and object.orientation ~= 0 then
		turn = math.deg(object.orientation)
	end
	return {
		guid = object.guid,
		file = object.fileID,
		name = modelName(object.name),
		empty = modelName(object.name):find("emptywmo_", 1, true) ~= nil,
		x = position.x,
		y = position.y,
		z = position.z,
		roll = rotation.x or 0,
		pitch = rotation.y or 0,
		turn = turn,
		scale = object.scale or 1,
		groupLeader = object.groupLeader or 0,
		canEdit = object.canEdit,
	}
end

--- Select the object and hand its record to the callback once the server has pushed it.
-- @param guid the object's GUID
-- @param callback function(object) or function(nil, reason)
local function resolve(guid, callback)
	local lib = _G.EpsilonLib
	local wanted = tonumber(guid)
	if not wanted then
		return callback(nil, "give the WMO's GUID")
	end
	local selected = lib.GameObject:GetSelected()
	if selected and tonumber(selected.guid) == wanted and not lib.GameObject:IsGroupSelected() then
		return callback(selected)
	end
	local door, why = sender()
	if not door then
		return callback(nil, why)
	end
	door(
		"gobject select " .. wanted,
		guarded(function(success, messages)
			if not success then
				return callback(
					nil,
					"could not select "
						.. wanted
						.. ": "
						.. tostring(messages and messages[1] or "no reply")
				)
			end
			local tries = 0
			local function look()
				local object = lib.GameObject:GetSelected()
				if object and tonumber(object.guid) == wanted then
					return callback(object)
				end
				tries = tries + 1
				if tries >= SELECT_TRIES then
					return callback(nil, "selected " .. wanted .. " but its record never arrived")
				end
				_G.C_Timer.After(SELECT_INTERVAL, guarded(look))
			end
			look()
		end)
	)
end

--- The root a gameobject entry spawns, through the server's own gobject info.
-- @param entry the gameobject template entry
-- @param callback function(file) or function(nil, reason)
function Furnish.RootOf(entry, callback)
	local door, why = sender()
	if not door then
		return callback(nil, why)
	end
	door(
		"gobject info " .. entry,
		guarded(function(success, messages)
			if not success then
				return callback(
					nil,
					("no gameobject %s: %s"):format(
						tostring(entry),
						tostring(messages and messages[1] or "no reply")
					)
				)
			end
			for _, line in ipairs(messages or {}) do
				local display = line:match("DisplayID:%s*|c%x%x%x%x%x%x%x%x(%d+)|r")
					or line:match("DisplayID:%s*(%d+)")
				if display then
					local file = Furnish.FileOf(tonumber(display))
					if file then
						return callback(file)
					end
					return callback(nil, ("the data has no sets for display %s"):format(display))
				end
			end
			callback(nil, ("gobject info %s printed no display"):format(tostring(entry)))
		end)
	)
end

--- The source root for a house: the root of the entry `from` names, the original behind an
-- emptywmo, else the house's own file.
-- @param callback function(file) or function(nil, reason)
local function sourceOf(house, from, callback)
	if from ~= nil then
		local entry = tonumber(from)
		if not entry then
			return callback(nil, "from is a gameobject entry")
		end
		return Furnish.RootOf(entry, callback)
	end
	if house.empty then
		local original = house.name:gsub("^eps_emptywmo_", "eps_"):gsub("^emptywmo_", "")
		return callback(Furnish.Find(original))
	end
	callback(house.file)
end

--- Spawn a set on a WMO.
-- @param guid the target WMO's GUID; Furnish.Selected() gives the selection's
-- @param index the set's position in the source's MODS, as the listing shows it
-- @param options { from = gameobject entry, attach, nopivot, default }, optional
function Furnish.Spawn(guid, index, options)
	guarded(function()
		options = options or {}
		say(
			("set %s of %s on %s"):format(
				tostring(index),
				options.from and ("entry " .. tostring(options.from)) or "its own root",
				tostring(guid)
			)
		)
		if running and not running.Done() then
			say("a run is still going; Furnish.Abort() stops it")
			return
		end
		local lib = _G.EpsilonLib
		if not (lib and lib.GameObject) then
			say("EpsilonLib is not loaded")
			return
		end
		resolve(guid, function(object, reason)
			if not object then
				say(reason)
				return
			end
			if not object:IsWMO() then
				say("that is not a WMO")
				return
			end
			local loaded, unloaded = Furnish.Load()
			if not loaded then
				say(unloaded)
				return
			end
			local house = Furnish.HouseOf(object)
			sourceOf(house, options.from, function(source, missing)
				if not source then
					say(missing)
					return
				end
				Furnish.Start(house, source, index, options)
			end)
		end)
	end)()
end

--- Plan and run one set of a source root on a resolved house.
function Furnish.Start(house, source, index, options)
	guarded(function()
		local plan, refused = Furnish.Plan.Build(house, source, index, options)
		if not plan then
			say(refused)
			return
		end
		local door, why = sender()
		if not door then
			say(why)
			return
		end
		say(
			("spawning set %d%s of root %d, %d objects, %s"):format(
				plan.set.index,
				plan.set.name ~= "" and (" " .. plan.set.name) or "",
				source,
				plan.doodads,
				plan.leader == "house" and "attached to the house"
					or (plan.leader == "pivot" and "with a pivot" or "first object leading")
			)
		)
		local last = 0
		running = Furnish.Run.Start(plan, door, {
			progress = guarded(function(done, total)
				if done == total or done - last >= 10 then
					last = done
					say(("%d of %d"):format(done, total))
				end
			end),
			finished = guarded(function(result)
				local text = ("done: %d spawned"):format(#result.spawned)
				if #result.refused > 0 then
					text = text .. (", %d refused"):format(#result.refused)
					for _, refusal in ipairs(result.refused) do
						say(
							("refused display %s: %s"):format(
								tostring(refusal.display),
								refusal.reason
							)
						)
					end
				end
				if result.leader then
					text = text .. ", leader " .. result.leader
				end
				if result.aborted then
					text = text
						.. ", aborted"
						.. (result.deleted and (", %d deleted"):format(result.deleted) or "")
				end
				say(text)
			end),
		})
	end)()
end

--- Stop the current run. With cleanup, delete what it spawned.
function Furnish.Abort(cleanup)
	if running and not running.Done() then
		running.Abort(cleanup)
	else
		say("nothing is running")
	end
end
