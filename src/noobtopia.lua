-- src/noobtopia.lua -- the Roblox host. This is the only file that touches workspace.
--
-- Placement: put this Script in ServerScriptService, with src/ (`ambient.lua`, `big_o_witness.lua`) and
-- src/generated/ (`ambient_life.lua`, `arena_rules.lua`) as ModuleScripts alongside it, and a rig named `Noob` in
-- ReplicatedStorage. It is the original NOOBTOPIA script (clone a noob, give it a line, let it wander) rebuilt on
-- three things it did not have:
--
--   1. SLIPPERY PHYSICS. Movement is not a teleport to a new random point every 33 seconds. Each noob has a speed
--      and a surface, and every frame asks PARENA (src/generated/arena_rules.lua) for the next speed:
--      `stepSpeed(speed, wish, surface)`. On ICE the wish buys almost no acceleration and the surface keeps what
--      you already had, so a noob stumbles and coasts; on CONCRETE it starts and stops on a dime. The numbers are
--      shared with SHANKPIT's C build of the same .prn, so this is not "Roblox physics", it is the game's physics.
--
--   2. COMBAT. Fists/bat/pistol/rocket from the same rules file: damage, knockback, cooldown, and a to-hit chance
--      that falls off with distance. Click a noob to punch it; it takes damage, gets shoved, and dies at 0 HP.
--
--   3. BIG_O's WITNESS RULE. When a noob dies in front of others, they are witnesses (src/big_o_witness.lua):
--      one or two go into denial and say so; five or more stop pretending and turn on the killer. That line is the
--      IP's whole identity, and it is now visible in a Roblox place.
--
-- Ambient lines still come from data/noob_lines.lua via src/ambient.lua (which takes its timing from PARENA). To
-- change what noobs say, edit the data file. To change how often they say it, edit the .prn. Neither is here.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Ambient = require(script.Parent.ambient)
local Witness = require(script.Parent.big_o_witness)
local Arena = require(script.Parent.generated.arena_rules)
local Wander = require(script.Parent.wander)
local LightingMatrix = require(script.Parent.lighting)
local Sky = require(script.Parent.sky)
local Wiring = require(script.Parent.wiring)
local Cozy = require(script.Parent.cozy)
local Props = require(script.Parent.props)
local LINES = require(script.Parent.data.noob_lines)

-- Surface ids, matching PARENA/stdlib/noobtopia/arena_rules.prn:
local CONCRETE, ICE, GRASS, METAL, MUD = 0, 1, 2, 3, 4

-- The wander rule speaks in whole world units (PARENA/stdlib/noobtopia/walk_rules.prn); this host picks up the
-- conversion to studs, and how big a piece of ground one noob is allowed to call its own.
local STUD_PER_UNIT = 4
local WALK_LEASH = 40          -- world units, i.e. 160 studs of street per noob
local WALK_WISH = 6            -- the speed a noob asks arena.stepSpeed for while it is mid-leg

local MAX_NOOBS = 12
local TALK_RADIUS = 60
local WITNESS_RADIUS = 30
local WEAPON_FIST, WEAPON_BAT, WEAPON_PISTOL, WEAPON_ROCKET = 0, 1, 2, 3

local byCat = Ambient.group(LINES)
local noobs = {}

-- A deliberately silly ice rink in one corner of the map: walking across it is the demo of the slippery physics.
local function surfaceAt(x, z)
    if math.abs(x) < 60 and math.abs(z) < 60 then return ICE end
    if math.abs(x) < 120 then return GRASS end
    return CONCRETE
end

local function makeBubble(model, text)
    local bubble = Instance.new("BillboardGui")
    bubble.Size = UDim2.new(0, 175, 0, 80)
    bubble.StudsOffset = Vector3.new(0, 6, 0)
    bubble.Adornee = model.PrimaryPart
    bubble.AlwaysOnTop = true
    bubble.Parent = model

    local label = Instance.new("TextLabel")
    label.BackgroundTransparency = 0.2
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundColor3 = Color3.new(1, 1, 1)
    label.TextColor3 = Color3.new(0, 0, 0)
    label.Font = Enum.Font.SourceSansBold
    label.TextScaled = true
    label.Text = text
    label.Parent = bubble

    task.delay(7, function()
        if bubble and bubble.Parent then bubble:Destroy() end
    end)
end

local function say(noob, text)
    if not text then return end
    makeBubble(noob.model, text)
end

