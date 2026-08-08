-- Driver: is a shiny visible on the FLAT paths -- the engine's own battle
-- screen (3D-BTL OFF) and the cards rung (2D-3D A)?
--
--   DS_SHOTS=mods/DramaticShapeVoxelMod/.claude/shiny_update/flat \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/shiny_flat.lua \
--   "/c/Program Files/LOVE/lovec.exe" .
--
-- The other shot driver covers the cards rung and the STADIUM rungs and NOT
-- 3D-BTL OFF -- which is the rung a player who has never touched the mod's
-- battle row is on, and so the one place a regression can sit unseen. It sat
-- there: the pic tint was a multiply that could only darken, and the arrival
-- sparkle was armed from Stadium.update and therefore never played here.
--
-- Each rung is shot TWICE, shiny and ordinary, from the same species at the
-- same spot, as a STRIP -- the intro flashes the pic through palette variants
-- on its way in, so a single frame lands wherever the pacing put it.
--
-- Reports, per rung: whether the roll landed, the PALETTE the pic was baked
-- under (which is where the recolour now lives), and whether the flat-path
-- sparkle armed and drew.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local BattleState = require("src.battle.BattleState")
  local PaletteFX = require("src.render.PaletteFX")
  local Pokemon = require("src.pokemon.Pokemon")

  local SPECIES = os.getenv("DS_SPECIES") or "GYARADOS"
  local LEVEL = tonumber(os.getenv("DS_LEVEL") or "") or 40
  local DIR = os.getenv("DS_SHOTS") or ".claude/shiny_update/flat"

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then U.log("DRAMATIC_SHAPE is not loaded") return end
  local Shiny = lib.require("Shiny")
  local ShinyPics = lib.require("ShinyPics")
  local ShinyFlash = lib.require("ShinyFlash")
  local OverworldBattle = lib.require("OverworldBattle")

  U.log(("wraps: pics=%s flash=%s"):format(
        tostring(PaletteFX.dramaticShapeShiny == true),
        tostring(ShinyFlash.installed == true)))

  -- ------- what the palette wrap hands the image cache
  --
  -- The recolour is baked ONCE, at build time, so counting draws says nothing
  -- about it. What matters is the cache key and the colours behind it: ask
  -- PaletteFX the same two questions monPalette asks, with the note the
  -- sprite hook would have left a moment earlier.
  local function palReport(mon)
    ShinyPics.note({ kind = "battle", species = SPECIES, mon = mon,
                     data = game.data })
    local cols = PaletteFX.monPal(game.data, SPECIES)
    local name = PaletteFX.monPalName(game.data, SPECIES)
    local out = { "pal=" .. tostring(name) }
    for i = 1, math.min(3, cols and #cols or 0) do
      local c = cols[i]
      if type(c) == "table" and c[1] then
        out[#out + 1] = ("c%d=%d,%d,%d"):format(i, c[1], c[2], c[3])
      end
    end
    return table.concat(out, " ")
  end

  -- The party is built at ORDINARY odds and pinned afterwards, so the
  -- player's own Pikachu stays common: this run is about the foe.
  game.save.player.name = "RED"
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }

  local function leave()
    while game.stack:top() and game.stack:top() ~= game.overworld do
      game.stack:pop()
    end
    U.wait(10)
  end

  local function shoot(rung, label, shiny)
    OverworldBattle.setting:setValue(rung, game)
    Shiny.setOdds(shiny and 1 or 100000000)
    for k in pairs(ShinyFlash.debug) do ShinyFlash.debug[k] = 0 end

    U.teleport(game, "ROUTE_1", 5, 8, "down")
    U.wait(60)

    local battle = BattleState.newWild(game, SPECIES, LEVEL)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)

    local mon = battle.enemy and battle.enemy.mon
    U.log(("%s %s: 3D-BTL=%s isShiny=%s %s"):format(
      label, shiny and "shiny" or "normal",
      tostring(OverworldBattle.setting:get()), tostring(Shiny.isShiny(mon)),
      palReport(mon)))

    -- The WIPE has to be walked through first. A driver run with no input at
    -- all sits on BattleTransition forever -- the battle is never pushed, so
    -- nothing about it draws and every counter below reads zero, which is
    -- exactly the false negative this probe produced before the taps went in.
    for _ = 1, 8 do U.tap(game, "a") U.wait(10) end

    -- the sparkle is three quarters of a second long and starts on the frame
    -- the pic appears, so the strip is TIGHT
    for k = 1, 10 do
      U.shot(game, ("%s/%s_%s_%02d.png"):format(DIR, label,
                                                shiny and "shiny" or "normal",
                                                k))
      U.wait(9)
    end
    local d = ShinyFlash.debug
    U.log(("  flash: renders=%s armed=%d draws=%d sparks=%d follows=%d occ=%d %s")
          :format(tostring(d.renders), d.armed, d.draws, d.sparks,
                  d.follows, d.occupied, tostring(d.err)))
    leave()
  end

  shoot(false, "off", false)
  shoot(false, "off", true)
  shoot(true, "cards", false)
  shoot(true, "cards", true)
end
