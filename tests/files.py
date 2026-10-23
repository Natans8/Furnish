"""Writers for the small WMO and ADT files the tests read.

They produce exactly the chunks the readers look at, in the layouts the readers document,
so a test states a file in terms of sets and placements rather than bytes.
"""

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
