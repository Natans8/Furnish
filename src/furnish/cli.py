"""The command line: ``furnish build``."""

import argparse
import dataclasses
import sys
from pathlib import Path

from furnish.build import Inputs, build
from furnish.displays import vendored_overlay
from furnish.sources import listfile, wago_table

DEFAULT_BUILD = "9.2.7.45745"
"""Epsilon's client build, whose tables the default build joins against."""


def main(argv: list[str] | None = None) -> int:
    """Run the command line and return the exit status.

    Args:
        argv: The arguments after the program name; None reads ``sys.argv``.
    """
    parser = argparse.ArgumentParser(prog="furnish", description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    builder = commands.add_parser("build", help="read WMO and ADT files and write the database")
    builder.add_argument(
        "--roots", type=Path, required=True, help="a directory of WMO files at their listfile paths"
    )
    builder.add_argument(
        "--maps", type=Path, help="a directory of ADT files at their listfile paths"
    )
    builder.add_argument(
        "--build", default=DEFAULT_BUILD, help="the client build whose tables to fetch"
    )
    builder.add_argument(
        "--cache", type=Path, default=Path(".cache"), help="where fetched tables are kept"
    )
    builder.add_argument(
        "--out", type=Path, default=Path("furnish.sqlite"), help="the database to write"
    )
    builder.add_argument(
        "--no-overlay", action="store_true", help="ignore the vendored Epsilon display rows"
    )
    args = parser.parse_args(argv)

    inputs = Inputs(
        roots=args.roots,
        maps=args.maps,
        listfile=listfile(args.cache),
        display_table=wago_table("GameObjectDisplayInfo", args.build, args.cache),
        map_table=wago_table("Map", args.build, args.cache),
        overlay=[] if args.no_overlay else vendored_overlay(),
        build=args.build,
    )
    report = build(inputs, args.out)
    for name, value in dataclasses.asdict(report).items():
        print(f"{name.replace('_', ' ')}: {value:,}", file=sys.stderr)
    print(args.out)
    return 0
