"""The core in a real Lua 5.1: the placement maths, the command grammar, a run over any series
of commands, the kernel for every way of grouping, and the providers against a stand-in client
whose replies read the way Epsilon's do."""

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
#: Every file the toc loads, in its order, as a path under the addon, read off the toc so a
#: file it gains loads here too.
LOADED = tuple(
    line.strip().replace("\\", "/")
    for line in (ADDON / "Furnish.toc").read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.startswith("#")
)
#: The files that draw frames, which need a client and are tried in the simulator instead.
DRAWN = {"UI/Window.lua", "UI/Options.lua"}
#: The folder of libraries embedded as their authors ship them, loaded before the addon's own
#: files and not Furnish's code: they need a client and are not held to its rules.
LIBRARIES = "Libs/"
#: The Lua files the core is tested with, in load order.
FILES = tuple(
    name
    for name in LOADED
    if name.endswith(".lua") and name not in DRAWN and not name.startswith(LIBRARIES)
)

HOUSE = 900
EMPTY_HOUSE = 777
CHAIR = Placement(1001, (1.5, -2.0, 0.25), (0.0, 0.0, 0.0, 1.0), 1.0)
LAMP = Placement(1002, (0.0, 0.0, 3.0), (0.0, 0.0, 0.0, 1.0), 0.5)
GLOW = Placement(1003, (4.0, 4.0, 1.0), (0.0, 0.0, 0.0, 1.0), 1.0)

ANCHOR = "{ x = 10, y = 20, z = 30 }"
SPAWN_CHAIR = "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north"
SPAWN_LAMP = "gobject spawn -21 scale 0.5 posx 10 posy 20 posz 33 face north"
SPAWN_PIVOT = "gobject spawn -424242 posx 10 posy 20 posz 30 face north"


def write_database(path: Path, layered: bool = False) -> None:
    """The house, its emptywmo twin, the map placement that draws Full and placement 4244, which
    draws only the base set. Layered, the house has a second set, Lights, and placement 4343
    draws both, as a tile naming a run of sets does."""
    with Database(path) as db:
        db.meta({"build": "9.2.7.45745"})
        default = db.add_set(None, [(21, GLOW)])
        full = db.add_set("Set_Full", [(20, CHAIR), (21, LAMP)])
        db.add_wmo_sets([(HOUSE, 0, default), (HOUSE, 1, full)])
        # An emptywmo twin of the house, which the build gives the house's sets.
        db.add_blank_root(EMPTY_HOUSE)
        db.add_wmo_sets([(EMPTY_HOUSE, 0, default), (EMPTY_HOUSE, 1, full)])
        db.add_root_displays([(30262, HOUSE)])
        db.add_entries([(817579, HOUSE)])
        db.add_map_sets([(1116, 4242, full), (1116, 4244, default)])
        # The model file each display draws, as the build writes it.
        db.add_models([(20, 1001), (21, 1002), (22, 1003)])
        if layered:
            lights = db.add_set("Set_Lights", [(22, GLOW)])
            db.add_wmo_sets([(HOUSE, 2, lights)])
            db.add_map_sets([(1116, 4343, full), (1116, 4343, lights)])


