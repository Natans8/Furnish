"""The public tables the build joins the files to, fetched once and cached.

Three of them, none Epsilon's. The community listfile turns an asset path into its file
id, which is what a root on disk lacks. wago.tools' export of ``GameObjectDisplayInfo``
turns a file id into the gameobject display that spawns it. Its export of ``Map`` turns a
map directory name into the map id the client reports.
"""

import csv
import json
import urllib.error
import urllib.request
from collections.abc import Iterator
from pathlib import Path

LISTFILE_RELEASE_API = "https://api.github.com/repos/wowdev/wow-listfile/releases/latest"
LISTFILE_ASSET = "community-listfile-withcapitals.csv"
WAGO_CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
USER_AGENT = "furnish (https://github.com/Natans8/Furnish)"


def fetch(url: str, into: Path) -> Path:
    """Download ``url`` to ``into`` unless it is already there, and return the path.

    Args:
        url: What to fetch.
        into: Where it lands. An existing file is trusted; delete it to refetch.
    """
    if not into.exists():
        into.parent.mkdir(parents=True, exist_ok=True)
        into.write_bytes(_get(url, 120))
    return into


def _get(url: str, timeout: int) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data: bytes = response.read()
            return data
    except urllib.error.URLError as error:
        raise RuntimeError(f"could not fetch {url}: {error}") from error


def listfile(cache: Path) -> Path:
    """The community listfile, from the latest ``wowdev/wow-listfile`` release.

    Args:
        cache: The build's cache directory.
    """
    into = cache / "listfile" / LISTFILE_ASSET
    if into.exists():
        return into
    release = json.loads(_get(LISTFILE_RELEASE_API, 60))
    assets = {asset["name"]: asset["browser_download_url"] for asset in release["assets"]}
    if LISTFILE_ASSET not in assets:
        raise LookupError(f"release {release['tag_name']} has no {LISTFILE_ASSET}")
    return fetch(assets[LISTFILE_ASSET], into)


def wago_table(table: str, build: str, cache: Path) -> Path:
    """A client table as wago.tools exports it, one CSV per table and build.

    Args:
        table: The table's name, such as ``GameObjectDisplayInfo``.
        build: The client build, such as ``9.2.7.45745``.
        cache: The build's cache directory.
    """
    return fetch(WAGO_CSV_URL.format(table=table, build=build), cache / build / f"{table}.csv")


def path_key(path: str) -> str:
    """The spelling a path is looked up by: lower case, forward slashes.

    Args:
        path: A path as a file or a listfile spells it.
    """
    return path.lower().replace(chr(92), "/")


def read_listfile(path: Path) -> Iterator[tuple[int, str]]:
    """Yield ``(file id, path)`` from a listfile, paths as written.

    Args:
        path: The listfile, ``id;path`` per line.
    """
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            file_id, _, name = line.rstrip("\n").partition(";")
            if file_id.isdigit():
                yield int(file_id), name


def read_csv(path: Path) -> Iterator[dict[str, str]]:
    """Yield a wago CSV's rows as dicts keyed by the header.

    Args:
        path: The CSV.
    """
    with path.open(encoding="utf-8", newline="") as handle:
        yield from csv.DictReader(handle)
