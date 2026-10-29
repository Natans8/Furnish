# Furnish

Spawn a WMO's doodad sets as gameobjects on Epsilon: the chairs, tables, shelves and lamps a WMO
was furnished with, placed where the game placed them, on a WMO you spawned or anywhere you like.

Epsilon spawns a WMO with its default set only. Furnish reads every set from the game's files and
spawns its pieces one gob at a time, grouped so you can move the whole furnishing as one.

## Install

1. Download `Furnish-<version>.zip` from the [releases](https://github.com/Natans8/Furnish/releases).
2. Unzip it into `World of Warcraft/_retail_/Interface/AddOns`, so `Furnish` and `Furnish_Data` sit
   side by side there.

Furnish needs EpsilonLib, which Epsilon ships. Optionally, with `Glimpse_WMO` installed, the
window shows a picture of the WMO you are furnishing. `Glimpse_WMO` is the WMO pictures download
of [Glimpse](https://github.com/Natans8/Glimpse), v0.3 or later, and needs Glimpse itself beside it.

## Quick start

1. Spawn or select a WMO gob.
2. Type `/furn` to open the window. The selected WMO is the source, its sets are listed.
3. Click a set to choose it and see it in the preview.
4. Press **Spawn**. The set is spawned onto the selected WMO, grouped, and the group is selected
   so `.gob group` commands act on it next.

Turn highlighting off before spawning a big set: highlighting many objects can crash the game.
Furnish reminds you once a session and leaves the choice to you.

## The window

**Source**: the WMO the sets come from.
- Follows the selected gob, or untick *Auto Update* to keep it.
- Type a gob entry into its ID box, or search a WMO by name.
- A set the WMO already shows as part of its model is marked *baked*.
- Click a set to choose it; ctrl- or shift-click to add or remove one.

**Destination**: where the sets go, as numbers.
- X, Y, Z, roll, pitch, turn and scale, in ObjectMover's colours.
- Follows the selected gob, or untick *Auto Update* to keep what you typed.
- *Here* fills in where you stand; *Use selected gob* fills them in once.

**Group leader**: what leads the spawned objects' group.
- *Pivot* (the default): one extra invisible object at the destination.
- *First spawned*: the first object leads, nothing extra spawns.
- *Selected gob*: the selected gob leads, or its group is joined; Spawn asks before joining a
  group that exists, the selected gob's or a selected group.
- *No group*: every object stands alone.

**Spawning**
- *Spawn* starts the run; the bar shows its progress.
- *Stop* ends it; *Stop and delete* also removes what it spawned.
- A whole run onto a WMO offers a blueprint name at the bottom right. *Paste to chat* puts the
  `.gobject blueprint new` command in your chat box for you to send.

**Doodad panel**: after `.doodad select`, the selected doodad shows beside the window.
- *Use as source* takes that WMO and the sets it shows.
- *Import doodad* turns it into a gob and spawns its sets onto it.

## The preview

Click a set and the preview opens beside the window, laying out its pieces.

| mouse           | does                                       |
|-----------------|--------------------------------------------|
| drag            | turn the view                              |
| wheel           | zoom toward the pointer                    |
| right-drag      | pan                                        |
| click           | choose a piece                             |
| shift-click     | add a piece, or let it go                  |
| ctrl-click      | make a piece lead                          |
| shift-drag      | add every piece in a band                  |
| ctrl-drag       | let go of every piece in a band            |
| right-click     | spawn that piece alone                     |
| ctrl+A          | choose every piece                         |

The pointed piece glows yellow, chosen pieces azure, the leader green. The leader is the piece
standing lowest, the widest among those level, unless you ctrl-clicked another. **Spawn** spawns
the chosen pieces at Destination; right-click **Spawn** to put the leader at your feet instead.
The **i** at the end of the control bar lists these clicks.

## Chat

- `[Furnish]` after a doodad line (`.doodad select`, `.doodad near`) imports and furnishes it.
- `[Furnish]` after a WMO gob's select or spawn line lists its sets as buttons. Click a set to
  spawn it on the selected gob, ctrl-click to spawn it at your feet.
- Right-click any `[Furnish]` button to open the window on it instead.

## Commands

`/furn` or `/furnish`. `/furn help` lists them in game.

| command                      | does                                                  |
|------------------------------|-------------------------------------------------------|
| `/furn`                      | open the window                                       |
| `/furn list [<entry>]`       | list the selected WMO's sets, or an entry's WMO's     |
| `/furn <set>`                | spawn a set onto the selected WMO                     |
| `/furn <set> from <entry>`   | spawn a set of the entry's WMO onto the selected gob  |
| `/furn <set> here [<entry>]` | spawn a set at your feet                              |
| `/furn import`               | import the selected doodad and spawn its sets onto it |
| `/furn stop [delete]`        | stop a run, and with `delete` remove what it spawned  |
| `/furn options`              | open the settings                                     |

After a set, list or import:

| word      | does                                                   |
|-----------|--------------------------------------------------------|
| `first`   | the first object leads the group; no pivot             |
| `merge`   | join the selected gob's group; no pivot                |
| `nogroup` | spawn every object ungrouped                           |
| `base`    | spawn the base set too                                 |
| `quiet`   | leave the progress counts out of chat                  |

## Settings

In the game's Options under AddOns, or `/furn options`: whether chat lines carry `[Furnish]`
buttons, how many commands a run sends ahead of the server's replies, and what a pivot spawns as.

# For developers

The rest of this file is for making the data and working on the addon. A WMO root file names its
doodad sets (`MODS`) and every placement each holds (`MODD`, `MODI`); the build reads the root
files, resolves every model to the gameobject display that spawns it, and writes one SQLite file,
which `furnish export` turns into the addon's data.

## Build

```bash
uv run furnish build --roots <dir of .wmo files> --maps <dir of .adt files> --out furnish.sqlite
```

The directories hold the files at their listfile paths (`world/wmo/...`), as any CASC
extractor writes them; a root may also be named by its file id, `849966.wmo`. `--maps` is
optional and fills `map_sets`. `--objects` is a CSV of the server's WMO gameobjects, `entry`
and `name`, and fills `entries`; the vendored `src/furnish/data/epsilon-objects.csv` is the
default, read off the server's own list in game, since no file or client call carries
Epsilon's entries. `--listfile-extra <file>` adds a listfile the community one
lacks, a private client's own names, plain or gzipped, and may be repeated. The build fetches the community listfile and wago.tools'
`GameObjectDisplayInfo` and `Map` exports for the build given (`--build`, default Epsilon's
`9.2.7.45745`) into `--cache`, once.

## Tables

| table         | row                                                           |
|---------------|---------------------------------------------------------------|
| `meta`        | `format`, `build`                                             |
| `sets`        | a doodad set and its name, NULL for the default set           |
| `wmo_sets`    | a root file id, a set index, its set                          |
| `blank_roots` | a root Epsilon emptied, which draws none of its sets itself   |
| `entries`     | a gameobject entry and the furnished root it spawns           |
| `placements`  | a set's doodad in order: display, position, quaternion, scale |
| `map_sets`    | a map id and ADT unique id, and a set it draws                |
| `models`      | a display a placement spawns, and the model file it draws     |

Epsilon empties a WMO by copying its root with every doodad at scale 0, an emptywmo
twin's also sunk below the ground. Such a root ships none of its own rows: its `wmo_sets`
are those of the root that places every doodad at the same x, y and rotation, when every
root that does holds the same sets, and it has none otherwise.

Floats are the file's own. Rotation is the file's quaternion, converted to the game's
pitch, roll and turn by the consumer. Set 0 is kept, since a blanked copy of a root draws
none of it; it is the default set by position, so its name is not stored. Placements whose model slot is blank, or whose
model no display spawns, are dropped at build; a set left empty, and a root left with no
set, get no rows. Two roots holding the same set, name and placements alike, share one
row of `sets`.

`src/furnish/data/epsilon-displays.csv` carries Epsilon's own display rows, every row of the
client's `GameObjectDisplayInfo` at or above 100000, because wago.tools cannot see them and
the server refuses a Blizzard display wherever Epsilon has made its own row for the file.

## The addon data

```bash
uv run furnish export --db furnish.sqlite --out addon/Furnish_Data/Data.lua
```

`addon/Furnish_Data` is the data addon: `Data.lua`, generated and not committed, declaring
`FurnishData` with a `format` number, the `build`, each root file's sets (`wmo`), the root
each gameobject entry spawns (`entries`), the roots Epsilon emptied (`blank`), each
set's placements as one printable string
(`blobs`), the sets beyond its base each map placement draws, with none kept for one that draws
only its base (`maps`) and the model each spawned display draws
(`models`), by its file id, which a model frame renders and the client's own catalogue names. A root is keyed by its file id,
which is what a selected object's record reports; an entry, the number a lookup line
prints, reaches it through `entries`.
It loads on demand and holds nothing else, so it changes only when the data does.

`addon/Furnish/Data/Reader.lua` is the reader and ships with the code, never with the data:
`Furnish.Reader.Load()` loads the data addon and refuses another format, and `Sets(file)`,
`Placements(set)`, `IsBlank(file)`, `FileOfEntry(entry)`, `MapSets(map, uid)`,
`ModelFile(display)`, `ModelFiles()`, `Roots()` and `EntryOfFile(file)` on it
answer from the data. A set's string is
LibDeflate's printable encoding of a raw deflate stream over varints, decoded the first time
the set is asked for; the layout is documented in `src/furnish/codec.py`. Nothing is
rounded: a placement ships as the file's own float32 values, so the spawn command can be
given every digit the server keeps.

## The core

`addon/Furnish` is the addon. Its core is a kernel over final values, and providers that
turn what a player has into those values. The kernel and everything below it are pure Lua,
tested in a real Lua 5.1 against a stand-in server; the providers are tested against a
stand-in EpsilonLib.

```lua
Furnish.Spawn(rows, position, rotation, scale, group, send, hooks)
```

- `rows`: a list of `{ display, x, y, z, qx, qy, qz, qw, scale }`, relative to the anchor,
  spawned in the order given, so rows from several sets go in together. The data gives a
  set's rows as a trail from the origin, each beside the one before.
- `position` `{ x, y, z }`, `rotation` `{ roll, pitch, turn }` in degrees or nil for level,
  `scale` or nil for 1.
- `group`: `Furnish.Group.Pivot` (the pivot at the anchor leads, `Settings.pivot` as
  `.gob spawn` takes it), `First` (the
  first doodad leads), `None` (loose), or the GUID of an object whose group to join.
- `send`: `function(text, callback(success, messages))`, the door to the server.
- `hooks`: `progress(done, total)`, `deleting(done, total)` and `finished(outcome)`, where the
  outcome carries `spawned`, `refused` with each refusal's display, whether it was the pivot and
  the server's words, `unjoined`, `leader`, `joined` (how many besides the leader are in its
  group), `pivot`, `aborted`, `joinRefused` and, after a cleanup, `deleted`.

It answers a handle with `Abort(cleanup)` and `Done()`, or nil and the reason; a second
`Abort` while a reply is owed gives up on it, and a cleanup once asked for stays asked for. A
cleanup deletes one object at a time at the run's width, and the run is `Done()` when the last
delete answers; an `Abort` while it deletes sends no more. A join the server refuses stops the
run, since every join after it goes to the same leader. Who leads is
read off the replies: the first command that answers a GUID, so a refused pivot hands the
lead to the first doodad.

The files sit in six folders after `Settings.lua`, each a layer that reads only the ones
before it, in the order the toc loads them: `Core`, the engine, which knows neither the game
nor the data; `Data`, the reader over Furnish_Data and what it answers; `Client`, the doors
to the game and EpsilonLib; `Actions`, what the window and the command both do; `UI`, the
window and the options panel; and `Slash`, the typed command, its chat buttons and links,
which can open the window. Each file is handed the addon's table as
`local _, Furnish = ...`, and `Settings.lua`, loaded first, makes it the one global.

| file                  | role                                                                                   |
|-----------------------|----------------------------------------------------------------------------------------|
| `Settings.lua`        | the defaults: pivot, in-flight width, chat buttons; `FurnishSettings` keeps changes    |
| `Core/Transform.lua`  | the placement maths: `Place(position, rotation, scale, row)` and `Placer`              |
| `Core/Commands.lua`   | every command spelling and every reply reader                                          |
| `Core/Run.lua`        | any series of commands through `send`, in order, with needs and a width                |
| `Core/Kernel.lua`     | `Furnish.Spawn` and `Furnish.Group`                                                    |
| `Data/Reader.lua`     | the data addon's reader                                                                |
| `Data/Names.lua`      | a set's name as a player reads it: `Set(name)`, and a blueprint's: `Blueprint`         |
| `Data/Sets.lua`       | which: `OfFile`, `Pick`, `OfEntry`, `IsBlank`, `OfPlacement`, `Named`, `Same`          |
| `Data/Rows.lua`       | what: `OfSet`, `Pieces`, `Union`                                                       |
| `Client/Client.lua`   | the one file naming EpsilonLib and `C_Epsilon`; it reads, and never selects            |
| `Client/Pose.lua`     | where: `At`, `Copy`, `Here`, `Selected`, `OfRecord`                                    |
| `Client/Chat.lua`     | the prefix, counts, the colours, every tooltip, a menu measured to chat, the links     |
| `Client/Previews.lua` | Glimpse's doors: a preview peeked, and a WMO's picture                                 |
| `Actions/Console.lua` | what the commands and the window do: `List`, `Spawn`, `Import`, `Stop`, `Run`, `Offer` |
| `UI/Scene.lua`        | the Preview pane's scene: pieces as actors, the camera, the piece under the pointer    |
| `UI/Window.xml`       | the window's layout, after ObjectMover's: a dark dialog of bordered panels             |
| `UI/Window.lua`       | the window: reads `Selected`, `Busy` and `Watch`, spawns and stops through `Console`   |
| `UI/Options.lua`      | the settings panel in the game's Options, writing into `Furnish.Settings`              |
| `Slash/Command.lua`   | `/furnish` and `/furn`: what is typed, the help, the chat buttons, a link's click      |

`addon/Furnish/Libs` holds LibQTip-1.0, which draws the piece tooltip as a grid, and LibStub,
each as its authors ship it and under its own licence, which travels in its folder. `LICENSE` is
the AGPL and `NOTICE` says what it covers and what it does not.

## Develop

```bash
uv sync
uv run ruff format && uv run ruff check && uv run mypy && uv run pytest
stylua addon/Furnish && selene addon/Furnish
```