local function spawnNoob()
    local template = ReplicatedStorage:FindFirstChild("Noob")
    if not template then return nil end
    local model = template:Clone()
    model.Name = "NPC"
    model.Parent = workspace
    if model.PrimaryPart then
        model:PivotTo(CFrame.new(math.random(-200, 200), 3, math.random(-200, 200)))
    end
    local noob = {
        model = model,
        speed = 0,
        wish = 0,
        mood = Ambient.IDLE,
        seed = math.random(1, 1000000),
        lastSaid = 0,          -- seconds of silence so far
        health = 100,
        cooldown = 0,
        dead = false,
    }
    -- where it drifts, decided by the SAME rule SHANKPIT's C host runs, in whole world units
    local p = model.PrimaryPart and model.PrimaryPart.Position or Vector3.new(0, 3, 0)
    noob.walk = Wander.new(math.floor(p.X / STUD_PER_UNIT), math.floor(p.Z / STUD_PER_UNIT),
        noob.mood, noob.seed, WALK_LEASH)
    table.insert(noobs, noob)
    return noob
end

local function punch(attacker, noob, weapon)
    if noob.dead or noob.cooldown > 0 then return end
    local root = noob.model.PrimaryPart
    if not root then return end
    local dist = attacker and (root.Position - attacker.Position).Magnitude or 0
    local chance = Arena.weaponHitChancePermille(weapon, math.floor(dist))
    if math.random(1, 1000) > chance then return end    -- the rules' own to-hit, not a Roblox raycast

    noob.cooldown = Arena.weaponCooldownTicks(weapon) / 60
    noob.health -= Arena.weaponDamage(weapon)

    -- knockback, straight from the rules: permille of the noob's own speed budget, shoved away from the attacker
    local shove = Arena.weaponKnockbackPermille(weapon) / 1000
    noob.speed = math.min(60, noob.speed + math.floor(20 * shove))
    noob.mood = Ambient.STARTLED

    if noob.health <= 0 then
        noob.dead = true
        -- zero or more witnesses of the death: BIG_O's rule decides what the group does about it
        local seen = {}
        for _, other in ipairs(noobs) do
            if other ~= noob and not other.dead and other.model.PrimaryPart then
                local d = (other.model.PrimaryPart.Position - root.Position).Magnitude
                if d <= WITNESS_RADIUS then
                    table.insert(seen, { state = Witness.DENIAL })
                    other.mood = Ambient.STARTLED
                end
            end
        end
        local state = Witness.resolve(seen)
        for _, w in ipairs(seen) do w.state = state end
        for _, other in ipairs(noobs) do
            if other ~= noob and not other.dead and other.model.PrimaryPart then
                local d = (other.model.PrimaryPart.Position - root.Position).Magnitude
                if d <= WITNESS_RADIUS then say(other, Witness.lineFor(state)) end
            end
        end
        noob.model:Destroy()
    else
        say(noob, "Ow.")
    end
end

local function tickNoob(noob, dt)
    if noob.dead or not noob.model.PrimaryPart then return end
    local root = noob.model.PrimaryPart

    if noob.cooldown > 0 then noob.cooldown -= dt end

    -- 1. WHERE it drifts is the shared walk rule (PARENA walk_rules.prn -> src/generated/walk_rules.lua),
    --    the same decision SHANKPIT's C host runs every tick: when to pick a target, which of the 8 compass
    --    headings, how long the leg is, and whether the destination stays inside its own leash. This replaced a
    --    `math.random() < 0.02` nudge on one axis, which could not be shared with anything.
    local stepped = Wander.tick(noob.walk)

    -- 2. HOW FAST is the arena rules' slippery half: no input is -1, the rules' own "slide" convention, which is
    --    when the surface takes over and a noob on ice keeps going after it has stopped asking.
    local surface = surfaceAt(root.Position.X, root.Position.Z)
    noob.wish = stepped and WALK_WISH or -1
    noob.speed = Arena.stepSpeed(noob.speed, noob.wish, surface)

    -- 3. move. Magnitude from arena rules, direction from the walk rule's heading. Driven by `stepped`, not by
    --    "is mid-leg", so a STARTLED noob stays put on screen as well as in the rules.
    if stepped and noob.speed > 0 then
        local step = noob.speed * dt * STUD_PER_UNIT
        local hx, hz = noob.walk.dx, noob.walk.dy
        root.CFrame = root.CFrame + Vector3.new(hx * step, 0, hz * step)
        if hx ~= 0 or hz ~= 0 then
            root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(hx, 0, hz))
        end
    end
    -- falling off the edge of the ice rink: put it back rather than let it disappear
    if root.Position.Y < -20 then
        root.CFrame = CFrame.new(0, 3, 0)
    end

    -- 4. ambient life: PARENA decides when, NOOBTOPIA's data decides what
    noob.lastSaid = noob.lastSaid + dt * 1000
    local text
    text, noob.seed = Ambient.speak(byCat, noob.mood, math.floor(noob.lastSaid), noob.seed)
    if text then
        noob.lastSaid = 0
        noob.mood = Ambient.IDLE
        say(noob, text)
    end
