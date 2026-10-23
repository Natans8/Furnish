# Furnish

The doodad sets of World of Warcraft's WMOs as a database, so that an Epsilon addon can
spawn a building's furniture as gameobjects.

A WMO root file names its doodad sets (`MODS`) and every placement each set holds
(`MODD`, `MODI`). Epsilon spawns a WMO with its default set only, and spawns each model
as a gameobject by a display id. The build joins the two: it reads the root files, resolves
every model to the display that spawns it, and writes one SQLite file.

## Build

```bash
uv run furnish build --roots <dir of .wmo files> --maps <dir of .adt files> --out furnish.sqlite
```

The directories hold the files at their listfile paths (`world/wmo/...`), as any CASC
extractor writes them; a root may also be named by its file id, `849966.wmo`. `--maps` is
optional and fills `map_sets`. `--listfile-extra <file>` adds a listfile the community one
lacks, a private client's own names, plain or gzipped, and may be repeated. The build fetches the community listfile and wago.tools'
`GameObjectDisplayInfo` and `Map` exports for the build given (`--build`, default Epsilon's
`9.2.7.45745`) into `--cache`, once.

## Tables

| table        | row                                                           |
|--------------|---------------------------------------------------------------|
| `meta`       | `format`, `build`                                             |
| `sets`       | a doodad set and its name, NULL for the default set           |
| `wmo_sets`   | a root file id, a set index, its set                          |
| `placements` | a set's doodad in order: display, position, quaternion, scale |
| `map_sets`   | a map id and ADT unique id, and a set it draws                |

Floats are the file's own. Rotation is the file's quaternion, converted to the game's
pitch, roll and turn by the consumer. Set 0 is kept, since a blanked copy of a root draws
none of it; it is the default set by position, so its name is not stored. Placements whose model slot is blank, or whose
model no display spawns, are dropped at build; a set left empty, and a root left with no
set, get no rows. Two roots holding the same set, name and placements alike, share one
row of `sets`.

`src/furnish/data/epsilon-displays.csv` carries Epsilon's own display rows for Blizzard's
model files, read from inside the game, because wago.tools cannot see them and some of
Blizzard's rows are refused by Epsilon's server.

## The addon data

```bash
uv run furnish export --db furnish.sqlite --out addon/Furnish_Data/Data.lua
```

`addon/Furnish_Data` is the data addon: `Data.lua`, generated and not committed, declaring
`FurnishData` with a `format` number, the `build`, each root file's sets (`wmo`), each set's
placements as one printable string (`blobs`) and the sets each map placement draws (`maps`).
It loads on demand and holds nothing else, so it changes only when the data does.

`addon/Furnish/Reader.lua` is the reader and ships with the code, never with the data:
`Furnish.Reader.Load()` loads the data addon and refuses another format, and `Sets(file)`,
`Placements(set)`, `FileOf(display)` and `MapSets(map, uid)` on it answer from the data. A set's string is
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

- `rows`: a list of `{ display, x, y, z, qx, qy, qz, qw, scale }`, relative to the anchor. A
  set is an unordered collection of these, so rows from several sets go in together.
- `position` `{ x, y, z }`, `rotation` `{ roll, pitch, turn }` in degrees or nil for level,
  `scale` or nil for 1.
- `group`: `Furnish.Group.Pivot` (an invisible marker at the anchor leads), `First` (the
  first doodad leads), `None` (loose), or the GUID of an object whose group to join.
- `send`: `function(text, callback(success, messages))`, the door to the server.
- `hooks`: `progress(done, total)` and `finished(outcome)`, where the outcome carries
  `spawned`, `refused` with each refusal's display and the server's words, `leader`, `pivot`
  and `aborted`.

It answers a handle with `Abort(cleanup)` and `Done()`, or nil and the reason. Who leads is
read off the replies: the first command that answers a GUID, so a refused marker hands the
lead to the first doodad.

| file            | role                                                                       |
|-----------------|----------------------------------------------------------------------------|
| `Settings.lua`  | the marker display and whether the join is chained onto a spawn            |
| `Transform.lua` | the placement maths: `Place(position, rotation, scale, row)`               |
| `Commands.lua`  | every command spelling and every reply reader                              |
| `Run.lua`       | any series of commands through `send`, in order, with needs and a width    |
| `Kernel.lua`    | `Furnish.Spawn` and `Furnish.Group`                                        |
| `Client.lua`    | the one file naming EpsilonLib and `C_Epsilon`                             |
| `Pose.lua`      | where: `At`, `Here`, `Of(guid, cb)`, `OfDoodad(line)`                      |
| `Sets.lua`      | which: `OfFile`, `Pick`, `OfDisplay`, `OfEntry(entry, cb)`, `Original`, `OfPlacement` |
| `Rows.lua`      | what: `OfSet`, `Union`, `Without`                                          |
| `Group.lua`     | `Furnish.Group.Leading(guid, cb)`, the GUID that leads an object's group   |
| `Console.lua`   | the `/run` door: `Sets`, `Spawn(index, options)`, `Here(file, index)`, `Abort` |

## Develop

```bash
uv sync
uv run ruff format && uv run ruff check && uv run mypy && uv run pytest
stylua addon/Furnish && selene addon/Furnish
```
