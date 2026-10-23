"""The chunk container that WMO and ADT files share.

Both formats are a flat sequence of ``tag, size, payload`` records, the four-character tag
stored reversed on disk (``MVER`` reads as ``REVM``). Nothing here knows what a chunk means;
the format readers do.
"""

import struct
from collections.abc import Iterator

_HEADER = struct.Struct("<4sI")


def chunks(raw: bytes) -> Iterator[tuple[bytes, memoryview]]:
    """Yield every ``(tag, payload)`` pair of a chunked file, tags in reading order.

    A truncated trailing chunk is cut at the end of the file rather than raised on, because
    Blizzard's own files carry a few and the client reads them the same way.

    Args:
        raw: The whole file.
    """
    view = memoryview(raw)
    offset = 0
    while offset + _HEADER.size <= len(view):
        tag, size = _HEADER.unpack_from(view, offset)
        offset += _HEADER.size
        yield tag[::-1], view[offset : offset + size]
        offset += size


def chunk_map(raw: bytes) -> dict[bytes, memoryview]:
    """The chunks of a file by tag, keeping the last of any repeated tag.

    Root files repeat no tag that matters here, so a map is the convenient shape.

    Args:
        raw: The whole file.
    """
    return dict(chunks(raw))
