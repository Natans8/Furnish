"""Doodad sets of World of Warcraft WMOs as a database, for spawning them on Epsilon.

A WMO root file names its doodad sets and every doodad placement each set holds. The
build reads those files, resolves each model to the gameobject display that spawns it,
and writes one SQLite database that an addon can be ported from.
"""

FORMAT = 7
"""The database layout's version, written to the ``meta`` table.

Bumped when a table, a column or a meaning changes, so a reader built against one layout
refuses another rather than misreading it.
"""
