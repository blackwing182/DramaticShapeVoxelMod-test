-- The shiny recolour: Stadium's own HSL slide, run over decoded texels.
--
-- THE COLOUR MODEL IS STADIUM'S, not an invention. The Stadium games do not
-- ship a second set of textures for a shiny Pokemon; they convert the
-- colours the model already has to HSL and slide them -- a hue rotation in
-- degrees, plus saturation and lightness on a quantized integer scale of
-- -8..+8 where 0 is no change. One step is 12.5%, so +-8 is +-100%: exactly
-- the range of GIMP's Hue-Saturation sliders, which is where the 12.5%
-- figure was measured. s = -8 is full greyscale, l = +8 is white.
--
-- That equivalence is why the maths below is GIMP's Hue-Saturation and not
-- a plain additive offset:
--
--   saturation   s' = s * (1 + k)                 multiplicative
--   lightness    l' = l * (1 + k)        k < 0    scale toward black
--                l' = l + k * (1 - l)    k > 0    blend toward white
--
-- The multiplicative saturation is the reason this is safe to run over a
-- whole texture rather than a masked region: a pixel with no saturation --
-- an eye white, a tooth, a grey shadow -- is immune to BOTH the hue
-- rotation and the saturation step, for free and by construction. Only the
-- lightness step touches achromatic pixels, which is why the species
-- carrying big l values (Golbat and Slowpoke at -6, Moltres at +5) are the
-- ones worth looking at with human eyes.
--
-- FIVE SPECIES CANNOT BE SLID. Clefairy, Clefable, Jigglypuff, Wigglytuff
-- and Gyarados get a real alternate texture in Stadium, because their shiny
-- moves one region a long way and leaves another alone -- Jigglypuff's body
-- stays pink while its irises go green -- and a single rotation moves
-- everything or nothing.
--
-- Those five carry `lut` instead: an explicit before/after colour mapping,
-- sampled from the verified texture pairs, listing only the colours that
-- actually move. A first attempt drove them from a handful of per-region
-- anchors and picked the nearest one per pixel, which is wrong in a way
-- worth recording: with regions as far apart as Clefairy's pink body and
-- its green ear tips, a dark red shadow pixel is "nearest" to the green and
-- gets rotated 150 degrees the wrong way. The fixture caught it at a
-- 124/255 channel error. An exact table is a few tens of kilobytes and has
-- no such failure mode, so these five are data rather than algorithm.
--
-- WHY THIS RUNS AT EXTRACTION. The textures are already decoded to RGBA in
-- memory at that moment (StadiumFragment.decodeTexture), and -- the part
-- that matters -- generated effect frames are still distinguishable there.
-- StadiumFx marks them `generated = true`, and the packer drops that field,
-- so at runtime an additive flame can only be inferred back from the prim
-- table. Recolouring a flame is wrong: a shiny Charizard has a shiny hide
-- and an ordinary fire. Doing the work while the marker still exists means
-- the discrimination is exact rather than reconstructed.
--
-- THE MEMO IS WHAT MAKES IT AFFORDABLE. These are N64 textures: a few
-- hundred distinct colours across tens of thousands of texels. Converting
-- per DISTINCT COLOUR instead of per pixel turns the inner loop into a
-- table lookup, which is the difference between a pass that is felt during
-- the install and one that is not.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ShinyPalette = {}

local floor, min, max, abs = math.floor, math.min, math.max, math.abs
local byte, char, concat = string.byte, string.char, table.concat

-- ------- HSL

local function rgbToHsl(r, g, b)
  r, g, b = r / 255, g / 255, b / 255
  local mx, mn = max(r, g, b), min(r, g, b)
  local l = (mx + mn) / 2
  if mx == mn then return 0, 0, l end          -- achromatic: hue is undefined
  local d = mx - mn
  local s = l > 0.5 and d / (2 - mx - mn) or d / (mx + mn)
  local h
  if mx == r then
    h = (g - b) / d + (g < b and 6 or 0)
  elseif mx == g then
    h = (b - r) / d + 2
  else
    h = (r - g) / d + 4
  end
  return h * 60, s, l
end

local function hue2rgb(p, q, t)
  if t < 0 then t = t + 1 end
  if t > 1 then t = t - 1 end
  if t < 1 / 6 then return p + (q - p) * 6 * t end
  if t < 1 / 2 then return q end
  if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
  return p
end

