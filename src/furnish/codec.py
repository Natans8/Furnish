"""The byte form of one set, as the addon's data file carries it.

A set is reduced to integers, written as varints, deflated, and spelled in LibDeflate's
printable alphabet so it can sit inside a Lua string literal. The addon reverses the three
steps with LibDeflate and a few lines of byte arithmetic, one set at a time, when a set is
asked for, so nothing is decoded at load.

The reduction is lossy by design and to the grain the spawn command takes: positions in
centimetres, the quaternion in ten-thousandths, the scale in thousandths. Layer 1 keeps the
files' own floats; this is the shipped form.

The layout, version 1, every integer a varint unless said otherwise::

    u8      version
    varint  rows
    varint  models, then that many display ids, the first whole and the rest as deltas
    per row:
        varint  model index
        zigzag  x, y, z            centimetres
        u8      flags              1: a rotation follows, 2: a scale follows
        zigzag  qx, qy, qz, qw     ten-thousandths, only under flag 1
        varint  scale              thousandths, only under flag 2

Rows are sorted by model then position, so deflate meets runs of the same model; the order
a set is spawned in does not matter.
"""

import zlib
from collections.abc import Iterable, Iterator, Sequence
from dataclasses import dataclass

VERSION = 1
POSITION_UNIT = 100
ROTATION_UNIT = 10_000
SCALE_UNIT = 1_000
FLAG_ROTATION = 1
FLAG_SCALE = 2
IDENTITY = (0, 0, 0, ROTATION_UNIT)

_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
_BYTE = 8
_DECODE = {character: index for index, character in enumerate(_ALPHABET)}


@dataclass(frozen=True, slots=True)
class Row:
    """One placement as the shipped form holds it, already quantised.

    Attributes:
        display: The doodad's display id.
        position: ``x, y, z`` in centimetres.
        rotation: The quaternion in ten-thousandths, ``IDENTITY`` when the file had none.
        scale: Thousandths, 1000 for the model's own size.
    """

    display: int
    position: tuple[int, int, int]
    rotation: tuple[int, int, int, int]
    scale: int


def quantise(
    display: int, position: Sequence[float], rotation: Sequence[float], scale: float
) -> Row:
    """Reduce one layer 1 placement to the shipped grain.

    Args:
        display: The doodad's display id.
        position: ``x, y, z`` in yards.
        rotation: The quaternion ``x, y, z, w``.
        scale: The uniform factor.
    """
    x, y, z = (round(v * POSITION_UNIT) for v in position)
    qx, qy, qz, qw = (round(v * ROTATION_UNIT) for v in rotation)
    return Row(display, (x, y, z), (qx, qy, qz, qw), round(scale * SCALE_UNIT))


def encode(rows: Iterable[Row]) -> str:
    """Spell a set's rows as the printable string the data file carries.

    Args:
        rows: The set's placements, in any order.
    """
    ordered = sorted(rows, key=lambda r: (r.display, r.position))
    models = sorted({r.display for r in ordered})
    index = {display: i for i, display in enumerate(models)}
    out = bytearray([VERSION])
    out += varint(len(ordered))
    out += varint(len(models))
    previous = 0
    for display in models:
        out += varint(display - previous)
        previous = display
    for row in ordered:
        out += varint(index[row.display])
        for v in row.position:
            out += zigzag(v)
        flags = (FLAG_ROTATION if row.rotation != IDENTITY else 0) | (
            FLAG_SCALE if row.scale != SCALE_UNIT else 0
        )
        out.append(flags)
        if flags & FLAG_ROTATION:
            for v in row.rotation:
                out += zigzag(v)
        if flags & FLAG_SCALE:
            out += varint(row.scale)
    return for_print(zlib.compress(bytes(out), 9, wbits=-15))


def decode(text: str) -> list[Row]:
    """Read a set back out of its printable string.

    Args:
        text: What ``encode`` produced.

    Raises:
        ValueError: If the version byte is not this layout's.
    """
    data = zlib.decompress(from_print(text), wbits=-15)
    reader = _Reader(data)
    if reader.u8() != VERSION:
        raise ValueError("not a version 1 set blob")
    count = reader.varint()
    models = []
    previous = 0
    for _ in range(reader.varint()):
        previous += reader.varint()
        models.append(previous)
    rows = []
    for _ in range(count):
        display = models[reader.varint()]
        position = (reader.zigzag(), reader.zigzag(), reader.zigzag())
        flags = reader.u8()
        rotation = (
            (reader.zigzag(), reader.zigzag(), reader.zigzag(), reader.zigzag())
            if flags & FLAG_ROTATION
            else IDENTITY
        )
        scale = reader.varint() if flags & FLAG_SCALE else SCALE_UNIT
        rows.append(Row(display, position, rotation, scale))
    return rows


def varint(value: int) -> bytes:
    """Unsigned LEB128: seven bits a byte, low bits first, the high bit saying more follows.

    Args:
        value: A non-negative integer.
    """
    if value < 0:
        raise ValueError("a varint is unsigned")
    out = bytearray()
    while True:
        byte, value = value & 127, value >> 7
        if value:
            out.append(byte | 128)
        else:
            out.append(byte)
            return bytes(out)


def zigzag(value: int) -> bytes:
    """A signed value as a varint, small magnitudes of either sign staying short.

    Args:
        value: Any integer.
    """
    return varint(value * 2 if value >= 0 else -value * 2 - 1)


def for_print(data: bytes) -> str:
    """LibDeflate's printable encoding: six bits a character over its 64-letter alphabet.

    Args:
        data: Any bytes.
    """
    out: list[str] = []
    whole = len(data) - len(data) % 3
    for i in range(0, whole, 3):
        cache = data[i] | data[i + 1] << 8 | data[i + 2] << 16
        out += [_ALPHABET[(cache >> shift) & 63] for shift in (0, 6, 12, 18)]
    cache = bits = 0
    for byte in data[whole:]:
        cache |= byte << bits
        bits += 8
    while bits > 0:
        out.append(_ALPHABET[cache & 63])
        cache >>= 6
        bits -= 6
    return "".join(out)


def from_print(text: str) -> bytes:
    """The bytes behind ``for_print``.

    Args:
        text: A printable encoding.
    """
    out = bytearray()
    whole = len(text) - len(text) % 4
    for i in range(0, whole, 4):
        cache = 0
        for j in range(4):
            cache |= _DECODE[text[i + j]] << (6 * j)
        out += bytes((cache & 255, (cache >> 8) & 255, (cache >> 16) & 255))
    cache = bits = 0
    for character in text[whole:]:
        cache |= _DECODE[character] << bits
        bits += 6
    while bits >= _BYTE:
        out.append(cache & 255)
        cache >>= _BYTE
        bits -= _BYTE
    return bytes(out)


class _Reader:
    def __init__(self, data: bytes) -> None:
        self._data = data
        self._at = 0

    def u8(self) -> int:
        value = self._data[self._at]
        self._at += 1
        return value

    def varint(self) -> int:
        value = shift = 0
        while True:
            byte = self.u8()
            value |= (byte & 127) << shift
            if not byte & 128:
                return value
            shift += 7

    def zigzag(self) -> int:
        value = self.varint()
        return value >> 1 if not value & 1 else -((value + 1) >> 1)


def chunked(text: str, width: int) -> Iterator[str]:
    """Split a printable string into lines of at most ``width`` characters.

    Args:
        text: The string.
        width: The line width.
    """
    for i in range(0, len(text), width):
        yield text[i : i + width]
