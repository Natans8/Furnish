"""Which doodad set each WMO placed on a map uses, out of an ADT object file.

Since Cataclysm a map tile is split over several files and the placements live in
``_obj0.adt``. Its ``MODF`` chunk is 64 bytes per placed WMO: the model, a ``uniqueId`` that
``.doodad near`` prints, position, rotation, extents, flags, and the ``doodadSet`` the zone
chose. Two flags matter here: ``0x8`` says the model word is a file id rather than an index
into the ``MWID`` and ``MWMO`` name chunks, and ``0x80`` (Shadowlands and later) says the set
word indexes ``MWDR``, a range over ``MWDS``, so one placement can draw several sets.
"""

import struct
from collections.abc import Iterator
from dataclasses import dataclass

from furnish.chunks import chunk_map, records
from furnish.sources import path_key

_ENTRY = struct.Struct("<II12f4H")
_RANGE = struct.Struct("<II")

FLAG_FILE_ID = 0x8
"""The model word is a file data id."""

FLAG_SETS_FROM_MWDS = 0x80
"""The set word is an ``MWDR`` index naming a run of ``MWDS`` set indexes."""


@dataclass(frozen=True, slots=True)
class MapPlacement:
    """One WMO placed on a map tile.

    Attributes:
        model: The root file's id, or 0 where the name could not be resolved.
        unique_id: The placement's id, unique over the map in practice.
        sets: The doodad set indexes the placement draws, usually one.
    """

    model: int
    unique_id: int
    sets: tuple[int, ...]


def read_placements(raw: bytes, path_to_id: dict[str, int] | None = None) -> Iterator[MapPlacement]:
    """Yield the WMO placements of an ADT object file.

    Args:
        raw: The whole ``_obj0.adt`` file.
        path_to_id: How to resolve a model named by path rather than by id. Keys are
            lower-cased paths with forward slashes. A path not in the map yields model 0.
    """
    found = chunk_map(raw)
    payload = found.get(b"MODF")
    if payload is None:
        return
    names = _Names(found, path_to_id or {})
    ranges = _ranges(found)
    for row in records(_ENTRY, payload):
        name_id, unique_id, flags, doodad_set = row[0], row[1], row[14], row[15]
        model = name_id if flags & FLAG_FILE_ID else names.resolve(name_id)
        sets = (
            ranges.get(doodad_set, (doodad_set,)) if flags & FLAG_SETS_FROM_MWDS else (doodad_set,)
        )
        yield MapPlacement(model, unique_id, sets)


def _ranges(found: dict[bytes, memoryview]) -> dict[int, tuple[int, ...]]:
    if b"MWDR" not in found or b"MWDS" not in found:
        return {}
    sets_payload = found[b"MWDS"]
    sets = struct.unpack_from(f"<{len(sets_payload) // 2}H", sets_payload)
    ranges_payload = found[b"MWDR"]
    out = {}
    for index, (begin, end) in enumerate(records(_RANGE, ranges_payload)):
        out[index] = tuple(sets[begin : end + 1])
    return out


class _Names:
    def __init__(self, found: dict[bytes, memoryview], path_to_id: dict[str, int]) -> None:
        offsets_payload = found.get(b"MWID", memoryview(b""))
        self._offsets = struct.unpack_from(f"<{len(offsets_payload) // 4}I", offsets_payload)
        self._names = bytes(found.get(b"MWMO", memoryview(b"")))
        self._path_to_id = path_to_id

    def resolve(self, index: int) -> int:
        if index >= len(self._offsets):
            return 0
        name = self._names[self._offsets[index] :].split(b"\0", 1)[0].decode("latin-1")
        return self._path_to_id.get(path_key(name), 0)
