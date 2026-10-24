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

| command                    | does                                                              |
|----------------------------|-------------------------------------------------------------------|
| `/furn`                    | open the window, described below                                  |
| `/furn list`               | the selected WMO's sets                                           |
| `/furn list <entry>`       | an object's sets, by the entry on its lookup line                 |
| `/furn <set>`              | spawn a set on the selected WMO                                   |
| `/furn <set> from <entry>` | spawn an object's set on the selected object                      |
| `/furn <set> here`         | spawn the selected WMO's set at your feet                         |
| `/furn <set> here <entry>` | spawn an object's set at your feet                                |
| `/furn import`             | import the selected doodad and furnish it, grouped on it          |
| `/furn stop`               | stop spawning; a second stop gives up on a reply that never comes |
| `/furn stop delete`        | stop, and delete what was spawned                                 |

A set, list or import takes any of these words after it:

| word      | does                                                            |
|-----------|-----------------------------------------------------------------|
| `first`   | its first object leads the group, instead of an invisible pivot |
| `attach`  | join the selected object's group                                |
| `nogroup` | spawn every object ungrouped                                    |
| `base`    | lay the base set under it, as an emptied WMO always gets        |

Each set in a list is a link: a click spawns it on the selected object, WMO or not, a
ctrl-click at your feet, and resting on it says what it is. A run that leaves a group selects that group
when it ends, in the chat as if typed, so `.gob group` commands act on it next. While it stays
selected it stands for the object the run was on, so the next set or list needs no reselecting.
A WMO's doodad line, from `.doodad select` or `.doodad near`, carries a `[Furnish]` button
that imports that WMO by its unique id and furnishes it as `/furn import` does.

The window shows the selected WMO's sets, and keeps showing them when the selection moves off
it. A click chooses a set or lets it go, any number of them, and a double-click spawns one
alone. Under the list are the grouping and where the sets go, on the target gob or on the
player; the choices that act on the selected WMO grey out while none is selected. During a run
a bar counts the objects and the clock, the spawn button stops it, and the bar says how it
ended. Every choice's tooltip says how a command types it.

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
(`blobs`) and the sets each map placement draws (`maps`). A root is keyed by its file id,
which is what a selected object's record reports; an entry, the number a lookup line
prints, reaches it through `entries`.
It loads on demand and holds nothing else, so it changes only when the data does.

`addon/Furnish/Reader.lua` is the reader and ships with the code, never with the data:
`Furnish.Reader.Load()` loads the data addon and refuses another format, and `Sets(file)`,
`Placements(set)`, `IsBlank(file)`, `FileOfEntry(entry)` and `MapSets(map, uid)` on it
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
