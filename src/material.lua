-- src/material.lua -- what a surface IS, the NOOBTOPIA half of the material merge.
--
-- SHANKPIT's other recent upgrade was a storytelling material vocabulary authored as ANIMATION rather than as PBR:
-- a material is (base look, how its UVs move, how its own light flickers, what colour the screen goes when it hurts
-- you), and every one of those is a pure function of the tick. That is what makes a flicker part of a deterministic
-- simulation at all, and it is why the same numbers can drive a Roblox part: a `Reflectance` value, a PointLight's
-- brightness, a texture offset.
--
-- The decisions are PARENA's (stdlib/shankpit/material_rules.prn), emitted to src/generated/material_rules.lua here
-- and to C in SHANKPIT (packages/simulation/material_rules.c). Nothing in this file restates a number.
--
-- TWO DIFFERENT AXES LIVE IN THAT FILE, and conflating them is a real bug (this file did, for one commit):
--
--   * the ANIMATION KIND -- 0 plain, 1 scrolling, 2 frame-loop sprite, 3 palette-LUT, 4 emissive flicker -- says how
--     a surface MOVES. Named `KIND_*` here.
--   * the REFLECTION SURFACE -- 0 MIRROR, 1 METAL, 2 GLASS, anything else none -- says how much of the look is the
--     environment. Named `MIRROR`/`METAL`/`GLASS`/`OTHER` here.
--
-- They share the integer 0 and mean completely different things, so they are never both called "kind".
--
-- Honest difference, stated rather than hidden: Roblox already ships real PBR (SurfaceAppearance) and real
-- shadowed lighting, which SHANKPIT's fixed-function path does not have. So this host maps the rules onto the
-- affordances Roblox actually has -- `BasePart.Reflectance` for the sphere-map reflection the C build draws by
-- hand, and per-fixture brightness for the Quake light styles -- instead of pretending the two renderers are the
-- same. What must not differ is the ANSWER to "how reflective is a mirror" or "how bright is a strobe on tick 6".

local Rules = require("generated.material_rules")

local Material = {}

Material.reflectionPermille = Rules.matReflectionStrengthPermille
Material.kindCount = Rules.matKindCount
Material.scrollSpeedMilli = Rules.matScrollSpeedMilli
Material.scrollU = Rules.matScrollUMilli
Material.scrollV = Rules.matScrollVMilli
Material.frameIndex = Rules.matFrameIndex
Material.lightStyleCount = Rules.matLightStyleCount
Material.lightLevel = Rules.lightStyleLevelPermille
Material.emissive = Rules.matEmissiveMilli
Material.tintLowHealth = Rules.tintLowHealthMilli
Material.tintSubmerged = Rules.tintSubmergedMilli
Material.tintAcid = Rules.tintAcidMilli
Material.tintShield = Rules.tintShieldMilli
Material.paletteIndex = Rules.paletteIndex256
Material.voxelAxis = Rules.vlmAxisIndexMilli
Material.VOXEL_AMBIENT_FLOOR = Rules.vlmAmbientFloorMilli()

-- The ANIMATION axis.
Material.KIND_PLAIN, Material.KIND_SCROLL, Material.KIND_FRAME = 0, 1, 2
Material.KIND_PALETTE, Material.KIND_FLICKER = 3, 4

-- The REFLECTION axis. `OTHER` is not a fourth look: it is everything that reflects nothing and costs nothing.
Material.MIRROR, Material.METAL, Material.GLASS, Material.OTHER = 0, 1, 2, 3

-- Light styles (Quake's vocabulary): 0 steady, 1 strobe, 2 fluorescent, 3 broken, 4 pulse, 5 dying, 6 alarm,
-- 7 candle.
Material.STEADY, Material.STROBE, Material.FLUORESCENT, Material.BROKEN = 0, 1, 2, 3
Material.PULSE, Material.DYING, Material.ALARM, Material.CANDLE = 4, 5, 6, 7

-- The one conversion this host owns: Roblox's Reflectance is 0..1 and the rules speak permille.
function Material.reflectance(surface)
    return Material.reflectionPermille(surface) / 1000
end

-- What a host draws for one material's ANIMATION at one tick.
function Material.appearance(kind, tick)
    return {
        scroll_u = Material.scrollU(kind, tick),
        scroll_v = Material.scrollV(kind, tick),
    }
end

-- What a host applies to a light-emitting fixture at one tick: permille of its own brightness, and the same
-- expressed the way a Roblox PointLight wants it.
function Material.fixture(style, tick, room_light_milli)
    local level = Material.emissive(style, tick, room_light_milli)
    return { level = level, brightness = level / 1000 }
end

return Material
