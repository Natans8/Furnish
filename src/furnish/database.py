"""Writing the database.

The schema is ``schema.sql`` beside this module, applied to a fresh file. Rows go in
through a few typed methods, in one transaction, so a failed build leaves no half file.
"""

import sqlite3
from collections.abc import Iterable, Mapping
from importlib import resources
from pathlib import Path
from types import TracebackType
from typing import Self

from furnish import FORMAT
from furnish.wmo import Placement


class Database:
    """A furnishing database being written.

    Use as a context manager: the schema is created on entry, the transaction committed on a
    clean exit and the file removed on an exception.
    """

    def __init__(self, path: Path) -> None:
        """Prepare to write ``path``, replacing any file there.

        Args:
            path: Where the database lands.
        """
        self._path = path
        self._connection: sqlite3.Connection | None = None
        self._sets: dict[tuple[str | None, tuple[tuple[int, Placement], ...]], int] = {}
        self.shared_sets = 0
        """How many sets were asked for that an identical one already answered."""

    def __enter__(self) -> Self:
        """Create the file and its schema, and open the one transaction."""
        self._path.unlink(missing_ok=True)
        self._connection = sqlite3.connect(self._path, isolation_level=None)
        self._connection.executescript(
            resources.files("furnish").joinpath("schema.sql").read_text()
        )
        self._connection.execute("BEGIN")
        return self

    def __exit__(
        self,
        kind: type[BaseException] | None,
        value: BaseException | None,
        trace: TracebackType | None,
    ) -> None:
        """Commit and compact on success; remove the half-written file on an error."""
        connection = self._connected()
        if kind is None:
            connection.execute("COMMIT")
            connection.execute("VACUUM")
            connection.close()
        else:
            connection.close()
            self._path.unlink(missing_ok=True)
        self._connection = None

    def meta(self, values: Mapping[str, str]) -> None:
        """Write the ``meta`` rows, the format version always among them.

        Args:
            values: Key to value, all text.
        """
        rows = {"format": str(FORMAT), **values}
        self._connected().executemany("INSERT INTO meta VALUES (?, ?)", rows.items())

    def add_set(self, name: str | None, placements: Iterable[tuple[int, Placement]]) -> int:
        """Insert a set and its placements, returning the set's id.

        A set with the same name and the same placements as one already written, in the same
        order, is not written again: the earlier id is returned, so roots that carry one
        furnishing share it.

        Args:
            name: The set's name, or None for the default set, whose name is a constant the
                file need not repeat.
            placements: ``(display id, placement)`` pairs, already filtered to the spawnable.
        """
        rows = tuple(placements)
        key = (name, rows)
        known = self._sets.get(key)
        if known is not None:
            self.shared_sets += 1
            return known
        connection = self._connected()
        cursor = connection.execute("INSERT INTO sets (name) VALUES (?)", (name,))
        set_id = cursor.lastrowid
        if set_id is None:
            raise RuntimeError("sqlite returned no rowid for a set")
        connection.executemany(
            "INSERT INTO placements VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            (
                (set_id, seq, display, *p.position, *p.rotation, p.scale)
                for seq, (display, p) in enumerate(rows)
            ),
        )
        self._sets[key] = set_id
        return set_id

    def add_wmo_sets(self, rows: Iterable[tuple[int, int, int]]) -> None:
        """Insert ``(display, index, set)`` rows.

        Args:
            rows: One per display id and set index.
        """
        self._connected().executemany("INSERT INTO wmo_sets VALUES (?, ?, ?)", rows)

    def add_map_sets(self, rows: Iterable[tuple[int, int, int]]) -> None:
        """Insert ``(map, uid, set)`` rows, ignoring exact repeats.

        A tile's placements can repeat across its object files; the same triple twice is not
        a conflict.

        Args:
            rows: One per map placement and set.
        """
        self._connected().executemany("INSERT OR IGNORE INTO map_sets VALUES (?, ?, ?)", rows)

    def _connected(self) -> sqlite3.Connection:
        if self._connection is None:
            raise RuntimeError("the database is not open; use it as a context manager")
        return self._connection
