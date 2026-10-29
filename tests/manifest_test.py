"""The manifest names a version only where the code needs one, and says why on the same line.

`uv.lock` pins what runs, so a floor that only repeats the lock is noise every upgrade would have
to raise by hand, and `uv sync --upgrade` cannot. The reason beside a floor is what tells the two
apart."""

import re
import tomllib
from pathlib import Path

PYPROJECT = Path(__file__).resolve().parents[1] / "pyproject.toml"


def unexplained(text: str) -> list[str]:
    """The requirements that name a version with no `#` reason on their line."""
    config = tomllib.loads(text)
    groups = [
        config["project"].get("dependencies", []),
        *config.get("dependency-groups", {}).values(),
    ]
    lines = text.splitlines()
    found = []
    for requirement in (r for group in groups for r in group if isinstance(r, str)):
        spec = re.sub(r"^[A-Za-z0-9_.\-]+(\[[^\]]*\])?", "", requirement).split(";", 1)[0]
        if not re.search(r"[<>=!~]", spec):
            continue
        quoted = f'"{requirement}"'
        line = next((line for line in lines if quoted in line), "")
        if "#" not in line.split(quoted, 1)[-1]:
            found.append(requirement)
    return found


def test_every_floor_says_why() -> None:
    assert unexplained(PYPROJECT.read_text(encoding="utf-8")) == []


def test_a_floor_without_its_reason_is_caught() -> None:
    text = (
        '[project]\ndependencies = [\n    "numpy",\n    "lupa>=2.1",  # why\n'
        '    "mypy>=2.4.0",\n]\n'
    )
    assert unexplained(text) == ["mypy>=2.4.0"]
