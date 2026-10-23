"""The core in a real Lua 5.1: the placement maths, the command grammar, a run over any series
of commands, the kernel for every way of grouping, and the providers against a stand-in client
whose replies read the way Epsilon's do."""

import math
from collections.abc import Callable
from pathlib import Path
from typing import Any

from lupa import lua51

from furnish.database import Database
from furnish.export import export
from furnish.wmo import Placement

LIBDEFLATE = Path(__file__).parent / "lua" / "LibDeflate.lua"
ADDON = Path(__file__).parents[1] / "addon" / "Furnish"
FILES = (
    "Settings.lua",
    "Reader.lua",
    "Names.lua",
    "Transform.lua",
    "Commands.lua",
    "Run.lua",
    "Kernel.lua",
    "Client.lua",
    "Pose.lua",
    "Sets.lua",
    "Rows.lua",
    "Chat.lua",
    "Console.lua",
    "Command.lua",
)

HOUSE = 900
EMPTY_HOUSE = 777
CHAIR = Placement(1001, (1.5, -2.0, 0.25), (0.0, 0.0, 0.0, 1.0), 1.0)
LAMP = Placement(1002, (0.0, 0.0, 3.0), (0.0, 0.0, 0.0, 1.0), 0.5)
GLOW = Placement(1003, (4.0, 4.0, 1.0), (0.0, 0.0, 0.0, 1.0), 1.0)

ANCHOR = "{ x = 10, y = 20, z = 30 }"
SPAWN_CHAIR = "gobject spawn -20 posx 11.5 posy 18 posz 30.25 face north"
SPAWN_LAMP = "gobject spawn -21 scale 0.5 posx 10 posy 20 posz 33 face north"
SPAWN_MARKER = "gobject spawn -424242 posx 10 posy 20 posz 30 face north"


def write_database(path: Path) -> None:
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
        db.add_map_sets([(1116, 4242, full)])


def lua_core(tmp_path: Path) -> lua51.LuaRuntime:
    write_database(tmp_path / "f.sqlite")
    export(tmp_path / "f.sqlite", tmp_path / "Data.lua")
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(
        """
        LibStub = { libs = {} }
        function LibStub:NewLibrary(name, minor) local lib = {} self.libs[name] = lib return lib end
        function LibStub:GetLibrary(name, silent) return self.libs[name] end
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
        """
    )
    lua.execute(LIBDEFLATE.read_text(encoding="utf-8"))
    lua.globals().DATA_PATH = (tmp_path / "Data.lua").as_posix()
    lua.execute("function LoadAddOn(name) dofile(DATA_PATH) return true end")
    for name in FILES:
        lua.execute((ADDON / name).read_text(encoding="utf-8"))
    lua.execute("Furnish.Settings.marker = 424242")
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
    return "Furnish.Rows.Union(" + ", ".join(f"Furnish.Rows.OfSet({s})" for s in sets) + ")"


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


def printed(lua: lua51.LuaRuntime) -> list[str]:
    return list(lua.eval("PRINTED").values())


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
    lua.execute(
        """
        SENT, PENDING = {}, {}
        function SEND(text, callback) SENT[#SENT + 1] = text PENDING[#SENT] = callback end
        function ANSWER(index) local cb = PENDING[index] PENDING[index] = nil cb(true, {}) end
        """
    )
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


def test_a_second_abort_gives_up_on_the_replies_still_owed(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute(
        """
        SENT, PENDING = {}, {}
        function SEND(text, callback) SENT[#SENT + 1] = text PENDING[#SENT] = callback end
        function ANSWER(index) local cb = PENDING[index] PENDING[index] = nil cb(true, {}) end
        """
    )
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


def test_pivot_spawns_the_marker_first_and_joins_every_doodad_to_it(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 2))
    assert sent() == [
        SPAWN_MARKER,
        SPAWN_CHAIR,
        "gobject group add 7001",
        SPAWN_LAMP,
        "gobject group add 7001",
    ]
    assert (result.leader, result.pivot, result.total) == ("7001", "7001", 2)
    assert list(result.spawned.values()) == ["7001", "7002", "7003"]
    assert list(lua.eval("PROGRESS").values()) == ["1/2", "2/2"]


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


def test_a_refused_marker_makes_the_first_doodad_lead(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua, refuse=424242)
    result = spawn(lua, rows(lua, 2))
    assert sent() == [SPAWN_MARKER, SPAWN_CHAIR, SPAWN_LAMP, "gobject group add 7001"]
    assert result.leader == "7001" and result.pivot is None
    refused = result.refused[1]
    assert refused.display == 424242 and "doesn't exist" in refused.messages[1]


