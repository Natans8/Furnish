"""The addon's layout: each folder is a layer that reads only the layers before it, the toc
loads them in that order, and every file is handed the addon's table the way the client hands
it, with the one global made in one place."""

import re
from pathlib import PurePosixPath

import pytest

from tests.core_test import ADDON, LOADED

#: The layers in load order; the top folder holds what every layer reads.
LAYERS = ("", "Core", "Data", "Client", "Actions", "UI", "Slash")
#: The line every file opens with: the addon's table, as the client hands it to each file.
NAMESPACE = "local _, Furnish = ..."
#: The one file that makes the addon's table a global.
EXPORTER = "Settings.lua"

DEFINES = re.compile(r"^(?:function\s+)?Furnish\.(\w+)\s*(?:=|\()", re.MULTILINE)
READS = re.compile(r"\bFurnish\.(\w+)")
SOURCES = tuple(name for name in LOADED if name.endswith(".lua"))


def layer(name: str) -> int:
    folder = PurePosixPath(name).parent.as_posix()
    return LAYERS.index("" if folder == "." else folder)


def text(name: str) -> str:
    return (ADDON / name).read_text(encoding="utf-8")


def definers() -> dict[str, str]:
    """Each part of the addon's table, by the file that puts it there."""
    found: dict[str, str] = {}
    for name in SOURCES:
        for part in DEFINES.findall(text(name)):
            found.setdefault(part, name)
    return found


def test_every_file_on_disk_is_loaded() -> None:
    on_disk = {
        path.relative_to(ADDON).as_posix()
        for path in ADDON.rglob("*")
        if path.suffix in {".lua", ".xml"}
    }
    assert on_disk == set(LOADED)


def test_the_toc_loads_the_layers_in_order() -> None:
    order = [layer(name) for name in LOADED]
    assert order == sorted(order), LOADED


@pytest.mark.parametrize("name", SOURCES)
def test_a_file_reads_only_its_own_layer_and_those_before(name: str) -> None:
    parts = definers()
    later = sorted(
        f"Furnish.{part} ({parts[part]})"
        for part in set(READS.findall(text(name)))
        if part in parts and layer(parts[part]) > layer(name)
    )
    assert not later, f"{name} reads a later layer: {', '.join(later)}"


@pytest.mark.parametrize("name", SOURCES)
def test_a_file_opens_with_the_addon_table(name: str) -> None:
    code = [
        line
        for line in text(name).splitlines()
        if line.strip() and not line.lstrip().startswith("--")
    ]
    assert code[0] == NAMESPACE


def test_one_file_makes_the_global() -> None:
    makers = [name for name in SOURCES if re.search(r"^_G\.Furnish\s*=", text(name), re.MULTILINE)]
    assert makers == [EXPORTER]
