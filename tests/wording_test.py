"""The words Furnish never uses, in anything it writes: its code, its comments, its messages,
its documentation and its tests. Epsilon's own data is not Furnish's writing and is left out."""

import re
from pathlib import Path

ROOT = Path(__file__).parents[1]

#: A WMO is a WMO. The word is put together here so this file does not hold it whole.
FORBIDDEN = re.compile("build" + "ing", re.IGNORECASE)

#: The game's word for a unit picked to act on. A gob is selected, and where a set goes is its
#: destination, so Furnish never says it. A Blizzard file path that holds it is the client's own,
#: and so is the method that points a model scene's camera, which Furnish cannot rename.
UNIT_PICK = re.compile(r"(?<![\\/])(?<!Set)" + "tar" + "get", re.IGNORECASE)

WRITTEN = [
    "README.md",
    "pyproject.toml",
    "addon/Furnish/**/*.lua",
    "addon/Furnish/**/*.xml",
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


#: A click written into a sentence, where a tooltip draws it as a row of its own.
CLICK_IN_PROSE = re.compile(r'"(?:Shift-|Ctrl-|Right-|Ctrl- or shift-)?[Cc]lick:')

#: A tooltip line or value that starts lowercase, or one that explains both states of a box.
LOWERCASE_TIP = re.compile(r'\b(?:text|value) = "[a-z]|"(?:Ticked|Unticked):')

#: The addon's own Lua, where its tooltips are written; the libraries it carries are not Furnish's.
TOOLTIPS = [
    path for path in sorted(ROOT.glob("addon/Furnish/**/*.lua")) if "Libs" not in path.parts
]


def tooltip_lines_matching(pattern: re.Pattern[str]) -> list[str]:
    """Every line of the addon's own Lua that matches, as a path, a line number and the line."""
    return [
        f"{path.relative_to(ROOT)}:{number}: {line.strip()}"
        for path in TOOLTIPS
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if pattern.search(line)
    ]


def test_a_tooltip_draws_a_click_as_a_row_never_in_a_sentence() -> None:
    assert tooltip_lines_matching(CLICK_IN_PROSE) == []


def test_a_tooltip_line_starts_capitalised_and_says_the_state_it_is_in() -> None:
    assert tooltip_lines_matching(LOWERCASE_TIP) == []


def test_a_wmo_is_never_called_anything_else() -> None:
    assert lines_saying(FORBIDDEN) == []


def test_a_gob_is_selected_and_where_a_set_goes_is_its_destination() -> None:
    assert lines_saying(UNIT_PICK) == []


def test_the_rule_reaches_every_kind_of_file_it_names() -> None:
    assert all(list(ROOT.glob(pattern)) for pattern in WRITTEN)
