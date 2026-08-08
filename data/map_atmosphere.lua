-- What hangs in the air of each map.
--
-- One entry per map that has an ATMOSPHERE: a ground fog the scene shader
-- folds every surface into, and volumetric god rays -- light let down
-- through an INVISIBLE canopy hanging above the map's real geometry, as
-- if the trees drawn are only the understorey of something taller. The
-- rays are not placed: a per-pixel march (see ForestAtmos) reads the
-- frame's own depth and the sun's own shadow map, so the beams stand
-- exactly where light really breaks between the tree hulls, trees and
-- characters carve dark columns through them, and a wind-blown leaf
-- field at the canopy plane opens and closes them like foliage moving
-- overhead. The light leans along the mod's fixed noon shear (the one
-- light a canopy map ever gets -- see DayNight.CANOPY); only its COLOUR
-- and STRENGTH follow the clock: gold spears of sun by day, silver moon
-- rays after dark, pollen adrift in the day's beams and fireflies once
-- they cool. The fireflies are the one part of this that reaches past the
-- table: they also come out over TALL GRASS on every outdoor map, entry
-- or no entry (see grassFlies below).
--
-- A map with no entry here has no atmosphere at all: no fog uniform is
-- raised, no march runs, nothing is spent. That is the contract a new
-- map opts into by adding a line, and what a stale entry degrades to if
-- its map id ever stops existing.
--
-- The knobs, in world pixels unless said otherwise (a map cell is 16):
--
--   canopyY   where the invisible canopy hangs. MUST clear the tallest
--             real geometry under it (Viridian's carved tree hulls top
--             at y = 32) -- a beam is alpha ZERO at this height and only
--             fades in below it, so a canopy at or under the tree tops
--             would cut every ray off before it cleared the leaves.
--   fadeTo    the height by which a descending ray reaches full strength.
--   fog       density  how fast distance dissolves into the haze
--                      (1 - exp(-density * distance-past-start))
--             start    how many pixels out the dissolve begins
--             heightK  how quickly the fog thins with ALTITUDE
--                      (exp(-y * heightK): 0.02 halves it by y = 35)
--   rays      strength  overall in-scatter gain on the march
--             reach     how far out the march walks, in world px
--   motes     count of pollen/dust flecks adrift in the daylight beams
--   fireflies count of the night shift, dealt over the map's whole volume
--   seed      the xorshift seed the particle deal runs on
--   grassFlies  per  fireflies dealt per TALL GRASS cell (default 0.8)
--               cap  and the most one map may have of them (default 200)
--
-- That last row is the odd one out, and the only knob here a map does not
-- need an entry to get. The GRASS fireflies are dealt over a map's tall
-- grass rather than over its air, and every outdoor map has them -- grass
-- is the entry, so a route gets fireflies after dark without a line here
-- and a map with no grass on it deals none. What an entry buys is TUNING:
-- a `grassFlies` row moves the two numbers off their defaults, and that
-- is the whole of it. See ForestAtmos, under "the grass fireflies".
--
-- Two caveats for maps opting in later: the water pass has no fog term,
-- so a lake under heavy haze stays clear-day sharp in its reflections;
-- and the march runs after the water's mirror copy, so beams will not
-- appear IN those reflections either. Neither can bite in a map without
-- water.

return {
  ["VIRIDIAN_FOREST"] = {
    canopyY = 56,
    fadeTo = 28,
    fog = { density = 0.0045, start = 64, heightK = 0.02 },
    -- strength is calibrated against the march's real integral: the
    -- under-canopy stretch of an orbit ray is short and thinly dense, so
    -- the raw accumulation for a fully lit beam core is a few percent --
    -- this gain lands it near +0.3 on screen. Halve it for a whisper,
    -- double it for cathedral light.
    rays = { strength = 16, reach = 380 },
    motes = { count = 96 },
    fireflies = { count = 48 },
    seed = 0x51D,
  },
}
