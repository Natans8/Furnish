-- What a player may change about how the core behaves. Nothing else in the addon holds a
-- tunable value; a surface that offers a setting writes it here. The values below are the
-- defaults; what a player changed is kept across sessions in FurnishSettings, which the
-- client restores at load, and only a key declared here, holding a value Allowed takes, is
-- taken from it.

local _, Furnish = ...
-- Every file is handed the addon's table; this one, loaded first, also makes it the addon's
-- one global, for another addon or a /run to reach.
_G.Furnish = Furnish

--- The addon's name, as the client hands it to every file: what its lines, its window, its
-- panel and its buttons call it, and what it registers with the client by.
Furnish.NAME = ...

Furnish.Settings = {
	--- What a set's invisible leader at the anchor is, as `.gob spawn` takes it: a gameobject
	-- entry, or a display as a negative number. Furnish's own is display 16031, chosen by
	-- scanning every gameobject model: of 17,239, six draw nothing, light nothing, emit
	-- nothing, sound nothing and collide with nothing, and the hologram base is the one that
	-- reads as a word in every list. A set led by its first object instead is the group word
	-- first, never an empty setting.
	pivot = -16031,

	--- How many commands may be out unanswered at once, joins counted, though a spawn and its
	-- join always go together. No spawn waits on the reply to the one before it; this only
	-- bounds how far ahead of the replies a run gets, so a stop lands within a few lines,
	-- since a line already queued cannot be taken back.
	inFlight = 4,

	--- Whether a WMO's doodad, selection and spawn lines in chat carry a [Furnish] button.
	chatButtons = true,
}

--- What a number setting may hold beyond being a number: a whole one, never nought, at
-- least and at most.
Furnish.Bounds = {
	pivot = { whole = true, nonzero = true },
	inFlight = { whole = true, least = 1, most = 16 },
}

--- Whether a value may stand for a setting: of the type its default has and, for a number,
-- within its bounds. The panel takes only what this allows, and so does a restore.
function Furnish.Allowed(key, value)
	if type(value) ~= type(Furnish.Settings[key]) then
		return false
	end
	local bounds = Furnish.Bounds[key]
	if not bounds then
		return true
	end
	return not (bounds.whole and value ~= math.floor(value))
		and not (bounds.nonzero and value == 0)
		and value >= (bounds.least or value)
		and value <= (bounds.most or value)
end
