-- Persistent settings stored as JSON in the mod's save slot.
local AC = TBOIAC
local json = require("json")
local util = AC.util

local save = {}

save.defaults = {
    ui = { lang = "ru", scale = 1, alpha = 0.8, x = 40, y = 30, pauseWorld = false },
    keys = { open = Keyboard.KEY_F2 },
    player = {
        target = 0,
        god = false, oneHit = false, flight = false, noclip = false,
        infCoins = false, infBombs = false, infKeys = false, infCharge = false,
        stats = { damage = 0, tears = 0, speed = 0, range = 0, shotspeed = 0, luck = 0 },
        size = 1,
    },
    time = { mode = 0, freezeEnemies = false, freezeProjectiles = false },
    enemies = { hpMult = 1, allChampions = false, friendlySpawn = false },
    world = { noCurses = false },
    recent = { items = {}, entities = {} },
    rules = { enabled = true, list = {}, nextId = 1 },
    -- Item pool filters: black/white are id lists, replace is a list of { from, to }.
    pools = { enabled = false, black = {}, white = {}, replace = {}, qmin = 0, qmax = 4 },
    -- Per-run rule state; wiped when a new run starts (kept on continue).
    run = {
        flags = {}, counters = {}, fired = {}, matches = {},
        stats = { damage = 0, tears = 0, speed = 0, range = 0, shotspeed = 0, luck = 0 },
    },
}

save.data = util.copy(save.defaults)

function save.load()
    local mod = AC.mod
    if not mod:HasData() then return end
    local ok, data = pcall(json.decode, mod:LoadData())
    if ok and type(data) == "table" then
        save.data = util.merge(data, save.defaults)
    else
        util.log("save data is corrupt, using defaults")
    end
end

function save.write()
    save.dirty = false
    local ok, str = pcall(json.encode, save.data)
    if ok then AC.mod:SaveData(str) end
end

-- Menu edits call this; the actual write is throttled by save.flush().
function save.markDirty()
    save.dirty = true
end

local lastFlush = 0

function save.flush(force)
    if not save.dirty then return end
    local now = Isaac.GetFrameCount()
    if force or now - lastFlush >= 60 then
        lastFlush = now
        save.write()
    end
end

-- Remember a value at the front of a bounded list.
function save.pushRecent(list, value, limit)
    for i = #list, 1, -1 do
        if list[i] == value then table.remove(list, i) end
    end
    table.insert(list, 1, value)
    while #list > (limit or 10) do table.remove(list) end
end

return save
