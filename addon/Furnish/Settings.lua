-- What a player may change about how the core behaves. Nothing else in the addon holds a
-- tunable value; a surface that offers a setting writes it here. The values below are the
-- defaults; what a player changed is kept across sessions in FurnishSettings, which the
-- client restores at load, and only a key declared here is taken from it.

local _, Furnish = ...
-- Every file is handed the addon's table; this one, loaded first, also makes it the addon's
-- one global, for another addon or a /run to reach.
_G.Furnish = Furnish

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