local function hslToRgb(h, s, l)
  if s <= 0 then
    local v = floor(l * 255 + 0.5)
    return v, v, v
  end
  h = (h % 360) / 360
  local q = l < 0.5 and l * (1 + s) or l + s - l * s
  local p = 2 * l - q
  return floor(hue2rgb(p, q, h + 1 / 3) * 255 + 0.5),
         floor(hue2rgb(p, q, h) * 255 + 0.5),
         floor(hue2rgb(p, q, h - 1 / 3) * 255 + 0.5)
end

-- GIMP's two curves, shared by the slide and the anchor paths so both
-- reach the same colour from the same k.
local function shiftSat(s, k)
  if k == 0 then return s end
  return max(0, min(1, s * (1 + k)))
end

local function shiftLight(l, k)
  if k == 0 then return l end
  if k < 0 then return max(0, l * (1 + k)) end
  return min(1, l + k * (1 - l))
end

-- ------- the two kinds of transform

-- A whole-model slide: the 146 species Stadium recolours this way.
local function slideFn(slide)
  local dh = slide.h or 0
  local ks = (slide.s or 0) * 0.125
  local kl = (slide.l or 0) * 0.125
  return function(r, g, b)
    local h, s, l = rgbToHsl(r, g, b)
    -- An achromatic pixel has no hue to rotate and no saturation to scale;
    -- only a lightness step can reach it. Returning early is not just
    -- speed, it is exactness: round-tripping grey through HSL and back can
    -- move it by a unit, and a tooth that drifts is a visible defect.
    if s <= 0 then
      if kl == 0 then return r, g, b end
      local v = floor(shiftLight(l, kl) * 255 + 0.5)
      return v, v, v
    end
    return hslToRgb(h + dh, shiftSat(s, ks), shiftLight(l, kl))
  end
end

-- An exact colour mapping: the five species Stadium gives a real second
-- texture. A colour absent from the table is one the alternate texture left
-- alone, so passing it straight through is the correct answer, not a
-- fallback -- that is how Wigglytuff keeps its white belly and its black
-- inner ears while its body moves to lilac.
local function lutFn(lut)
  return function(r, g, b)
    local hit = lut[r * 65536 + g * 256 + b]
    if not hit then return r, g, b end
    return floor(hit / 65536) % 256, floor(hit / 256) % 256, hit % 256
  end
end

-- ------- the colour table
--
-- Loaded lazily and cached. Two paths on purpose: through the mod namespace
-- when the mod is running, and straight off disk when it is not. The
-- extraction byte-diff (tests/stadium_extract_test.lua) stubs V with only
-- `require` and `mod.log`, and the recolour has to be exercisable under
-- exactly that harness -- a colour transform that can only run inside a
-- live LOVE process is a colour transform nobody will test.
local colors = nil

local function loadColors()
  if colors ~= nil then return colors or nil end
  if V and V.data then
    local ok, t = pcall(V.data, "shiny_colors")
    if ok and type(t) == "table" then colors = t; return colors end
  end
  local tries = { "data/shiny_colors.lua",
                  "mods/DramaticShapeVoxelMod/data/shiny_colors.lua" }
  for _, p in ipairs(tries) do
    local chunk = loadfile(p)
    if chunk then
      local ok, t = pcall(chunk)
      if ok and type(t) == "table" then colors = t; return colors end
    end
  end
  colors = false          -- cache the miss; do not retry the disk per species
  return nil
end

-- The spec for one dex number, or nil if we have nothing for it.
function ShinyPalette.forDex(dex)
  local all = loadColors()
  return all and all[dex] or nil
end

-- Build the pixel transform for one species' spec, or nil when there is
-- nothing to do.
function ShinyPalette.transform(spec)
  if type(spec) ~= "table" then return nil end
  if spec.lut then
    if next(spec.lut) == nil then return nil end
    return lutFn(spec.lut)
  end
  local s = spec.slide
  if not s then return nil end
  if (s.h or 0) == 0 and (s.l or 0) == 0 and (s.s or 0) == 0 then return nil end
  return slideFn(s)
end

