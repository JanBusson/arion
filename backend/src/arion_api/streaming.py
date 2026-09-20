"""HTTP byte-range parsing for audio streaming."""

from __future__ import annotations

import re
from dataclasses import dataclass

_SINGLE_RANGE = re.compile(r"^(\d*)-(\d*)$")


class InvalidByteRange(ValueError):
    """Raised when a Range header cannot select one satisfiable byte range."""


@dataclass(frozen=True, slots=True)
class ByteRange:
    """An inclusive byte interval within an object."""

    start: int
    end: int

    @property
    def length(self) -> int:
        return self.end - self.start + 1


def parse_byte_range(value: str, object_size: int) -> ByteRange:
    """Parse one HTTP bytes range against an object of ``object_size`` bytes."""

    if object_size < 0:
        raise ValueError("object_size must not be negative")

    try:
        unit, range_value = value.strip().split("=", 1)
    except ValueError as error:
        raise InvalidByteRange() from error
    if unit.lower() != "bytes" or "," in range_value:
        raise InvalidByteRange()

    match = _SINGLE_RANGE.fullmatch(range_value)
    if match is None:
        raise InvalidByteRange()
    start_value, end_value = match.groups()
    if not start_value and not end_value:
        raise InvalidByteRange()
    if object_size == 0:
        raise InvalidByteRange()

    if not start_value:
        suffix_length = int(end_value)
        if suffix_length <= 0:
            raise InvalidByteRange()
        return ByteRange(max(0, object_size - suffix_length), object_size - 1)

    start = int(start_value)
    if start >= object_size:
        raise InvalidByteRange()
    if not end_value:
        return ByteRange(start, object_size - 1)

    requested_end = int(end_value)
    if start > requested_end:
        raise InvalidByteRange()
    return ByteRange(start, min(requested_end, object_size - 1))
