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
    -- Arena waves: list entries are { kind = "enemy"|"boss"|"entity", ent = "t.v.s", count, champion }.
    waves = {
        list = {
            { kind = "enemy", ent = "10.0.0", count = 4, champion = false },
            { kind = "enemy", ent = "10.0.0", count = 6, champion = false },
            { kind = "boss", ent = "20.0.0", count = 1, champion = false },
        },
        mode = "clear", interval = 20, pause = 3, total = 10, endless = true, growth = 1, bossEvery = 5,
        reward = "pickup", lockDoors = true,
    },
    -- Studio: overlay for videos, clean frame, profiles (profiles are not part of a profile).
    studio = {
        clean = false, cleanKey = Keyboard.KEY_F3,
        timer = { show = false, x = 20, y = 200 },
        showRules = false, rulesX = 300, rulesY = 40,
        showCounters = false, countersX = 20, countersY = 60,
        lines = {
            { text = "", x = 20, y = 230, show = false },
            { text = "", x = 20, y = 245, show = false },
            { text = "", x = 20, y = 260, show = false },
        },
    },
    profiles = {},
    -- Reward rules: room clear award multiplier/bonus, pickup multiplier, enemy drops.
    drops = {
        enabled = false, clearMult = 1, clearBonus = "none", noClearAward = false, bossItems = 0,
        pickupMult = 1, noPickups = false, enemyDrop = 0,
    },
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
