"""The byte form of one set, as the addon's data file carries it.

A set is packed to bytes, deflated, and spelled in LibDeflate's printable alphabet so it
can sit inside a Lua string literal. The addon reverses the three steps with LibDeflate and
a few lines of byte arithmetic, one set at a time, when a set is asked for, so nothing is
decoded at load.

Nothing is rounded. A placement's numbers are the file's own float32 values, shipped as the
four bytes each one is, so the shipped form carries exactly what the database holds and the
spawn command can be given every digit the server will keep.

The layout, version 1, every integer a varint unless said otherwise::

    u8      version
    varint  rows
    varint  models, then that many display ids, the first whole and the rest as deltas
    per row:
        varint  model index
        f32     x, y, z
        u8      flags              1: a rotation follows, 2: a scale follows
        f32     qx, qy, qz, qw     only under flag 1; identity otherwise
        f32     scale              only under flag 2; 1 otherwise

Rows are sorted by model then position, so deflate meets runs of the same model; the order
a set is spawned in does not matter.
"""

import struct
import zlib
from collections.abc import Iterable, Iterator
from dataclasses import dataclass

VERSION = 1
FLAG_ROTATION = 1
FLAG_SCALE = 2
IDENTITY = (0.0, 0.0, 0.0, 1.0)

_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
_DECODE = {character: index for index, character in enumerate(_ALPHABET)}
_BYTE = 8
_F32 = struct.Struct("<f")


@dataclass(frozen=True, slots=True)
class Row:
    """One placement as the shipped form holds it.

    Attributes:
        display: The doodad's display id.
        position: ``x, y, z`` in yards, relative to the WMO.
        rotation: The quaternion ``x, y, z, w``; ``IDENTITY`` when the file had none.
        scale: The uniform factor, 1 for the model's own size.
    """

    display: int
    position: tuple[float, float, float]
    rotation: tuple[float, float, float, float]
    scale: float


def encode(rows: Iterable[Row]) -> str:
    """Spell a set's rows as the printable string the data file carries.

    Args:
        rows: The set's placements, in any order. Values must be representable as float32,
            which the database's are, since they came from float32 fields.
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
            out += _F32.pack(v)
        flags = (FLAG_ROTATION if row.rotation != IDENTITY else 0) | (
            FLAG_SCALE if row.scale != 1 else 0
        )
        out.append(flags)
        if flags & FLAG_ROTATION:
            for v in row.rotation:
                out += _F32.pack(v)
        if flags & FLAG_SCALE:
            out += _F32.pack(row.scale)
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
        position = (reader.f32(), reader.f32(), reader.f32())
        flags = reader.u8()
        rotation = (
            (reader.f32(), reader.f32(), reader.f32(), reader.f32())
            if flags & FLAG_ROTATION
            else IDENTITY
        )
        scale = reader.f32() if flags & FLAG_SCALE else 1.0
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
        bits += _BYTE
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

    def f32(self) -> float:
        value: float = _F32.unpack_from(self._data, self._at)[0]
        self._at += _F32.size
        return value


def chunked(text: str, width: int) -> Iterator[str]:
    """Split a printable string into lines of at most ``width`` characters.

    Args:
        text: The string.
        width: The line width.
    """
    for i in range(0, len(text), width):
        yield text[i : i + width]
