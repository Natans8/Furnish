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
| `wmo_sets`   | a display id that spawns a root, a set index, its set         |
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

## Develop

```bash
uv sync
uv run ruff format && uv run ruff check && uv run mypy && uv run pytest
```