end

-- ---- THE ENGINE UPGRADES, WIRED -------------------------------------------------------------------
-- Until this block existed, src/lighting.lua and src/material.lua returned numbers and nothing applied them. This is
-- the only place they reach the engine: the Lighting service's own properties, a part's Reflectance, a PointLight's
-- Brightness. PARENA still decides the numbers (stdlib/shankpit/{lighting,material}_rules.prn), the two pure modules
-- still do the conversion, and Wiring still decides WHAT to write -- so this block only reads attributes, calls
-- those, and assigns.
--
-- A place publishes its weather through attributes on `workspace` (or on Lighting): SHANKPIT_cover, _rain, _storm,
-- _fog_wash, _visibility, _ambient_level, _flash, _interior. Absent readings fall back to the .prn's own defaults,
-- never to an invented value. Parts are classified by name (mirror / metal / glass, else nothing) unless they state
-- SHANKPIT_Surface themselves, and a PointLight follows SHANKPIT_LightStyle (0..7) if it has one.
local LightingSvc = game:GetService("Lighting")
local ENV_EVERY = 0.25
local MATERIAL_SCAN_EVERY = 5

local envAccum, materialAccum = 0, MATERIAL_SCAN_EVERY
local surfaceOn = {}          -- [part] = the surface id whose value is already written on it

-- The place's sky: a CLOCK (seeded from SHANKPIT_minutes, default noon), a WEATHER (SHANKPIT_weather), and the
-- shared sky rules deciding the rest. MINUTES_PER_SECOND is host pacing -- how long a day lasts is a design choice,
-- so it lives here and not in PARENA.
local MINUTES_PER_SECOND = 1
local skyState = Sky.new(workspace:GetAttribute("SHANKPIT_minutes") or 720,
                         workspace:GetAttribute("SHANKPIT_weather") or Sky.CLEAR)

-- The sun, as the sky last reported it (permille, 0..1000). The cosy verbs ask whether a dandelion is open, and
-- that question is the sun's, so the host keeps the latest reading rather than making one up per press.
local currentSun = 500

local function publishedWeather()
    return Wiring.publishedSky(function(key)
        local v = workspace:GetAttribute("SHANKPIT_" .. key)
        if v == nil then v = LightingSvc:GetAttribute("SHANKPIT_" .. key) end
        return v
    end)
end

local function wireEnvironment(dt)
    Sky.advance(skyState, (dt or 0) * MINUTES_PER_SECOND, (dt or 0) * 60)
    -- The clock+weather model fills every field; a place that explicitly published one overrides just that field.
    local sky = Wiring.mergeSky(Sky.inputs(skyState, Wiring.SKY_DEFAULTS.ambient_level), publishedWeather())
    local scene = LightingMatrix.scene(sky)
    currentSun = sky.sun or currentSun
    local plan = Wiring.lightPlan(scene, STUD_PER_UNIT, Sky.sun(skyState))
    Wiring.applyPlan(plan, LightingSvc, function(rgb)
        return Color3.new(rgb[1], rgb[2], rgb[3])
    end)
    -- The sun also moves the actual sun: 23.83 hours means dusk to Roblox, and the rules decide what that is.
    LightingSvc.ClockTime = Sky.clockHours(skyState)
    return scene
end

local function wireMaterials()
    local tick = math.floor(os.clock() * 60)
    for _, inst in ipairs(workspace:GetDescendants()) do
        if inst:IsA("BasePart") then
            local surface = Wiring.surfaceForPart(inst)
            if surfaceOn[inst] ~= surface then
                Wiring.applySurface(inst, surface)
                surfaceOn[inst] = surface
            end
        elseif inst:IsA("PointLight") then
            local style = tonumber(inst:GetAttribute("SHANKPIT_LightStyle"))
            if style ~= nil then
                -- a place is lit unless it says how lit: 900 is "a room with the lights on", and a fixture's own
                -- floor is then the .prn's business, not this host's
                local room = tonumber(inst:GetAttribute("SHANKPIT_RoomLight")) or 900
                Wiring.applyFixture(inst, math.floor(style), tick, math.floor(room))
            end
        end
    end
end

wireEnvironment(0)
wireMaterials()

