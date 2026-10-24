-- The client adapter: the one file that names EpsilonLib and C_Epsilon.
--
-- Everything above reaches the game through these few functions, so the rest of the addon
-- runs in a plain Lua with this file's globals stood in. Nothing here decides anything about
-- furnishing; it only sends, reads and reshapes.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish
local Client = {}
Furnish.Client = Client

local send

local reported = {}

--- Report a fault: in chat, once for each, since a client with its Lua errors switched off
-- shows nothing at all; and to the client's own error handler, so BugSack and the error
-- frame keep it the way they keep any addon's.
function Client.Fault(message)
	local text = tostring(message)
	if not reported[text] then
		reported[text] = true
		print("|cff66ccffFurnish:|r |cffff2020stopped by an error: " .. text .. "|r")
	end
	local handler = _G.geterrorhandler and _G.geterrorhandler()
	if handler then
		handler(message)
	end
	return message
end

--- A function whose fault is reported rather than dying in silence. Every door the client
-- opens is wrapped, the command, a click, a hover and a chat filter, and so is every reply
-- and timer callback, since AddonCommands swallows an error thrown inside one.
function Client.Guarded(fn)
	if fn == nil then
		return nil
	end
	return function(...)
		local count, arguments = select("#", ...), { ... }
		return select(
			2,
			xpcall(function()
				return fn(unpack(arguments, 1, count))
			end, Client.Fault)
		)
	end
end

--- The door to the server: function(text, callback(success, messages), shown), registered
-- once. The server's reply is kept from chat, refusals too, since every caller reports
-- what it asked for in its own words; shown true lets the player see it as if they had
-- typed the command. The callback is optional and guarded, so a fault in it is reported
-- rather than swallowed.
-- @return the function, or nil and the reason
function Client.Send()
	if send then
		return send
	end
	local lib = _G.EpsilonLib
	if not (lib and lib.AddonCommands) then
		return nil, "EpsilonLib is not loaded, and Furnish sends every command through it"
	end
	local ok, registered = pcall(lib.AddonCommands.Register, "Furnish", false)
	local raw
	if ok and registered then
		raw = registered
	else
		raw = function(text, callback, shown)
			lib.AddonCommands.Send("Furnish", text, callback, shown)
		end
	end
	send = function(text, callback, shown)
		raw(text, Client.Guarded(callback), shown or nil)
	end
	return send
end

--- Whether the player may spawn objects in this phase, its members, officers and owner. A
-- refusal is said in chat in Epsilon's own words, as its other tools say it, unless quiet.
-- Where EpsilonLib cannot answer, the server is left to decide.
function Client.CanSpawn(quiet)
	local lib = _G.EpsilonLib
	local check = lib and lib.GameObject and lib.GameObject.CanSpawn
	if not check then
		return true
	end
	-- Any true answer is permission, as EpsilonLib reads it: Epsilon's calls may answer 1.
	return check(not quiet) and true or false
end

--- Whether the player may change an object, and so group with it: a phase's officers and
-- owner may change anything, a member what the object's record says they may.
-- @param pose an object's pose, as Pose.OfRecord gives it
function Client.CanEdit(pose)
	local epsilon = _G.C_Epsilon
	if not (epsilon and epsilon.IsOfficer) then
		return true
	end
	return epsilon.IsOfficer()
		or epsilon.IsOwner()
		or (epsilon.IsMember() and pose.canEdit)
		or false
end

--- The selected object's record, or nil; false for a group selection.
function Client.Selected()
	local lib = _G.EpsilonLib
	if not (lib and lib.GameObject) then
		return nil
	end
	if lib.GameObject:IsGroupSelected() then
		return false
	end
	return lib.GameObject:GetSelected()
end

--- Call fn whenever EpsilonLib fires an event, until the function returned is called; or nil
-- and the reason.
local function listen(event, fn)
	local lib = _G.EpsilonLib
	local events = lib and lib.EventManager
	if not events then
		return nil, "EpsilonLib is not loaded, and Furnish reads every object through it"
	end
	local _, reference = events:Register(
		event,
		Client.Guarded(function()
			fn()
		end)
	)
	return function()
		if reference then
			events:Remove(reference, event)
			reference = nil
		end
	end
