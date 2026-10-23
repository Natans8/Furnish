"""A set's name as a player reads it: the prefix dropped, the words split and cased."""

from pathlib import Path

import pytest
from lupa import lua51

NAMES = Path(__file__).parents[1] / "addon" / "Furnish" / "Names.lua"


@pytest.fixture(scope="module")
def pretty() -> lua51.LuaFunction:
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(NAMES.read_text(encoding="utf-8"))
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
