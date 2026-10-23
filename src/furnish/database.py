"""Writing the database.

The schema is ``schema.sql`` beside this module, applied to a fresh file. Rows go in
through a few typed methods, in one transaction, so a failed build leaves no half file.
"""

import hashlib
import sqlite3
import struct
from collections.abc import Iterable, Mapping
from importlib import resources
from pathlib import Path
from types import TracebackType
from typing import Self

from furnish import FORMAT
from furnish.wmo import Placement

_ROW = struct.Struct("<Q8f")


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
        self._sets: dict[tuple[str | None, bytes], int] = {}
        self.sets = 0
        """Set rows written."""
        self.placements = 0
        """Placement rows written."""
        self.shared_sets = 0
        """Sets asked for that an identical row already answered."""

    def __enter__(self) -> Self:
        """Create the file and its schema, and open the one transaction."""
        try:
            self._path.unlink(missing_ok=True)
        except PermissionError as error:
            raise RuntimeError(
                f"cannot replace {self._path}: another program holds it open; close it and retry"
            ) from error
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
        key = (name, _digest(rows))
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
        self.sets += 1
        self.placements += len(rows)
        return set_id

    def add_wmo_sets(self, rows: Iterable[tuple[int, int, int]]) -> None:
        """Insert ``(file, index, set)`` rows.

        Args:
            rows: One per root file and set index.
        """
        self._connected().executemany("INSERT INTO wmo_sets VALUES (?, ?, ?)", rows)

    def add_root_displays(self, rows: Iterable[tuple[int, int]]) -> None:
        """Insert ``(display, file)`` rows, one per display that spawns a furnished root.

        Args:
            rows: The displays and the root file each spawns.
        """
        self._connected().executemany("INSERT INTO root_displays VALUES (?, ?)", rows)

    def add_entries(self, rows: Iterable[tuple[int, int]]) -> None:
        """Insert ``(entry, file)`` rows, one per stock entry that spawns a furnished root.

        Args:
            rows: The entries and the root file each spawns.
        """
        self._connected().executemany("INSERT INTO entries VALUES (?, ?)", rows)

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


def _digest(rows: tuple[tuple[int, Placement], ...]) -> bytes:
    """A fingerprint of a set's rows, so sharing costs bytes per set rather than the rows."""
    digest = hashlib.blake2b(digest_size=16)
    for display, p in rows:
        digest.update(_ROW.pack(display, *p.position, *p.rotation, p.scale))
    return digest.digest()
