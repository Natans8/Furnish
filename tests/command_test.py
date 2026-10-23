"""The command layer in a real Lua 5.1: what a player types read into requests, the help, the
list and its links, a spawn closed by selecting its group, an import, and stopping, against
the stand-in client the core's tests use."""

from pathlib import Path
from typing import Any

import pytest
from lupa import lua51

from tests.core_test import fake_client, lua_core, printed

PREFIX = "|cff66ccffFurnish:|r "


def command_lua(tmp_path: Path, deferred: bool = False) -> lua51.LuaRuntime:
    """The core with the client stood in, every send logged with whether its reply is shown,
    the import answered, and a selection's record announced the way EpsilonLib announces it.
    Deferred, a reply waits until FLUSH() so a run can be caught in flight."""
    lua = lua_core(tmp_path)
    fake_client(lua)
    lua.globals().DEFERRED = deferred
    lua.execute(
        """
        SHOWN, LISTENERS, PENDING = {}, {}, {}
        EpsilonLib.EventManager = {
          Register = function(_, event, fn)
            local ref = { fn = fn }
            LISTENERS[ref] = true
            return fn, ref
          end,
          Remove = function(_, ref) LISTENERS[ref] = nil end,
        }
        local server = SEND
        local function answer(text, callback)
          if text:match("^doodad import") then
            SENT[#SENT + 1] = text
            local uid, guid = IMPORT_UID or 4242, IMPORT_GUID or 500
            return callback(true, { "Successfully imported [house.wmo - 817579] (UniqueId: "
              .. uid .. ") as GUID " .. guid .. "." })
          end
          if SELECT_REFUSED and text:match("^gobject select") then
            SENT[#SENT + 1] = text
            return callback(false, { "Object not found" })
          end
          server(text, function(ok, messages)
            local guid = text:match("^gobject select (%d+)")
            if guid then
              for ref in pairs(LISTENERS) do
                ref.fn(nil, "EPSILON_OBJ_UPDATE", "EPSILON_OBJ_SEL", RECORDS[tonumber(guid)])
              end
            end
            callback(ok, messages)
          end)
        end
        function SEND(text, callback, shown)
          if shown then SHOWN[#SHOWN + 1] = text end
          callback = callback or function() end
          if DEFERRED then
            PENDING[#PENDING + 1] = function() answer(text, callback) end
          else
            answer(text, callback)
          end
        end
        function FLUSH()
          while #PENDING > 0 do table.remove(PENDING, 1)() end
        end
        function STEP() table.remove(PENDING, 1)() end
        function IsModifiedClick(kind) return MODIFIER == "shift" and kind == "CHATLINK" end
        function IsControlKeyDown() return MODIFIER == "ctrl" end
        """
    )
    return lua


def run(lua: lua51.LuaRuntime, text: str) -> list[str]:
    """Type a command and answer the lines it printed."""
    before = len(printed(lua))
    lua.globals().SlashCmdList.FURNISH(text)
    return printed(lua)[before:]


def sent(lua: lua51.LuaRuntime) -> list[str]:
    return list(lua.eval("SENT").values())


def shown(lua: lua51.LuaRuntime) -> list[str]:
    return list(lua.eval("SHOWN").values())


# -- Reading what is typed ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("typed", "request_"),
    [
        ("", {"action": "window"}),
        ("help me", {"action": "help"}),
        ("list", {"action": "list"}),
        (
            "list 830385 attach base",
            {"action": "list", "entry": 830385, "group": "attach", "base": True},
        ),
        ("3", {"action": "spawn", "index": 3}),
        ("3 from 830385 first", {"action": "spawn", "index": 3, "entry": 830385, "group": "first"}),
        ("3 here", {"action": "spawn", "index": 3, "here": True}),
        (
            "3 HERE 830385 nogroup",
            {"action": "spawn", "index": 3, "here": True, "entry": 830385, "group": "nogroup"},
        ),
        ("import base", {"action": "import", "base": True}),
        ("stop", {"action": "stop", "delete": False}),
        ("stop delete", {"action": "stop", "delete": True}),
    ],
)
def test_what_is_typed_reads_as_a_request(
    tmp_path: Path, typed: str, request_: dict[str, Any]
) -> None:
    lua = lua_core(tmp_path)
    request = lua.eval("Furnish.Command.Parse")(typed)
    assert dict(request) == request_


