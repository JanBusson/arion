import pytest

from arion_api.streaming import ByteRange, InvalidByteRange, parse_byte_range


@pytest.mark.parametrize(
    ("header", "size", "expected"),
    [
        ("bytes=2-5", 10, ByteRange(2, 5)),
        ("bytes=2-", 10, ByteRange(2, 9)),
        ("bytes=-4", 10, ByteRange(6, 9)),
        ("bytes=-20", 10, ByteRange(0, 9)),
        ("bytes=2-99", 10, ByteRange(2, 9)),
        ("BYTES=0-0", 1, ByteRange(0, 0)),
    ],
)
def test_parse_byte_range(
    header: str, size: int, expected: ByteRange
) -> None:
    selected = parse_byte_range(header, size)

    assert selected == expected
    assert selected.length == expected.end - expected.start + 1


@pytest.mark.parametrize(
    ("header", "size"),
    [
        ("bytes=", 10),
        ("items=0-1", 10),
        ("bytes=0-1,4-5", 10),
        ("bytes=abc-def", 10),
        ("bytes=5-4", 10),
        ("bytes=-0", 10),
        ("bytes=10-", 10),
        ("bytes=0-0", 0),
        ("bytes =0-1", 10),
        ("bytes=0 -1", 10),
    ],
)
def test_parse_byte_range_rejects_invalid_or_unsatisfiable_values(
    header: str, size: int
) -> None:
    with pytest.raises(InvalidByteRange):
        parse_byte_range(header, size)


def test_parse_byte_range_rejects_negative_object_size() -> None:
    with pytest.raises(ValueError, match="object_size"):
        parse_byte_range("bytes=0-0", -1)
