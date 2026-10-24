import sqlite3
from dataclasses import replace
from pathlib import Path

from furnish.build import Inputs, build
from furnish.displays import preferred, spawners
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
    (roots / "world/wmo/house_copy.wmo").write_bytes(
        wmo_root([("Set_$DefaultGlobal", [LAMP]), ("Set_Full", [CHAIR, LAMP])], models=[1001, 1002])
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
        "904;world/wmo/house_copy.wmo\n1001;world/chair.m2\n"
    )
    (tmp_path / "displays.csv").write_text(
        "ID,FileDataID\n10,900\n11,900\n12,903\n13,904\n20,1001\n21,1002\n"
    )
    (tmp_path / "maps.csv").write_text("ID,Directory\n0,Azeroth\n1,Kalimdor\n")
    (tmp_path / "objects.csv").write_text(
        "entry,name\n817579,house.wmo\n817580,[9270100] HOUSE.wmo\n817581,emptywmo_house.wmo\n"
        "817582,eps_emptywmo_house.wmo\n817583,bare.wmo\n817584,nothing.wmo\n"
    )
    return Inputs(
        roots=roots,
        maps=maps,
        objects=tmp_path / "objects.csv",
        listfile=tmp_path / "listfile.csv",
        display_table=tmp_path / "displays.csv",
        map_table=tmp_path / "maps.csv",
        overlay=[(1002, 100_500)],
        build="9.2.7.45745",
    )


def test_build_writes_every_table(tmp_path: Path) -> None:
    out = tmp_path / "furnish.sqlite"
    inputs = write_inputs(tmp_path)
    report = build(inputs, out)
    db = sqlite3.connect(out)
    assert dict(db.execute("SELECT key, value FROM meta")) == {
        "format": "6",
        "build": "9.2.7.45745",
    }
    assert db.execute("SELECT name FROM sets ORDER BY id").fetchall() == [(None,), ("Set_Full",)]
    assert db.execute('SELECT file, "index", "set" FROM wmo_sets ORDER BY 1, 2').fetchall() == [
        (900, 0, 1),
        (900, 1, 2),
        (904, 0, 1),
        (904, 1, 2),
    ]
    rows = db.execute(
        'SELECT "set", display, x, qz, scale FROM placements ORDER BY "set", seq'
    ).fetchall()
    assert rows[0] == (1, 100_500, 0.0, 0.0, 0.5)
    assert rows[1] == (2, 20, 1.5, 0.5, 1.0)
    assert rows[2] == (2, 100_500, 0.0, 0.0, 0.5)
    assert len(rows) == 3
    assert report.shared_sets == 2
    assert db.execute('SELECT map, uid, "set" FROM map_sets ORDER BY 2, 3').fetchall() == [
        (0, 4242, 2),
        (0, 4243, 1),
        (0, 4243, 2),
    ]
    assert db.execute("SELECT count(*) FROM wmo_sets WHERE file = 903").fetchone() == (0,)
    assert db.execute("SELECT display, file FROM root_displays ORDER BY 1").fetchall() == [
        (10, 900),
        (11, 900),
        (13, 904),
    ]
    # Named directly, tagged, and as a twin, an entry reaches the furnished root; a root
    # without sets or a name no root carries does not.
    assert db.execute("SELECT entry, file FROM entries ORDER BY 1").fetchall() == [
        (817579, 900),
        (817580, 900),
        (817581, 900),
        (817582, 900),
    ]
    assert (report.entries, report.entries_unresolved) == (4, 2)
    assert (
        report.roots_read,
        report.roots_without_display,
        report.roots_without_doodads,
        report.empty_sets,
        report.blank_slots,
        report.models_without_display,
    ) == (2, 1, 1, 2, 2, 1)
    assert (report.tiles_read, report.map_rows, report.map_rows_unresolved) == (1, 3, 1)
    # Each display a placement spawns names its model by the file's name alone; the lamp's
    # file is in no listfile, so it is counted rather than named.
    assert db.execute("SELECT display, name FROM models ORDER BY 1").fetchall() == [(20, "chair")]
    assert report.models_unnamed == 1


def test_spawners_merge_the_overlay_and_preferred_picks_epsilon_then_lowest(tmp_path: Path) -> None:
    table = tmp_path / "displays.csv"
    table.write_text("ID,FileDataID\n58035,5\n58036,5\n7,6\n")
    assert spawners(table) == {5: (58035, 58036), 6: (7,)}
    merged = spawners(table, [(5, 116638), (5, 116000)])
    assert merged[5] == (58035, 58036, 116000, 116638)
    assert preferred(merged[5]) == 116000
    assert preferred(merged[6]) == 7


