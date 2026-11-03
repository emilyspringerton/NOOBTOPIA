-- src/deadweight_ui.lua -- the ONLY new file that touches the Roblox API. Everything it draws comes from
-- src/deadweight_room.lua's `frame()`; everything it receives is a ProximityPrompt trigger.
--
-- NOT TESTED BY THIS REPO'S TESTS, and it says so: this box has no Roblox Studio, no place file and no `luau`
-- interpreter (let alone the Studio-only global `Instance`), so this file is written and reviewed, never run.
-- The reason it is thin is that this is the part that cannot be checked here: the logic that a screen can get
-- WRONG -- a stale offer, an answer for a challenge that moved, a row for somebody who left -- lives in the
-- pure module, where tests/deadweight_room_test.lua does check it.
--
-- Two Roblox constraints this is built around, both learned the hard way elsewhere in this repo:
--   * a server Script cannot see a click (see src/noobtopia.lua's Punch comment), so the only input used is a
--     ProximityPrompt, whose Triggered event the SERVER receives;
--   * the server CAN write text into a player's PlayerGui, so the board is drawn by the server and the client
--     ships nothing at all.

local Players = game:GetService("Players")

local M = {}

local WOOD = Color3.fromRGB(86, 60, 32)
local INK = Color3.fromRGB(8, 12, 10)
local PAPER = Color3.fromRGB(232, 226, 200)

local function makePart(name, size, cframe, colour)
    local part = Instance.new("Part")
    part.Name = name
    part.Size = size
    part.CFrame = cframe
    part.Anchored = true
    part.TopSurface = Enum.SurfaceType.Smooth
    part.BottomSurface = Enum.SurfaceType.Smooth
    part.Color = colour
    part.Parent = workspace
    return part
end

-- A table you can walk up to: a top, and one prompt standing on it. The prompt's ActionText is rewritten each
-- tick from the frame, so the affordance always says what pressing it will actually do.
function M.build(position)
    local at = position or CFrame.new(0, 3, 40)
    local top = makePart("DeadweightTable", Vector3.new(8, 1, 6), at, WOOD)
    local leg = Instance.new("CylinderShape")
    leg.Parent = top   -- geometry hint only; a tabletop is enough for the affordance

    local prompt = Instance.new("ProximityPrompt")
    prompt.ActionText = "Sit down"
    prompt.ObjectText = "DEADWEIGHT"
    prompt.HoldDuration = 0
    prompt.MaxActivationDistance = 12
    prompt.RequiresLineOfSight = false
    prompt.Parent = top

    return { table = top, prompt = prompt, guis = {} }
end

-- THE STAGE: a raised platform, two podiums, a banner, and stands around it. Built once, at start; the
-- banner's text is rewritten each tick from the tournament's own frame, so what the crowd reads is what the
-- bracket says rather than a second opinion.
function M.buildStage(position)
    local at = position or CFrame.new(0, 3, -70)
    local deck = makePart("DeadweightStage", Vector3.new(26, 2, 20), at, WOOD)

    local left = makePart("DeadweightPodiumA", Vector3.new(3, 3, 3), at * CFrame.new(-6, 2.5, 0), INK)
    local right = makePart("DeadweightPodiumB", Vector3.new(3, 3, 3), at * CFrame.new(6, 2.5, 0), INK)

    -- the stands: three risers a side, so a crowd has somewhere to be that is not the playfield
    for i = 1, 3 do
        makePart("DeadweightStandL" .. i, Vector3.new(3, 1, 18), at * CFrame.new(-15 - i * 3, 1 + i, 0), WOOD)
        makePart("DeadweightStandR" .. i, Vector3.new(3, 1, 18), at * CFrame.new(15 + i * 3, 1 + i, 0), WOOD)
    end

    local banner = makePart("DeadweightBanner", Vector3.new(22, 5, 1), at * CFrame.new(0, 7, -9), INK)
    local surface = Instance.new("SurfaceGui")
    surface.Face = Enum.NormalId.Front
    surface.CanvasSize = Vector2.new(880, 200)
    surface.Parent = banner
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = PAPER
    label.Font = Enum.Font.Code
    label.TextScaled = true
    label.Text = "THE PIT"
    label.Parent = surface

    return { stage = deck, podiums = { left, right }, banner = banner, label = label }
end

function M.setBanner(stage, text)
    if stage and stage.label and stage.label.Parent then stage.label.Text = text end
end

local function guiFor(ui, player)
    if ui.guis[player] then return ui.guis[player] end

    local gui = Instance.new("ScreenGui")
    gui.Name = "Deadweight"
    gui.ResetOnSpawn = false
    gui.Enabled = false
    gui.Parent = player:WaitForChild("PlayerGui")

    local panel = Instance.new("Frame")
    panel.Size = UDim2.new(0, 300, 0, 240)
    panel.Position = UDim2.new(1, -320, 0.5, -120)
    panel.BackgroundColor3 = PAPER
    panel.BorderSizePixel = 0
    panel.Parent = gui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 26)
    title.BackgroundColor3 = INK
    title.TextColor3 = PAPER
    title.Font = Enum.Font.Code
    title.TextSize = 18
    title.Text = "DEADWEIGHT"
    title.Parent = panel

    local body = Instance.new("TextLabel")
    body.Name = "Body"
    body.Position = UDim2.new(0, 8, 0, 34)
    body.Size = UDim2.new(1, -16, 1, -42)
    body.BackgroundTransparency = 1
    body.TextColor3 = INK
    body.Font = Enum.Font.Code
    body.TextSize = 14
    body.TextXAlignment = Enum.TextXAlignment.Left
    body.TextYAlignment = Enum.TextYAlignment.Top
    body.Text = ""
    body.Parent = panel

    local entry = { gui = gui, body = body }
    ui.guis[player] = entry
    return entry
