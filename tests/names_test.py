"""A set's name as a player reads it: the prefix dropped, the words split and cased. And the
blueprint name a run is offered under, made of those words."""

import pytest
from lupa import lua51

from tests.core_test import ADDON, run_file

NAMES = ADDON / "Data" / "Names.lua"


@pytest.fixture(scope="module")
def pretty() -> lua51.LuaFunction:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    run_file(lua, NAMES)
    return lua.eval("Furnish.Names.Set")


@pytest.mark.parametrize(
    ("spelled", "read"),
    [
        ("Set_Home_Alchemy", "Home Alchemy"),
        ("set_cloth", "Cloth"),
        ("SET_Bones01", "Bones 01"),
        ("Set_DemonHunter", "Demon Hunter"),
        ("Set_withSand", "With Sand"),
        ("Set_AggramarsVault", "Aggramars Vault"),
        ("Set_Rm3_Bells01", "Rm 3 Bells 01"),
        ("Set_01_Natural01", "01 Natural 01"),
        ("Floor2_Libary01", "Floor 2 Libary 01"),
        ("SCF_Chains02", "SCF Chains 02"),
        ("MD_Tunnel 01 ", "MD Tunnel 01"),
        ("Set_Abandoned-2", "Abandoned 2"),
        ("Firim's Lab", "Firim's Lab"),
        ("HTTPServer", "HTTP Server"),
        ("PreviewSet", "Preview Set"),
        ("set_garrison_magict", "Garrison Magict"),
        ("Set_B", "B"),
        ("set_1", "1"),
        ("ARDENWEALD", "Ardenweald"),
        ("SET_CARGOSHIP_NORM", "Cargoship Norm"),
        ("SET_KTPIG_WH_LINK03", "Ktpig Wh Link 03"),
        ("SET_MURLOCHUT01VAR1", "Murlochut 01 Var 1"),
        ("SET_7NB_LOUNGEBOAT", "7 Nb Loungeboat"),
    ],
)
def test_a_set_name_reads_as_words(pretty: lua51.LuaFunction, spelled: str, read: str) -> None:
    assert pretty(spelled) == read


def test_the_default_sets_empty_name_stays_empty(pretty: lua51.LuaFunction) -> None:
    assert pretty("") == ""


def test_a_name_that_is_only_its_prefix_is_drawn_as_spelled(pretty: lua51.LuaFunction) -> None:
    assert pretty("Set_") == "Set_"


@pytest.fixture(scope="module")
def names() -> lua51.LuaRuntime:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    run_file(lua, NAMES)
    return lua


def blueprint(lua: lua51.LuaRuntime, wmo: str, sets: list[tuple[int, str]], apart: bool) -> str:
    rows = ", ".join(f'{{ index = {index}, name = "{name}" }}' for index, name in sets)
    named: str = lua.eval(f'Furnish.Names.Blueprint("{wmo}", {{ {rows} }}, {str(apart).lower()})')
    return named


@pytest.mark.parametrize(
    ("wmo", "sets", "apart", "name"),
    [
        ("goldshireinn", [(2, "Set_C")], True, "goldshireinn_set_c"),
        ("goldshireinn", [(2, "Set_C")], False, "goldshireinn_c"),
        ("goldshireinn", [(1, "Set_B"), (2, "Set_C")], False, "goldshireinn_b_c"),
        (
            "6dr_draenei_house2",
            [(2, "Set_Restaurant"), (8, "Set_Schoolhouse")],
            True,
            "6dr_draenei_house2_sets_restaurant_schoolhouse",
        ),
        ("6dr_draenei_house2", [(1, "Set_Home_Alchemy")], False, "6dr_draenei_house2_home_alchemy"),
        (
            "emptywmo_goldshireinn",
            [(0, ""), (2, "Set_C")],
            True,
            "emptywmo_goldshireinn_sets_base_c",
        ),
        ("object 830051", [(1, "Set_Full")], True, "object_830051_set_full"),
    ],
)
def test_a_blueprint_is_named_after_the_wmo_and_its_sets(
    names: lua51.LuaRuntime, wmo: str, sets: list[tuple[int, str]], apart: bool, name: str
) -> None:
    assert blueprint(names, wmo, sets, apart) == name


def test_a_blueprint_name_past_the_limit_gives_the_sets_by_index(names: lua51.LuaRuntime) -> None:
    sets = [(index, f"Set_LongLongLongLongLongLong{index}") for index in range(1, 11)]
    named = blueprint(names, "9du_torghast_modular_chambercap01", sets, True)
    assert named == "9du_torghast_modular_chambercap01_sets_1_2_3_4_5_6_7_8_9_10"
    assert names.eval("Furnish.Names.BLUEPRINT") == 225
