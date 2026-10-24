"""The words Furnish never uses, in anything it writes: its code, its comments, its messages,
its documentation and its tests. Epsilon's own data is not Furnish's writing and is left out."""

import re
from pathlib import Path

ROOT = Path(__file__).parents[1]

#: A WMO is a WMO. The word is put together here so this file does not hold it whole.
FORBIDDEN = re.compile("build" + "ing", re.IGNORECASE)

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


def test_a_wmo_is_never_called_anything_else() -> None:
    found = [
        f"{path.relative_to(ROOT)}:{number}: {line.strip()}"
        for pattern in WRITTEN
        for path in sorted(ROOT.glob(pattern))
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1)
        if FORBIDDEN.search(line)
    ]
    assert found == []


def test_the_rule_reaches_every_kind_of_file_it_names() -> None:
    assert all(list(ROOT.glob(pattern)) for pattern in WRITTEN)