-- ------- the pass over one texture
--
-- Memoised per distinct colour (see the header). The key packs RGB into one
-- integer because a table with 24-bit integer keys is a flat array probe,
-- where a "r,g,b" string key would allocate on every pixel -- and allocation
-- inside a multi-million-iteration loop is the whole cost.
--
-- Alpha is copied through untouched, never premultiplied and never
-- recomputed: the transform is defined on colour alone, and a shiny
-- Gastly's soft edge must stay exactly as soft as it was.
function ShinyPalette.recolorTexels(rgba, fn)
  local n = #rgba
  if n == 0 or not fn then return rgba end
  local memo = {}
  local out, blocks = {}, {}
  local bi = 0
  for i = 1, n, 4 do
    local r, g, b, a = byte(rgba, i, i + 3)
    local key = r * 65536 + g * 256 + b
    local hit = memo[key]
    if not hit then
      local nr, ng, nb = fn(r, g, b)
      hit = { nr, ng, nb }
      memo[key] = hit
    end
    bi = bi + 1
    blocks[bi] = char(hit[1], hit[2], hit[3], a)
    -- flushed in blocks so the concat never walks a table with millions of
    -- one-texel strings in it
    if bi >= 4096 then
      out[#out + 1] = concat(blocks)
      blocks, bi = {}, 0
    end
  end
  if bi > 0 then out[#out + 1] = concat(blocks, "", 1, bi) end
  return concat(out)
end

-- ------- a tint, for the flat sprites
--
-- The 3D models get real recoloured texels. The 2D battle pics cannot: the
-- engine bakes a species palette into a cached image keyed by path and
-- palette name, and that cache has no idea which INDIVIDUAL is being drawn.
-- What is available per-draw is the draw colour, which multiplies.
--
-- So the pic is tinted, and the tint is derived from the species' OWN shiny
-- slide rather than being a generic gold: run a spread of reference colours
-- through the real transform, take the mean ratio out to in, and that is
-- the multiply that best stands in for it. A shiny Golbat leans green, a
-- shiny Charizard goes dusky, and neither is a costume.
--
-- ITS ONE LIMIT, stated plainly: a multiply can only darken. Where a species'
-- shiny is LIGHTER than its normal, the honest ratio is above 1 and gets
-- clamped, so those come out under-shifted -- present, but quieter than the
-- model. The floor keeps the darkest cases readable rather than muddy.
local TINT_FLOOR = 0.45
local tintCache = {}

-- Mid-tone references across the wheel. Deliberately not greys: the slide
-- is multiplicative in saturation, so a grey reference would report no
-- change for every species and hand back a tint of 1,1,1.
local REFS = {
  { 200, 90, 70 }, { 200, 150, 70 }, { 190, 190, 80 }, { 90, 180, 90 },
  { 80, 170, 170 }, { 80, 120, 200 }, { 140, 90, 190 }, { 190, 90, 150 },
}

function ShinyPalette.tintFor(dex)
  local hit = tintCache[dex]
  if hit ~= nil then return hit or nil end
  local fn = ShinyPalette.transform(ShinyPalette.forDex(dex))
  if not fn then tintCache[dex] = false; return nil end
  local sr, sg, sb, n = 0, 0, 0, 0
  for _, c in ipairs(REFS) do
    local r, g, b = fn(c[1], c[2], c[3])
    sr = sr + r / c[1]
    sg = sg + g / c[2]
    sb = sb + b / c[3]
    n = n + 1
  end
  local t = {
    max(TINT_FLOOR, min(1, sr / n)),
    max(TINT_FLOOR, min(1, sg / n)),
    max(TINT_FLOOR, min(1, sb / n)),
  }
  -- a tint that came out as no tint at all is worse than none: it costs a
  -- colour-hook wrap per draw and changes nothing
  if t[1] > 0.995 and t[2] > 0.995 and t[3] > 0.995 then
    tintCache[dex] = false
    return nil
  end
  tintCache[dex] = t
  return t
end

-- ------- the pass over one species' whole texture array

-- Recolour `textures` in place, skipping the ones that must not move.
--
-- Two exclusions, both load-bearing:
--
--   generated / index == -1   StadiumFx's flipbook frames -- flames, beams,
--                             sparks. A shiny Pokemon has a shiny hide and
--                             an ordinary fire; tinting the attack effects
--                             would read as a bug. This marker exists ONLY
--                             here, which is why the recolour lives at
--                             extraction (see the header).
--   w or h of zero            a degenerate slot with nothing to transform.
--
-- Returns the number of textures actually touched, so the caller can tell a
-- species that recoloured from one that silently did not.
function ShinyPalette.recolorTextures(textures, spec)
  local fn = ShinyPalette.transform(spec)
  if not fn then return 0 end
  local touched = 0
  for i = 1, #textures do
    local t = textures[i]
    local skip = t.generated == true or t.index == -1
                 or not t.w or not t.h or t.w == 0 or t.h == 0
    if not skip and t.rgba and #t.rgba > 0 then
      t.rgba = ShinyPalette.recolorTexels(t.rgba, fn)
      touched = touched + 1
    end
  end
  return touched
end

return ShinyPalette