def test_no_marker_setting_spawns_none(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute("Furnish.Settings.marker = nil")
    sent = fake_server(lua)
    spawn(lua, rows(lua, 2))
    assert sent()[0] == SPAWN_CHAIR


def test_a_refused_doodad_is_counted_with_the_servers_words(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    fake_server(lua, refuse=20)
    result = spawn(lua, rows(lua, 2), "Furnish.Group.First")
    assert len(result.spawned) == 1 and result.leader == "7001"
    assert result.refused[1].display == 20
    assert result.refused[1].messages[1] == "the gameobject with displayid -20 doesn't exist"


def test_a_refused_join_is_reported_as_unjoined(tmp_path: Path) -> None:
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
    assert len(result.spawned) == 2 and len(result.refused) == 0
    assert [(u.display, u.guid) for u in result.unjoined.values()] == [(20, "7001"), (21, "7002")]
    assert result.unjoined[1].messages[1] == "You cannot edit this group."


def held_server(lua: lua51.LuaRuntime) -> Callable[[], list[str]]:
    """A send() that holds every reply until ANSWER(n) answers the n-th line sent: a spawn
    with a GUID line, numbered in the order spawns are answered, anything else with success."""
    lua.execute(
        """
        SENT, PENDING, NEXT_GUID = {}, {}, 7000
        function SEND(text, callback) SENT[#SENT + 1] = text PENDING[#SENT] = callback end
        function ANSWER(index)
          local callback = PENDING[index]
          PENDING[index] = nil
          if SENT[index]:match("^gobject spawn") then
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
    # The chair goes before the marker answers; its join waits for the marker alone.
    assert sent() == [SPAWN_MARKER, SPAWN_CHAIR]
    lua.execute("ANSWER(1)")
    # The lamp goes before the chair answers; its join waits for the chair as well, which
    # would lead had the marker been refused.
    assert sent() == [SPAWN_MARKER, SPAWN_CHAIR, "gobject group add 7001", SPAWN_LAMP]
    lua.execute("ANSWER(2)")
    assert sent()[-1] == "gobject group add 7001"


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
    lua.execute("Furnish.Settings.marker = 20")
    sent = fake_server(lua, refuse=20)
    result = spawn(lua, rows(lua, 2))
    assert not [line for line in sent() if line.startswith("gobject group")]
    assert (result.leader, result.joined, len(result.spawned)) == (None, 0, 1)


def test_rows_from_two_sets_spawn_as_one_collection(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    sent = fake_server(lua)
    result = spawn(lua, rows(lua, 1, 2), "Furnish.Group.None")
    assert len(sent()) == 3 and result.total == 3
    thinned = lua.eval(f"#Furnish.Rows.Without({rows(lua, 1, 2)}, 21)")
    assert thinned == 1


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
    lua.execute(
        """
        SENT, PENDING = {}, {}
        function SEND(text, callback) SENT[#SENT + 1] = text PENDING[#SENT] = callback end
        function ANSWER(index, ...) local cb = PENDING[index] PENDING[index] = nil cb(...) end
        """
    )
    spawn(lua, rows(lua, 2))
    lua.execute('ANSWER(1, true, { "|Hgameobject_GUID:7001|h7001|h" })')
    lua.execute("HANDLE.Abort(true)")
    # Out at the abort: the chair, its join and the lamp. The lamp's join waited for the
    # chair's reply and never goes; the rest answer, and then everything spawned is deleted.
    lua.execute('ANSWER(2, true, { "|Hgameobject_GUID:7002|h7002|h" })')
    lua.execute("ANSWER(3, true, {})")
    lua.execute('ANSWER(4, true, { "|Hgameobject_GUID:7003|h7003|h" })')
    sent = list(lua.eval("SENT").values())
    assert sent[:4] == [SPAWN_MARKER, SPAWN_CHAIR, "gobject group add 7001", SPAWN_LAMP]
    assert sent[4:] == ["gobject delete 7001", "gobject delete 7002", "gobject delete 7003"]
    lua.execute("ANSWER(5, true, {}); ANSWER(6, true, {}); ANSWER(7, true, {})")
    result = lua.eval("RESULT")
    assert result.aborted is True and result.deleted == 3 and lua.eval("HANDLE.Done()") is True


# -- Settings ---------------------------------------------------------------------------


def test_settings_are_restored_from_the_saved_copy_and_then_are_it(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute('FurnishSettings = { marker = 9653, inFlight = "yes", stray = 1 }')
    lua.execute('FIRE("ADDON_LOADED", "Furnish")')
    settings = lua.eval("Furnish.Settings")
    # The marker is taken; a value of the wrong type and a key the defaults lack are not.
    assert (settings.marker, settings.inFlight) == (9653, 4)
    assert settings.stray is None
    assert lua.eval("FurnishSettings == Furnish.Settings") is True
    lua.execute("Furnish.Settings.inFlight = 2")
    assert lua.eval("FurnishSettings.inFlight") == 2


def test_settings_stand_on_their_defaults_with_nothing_saved(tmp_path: Path) -> None:
    lua = lua_core(tmp_path)
    lua.execute('FIRE("ADDON_LOADED", "Furnish")')
    assert lua.eval("FurnishSettings == Furnish.Settings") is True
    assert lua.eval("Furnish.Settings.marker") == 424242


# -- Providers --------------------------------------------------------------------------


def fake_client(lua: lua51.LuaRuntime) -> None:
    """EpsilonLib and C_Epsilon as the providers see them: a selection record arrives when an
    object is selected, gobject info answers a display, and the model search knows one root."""
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
        SELECTED = nil
        EpsilonLib = {
          GameObject = {
            IsGroupSelected = function() return SELECTED == "group" end,
            GetSelected = function() return RECORDS[SELECTED] end,
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
          local entry = text:match("^gobject info (%d+)")
          if guid or entry then SENT[#SENT + 1] = text end
          if guid then SELECTED = tonumber(guid) return callback(true, {}) end
          if entry == "817579" then
            return callback(true, { "Entry: |cff00CCFF817579|r",
                                    "Template GameObject DisplayID: |cff00CCFF30262|r" })
          elseif entry then
            return callback(true, { "Template GameObject DisplayID: |cff00CCFF1|r" })
          end
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
    assert (pose.position.x, pose.position.y, pose.position.z, pose.map) == (1, 2, 3, 1116)
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
    faults = [line for line in printed(lua) if "stopped by an error" in line]
    assert faults == ["|cff66ccffFurnish:|r |cffff2020stopped by an error: the reader broke|r"]
