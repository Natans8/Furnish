"""The core in a real Lua 5.1: the placement maths, the plan a house and a set become, and a
run against a stand-in server that answers the way Epsilon's replies read."""

import math
from collections.abc import Callable
from pathlib import Path
from typing import Any

import pytest
from lupa import lua51

from furnish.database import Database
from furnish.export import export
from furnish.wmo import Placement

LIBDEFLATE = Path(__file__).parent / "lua" / "LibDeflate.lua"
ADDON = Path(__file__).parents[1] / "addon" / "Furnish"

HOUSE = 900
CHAIR = Placement(1001, (1.5, -2.0, 0.25), (0.0, 0.0, 0.0, 1.0), 1.0)
LAMP = Placement(1002, (0.0, 0.0, 3.0), (0.0, 0.0, 0.0, 1.0), 0.5)
GLOW = Placement(1003, (4.0, 4.0, 1.0), (0.0, 0.0, 0.0, 1.0), 1.0)


def write_database(path: Path) -> None:
    with Database(path) as db:
        db.meta({"build": "9.2.7.45745"})
        default = db.add_set(None, [(21, GLOW)])
        full = db.add_set("Set_Full", [(20, CHAIR), (21, LAMP)])
        db.add_wmo_sets([(HOUSE, 0, default), (HOUSE, 1, full)])


