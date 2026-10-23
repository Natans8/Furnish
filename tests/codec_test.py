import pytest

from furnish.codec import IDENTITY, Row, chunked, decode, encode, for_print, from_print, varint
from furnish.export import LINE_WIDTH
from tests.files import varied_placements


def test_varints_round_small_and_large() -> None:
    assert varint(0) == b"\x00"
    assert varint(127) == b"\x7f"
    assert varint(128) == b"\x80\x01"
    assert varint(2**31) == b"\x80\x80\x80\x80\x08"


def test_print_alphabet_round_trips_any_length() -> None:
    for data in (b"", b"a", b"ab", b"abc", bytes(range(256))):
        assert from_print(for_print(data)) == data


def test_a_set_round_trips_exactly_in_the_order_given() -> None:
    rows = [
        Row(200, (0.05, 0.05, 0.05), IDENTITY, 1.0),
        Row(100, (-300.75, 0.0, 20.125), (0.0, 0.0, 0.5, 0.75), 1.0),
        Row(100, (-400.5, 0.0, 20.125), IDENTITY, 0.85009765625),
    ]
    # 0.05 is not a float32 value; it comes back as the nearest one, which is what the
    # database holds for any value read out of a file.
    decoded = decode(encode(rows))
    assert decoded[0].display == 200
    assert abs(decoded[0].position[0] - 0.05) < 1e-8
    assert decoded[1:] == rows[1:]


def test_the_empty_set_round_trips() -> None:
    assert decode(encode([])) == []


@pytest.mark.parametrize("count", [1, 7, 300])
def test_varied_sets_round_trip_exactly(count: int) -> None:
    rows = [Row(d, p.position, p.rotation, p.scale) for d, p in varied_placements(count, count)]
    assert decode(encode(rows)) == rows


@pytest.mark.parametrize(
    "length", [0, 1, LINE_WIDTH - 1, LINE_WIDTH, LINE_WIDTH + 1, 3 * LINE_WIDTH + 17]
)
def test_chunked_lines_join_back_and_none_is_wider(length: int) -> None:
    text = "".join("abc"[i % 3] for i in range(length))
    lines = list(chunked(text, LINE_WIDTH))
    assert "".join(lines) == text
    assert all(0 < len(line) <= LINE_WIDTH for line in lines)
    assert len(lines) == -(-length // LINE_WIDTH)


def test_a_line_break_is_no_letter_of_the_print_alphabet() -> None:
    # The exporter breaks a long string across lines, so a reader drops the breaks first.
    with pytest.raises(KeyError):
        from_print(for_print(b"furnish") + "\n")