def sunk(p: Placement) -> Placement:
    """A placement as an emptywmo twin holds it: below the ground, at scale 0."""
    return replace(p, position=(p.position[0], p.position[1], -1000.0), scale=0.0)


def test_a_blanked_root_takes_the_sets_of_the_wmo_it_was_emptied_from(
    tmp_path: Path,
) -> None:
    inputs = write_inputs(tmp_path)
    roots = inputs.roots
    blank = [
        ("Set_$DefaultGlobal", [sunk(LAMP), sunk(BLANK)]),
        ("Set_Full", [sunk(p) for p in (CHAIR, LAMP, UNSPAWNABLE)]),
    ]
    (roots / "world/wmo/emptywmo_house.wmo").write_bytes(
        wmo_root(blank, models=[1001, 1002, 1003, 0])
    )
    # Nothing places its doodads where this one does.
    (roots / "world/wmo/lonely.wmo").write_bytes(
        wmo_root(
            [("Set_$DefaultGlobal", [replace(CHAIR, position=(9.0, 9.0, 9.0), scale=0.0)])],
            models=[1001],
        )
    )
    # Two WMOs place their doodads alike but hold different models.
    (roots / "world/wmo/tower.wmo").write_bytes(
        wmo_root(
            [("Set_$DefaultGlobal", [replace(CHAIR, position=(5.0, 0.0, 0.0))])], models=[1001]
        )
    )
    (roots / "world/wmo/tower_red.wmo").write_bytes(
        wmo_root(
            [
                (
                    "Set_$DefaultGlobal",
                    [replace(LAMP, position=(5.0, 0.0, 0.0), rotation=CHAIR.rotation)],
                )
            ],
            models=[1002],
        )
    )
    # A twin of either, sunk below the ground, cannot say which; a copy blanked by its
    # scales alone keeps its models and heights, and says.
    (roots / "world/wmo/tower_empty.wmo").write_bytes(
        wmo_root(
            [("Set_$DefaultGlobal", [sunk(replace(CHAIR, position=(5.0, 0.0, 0.0)))])],
            models=[1001],
        )
    )
    # A copy that emptied its base set as well is known by the sets after it.
    (roots / "world/wmo/eps_house.wmo").write_bytes(
        wmo_root(
            [
                ("Set_$DefaultGlobal", []),
                ("Set_Full", [replace(p, scale=0.0) for p in (CHAIR, LAMP)]),
            ],
            models=[1001, 1002],
        )
    )
    (roots / "world/wmo/eps_tower.wmo").write_bytes(
        wmo_root(
            [("Set_$DefaultGlobal", [replace(CHAIR, position=(5.0, 0.0, 0.0), scale=0.0)])],
            models=[1001],
        )
    )
    with (tmp_path / "listfile.csv").open("a") as listfile:
        listfile.write(
            "905;world/wmo/emptywmo_house.wmo\n906;world/wmo/lonely.wmo\n907;world/wmo/tower.wmo\n"
            "908;world/wmo/tower_red.wmo\n909;world/wmo/tower_empty.wmo\n"
            "910;world/wmo/eps_tower.wmo\n911;world/wmo/eps_house.wmo\n"
        )
    with (tmp_path / "displays.csv").open("a") as displays:
        displays.write("14,905\n15,906\n16,907\n17,908\n18,909\n19,910\n22,911\n")
    out = tmp_path / "furnish.sqlite"
    report = build(inputs, out)
    db = sqlite3.connect(out)
    assert db.execute("SELECT file FROM blank_roots ORDER BY 1").fetchall() == [
        (905,),
        (910,),
        (911,),
    ]
    sets = 'SELECT "index", "set" FROM wmo_sets WHERE file = ? ORDER BY 1'
    assert db.execute(sets, (905,)).fetchall() == db.execute(sets, (900,)).fetchall()
    assert db.execute(sets, (906,)).fetchall() == []
    assert db.execute(sets, (909,)).fetchall() == []
    assert db.execute(sets, (910,)).fetchall() == db.execute(sets, (907,)).fetchall()
    assert db.execute(sets, (911,)).fetchall() == db.execute(sets, (904,)).fetchall()
    assert (report.blank_roots, report.blank_unmatched, report.blank_ambiguous) == (3, 1, 1)
    # The twin's entry now names the twin itself, which carries the sets it was emptied of.
    assert db.execute("SELECT file FROM entries WHERE entry = 817581").fetchone() == (905,)
