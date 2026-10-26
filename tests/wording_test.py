"""The words Furnish never uses, in anything it writes: its code, its comments, its messages,
its documentation and its tests. Epsilon's own data is not Furnish's writing and is left out."""

import re
from pathlib import Path

ROOT = Path(__file__).parents[1]

#: A WMO is a WMO. The word is put together here so this file does not hold it whole.
FORBIDDEN = re.compile("build" + "ing", re.IGNORECASE)

#: The game's word for a unit picked to act on. A gob is selected, and where a set goes is its
#: destination, so Furnish never says it; a Blizzard file path that holds it is the client's own.
UNIT_PICK = re.compile(r"(?<![\\/])" + "tar" + "get", re.IGNORECASE)

WRITTEN = [
    "README.md",
    "pyproject.toml",
    "addon/Furnish/*.lua",
    "addon/Furnish/*.xml",
    "addon/Furnish/*.toc",
    "src/furnish/*.py",
    "src/furnish/*.sql",
    "tests/*.py",
]


def lines_saying(word: re.Pattern[str]) -> list[str]:
    """Every line Furnish wrote that holds the word, as a path, a line number and the line."""
    return [
        f"{path.relative_to(ROOT)}:{number}: {line.strip()}"
        for pattern in WRITTEN
        for path in sorted(ROOT.glob(pattern))
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if word.search(line)
    ]


def test_a_wmo_is_never_called_anything_else() -> None:
    assert lines_saying(FORBIDDEN) == []


def test_a_gob_is_selected_and_where_a_set_goes_is_its_destination() -> None:
    assert lines_saying(UNIT_PICK) == []


def test_the_rule_reaches_every_kind_of_file_it_names() -> None:
    assert all(list(ROOT.glob(pattern)) for pattern in WRITTEN)