def bare_lua() -> lua51.LuaRuntime:
    """A Lua 5.1 with LibStub and the real LibDeflate, which the reader needs and nothing more."""
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        LibStub = { libs = {} }
        function LibStub:NewLibrary(name, minor) local lib = {} self.libs[name] = lib return lib end
        function LibStub:GetLibrary(name, silent) return self.libs[name] end
        """
    )
    lua.execute(LIBDEFLATE.read_text(encoding="utf-8"))
    return lua


def run_file(lua: lua51.LuaRuntime, path: Path) -> None:
    """Run one of the addon's files as the client does, handed the addon's name and its table;
    the table is the global Furnish here, so a test reaches every part of it."""
    lua.globals().SOURCE = path.read_text(encoding="utf-8")
    lua.globals().NAME = path.relative_to(ADDON).as_posix()
    lua.execute(
        'Furnish = Furnish or {} assert(loadstring(SOURCE, "@" .. NAME))("Furnish", Furnish)'
    )


def lua_core(tmp_path: Path, layered: bool = False) -> lua51.LuaRuntime:
    write_database(tmp_path / "f.sqlite", layered)
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = bare_lua()
    lua.execute(
        """
        PRINTED = {}
        function print(...) PRINTED[#PRINTED + 1] = table.concat({ ... }, " ") end
        FRAMES = {}
        function CreateFrame()
          local frame = { events = {} }
          function frame:RegisterEvent(event) self.events[event] = true end
          function frame:UnregisterEvent(event) self.events[event] = nil end
          function frame:SetScript(_, fn) self.handler = fn end
          FRAMES[#FRAMES + 1] = frame
          return frame
        end
        SlashCmdList = {}
        HOOKS = {}
        function hooksecurefunc(name, fn) HOOKS[name] = fn end
        NUM_CHAT_WINDOWS = 0
        FILTERS = {}
        function ChatFrame_AddMessageEventFilter(event, fn) FILTERS[#FILTERS + 1] = fn end
        function FIRE(event, ...)
          for _, frame in ipairs(FRAMES) do
            if frame.events[event] and frame.handler then frame.handler(frame, event, ...) end
          end
        end
        -- Every row of every list given, in the order given: several sets' rows as one run.
        function UNION(...)
          local out = {}
          for i = 1, select("#", ...) do
            for _, row in ipairs(select(i, ...)) do out[#out + 1] = row end
          end
          return out
        end
        """
    )
    lua.globals().DATA_PATH = (tmp_path / "Data.lua").as_posix()
    lua.execute("function LoadAddOn(name) dofile(DATA_PATH) return true end")
    for name in FILES:
        run_file(lua, ADDON / name)
    lua.execute("Furnish.Settings.pivot = -424242")
    return lua


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


def rows(lua: lua51.LuaRuntime, *sets: int) -> str:
    return "UNION(" + ", ".join(f"Furnish.Rows.OfSet({s})" for s in sets) + ")"


def spawn(lua: lua51.LuaRuntime, rows_expr: str, group: str = "Furnish.Group.Pivot") -> Any:
    lua.execute(
        f"""
        RESULT, PROGRESS = nil, {{}}
        HANDLE, REASON = Furnish.Spawn({rows_expr}, {ANCHOR}, nil, nil, {group}, SEND, {{
          progress = function(done, total) PROGRESS[#PROGRESS + 1] = done .. "/" .. total end,
          finished = function(result) RESULT = result end,
        }})
        """
    )
    return lua.eval("RESULT")


HIGHLIGHT_REMINDER = "highlighting too many objects can crash the game"
"""The words of the reminder a session's first run prints, which only its own test reads."""


def printed(lua: lua51.LuaRuntime, reminders: bool = False) -> list[str]:
    """The lines printed so far, the highlighting reminder left out unless asked for."""
    lines = list(lua.eval("PRINTED").values())
    return lines if reminders else [line for line in lines if HIGHLIGHT_REMINDER not in line]


# -- Transform --------------------------------------------------------------------------


def test_angles_round_trip_through_the_quaternion(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    for roll, pitch, turn in ((0, 0, 0), (0, 0, 90), (10, 0, 0), (0, -20, 0), (15, 25, 300)):
        back = lua.eval(
            f"{{Furnish.Transform.ToAngles(Furnish.Transform.FromAngles({roll}, {pitch}, {turn}))}}"
        )
        assert [round(v, 6) % 360 for v in back.values()] == [roll % 360, pitch % 360, turn % 360]


def test_an_anchor_turned_west_moves_a_doodad_ahead_of_it_to_its_left(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    # Facing 0 is north, +X; a quarter turn goes toward west, +Y. A doodad one yard ahead
    # of the anchor stands one yard west of it once the anchor faces west.
    pose = lua.eval(
        "Furnish.Transform.Place({ x = 100, y = 200, z = 5 }, { turn = 90 }, 1,"
        " { x = 1, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 })"
    )
    assert (round(pose.x, 6), round(pose.y, 6), pose.z) == (100, 201, 5)
    assert (round(pose.roll, 6), round(pose.pitch, 6), round(pose.turn, 6)) == (0, 0, 90)


def test_a_scaled_anchor_scales_offsets_and_doodads(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    pose = lua.eval(
        "Furnish.Transform.Place({ x = 0, y = 0, z = 0 }, nil, 2,"
        " { x = 1.5, y = -2, z = 0.25, qx = 0, qy = 0, qz = 0, qw = 1, scale = 0.5 })"
    )
    assert (pose.x, pose.y, pose.z, pose.scale) == (3, -4, 0.5, 1)


def test_a_doodads_turn_adds_to_the_anchors(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    half = math.sin(math.radians(45))
    pose = lua.eval(
        "Furnish.Transform.Place({ x = 0, y = 0, z = 0 }, { turn = 30 }, 1,"
        f" {{ x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = {half}, qw = {half}, scale = 1 }})"
    )
    assert round(pose.turn, 4) == 120


# -- Commands ---------------------------------------------------------------------------


def test_the_spawn_command_says_only_what_differs(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    plain = lua.eval(
        "Furnish.Commands.Spawn(1001,"
        " { x = 1, y = -2.5, z = 0, roll = 0, pitch = 0, turn = 0, scale = 1 })"
    )
    assert plain == "gobject spawn -1001 posx 1 posy -2.5 posz 0 face north"
    full = lua.eval(
        "Furnish.Commands.Spawn(1001,"
        " { x = 1, y = 2, z = 3, roll = 10, pitch = 350, turn = 90, scale = 0.5 })"
    )
    assert (
        full
        == "gobject spawn -1001 scale 0.5 posx 1 posy 2 posz 3 pitch 350 roll 10 face north turn 90"
    )


def test_numbers_keep_nine_digits_and_drop_noise(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    number = lua.eval("Furnish.Commands.Number")
    assert number(-318.0223083496094) == "-318.022308"
    assert number(0.0) == "0"
    assert number(-0.0) == "0"
    assert number(5.135284900665283) == "5.1352849"
    assert number(1e-7) == "0.0000001"


def test_the_widest_spawn_line_stays_under_the_limit(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    line = lua.eval(
        "Furnish.Commands.Spawn(9999999, { x = -17066.1234,"
        " y = -17066.1234, z = -17066.1234, roll = 359.999999, pitch = 359.999999,"
        " turn = 359.999999, scale = 0.123456789 })"
    )
    assert len(line) < lua.eval("Furnish.Commands.LIMIT")


def test_replies_are_read_and_stripped_plain(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    commands = lua.eval("Furnish.Commands")
    guid = "Spawned |cff00ff00|Hgameobject_GUID:7001|h7001|h|r"
    assert commands.GuidIn(lua.table(guid)) == "7001"
    assert commands.GuidIn(lua.table("(GUID: |cff00CCFF88|r)")) == "88"
    assert commands.Plain(guid) == "Spawned 7001"


#: A doodad's selection line as the server printed it, captured whole.
SELECTED_DOODAD = (
    "Selected doodad |cff00CCFF|Hdoodad_uid:10059564:0|h[draenei jug - 326022]|h|r"
    " (UID: |cff00CCFF10059564|r) at X: |cff00CCFF2984.496745|r Y: |cff00CCFF3273.661784|r"
    " Z: |cff00CCFF45.630093|r on map |cff00CCFF1116|r with scale: |cff00CCFF1.000000|r."
)


#: The same selection once the doodad is off the map: an import replaced it with a gob.
REPLACED_DOODAD = SELECTED_DOODAD.replace("|Hdoodad_uid:", "|Hdoodad_deleted_uid:").replace(
    "]|h|r (UID", "]|h|r (Replaced) (UID"
)


def test_a_doodad_off_the_map_is_read_and_says_how(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    link = lua.eval("Furnish.Commands.DoodadLink")
    assert link(SELECTED_DOODAD) == (10059564, 326022, 1116, False)
    assert link(REPLACED_DOODAD) == (10059564, 326022, 1116, True)
    doodad = lua.eval("Furnish.Commands.SelectedDoodad")(REPLACED_DOODAD)
    assert (doodad.uid, doodad.name, doodad.removed, doodad.status) == (
        10059564,
        "draenei jug",
        True,
        "replaced",
    )
    standing = lua.eval("Furnish.Commands.SelectedDoodad")(SELECTED_DOODAD)
    assert (standing.removed, standing.status) == (False, None)


def test_a_doodad_link_names_the_map_its_line_colours(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    assert lua.eval("Furnish.Commands.DoodadLink")(SELECTED_DOODAD) == (
        10059564,
        326022,
        1116,
        False,
    )
    # A near line names no map; its doodads stand on the player's.
    near = "|Hdoodad_uid:4242:0|h[house.wmo - 817579]|h (UID: 4242)"
    assert lua.eval("Furnish.Commands.DoodadLink")(near) == (4242, 817579, None, False)


def test_an_angle_is_level_on_either_side_of_nought(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    level = lua.eval("Furnish.Commands.IsLevel")
    assert [level(angle) for angle in (0, -0.0001, 359.9999, 360, -5, 5, 180)] == [
        True,
        True,
        True,
        True,
        False,
        False,
        False,
    ]
    unit = lua.eval("Furnish.Commands.IsUnit")
    assert [unit(scale) for scale in (1, 1.0001, 0.9999, 1.001, 2)] == [
        True,
        True,
        True,
        False,
        False,
    ]


def test_a_doodad_selection_line_is_read_and_nothing_else(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    read = lua.eval("Furnish.Commands.SelectedDoodad")
    doodad = read(SELECTED_DOODAD)
    assert (doodad.uid, doodad.entry, doodad.name, doodad.map) == (
        10059564,
        326022,
        "draenei jug",
        1116,
    )
    assert read("Imported [house.wmo - 817579] (UniqueId: 4242) as GUID 500.") is None
    assert read("|Hdoodad_uid:4242:0|h[house.wmo - 817579]|h (UID: 4242)") is None


# -- Run --------------------------------------------------------------------------------


def start_run(lua: lua51.LuaRuntime, commands: str, width: int = 1) -> Any:
    lua.execute(
        f"""
        OUT = nil
        HANDLE, REASON = Furnish.Run.Start({commands}, SEND, {{
          finished = function(out) OUT = out end,
        }}, {width})
        """
    )
    return lua.eval("OUT")


def test_a_run_sends_in_order_and_keeps_every_result_by_position(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    out = start_run(
        lua, '{ { text = "gobject spawn -1 posx 0" }, { text = "gobject group add 5" } }'
    )
    assert sent() == ["gobject spawn -1 posx 0", "gobject group add 5"]
    assert out.done == 2 and out.results[1].success is True and out.results[2].messages is not None


def test_a_command_may_read_an_earlier_reply_or_send_nothing(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    out = start_run(
        lua,
        """{
          { text = "gobject spawn -1 posx 0" },
          { needs = { 1 }, text = function(results)
              return "gobject group add " .. Furnish.Commands.GuidIn(results[1].messages) end },
          { needs = { 1 }, text = function() return nil end },
        }""",
    )
    assert sent() == ["gobject spawn -1 posx 0", "gobject group add 7001"]
    assert out.done == 3 and out.results[3].skipped is True


def test_a_need_that_is_not_earlier_is_refused_before_anything_is_sent(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    start_run(lua, '{ { needs = { 2 }, text = "a" }, { text = "b" } }')
    assert lua.eval("HANDLE") is None and "command 1 needs position 2" in lua.eval("REASON")
    assert sent() == []


def test_width_bounds_what_is_in_flight(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    held_server(lua)
    start_run(lua, '{ { text = "a" }, { text = "b" }, { text = "c" }, { text = "d" } }', width=2)
    assert list(lua.eval("SENT").values()) == ["a", "b"]
    lua.execute("ANSWER(1)")
    assert list(lua.eval("SENT").values()) == ["a", "b", "c"]
    lua.execute("HANDLE.Abort()")
    lua.execute("ANSWER(2); ANSWER(3)")
    out = lua.eval("OUT")
    assert (
        out.aborted is True and out.done == 3 and list(lua.eval("SENT").values()) == ["a", "b", "c"]
    )


def test_a_glued_command_goes_with_the_one_before_it_or_not_at_all(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    held_server(lua)
    # b waits for c, glued to it, which waits for a; the width of one never parts them.
    start_run(
        lua,
        '{ { text = "a" }, { text = "b" }, { glued = true, needs = { 1 }, text = "c" },'
        ' { text = "d" } }',
        width=1,
    )
    assert list(lua.eval("SENT").values()) == ["a"]
    lua.execute("ANSWER(1)")
    assert list(lua.eval("SENT").values()) == ["a", "b", "c"]
    lua.execute("ANSWER(2)")
    assert list(lua.eval("SENT").values()) == ["a", "b", "c"]
    lua.execute("ANSWER(3)")
    assert list(lua.eval("SENT").values()) == ["a", "b", "c", "d"]


@pytest.mark.parametrize(
    "commands",
    [
        '{ { glued = true, text = "a" } }',
        '{ { text = "a" }, { glued = true, needs = { 1 }, text = "b" } }',
    ],
)
def test_a_glued_run_that_could_never_go_is_refused(tmp_path: Path, commands: str) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    start_run(lua, commands)
    assert lua.eval("HANDLE") is None and "glued" in lua.eval("REASON")
    assert sent() == []


def test_a_second_abort_gives_up_on_the_replies_still_owed(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    held_server(lua)
    start_run(lua, '{ { text = "a" }, { text = "b" }, { text = "c" } }', width=2)
    lua.execute("HANDLE.Abort()")
    assert lua.eval("OUT") is None  # two replies are still owed
    lua.execute("ANSWER(1)")
    assert lua.eval("OUT") is None
    lua.execute("HANDLE.Abort()")
    out = lua.eval("OUT")
    assert out.aborted is True and out.done == 1 and list(lua.eval("SENT").values()) == ["a", "b"]
    lua.execute("ANSWER(2)")  # the late reply changes nothing
    assert lua.eval("OUT").done == 1


# -- Kernel -----------------------------------------------------------------------------


def test_pivot_spawns_the_pivot_first_and_joins_every_doodad_to_it(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 2))
    assert sent() == [
        SPAWN_PIVOT,
        SPAWN_CHAIR,
        "gobject group add 7001",
        SPAWN_LAMP,
        "gobject group add 7001",
    ]
    assert (result.leader, result.pivot, result.total) == ("7001", "7001", 2)
    assert list(result.spawned.values()) == ["7001", "7002", "7003"]
    assert list(lua.eval("PROGRESS").values()) == ["1/2", "2/2"]


def test_the_pivot_turns_and_scales_with_the_set_it_leads(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    lua.execute(
        f"Furnish.Spawn({rows(lua, 2)}, {ANCHOR}, {{ roll = 0, pitch = 10, turn = 90 }}, 2,"
        " Furnish.Group.Pivot, SEND, {})"
    )
    pivot = "gobject spawn -424242 scale 2 posx 10 posy 20 posz 30 pitch 10 face north turn 90"
    assert sent()[0] == pivot


def test_first_lets_the_first_doodad_lead_and_sends_it_no_join(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 2), "Furnish.Group.First")
    assert sent() == [SPAWN_CHAIR, SPAWN_LAMP, "gobject group add 7001"]
    assert result.leader == "7001" and result.pivot is None


def test_a_guid_group_joins_every_doodad_to_the_object_given(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 2), "333")
    assert sent()[1::2] == ["gobject group add 333", "gobject group add 333"]
    assert result.leader == "333"


def test_none_spawns_loose_objects_several_at_a_time(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 2), "Furnish.Group.None")
    assert sent() == [SPAWN_CHAIR, SPAWN_LAMP]
    assert result.leader is None and len(result.spawned) == 2


def test_a_refused_pivot_makes_the_first_doodad_lead(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua, refuse=424242)
    result = spawn(lua, rows(lua, 2))
    assert sent() == [SPAWN_PIVOT, SPAWN_CHAIR, SPAWN_LAMP, "gobject group add 7001"]
    assert result.leader == "7001" and result.pivot is None
    refused = result.refused[1]
    assert (refused.display, refused.pivot) == (-424242, True)
    assert "doesn't exist" in refused.messages[1]


def test_a_pivot_set_to_an_entry_spawns_that_entry(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Settings.pivot = 20")
    sent = fake_server(lua, refuse=20)
    result = spawn(lua, rows(lua, 2))
    # The setting is what `.gob spawn` takes, so a positive one is an entry, spawned as it is;
    # refused, it is the pivot, whatever doodad shares its number.
    assert sent()[0] == "gobject spawn 20 posx 10 posy 20 posz 30 face north"
    pivot = result.refused[1]
    assert (pivot.display, pivot.pivot) == (20, True)
    assert result.refused[2].pivot is False


def test_a_refused_doodad_is_counted_with_the_servers_words(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_server(lua, refuse=20)
    result = spawn(lua, rows(lua, 2), "Furnish.Group.First")
    assert len(result.spawned) == 1 and result.leader == "7001"
    assert result.refused[1].display == 20
    assert result.refused[1].messages[1] == "the gameobject with displayid -20 doesn't exist"


def test_a_refused_join_stops_the_run_and_is_reported_as_unjoined(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(
        """
        SENT = {}
        NEXT_GUID = 7000
        function SEND(text, callback)
          SENT[#SENT + 1] = text
          if text:match("^gobject spawn") then
            NEXT_GUID = NEXT_GUID + 1
            callback(true, { "|Hgameobject_GUID:" .. NEXT_GUID .. "|h" .. NEXT_GUID .. "|h" })
          else
            callback(false, { "You cannot edit this group." })
          end
        end
        """
    )
    result = spawn(lua, rows(lua, 2), "333")
    # Every join after goes to the same group, so the lamp is not spawned outside it.
    assert list(lua.eval("SENT").values()) == [
        "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north",
        "gobject group add 333",
    ]
    assert result.joinRefused is True and result.aborted is True
    assert len(result.spawned) == 1 and len(result.refused) == 0
    assert [(u.display, u.guid) for u in result.unjoined.values()] == [(20, "7001")]
    assert list(lua.eval("PROGRESS").values()) == ["1/2"]
    assert result.unjoined[1].messages[1] == "You cannot edit this group."


def held_server(lua: lua51.LuaRuntime) -> Callable[[], list[str]]:
    """A send() that holds every reply until ANSWER(n) answers the n-th line sent: a spawn
    with a GUID line, numbered in the order spawns are answered, anything else with success;
    ANSWER(n, success, messages) answers it as given instead."""
    lua.execute(
        """
        SENT, PENDING, NEXT_GUID = {}, {}, 7000
        function SEND(text, callback) SENT[#SENT + 1] = text PENDING[#SENT] = callback end
        function ANSWER(index, ...)
          local callback = PENDING[index]
          PENDING[index] = nil
          if select("#", ...) > 0 then
            callback(...)
          elseif SENT[index]:match("^gobject spawn") then
            NEXT_GUID = NEXT_GUID + 1
            callback(true, { "|Hgameobject_GUID:" .. NEXT_GUID .. "|h" .. NEXT_GUID .. "|h" })
          else
            callback(true, {})
          end
        end
        """
    )
    return lambda: list(lua.eval("SENT").values())


def test_a_guid_group_sends_spawns_and_joins_without_waiting_for_a_reply(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = held_server(lua)
    spawn(lua, rows(lua, 2), "333")
    assert sent() == [SPAWN_CHAIR, "gobject group add 333", SPAWN_LAMP, "gobject group add 333"]


def test_a_word_group_waits_only_for_the_two_that_may_lead(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = held_server(lua)
    spawn(lua, rows(lua, 2))
    # The chair goes with its join, and the join waits for the pivot.
    assert sent() == [SPAWN_PIVOT]
    lua.execute("ANSWER(1)")
    # The lamp's join waits for the chair as well, which would lead had the pivot been
    # refused; nothing waits on the reply to the join before it.
    assert sent() == [SPAWN_PIVOT, SPAWN_CHAIR, "gobject group add 7001"]
    lua.execute("ANSWER(2)")
    assert sent()[3:] == [SPAWN_LAMP, "gobject group add 7001"]


def test_a_reselect_sent_on_a_joins_reply_never_parts_a_spawn_from_its_join(
    tmp_path: Path,
) -> None:
    lua = lua_core(tmp_path)
    sent = held_server(lua)
    # As EpsilonLib does: the reply to a join sends a reselect of the group, which moves the
    # server's selection to the leader.
    lua.execute(
        """
        local answer = ANSWER
        function ANSWER(index)
          local leader = SENT[index]:match("^gobject group add (%d+)")
          if leader then SEND("gobject group sel " .. leader, function() end) end
          answer(index)
        end
        """
    )
    spawn(lua, rows(lua, 2))
    lua.execute("ANSWER(1); ANSWER(3); ANSWER(2)")
    lines = sent()
    assert "gobject group sel 7001" in lines
    assert all(
        lines[i - 1].startswith("gobject spawn")
        for i, line in enumerate(lines)
        if line.startswith("gobject group add")
    )


def test_a_join_behind_a_refused_spawn_speaks_for_nobody(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua, refuse=21)
    result = spawn(lua, rows(lua, 2), "333")
    # The lamp's join still goes, and acts on the chair, which is in the group already.
    assert sent() == [SPAWN_CHAIR, "gobject group add 333", SPAWN_LAMP, "gobject group add 333"]
    assert (result.joined, len(result.unjoined)) == (1, 0)
    assert result.refused[1].display == 21


def test_with_both_that_may_lead_refused_the_rest_stand_loose(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Settings.pivot = -20")
    sent = fake_server(lua, refuse=20)
    result = spawn(lua, rows(lua, 2))
    assert not [line for line in sent() if line.startswith("gobject group")]
    assert (result.leader, result.joined, len(result.spawned)) == (None, 0, 1)


def test_a_sets_pieces_are_its_placements_by_the_file_each_draws(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    pieces = lua.eval("Furnish.Rows.Pieces(Furnish.Sets.Pick(900, 1).id)")
    drawn = sorted((p.display, p.file, p.x, p.y, p.z, p.qw, p.scale) for p in pieces.values())
    assert drawn == [(20, 1001, 1.5, -2.0, 0.25, 1.0, 1.0), (21, 1002, 0.0, 0.0, 3.0, 1.0, 0.5)]
    # A display the data names no file for is left out.
    lua.execute(
        "local file = Furnish.Reader.ModelFile function Furnish.Reader.ModelFile(display)"
        " if display == 20 then return nil end return file(display) end"
    )
    pieces = lua.eval("Furnish.Rows.Pieces(Furnish.Sets.Pick(900, 1).id)")
    assert [p.file for p in pieces.values()] == [1002]


#: A model scene that keeps what each actor and the camera were last told, by method. Its field of
#: view is twice atan(0.5) and it is twice as wide as tall, so the vertical half-angle is the
#: narrower, with a tangent of 0.5. Every model is a two-yard cube about its origin, and loads only
#: when LOAD calls it in, as the client calls back.
RECORDING_SCENE = """
ACTORS, CAMERA, TOLD, SCRIPTS, HOOKED, BAND, NOW = {}, {}, {}, {}, {}, {}, 10
GetTime = function() return NOW end
-- The pointer rests on the scene's middle unless a test moves it, with no button or shift held.
GetCursorPosition = function() return 100, 50 end
HELD = {}
IsMouseButtonDown = function(button) return HELD[button] end
IsShiftKeyDown = function() return SHIFT end
local function recorder(into, own)
  return setmetatable(own or {}, { __index = function(_, method)
    return function(_, ...) into[method] = { ... } end
  end })
end
FRAME = {
  SetCameraNearClip = function() end, SetCameraFarClip = function() end,
  CreateCameraFromScene = function() end, EnableMouse = function() end,
  EnableMouseWheel = function() end,
  HookScript = function(_, name, fn) HOOKED[name] = fn end,
  SetScript = function(_, name, fn) SCRIPTS[name] = fn end,
  GetCameraFieldOfView = function() return 2 * math.atan(0.5) end,
  GetWidth = function() return 200 end, GetHeight = function() return 100 end,
  GetEffectiveScale = function() return 1 end,
  GetLeft = function() return 0 end, GetBottom = function() return 0 end,
  GetFrameLevel = function() return 1 end,
  GetActiveCamera = function() return recorder(CAMERA) end,
  CreateActor = function()
    local told = {}
    ACTORS[#ACTORS + 1] = told
    local actor
    actor = recorder(told, {
      SetOnModelLoadedCallback = function(_, fn) told.loaded = fn end,
      GetActiveBoundingBox = function() return -1, -1, -1, 1, 1, 1 end,
    })
    told.actor = actor
    return actor
  end,
}
function LOAD(i) ACTORS[i].loaded(ACTORS[i].actor) end
-- The band is the one frame a scene makes.
CreateFrame = function(_, _, _, template) BAND.template = template return recorder(BAND) end
SAID = function(loaded, total, seconds) TOLD[#TOLD + 1] = { loaded, total, seconds } end
"""


def test_a_scene_lays_each_piece_about_the_centre_in_its_own_scale(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({
          { file = 1, x = 10, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 0.5 },
          { file = 2, x = 0, y = 2, z = 0, qx = 0, qy = 0, qz = 0.70710678, qw = 0.70710678,
            scale = 1 },
        })
        """
    )
    first, second = lua.eval("ACTORS[1]"), lua.eval("ACTORS[2]")
    # The centre is (5, 1, 0), and an actor stands in its own scaled space.
    assert tuple(first.SetPosition.values()) == (10.0, -2.0, 0.0)
    assert tuple(second.SetPosition.values()) == (-5.0, 1.0, 0.0)
    assert (first.SetModelByFileID[1], first.SetScale[1]) == (1, 0.5)
    # A quarter turn about the vertical, read as `.gob spawn` reads it.
    assert second.SetYaw[1] == pytest.approx(math.pi / 2)
    # Drawn again with less, the rest are emptied and hidden.
    lua.execute(
        "SCENE:Draw({ { file = 3, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1,"
        " scale = 1 } })"
    )
    assert lua.eval("ACTORS[2].Hide") is not None
    assert len(lua.eval("ACTORS")) == 2


def test_a_scene_frames_the_sphere_around_its_loaded_models(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({
          { file = 1, x = 10, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 0.5 },
          { file = 2, x = 0, y = 2, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 },
        })
        """
    )
    assert tuple(lua.eval("TOLD[1]").values()) == (0, 2, 0)
    # Nothing loaded leaves the camera unaimed.
    lua.execute("SCENE:Tick()")
    assert lua.eval("CAMERA.SetZoomDistance") is None
    # Both cubes loaded, about the centre (5, 1, 0): one yard either side of (-5, 1, 0), and half a
    # yard either side of (5, -1, 0). The sphere around them reaches the frame's top and bottom.
    lua.execute("NOW = 10.25 LOAD(1) LOAD(2) SCENE:Tick()")
    low, high = (-6, -1.5, -1), (5.5, 2, 1)
    radius = math.dist(low, high) / 2
    assert tuple(lua.eval("CAMERA.SetTarget").values()) == pytest.approx((-0.25, 0.25, 0))
    distance = lua.eval("CAMERA.SetZoomDistance[1]")
    assert distance == pytest.approx(radius / math.sin(math.atan(0.5)))
    assert tuple(lua.eval("TOLD[#TOLD]").values()) == (2, 2, 0.25)
    # The camera scene's drift as it zooms is taken out, and a load counts once.
    assert tuple(lua.eval("CAMERA.SetTargetSpline").values()) == ()
    lua.execute("LOAD(2) SCENE:Tick()")
    assert lua.eval("SCENE.loaded") == 2


def test_once_the_wheel_has_turned_a_load_leaves_the_camera_be(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({
          { file = 1, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 },
          { file = 2, x = 30, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 },
        })
        LOAD(1) SCENE:Tick()
        """
    )
    framed = lua.eval("CAMERA.SetZoomDistance[1]")
    # The pointer rests where no piece is, so the step is of the framed distance.
    lua.execute("GetCursorPosition = function() return 0, 100 end SCRIPTS.OnMouseWheel(FRAME, 1)")
    assert lua.eval("CAMERA.SetZoomDistance[1]") == pytest.approx(framed * 0.88)
    # The second, far piece loading would widen the frame, but the player has zoomed.
    lua.execute("LOAD(2) SCENE:Tick()")
    assert lua.eval("CAMERA.SetZoomDistance[1]") == pytest.approx(framed * 0.88)
    assert tuple(lua.eval("TOLD[#TOLD]").values())[:2] == (2, 2)
    # Zooming in stops only where the camera stops drawing.
    lua.execute("for _ = 1, 200 do SCRIPTS.OnMouseWheel(FRAME, 1) end")
    assert lua.eval("CAMERA.SetZoomDistance[1]") == pytest.approx(0.01)


def view_axes(lua: lua51.LuaRuntime) -> tuple[tuple[float, ...], tuple[float, ...]]:
    """The scene's view right and up, as SCENE:Axes gives them."""
    axes = lua.eval("{ SCENE:Axes() }")
    values = tuple(axes.values())
    return values[:3], values[3:]


def forward(yaw: float, pitch: float) -> tuple[float, float, float]:
    """Where the client's orbit camera looks, as Vector3D_CalculateNormalFromYawPitch has it."""
    return (math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch))


def test_the_view_axes_are_square_and_right_is_east_looking_north(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute("SCENE = Furnish.Scene.New(FRAME, SAID)")
    right, up = view_axes(lua)
    ahead = forward(math.radians(225), math.radians(35))
    square = (math.sumprod(right, ahead), math.sumprod(up, ahead), math.sumprod(right, up))
    assert square == pytest.approx((0, 0, 0))
    assert up[2] > 0
    # Looking north, level: right is east, which is -y, and up is up.
    lua.execute("SCENE.yaw, SCENE.pitch = 0, 0")
    right, up = view_axes(lua)
    assert right == pytest.approx((0, -1, 0))
    assert up == pytest.approx((0, 0, 1))


def test_the_wheel_grabs_the_piece_under_the_pointer_at_its_depth(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({ { file = 1, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 } })
        LOAD(1) SCENE:Tick()
        """
    )
    framed = lua.eval("CAMERA.SetZoomDistance[1]")
    # Off the cube, nothing is grabbed: the camera turns about the same point, as far off.
    lua.execute("GetCursorPosition = function() return 0, 100 end SCENE:Grab()")
    assert (lua.eval("SCENE.zoom"), tuple(lua.eval("SCENE.centre").values())) == (1, (0, 0, 0))
    # Through the middle of the view the ray meets the cube's corner faces first, nearest the
    # camera along the view: the point the camera turns about moves there, and the step zooms from
    # it.
    lua.execute("GetCursorPosition = function() return 100, 50 end SCRIPTS.OnMouseWheel(FRAME, 1)")
    ahead = forward(math.radians(225), math.radians(35))
    reach = 1 / abs(ahead[0])
    assert tuple(lua.eval("CAMERA.SetTarget").values()) == pytest.approx(
        tuple(-a * reach for a in ahead)
    )
    assert lua.eval("CAMERA.SetZoomDistance[1]") == pytest.approx((framed - reach) * 0.88)


def test_the_piece_under_the_pointer_is_marked_and_named(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        HOVERS = {}
        SCENE = Furnish.Scene.New(FRAME, SAID, function(piece)
          HOVERS[#HOVERS + 1] = piece and piece.file or false
        end)
        SCENE:Draw({ { file = 7, display = 70, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1,
          scale = 1 } })
        LOAD(1) SCENE:Tick(0)
        """
    )
    # Not looked for until the pointer is on the scene.
    assert lua.eval("ACTORS[1].SetSpellVisualKit") is None
    # On the scene's middle the pointer is on the cube, which takes the edge glow and is named.
    lua.execute("HOOKED.OnEnter() SCENE:Tick(0)")
    assert tuple(lua.eval("ACTORS[1].SetSpellVisualKit").values()) == (87979, False)
    assert lua.eval("HOVERS[#HOVERS]") == 7
    # Off the cube, the kit comes off and what it painted is cleared, and the name goes.
    lua.execute("GetCursorPosition = function() return 0, 100 end SCENE:Tick(0)")
    assert tuple(lua.eval("ACTORS[1].SetSpellVisualKit").values()) == ()
    assert lua.eval("ACTORS[1].ClearAllEffects") is not None
    assert lua.eval("HOVERS[#HOVERS]") is False
    # On a client whose actors lack the clearing method, the model is loaded afresh where it
    # stood instead, back on the cube and then off the scene altogether.
    lua.execute(
        "GetCursorPosition = function() return 100, 50 end SCENE:Tick(0)"
        " rawset(ACTORS[1].actor, 'ClearAllEffects', false)"
        " ACTORS[1].SetModelByFileID, ACTORS[1].SetPosition = nil, nil HOOKED.OnLeave()"
    )
    assert tuple(lua.eval("ACTORS[1].SetModelByFileID").values()) == (7,)
    assert tuple(lua.eval("ACTORS[1].SetPosition").values()) == (0, 0, 0)
    assert lua.eval("HOVERS[#HOVERS]") is False


def hovered_of(lua: lua51.LuaRuntime, pieces: str) -> int:
    """Draw the pieces, load them all, put the pointer on the middle of the view, and answer the
    file of the piece it is on."""
    lua.execute(RECORDING_SCENE)
    lua.execute(
        f"""
        HOVERS = {{}}
        SCENE = Furnish.Scene.New(FRAME, SAID, function(piece)
          HOVERS[#HOVERS + 1] = piece and piece.file or false
        end)
        SCENE:Draw({{ {pieces} }})
        for i = 1, #ACTORS do LOAD(i) end
        SCENE:Tick(0)
        HOOKED.OnEnter() SCENE:Tick(0)
        """
    )
    hovered: int = lua.eval("HOVERS[#HOVERS]")
    return hovered


def piece_at(file: int, at: tuple[float, float, float], scale: float) -> str:
    """A piece as Rows.Pieces gives one, unturned, for a scene test."""
    x, y, z = at
    return (
        f"{{ file = {file}, display = {file}, x = {x}, y = {y}, z = {z},"
        f" qx = 0, qy = 0, qz = 0, qw = 1, scale = {scale} }},"
    )


def test_a_piece_standing_in_another_is_the_one_pointed_at(tmp_path: Path) -> None:
    # A jar at the middle of a shelf, inside the shelf's box: the ray meets the shelf's box first,
    # but the pointer is on the jar.
    lua = lua_core(tmp_path)
    assert hovered_of(lua, piece_at(1, (0, 0, 0), 1) + piece_at(2, (0, 0, 0), 0.2)) == 2


def test_a_piece_only_behind_another_is_not_pointed_at(tmp_path: Path) -> None:
    # A small piece further along the view than a cube, its middle outside the cube's box: the
    # cube, nearer, is what the pointer is on.
    lua = lua_core(tmp_path)
    ahead = forward(math.radians(225), math.radians(35))
    behind = tuple(3 * a for a in ahead)
    assert hovered_of(lua, piece_at(1, (0, 0, 0), 1) + piece_at(2, behind, 0.2)) == 1


#: A pinhole projection for the stub scene, wider than its field of view claims: a tangent of 0.8
#: up from the middle to the top edge where GetCameraFieldOfView says 0.5. It answers in pixels
#: from the scene's bottom left, as the client's does, from the scene's own camera.
WIDER_LENS = """
function FRAME:Project3DPointTo2D(x, y, z)
  local s = SCENE
  local fx = math.cos(s.pitch) * math.cos(s.yaw)
  local fy = math.cos(s.pitch) * math.sin(s.yaw)
  local fz = -math.sin(s.pitch)
  local rx, ry, rz, ux, uy, uz = s:Axes()
  local d = s.distance * s.zoom
  local vx = x - (s.centre[1] - fx * d)
  local vy = y - (s.centre[2] - fy * d)
  local vz = z - (s.centre[3] - fz * d)
  local depth = vx * fx + vy * fy + vz * fz
  if depth <= 0 then return nil end
  local k = 50 / 0.8
  local across, up = vx * rx + vy * ry + vz * rz, vx * ux + vy * uy + vz * uz
  return 100 + k * across / depth, 50 + k * up / depth
end
"""


def test_the_pointer_is_read_through_the_scene_s_own_projection(tmp_path: Path) -> None:
    # Two small pieces apart, the scene wider than its field of view says: the pointer put where
    # the projection draws the second is on the second, which a ray built from the claimed field
    # of view would miss.
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(WIDER_LENS)
    lua.execute(
        f"""
        HOVERS = {{}}
        SCENE = Furnish.Scene.New(FRAME, SAID, function(piece)
          HOVERS[#HOVERS + 1] = piece and piece.file or false
        end)
        SCENE:Draw({{ {piece_at(1, (0, 0, 0), 0.1)} {piece_at(2, (0, 6, 0), 0.1)} }})
        LOAD(1) LOAD(2) SCENE:Tick(0)
        """
    )
    x, y = lua.eval("{ FRAME:Project3DPointTo2D(unpack(SCENE.boxes[2].centre)) }").values()
    lua.execute(
        f"GetCursorPosition = function() return {x}, {y} end HOOKED.OnEnter() SCENE:Tick(0)"
    )
    assert lua.eval("HOVERS[#HOVERS]") == 2
    # And the framing reads the same projection: the sphere fits the wider view.
    radius = math.dist((-0.1, -0.1, -0.1), (0.1, 6.1, 0.1)) / 2
    assert lua.eval("SCENE.distance") == pytest.approx(radius / math.sin(math.atan(0.8)))


def test_a_click_chooses_the_piece_under_the_pointer_alone(tmp_path: Path) -> None:
    lua = core_scene_choosing(tmp_path)
    click(lua)
    assert chosen(lua) == [7] and lua.eval("TOLD_CHOSEN") == 1
    # Chosen, the cube stays lit once the pointer leaves it.
    lua.execute("GetCursorPosition = function() return 0, 100 end SCENE:Tick(0)")
    assert tuple(lua.eval("ACTORS[1].SetSpellVisualKit").values()) == (87979, False)
    assert lua.eval("ACTORS[1].ClearAllEffects") is None
    # A click on nothing chooses none, and the light goes out.
    click(lua)
    assert chosen(lua) == [] and lua.eval("TOLD_CHOSEN") == 2
    assert tuple(lua.eval("ACTORS[1].SetSpellVisualKit").values()) == ()
    # A press dragged away before it is let go turns the camera, and chooses nothing.
    lua.execute("GetCursorPosition = function() return PRESS[1], PRESS[2] end SCENE:Tick(0)")
    lua.execute(
        "SCRIPTS.OnMouseDown(FRAME, 'LeftButton')"
        " GetCursorPosition = function() return 110, 50 end SCRIPTS.OnMouseUp(FRAME, 'LeftButton')"
    )
    assert chosen(lua) == [] and lua.eval("TOLD_CHOSEN") == 2


def test_a_shift_click_chooses_a_piece_too_and_again_lets_it_go(tmp_path: Path) -> None:
    lua = core_scene_choosing(tmp_path, piece_at(8, (0, 6, 0), 1))
    lua.execute("SHIFT = true")
    click(lua)
    on_second = lua.eval("{ FRAME:Project3DPointTo2D(unpack(SCENE.boxes[2].centre)) }")
    x, y = on_second.values()
    lua.execute(f"GetCursorPosition = function() return {x}, {y} end SCENE:Tick(0)")
    click(lua)
    assert chosen(lua) == [7, 8]
    # Shift-clicked again, a chosen piece is let go, the first keeping its place; under the
    # pointer still, it goes dark, so the letting go shows, and lights again once the pointer
    # comes back to it.
    click(lua)
    assert chosen(lua) == [7]
    assert tuple(lua.eval("ACTORS[2].SetSpellVisualKit").values()) == ()
    lua.execute("GetCursorPosition = function() return 0, 100 end SCENE:Tick(0)")
    lua.execute(f"GetCursorPosition = function() return {x}, {y} end SCENE:Tick(0)")
    assert tuple(lua.eval("ACTORS[2].SetSpellVisualKit").values()) == (87979, False)
    # Clicked without shift, the second stands alone.
    lua.execute("SHIFT = nil")
    click(lua)
    assert chosen(lua) == [8]
    # A drawing lets everything go.
    lua.execute(f"SCENE:Draw({{ {piece_at(7, (0, 0, 0), 1)} }})")
    assert chosen(lua) == [] and lua.eval("rawget(ACTORS[2].actor, 'chosen')") is None


def test_a_shift_drag_chooses_every_piece_whose_middle_its_band_holds(tmp_path: Path) -> None:
    lua = core_scene_choosing(tmp_path, piece_at(8, (0, 6, 0), 1), piece_at(9, (0, -6, 0), 1))
    # A press with shift at the first cube's middle, dragged just past the second's, stretches
    # the band over the scene as it goes, and lets no drag turn the camera.
    x0, y0 = lua.eval("PRESS").values()
    second = lua.eval("{ FRAME:Project3DPointTo2D(unpack(SCENE.boxes[2].centre)) }")
    x, y = second.values()
    far_x, far_y = x + math.copysign(2, x - x0), y + math.copysign(2, y - y0)
    lua.execute(
        f"""
        SHIFT, HELD.LeftButton = true, true
        SCRIPTS.OnMouseDown(FRAME, 'LeftButton')
        GetCursorPosition = function() return {far_x}, {far_y} end
        SCENE:Tick(0)
        """
    )
    assert lua.eval("SCENE.dragged") is None and lua.eval("BAND.Show") is not None
    width, height = abs(far_x - x0), abs(far_y - y0)
    assert tuple(lua.eval("BAND.SetSize").values()) == pytest.approx((width, height))
    # The band chooses as it goes: the first two cubes are chosen already, in the order drawn, and
    # the third, outside, is not; drawn back short of the second, it lets the second go again.
    assert chosen(lua) == [7, 8]
    lua.execute(f"GetCursorPosition = function() return {x0 + (far_x - x0) / 8}, {y0} end")
    lua.execute("SCENE:Tick(0)")
    assert chosen(lua) == [7]
    lua.execute(f"GetCursorPosition = function() return {far_x}, {far_y} end SCENE:Tick(0)")
    # Let go, the band is read once more where it ends.
    lua.execute("BAND.Hide = nil HELD.LeftButton = nil SCENE:Tick(0)")
    assert chosen(lua) == [7, 8] and lua.eval("BAND.Hide") is not None
    assert tuple(lua.eval("ACTORS[2].SetSpellVisualKit").values()) == (87979, False)
    assert lua.eval("ACTORS[3].SetSpellVisualKit") is None


def test_a_bands_pieces_come_in_the_order_drawn_whatever_loaded_first(tmp_path: Path) -> None:
    lua = core_scene_choosing(tmp_path, piece_at(8, (0, 6, 0), 1), backwards=True)
    # The press is on the first box, the second cube's; the band is drawn past the first cube's.
    x0, y0 = lua.eval("PRESS").values()
    x, y = lua.eval("{ FRAME:Project3DPointTo2D(unpack(SCENE.boxes[2].centre)) }").values()
    far_x, far_y = x + math.copysign(2, x - x0), y + math.copysign(2, y - y0)
    lua.execute(
        f"""
        SHIFT, HELD.LeftButton = true, true
        SCRIPTS.OnMouseDown(FRAME, 'LeftButton')
        GetCursorPosition = function() return {far_x}, {far_y} end
        SCENE:Tick(0)
        """
    )
    # The second cube loaded first and so holds the first box, but the first drawn leads.
    assert lua.eval("SCENE.boxes[1].actor.source.file") == 8
    assert chosen(lua) == [7, 8]


def core_scene_choosing(tmp_path: Path, *more: str, backwards: bool = False) -> lua51.LuaRuntime:
    """A scene of a cube at the origin, and any more given, projected as the scene's own lens
    would, the pointer on the first cube, counting how often what is chosen is told; the models
    load in the order drawn, or the last first."""
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(WIDER_LENS)
    loads = (
        "for i = #ACTORS, 1, -1 do LOAD(i) end"
        if backwards
        else "for i = 1, #ACTORS do LOAD(i) end"
    )
    lua.execute(
        f"""
        TOLD_CHOSEN = 0
        SCENE = Furnish.Scene.New(FRAME, SAID, nil, function() TOLD_CHOSEN = TOLD_CHOSEN + 1 end)
        SCENE:Draw({{ {piece_at(7, (0, 0, 0), 1)} {"".join(more)} }})
        {loads}
        SCENE:Tick(0)
        PRESS = {{ FRAME:Project3DPointTo2D(unpack(SCENE.boxes[1].centre)) }}
        GetCursorPosition = function() return PRESS[1], PRESS[2] end
        HOOKED.OnEnter() SCENE:Tick(0)
        """
    )
    return lua


def click(lua: lua51.LuaRuntime) -> None:
    """A press let go where it was made."""
    lua.execute("SCRIPTS.OnMouseDown(FRAME, 'LeftButton') SCRIPTS.OnMouseUp(FRAME, 'LeftButton')")


def chosen(lua: lua51.LuaRuntime) -> list[int]:
    """The files of the pieces chosen, in the order chosen."""
    return [piece.file for piece in lua.eval("SCENE:Chosen()").values()]


def test_a_held_rotate_button_turns_and_reset_reframes(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        HELD = { LeftButton = true }
        IsMouseButtonDown = function(button) return HELD[button] end
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({ { file = 1, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 } })
        LOAD(1) SCENE:Tick(0)
        """
    )
    framed = lua.eval("CAMERA.SetZoomDistance[1]")
    # Half a second held turns a quarter of a turn, then letting go stops it.
    lua.execute("SCENE:Spin(1) SCENE:Tick(0.5) HELD.LeftButton = nil SCENE:Tick(0.5)")
    assert lua.eval("CAMERA.SetYaw[1]") == pytest.approx(math.radians(225) + math.pi / 2)
    assert lua.eval("SCENE.spin") is None
    lua.execute("SCRIPTS.OnMouseWheel(FRAME, 1) SCENE:Reset()")
    assert lua.eval("CAMERA.SetYaw[1]") == pytest.approx(math.radians(225))
    assert lua.eval("CAMERA.SetZoomDistance[1]") == pytest.approx(framed)


def test_a_right_or_middle_drag_pans_and_the_pieces_follow_the_pointer(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    lua.execute(
        """
        CURSOR, HELD = { 100, 100 }, {}
        GetCursorPosition = function() return CURSOR[1], CURSOR[2] end
        IsMouseButtonDown = function(button) return HELD[button] end
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({
          { file = 1, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 },
          { file = 2, x = 30, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 },
        })
        LOAD(1) SCENE:Tick()
        """
    )
    centre = tuple(lua.eval("CAMERA.SetTarget").values())
    distance = lua.eval("CAMERA.SetZoomDistance[1]")
    for button in ("RightButton", "MiddleButton"):
        lua.execute(
            f"HELD.{button} = true SCRIPTS.OnMouseDown(FRAME, '{button}')"
            " CURSOR[1] = CURSOR[1] + 10 SCENE:Tick()"
            f" HELD.{button} = nil SCENE:Tick()"
        )
    # Twenty pixels right, at a view one framed distance tall over a hundred pixels: what the
    # camera looks at moves against the view's right, so the pieces move with the pointer.
    right = view_axes(lua)[0]
    moved = tuple(lua.eval("CAMERA.SetTarget").values())
    step = 20 * distance / 100
    assert moved == pytest.approx(tuple(c - r * step for c, r in zip(centre, right, strict=True)))
    assert lua.eval("SCENE.dragged") is None
    # Panned, a load leaves the camera where the player put it.
    lua.execute("LOAD(2) SCENE:Tick()")
    assert tuple(lua.eval("CAMERA.SetTarget").values()) == pytest.approx(moved)


def test_the_wheel_zooms_toward_the_point_under_the_pointer(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(RECORDING_SCENE)
    # Nothing loaded, so there is no piece to grab and the camera stands as it began.
    lua.execute(
        """
        SCENE = Furnish.Scene.New(FRAME, SAID)
        SCENE:Draw({ { file = 1, x = 0, y = 0, z = 0, qx = 0, qy = 0, qz = 0, qw = 1, scale = 1 } })
        """
    )
    centre, distance = (0, 0, 0), lua.eval("SCENE.distance")
    # At the scene's middle the wheel zooms straight in.
    lua.execute("SCRIPTS.OnMouseWheel(FRAME, 1)")
    assert tuple(lua.eval("CAMERA.SetTarget").values()) == pytest.approx(centre)
    # Fifty pixels right of the middle, the point there is approached by the twelfth the step
    # takes off: fifty pixels at the view's scale then, along the view's right.
    lua.execute("GetCursorPosition = function() return 150, 50 end SCRIPTS.OnMouseWheel(FRAME, 1)")
    nearer = distance * 0.88
    shift = 50 * nearer / 100 * (1 - 0.88)
    right = view_axes(lua)[0]
    aimed = tuple(lua.eval("CAMERA.SetTarget").values())
    assert aimed == pytest.approx(tuple(c + r * shift for c, r in zip(centre, right, strict=True)))


def test_rows_from_two_sets_spawn_as_one_collection(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 1, 2), "Furnish.Group.None")
    assert len(sent()) == 3 and result.total == 3


def test_the_kernel_refuses_bad_values_by_name(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_server(lua)
    refuse = lua.eval(
        "function(rows, position, rotation, scale, group)"
        " local _, why = Furnish.Spawn(rows, position, rotation, scale, group, SEND) return why end"
    )
    good = lua.eval(rows(lua, 2))
    position = lua.eval(ANCHOR)
    assert (
        refuse(lua.table(), position, None, None, "pivot") == "nothing to spawn: the rows are empty"
    )
    assert (
        refuse(good, lua.table(x=1), None, None, "pivot") == "the anchor position needs x, y and z"
    )
    assert refuse(good, position, None, -1, "pivot").startswith("the anchor scale must be")
    assert refuse(good, position, None, None, "chair").startswith("the group must be")
    assert refuse(good, position, "west", None, "pivot").startswith("the anchor rotation is")
    assert lua.eval(
        'select(2, Furnish.Spawn({ { display = 1 } }, { x = 0, y = 0, z = 0 }, nil, nil, "pivot"))'
    ) == ("send must be the function that delivers a command")


def test_an_abort_with_cleanup_deletes_what_was_spawned(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    # A server that answers nothing until asked, so the run can be aborted mid-way.
    held_server(lua)
    spawn(lua, rows(lua, 2))
    lua.execute('ANSWER(1, true, { "|Hgameobject_GUID:7001|h7001|h" })')
    lua.execute("HANDLE.Abort(true)")
    # Out at the abort: the chair and its join. The lamp went with its join, which waited
    # for the chair, so neither goes; the rest answer, and then everything spawned is deleted.
    lua.execute('ANSWER(2, true, { "|Hgameobject_GUID:7002|h7002|h" })')
    lua.execute("ANSWER(3, true, {})")
    sent = list(lua.eval("SENT").values())
    assert sent[:3] == [SPAWN_PIVOT, SPAWN_CHAIR, "gobject group add 7001"]
    assert sent[3:] == ["gobject delete 7001", "gobject delete 7002"]
    lua.execute("ANSWER(4, true, {}); ANSWER(5, true, {})")
    result = lua.eval("RESULT")
    assert result.aborted is True and result.deleted == 2 and lua.eval("HANDLE.Done()") is True


def cleanup_after_two(lua: lua51.LuaRuntime) -> None:
    """A run one command wide, stopped with a cleanup once the pivot and the chair stand."""
    held_server(lua)
    lua.execute(
        f"""
        Furnish.Settings.inFlight = 1
        RESULT, DELETING = nil, {{}}
        HANDLE = Furnish.Spawn({rows(lua, 2)}, {ANCHOR}, nil, nil, Furnish.Group.Pivot, SEND, {{
          deleting = function(done, total) DELETING[#DELETING + 1] = done .. "/" .. total end,
          finished = function(result) RESULT = result end,
        }})
        ANSWER(1)
        ANSWER(2)
        HANDLE.Abort(true)
        ANSWER(3)
        """
    )


def test_a_cleanup_deletes_at_the_runs_width_and_the_run_is_done_when_it_ends(
    tmp_path: Path,
) -> None:
    lua = lua_core(tmp_path)
    cleanup_after_two(lua)
    # One wide, as the run was: the chair waits for the pivot's delete to answer.
    assert list(lua.eval("SENT").values())[3:] == ["gobject delete 7001"]
    assert lua.eval("HANDLE.Done()") is False and lua.eval("RESULT") is None
    lua.execute("ANSWER(4)")
    assert list(lua.eval("SENT").values())[3:] == ["gobject delete 7001", "gobject delete 7002"]
    assert lua.eval("HANDLE.Done()") is False
    lua.execute("ANSWER(5)")
    assert list(lua.eval("DELETING").values()) == ["0/2", "1/2", "2/2"]
    assert lua.eval("RESULT.deleted") == 2 and lua.eval("HANDLE.Done()") is True


def test_an_abort_while_deleting_sends_no_more_deletes(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    cleanup_after_two(lua)
    lua.execute("HANDLE.Abort()")
    lua.execute("ANSWER(4)")
    assert list(lua.eval("SENT").values())[3:] == ["gobject delete 7001"]
    assert lua.eval("RESULT.deleted") == 1 and lua.eval("HANDLE.Done()") is True


# -- Chat -------------------------------------------------------------------------------


def test_chat_counts_a_run_by_quarters_and_a_long_one_by_tenths(tmp_path: Path) -> None:
    stride = lua_core(tmp_path).eval("Furnish.Chat.Stride")
    said = {}
    for total in (10, 11, 40, 100, 500, 501, 9931):
        # The lines a run says on its way, as the console counts them: one each stride, the
        # last object left to the line that ends the run.
        step, told, lines = stride(total), 0, 0
        for done in range(1, total):
            if done - told >= step:
                told, lines = done, lines + 1
        said[total] = lines
    assert said == {10: 0, 11: 1, 40: 3, 100: 3, 500: 3, 501: 9, 9931: 9}


# -- Settings ---------------------------------------------------------------------------


def test_settings_are_restored_from_the_saved_copy_and_then_are_it(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute('FurnishSettings = { pivot = 9653, inFlight = "yes", stray = 1 }')
    lua.execute('FIRE("ADDON_LOADED", "Furnish")')
    settings = lua.eval("Furnish.Settings")
    # The pivot is taken; a value of the wrong type and a key the defaults lack are not.
    assert (settings.pivot, settings.inFlight) == (9653, 4)
    assert settings.stray is None
    assert lua.eval("FurnishSettings == Furnish.Settings") is True
    lua.execute("Furnish.Settings.inFlight = 2")
    assert lua.eval("FurnishSettings.inFlight") == 2


@pytest.mark.parametrize(
    ("saved", "kept"),
    [
        ("pivot = 0", "pivot = -424242"),
        ("pivot = 2.5", "pivot = -424242"),
        ("inFlight = 0", "inFlight = 4"),
        ("inFlight = 99", "inFlight = 4"),
        ("inFlight = 16", "inFlight = 16"),
    ],
)
def test_a_saved_number_out_of_its_bounds_is_not_restored(
    tmp_path: Path, saved: str, kept: str
) -> None:
    lua = lua_core(tmp_path)
    lua.execute(f"FurnishSettings = {{ {saved} }}")
    lua.execute('FIRE("ADDON_LOADED", "Furnish")')
    key, value = kept.split(" = ")
    assert lua.eval(f"Furnish.Settings.{key}") == float(value)


def test_settings_stand_on_their_defaults_with_nothing_saved(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute('FIRE("ADDON_LOADED", "Furnish")')
    assert lua.eval("FurnishSettings == Furnish.Settings") is True
    assert lua.eval("Furnish.Settings.pivot") == -424242


def test_a_display_saved_as_the_old_marker_is_not_read_as_the_pivot(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    # A positive display under the old name would be an entry under the new one.
    lua.execute("FurnishSettings = { marker = 9653 }")
    lua.execute('FIRE("ADDON_LOADED", "Furnish")')
    assert lua.eval("Furnish.Settings.pivot") == -424242
    assert lua.eval("Furnish.Settings.marker") is None


# -- Providers --------------------------------------------------------------------------


def fake_client(lua: lua51.LuaRuntime) -> None:
    """EpsilonLib and C_Epsilon as the providers see them: the records of three objects, which
    one is selected or whether a group is, permission to spawn, the player's position, and a
    server that selects what it is asked to select."""
    lua.execute(
        """
        RECORDS = {
          [500] = { guid = "500", fileID = 900, name = "world/wmo/house.wmo\\r", scale = 2,
                    transform = { position = { x = 10, y = 20, z = 30 },
                                  rotation = { x = 0, y = 0, z = 90 } },
                    groupLeader = 0, canEdit = true, IsWMO = function() return true end },
          [501] = { guid = "501", fileID = 777, name = "world/wmo/emptywmo_house.wmo", scale = 1,
                    transform = { position = { x = 0, y = 0, z = 0 },
                                  rotation = { x = 0, y = 0, z = 0 } },
                    orientation = math.pi, groupLeader = 333, canEdit = true,
                    IsWMO = function() return true end },
          [502] = { guid = "502", fileID = 1, name = "world/prop/chair.m2", scale = 1,
                    transform = { position = { x = 0, y = 0, z = 0 },
                                  rotation = { x = 0, y = 0, z = 0 } },
                    groupLeader = 0, canEdit = false, IsWMO = function() return false end },
        }
        SELECTED, GROUP_LEADER = nil, nil
        EpsilonLib = {
          GameObject = {
            IsGroupSelected = function() return SELECTED == "group" end,
            GetSelected = function()
              if SELECTED == "group" then
                return { isGroup = true, leaderGUID = GROUP_LEADER }
              end
              return RECORDS[SELECTED]
            end,
            CanSpawn = function(vocal)
              if NO_PERMISSION and vocal then
                print("You do not have permission to spawn objects here.")
              end
              return not NO_PERMISSION
            end,
          },
          AddonCommands = { Register = function() return SEND end },
        }
        C_Timer = { After = function(_, fn) fn() end }
        C_Epsilon = {
          GetPosition = function() return 1, 2, 3, 1116 end,
        }
        function GetPlayerFacing() return math.pi / 2 end
        CLOCK = 0
        function GetTime() return CLOCK end
        """
    )
    fake_server(lua)
    lua.execute(
        """
        local plain = SEND
        function SEND(text, callback)
          local guid = text:match("^gobject select (%d+)")
          local leader = text:match("^gobject group select (%d+)")
          if guid then
            SENT[#SENT + 1] = text
            SELECTED = tonumber(guid)
            return callback(true, {})
          end
          if leader then SELECTED, GROUP_LEADER = "group", tonumber(leader) end
          plain(text, callback)
        end
        """
    )


def test_pose_selected_reads_the_record_and_never_selects(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_client(lua)
    lua.execute("SELECTED = 500")
    pose = lua.eval("Furnish.Pose.Selected()")
    assert (pose.position.x, pose.position.y, pose.position.z, pose.scale) == (10, 20, 30, 2)
    assert (pose.rotation.turn, pose.guid, pose.file, pose.name, pose.wmo) == (
        90,
        500,
        900,
        "house",
        True,
    )
    lua.execute("SELECTED = 501")
    pose = lua.eval("Furnish.Pose.Selected()")
    assert pose.groupLeader == 333 and round(pose.rotation.turn) == 180
    assert lua.eval("Furnish.Sets.IsBlank")(pose.file) is True
    assert lua.eval("Furnish.Sets.IsBlank")(HOUSE) is False
    lua.execute("SELECTED = nil")
    assert lua.eval("select(2, Furnish.Pose.Selected())") == "no object is selected"
    lua.execute("SELECTED = 'group'")
    assert lua.eval("select(2, Furnish.Pose.Selected())") == "a group is selected, not one object"
    assert list(lua.eval("SENT").values()) == []


def test_pose_here_reads_the_servers_position_and_the_facing(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_client(lua)
    pose = lua.eval("Furnish.Pose.Here()")
    assert (pose.position.x, pose.position.y, pose.position.z) == (1, 2, 3)
    assert round(pose.rotation.turn) == 90 and pose.scale == 1


def test_an_entry_resolves_from_the_data(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    assert lua.eval("Furnish.Sets.OfEntry(817579)") == HOUSE
    assert lua.eval("select(2, Furnish.Sets.OfEntry(5))") == (
        "entry 5 is no WMO object the data knows, or its root has no doodad sets"
    )


def test_a_map_placement_names_the_sets_its_zone_drew(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    assert list(lua.eval("Furnish.Sets.OfPlacement(1116, 4242)").values()) == [2]
    assert "no map placement 1 on map 1116" in lua.eval(
        "select(2, Furnish.Sets.OfPlacement(1116, 1))"
    )


def test_sets_name_what_a_root_offers_and_what_it_lacks(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sets = lua.eval(f"Furnish.Sets.OfFile({HOUSE})")
    assert [(s.index, s.name, s.count) for s in sets.values()] == [(0, "", 1), (1, "Set_Full", 2)]
    assert lua.eval(f"Furnish.Sets.Pick({HOUSE}, 1)").id == 2
    assert lua.eval(f"select(2, Furnish.Sets.Pick({HOUSE}, 7))") == (
        "root file 900 has no set 7; it has 0, 1 Full"
    )
    assert (
        lua.eval("select(2, Furnish.Sets.OfFile(1))")
        == "the data has no doodad sets for root file 1"
    )


def test_a_fault_is_said_in_chat_once(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("BROKEN = Furnish.Client.Guarded(function() error('the reader broke', 0) end)")
    lua.execute("BROKEN(); BROKEN()")
    faults = [line for line in printed(lua) if "error:" in line]
    red = lua.eval("Furnish.Chat.RED")
    assert faults == [f"|cff66ccffFurnish:|r {red}error: the reader broke|r"]


#: A stand-in for the client's catalogue of gameobject displays: ROWS in the order given, and a
#: search over their names.
CATALOGUE = """
CATALOGUE_READS = 0
C_Epsilon.GODI_Count = function() return #ROWS end
C_Epsilon.GODI_Get = function(i)
  CATALOGUE_READS = CATALOGUE_READS + 1
  return ROWS[i + 1]
end
C_Epsilon.GODI_Search = function(words)
  FOUND = {}
  for _, row in ipairs(ROWS) do
    if row.name:lower():find(words, 1, true) then FOUND[#FOUND + 1] = row end
  end
  return #FOUND
end
C_Epsilon.GODI_RetrieveSearch = function(i) return FOUND[i + 1] end
"""


def test_one_walk_names_the_wanted_files_and_a_second_ask_walks_nothing(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_client(lua)
    lua.execute(
        "ROWS = { { displayid = 20, fileid = 2, name = 'world/b.m2' },"
        " { displayid = 30, fileid = 3, name = '[tag] C.m2\\r' },"
        " { displayid = 10, fileid = 1, name = 'a.m2' } }"
    )
    lua.execute(CATALOGUE)
    lua.execute("DONE = 0; COUNT = function() DONE = DONE + 1 end")
    lua.execute("Furnish.Client.NameFiles({ [3] = true, [9] = true }, COUNT)")
    assert lua.eval("DONE") == 1
    # Named as a player reads it, kept only where wanted, and nil where the catalogue lacks it.
    assert lua.eval("Furnish.Client.FileName(3)") == "c"
    assert lua.eval("Furnish.Client.FileName(2)") is None
    assert lua.eval("Furnish.Client.FileName(9)") is None
    lua.execute("CATALOGUE_READS = 0; Furnish.Client.NameFiles({ [2] = true }, COUNT)")
    assert (lua.eval("CATALOGUE_READS"), lua.eval("DONE")) == (0, 2)


def test_a_set_names_its_models_by_the_files_the_data_carries(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_client(lua)
    lua.execute("ROWS = { { displayid = 99999, fileid = 1001, name = 'world/chair.m2' } }")
    lua.execute(CATALOGUE)
    assert lua.eval("Furnish.Console.ModelName(20)") is None
    lua.execute("Furnish.Console.NameModels(function() end)")
    assert lua.eval("Furnish.Console.ModelName(20)") == "chair"
    assert lua.eval("Furnish.Console.ModelName(21)") is None
