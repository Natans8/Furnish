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

	--- How many spawns go out at once where no join waits on the selection, which is when
	-- they go ungrouped. A grouped set goes one object at a time, each spawn followed by the
	-- join that acts on the selection it left, since the server takes no join on a spawn line.
	inFlight = 4,
}
