"""The order a set spawns in: a trail a player can follow with their eyes.

The walk starts at the placement nearest the building's origin, which is where a set is
anchored, and always moves to the nearest placement not yet placed. Each object appears beside
the one before it, so the furnishing creeps across the building instead of popping up at
random; the walk jumps only when it has finished an area and moves on to the nearest one left.
Ties go to the placement that comes first in the order given, so the trail is the same on
every export.
"""

from collections.abc import Sequence

import numpy as np

from furnish.codec import Row


def trail(rows: Sequence[Row]) -> list[Row]:
    """The rows in the order a trail from the origin visits them.

    Args:
        rows: A set's placements, in the file's order.
    """
    if not rows:
        return []
    points = np.array([row.position for row in rows], dtype=np.float64)
    placed = np.zeros(len(rows), dtype=bool)
    here = np.zeros(3, dtype=np.float64)
    out: list[Row] = []
    for _ in rows:
        distances = ((points - here) ** 2).sum(axis=1)
        distances[placed] = np.inf
        nearest = int(np.argmin(distances))
        placed[nearest] = True
        here = points[nearest]
        out.append(rows[nearest])
    return out
