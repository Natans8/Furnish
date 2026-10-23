"""The public tables the build joins the files to, fetched once and cached.

Three of them, none Epsilon's. The community listfile turns an asset path into its file
id, which is what a root on disk lacks. wago.tools' export of ``GameObjectDisplayInfo``
turns a file id into the gameobject display that spawns it. Its export of ``Map`` turns a
map directory name into the map id the client reports.
"""

import csv
import gzip
import json
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Iterator
from pathlib import Path

LISTFILE_RELEASE_API = "https://api.github.com/repos/wowdev/wow-listfile/releases/latest"
LISTFILE_ASSET = "community-listfile-withcapitals.csv"
WAGO_CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
USER_AGENT = "furnish (https://github.com/Natans8/Furnish)"
ATTEMPTS = 3
"""How many times a fetch is tried before it is given up on."""
BACKOFF = 2.0
"""Seconds before the second attempt; each later wait doubles."""
SERVER_ERROR = 500
"""The first HTTP status that says the server, not the request, failed."""


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


def _get(url: str, timeout: int, sleep: Callable[[float], None] = time.sleep) -> bytes:
    """The body at ``url``, tried again after a transient failure.

    A connection that drops, a timeout or a server-side error is tried ``ATTEMPTS`` times
    with a doubling wait between; a client-side refusal such as a 404 is not, since asking
    again changes nothing.

    Args:
        url: What to fetch.
        timeout: Seconds to wait on one attempt.
        sleep: How to wait between attempts; a test passes one that does not.

    Raises:
        RuntimeError: every attempt failed, or the server refused the request.
    """
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(1, ATTEMPTS + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                data: bytes = response.read()
                return data
        except urllib.error.HTTPError as error:
            if error.code < SERVER_ERROR:
                raise RuntimeError(f"{url} was refused: HTTP {error.code}") from error
            last: Exception = error
        except (urllib.error.URLError, TimeoutError) as error:
            last = error
        if attempt < ATTEMPTS:
            sleep(BACKOFF * 2 ** (attempt - 1))
    raise RuntimeError(f"could not fetch {url} in {ATTEMPTS} attempts: {last}") from last


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
        path: The listfile, ``id;path`` per line, gzipped when its name ends in ``.gz``.
    """
    opener = gzip.open if path.suffix == ".gz" else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as handle:
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
