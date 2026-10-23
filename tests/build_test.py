import sqlite3
from pathlib import Path

from furnish.build import Inputs, build
from furnish.displays import display_map
from furnish.wmo import Placement
from tests.files import adt_object, wmo_root

HOUSE = 900
EMPTY_TWIN = 901
CHAIR = Placement(1001, (1.5, -2.0, 0.25), (0.0, 0.0, 0.5, 0.75), 1.0)
LAMP = Placement(1002, (0.0, 0.0, 3.0), (0.0, 0.0, 0.0, 1.0), 0.5)
UNSPAWNABLE = Placement(1003, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), 1.0)
BLANK = Placement(0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), 1.0)


def write_inputs(tmp_path: Path) -> Inputs:
    roots = tmp_path / "roots"
    (roots / "world/wmo").mkdir(parents=True)
    (roots / "world/wmo/house.wmo").write_bytes(
        wmo_root(
            [("Set_$DefaultGlobal", [LAMP, BLANK]), ("Set_Full", [CHAIR, LAMP, UNSPAWNABLE])],
            models=[1001, 1002, 1003, 0],
        )
    )
    (roots / "world/wmo/house_000.wmo").write_bytes(b"group file, never read")
    (roots / "world/wmo/nodisplay.wmo").write_bytes(
        wmo_root([("Set_$DefaultGlobal", [CHAIR])], models=[1001])
    )
    (roots / "world/wmo/bare.wmo").write_bytes(
        wmo_root([("Set_$DefaultGlobal", [BLANK]), ("Set_Nothing", [])], models=[0])
    )
    maps = tmp_path / "maps"
    (maps / "world/maps/azeroth").mkdir(parents=True)
    (maps / "world/maps/azeroth/azeroth_32_48_obj0.adt").write_bytes(
        adt_object(
            [(HOUSE, 4242, 0x8, 1), (HOUSE, 4243, 0x8 | 0x80, 0), (EMPTY_TWIN, 4244, 0x8, 0)],
            ranges=[[0, 1]],
        )
    )
    (tmp_path / "listfile.csv").write_text(
        "900;world/wmo/house.wmo\n902;world/wmo/nodisplay.wmo\n903;world/wmo/bare.wmo\n"
        "1001;world/chair.m2\n"
    )
    (tmp_path / "displays.csv").write_text(
        "ID,FileDataID\n10,900\n11,900\n12,903\n20,1001\n21,1002\n"
    )
    (tmp_path / "maps.csv").write_text("ID,Directory\n0,Azeroth\n1,Kalimdor\n")
    return Inputs(
        roots=roots,
        maps=maps,
        listfile=tmp_path / "listfile.csv",
        display_table=tmp_path / "displays.csv",
        map_table=tmp_path / "maps.csv",
        overlay=[(1002, 100_500)],
        build="9.2.7.45745",
    )


def test_build_writes_the_four_tables(tmp_path: Path) -> None:
    out = tmp_path / "furnish.sqlite"
    inputs = write_inputs(tmp_path)
    report = build(inputs, out)
    db = sqlite3.connect(out)
    assert dict(db.execute("SELECT key, value FROM meta")) == {
        "format": "1",
        "build": "9.2.7.45745",
    }
    assert db.execute("SELECT name FROM sets ORDER BY id").fetchall() == [
        ("Set_$DefaultGlobal",),
        ("Set_Full",),
    ]
    assert db.execute('SELECT display, "index", "set" FROM wmo_sets ORDER BY 1, 2').fetchall() == [
        (10, 0, 1),
        (10, 1, 2),
        (11, 0, 1),
        (11, 1, 2),
    ]
    rows = db.execute(
        'SELECT "set", display, x, qz, scale FROM placements ORDER BY "set", display'
    ).fetchall()
    assert rows[0] == (1, 100_500, 0.0, 0.0, 0.5)
    assert rows[1] == (2, 20, 1.5, 0.5, 1.0)
    assert rows[2] == (2, 100_500, 0.0, 0.0, 0.5)
    assert len(rows) == 3
    assert db.execute('SELECT map, uid, "set" FROM map_sets ORDER BY 2, 3').fetchall() == [
        (0, 4242, 2),
        (0, 4243, 1),
        (0, 4243, 2),
    ]
    assert db.execute("SELECT count(*) FROM wmo_sets WHERE display = 12").fetchone() == (0,)
    assert (
        report.roots_read,
        report.roots_without_display,
        report.roots_without_doodads,
        report.empty_sets,
        report.blank_slots,
        report.models_without_display,
    ) == (1, 1, 1, 2, 2, 1)
    assert (report.tiles_read, report.map_rows, report.map_rows_unresolved) == (1, 3, 1)


def test_display_map_prefers_an_epsilon_row_then_the_lowest(tmp_path: Path) -> None:
    table = tmp_path / "displays.csv"
    table.write_text("ID,FileDataID\n58035,5\n58036,5\n7,6\n")
    assert display_map(table) == {5: 58035, 6: 7}
    assert display_map(table, [(5, 116638), (5, 116000)]) == {5: 116000, 6: 7}
