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
