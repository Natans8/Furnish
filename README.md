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
optional and fills `map_sets`. The build fetches the community listfile and wago.tools'
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
`Furnish.Load()` loads the data addon and refuses another format, `Furnish.Sets(file)`,
`Furnish.Placements(set)` and `Furnish.MapSets(map, uid)` answer from it. A set's string is
LibDeflate's printable encoding of a raw deflate stream over varints, decoded the first time
the set is asked for; the layout is documented in `src/furnish/codec.py`. Nothing is
rounded: a placement ships as the file's own float32 values, so the spawn command can be
given every digit the server keeps.

## The core

`addon/Furnish` is the addon, and its core is three files over the reader, each pure
enough to run outside the client and tested in a real Lua 5.1 against a stand-in server:

- `Transform.lua`: the placement maths. `Place(house, row)` is where a doodad stands once its
  house stands at a pose, `SpawnCommand(display, pose)` the command for it, saying only what
  differs from a plain spawn.
- `Plan.lua`: preprocessing. `Plan.Build(house, index, options)` turns a house record, a set
  index and the options `attach`, `nopivot` and `default` into a plan, which is data: every
  command in order with its role, the counts, and the leader it will have. A plan is the dry
  run, and a refusal is nil and the reason.
- `Run.lua`: processing and post-processing. `Run.Start(plan, send, hooks)` sends the plan
  through the `send` it is given, reads each reply for its GUID, counts a refusal and goes on,
  joins every doodad to the leader, and tells its hooks `progress` and `finished`. The handle
  it returns has `Abort(cleanup)`. A run keeps nothing past its end.

Two facts the core still waits on from the game, both declared at the top of `Plan.lua`:
the marker entry a pivot is spawned as, and whether `group add` chains onto a spawn.

## Develop

```bash
uv sync
uv run ruff format && uv run ruff check && uv run mypy && uv run pytest
stylua addon/Furnish && selene addon/Furnish
```