-- ---- THE COSY VERBS, REACHABLE --------------------------------------------------------------------
-- Until this block existed the two verbs were tested and unreachable: nothing in the place was a dandelion a player
-- could press. `src/props.lua` decides WHAT stands where and what a press means (tested, plain Lua); this block only
-- builds the parts, hands Roblox the prompt, and shows the result. The rules stay PARENA's
-- (`stdlib/shankpit/cozy_rules.prn`), the two cooldowns and the day count stay `src/cozy.lua`'s.
--
-- The actor is the PLAYER, not a passing noob: a cosy verb is something you do with your hands, and the state is per
-- player so two players in one server do not share a cooldown. Comfort is republished as a `Cozy` attribute on the
-- player, so a future HUD has something to read without a second copy of the number living in a GUI.
local cozyByPlayer = {}

local function cozyFor(player)
    local state = cozyByPlayer[player]
    if not state then
        -- the seed is the UserId: stable across a session, distinct per player, and exactly representable
        state = Cozy.new(Cozy.IDLE, player.UserId)
        cozyByPlayer[player] = state
        player:SetAttribute("Cozy", state.comfort)
    end
    return state
end

local function nowMs()
    return math.floor(workspace:GetServerTimeNow() * 1000)
end

local function propPart(name, size, position, colour, shape)
    local part = Instance.new("Part")
    part.Name = name
    part.Anchored = true
    part.CanCollide = false
    part.Size = size
    part.Color = colour
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    if shape then part.Shape = shape end
    part.CFrame = CFrame.new(position)
    return part
end

-- A tree leans, then settles. Cosmetic, and kept to the one prop that was pressed so a street of trees is not a
-- street of windmills.
local function sway(tree)
    local canopy, base = tree.canopy, tree.base
    if not canopy or not base then return end
    task.spawn(function()
        for i = 1, 14 do
            if not canopy.Parent then return end
            canopy.CFrame = base * CFrame.Angles(math.sin(i * 0.7) * 0.05, 0, math.sin(i * 0.5) * 0.04)
            task.wait(0.05)
        end
        if canopy.Parent then canopy.CFrame = base end
    end)
end

-- The seeds that came off, floating up and out. Purely a reading of `amount`, which the rules chose.
local function puffSeeds(at, count)
    for _ = 1, count do
        local seed = propPart("SeedPuff", Vector3.new(0.25, 0.25, 0.25),
            at + Vector3.new(math.random(-8, 8) / 10, 1.6, math.random(-8, 8) / 10),
            Color3.fromRGB(250, 240, 170), Enum.PartType.Ball)
        seed.Material = Enum.Material.Neon
        seed.Parent = workspace
        task.spawn(function()
            for _ = 1, 12 do
                if not seed.Parent then return end
                seed.CFrame = seed.CFrame * CFrame.new(0, 0.35, 0) * CFrame.Angles(0.25, 0.35, 0)
                task.wait(0.08)
            end
            seed:Destroy()
        end)
    end
end

-- A sentence over the player's own head. `makeBubble` wants a model with a PrimaryPart, which a character has.
local function hint(character, text)
    if not character or not text then return end
    local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    character.PrimaryPart = root
    makeBubble(character, text)
end

local function buildProps()
    local folder = Instance.new("Folder")
    folder.Name = "CosyProps"
    folder.Parent = workspace

    for _, spec in ipairs(Props.default()) do
        local d = Props.describe(spec)
        local base = Vector3.new(d.x, 3, d.z)
        local model = Instance.new("Model")
        model.Name = d.id
        model.Parent = folder

        local anchor, tree = nil, nil
        if d.kind == "dandelion" then
            -- a stem and a head: everything a dandelion needs to be kicked
            local stem = propPart("DandelionStem", Vector3.new(0.18, 1.4, 0.18), base + Vector3.new(0, 0.7, 0),
                Color3.fromRGB(94, 148, 72))
            stem.Material = Enum.Material.Grass
            stem.Parent = model
            anchor = propPart("DandelionHead", Vector3.new(0.6, 0.6, 0.6), base + Vector3.new(0, 1.5, 0),
                Color3.fromRGB(250, 232, 118), Enum.PartType.Ball)
            anchor.Material = Enum.Material.Neon
            anchor.Parent = model
            model.PrimaryPart = anchor
        elseif d.kind == "tree" then
            local girth = d.trunk_studs
            anchor = propPart("TreeTrunk", Vector3.new(girth, 8, girth), base + Vector3.new(0, 4, 0),
                Color3.fromRGB(92, 68, 44))
            anchor.Material = Enum.Material.Wood
            anchor.Parent = model
            local canopy = propPart("TreeCanopy", Vector3.new(girth * 3.4, girth * 3, girth * 3.4),
                base + Vector3.new(0, 9, 0), Color3.fromRGB(58, 110, 54), Enum.PartType.Ball)
            canopy.Parent = model
            model.PrimaryPart = anchor
            tree = { canopy = canopy, base = canopy.CFrame }
        else
            warn("NOOBTOPIA: cosy prop " .. tostring(d.id) .. " has an unknown kind " .. tostring(d.kind))
        end

        if anchor then
            local prompt = Instance.new("ProximityPrompt")
            prompt.ActionText = d.action
            prompt.ObjectText = d.object
            prompt.HoldDuration = 0
            prompt.MaxActivationDistance = d.radius
            prompt.RequiresLineOfSight = false
            prompt.Parent = anchor

            prompt.Triggered:Connect(function(player)
                local result = Props.interact(spec, cozyFor(player), nowMs(), currentSun)
                if result.ok and result.verb == "kick" then puffSeeds(anchor.Position, result.amount) end
                if result.ok and result.verb == "hug" then sway(tree) end
                player:SetAttribute("Cozy", result.comfort)
                hint(player.Character, Props.reply(result))
            end)
        end
    end
