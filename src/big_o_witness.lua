-- src/big_o_witness.lua -- BIG_O's signature mechanic, as a pure Luau module for Roblox.
--
-- This is the first direction of the merge: build the IP into Roblox by porting the part that does not need an engine.
-- BIG_O's own rule (`BIG_O/core/witness_rules.c`, spec in `BIG_O/docs/B1_WITNESS_RULES.md`) is: reality in polite
-- society is whatever has been socially acknowledged. One witness goes into catatonic denial; five or more can no
-- longer pretend, so the group turns to aggressive silencing; a witness you compromise becomes an accomplice and helps
-- cover it up.
--
-- The thresholds here are BIG_O's, and they are the reason this port comes first: they are integers, they are the
-- IP's whole identity, and nothing about them needs SHANKPIT, a renderer, or a network. `WITNESS_SILENCING` is 5, not
-- "a group feels threatened around five" -- a Roblox noob and a SHANKPIT citizen must agree, or the two worlds are
-- telling different stories.
--
-- Headless by design (no `game`/`Instance`/`wait`), so it can be tested with a plain Lua interpreter. The Roblox host
-- is src/noobtopia.lua.

local Witness = {}

-- BIG_O witness states (BIG_O/core/witness_rules.h): an NPC a fact is told to resolves to one of these.
Witness.UNAWARE = 0    -- never saw it, so it is not real
Witness.DENIAL = 1     -- saw it, refuses to admit it: looks away, talks louder about quarterly numbers
Witness.SILENCING = 2  -- the group cannot pretend any more and moves to clean the witness list
Witness.COMPROMISED = 3 -- an asset: helps cover it up to protect itself

-- Thresholds, transcribed from BIG_O's rules module (WITNESS_SILENCING_THRESHOLD = 5).
Witness.GROUP_THRESHOLD = 5

-- How many witnesses of ONE event are still denying it (i.e. not compromised, not silencing).
local function denying(list)
    local n = 0
    for _, w in ipairs(list) do
        if w.state == Witness.DENIAL then n = n + 1 end
    end
    return n
end

-- The group state for one witnessed event, given every NPC who saw it.
-- Returns: state, count. SILENCING wins over denial the moment the count reaches the threshold -- that ordering is
-- BIG_O's own (a crowd that has crossed the line no longer cares how many individuals are still denying it).
function Witness.resolve(list)
    local n = denying(list)
    if n >= Witness.GROUP_THRESHOLD then return Witness.SILENCING, n end
    if n >= 1 then return Witness.SILENCING - 1 - 0 + Witness.DENIAL - 1, n end -- n >= 1: DENIAL
    return Witness.UNAWARE, 0
end

-- A witness who is talked to (or bought, or whose own exposure you threaten) becomes an asset. Silencing is
-- deliberately NOT reachable this way: a crowd past the threshold cannot be individually bought back, which is the
-- whole reason the mechanic has teeth.
function Witness.compromise(witness)
    if witness.state == Witness.DENIAL then
        witness.state = Witness.COMPROMISED
        return true
    end
    return false
end

-- Does a compromised witness now help hide it? BIG_O: yes, to protect itself.
function Witness.helpsCoverUp(list)
    for _, w in ipairs(list) do
        if w.state == Witness.COMPROMISED then return true end
    end
    return false
end

-- The one decision a Roblox demo needs to *show* the mechanic: what a noob does when it has seen something it cannot
-- admit. Returns a line, so the port is visible on screen and not only in a test.
function Witness.lineFor(state)
    if state == Witness.DENIAL then return "What? I didn't see anything."
    elseif state == Witness.SILENCING then return "Get them. Before anyone else sees."
    elseif state == Witness.COMPROMISED then return "Relax. I was never here either."
    else return "Seen what?"
    end
end

return Witness
