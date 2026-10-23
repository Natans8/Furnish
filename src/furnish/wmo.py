"""Doodad sets and placements out of a WMO root file.

Three chunks carry them. ``MODS`` names the sets, 32 bytes each: a name of up to 20 bytes,
the index of the set's first placement, how many it holds, and four bytes of padding. ``MODD``
is the placements, 40 bytes each: a model reference, a position, a rotation quaternion, a
scale and a colour. ``MODI`` lists the models by file id, one per reference; roots older than
Legion list them by path in ``MODN`` instead, and the reference is then a byte offset into
that chunk.

Set 0 is always ``Set_$DefaultGlobal`` and the client draws it under every other set. The
reader keeps it: a WMO whose doodad list was blanked still has the geometry the default set
was authored for.
"""

import struct
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from furnish.chunks import chunk_map, records
from furnish.sources import path_key

_SET = struct.Struct("<20sII4x")
_PLACEMENT = struct.Struct("<I3f4ff4B")
_HEADER_WMO_ID_OFFSET = 36

MODEL_INDEX_MASK = 0xFFFFFF
"""The low 24 bits of a placement's first word are the model reference; the high 8 are flags."""


@dataclass(frozen=True, slots=True)
class Placement:
    """One doodad inside a WMO, in the WMO's own coordinates.

    Attributes:
        model: The model's file id, or 0 where the slot has been blanked.
        position: ``x, y, z`` relative to the WMO's origin.
        rotation: The quaternion ``x, y, z, w`` as the file stores it.
        scale: A uniform factor, 1.0 for the model's own size.
    """

    model: int
    position: tuple[float, float, float]
    rotation: tuple[float, float, float, float]
    scale: float


@dataclass(frozen=True, slots=True)
class DoodadSet:
    """A named set of placements.

    Attributes:
        name: The name as ``MODS`` spells it, without the padding.
        placements: The set's placements in file order.
    """

    name: str
    placements: tuple[Placement, ...]


@dataclass(frozen=True, slots=True)
class Root:
    """What a WMO root file says about its doodads.

    Attributes:
        wmo_id: The root's own id from its header, shared by a model family's variants.
        sets: Every set in ``MODS`` order, index 0 the default set.
    """

    wmo_id: int
    sets: tuple[DoodadSet, ...]


def read_root(raw: bytes, path_to_id: dict[str, int] | None = None) -> Root:
    """Read a WMO root file's doodad sets.

    Args:
        raw: The whole root file. A group file is refused, since it has no header.
        path_to_id: How to resolve a model named by path, for roots that predate file ids.
            Keys are lower-cased paths with forward slashes. A path not in the map, or a
            root naming paths when no map is given, yields model 0.

    Raises:
        ValueError: If the file is not a WMO root, a group file among them.
    """
    found = chunk_map(raw)
    if b"MVER" not in found or b"MOHD" not in found:
        raise ValueError("not a WMO root: no MVER and MOHD chunks")
    wmo_id = struct.unpack_from("<I", found[b"MOHD"], _HEADER_WMO_ID_OFFSET)[0]
    models = _models(found, path_to_id or {})
    placements = _placements(found.get(b"MODD", memoryview(b"")), models)
    sets = tuple(
        DoodadSet(name, placements[start : start + count])
        for name, start, count in _sets(found.get(b"MODS", memoryview(b"")))
    )
    return Root(wmo_id, sets)


def _sets(payload: memoryview) -> list[tuple[str, int, int]]:
    out = []
    for name, start, count in records(_SET, payload):
        out.append((name.split(b"\0", 1)[0].decode("latin-1"), start, count))
    return out


def _models(found: dict[bytes, memoryview], path_to_id: dict[str, int]) -> Callable[[int], int]:
    """How this root names a model: by id through ``MODI``, or by path through ``MODN``."""
    if b"MODI" in found:
        ids = found[b"MODI"]
        return _by_id(struct.unpack_from(f"<{len(ids) // 4}I", ids))
    return _by_name(bytes(found.get(b"MODN", memoryview(b""))), path_to_id)


def _placements(payload: memoryview, resolve: Callable[[int], int]) -> tuple[Placement, ...]:
    out = []
    for head, x, y, z, qx, qy, qz, qw, scale, _b, _g, _r, _a in records(_PLACEMENT, payload):
        out.append(Placement(resolve(head & MODEL_INDEX_MASK), (x, y, z), (qx, qy, qz, qw), scale))
    return tuple(out)


def _by_id(ids: Sequence[int]) -> Callable[[int], int]:
    return lambda reference: ids[reference] if reference < len(ids) else 0


def _by_name(names: bytes, path_to_id: dict[str, int]) -> Callable[[int], int]:
    def resolve(reference: int) -> int:
        if reference >= len(names):
            return 0
        name = names[reference:].split(b"\0", 1)[0].decode("latin-1")
        return path_to_id.get(path_key(name), 0)

    return resolve