def lua_core(tmp_path: Path) -> lua51.LuaRuntime:
    write_database(tmp_path / "f.sqlite")
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        LibStub = { libs = {} }
        function LibStub:NewLibrary(name, minor) local lib = {} self.libs[name] = lib return lib end
        function LibStub:GetLibrary(name, silent) return self.libs[name] end
        """
    )
    lua.execute(LIBDEFLATE.read_text(encoding="utf-8"))
    lua.globals().DATA_PATH = (tmp_path / "Data.lua").as_posix()
    lua.execute("function LoadAddOn(name) dofile(DATA_PATH) return true end")
    for name in ("Reader.lua", "Transform.lua", "Plan.lua", "Run.lua"):
        lua.execute((ADDON / name).read_text(encoding="utf-8"))
    return lua


# -- Transform --------------------------------------------------------------------------


def test_angles_round_trip_through_the_quaternion(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    for roll, pitch, turn in ((0, 0, 0), (0, 0, 90), (10, 0, 0), (0, -20, 0), (15, 25, 300)):
        back = lua.eval(
            f"{{Furnish.Transform.ToAngles(Furnish.Transform.FromAngles({roll}, {pitch}, {turn}))}}"
        )
        assert [round(v, 6) % 360 for v in back.values()] == [roll % 360, pitch % 360, turn % 360]


def test_a_level_house_turned_west_moves_a_doodad_ahead_of_it_to_its_left(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    # Facing 0 is north, +X; a quarter turn goes toward west, +Y. A doodad one yard ahead
    # of the house's origin stands one yard west of it once the house faces west.
    pose = lua.eval(
        "Furnish.Transform.Place("
        "{ x = 100, y = 200, z = 5, roll = 0, pitch = 0, turn = 90, scale = 1 },"
        " { x = 1, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 })"
    )
    assert (round(pose.x, 6), round(pose.y, 6), pose.z) == (100, 201, 5)
    assert (round(pose.roll, 6), round(pose.pitch, 6), round(pose.turn, 6)) == (0, 0, 90)


def test_a_scaled_house_scales_offsets_and_doodads(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    pose = lua.eval(
        "Furnish.Transform.Place({ x = 0, y = 0, z = 0, roll = 0, pitch = 0, turn = 0, scale = 2 },"
        " { x = 1.5, y = -2, z = 0.25, qx = 0, qy = 0, qz = 0, qw = 1, scale = 0.5 })"
    )
    assert (pose.x, pose.y, pose.z, pose.scale) == (3, -4, 0.5, 1)


def test_a_doodads_turn_adds_to_the_houses(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    half = math.sin(math.radians(45))
    pose = lua.eval(
        "Furnish.Transform.Place("
        "{ x = 0, y = 0, z = 0, roll = 0, pitch = 0, turn = 30, scale = 1 },"
        f" {{ x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = {half}, qw = {half}, scale = 1 }})"
    )
    assert round(pose.turn, 4) == 120


def test_the_spawn_command_says_only_what_differs(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    plain = lua.eval(
        "Furnish.Transform.SpawnCommand(1001,"
        " { x = 1, y = -2.5, z = 0, roll = 0, pitch = 0, turn = 0, scale = 1 })"
    )
    assert plain == "gobject spawn -1001 posx 1 posy -2.5 posz 0 face north"
    full = lua.eval(
        "Furnish.Transform.SpawnCommand(1001,"
        " { x = 1, y = 2, z = 3, roll = 10, pitch = 350, turn = 90, scale = 0.5 })"
    )
    assert (
        full
        == "gobject spawn -1001 scale 0.5 posx 1 posy 2 posz 3 pitch 350 roll 10 face north turn 90"
    )


def test_numbers_keep_nine_digits_and_drop_noise(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    number = lua.eval("Furnish.Transform.Number")
    assert number(-318.0223083496094) == "-318.022308"
    assert number(0.0) == "0"
    assert number(-0.0) == "0"
    assert number(5.135284900665283) == "5.1352849"
    assert number(1e-7) == "0.0000001"


# -- Plan -------------------------------------------------------------------------------

STOCK = (
    "{ guid = 500, file = 900, x = 10, y = 20, z = 30, roll = 0, pitch = 0, turn = 0, scale = 1,"
    " groupLeader = 0, canEdit = true }"
)
TWIN = (
    "{ guid = 501, file = 777, twinOf = 900, x = 0, y = 0, z = 0, roll = 0, pitch = 0, turn = 0,"
    " scale = 1, groupLeader = 0, canEdit = true }"
)


def test_a_plan_spawns_a_pivot_then_the_set(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Plan.MARKER = 424242")
    plan = lua.eval(f"Furnish.Plan.Build({STOCK}, 1, {{}})")
    assert plan.leader == "pivot" and plan.doodads == 2 and plan.set.name == "Set_Full"
    commands = [(c.role, c.text) for c in plan.commands.values()]
    assert commands[0] == ("pivot", "gobject spawn 424242 posx 10 posy 20 posz 30 face north")
    assert commands[1] == ("doodad", "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north")
    assert commands[2] == (
        "doodad",
        "gobject spawn -21 scale 0.5 posx 10 posy 20 posz 33 face north",
    )


def test_a_twin_gets_the_default_set_too_and_no_pivot_when_attached(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    plan = lua.eval(f"Furnish.Plan.Build({TWIN}, 1, {{ attach = true }})")
    assert plan.leader == "house" and plan.withDefault is True and plan.doodads == 3
    assert [c.display for c in plan.commands.values()] == [21, 20, 21]


def test_a_plan_refuses_what_it_must(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    build = lua.eval("Furnish.Plan.Build")
    assert build(lua.eval(STOCK), 0, lua.table())[1].startswith("the shell already draws")
    assert build(lua.eval(STOCK), 7, lua.table())[1] == "this WMO has no set 7"
    assert build(lua.eval(STOCK), 1, lua.table())[1].startswith("no marker entry")
    assert (
        build(lua.eval(STOCK.replace("canEdit = true", "canEdit = false")), 1, lua.table())[1]
        == "you cannot edit this object"
    )
    assert (
        build(lua.eval(STOCK.replace("file = 900", "file = 1")), 1, lua.table())[1]
        == "the data has no sets for this WMO"
    )
    assert build(lua.eval(STOCK), 0, lua.table(default=True, nopivot=True)).doodads == 1


# -- Run --------------------------------------------------------------------------------


def fake_server(lua: lua51.LuaRuntime, refuse: int | None = None) -> Callable[[], list[str]]:
    """A send() that answers a spawn with a GUID line, numbered in order, and anything else
    with an empty success; `refuse` names a display the server rejects."""
    lua.globals().REFUSE = refuse or -1
    lua.execute(
        """
        SENT = {}
        NEXT_GUID = 7000
        function SEND(text, callback)
          SENT[#SENT + 1] = text
          local display = text:match("^gobject spawn %-?(%d+)")
          if display and tonumber(display) == REFUSE then
            callback(false, { "the gameobject with displayid -" .. display .. " doesn't exist" })
          elseif display then
            NEXT_GUID = NEXT_GUID + 1
            local guid = tostring(NEXT_GUID)
            local link = "|Hgameobject_GUID:" .. guid .. "|h" .. guid .. "|h"
            callback(true, { "Spawned |cff00ff00" .. link .. "|r" })
          else
            callback(true, {})
          end
        end
        """
    )
    return lambda: list(lua.eval("SENT").values())


def run(lua: lua51.LuaRuntime, plan_expr: str) -> Any:
    lua.execute(
        f"""
        RESULT = nil
        PROGRESS = {{}}
        local plan = assert({plan_expr})
        HANDLE = Furnish.Run.Start(plan, SEND, {{
          progress = function(done, total) PROGRESS[#PROGRESS + 1] = done .. "/" .. total end,
          finished = function(result) RESULT = result end,
        }})
        """
    )
    return lua.eval("RESULT")


def test_a_run_spawns_the_pivot_first_and_joins_every_doodad_to_it(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Plan.MARKER = 424242")
    sent = fake_server(lua)
    result = run(lua, f"Furnish.Plan.Build({STOCK}, 1, {{}})")
    assert sent() == [
        "gobject spawn 424242 posx 10 posy 20 posz 30 face north",
        "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north",
        "gobject group add 7001",
        "gobject spawn -21 scale 0.5 posx 10 posy 20 posz 33 face north",
        "gobject group add 7001",
    ]
    assert result.leader == "7001" and result.done == 3 and len(result.refused) == 0
    assert list(result.spawned.values()) == ["7001", "7002", "7003"]
    assert list(lua.eval("PROGRESS").values()) == ["1/3", "2/3", "3/3"]


def test_an_attached_run_joins_the_houses_group_and_spawns_no_pivot(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    grouped = STOCK.replace("groupLeader = 0", "groupLeader = 333")
    result = run(lua, f"Furnish.Plan.Build({grouped}, 1, {{ attach = true }})")
    assert sent()[1::2] == ["gobject group add 333", "gobject group add 333"]
    assert result.leader is None and result.done == 2


def test_a_refused_display_is_counted_and_the_run_goes_on(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua, refuse=20)
    result = run(lua, f"Furnish.Plan.Build({STOCK}, 1, {{ nopivot = true }})")
    assert result.done == 2 and len(result.refused) == 1
    refused = result.refused[1]
    assert refused.display == 20 and "doesn't exist" in refused.reason
    # With the first doodad refused, the next one leads.
    assert result.leader == "7001" and "gobject group add" not in " ".join(sent())


def test_chained_joins_go_out_several_at_a_time(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Plan.MARKER = 424242; Furnish.Plan.CHAINED_JOIN = true")
    sent = fake_server(lua)
    result = run(lua, f"Furnish.Plan.Build({STOCK}, 1, {{}})")
    assert sent() == [
        "gobject spawn 424242 posx 10 posy 20 posz 30 face north",
        "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north group add 7001",
        "gobject spawn -21 scale 0.5 posx 10 posy 20 posz 33 face north group add 7001",
    ]
    assert result.done == 3


def test_an_abort_with_cleanup_deletes_what_was_spawned(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Plan.MARKER = 424242")
    # A server that answers nothing until asked, so the run can be aborted mid-way.
    lua.execute(
        """
        SENT, PENDING = {}, {}
        function SEND(text, callback) SENT[#SENT + 1] = text PENDING[#SENT] = callback end
        function ANSWER(index, ...) local cb = PENDING[index] PENDING[index] = nil cb(...) end
        """
    )
    run(lua, f"Furnish.Plan.Build({STOCK}, 1, {{}})")
    lua.execute('ANSWER(1, true, { "|Hgameobject_GUID:7001|h7001|h" })')
    lua.execute('ANSWER(2, true, { "|Hgameobject_GUID:7002|h7002|h" })')
    lua.execute("HANDLE.Abort(true)")
    lua.execute("ANSWER(3, true, {})")
    sent = list(lua.eval("SENT").values())
    assert sent[:3] == [
        "gobject spawn 424242 posx 10 posy 20 posz 30 face north",
        "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north",
        "gobject group add 7001",
    ]
    assert sent[3:] == ["gobject delete 7001", "gobject delete 7002"]
    lua.execute("ANSWER(4, true, {}); ANSWER(5, true, {})")
    result = lua.eval("RESULT")
    assert result.aborted is True and result.deleted == 2


@pytest.mark.parametrize("field", ["spawned", "refused"])
def test_the_result_carries_lists(tmp_path: Path, field: str) -> None:
    lua = lua_core(tmp_path)
    fake_server(lua)
    result = run(lua, f"Furnish.Plan.Build({STOCK}, 1, {{ nopivot = true }})")
    assert lua.eval("type")(result[field]) == "table"
