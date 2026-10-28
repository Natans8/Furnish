# Furnish

The doodad sets of World of Warcraft's WMOs as a database, so that an Epsilon addon can
spawn a WMO's furniture as gameobjects.

A WMO root file names its doodad sets (`MODS`) and every placement each set holds
(`MODD`, `MODI`). Epsilon spawns a WMO with its default set only, and spawns each model
as a gameobject by a display id. The build joins the two: it reads the root files, resolves
every model to the display that spawns it, and writes one SQLite file.

## Commands

The command is `/furn`, or `/furnish`, and `/furn help` prints a short form of what follows; every
message reads the first name.

| command                    | does                                                                           |
|----------------------------|--------------------------------------------------------------------------------|
| `/furn`                    | open the window, described below                                               |
| `/furn list`               | list the selected WMO's sets                                                   |
| `/furn list <entry>`       | list the sets of the WMO an entry names, the number on a lookup line           |
| `/furn <set>`              | spawn one of the selected WMO's sets onto that WMO                             |
| `/furn <set> from <entry>` | spawn a set of the WMO an entry names onto the selected gob                    |
| `/furn <set> here`         | spawn the selected WMO's set at your feet                                      |
| `/furn <set> here <entry>` | spawn a set of the WMO an entry names at your feet                             |
| `/furn import`             | turn the selected doodad into a gob, then spawn the doodad's sets onto the gob |
| `/furn stop`               | stop spawning; a second stop gives up on a reply that never comes              |
| `/furn stop delete`        | stop spawning, then delete what was spawned, one object at a time              |

A set, list or import takes any of these words after it:

| word      | does                                                                             |
|-----------|----------------------------------------------------------------------------------|
| `first`   | the first object spawned leads the group, so no pivot spawns                     |
| `merge`   | merge the set into the selected gob's group, so no pivot spawns                  |
| `nogroup` | spawn every object ungrouped                                                     |
| `base`    | spawn the base set as well, as a WMO that comes unfurnished always gets          |
| `quiet`   | leave the progress counts out of chat, saying only how the run began and ended   |

`/furn help` prints one short line a command and the words on one line, each a link whose tooltip
says what it does. Furnish's settings are in the game's Options, under AddOns: whether chat lines
carry `[Furnish]` buttons, how many commands a run sends before the first is answered, and what
a pivot spawns as, written as `.gob spawn` takes it: a gob entry, or a display as a negative
number. A change takes effect at once; Cancel puts back what the panel showed when it opened.

A list is a menu of buttons, one a set: a click spawns the set onto the selected gob, WMO or
not, a ctrl-click at your feet, and resting on one says its index, its objects and what it is.
Without a word, a pivot leads the group: one extra invisible object where the WMO stands,
turned and scaled with the set. The first run of a session reminds you that highlighting too
many objects can crash the game; turning it off is yours to do. A run that leaves a group selects that group
when it ends, in the chat as if typed, so `.gob group` commands act on it next. While it stays
selected it stands for the object the run was on, so the next set or list needs no reselecting.
A WMO's doodad line, from `.doodad select` or `.doodad near`, carries a `[Furnish]` button
that imports that WMO by its unique id and furnishes it as `/furn import` does, where the map
placed it with a set beyond its base, so that the import spawns something; and a WMO gob's
selection line, from `.gob select`, or its spawn line, from `.gob spawn`, which selects what it
makes, one that lists its sets. A right-click on either, or on a set's button in a list, opens
the window on it instead: the doodad in its panel, the gob's WMO as the source, or that set
chosen on its WMO.

