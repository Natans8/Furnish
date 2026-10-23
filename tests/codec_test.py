from furnish.codec import (
    IDENTITY,
    Row,
    decode,
    encode,
    for_print,
    from_print,
    quantise,
    varint,
    zigzag,
)


def test_varints_round_small_and_large() -> None:
    assert varint(0) == b"\x00"
    assert varint(127) == b"\x7f"
    assert varint(128) == b"\x80\x01"
    assert zigzag(0) == b"\x00"
    assert zigzag(-1) == b"\x01"
    assert zigzag(1) == b"\x02"


def test_print_alphabet_round_trips_any_length() -> None:
    for data in (b"", b"a", b"ab", b"abc", bytes(range(256))):
        assert from_print(for_print(data)) == data


def test_quantise_reduces_to_the_shipped_grain() -> None:
    row = quantise(30262, (1.234, -2.346, 0.0051), (0.0, 0.0, 0.70710678, 0.70710678), 0.8504)
    assert row == Row(30262, (123, -235, 1), (0, 0, 7071, 7071), 850)


def test_a_set_round_trips_sorted_by_model() -> None:
    rows = [
        Row(200, (5, 5, 5), IDENTITY, 1000),
        Row(100, (-300, 0, 20), (0, 0, 7071, 7071), 1000),
        Row(100, (-400, 0, 20), IDENTITY, 850),
    ]
    assert decode(encode(rows)) == [rows[2], rows[1], rows[0]]


def test_the_empty_set_round_trips() -> None:
    assert decode(encode([])) == []
