"""Writers for the small WMO and ADT files the tests read.

They produce exactly the chunks the readers look at, in the layouts the readers document,
so a test states a file in terms of sets and placements rather than bytes.
"""

import random
import struct
from collections.abc import Iterable, Sequence

from furnish.wmo import Placement


def chunk(tag: str, payload: bytes) -> bytes:
    return tag.encode()[::-1] + struct.pack("<I", len(payload)) + payload


def wmo_root(
    sets: Sequence[tuple[str, Sequence[Placement]]],
    models: Sequence[int] | None = None,
    model_names: Sequence[str] | None = None,
    wmo_id: int = 7,
) -> bytes:
    """A root whose placements reference models by id (``models``) or by path (``model_names``)."""
    references = list(models or [])
    names = b""
    offsets = []
    if model_names is not None:
        for name in model_names:
            offsets.append(len(names))
            names += name.encode() + b"\0"
    placements = b""
    mods = b""
    start = 0
    for name, rows in sets:
        mods += struct.pack("<20sII4x", name.encode(), start, len(rows))
        for p in rows:
            reference = (
                offsets[references.index(p.model)]
                if model_names is not None
                else references.index(p.model)
            )
            placements += struct.pack(
                "<I3f4ff4B", reference, *p.position, *p.rotation, p.scale, 0, 0, 0, 0
            )
            start += 1
    header = bytearray(64)
    struct.pack_into("<I", header, 36, wmo_id)
    model_chunk = (
        chunk("MODN", names)
        if model_names is not None
        else chunk("MODI", struct.pack(f"<{len(references)}I", *references))
    )
    return (
        chunk("MVER", struct.pack("<I", 17))
        + chunk("MOHD", bytes(header))
        + chunk("MODS", mods)
        + model_chunk
        + chunk("MODD", placements)
    )


def adt_object(
    placements: Iterable[tuple[int, int, int, int]],
    ranges: Sequence[Sequence[int]] = (),
    names: Sequence[str] = (),
) -> bytes:
    """An ``_obj0.adt`` with ``(model, unique id, flags, set word)`` placements.

    ``ranges`` fills MWDR and MWDS for placements flagged 0x80; ``names`` fills MWMO and MWID
    for placements without 0x8, whose model word is then an index into ``names``.
    """
    modf = b""
    for model, unique_id, flags, set_word in placements:
        modf += struct.pack("<II12f4H", model, unique_id, *([0.0] * 12), flags, set_word, 0, 1024)
    out = chunk("MVER", struct.pack("<I", 18))
    if names:
        blob = b""
        offsets = []
        for name in names:
            offsets.append(len(blob))
            blob += name.encode() + b"\0"
        out += chunk("MWMO", blob) + chunk("MWID", struct.pack(f"<{len(offsets)}I", *offsets))
    if ranges:
        flat: list[int] = []
        spans = []
        for run in ranges:
            spans.append((len(flat), len(flat) + len(run) - 1))
            flat.extend(run)
        out += chunk("MWDS", struct.pack(f"<{len(flat)}H", *flat))
        out += chunk("MWDR", b"".join(struct.pack("<II", b, e) for b, e in spans))
    return out + chunk("MODF", modf)


def float32(value: float) -> float:
    """The float32 nearest ``value``, as a file stores it."""
    result: float = struct.unpack("<f", struct.pack("<f", value))[0]
    return result


IDENTITY = (0.0, 0.0, 0.0, 1.0)


def varied_placements(count: int, seed: int) -> list[tuple[int, Placement]]:
    """Rows of exact float32 values that reach the edges, the same for a seed.

    The smallest and largest display ids, negative, zero and negative zero coordinates,
    identity and turned rotations, and scales of one and others.
    """
    pick = random.Random(seed)

    def coordinate() -> float:
        return float32(pick.uniform(-5000, 5000))

    rows = []
    for i in range(count):
        display = (1, 2**31, 16384)[i] if i < 3 else pick.randint(1, 2**31)
        position = (-0.0, 0.0, -5000.5) if i == 0 else (coordinate(), coordinate(), coordinate())
        rotation = IDENTITY
        if i % 5:
            x, y, z, w = (pick.uniform(-1, 1) for _ in range(4))
            norm = (x * x + y * y + z * z + w * w) ** 0.5
            rotation = (float32(x / norm), float32(y / norm), float32(z / norm), float32(w / norm))
        scale = float32(pick.choice((1.0, 1.0, 0.5, 1.25, 3.7)))
        rows.append((display, Placement(display, position, rotation, scale)))
    return rows
