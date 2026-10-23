-- The furnishing database. One row of meta, then four tables: a set is a named list of
-- doodad placements, shared by every root that holds the same one; a display id reaches
-- the sets of the file it spawns; a map placement names the sets its zone chose.

PRAGMA foreign_keys = ON;

CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
) WITHOUT ROWID;

CREATE TABLE sets (
    id   INTEGER PRIMARY KEY,
    name TEXT NOT NULL              -- as MODS spells it
);

CREATE TABLE wmo_sets (
    display INTEGER NOT NULL,       -- a display id that spawns the root
    "index" INTEGER NOT NULL,       -- the set's position in the root's MODS
    "set"   INTEGER NOT NULL REFERENCES sets(id),
    PRIMARY KEY (display, "index")
) WITHOUT ROWID;

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
