"""The spawn order: a trail from the origin, each step to the nearest placement left."""

import math

from furnish.codec import IDENTITY, Row
from furnish.order import trail
from tests.files import varied_placements


def at(*points: tuple[float, float, float]) -> list[Row]:
    return [Row(i + 1, point, IDENTITY, 1.0) for i, point in enumerate(points)]


def test_the_trail_starts_nearest_the_origin_and_steps_to_the_nearest_left() -> None:
    rows = [Row(d, p.position, p.rotation, p.scale) for d, p in varied_placements(300, 7)]
    walked = trail(rows)
    assert sorted(walked, key=repr) == sorted(rows, key=repr)
    here: tuple[float, float, float] = (0.0, 0.0, 0.0)
    left = list(rows)
    for row in walked:
        nearest = min(math.dist(here, r.position) for r in left)
        assert math.dist(here, row.position) <= nearest + 1e-9
        left.remove(row)
        here = row.position


def test_a_line_is_walked_from_its_near_end() -> None:
    walked = trail(at((3.0, 0.0, 0.0), (1.0, 0.0, 0.0), (2.0, 0.0, 0.0)))
    assert [row.position[0] for row in walked] == [1.0, 2.0, 3.0]


def test_a_tie_goes_to_the_row_given_first() -> None:
    walked = trail(at((-1.0, 0.0, 0.0), (1.0, 0.0, 0.0)))
    assert [row.display for row in walked] == [1, 2]


def test_an_empty_set_has_an_empty_trail() -> None:
    assert trail([]) == []
