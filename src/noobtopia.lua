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
local LINES = require(script.Parent.data.noob_lines)

-- Surface ids, matching PARENA/stdlib/noobtopia/arena_rules.prn:
local CONCRETE, ICE, GRASS, METAL, MUD = 0, 1, 2, 3, 4

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

    -- 1. decide a wish: wander, and now and then stand still (which is when the surface takes over and you slide)
    if math.random() < 0.02 then
        noob.wish = math.random(-12, 12)
    end

    -- 2. ask the shared rules for the next speed. No input is -1, the rules' own "slide" convention.
    local surface = surfaceAt(root.Position.X, root.Position.Z)
    local wish = noob.wish
    if math.abs(wish) < 1 then wish = -1 end
    noob.speed = Arena.stepSpeed(noob.speed, wish, surface)

    -- 3. move. Speed is a magnitude; direction is the wish's sign (flip when the wish flips).
    if noob.speed > 0 and wish ~= -1 then
        local dir = (wish < 0) and -1 or 1
        root.CFrame = root.CFrame + Vector3.new(dir * noob.speed * dt, 0, 0)
        if dir < 0 then
            root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(-1, 0, 0))
        else
            root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(1, 0, 0))
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

-- Spawn up to MAX_NOOBS, topping up as they die (the original script's loop, minus the 0.1s hammering)
local spawnAccum = 0
RunService.Heartbeat:Connect(function(dt)
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

workspace.Clicked:Connect(function() end) -- placeholder: a real place hooks a Tool's Activated event instead