end

--- Call fn whenever EpsilonLib says the selection changed, until the function returned is
-- called; or nil and the reason.
function Client.OnSelection(fn)
	return listen("EPSILON_OBJ_UPDATE", fn)
end

--- Call fn whenever the player enters another phase, until the function returned is called;
-- or nil and the reason.
function Client.OnPhaseChange(fn)
	return listen("EPSILON_PHASE_CHANGE", fn)
end

--- The GUID of the selected group's leader, or nil when no group is selected.
function Client.SelectedGroup()
	local lib = _G.EpsilonLib
	if not (lib and lib.GameObject and lib.GameObject:IsGroupSelected()) then
		return nil
	end
	local group = lib.GameObject:GetSelected()
	if not (group and group.leaderGUID) then
		return nil
	end
	return tostring(group.leaderGUID)
end

--- Call fn with an object's record once EpsilonLib holds it, which is once the server has
-- pushed it for the selection. A record already selected is handed over at once.
-- @param guid the object's GUID
-- @param fn function(record), called once
-- @return a function that stops waiting; or nil and the reason
function Client.AwaitRecord(guid, fn)
	local lib = _G.EpsilonLib
	local events = lib and lib.EventManager
	if not events then
		return nil, "EpsilonLib is not loaded, and Furnish reads every object through it"
	end
	local wanted, reference = tostring(guid), nil
	local function stop()
		if reference then
			events:Remove(reference, "EPSILON_OBJ_UPDATE")
			reference = nil
		end
	end
	local function offer(record)
		if reference and record and tostring(record.guid) == wanted then
			stop()
			fn(record)
		end
	end
	-- EpsilonLib calls a listener as listener(nil, event, ...), its own frame withheld.
	local _
	_, reference = events:Register(
		"EPSILON_OBJ_UPDATE",
		Client.Guarded(function(_, _, _, record)
			offer(record)
		end)
	)
	offer(Client.Selected() or nil)
	return stop
end

local systemFrame
local systemListeners = {}

