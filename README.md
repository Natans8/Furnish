# Furnish

The doodad sets of World of Warcraft's WMOs as a database, so that an Epsilon addon can
spawn a WMO's furniture as gameobjects.

A WMO root file names its doodad sets (`MODS`) and every placement each set holds
(`MODD`, `MODI`). Epsilon spawns a WMO with its default set only, and spawns each model
as a gameobject by a display id. The build joins the two: it reads the root files, resolves
every model to the display that spawns it, and writes one SQLite file.

## Commands

The command is `/furn`, or `/furnish`, and `/furn help` prints what follows. Both names are
placeholders: they are `SLASH_FURNISH1` and `SLASH_FURNISH2` in `Command.lua`, and every message
reads the first.

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
| `/furn stop delete`        | stop spawning, and delete what was spawned                                     |

A set, list or import takes any of these words after it:

| word      | does                                                                    |
|-----------|-------------------------------------------------------------------------|
| `first`   | the set's first object leads the group, so no pivot spawns              |
| `attach`  | include the selected gob in the group, so no pivot spawns               |
| `nogroup` | spawn every object ungrouped                                            |
| `base`    | spawn the base set as well, as a WMO that comes unfurnished always gets |

A list is a menu of buttons, one a set: a click spawns the set onto the selected gob, WMO or
not, a ctrl-click at your feet, and resting on one says its index, its objects and what it is.
Without a word, a pivot leads the group: one extra invisible object where the WMO stands,
turned and scaled with the set. The first run of a session reminds you that highlighting too
many objects can crash the game; turning it off is yours to do. A run that leaves a group selects that group
when it ends, in the chat as if typed, so `.gob group` commands act on it next. While it stays
selected it stands for the object the run was on, so the next set or list needs no reselecting.
A WMO's doodad line, from `.doodad select` or `.doodad near`, carries a `[Furnish]` button
that imports that WMO by its unique id and furnishes it as `/furn import` does, and a WMO gob's
selection line, from `.gob select`, one that lists its sets.

The window reads top to bottom as where the sets come from, which to spawn, and where they go.
Source is the WMO a gob entry is, held in its ID box as Target's numbers are: the selected gob's, one typed, which
keeps it whatever gob is selected, or the lowest entry of a WMO searched by name, since every entry of one WMO reads
the same sets. A search lists the WMOs with sets that the client's own catalogue names like it, the first
lit so Enter takes it and Up and Down moving the light, and those that come unfurnished
marked. A set the selected WMO draws already, as part of its model, is marked baked: its
base set, unless it comes unfurnished. A click chooses one set and a
ctrl-click adds or removes one, a strip at either end of the list counts the chosen sets
scrolled out of view, and resting on a set names the models it holds, as the client's own
catalogue names them once a walk of it, started when the window opens, has ended. Target is the selected
gob, or where you stand while nothing is selected, so every number always holds a value: X, Y
and Z, then the roll, pitch and turn about each in ObjectMover's colours, then the scale. Here
and Use selected gob fill it once; typing a number keeps what was typed; Tab moves through the
boxes. Either block's Follow selection, unticked, keeps what it shows whatever you select. A
selected group is used by neither block, as a model is no source: both say a group is selected, and
Use selected group fills Target once with the group's position and facing, level, since a group
has no roll or pitch of its own; Include the target then joins that group. The group a run selects
when it ends still stands for the WMO the run was on. The
doodad `.doodad select` picks is a selection of its own, held beside the gob's: it never changes
Source or Target, and while there is one a panel stands against the window's right edge with
its name and the sets of the WMO it is, those it draws already marked baked. Use as source keeps
that WMO as the source, with the sets the doodad drew beyond its base chosen. Import doodad turns
it into a gob that is selected like any other; while Source follows the selection, the same sets
come chosen on it, and either block kept as it is stays so. The doodad is
hidden, not gone, and stays selected; closing the panel lets it go. Group on spawn makes the objects one group,
led by a pivot the button counts; Include the target makes the target lead it instead, and
where the target is in a group already a mark warns and Spawn asks first. The status row
holds Highlighting, which toggles the client's outline on selected objects, beside a run's
progress with its time left, a warning before spawning onto a WMO the sets were not made for,
or the reminder that highlighting too many objects can crash the game. During a run every
control holds still and Stop and delete stands beside Stop; once the run ends, its group is
yours to manage. The window resizes from its corner, and the game keeps its size and place.

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
(`blobs`), the sets each map placement draws (`maps`) and the model each spawned display draws
(`models`), by its file id, which a model frame renders and the client's own catalogue names. A root is keyed by its file id,
which is what a selected object's record reports; an entry, the number a lookup line
prints, reaches it through `entries`.
It loads on demand and holds nothing else, so it changes only when the data does.

`addon/Furnish/Reader.lua` is the reader and ships with the code, never with the data:
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
- `group`: `Furnish.Group.Pivot` (an invisible marker at the anchor leads), `First` (the
  first doodad leads), `None` (loose), or the GUID of an object whose group to join.
- `send`: `function(text, callback(success, messages))`, the door to the server.
- `hooks`: `progress(done, total)` and `finished(outcome)`, where the outcome carries
  `spawned`, `refused` with each refusal's display and the server's words, `unjoined`,
  `leader`, `joined` (how many besides the leader are in its group), `pivot` and `aborted`.

It answers a handle with `Abort(cleanup)` and `Done()`, or nil and the reason; a second
`Abort` while a reply is owed gives up on it, and a cleanup once asked for stays asked for. Who leads is
read off the replies: the first command that answers a GUID, so a refused marker hands the
lead to the first doodad.

| file            | role                                                                                 |
|-----------------|--------------------------------------------------------------------------------------|
| `Settings.lua`  | the defaults: marker, in-flight width; `FurnishSettings` keeps changes               |
| `Reader.lua`    | the data addon's reader                                                              |
| `Names.lua`     | a set's name as a player reads it: `Set(name)`                                       |
| `Transform.lua` | the placement maths: `Place(position, rotation, scale, row)`                         |
| `Commands.lua`  | every command spelling and every reply reader                                        |
| `Run.lua`       | any series of commands through `send`, in order, with needs and a width              |
| `Kernel.lua`    | `Furnish.Spawn` and `Furnish.Group`                                                  |
| `Client.lua`    | the one file naming EpsilonLib and `C_Epsilon`; it reads, and never selects          |
| `Pose.lua`      | where: `At`, `Here`, `Selected`, `OfRecord`                                          |
| `Sets.lua`      | which: `OfFile`, `Pick`, `OfEntry`, `IsBlank`, `OfPlacement`                         |
| `Rows.lua`      | what: `OfSet`, `Union`, `Without`                                                    |
| `Chat.lua`      | the prefix, the colours, columns of exact width, and Furnish's links                 |
| `Console.lua`   | what the commands and the window do: `List`, `Spawn`, `Import`, `Stop`, `Target`     |
| `Window.xml`    | the window's layout, after ObjectMover's: a dark dialog of bordered panels           |
| `Window.lua`    | the window: reads `Target`, `Busy` and `Watch`, spawns and stops through `Console`   |
| `Command.lua`   | `/furnish` and `/furn`: reading what is typed, the help, a link's click              |

## Develop

```bash
uv sync
uv run ruff format && uv run ruff check && uv run mypy && uv run pytest
stylua addon/Furnish && selene addon/Furnish
```