end

-- Draws one player's panel from the frame. Pure assignment: no decisions, no state.
function M.render(ui, player, frame)
    local entry = guiFor(ui, player)
    if not frame then
        entry.gui.Enabled = false
        return
    end
    entry.gui.Enabled = true
    local lines = {}
    lines[#lines + 1] = frame.prompt
    lines[#lines + 1] = string.format("%d/%d seats", frame.seated, frame.seats)
    lines[#lines + 1] = ""
    for _, line in ipairs(frame.lines) do lines[#lines + 1] = line end
    if frame.you then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("you: %d  (%d-%d)", frame.you.rating, frame.you.wins, frame.you.games)
    end
    if #frame.log > 0 then
        lines[#lines + 1] = ""
        for _, line in ipairs(frame.log) do lines[#lines + 1] = "-- " .. line end
    end
    local t = frame.tournament
    if t then
        lines[#lines + 1] = ""
        lines[#lines + 1] = string.format("%s  round %d/%d  (%d entrants%s)", t.name, t.round, t.rounds, t.entrants,
            t.byes > 0 and (", " .. t.byes .. " bye" .. (t.byes == 1 and "" or "s")) or "")
        if t.champion then
            lines[#lines + 1] = "CHAMPION  P" .. tostring(t.champion)
        elseif t.match then
            lines[#lines + 1] = "on stage: P" .. tostring(t.match.a) .. " vs P" .. tostring(t.match.b)
        end
        for i = math.max(1, #t.lines - 2), #t.lines do
            lines[#lines + 1] = "  " .. t.lines[i]
        end
    end
    entry.body.Text = table.concat(lines, "\n")
end

function M.setAction(ui, text)
    if ui.prompt and ui.prompt.Parent then ui.prompt.ActionText = text end
end

function M.forget(ui, player)
    local entry = ui.guis[player]
    if entry and entry.gui then entry.gui:Destroy() end
    ui.guis[player] = nil
end

function M.destroyStage(stage)
    if not stage then return end
    if stage.banner and stage.banner.Parent then stage.banner:Destroy() end
    for _, p in ipairs(stage.podiums or {}) do if p.Parent then p:Destroy() end end
    if stage.stage and stage.stage.Parent then stage.stage:Destroy() end
end

function M.destroy(ui)
    for player in pairs(ui.guis) do M.forget(ui, player) end
    if ui.prompt and ui.prompt.Parent then ui.prompt:Destroy() end
    if ui.table and ui.table.Parent then ui.table:Destroy() end
end

-- The prompt is the input; the routing is all in the room. Returns the room's own answer string so the host can
-- log what actually happened rather than what it hoped happened.
function M.bind(ui, onPress)
    ui.prompt.Triggered:Connect(function(player)
        if player and player.UserId then onPress(player) end
    end)
end

M.Players = Players
return M