--- Hear every system line the server prints: fn(line) for each, until the function returned
-- is called. An import waiting for its line and a window watching for a selected doodad may
-- both be listening.
function Client.OnSystemLine(fn)
	if not systemFrame then
		systemFrame = _G.CreateFrame("Frame")
		systemFrame:RegisterEvent("CHAT_MSG_SYSTEM")
		systemFrame:SetScript(
			"OnEvent",
			Client.Guarded(function(_, _, line)
				-- A copy, since a listener may stop hearing from inside its own call.
				local listening = { unpack(systemListeners) }
				for _, listener in ipairs(listening) do
					listener(line)
				end
			end)
		)
	end
	systemListeners[#systemListeners + 1] = fn
	return function()
		for i, listener in ipairs(systemListeners) do
			if listener == fn then
				table.remove(systemListeners, i)
				return
			end
		end
	end
end

--- Restore the saved copy of a settings table over its defaults, then make the live table
-- the saved one, so the client writes whatever a surface changes at logout. A saved value
-- is taken only for a key the defaults declare and only when its type agrees, so a stale
-- or hand-edited file cannot put a string where a number goes.
-- @param settings the defaults, which become the live values
-- @param name the saved variable's global name, as the toc declares it
function Client.Restore(settings, name)
	local saved = _G[name]
	if type(saved) == "table" then
		for key, default in pairs(settings) do
			local value = saved[key]
			if type(value) == type(default) then
				settings[key] = value
			end
		end
	end
	_G[name] = settings
end

--- Call fn once this addon has loaded, which is when its saved variables are readable.
function Client.OnLoaded(fn)
	local frame = _G.CreateFrame("Frame")
	frame:RegisterEvent("ADDON_LOADED")
	frame:SetScript("OnEvent", function(_, _, addon)
		if addon == "Furnish" then
			frame:UnregisterEvent("ADDON_LOADED")
			Client.Guarded(fn)()
		end
	end)
end

Client.OnLoaded(function()
	Client.Restore(Furnish.Settings, "FurnishSettings")
end)

--- The player's position as the server places by, and the map: x, y, z, map. Blizzard's
-- UnitPosition answers nothing useful on a phase, which is an instanced map.
function Client.Position()
	return _G.C_Epsilon.GetPosition()
end

--- The client's clock, in seconds.
function Client.Now()
	return _G.GetTime()
end

--- The player's facing in degrees, 0 north and growing toward west, as a spawn's turn.
function Client.Facing()
	return math.deg(_G.GetPlayerFacing() or 0)
end

--- The model name a record carries, as the data spells it: the file's base name, lower
-- case, without the folder, a leading tag in brackets, the extension or the carriage return
-- the client appends.
function Client.ModelName(name)
	name = tostring(name or ""):gsub("[\r\n]", ""):lower()
	name = name:match("([^/\\]+)$") or name
	name = name:gsub("^%[.-%]%s*", "")
	return (name:gsub("%.wmo$", ""):gsub("%.m2$", ""))
end

--- How many rows of the client's display catalogue a walk reads in one frame.
local WALK = 4000

--- The client's catalogue of gameobject displays, or nil where this client has none.
local function catalogue()
	local epsilon = _G.C_Epsilon
	if epsilon and epsilon.GODI_Get and epsilon.GODI_Count and epsilon.GODI_Search then
		return epsilon
	end
	return nil
end

--- The rows of the client's display catalogue whose names hold some words.
-- @return a list of { display, file, name }, the name as the client holds it
function Client.SearchDisplays(words)
	local epsilon = catalogue()
	if not epsilon then
		return {}
	end
	local found = {}
	for i = 0, (epsilon.GODI_Search(words) or 0) - 1 do
		local row = epsilon.GODI_RetrieveSearch(i)
		if row then
			found[#found + 1] = { display = row.displayid, file = row.fileid, name = row.name }
		end
	end
	return found
end

--- What each display draws, as far as it is known: a model's name, or false once a walk of the
-- whole catalogue has missed the display.
local drawn = {}

--- The model a gameobject display draws, by the client's own catalogue, or nil while unknown.
-- The catalogue is searched by halves first, which finds it at once where the catalogue is in
-- display order; a display that search misses is left to Client.WalkDisplays.
function Client.DisplayModel(display)
	if drawn[display] ~= nil then
		return drawn[display] or nil
	end
	local epsilon = catalogue()
	if not epsilon then
		return nil
	end
	local low, high = 0, epsilon.GODI_Count() - 1
	while low <= high do
		local middle = math.floor((low + high) / 2)
		local row = epsilon.GODI_Get(middle)
		local id = row and row.displayid
		if not id then
			return nil
		elseif id == display then
			drawn[display] = row.name
			return row.name
		elseif id < display then
			low = middle + 1
		else
			high = middle - 1
		end
	end
	return nil
end

--- The displays a walk is out looking for, so a second ask does not start a second walk.
local sought = {}

--- Read the whole catalogue a few thousand rows a frame, learning what every display asked for
-- draws, then call done. A display the walk does not meet draws nothing the catalogue knows.
function Client.WalkDisplays(displays, done)
	local epsilon = catalogue()
	local missing, any = {}, false
	for _, display in ipairs(displays) do
		if drawn[display] == nil and not sought[display] then
			missing[display], sought[display], any = true, true, true
		end
	end
	if not (epsilon and any) then
		return
	end
	local at, count = 0, epsilon.GODI_Count()
	local function step()
		local stop = math.min(at + WALK, count) - 1
		for i = at, stop do
			local row = epsilon.GODI_Get(i)
			if row and missing[row.displayid] then
				drawn[row.displayid], missing[row.displayid] = row.name, nil
				sought[row.displayid] = nil
			end
		end
		at = stop + 1
		if at < count and next(missing) then
			return _G.C_Timer.After(0, Client.Guarded(step))
		end
		for display in pairs(missing) do
			drawn[display], sought[display] = false, nil
		end
		done()
	end
	step()
end
