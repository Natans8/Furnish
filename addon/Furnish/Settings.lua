-- What a player may change about how the core behaves. Nothing else in the addon holds a
-- tunable value; a surface that offers a setting writes it here.

_G.Furnish = _G.Furnish or {}
local Furnish = _G.Furnish

Furnish.Settings = {
	--- The display spawned as a set's invisible leader at the anchor. Chosen by scanning every
	-- gameobject model: of 17,239, six draw nothing, light nothing, emit nothing, sound
	-- nothing and collide with nothing, and the hologram base is the one that reads as a word
	-- in every list. Spawned by display like every doodad. Nil spawns no marker, and the
	-- first doodad leads instead.
	marker = 16031,

	--- Whether `group add` is chained onto each spawn line, which lets several spawns go out
	-- at once. Off until it is seen to work in game: unchained, each spawn is followed by a
	-- join acting on the selection the spawn left behind, so one object goes at a time.
	chainedJoin = false,
}
