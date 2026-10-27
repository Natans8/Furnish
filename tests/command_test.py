"""The command layer in a real Lua 5.1: what a player types read into requests, the help, the
list and its links, a spawn closed by selecting its group, an import, and stopping, against
the stand-in client the core's tests use."""

from pathlib import Path
from typing import Any

import pytest
from lupa import lua51

from tests.core_test import CATALOGUE, fake_client, lua_core, printed

PREFIX = "|cff66ccffFurnish:|r "


def command_lua(tmp_path: Path, deferred: bool = False, layered: bool = False) -> lua51.LuaRuntime:
    """The core with the client stood in, every send logged with whether its reply is shown,
    the import answered, and a selection's record announced the way EpsilonLib announces it.
    Deferred, a reply waits until FLUSH() so a run can be caught in flight; layered, the data
    is the fixture's layered house."""
    lua = lua_core(tmp_path, layered)
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
            local line = "Successfully imported [house.wmo - 817579] (UniqueId: "
              .. uid .. ") as GUID " .. guid .. "."
            if not IMPORT_APART then
              return callback(true, { line })
            end
            -- As Epsilon sends it: the command answers nothing, and the line comes after as
            -- a plain system line, behind another import's.
            callback(true, {})
            FIRE("CHAT_MSG_SYSTEM",
              "Successfully imported [barn.wmo - 1] (UniqueId: 99) as GUID 999.")
            return FIRE("CHAT_MSG_SYSTEM", line)
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


def spawn(lua: lua51.LuaRuntime, request: str) -> None:
    """Spawn through the console as a window does, the request written as a Lua table."""
    lua.execute(f"Furnish.Console.Spawn({request})")


# -- Reading what is typed ---------------------------------------------------------------