end

buildProps()

Players.PlayerRemoving:Connect(function(player)
    cozyByPlayer[player] = nil
end)

-- Spawn up to MAX_NOOBS, topping up as they die (the original script's loop, minus the 0.1s hammering)
local spawnAccum = 0
RunService.Heartbeat:Connect(function(dt)
    envAccum += dt
    if envAccum >= ENV_EVERY then
        envAccum = 0
        wireEnvironment(dt)
        -- comfort drifts back toward what the mood wants, a permille per tick of THIS host's 0.25 s: pace is a
        -- presentation choice, so it is counted here and not in the rules
        for player, state in pairs(cozyByPlayer) do
            player:SetAttribute("Cozy", Cozy.tick(state, 1))
        end
    end
    materialAccum += dt
    if materialAccum >= MATERIAL_SCAN_EVERY then
        materialAccum = 0
        wireMaterials()
    end

    local alive = 0
    for _, n in ipairs(noobs) do if not n.dead then alive += 1 end end
    spawnAccum += dt
    if alive < MAX_NOOBS and spawnAccum > 1 then
        spawnAccum = 0
        spawnNoob()
    end
    for i = #noobs, 1, -1 do
        local n = noobs[i]
        tickNoob(n, dt)
        if n.dead and not n.model.Parent then table.remove(noobs, i) end
    end
end)

-- Click to fight: the nearest noob within reach takes a fist, or a bat/pistol/rocket if the player is holding the
-- tool named for it. Distance and to-hit are the rules'; the raycast only picks the target.
for _, player in ipairs(Players:GetPlayers()) do
    player:SetAttribute("Weapon", WEAPON_FIST)
end
Players.PlayerAdded:Connect(function(player)
    player:SetAttribute("Weapon", WEAPON_FIST)
end)

-- Combat input. A server Script cannot see a click, so the action arrives as a RemoteEvent named "Punch" in
-- ReplicatedStorage, fired by a LocalScript (see README: one small client script is the piece this repo does not
-- ship). Everything the decision needs is here: the rules pick the weapon's damage/knockback/cooldown and the
-- to-hit chance, and only the nearest noob within arm's reach is a candidate.
local PUNCH_REACH = 8
local punchEvent = ReplicatedStorage:FindFirstChild("Punch")
if punchEvent and punchEvent:IsA("RemoteEvent") then
    punchEvent.OnServerEvent:Connect(function(player, weapon)
        if type(weapon) ~= "number" then weapon = WEAPON_FIST end
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        local best, bestDist = nil, PUNCH_REACH
        for _, noob in ipairs(noobs) do
            if not noob.dead and noob.model.PrimaryPart then
                local d = (noob.model.PrimaryPart.Position - hrp.Position).Magnitude
                if d < bestDist then best, bestDist = noob, d end
            end
        end
        if best then punch(hrp, best, weapon) end
    end)
else
    warn("NOOBTOPIA: no 'Punch' RemoteEvent in ReplicatedStorage -- noobs spawn and talk, but cannot be hit yet")
end

-- DEADWEIGHT: the table, the citizens' ladder and the PER-SERVER leaderboard (src/deadweight_server.lua, which
-- keeps every decision in the tested pure module src/deadweight_room.lua). One prompt, one clock, one board.
-- Wrapped so a place without the module still runs: the game is the point, the card table is an affordance.
pcall(function()
    local Deadweight = require(script.Parent.deadweight_server)
    Deadweight.start()
end)
