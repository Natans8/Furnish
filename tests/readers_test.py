from furnish.adt import read_placements
from furnish.wmo import Placement, read_root
from tests.files import adt_object, wmo_root

CHAIR = Placement(1001, (1.5, -2.0, 0.25), (0.0, 0.0, 0.5, 0.75), 1.0)
LAMP = Placement(1002, (0.0, 0.0, 3.0), (0.0, 0.0, 0.0, 1.0), 0.5)


def test_root_reads_sets_in_order_with_their_placements() -> None:
    root = read_root(
        wmo_root(
            [("Set_$DefaultGlobal", [LAMP]), ("Set_Furnished", [CHAIR, LAMP])], models=[1001, 1002]
        )
    )
    assert root.wmo_id == 7
    assert [s.name for s in root.sets] == ["Set_$DefaultGlobal", "Set_Furnished"]
    assert root.sets[0].placements == (LAMP,)
    assert root.sets[1].placements == (CHAIR, LAMP)


def test_root_keeps_floats_as_the_file_holds_them() -> None:
    root = read_root(wmo_root([("Set_$DefaultGlobal", [CHAIR])], models=[1001]))
    placement = root.sets[0].placements[0]
    assert placement.position == (1.5, -2.0, 0.25)
    assert placement.rotation == (0.0, 0.0, 0.5, 0.75)


def test_root_resolves_models_named_by_path_through_the_listfile() -> None:
    raw = wmo_root(
        [("Set_$DefaultGlobal", [CHAIR, LAMP])],
        models=[1001, 1002],
        model_names=["World\\Chair.m2", "world/lamp.m2"],
    )
    root = read_root(raw, {"world/chair.m2": 1001})
    assert [p.model for p in root.sets[0].placements] == [1001, 0]


def test_root_reads_a_blanked_model_as_zero() -> None:
    blank = Placement(0, (0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), 1.0)
    root = read_root(wmo_root([("Set_$DefaultGlobal", [blank])], models=[0]))
    assert root.sets[0].placements[0].model == 0


def test_group_file_is_refused() -> None:
    try:
        read_root(b"")
    except ValueError as error:
        assert "root" in str(error)
    else:
        raise AssertionError("an empty file read as a root")


def test_adt_reads_file_id_placements_and_their_set() -> None:
    rows = list(read_placements(adt_object([(5000, 42, 0x8, 3)])))
    assert rows == [type(rows[0])(5000, 42, (3,))]


def test_adt_resolves_named_placements_through_the_listfile() -> None:
    raw = adt_object([(1, 42, 0, 0)], names=["World/wmo/a.wmo", "World/wmo/B.wmo"])
    assert [p.model for p in read_placements(raw, {"world/wmo/b.wmo": 777})] == [777]


def test_adt_expands_set_ranges_when_flagged() -> None:
    raw = adt_object([(5000, 1, 0x8 | 0x80, 1), (5000, 2, 0x8, 1)], ranges=[[0], [0, 2, 5]])
    assert [p.sets for p in read_placements(raw)] == [(0, 2, 5), (1,)]
