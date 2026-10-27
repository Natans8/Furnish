"""The Lua reader against a real Lua 5.1 and the real LibDeflate, over a database it exports."""

import random
from pathlib import Path

import pytest
from lupa import lua51

from furnish.codec import Row, decode, for_print
from furnish.database import Database
from furnish.export import LINE_WIDTH, export
from furnish.order import trail
from furnish.wmo import Placement
from tests.core_test import ADDON, bare_lua, run_file
from tests.files import varied_placements

READER = ADDON / "Data" / "Reader.lua"

CHAIR = Placement(1001, (1.5, -2.0, 0.25), (0.0, 0.0, 0.5, 0.75), 1.0)
LAMP = Placement(1002, (0.0, 0.0, 3.0), (0.0, 0.0, 0.0, 1.0), 0.5)


def write_database(path: Path) -> None:
    with Database(path) as db:
        db.meta({"build": "9.2.7.45745"})
        default = db.add_set(None, [(21, LAMP)])
        full = db.add_set("Set_Full", [(20, CHAIR), (21, LAMP)])
        db.add_wmo_sets([(900, 0, default), (900, 1, full)])
        db.add_root_displays([(10, 900), (11, 900)])
        db.add_entries([(817579, 900)])
        db.add_map_sets([(0, 4242, full), (0, 4243, default), (0, 4243, full)])
        db.add_models([(20, 1001), (21, 1002)])


def lua_with(data: Path, format_override: str = "") -> lua51.LuaRuntime:
    lua = bare_lua()
    lua.globals().DATA_PATH = data.as_posix()
    lua.execute(
        "function LoadAddOn(name) if name == 'Furnish_Data' then dofile(DATA_PATH) "
        + format_override
        + " return true end return false, 'MISSING' end"
    )
    # The reader reads the layer under it, as the toc loads it first.
    run_file(lua, ADDON / "Settings.lua")
    run_file(lua, READER)
    return lua


def test_reader_loads_and_answers(tmp_path: Path) -> None:
    write_database(tmp_path / "f.sqlite")
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = lua_with(tmp_path / "Data.lua")
    assert lua.eval("Furnish.Reader.Load()") is True
    sets = lua.eval("Furnish.Reader.Sets(900)")
    assert [(s[1], s[3], s[4]) for s in sets.values()] == [(0, "", 1), (1, "Set_Full", 2)]
    rows = lua.eval("Furnish.Reader.Placements(Furnish.Reader.Sets(900)[2][2])")
    chair, lamp = rows[1], rows[2]
    assert (chair.display, chair.x, chair.y, chair.z) == (20, 1.5, -2.0, 0.25)
    assert (chair.qx, chair.qy, chair.qz, chair.qw, chair.scale) == (0, 0, 0.5, 0.75, 1)
    assert (lamp.display, lamp.z, lamp.qw, lamp.scale) == (21, 3.0, 1, 0.5)
    assert lua.eval("Furnish.Reader.Placements(2) == Furnish.Reader.Placements(2)") is True
    # The base set is left out, the gob a doodad becomes drawing it itself.
    assert list(lua.eval("Furnish.Reader.MapSets(0, 4243)").values()) == [2]
    assert lua.eval("Furnish.Reader.MapSets(1, 4243)") is None
    assert lua.eval("Furnish.Reader.FileOfEntry(817579)") == 900
    assert lua.eval("Furnish.Reader.FileOfEntry(1)") is None
    assert lua.eval("Furnish.Reader.Sets(999)") is None
    assert lua.eval("Furnish.Reader.ModelFile(20)") == 1001
    assert lua.eval("Furnish.Reader.ModelFile(21)") == 1002
    assert lua.eval("Furnish.Reader.ModelFile(22)") is None


def test_reader_refuses_another_format(tmp_path: Path) -> None:
    write_database(tmp_path / "f.sqlite")
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = lua_with(tmp_path / "Data.lua", "FurnishData.format = 99")
    ok, reason = lua.eval("Furnish.Reader.Load()")
    assert ok is False
    assert "format 99" in reason
    with pytest.raises(lua51.LuaError, match="Load"):
        lua.eval("Furnish.Reader.Sets(900)")


def test_reader_says_when_the_data_is_missing(tmp_path: Path) -> None:
    lua = lua_with(tmp_path / "absent.lua")
    lua.execute("function LoadAddOn(name) return false, 'MISSING' end")
    ok, reason = lua.eval("Furnish.Reader.Load()")
    assert ok is False
    assert "missing" in reason


@pytest.mark.parametrize("value", [0, 1, 127, 128, 16383, 16384, 2**31])
def test_lua_reads_large_display_ids_and_their_floats(tmp_path: Path, value: int) -> None:
    # A display id travels as a varint the Lua reads with powers of two rather than the bit
    # library, which wraps at 2^31; the float beside it must come back exact at any size.
    with Database(tmp_path / "f.sqlite") as db:
        db.meta({})
        db.add_set(
            "S", [(value or 1, Placement(1, (float(value), 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), 1.0))]
        )
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = lua_with(tmp_path / "Data.lua")
    assert lua.eval("Furnish.Reader.Load()") is True
    row = lua.eval("Furnish.Reader.Placements(1)[1]")
    assert (row.display, row.x) == (value or 1, float(value))


@pytest.mark.parametrize("count", [1, 40, 400, 3000])
def test_every_row_comes_back_bit_for_bit_through_the_exporter_and_the_reader(
    tmp_path: Path, count: int
) -> None:
    rows = varied_placements(count, count)
    with Database(tmp_path / "f.sqlite") as db:
        db.meta({"build": "9.2.7.45745"})
        set_id = db.add_set("Set_Varied", rows)
        db.add_wmo_sets([(900, 1, set_id)])
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = lua_with(tmp_path / "Data.lua")
    lua.execute("Furnish.Reader.Load()")
    stored = lua.eval(f"FurnishData.blobs[{set_id}]")
    # The exporter breaks a long string into lines of LINE_WIDTH, the first after the opener.
    lines = stored.split("\n")
    assert all(len(line) <= LINE_WIDTH for line in lines)
    joined = "".join(lines)
    # Every row comes back, in the trail the exporter walked.
    walked = trail([Row(d, p.position, p.rotation, p.scale) for d, p in rows])
    expected = [(r.display, *r.position, *r.rotation, r.scale) for r in walked]
    read = lua.eval(f"Furnish.Reader.Placements({set_id})")
    assert [
        (row.display, row.x, row.y, row.z, row.qx, row.qy, row.qz, row.qw, row.scale)
        for row in read.values()
    ] == expected
    # The Python codec reads the same string to the same rows.
    assert [(r.display, *r.position, *r.rotation, r.scale) for r in decode(joined)] == expected


def test_the_print_encoding_is_libdeflates(tmp_path: Path) -> None:
    """The exporter's printable encoding against the library the game decodes with."""
    lua = lua_with(tmp_path / "absent.lua")
    encode_for_print = lua.eval(
        "function(s) return LibStub:GetLibrary('LibDeflate'):EncodeForPrint(s) end"
    )
    pick = random.Random(7)
    samples = [bytes(pick.randrange(256) for _ in range(n)) for n in range(65)]
    samples.append(bytes(pick.randrange(256) for _ in range(20000)))
    for data in samples:
        expected = encode_for_print(data) if data else ""
        assert for_print(data) == (expected or "")