The window reads top to bottom as where the sets come from, which to spawn, and where they go.
Source is the WMO a gob entry is, held in its ID box as Destination's numbers are: the selected gob's, one typed, which
keeps it whatever gob is selected, or the lowest entry of a WMO searched by name, since every entry of one WMO reads
the same sets. A search lists the WMOs with sets that the client's own catalogue names like it, the first
lit so Enter takes it and Up and Down moving the light, and those that come unfurnished
marked. Where Glimpse and its WMO pictures are installed, the source's WMO shows as its picture
beside these rows, read through the pictures' own door. A set the selected WMO draws already, as
part of its model, is marked baked: its base set, unless it comes unfurnished. A click chooses one
set and opens the Preview pane, a ctrl- or shift-click adds or removes one, and a strip at either
end of the list counts the chosen sets scrolled out of view. Destination is
numbers and nothing else: X, Y and Z, then the roll, pitch and turn about each in ObjectMover's
colours, then the scale. Following the selected gob is one way to fill them, Here and Use
selected gob fill them once, typing a number keeps what was typed, and while no gob is followed
they hold where you stood when they were read, so every number always holds a value; Tab moves
through the boxes. Either block's Follow selection, unticked, keeps what it shows whatever you
select. A selected group is followed by neither block, as a model is no source, and Use selected
group fills Destination once with the group's position and facing, level, since a group has no
roll or pitch of its own. The selection decides nothing else about Destination: what it decides
is the group. The group a run selects when it ends still stands for the WMO the run was on. The
doodad `.doodad select` picks is a selection of its own, held beside the gob's: it never changes
Source or Destination, and while there is one a panel stands against the window's right edge with
its name and the sets of the WMO it is, those it draws already marked baked. Every pick takes
the panel, the window open or not, and a doodad with no sets Furnish knows of shows there saying so. Use as source keeps
that WMO as the source, with the sets the doodad drew beyond its base chosen. Import doodad is
`/furn import`: it turns the doodad into a gob and spawns those sets merged into it, the run on
the window's bar. The doodad is hidden, not gone, and stays selected; closing the panel lets it
go. Group leader is one choice
of four, all in view: No group spawns the objects loose; Pivot, the default, makes them one
group led by an invisible pivot at the destination, which the button counts; First spawned lets
the first object lead instead, so nothing extra spawns; Selected gob makes whatever is selected
when the run starts lead, wherever Destination's numbers came from, or joins its group where it is
in one already, which a mark on the segment warns of and Spawn asks about first; with a group
selected it reads Selected group and joins that group. A group moves, turns and scales about its
leader. Selected gob greys while nothing is selected or while what is selected is not yours to
edit in the phase, Pivot standing in until it can lead; typed, such a merge is refused before
anything spawns, and a join the server refuses during a run stops it there. The
status row
holds Highlighting, which toggles the client's outline on selected objects, beside a run's
progress with its time left, a warning while Destination follows a WMO the sets were not made for,
or the reminder that highlighting too many objects can crash the game. During a run every
control holds still and Stop and delete stands beside Stop. It deletes what the run spawned one
object at a time, at the pace the run spawned, while the bar empties; Stop while it deletes sends
no more. Once the run ends, its group is yours to manage. A run that ends whole, at scale 1 with
no roll or pitch, led by its pivot or merged into a WMO that stood where they were placed, alone
and owning its sets, offers a blueprint at the window's bottom right whenever its group is the
selection: a suggested name, held to 225 bytes, and Paste to chat, which puts
`.gobject blueprint new <name>` in the chat box for you to send. A run from chat, an import
included, ends on the same offer as a button carrying the name, which pastes the command while the
run's group is selected and otherwise says how to select it. Closed or overtaken by the next run,
the offer goes. The window resizes from its corner, and the game keeps its size and place.

Preview is a pane against the window's right edge, below the doodad panel and above the blueprint
offer while they show, that any click on a set opens. It lays the chosen sets out in a model
scene, every piece at its own place, tilt and scale, without the WMO, which no model frame can
draw. The camera opens from a corner, framing the sphere around the models as they load, and a
line under the scene counts them in and then says how long they took. Drag to turn, right- or
middle-drag to pan, and turn the wheel to zoom, each about the piece under the pointer, so a zoom
closes on what is pointed at and a pan carries it with the pointer; the game's own model controls
stand over the scene, and Reset frames the sets as they opened. The pane's corner drags it wider
and the window taller with it. Resting on a piece marks it with a glow and names it in a tooltip
at the pointer: its model and the display it spawns by, its set, its position and rotation from
the WMO's origin as `.gob spawn` takes them, in Destination's colours, and its scale where it is
not one. A click chooses a piece alone, a shift-click chooses it too, and a shift-drag chooses
every piece in its band as it is drawn; the chosen stay lit and are counted under the pane's name, and Spawn,
at the pane's foot, spawns them where a run of their sets would put them at Destination, one
alone and several as a group led by the piece standing lowest, the one covering most ground among
those standing level, so a table leads what is on it, a carpet leads the chairs on it, and a group
moved to the ground sits on it. It unticks
Destination's Follow selection,
since the server selects what it spawns and a destination that followed would carry the next
pieces off; what spawned stays selected, and the choice is let go.

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
