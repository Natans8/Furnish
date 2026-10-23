"""The build: files in, one database out.

Every WMO root under the roots directory is read, its sets and placements resolved to
display ids and written, and every ADT object file under the maps directory contributes
which set each of its WMO placements draws. The tables the join needs are passed in as
paths, so the build itself touches no network and a test can hand it small ones.
"""

import re
from collections.abc import Iterator
from dataclasses import dataclass, field
from pathlib import Path

from tqdm import tqdm

from furnish.adt import read_placements
from furnish.database import Database
from furnish.displays import preferred, spawners
from furnish.sources import path_key, read_csv, read_listfile
from furnish.wmo import Placement, Root, read_root

GROUP_FILE = re.compile(r"_\d{3}(_lod\d)?\.wmo$", re.IGNORECASE)
"""A WMO group file's name ends in a three-digit group number; a root's does not."""

OBJECT_FILE = re.compile(r"_obj0\.adt$", re.IGNORECASE)
"""The map tile file that carries WMO placements.

Its ``_obj1`` twin repeats them for the far view and is left alone.
"""

MAP_DIRECTORY = re.compile(r"(?:^|/)world/maps/([^/]+)/", re.IGNORECASE)
"""Where a tile's path names its map."""


@dataclass(frozen=True, slots=True)
class Inputs:
    """Where the build reads from.

    Attributes:
        roots: A directory of WMO files, each at its listfile path or named ``<id>.wmo``.
        maps: A directory of ADT files at their listfile paths, or None to skip ``map_sets``.
        listfile: The community listfile.
        display_table: wago's ``GameObjectDisplayInfo`` CSV.
        map_table: wago's ``Map`` CSV.
        overlay: Extra ``(file id, display)`` rows that outrank the table's.
        build: The client build the tables came from, recorded in ``meta``.
    """

    roots: Path
    maps: Path | None
    listfile: Path
    display_table: Path
    map_table: Path
    overlay: list[tuple[int, int]] = field(default_factory=list)
    build: str = ""


@dataclass(slots=True)
class Report:
    """What the build did, for the log line at the end.

    A slot is a set or placement a root asked for; a row is one written, after identical sets
    were shared.
    """

    roots_read: int = 0
    roots_without_display: int = 0
    roots_without_doodads: int = 0
    roots_unresolved: int = 0
    roots_unreadable: int = 0
    empty_sets: int = 0
    set_slots: int = 0
    placement_slots: int = 0
    sets: int = 0
    placements: int = 0
    shared_sets: int = 0
    blank_slots: int = 0
    models_without_display: int = 0
    tiles_read: int = 0
    tiles_without_map: int = 0
    map_rows: int = 0
    map_rows_unresolved: int = 0


def build(inputs: Inputs, out: Path) -> Report:
    """Write the database at ``out`` from ``inputs`` and say what went in.

    Args:
        inputs: The files and tables.
        out: The database path; an existing file is replaced.
    """
    report = Report()
    path_to_id = {path_key(path): file_id for file_id, path in read_listfile(inputs.listfile)}
    spawnable = spawners(inputs.display_table, inputs.overlay)
    displays = {file_id: preferred(ids) for file_id, ids in spawnable.items()}
    with Database(out) as database:
        database.meta({"build": inputs.build})
        sets_by_root = _write_roots(inputs.roots, path_to_id, displays, spawnable, database, report)
        if inputs.maps is not None:
            maps = {row["Directory"].lower(): int(row["ID"]) for row in read_csv(inputs.map_table)}
            _write_maps(inputs.maps, path_to_id, maps, sets_by_root, database, report)
        report.sets = database.sets
        report.placements = database.placements
        report.shared_sets = database.shared_sets
    return report


def _write_roots(
    directory: Path,
    path_to_id: dict[str, int],
    displays: dict[int, int],
    spawners: dict[int, tuple[int, ...]],
    database: Database,
    report: Report,
) -> dict[int, dict[int, int]]:
    sets_by_root: dict[int, dict[int, int]] = {}
    for path in tqdm(sorted(_files(directory, ".wmo")), desc="roots", unit="root"):
        if GROUP_FILE.search(path.name):
            continue
        file_id = _file_id(path, directory, path_to_id)
        if file_id is None:
            report.roots_unresolved += 1
            continue
        if file_id not in spawners:
            report.roots_without_display += 1
            continue
        try:
            root = read_root(path.read_bytes(), path_to_id)
        except ValueError as error:
            tqdm.write(f"skipped {path}: {error}")
            report.roots_unreadable += 1
            continue
        kept = _spawnable(root, displays, report)
        if not kept:
            report.roots_without_doodads += 1
            continue
        report.roots_read += 1
        set_ids = {index: database.add_set(name, rows) for index, (name, rows) in kept.items()}
        sets_by_root[file_id] = set_ids
        database.add_wmo_sets((file_id, index, set_id) for index, set_id in set_ids.items())
    return sets_by_root


def _spawnable(
    root: Root, displays: dict[int, int], report: Report
) -> dict[int, tuple[str | None, list[tuple[int, Placement]]]]:
    """The root's sets that still hold a placement once the unspawnable are dropped.

    Keyed by the set's position in ``MODS``, which stays meaningful when a set between two
    kept ones is dropped. Index 0 is the default set, named ``Set_$DefaultGlobal`` or
    ``DefaultGlobal`` in every file, so its name is not carried.
    """
    kept = {}
    for index, doodad_set in enumerate(root.sets):
        rows = []
        for placement in doodad_set.placements:
            if placement.model == 0:
                report.blank_slots += 1
            elif placement.model not in displays:
                report.models_without_display += 1
            else:
                rows.append((displays[placement.model], placement))
        if not rows:
            report.empty_sets += 1
            continue
        kept[index] = (doodad_set.name if index else None, rows)
        report.set_slots += 1
        report.placement_slots += len(rows)
    return kept


def _write_maps(
    directory: Path,
    path_to_id: dict[str, int],
    maps: dict[str, int],
    sets_by_root: dict[int, dict[int, int]],
    database: Database,
    report: Report,
) -> None:
    for path in tqdm(sorted(_files(directory, ".adt")), desc="tiles", unit="tile"):
        if not OBJECT_FILE.search(path.name):
            continue
        match = MAP_DIRECTORY.search(path.as_posix())
        directory_name = match.group(1).lower() if match else None
        if directory_name is None or directory_name not in maps:
            report.tiles_without_map += 1
            continue
        report.tiles_read += 1
        map_id = maps[directory_name]
        rows: list[tuple[int, int, int]] = []
        for placement in read_placements(path.read_bytes(), path_to_id):
            set_ids = sets_by_root.get(placement.model)
            if set_ids is None:
                report.map_rows_unresolved += 1
                continue
            rows.extend(
                (map_id, placement.unique_id, set_ids[index])
                for index in placement.sets
                if index in set_ids
            )
        database.add_map_sets(rows)
        report.map_rows += len(rows)


def _files(directory: Path, suffix: str) -> Iterator[Path]:
    for path in directory.rglob(f"*{suffix}"):
        if path.is_file():
            yield path


def _file_id(path: Path, directory: Path, path_to_id: dict[str, int]) -> int | None:
    if path.stem.isdigit():
        return int(path.stem)
    return path_to_id.get(path_key(path.relative_to(directory).as_posix()))
