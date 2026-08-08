-- Driver: screenshot the fireflies over tall grass.
--
-- The forest's own particle, dealt over a map's grass instead of over its
-- air, on every outdoor map rather than the one with an atmosphere entry
-- (see ForestAtmos, "the grass fireflies"). What this has to show:
--
--   * a route with tall grass on it, at night, with lights over the grass
--     and none over the road beside it -- the whole point of placing them
--     by isGrassCell rather than by the grass GRAPHIC;
--   * the same vantage by DAY, which must have none at all;
--   * a MAP SEAM at night: the swarm has to carry onto the connected
--     neighbour, whose grass is drawn in full;
--   * Viridian Forest, where the grass swarm stands alongside the
--     authored map-wide one and neither should read as double;
--   * and the row OFF, which must be pixel-identical to a run from before
--     the feature existed.
--
-- Deterministic on the same recipe forest_fog_shots runs: encounters
-- killed, tile animation frozen, the atmosphere's clock pinned -- so an
-- AB_TAG=before/after pair diffs clean. The grass deal itself is seeded
-- off the map id and never moves.
--
--   SHOT_DIR=.scratchpad/grassfly AB_TAG=after \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/grass_firefly_shots.lua \
--   lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or ".scratchpad/grassfly")
    .. "/" .. (os.getenv("AB_TAG") or "after")
  -- U.shot's own mkdir is Unix-flavoured and fails silently on Windows
  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  local exports = game.mods and game.mods.exports
  local handle = exports and exports.DRAMATIC_SHAPE
  if not (handle and handle.lib) then
    U.log("DRAMATIC_SHAPE is not loaded -- check the ds_fp_ceiling conflict")
    return
  end
  local lib = handle.lib
  local DayNight = lib.require("DayNight")
  local ChunkMesher = lib.require("ChunkMesher")
  local Voxel = lib.require("VoxelState")
  local ForestAtmos = lib.require("ForestAtmos")

  -- Prove the running game is reading THIS copy of the file before any
  -- shot is trusted: an install in the save dir shadows the repo, and a
  -- stale one makes an unchanged AFTER look like a broken feature.
  if not ForestAtmos.grassFliesFor then
    U.log("the loaded ForestAtmos has no grassFliesFor -- a STALE copy is "
          .. "being read, not this repo. Shots would be meaningless.")
    return
  end
  U.log("grass fireflies present in the loaded mod -- shooting")

  -- ------- the determinism recipe (see forest_fog_shots)
  require("src.world.OverworldController").rollEncounter =
    function() return nil end
  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end
  local Zoom = require("src.render.Zoom")
  pcall(function()
    game.save.options.zoom = 1
    Zoom.applyOptions(game.save.options)
  end)
  ForestAtmos.frozen = true
  ForestAtmos.time = 5

  local function setTime(value)
    DayNight.setting:sync(value)
    DayNight.update(0)
  end

  local function settle()
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    for _ = 1, 300 do
      if Voxel.t >= 1 and Voxel.ready and ChunkMesher.pending() == 0 then
        break
      end
      U.wait(1)
    end
    U.wait(40)
  end

  local function go(mapId, x, y, face, rung)
    U.teleport(game, mapId, x, y, face or "up")
    Pipelines.setLevel("voxel", rung or 5)
    Pipelines.setLevel("tiltshift", 0)   -- judge the lights, not the blur
    settle()
  end

  ForestAtmos.setting:sync("full")

  -- ------- find a route the deal actually put fireflies on
  --
  -- Rather than guessing a cell with grass in it, ask the layout: it is
  -- the same list the mesh is built from, so a vantage picked out of it
  -- is guaranteed to have lights in frame.
  local ROUTES = { "ROUTE_1", "ROUTE_2", "ROUTE_22", "ROUTE_3" }
  local routeId, spotX, spotY
  for _, id in ipairs(ROUTES) do
    if game.data.maps and game.data.maps[id] then
      go(id, 5, 5)
      local map = game.stack:top() and game.stack:top().map
      local flies = map and ForestAtmos.grassFliesFor(map)
      if flies and #flies > 0 then
        -- the middle of the swarm, so the frame holds many rather than one
        local sx, sy, n = 0, 0, 0
        for _, fly in ipairs(flies) do
          sx, sy, n = sx + fly.x, sy + fly.z, n + 1
        end
        routeId = id
        spotX = math.floor(sx / n / 16)
        spotY = math.floor(sy / n / 16)
        U.log(("%s: %d fireflies over its grass, centre cell %d,%d")
              :format(id, #flies, spotX, spotY))
        break
      end
      U.log(id .. ": no grass fireflies dealt")
    end
  end

  if not routeId then
    U.log("no route in this dataset got a grass swarm -- nothing to shoot")
    return
  end

  -- ------- the route: night, then the same frame by day
  setTime("night")
  go(routeId, spotX, spotY + 3, "up")
  U.shot(game, ROOT .. "/10_route_night.png")
  go(routeId, spotX, spotY + 3, "up", 6)      -- 1ST: eye level in the grass
  U.shot(game, ROOT .. "/11_route_night_fp.png")
  setTime("day")
  go(routeId, spotX, spotY + 3, "up")
  U.shot(game, ROOT .. "/12_route_day.png")   -- must have none at all
  setTime("dusk")
  go(routeId, spotX, spotY + 3, "up")
  U.shot(game, ROOT .. "/13_route_dusk.png")  -- coming on, not yet full

  -- ------- the seam: the swarm has to carry onto the connected neighbour
  --
  -- Stand at the map's own edge looking out of it. The neighbour's ground,
  -- trees and grass are all drawn; if its fireflies were not, the picture
  -- would have a line across it where the lights stopped.
  setTime("night")
  do
    local map = game.stack:top() and game.stack:top().map
    local h = map and map.heightCells or 20
    go(routeId, spotX, math.max(h - 2, 0), "down")
    U.shot(game, ROOT .. "/20_seam_south_night.png")
    go(routeId, spotX, 1, "up")
    U.shot(game, ROOT .. "/21_seam_north_night.png")
  end

  -- ------- Viridian Forest: the authored swarm and the grass one together
  if game.data.maps and game.data.maps.VIRIDIAN_FOREST then
    setTime("night")
    go("VIRIDIAN_FOREST", 17, 20)
    U.shot(game, ROOT .. "/30_forest_night.png")
    go("VIRIDIAN_FOREST", 16, 24)
    U.shot(game, ROOT .. "/31_forest_night_b.png")
    setTime("day")
    go("VIRIDIAN_FOREST", 17, 20)
    U.shot(game, ROOT .. "/32_forest_day.png")  -- pollen, no fireflies
  end

  -- ------- the controls
  setTime("night")
  ForestAtmos.setting:sync("low")
  go(routeId, spotX, spotY + 3, "up")
  U.shot(game, ROOT .. "/40_route_night_low.png")   -- the tuft cards alone
  ForestAtmos.setting:sync("off")
  go(routeId, spotX, spotY + 3, "up")
  U.shot(game, ROOT .. "/41_route_night_off.png")   -- a pre-feature run

  ForestAtmos.setting:sync("full")
  ForestAtmos.frozen = false
  setTime("day")
  U.log("done -- " .. ROOT)
end