@pytest.mark.parametrize(
    ("typed", "request_"),
    [
        ("", {"action": "window"}),
        ("help me", {"action": "help"}),
        ("list", {"action": "list"}),
        (
            "list 830385 merge base",
            {"action": "list", "entry": 830385, "group": "merge", "base": True},
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
    assert lines[0] == "|cffffd100Furnish|r|cff9d9d9d spawns a WMO's doodad sets as objects|r"
    assert lines[1] == "  |cffffd100/furn|r: the window"
    assert lines[2] == "  |cffffd100/furn list [<entry>]|r: a WMO's sets, as buttons"
    # The words share one line, each a link whose tooltip says what it does.
    words = lines[-1]
    for word in ("first", "merge", "nogroup", "base", "quiet"):
        assert f"|Hgarrmission:furnish:word:{word}|h[{word}]|h" in words
    assert len(lines) == 1 + 6 + 1
    lua.execute(
        "TIP = {}; FAKE = { SetText = function(_, t) TIP[#TIP + 1] = t end,"
        " AddLine = function(_, t) TIP[#TIP + 1] = t end }"
    )
    lua.eval("Furnish.Command.Hover")("word:merge", lua.eval("FAKE"))
    assert list(lua.eval("TIP").values()) == [
        "merge",
        "merge the set into the selected gob's group, so no pivot spawns",
    ]


def test_the_command_alone_opens_the_window(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("TOGGLED = 0; Furnish.Window = { Toggle = function() TOGGLED = TOGGLED + 1 end }")
    assert run(lua, "") == []
    assert lua.eval("TOGGLED") == 1


# -- What a window reads -----------------------------------------------------------------


def test_a_window_takes_its_sets_from_the_selected_wmo(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert lua.eval("select(2, Furnish.Console.Source())") == "no object is selected"
    lua.execute("SELECTED = 502")
    assert (
        lua.eval("select(2, Furnish.Console.Source())") == "chair is not a WMO, so it has no sets"
    )
    lua.execute("SELECTED = 500")
    source = lua.eval("Furnish.Console.Source()")
    assert (source.name, source.file, source.blank) == ("house", 900, False)
    assert [(s.index, s.name, s.count, s.canonical) for s in source.sets.values()] == [
        (0, "Base", 1, ""),
        (1, "Full", 2, "Set_Full"),
    ]
    # The group the run selects stands for the WMO it was on.
    run(lua, "1")
    assert lua.eval("Furnish.Console.Source()").name == "house"
    lua.execute("GROUP_LEADER = 12345")
    assert lua.eval("select(2, Furnish.Console.Source())") == "a group is selected, not one object"


def test_a_window_takes_its_sets_from_an_entry_whatever_is_selected(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    source = lua.eval("Furnish.Console.Source({ entry = 817579 })")
    assert (source.name, source.file) == ("object 817579", 900)
    assert lua.eval("select(2, Furnish.Console.Source({ entry = 1 }))").startswith(
        "entry 1 is no WMO object"
    )


def test_a_window_takes_its_sets_from_a_root_by_its_file(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    source = lua.eval("Furnish.Console.Source({ file = 900, name = 'house' })")
    assert (source.name, source.file, len(source.sets)) == ("house", 900, 2)
    assert (
        lua.eval("select(2, Furnish.Console.Source({ file = 1, name = 'chair' }))")
        == "chair has no doodad sets in Furnish's data"
    )


def test_a_selected_map_wmo_names_its_source_and_marks_the_sets_its_map_draws(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    source = lua.eval(
        "Furnish.Console.Source({ entry = 817579,"
        " placement = { map = 1116, uid = 4242, name = 'House.wmo' } })"
    )
    assert source.name == "house"
    assert [(s.name, s.placed) for s in source.sets.values()] == [("Base", False), ("Full", True)]
    # A doodad the map does not place leaves every set unmarked.
    stray = lua.eval(
        "Furnish.Console.Source({ entry = 817579,"
        " placement = { map = 1116, uid = 1, name = 'house' } })"
    )
    assert [s.placed for s in stray.sets.values()] == [False, False]


def test_the_selection_is_any_selected_object_with_its_pose(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert lua.eval("select(2, Furnish.Console.Selected())") == "no object is selected"
    lua.execute("SELECTED = 502")
    assert lua.eval("(Furnish.Console.Selected())").name == "chair"
    lua.execute("SELECTED = 500")
    selected = lua.eval("(Furnish.Console.Selected())")
    assert (selected.name, selected.guid, selected.scale) == ("house", 500, 2)
    assert (selected.position.x, selected.rotation.turn, selected.groupLeader) == (10, 90, 0)


def test_a_set_spawns_at_a_pose_given_with_no_object_behind_it(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 502")
    spawn(lua, "{ index = 1, file = 900, label = 'house', at = Furnish.Pose.At(1, 2, 3, 0) }")
    assert printed(lua)[-2] == (
        PREFIX
        + "spawning house's Full (set 1, 2 objects) at 1.0, 2.0, 3.0, "
        + "led by a pivot, one extra invisible object"
    )
    assert sent(lua)[0] == "gobject spawn -424242 posx 1 posy 2 posz 3 face north"
    # A merge needs something selected to merge into, and a pose names no WMO.
    lua.execute("SELECTED = nil")
    spawn(lua, "{ index = 1, file = 900, at = Furnish.Pose.At(1, 2, 3), group = 'merge' }")
    assert printed(lua)[-1] == PREFIX + MERGE_REFUSED
    spawn(lua, "{ index = 1, at = Furnish.Pose.At(1, 2, 3) }")
    assert printed(lua)[-1] == (
        PREFIX + "a position names no WMO; name the one whose sets to spawn"
    )


MERGE_REFUSED = (
    "no object is selected; select the object whose group to join first, as with .gob select"
)


def test_a_merge_into_a_gob_the_player_cannot_edit_is_refused_before_anything_is_sent(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    lua.execute(
        """
        C_Epsilon.IsOfficer = function() return false end
        C_Epsilon.IsOwner = function() return false end
        C_Epsilon.IsMember = function() return true end
        SELECTED = 502
        """
    )
    spawn(
        lua,
        "{ index = 1, file = 900, label = 'house', at = Furnish.Pose.At(1, 2, 3),"
        " group = 'merge' }",
    )
    assert printed(lua)[-1] == (
        PREFIX + "you can't edit chair in this phase, so the set can't merge into its group"
    )
    assert not [line for line in sent(lua) if line.startswith("gobject spawn")]


# -- The blueprint offer ------------------------------------------------------------------


def on_the_house_at_scale_one(tmp_path: Path) -> lua51.LuaRuntime:
    """The house selected, level and at scale 1, so a whole run on it may offer a blueprint."""
    lua = command_lua(tmp_path)
    lua.execute("RECORDS[500].scale = 1; SELECTED = 500")
    return lua


def offer(lua: lua51.LuaRuntime) -> str | None:
    named: str | None = lua.eval("Furnish.Console.Offer()")
    return named


def test_a_whole_run_led_by_its_pivot_offers_the_set_as_a_blueprint(tmp_path: Path) -> None:
    lua = on_the_house_at_scale_one(tmp_path)
    run(lua, "1")
    assert offer(lua) == "house_set_full"


def test_a_whole_run_merged_into_its_wmo_offers_the_wmo_furnished(tmp_path: Path) -> None:
    lua = on_the_house_at_scale_one(tmp_path)
    run(lua, "1 merge")
    assert offer(lua) == "house_full"


@pytest.mark.parametrize(
    ("change", "typed"),
    [
        ("RECORDS[500].scale = 2", "1"),
        ("RECORDS[500].transform.rotation.x = 15", "1"),
        ("RECORDS[500].transform.rotation.y = -5", "1 merge"),
        ("", "1 first"),
        ("", "1 nogroup"),
        # Selected, the twin is in a group already, so a merge would save that group's objects too.
        ("RECORDS[501].scale = 1; SELECTED = 501", "1 merge"),
    ],
)
def test_no_blueprint_is_offered_off_scale_tilted_or_otherwise_grouped(
    tmp_path: Path, change: str, typed: str
) -> None:
    lua = on_the_house_at_scale_one(tmp_path)
    lua.execute(change)
    run(lua, typed)
    assert offer(lua) is None


def test_the_offer_waits_for_its_group_and_lapses_once_anything_else_is_selected(
    tmp_path: Path,
) -> None:
    lua = on_the_house_at_scale_one(tmp_path)
    run(lua, "1")
    leader = lua.eval("GROUP_LEADER")
    # Something else selected before the group's selection is seen: the offer waits.
    lua.execute("SELECTED = 502")
    assert offer(lua) is None
    lua.execute(f'SELECTED, GROUP_LEADER = "group", {leader}')
    assert offer(lua) == "house_set_full"
    # Seen, it lapses once anything else is selected, and stays lapsed.
    lua.execute("SELECTED = 502")
    assert offer(lua) is None
    lua.execute(f'SELECTED, GROUP_LEADER = "group", {leader}')
    assert offer(lua) is None


def test_a_dismissed_offer_is_gone(tmp_path: Path) -> None:
    lua = on_the_house_at_scale_one(tmp_path)
    run(lua, "1")
    lua.execute("Furnish.Console.DismissOffer()")
    assert offer(lua) is None


def test_numbers_given_merge_into_whatever_is_selected_not_what_they_were_read_off(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    lua.execute("AT = Furnish.Console.Selected(); SELECTED = 502")
    spawn(lua, "{ index = 1, file = 900, label = 'house', at = AT, group = 'merge' }")
    # The numbers are the house's, but the chair is what is selected, so its group is joined.
    assert printed(lua)[-2] == (
        PREFIX + "spawning house's Full (set 1, 2 objects) at 10.0, 20.0, 30.0, led by chair"
    )
    assert "gobject group add 502" in sent(lua)
    assert "gobject group add 500" not in sent(lua)


def test_numbers_given_merge_into_a_selected_group(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute(
        """
        SELECTED, GROUP_LEADER = "group", 501
        local plain = EpsilonLib.GameObject.GetSelected
        EpsilonLib.GameObject.GetSelected = function(...)
          local selected = plain(...)
          if selected and selected.isGroup then
            selected.GetLeader = function() return RECORDS[501] end
          end
          return selected
        end
        """
    )
    spawn(
        lua,
        "{ index = 1, file = 900, label = 'house', at = Furnish.Pose.At(1, 2, 3),"
        " group = 'merge' }",
    )
    assert printed(lua)[-2].endswith("joining the group emptywmo_house is in")
    assert "gobject group add 501" in sent(lua)


def test_a_named_source_spawns_on_any_selected_object(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 502")
    lua.globals().Furnish.Console.Spawn(
        lua.eval("{ indexes = { 1 }, file = 900, label = 'house', group = 'nogroup' }")
    )
    assert printed(lua)[-2] == (
        PREFIX + "spawning house's Full (set 1, 2 objects) on chair, ungrouped"
    )


def test_a_window_hears_the_run_it_started_until_it_stops_hearing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute(
        """
        HEARD = {}
        local function hear(line) HEARD[#HEARD + 1] = line end
        STOP = Furnish.Console.Watch({
          started = function(total, what) hear("started " .. total .. " " .. what) end,
          progress = function(done, total) hear(done .. "/" .. total) end,
          finished = function(result) hear("finished " .. #result.spawned) end,
        })
        SELECTED = 500
        """
    )
    run(lua, "1")
    assert list(lua.eval("HEARD").values()) == [
        "started 2 Full (set 1, 2 objects)",
        "1/2",
        "2/2",
        "finished 3",
    ]
    lua.execute("STOP(); HEARD = {}; SELECTED = 500")
    run(lua, "1")
    assert list(lua.eval("HEARD").values()) == []


def test_a_window_is_told_when_it_may_not_start(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, deferred=True)
    assert lua.eval("Furnish.Console.Busy()") is None
    lua.execute("SELECTED = 500")
    run(lua, "1")
    assert lua.eval("Furnish.Console.Busy()") == "Furnish is still spawning; /furn stop ends it"


# -- Listing -----------------------------------------------------------------------------


def test_a_list_prints_a_menu_of_set_buttons_carrying_the_words(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    assert run(lua, "list merge") == [
        PREFIX + "house has 2 sets:",
        "  |cff71d5ff|Hgarrmission:furnish:900:0:merge::house|h[Base]|h|r "
        "|cff71d5ff|Hgarrmission:furnish:900:1:merge::house|h[Full]|h|r",
    ]
    assert run(lua, "list 817579 base")[0] == PREFIX + "object 817579 has 2 sets:"
    assert sent(lua) == []


def test_a_list_refuses_without_a_wmo(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "list") == [
        PREFIX + "no object is selected; select the WMO first, as with .gob select"
    ]
    lua.execute("SELECTED = 502")
    assert run(lua, "list") == [
        PREFIX + "chair is not a WMO, so it has no sets; /furn list <entry> lists another object's"
    ]
    assert run(lua, "list 5") == [
        PREFIX + "object 5 is not a WMO Furnish has sets for; check the entry on its lookup line"
    ]


# -- Spawning ----------------------------------------------------------------------------


def test_a_spawn_says_what_it_sends_and_selects_its_group_in_sight(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    lines = run(lua, "1")
    assert lines == [
        PREFIX
        + "spawning Full (set 1, 2 objects) on house, led by a pivot, one extra invisible object",
        PREFIX + "done: 2 of 2 spawned, and the pivot, in 0.0 s",
    ]
    assert (
        sent(lua)[0] == "gobject spawn -424242 scale 2 posx 10 posy 20 posz 30 face north turn 90"
    )
    assert shown(lua) == ["gobject group select 7001"]


def test_an_ungrouped_spawn_selects_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    assert run(lua, "1 nogroup")[0].endswith("on house, ungrouped")
    assert shown(lua) == []


def test_merge_joins_the_wmos_own_group(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 501")
    assert run(lua, "1 merge")[0].endswith("joining the group emptywmo_house is in")
    assert "gobject group add 333" in sent(lua)
    assert shown(lua) == ["gobject group select 333"]


def test_an_emptywmo_is_given_the_base_set_it_does_not_draw(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 501")
    line = run(lua, "1 nogroup")[0]
    assert line == (
        PREFIX + "spawning Base and Full (sets 0 and 1, 3 objects) on emptywmo_house, ungrouped"
    )
    assert [s.split()[2] for s in sent(lua)] == ["-21", "-20", "-21"]


def test_several_sets_spawn_together_and_the_base_set_comes_once(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 501")
    lua.globals().Furnish.Console.Spawn(lua.eval("{ indexes = { 0, 1 }, group = 'nogroup' }"))
    assert printed(lua)[-2] == (
        PREFIX + "spawning Base and Full (sets 0 and 1, 3 objects) on emptywmo_house, ungrouped"
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
        + "spawning object 817579's Base (set 0, 1 object) at your feet, "
        + "led by the set's first object"
    )
    assert sent(lua) == ["gobject spawn -21 posx -3 posy 6 posz 4 face north turn 90"]


def test_a_spawn_refuses_with_the_way_out(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "1")[0].endswith(
        "no object is selected; select the WMO first, as with .gob select"
    )
    lua.execute("SELECTED = 'group'")
    assert run(lua, "1")[0].endswith(
        "a group is selected, not one object; select the WMO first, as with .gob select"
    )
    lua.execute("SELECTED = 500")
    assert run(lua, "7") == [PREFIX + "house has no set 7; /furn list shows its 2"]
    assert run(lua, "7 here 817579") == [
        PREFIX + "object 817579 has no set 7; /furn list 817579 shows its 2"
    ]
    assert sent(lua) == []


GROUP_REFUSED = "a group is selected, not one object; select the WMO first, as with .gob select"


def test_the_group_a_run_selected_stands_for_its_wmo_read_fresh(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    assert lua.eval("Furnish.Client.SelectedGroup()") == "7001"
    # The group moved the WMO after the run; the next set goes where it stands now.
    lua.execute("RECORDS[500].transform.position.x = 99")
    before = len(sent(lua))
    assert run(lua, "1")[0] == (
        PREFIX
        + "spawning Full (set 1, 2 objects) on house, led by a pivot, one extra invisible object"
    )
    assert sent(lua)[before : before + 2] == [
        "gobject select 500",
        "gobject spawn -424242 scale 2 posx 99 posy 20 posz 30 face north turn 90",
    ]
    assert run(lua, "list")[0] == PREFIX + "house has 2 sets:"


def test_a_group_no_run_selected_is_still_refused(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    lua.execute("GROUP_LEADER = 12345")
    assert run(lua, "1")[0].endswith(GROUP_REFUSED)


def test_a_wmo_that_cannot_be_selected_again_says_so_and_is_forgotten(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    lua.execute("SELECT_REFUSED = true")
    assert run(lua, "1") == [
        PREFIX + "the group stands for object 500, but selecting it was refused: "
        '"Object not found"; select the WMO first'
    ]
    assert run(lua, "1")[0].endswith(GROUP_REFUSED)


def test_a_wait_for_the_wmo_blocks_another_and_stops_with_nothing_spawned(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path, deferred=True)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    lua.execute("FLUSH()")
    run(lua, "1")
    assert run(lua, "1") == [PREFIX + "Furnish is waiting for object 500; /furn stop ends it"]
    assert run(lua, "stop") == [PREFIX + "stopped; nothing was spawned"]
    before = len(sent(lua))
    lua.execute("FLUSH()")
    assert not [line for line in sent(lua)[before:] if line.startswith("gobject spawn")]


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
    assert printed(lua)[-1] == PREFIX + "stopped, and deleted the 1 object spawned"
    assert sent(lua)[-1] == "gobject delete 7001"
    assert shown(lua) == []
    assert run(lua, "stop") == [PREFIX + "nothing is spawning"]


# -- Links -------------------------------------------------------------------------------


def link_words(lua: lua51.LuaRuntime, index: int = 1) -> str:
    """The words the list's button for set number index carries, counted from 0."""
    menu = "".join(run(lua, "list")[1:])
    marker = "garrmission:furnish:"
    start = -1
    for _ in range(index + 1):
        start = menu.index(marker, start + 1)
    start += len(marker)
    return menu[start : menu.index("|h", start)]


def test_a_click_spawns_on_the_selection_and_ctrl_at_the_feet(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    words = link_words(lua)
    click = lua.globals().HOOKS.SetItemRef
    click("garrmission:furnish:" + words)
    assert (
        printed(lua)[-2]
        == PREFIX
        + "spawning Full (set 1, 2 objects) on house, led by a pivot, one extra invisible object"
    )
    lua.execute("MODIFIER = 'ctrl'")
    click("garrmission:furnish:" + words)
    assert (
        printed(lua)[-2]
        == PREFIX
        + "spawning house's Full (set 1, 2 objects) at your feet, "
        + "led by a pivot, one extra invisible object"
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
    words = run(lua, "list base")[1].split("garrmission:furnish:")[2].split("|h")[0]
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
        "Click: spawn the set onto the selected gob",
        "Ctrl-click: spawn the set at your feet",
    ]


# -- Importing ---------------------------------------------------------------------------


def test_an_import_furnishes_the_object_with_the_sets_the_map_placed(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lines = run(lua, "import")
    assert sent(lua)[:2] == ["doodad import", "gobject select 500"]
    assert lines == [
        PREFIX + "spawning Full (set 1, 2 objects) on house, led by house",
        PREFIX + "done: 2 of 2 spawned in 0.0 s",
    ]
    assert "gobject group add 500" in sent(lua)
    assert shown(lua) == ["gobject group select 500"]
    # A word still decides who leads.
    run(lua, "import first")
    assert shown(lua)[-1] == "gobject group select 7003"


def test_an_import_the_map_did_not_furnish_spawns_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("IMPORT_UID = 1")
    assert run(lua, "import") == [
        PREFIX + "imported house.wmo as object 500; "
        "the doodad drew no set beyond its base that Furnish knows of; "
        "/furn list lists the WMO's own"
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
    assert printed(lua)[-1] == PREFIX + "stopped, and deleted the 1 object spawned"


def test_a_set_at_the_feet_with_nothing_selected_offers_naming_it(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "1 here") == [
        PREFIX + "no object is selected; select the WMO first, as with .gob select, "
        "or name it, as /furn 3 here <entry>"
    ]


def test_an_import_of_a_placement_drawing_several_sets_spawns_every_one(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, layered=True)
    lua.execute("IMPORT_UID = 4343")
    assert run(lua, "import") == [
        PREFIX + "spawning Full and Lights (sets 1 and 2, 3 objects) on house, led by house",
        PREFIX + "done: 3 of 3 spawned in 0.0 s",
    ]
    # The base is laid once beside them, not once a set.
    assert run(lua, "import base")[0] == (
        PREFIX + "spawning Base and Full and Lights (sets 0 and 1 and 2, 4 objects) on house,"
        " led by house"
    )


def test_an_import_spawns_the_sets_named_in_place_of_the_maps(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, layered=True)
    lua.execute("IMPORT_UID = 4343")
    lua.execute("Furnish.Console.Import({ indexes = { 2 }, group = 'nogroup', quiet = true })")
    assert printed(lua)[-2:] == [
        PREFIX + "spawning Lights (set 2, 1 object) on house, ungrouped",
        PREFIX + "done: 1 of 1 spawned in 0.0 s",
    ]


def test_an_import_with_base_lays_the_base_set_the_map_did_not_name(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    assert run(lua, "import base")[0] == (
        PREFIX + "spawning Base and Full (sets 0 and 1, 3 objects) on house, led by house"
    )


def test_an_imported_doodad_that_is_no_wmo_is_said_so(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("IMPORT_GUID = 502")
    assert run(lua, "import") == [
        PREFIX + "imported house.wmo as object 502, which is not a WMO and has no sets"
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
        PREFIX + "no object is selected; select the WMO first, as with .gob select"
    ]
    assert run(lua, "1") == [
        PREFIX + "Furnish is waiting for the imported object; /furn stop ends it"
    ]


def test_a_named_set_spawns_on_any_selected_object(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    words = run(lua, "list 817579")[1].split("garrmission:furnish:")[2].split("|h")[0]
    lua.execute("SELECTED = 502")
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:" + words)
    assert printed(lua)[-2] == (
        PREFIX
        + "spawning object 817579's Full (set 1, 2 objects) on chair, "
        + "led by a pivot, one extra invisible object"
    )
    assert run(lua, "1 from 817579 nogroup")[0] == (
        PREFIX + "spawning object 817579's Full (set 1, 2 objects) on chair, ungrouped"
    )


def test_a_set_read_off_the_selection_needs_a_wmo(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 502")
    assert run(lua, "1") == [
        PREFIX + "chair is not a WMO, so it has no sets; name one, as /furn 3 from <entry>"
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


WMO_LINE = (
    "Selected doodad |Hdoodad_uid:4242:0|h[6dr_draenei_house2 - 817579]|h (UID: 4242) "
    "at X: 1 Y: 2 Z: 3 on map 1116 with scale: 1.000000."
)


def shown_line(lua: lua51.LuaRuntime, line: str) -> Any:
    """The line as the chat frame would show it once the filters have run."""
    out = line
    for fn in lua.eval("FILTERS").values():
        answer = fn(None, "CHAT_MSG_SYSTEM", out)
        hidden, changed = answer if isinstance(answer, tuple) else (answer, None)
        assert hidden is False
        out = changed or out
    return out


def test_a_wmos_doodad_line_carries_a_button_that_imports_and_furnishes_it(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    line = shown_line(lua, WMO_LINE)
    assert line == WMO_LINE + " - |cff71d5ff|Hgarrmission:furnish:import:4242|h[Furnish]|h|r"
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:import:4242")
    assert sent(lua)[:2] == ["doodad import 4242", "gobject select 500"]
    assert printed(lua)[-2] == (PREFIX + "spawning Full (set 1, 2 objects) on house, led by house")


def test_the_quiet_word_asks_a_run_to_leave_its_progress_counts_out(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    request = lua.eval("Furnish.Command.Parse('1 quiet')")
    assert (request.action, request.index, request.quiet) == ("spawn", 1, True)
    assert lua.eval("Furnish.Command.Parse('import quiet')").quiet is True
    assert any("quiet" in line for line in run(lua, "help"))


def test_chat_buttons_turned_off_leave_every_line_as_it_came(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("Furnish.Settings.chatButtons = false")
    assert shown_line(lua, WMO_LINE) == WMO_LINE


def test_a_doodad_the_map_placed_with_only_its_base_set_gets_no_button(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    # Importing it would spawn nothing, the gob drawing its base set itself.
    base_only = WMO_LINE.replace("4242", "4244")
    assert shown_line(lua, base_only) == base_only
    # Nor does a placement the data does not know, whose sets cannot be told.
    unknown = WMO_LINE.replace("4242", "9999")
    assert shown_line(lua, unknown) == unknown


def test_a_near_line_takes_the_map_the_player_stands_on(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    near = "|Hdoodad_uid:4242:0|h[6dr_draenei_house2 - 817579]|h"
    assert (
        shown_line(lua, near)
        == near + " - |cff71d5ff|Hgarrmission:furnish:import:4242|h[Furnish]|h|r"
    )


def test_a_line_whose_entry_is_no_furnished_wmo_is_left_as_it_came(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    # Named like a WMO, but an entry the data has no sets for.
    model_line = WMO_LINE.replace("6dr_draenei_house2 - 817579", "6dr_draenei_house2.wmo - 717747")
    assert shown_line(lua, model_line) == model_line
    assert shown_line(lua, "You have mounted 17697.") == "You have mounted 17697."


def test_an_import_hears_its_line_when_the_server_sends_it_apart(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("IMPORT_APART = true")
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:import:4242")
    assert sent(lua)[:2] == ["doodad import 4242", "gobject select 500"]
    assert printed(lua)[-2] == (PREFIX + "spawning Full (set 1, 2 objects) on house, led by house")


def test_any_true_answer_to_the_permission_check_is_permission(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500; EpsilonLib.GameObject.CanSpawn = function() return 1 end")
    assert run(lua, "1")[0].startswith(PREFIX + "spawning Full")


def test_a_run_says_how_long_it_took(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, deferred=True)
    lua.execute("SELECTED = 500; CLOCK = 2")
    run(lua, "1")
    lua.execute("CLOCK = 14.5; FLUSH()")
    assert printed(lua)[-1] == PREFIX + "done: 2 of 2 spawned, and the pivot, in 12.5 s"


def test_a_name_search_lists_each_wmo_with_sets_once(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute(
        "ROWS = { { displayid = 30262, fileid = 900, name = 'world/wmo/house.wmo\\r' },"
        " { displayid = 30263, fileid = 900, name = 'world/wmo/house.wmo' },"
        " { displayid = 5, fileid = 777, name = '[bfa 810-820] emptywmo_house.wmo' },"
        " { displayid = 6, fileid = 1, name = 'world/prop/housechair.m2' } }"
    )
    lua.execute(CATALOGUE)
    found = lua.eval("Furnish.Console.Find('house')")
    assert [(w.name, w.file, w.sets, w.blank) for w in found.values()] == [
        ("emptywmo_house", 777, 2, True),
        ("house", 900, 2, False),
    ]


def test_a_name_search_lists_the_wmos_with_the_most_sets_first(tmp_path: Path) -> None:
    lua = command_lua(tmp_path, layered=True)
    lua.execute(
        "ROWS = { { displayid = 30262, fileid = 900, name = 'world/wmo/house.wmo' },"
        " { displayid = 5, fileid = 777, name = 'emptywmo_house.wmo' } }"
    )
    lua.execute(CATALOGUE)
    found = lua.eval("Furnish.Console.Find('house')")
    assert [(w.name, w.sets) for w in found.values()] == [("house", 3), ("emptywmo_house", 2)]


def test_an_import_alone_spawns_nothing(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("Furnish.Console.Import({ only = true })")
    assert sent(lua) == ["doodad import", "gobject select 500"]
    assert printed(lua)[-1] == PREFIX + "imported house.wmo as object 500"


def test_a_doodads_sets_are_marked_on_the_selected_wmo(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    source = lua.eval("Furnish.Console.Source({ placement = { map = 1116, uid = 4242 } })")
    assert [(s.name, s.placed) for s in source.sets.values()] == [("Base", False), ("Full", True)]


def test_a_wmo_gobs_selection_line_carries_a_button_that_lists_its_sets(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    selected = (
        "Selected gameobject |Hgameobject_entry:817579|h[6dr_draenei_house2 - 817579]|h "
        "(GUID: |Hgameobject_GUID:500|h500|h)"
    )
    line = shown_line(lua, selected)
    assert line == selected + " - |cff71d5ff|Hgarrmission:furnish:list:817579|h[Furnish]|h|r"
    lua.globals().HOOKS.SetItemRef("garrmission:furnish:list:817579")
    assert any("Full" in each for each in printed(lua))
    # A gob whose entry is no furnished WMO is left as it came.
    chair = selected.replace("817579", "717747")
    assert shown_line(lua, chair) == chair


def test_a_wmo_gobs_spawn_line_carries_the_same_button(tmp_path: Path) -> None:
    lua = command_lua(tmp_path)
    # As the server sends it, the name's link left unclosed.
    spawned = (
        "Spawned gameobject |cff00CCFF|Hgameobject_entry:817579|h[6dr_draenei_house2 - 817579]|r "
        "(GUID: |cff00CCFF|Hgameobject_GUID:500|h500|h|r)"
    )
    line = shown_line(lua, spawned)
    assert line == spawned + " - |cff71d5ff|Hgarrmission:furnish:list:817579|h[Furnish]|h|r"
    moved = spawned.replace("Spawned gameobject", "Moved GameObject")
    assert shown_line(lua, moved) == moved


def test_the_first_run_reminds_about_highlighting_and_leaves_it_to_the_player(
    tmp_path: Path,
) -> None:
    lua = command_lua(tmp_path)
    lua.execute("SELECTED = 500")
    run(lua, "1")
    run(lua, "1")
    reminders = [line for line in printed(lua, reminders=True) if "highlighting" in line]
    assert reminders == [
        PREFIX + "highlighting too many objects can crash the game; "
        ".toggle highlight off turns it off"
    ]
    assert not any("highlight" in line for line in sent(lua))
