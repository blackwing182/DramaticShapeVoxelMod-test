-- Driver: ONE shiny encounter, at real 1x speed, held open until you close
-- the window. Meant to be launched once per Pokemon by tests/shiny_run.sh.
--
--   DS_SPECIES=GYARADOS DS_LEVEL=45 DS_MAP=CERULEAN_CITY DS_CX=10 DS_CY=12 \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/shiny_one.lua \
--   "/c/Program Files/LOVE/lovec.exe" .
--
-- ------- why the pacing is done here
--
-- A driver run is deliberately UNPACED: main.lua's pacingEnabled() returns
-- false whenever POKEPORT_DRIVER is set, so love.run spins as fast as the
-- machine will go and the loop takes one logic step (Game:update(1/60)) per
-- turn of it. That is right for a screenshot script and wrong for a capture:
-- the game runs at whatever multiple of real time the hardware manages, so
-- "wait 180 frames" is three seconds only by coincidence.
--
-- The fix does not need an engine change. The loop is blocked while this
-- coroutine is running, so sleeping HERE before each yield paces the whole
-- thing -- one 1/60 logic step per 1/60 of real time, which is 1x by
-- construction. Nothing else in the engine has to know.
--
-- ------- and why it never finishes
--
-- When a driver coroutine goes dead, main.lua calls love.event.quit(). So
-- holding the battle open forever is exactly how the window stays up until
-- somebody closes it, which is the handshake this run wants: one window, one
-- Pokemon, closed by hand, and only then the next.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  local SPECIES = os.getenv("DS_SPECIES") or "GYARADOS"
  local LEVEL   = tonumber(os.getenv("DS_LEVEL") or "") or 45
  local MAP     = os.getenv("DS_MAP") or "ROUTE_1"
  local CX      = tonumber(os.getenv("DS_CX") or "") or 5
  local CY      = tonumber(os.getenv("DS_CY") or "") or 8
  local LEAD    = tonumber(os.getenv("DS_LEAD") or "") or 2.0   -- seconds

  -- ------- real-time pacing
  --
  -- Each call is one logic step AND one sixtieth of a second of wall clock.
  -- The target is carried forward rather than measured from "now" so a slow
  -- frame is absorbed by the next one instead of compounding into drift.
  local nextAt = nil
  local function step()
    local now = love.timer.getTime()
    nextAt = (nextAt and (nextAt + 1 / 60)) or (now + 1 / 60)
    local slack = nextAt - now
    if slack > 0 then
      love.timer.sleep(slack)
    else
      nextAt = now                 -- fell behind; do not try to catch up
    end
    coroutine.yield()
  end

  local function hold(seconds)
    for _ = 1, math.floor(seconds * 60) do step() end
  end

  -- Unpaced, on purpose: a model rebuild is a loading screen, not part of
  -- the capture, and there is no reason to watch it at 1x.
  local function fast(n)
    for _ = 1, n do coroutine.yield() end
  end

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded")
    return
  end
  local Shiny = lib.require("Shiny")
  local OverworldBattle = lib.require("OverworldBattle")
  local StadiumInstall = lib.require("StadiumInstall")

  if not StadiumInstall.ready() then
    U.log("building stadium models (not part of the capture)...")
    StadiumInstall.begin()
    local guard = 0
    while not StadiumInstall.ready() and guard < 2000 do
      for _ = 1, 6 do StadiumInstall.step() end
      fast(1)
      guard = guard + 1
    end
  end

  OverworldBattle.setting:setValue("stadium", game)
  Shiny.setOdds(1)                       -- this encounter is shiny

  game.save.player.name = "RED"
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }

  if not game.data.pokemon[SPECIES] then
    U.log("no such species: " .. SPECIES)
    return
  end
  if not game.data.maps[MAP] then
    U.log("no such map: " .. MAP)
    return
  end

  U.teleport(game, MAP, CX, CY, "down")
  hold(1.6)                              -- let the neighbourhood mesh

  hold(LEAD)                             -- a beat before the fight opens

  local battle = BattleState.newWild(game, SPECIES, LEVEL)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  local mon = battle.enemy and battle.enemy.mon
  U.log(("%s at %s -- shiny=%s   (1x; close the window for the next one)")
        :format(SPECIES, MAP, tostring(Shiny.isShiny(mon))))

  -- The battle stays up, at 1x, until the window is closed by hand. No taps:
  -- the recording should be the Pokemon standing there, not a text box being
  -- clicked through.
  --
  -- DS_AUTOCLOSE is for checking the pacing without a person in the loop: set
  -- it to a number of seconds and the run should take about that long by the
  -- wall clock, which is the only way to prove 1x is actually 1x.
  local auto = tonumber(os.getenv("DS_AUTOCLOSE") or "") or 0
  if auto > 0 then
    local t0 = love.timer.getTime()
    hold(auto)
    U.log(("autoclose: asked for %.1fs, took %.2fs")
          :format(auto, love.timer.getTime() - t0))
    return
  end
  while true do step() end
end
