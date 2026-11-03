-- src/deadweight_server.lua -- the glue: one ladder per SERVER, one table, one prompt, one clock.
--
-- Founder, real-time: "the leaderboard can be per server and reset its fine it lets players face the noobs and
-- also eachother to climb the elos", then "we dont need iduna i guess just the leaderboard for now whatever you
-- think". So this is deliberately the whole of the persistence story on Roblox: the ladder is seeded from the
-- job id and lives in this server's memory. When the server ends the board resets. That is the accepted design,
-- not an oversight -- a permanent home is a later decision, and pretending otherwise would mean shipping a
-- DataStore schema nobody has agreed to.
--
-- NOT RUNNABLE HERE. Like src/deadweight_ui.lua this needs Roblox Studio; this file is written and reviewed,
-- never executed by this repo's tests. What it does is deliberately mechanical: tick the room, redraw the
-- panels, route one prompt. The decisions are in src/deadweight_room.lua, which IS tested.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Ladder = require(script.Parent.deadweight_ladder)
local Board = require(script.Parent.deadweight_board)
local Room = require(script.Parent.deadweight_room)
local Tour = require(script.Parent.deadweight_tournament)
local UI = require(script.Parent.deadweight_ui)

local M = {}

M.TICK_SECONDS = 0.25
M.CITIZENS = 3            -- noobs standing at the table, so a lone player always has somebody to play
M.STAGE_MIN = 3           -- members needed before the world opens a bracket (3 fits a 4-slot stage with a bye)
M.STAGE_COOLDOWN_MS = 60000   -- how long a finished stage keeps its champion on the banner

-- Opens the next stage when the population can field one and nothing is running. Called from the tick, so a
-- stage begins on the world's clock rather than on anybody's arrival.
local function maybeStage(room, now)
    local t = room.tournament
    if t and not Tour.done(t) then return end
    if t and Tour.done(t) and (now - (room.stageEndedMs or 0)) < M.STAGE_COOLDOWN_MS then return end
    if room.ladder.count < M.STAGE_MIN then return end
    if Room.startTournament(room, now, 4) then room.stageEndedMs = 0 end
end

-- A stable number for THIS server. Two servers get different populations; the same server restarts and gets the
-- same tables, which is what makes a bug reproducible from a log line.
local function jobSeed()
    local id = tostring(game.JobId ~= "" and game.JobId or "studio")
    local h = 0
    for i = 1, #id do
        h = (h * 31 + string.byte(id, i)) % 4294967296
    end
    return h ~= 0 and h or 777
end

-- Player pids are UserIds; citizens get synthetic pids from a base far above any UserId, so the two species
-- cannot collide in the ladder.
--
-- NOT negative, and that is a fixed bug rather than a preference: `Ladder.memberForPid` answers -1 for any pid
-- below zero (the same "-1 means nobody" sentinel dw_member_for_pid keeps in C), so a citizen given a negative
-- pid sat at the table while being invisible to everything that matters -- unranked on the board, unchallengeable
-- (`Room.press` answered "busy"), never rated. tests/deadweight_room_test.lua caught it. UserIds are nowhere
-- near 1e12, so this base is collision-free for the lifetime of the game.
M.CITIZEN_PID_BASE = 1000000000000
local function citizenPid(index)
    return M.CITIZEN_PID_BASE + index
end

function M.start(position)
    local seed = jobSeed()
    local ladder = Ladder.new(seed)
    local board = Board.new()
    local room = Room.new(ladder, board)

    -- the noobs at the table: they exist so a player arriving alone has an opponent, and they climb too
    for i = 1, M.CITIZENS do
        Room.join(room, citizenPid(i), false, 0)
    end

    -- the table must actually be able to hold them: a citizen the ladder cannot see is the bug documented above
    for i = 1, M.CITIZENS do
        assert(Ladder.memberForPid(ladder, citizenPid(i)) >= 0, "citizen " .. citizenPid(i) .. " is not on the ladder")
    end

    local ui = UI.build(position)
    local stage = UI.buildStage()

    UI.bind(ui, function(player)
        local answer = Room.press(room, player.UserId, os.clock() * 1000)
        if answer == "full" then
            -- say so through the panel rather than failing silently: a table that ignores a press reads broken
            UI.setAction(ui, "Table is full")
        end
    end)

    Players.PlayerRemoving:Connect(function(player)
        Room.leave(room, player.UserId)
        UI.forget(ui, player)
    end)

    local accum = 0
    RunService.Heartbeat:Connect(function(dt)
        accum = accum + dt
        if accum < M.TICK_SECONDS then return end
        accum = 0

        local now = os.clock() * 1000
        Room.tick(room, now)

        -- the esports stage, on the world's own clock: opened when a bracket can be fielded, and its champion
        -- left on the banner for a minute before the next one seeds
        maybeStage(room, now)
        local tour = room.tournament
        if tour and Tour.done(tour) then
            if not room.stageEndedMs or room.stageEndedMs == 0 then room.stageEndedMs = now end
            UI.setBanner(stage, "CHAMPION  P" .. tostring(tour.champion))
        elseif tour then
            UI.setBanner(stage, string.format("THE PIT  \u2014  ROUND %d", tour.round))
        else
            UI.setBanner(stage, "THE PIT")
        end

        -- one frame per player, from the same room state, so two players can never see two different tables
        local any = nil
        for _, player in ipairs(Players:GetPlayers()) do
            local frame = Room.frame(room, player.UserId)
            UI.render(ui, player, frame)
            if not any then any = frame end
        end
        if any then UI.setAction(ui, any.waiting and "Play" or "Sit down") end
    end)

    return { room = room, ui = ui, stage = stage, ladder = ladder, board = board, seed = seed }
end

return M
