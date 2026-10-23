from furnish.codec import IDENTITY, Row, decode, encode, for_print, from_print, varint


def test_varints_round_small_and_large() -> None:
    assert varint(0) == b"\x00"
    assert varint(127) == b"\x7f"
    assert varint(128) == b"\x80\x01"
    assert varint(2**31) == b"\x80\x80\x80\x80\x08"


def test_print_alphabet_round_trips_any_length() -> None:
    for data in (b"", b"a", b"ab", b"abc", bytes(range(256))):
        assert from_print(for_print(data)) == data


def test_a_set_round_trips_exactly_sorted_by_model() -> None:
    rows = [
        Row(200, (0.05, 0.05, 0.05), IDENTITY, 1.0),
        Row(100, (-300.75, 0.0, 20.125), (0.0, 0.0, 0.5, 0.75), 1.0),
        Row(100, (-400.5, 0.0, 20.125), IDENTITY, 0.85009765625),
    ]
    # 0.05 is not a float32 value; it comes back as the nearest one, which is what the
    # database holds for any value read out of a file.
    decoded = decode(encode(rows))
    assert decoded[0] == rows[2]
    assert decoded[1] == rows[1]
    assert decoded[2].display == 200
    assert abs(decoded[2].position[0] - 0.05) < 1e-8


def test_the_empty_set_round_trips() -> None:
    assert decode(encode([])) == []
