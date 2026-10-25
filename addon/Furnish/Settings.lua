-- What a player may change about how the core behaves. Nothing else in the addon holds a
-- tunable value; a surface that offers a setting writes it here. The values below are the
-- defaults; what a player changed is kept across sessions in FurnishSettings, which the
-- client restores at load, and only a key declared here is taken from it.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish

Furnish.Settings = {
	--- The display spawned as a set's invisible leader at the anchor. Chosen by scanning every
	-- gameobject model: of 17,239, six draw nothing, light nothing, emit nothing, sound
	-- nothing and collide with nothing, and the hologram base is the one that reads as a word
	-- in every list. Spawned by display like every doodad. Nil spawns no marker, and the
	-- first doodad leads instead.
	marker = 16031,

	--- How many commands may be out unanswered at once, joins counted, though a spawn and its
	-- join always go together. No spawn waits on the reply to the one before it; this only
	-- bounds how far ahead of the replies a run gets, so a stop lands within a few lines,
	-- since a line already queued cannot be taken back.
	inFlight = 4,

	--- Whether a WMO's doodad, selection and spawn lines in chat carry a [Furnish] button.
	chatButtons = true,
}
