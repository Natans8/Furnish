"""Which gameobject display spawns a given model.

``GameObjectDisplayInfo`` maps a display id to a model file, and several displays can name
one file. Blizzard's rows come from wago.tools. Epsilon adds rows of its own above a floor
of 100,000, and where it has, its row is the one its server spawns: a few of Blizzard's are
refused there. Those Epsilon rows for Blizzard's files are vendored in ``data/``, because
they can be read only from inside the game.
"""

import csv
from collections.abc import Iterable, Mapping
from importlib import resources
from pathlib import Path

from furnish.sources import read_csv

EPSILON_FLOOR = 100_000
"""Display ids at or above this are Epsilon's own rows."""

OVERLAY = "epsilon-displays.csv"
"""The vendored Epsilon rows: ``file_id,display`` for Blizzard files Epsilon re-registered."""


def display_map(table: Path, overlay: Iterable[tuple[int, int]] = ()) -> dict[int, int]:
    """Model file id to the display id that spawns it.

    Where a file has several displays, an Epsilon row wins over a Blizzard row and the lowest
    id wins within a tier, so a build is deterministic.

    Args:
        table: wago's ``GameObjectDisplayInfo`` CSV.
        overlay: Extra ``(file id, display)`` rows, Epsilon's by convention.
    """
    chosen: dict[int, int] = {}
    rows = ((int(row["FileDataID"]), int(row["ID"])) for row in read_csv(table))
    for file_id, display in (*rows, *overlay):
        if file_id == 0:
            continue
        held = chosen.get(file_id)
        if held is None or _rank(display) < _rank(held):
            chosen[file_id] = display
    return chosen


def displays_of(table: Path) -> Mapping[int, tuple[int, ...]]:
    """Every display id that spawns each file, ascending, for the files that have one.

    Args:
        table: wago's ``GameObjectDisplayInfo`` CSV.
    """
    out: dict[int, list[int]] = {}
    for row in read_csv(table):
        file_id = int(row["FileDataID"])
        if file_id:
            out.setdefault(file_id, []).append(int(row["ID"]))
    return {file_id: tuple(sorted(ids)) for file_id, ids in out.items()}


def vendored_overlay() -> list[tuple[int, int]]:
    """The Epsilon rows shipped with the package."""
    text = resources.files("furnish").joinpath("data", OVERLAY).read_text(encoding="utf-8")
    return [(int(row["file_id"]), int(row["display"])) for row in csv.DictReader(text.splitlines())]


def _rank(display: int) -> tuple[int, int]:
    return (0 if display >= EPSILON_FLOOR else 1, display)