@pytest.mark.parametrize(
    ("typed", "reason"),
    [
        ("spawn 3", "spawn is not a Furnish command; /furn help shows them"),
        ("3 quickly", "quickly is not a word Furnish knows; /furn help shows them"),
        ("3 first nogroup", "first and nogroup cannot go together; choose one"),
        ("3 base base", "base and base cannot go together; choose one"),
        ("3 from", "from takes an object's entry, as /furn 3 from <entry>"),
        ("3 from 1 here 2", "name the object once, as /furn 3 here <entry>"),
        ("list here", "here follows a set's number, as /furn 3 here"),
        ("stop now", "stop takes delete or nothing: /furn stop delete"),
    ],
)
def test_what_cannot_be_read_says_the_way_out(tmp_path: Path, typed: str, reason: str) -> None:
    lua = lua_core(tmp_path)
    assert lua.eval("select(2, Furnish.Command.Parse(...))", typed) == reason


def test_a_refused_command_is_said_once_with_the_prefix(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "spawn 3") == [PREFIX + "spawn is not a Furnish command; /furn help shows them"]
    assert sent(lua) == []


def test_the_help_names_every_command_and_word(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lines = run(lua, "help")
    assert lines[0] == "|cffffd100Furnish|r|cff9d9d9d spawns a building's doodad sets as objects|r"
    assert lines[1] == "  |cffffd100/furn help|r this help"
    assert lines[2] == "  |cffffd100/furn list|r the selected building's sets"
    assert "  |cffffd100attach|r join the selected object's group" in lines
    assert lines[-2].endswith("click it to spawn it, ctrl-click to spawn it at your feet.|r")
    assert len(lines) == 1 + 10 + 1 + 4 + 2


def test_the_command_alone_is_the_windows(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "") == [PREFIX + "the window is not built yet; /furn help lists the commands"]


# -- Listing -----------------------------------------------------------------------------


def test_a_list_prints_each_set_as_a_link_carrying_the_words(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    assert run(lua, "list attach") == [
        PREFIX + "house has 2 sets:",
        "  |cffffd1000|r |cff71d5ff|Hgarrmission:furnish:900:0:attach::house|h[Base]|h|r "
        "|cff9d9d9d1 object|r",
        "  |cffffd1001|r |cff71d5ff|Hgarrmission:furnish:900:1:attach::house|h[Full]|h|r "
        "|cff9d9d9d2 objects|r",
    ]
    assert run(lua, "list 817579 base")[0] == PREFIX + "object 817579 has 2 sets:"
    assert sent(lua) == []


def test_a_list_refuses_without_a_building(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "list") == [
        PREFIX + "no object is selected; select the building first, as with .gob select"
    ]
    lua.execute("SELECTED = 502")
    assert run(lua, "list") == [
        PREFIX + "chair.m2 is not a building, so it has no sets; "
        "/furn list <entry> lists another object's"
    ]
    assert run(lua, "list 5") == [
        PREFIX
        + "object 5 is not a building Furnish has sets for; check the entry on its lookup line"
    ]


# -- Spawning ----------------------------------------------------------------------------


def test_a_spawn_says_what_it_sends_and_selects_its_group_in_sight(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    lines = run(lua, "1")
    assert lines == [
        PREFIX + "spawning Full (set 1, 2 objects) on house, led by an invisible pivot",
        PREFIX + "done: 2 of 2 spawned",
    ]
    assert sent(lua)[0] == "gobject spawn -424242 posx 10 posy 20 posz 30 face north turn 90"
    assert shown(lua) == ["gobject group select 7001"]


def test_an_ungrouped_spawn_selects_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    assert run(lua, "1 nogroup")[0].endswith("on house, ungrouped")
    assert shown(lua) == []


def test_attach_joins_the_buildings_own_group(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 501")
    assert run(lua, "1 attach")[0].endswith("joining emptywmo_house's group")
    assert "gobject group add 333" in sent(lua)
    assert shown(lua) == ["gobject group select 333"]


def test_an_emptywmo_is_given_the_base_set_it_does_not_draw(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 501")
    line = run(lua, "1 nogroup")[0]
    assert line == (
        PREFIX
        + "spawning Full (set 1, 2 objects and the base set's 1) on emptywmo_house, ungrouped"
    )
    assert [s.split()[2] for s in sent(lua)] == ["-21", "-20", "-21"]


def test_another_objects_set_is_named_by_its_entry(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    assert run(lua, "1 from 817579 nogroup")[0] == (
        PREFIX + "spawning object 817579's Full (set 1, 2 objects) on house, ungrouped"
    )


def test_a_set_at_the_players_feet_needs_no_selection(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "0 here 817579 first")[0] == (
        PREFIX
        + "spawning object 817579's Base (set 0, 1 object) at your feet, led by its first object"
    )
    assert sent(lua) == ["gobject spawn -21 posx -3 posy 6 posz 4 face north turn 90"]


def test_a_spawn_refuses_with_the_way_out(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "1")[0].endswith(
        "no object is selected; select the building first, as with .gob select"
    )
    lua.execute("SELECTED = 'group'")
    assert run(lua, "1")[0].endswith(
        "a group is selected, not one object; select the building first, as with .gob select"
    )
    lua.execute("SELECTED = 500")
    assert run(lua, "7") == [PREFIX + "house has no set 7; /furn list shows its 2"]
    assert run(lua, "7 here 817579") == [
        PREFIX + "object 817579 has no set 7; /furn list 817579 shows its 2"
    ]
    assert sent(lua) == []


def test_a_run_in_flight_blocks_another_and_stops_with_its_objects_deleted(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, deferred=True)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    assert run(lua, "1") == [PREFIX + "Furnish is still spawning; /furn stop ends it"]
    assert run(lua, "stop delete") == [
        PREFIX + "stopping, then deleting what was spawned; "
        "/furn stop again gives up on a reply that never comes"
    ]
    lua.execute("FLUSH()")
    assert printed(lua)[-1] == PREFIX + "stopped, and deleted the 1 object it spawned"
    assert sent(lua)[-1] == "gobject delete 7001"
    assert shown(lua) == []
    assert run(lua, "stop") == [PREFIX + "nothing is spawning"]


# -- Links -------------------------------------------------------------------------------


def link_words(lua: lua51.LuaRuntime, index: int = 1) -> str:
    line = run(lua, "list")[index + 1]
    start = line.index("garrmission:furnish:") + len("garrmission:furnish:")
    return line[start : line.index("|h", start)]


def test_a_click_spawns_on_the_selection_and_ctrl_at_the_feet(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    words = link_words(lua)
    click = lua.globals().HOOKS.SetItemRef
    click("garrmission:furnish:" + words)
    assert (
        printed(lua)[-2]
        == PREFIX + "spawning Full (set 1, 2 objects) on house, led by an invisible pivot"
    )
    lua.execute("MODIFIER = 'ctrl'")
    click("garrmission:furnish:" + words)
    assert (
        printed(lua)[-2]
        == PREFIX
        + "spawning house's Full (set 1, 2 objects) at your feet, led by an invisible pivot"
    )


def test_a_shift_click_and_another_link_do_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    words = link_words(lua)
    before = len(printed(lua))
    lua.execute("MODIFIER = 'shift'")
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:" + words)
    lua.execute("MODIFIER = nil")
    lua.globals().HOOKS.SetItemRef("garrmission:1:abc")
    assert len(printed(lua)) == before and sent(lua) == []


def test_resting_on_a_link_says_the_set_and_the_clicks(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    words = run(lua, "list base")[2].split("garrmission:furnish:")[1].split("|h")[0]
    lua.execute(
        """
        TIP = {}
        TOOLTIP = {
          SetText = function(_, text) TIP[#TIP + 1] = text end,
          AddLine = function(_, text) TIP[#TIP + 1] = text end,
        }
        """
    )
    lua.eval("Furnish.Command.Hover")(words, lua.eval("TOOLTIP"))
    assert list(lua.eval("TIP").values()) == [
        "Full",
        "Set_Full, set 1 of house, 2 objects",
        "with base",
        "Click: spawn it on the selected object",
        "Ctrl-click: spawn it at your feet",
    ]


# -- Importing ---------------------------------------------------------------------------


def test_an_import_furnishes_the_object_with_the_sets_the_map_placed(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lines = run(lua, "import")
    assert sent(lua)[:2] == ["doodad import", "gobject select 500"]
    assert lines == [
        PREFIX + "spawning Full (set 1, 2 objects) on house, joining house's group",
        PREFIX + "done: 2 of 2 spawned",
    ]
    assert "gobject group add 500" in sent(lua)
    assert len(lines) == 2
    assert shown(lua) == ["gobject group select 500"]
    # A word still decides who leads.
    run(lua, "import first")
    assert shown(lua)[-1] == "gobject group select 7003"


def test_an_import_the_map_did_not_furnish_spawns_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("IMPORT_UID = 1")
    assert run(lua, "import") == [
        PREFIX + "imported house.wmo as object 500; "
        "the map placed it with no set Furnish knows; /furn list shows its own"
    ]
    assert sent(lua) == ["doodad import", "gobject select 500"]


def test_an_import_stopped_while_waiting_spawns_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, deferred=True)
    run(lua, "import")
    assert run(lua, "stop") == [
        PREFIX + "stopped; nothing was spawned, and an import already sent stands"
    ]
    lua.execute("FLUSH()")
    assert sent(lua) == ["doodad import"]


def test_a_second_stop_gives_up_on_the_reply_and_still_deletes(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, deferred=True)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    lua.execute("STEP()")  # the pivot answers; the first doodad is now owed
    run(lua, "stop delete")
    assert run(lua, "stop") == [PREFIX + "giving up on the replies still owed"]
    lua.execute("FLUSH()")
    assert "gobject delete 7001" in sent(lua)
    assert printed(lua)[-1] == PREFIX + "stopped, and deleted the 1 object it spawned"


def test_a_set_at_the_feet_with_nothing_selected_offers_naming_it(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "1 here") == [
        PREFIX + "no object is selected; select the building first, as with .gob select, "
        "or name it, as /furn 3 here <entry>"
    ]


def test_an_import_with_base_lays_the_base_set_the_map_did_not_name(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "import base")[0] == (
        PREFIX + "spawning Base and Full (sets 0 and 1, 3 objects) on house, joining house's group"
    )


def test_an_imported_doodad_that_is_no_building_is_said_so(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("IMPORT_GUID = 502")
    assert run(lua, "import") == [
        PREFIX + "imported house.wmo as object 502; it is not a building, so it has no sets"
    ]


def test_an_import_whose_select_is_refused_says_so_and_frees_furnish(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECT_REFUSED = true")
    assert run(lua, "import") == [
        PREFIX + "imported house.wmo as object 500, but selecting it was refused: "
        '"Object not found"'
    ]
    lua.execute("SELECT_REFUSED = false; SELECTED = 500")
    assert run(lua, "1")[0].startswith(PREFIX + "spawning Full")


def test_an_import_waiting_for_its_object_says_so_to_another_command(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, deferred=True)
    run(lua, "import")
    assert run(lua, "list") == [
        PREFIX + "no object is selected; select the building first, as with .gob select"
    ]
    assert run(lua, "1") == [
        PREFIX + "Furnish is waiting for the imported object; /furn stop ends it"
    ]


def test_a_named_set_spawns_on_any_selected_object(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    words = run(lua, "list 817579")[2].split("garrmission:furnish:")[1].split("|h")[0]
    lua.execute("SELECTED = 502")
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:" + words)
    assert printed(lua)[-2] == (
        PREFIX
        + "spawning object 817579's Full (set 1, 2 objects) on chair.m2, led by an invisible pivot"
    )
    assert run(lua, "1 from 817579 nogroup")[0] == (
        PREFIX + "spawning object 817579's Full (set 1, 2 objects) on chair.m2, ungrouped"
    )


def test_a_set_read_off_the_selection_needs_a_building(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 502")
    assert run(lua, "1") == [
        PREFIX + "chair.m2 is not a building, so it has no sets; name one, as /furn 3 from <entry>"
    ]
    lua.execute("SELECTED = nil")
    assert run(lua, "1 from 817579") == [
        PREFIX + "no object is selected; select the object to spawn on first, as with .gob select"
    ]


def test_nothing_is_sent_where_the_player_may_not_spawn(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500; NO_PERMISSION = true")
    refusal = ["You do not have permission to spawn objects here."]
    assert run(lua, "1") == refusal
    assert run(lua, "import") == refusal
    assert sent(lua) == []
    # A list sends nothing, so it is not asked for permission.
    assert run(lua, "list")[0] == PREFIX + "house has 2 sets:"


def test_the_command_answers_to_both_its_names(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert list(lua.eval("SLASH_FURNISH1, SLASH_FURNISH2")) == ["/furn", "/furnish"]


BUILDING_LINE = (
    "Selected doodad |Hdoodad_uid:4242:0|h[6dr_draenei_house2.wmo - 830385]|h (UID: 4242) "
    "at X: 1 Y: 2 Z: 3 on map 1116 with scale: 1.000000."
)


def shown_line(lua: lua51.LuaRuntime, line: str) -> Any:
    """The line as the chat frame would show it once the filters have run, at login."""
    lua.execute('FIRE("PLAYER_LOGIN")')
    out = line
    for fn in lua.eval("FILTERS").values():
        answer = fn(None, "CHAT_MSG_SYSTEM", out)
        hidden, changed = answer if isinstance(answer, tuple) else (answer, None)
        assert hidden is False
        out = changed or out
    return out


def test_a_buildings_doodad_line_carries_a_button_that_imports_and_furnishes_it(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    line = shown_line(lua, BUILDING_LINE)
    assert line == BUILDING_LINE + " - |cff71d5ff|Hgarrmission:furnish:import:4242|h[Furnish]|h|r"
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:import:4242")
    assert sent(lua)[:2] == ["doodad import 4242", "gobject select 500"]
    assert printed(lua)[-2] == (
        PREFIX + "spawning Full (set 1, 2 objects) on house, joining house's group"
    )


def test_a_models_doodad_line_is_left_as_it_came(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    model_line = BUILDING_LINE.replace("6dr_draenei_house2.wmo", "6dr_draenei_bottle02.m2")
    assert shown_line(lua, model_line) == model_line
    assert shown_line(lua, "You have mounted 17697.") == "You have mounted 17697."
