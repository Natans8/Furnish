-- The furnishing database. One row of meta, then five tables: a set is a named list of
-- doodad placements, shared by every root that holds the same one; a display id and a
-- gameobject entry each reach the sets of the file they spawn; a map placement names the
-- sets its zone chose.

PRAGMA foreign_keys = ON;

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE sets (
    id   INTEGER PRIMARY KEY,
    name TEXT                       -- as MODS spells it; NULL for the default set, index 0
);

CREATE TABLE wmo_sets (
    file    INTEGER NOT NULL,       -- the root's file id, which a spawned object reports
    "index" INTEGER NOT NULL,       -- the set's position in the root's MODS
    "set"   INTEGER NOT NULL REFERENCES sets(id),
    PRIMARY KEY (file, "index")
) WITHOUT ROWID;

CREATE TABLE root_displays (
    display INTEGER PRIMARY KEY,    -- a gameobject display that spawns a furnished root
    file    INTEGER NOT NULL        -- that root's file id, the key of wmo_sets
) WITHOUT ROWID;

CREATE TABLE blank_roots (
    file INTEGER PRIMARY KEY        -- a root whose every doodad is at scale 0, so it draws none;
) WITHOUT ROWID;                    -- its wmo_sets are the WMO's it was emptied from

CREATE TABLE entries (
    entry INTEGER PRIMARY KEY,      -- a gameobject entry whose object is a furnished root
    file  INTEGER NOT NULL          -- that root's file id, the key of wmo_sets; an
) WITHOUT ROWID;                    -- emptywmo twin's entry names its original

CREATE TABLE placements (
    "set"   INTEGER NOT NULL REFERENCES sets(id),
    seq     INTEGER NOT NULL,       -- the placement's position within the set
    display INTEGER NOT NULL,       -- the doodad's display id
    x       REAL NOT NULL,
    y       REAL NOT NULL,
    z       REAL NOT NULL,
    qx      REAL NOT NULL,
    qy      REAL NOT NULL,
    qz      REAL NOT NULL,
    qw      REAL NOT NULL,
    scale   REAL NOT NULL,
    PRIMARY KEY ("set", seq)
) WITHOUT ROWID;                    -- clustered by set, which is the one way it is read

CREATE TABLE map_sets (
    map   INTEGER NOT NULL,         -- the map id the client reports
    uid   INTEGER NOT NULL,         -- the ADT placement's uniqueId
    "set" INTEGER NOT NULL REFERENCES sets(id),
    PRIMARY KEY (map, uid, "set")
) WITHOUT ROWID;
