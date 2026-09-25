-- Smoke test: loads the mod against a stubbed Isaac API, opens the menu, visits every
-- page, presses every widget, and runs every registered callback once.
-- Catches Lua-level mistakes (typos, nil calls, bad enum names), not game behaviour.

local errors = {}
local function fail(msg) errors[#errors + 1] = msg end

-- Proxy that accepts any field access / call and returns another proxy.
local Any
local anyMeta = {
    __index = function() return Any end,
    __call = function() return Any end,
    __add = function() return Any end, __sub = function() return Any end,
    __mul = function() return Any end, __div = function() return Any end,
    __unm = function() return Any end, __band = function() return 0 end,
    __lt = function() return false end, __le = function() return false end,
    __concat = function(a, b) return tostring(a) .. tostring(b) end,
    __tostring = function() return "<any>" end,
    __newindex = function() end,
}
Any = setmetatable({}, anyMeta)

-- Object with explicit members, falling back to Any.
local function obj(members)
    return setmetatable(members or {}, { __index = function() return function() return Any end end })
end

-- Strict enum: unknown names are reported.
local function enum(name, values)
    return setmetatable(values, {
        __index = function(_, k) fail("unknown enum " .. name .. "." .. tostring(k)) return -999 end,
    })
end

local function vec(x, y)
    return setmetatable({ X = x, Y = y }, {
        __add = function(a, b) return vec(a.X + b.X, a.Y + b.Y) end,
        __sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y) end,
        __mul = function(a, b)
            if type(a) == "number" then a, b = b, a end
            if type(b) == "number" then return vec(a.X * b, a.Y * b) end
            return vec(a.X * b.X, a.Y * b.Y)
        end,
    })
end
Vector = setmetatable({ Zero = vec(0, 0), FromAngle = function() return vec(1, 0) end },
    { __call = function(_, x, y) return vec(x, y) end })
Color = function() return {} end
KColor = function() return {} end
EntityRef = function() return {} end
Random = function() return 12345 end
GetPtrHash = function(x) return tostring(x) end

local keyboard = { KEY_SPACE = 32, KEY_APOSTROPHE = 39, KEY_MINUS = 45, KEY_PERIOD = 46,
    KEY_0 = 48, KEY_9 = 57, KEY_A = 65, KEY_Z = 90, KEY_GRAVE_ACCENT = 96, KEY_ESCAPE = 256,
    KEY_ENTER = 257, KEY_BACKSPACE = 259, KEY_INSERT = 260, KEY_RIGHT = 262, KEY_LEFT = 263,
    KEY_DOWN = 264, KEY_UP = 265, KEY_HOME = 268, KEY_KP_0 = 320, KEY_KP_9 = 329, KEY_KP_ENTER = 335,
    KEY_LEFT_SHIFT = 340, KEY_RIGHT_SHIFT = 344 }
for i = 1, 12 do keyboard["KEY_F" .. i] = 289 + i end
Keyboard = enum("Keyboard", keyboard)
Controller = enum("Controller", { DPAD_LEFT = 0, DPAD_RIGHT = 1, DPAD_UP = 2, DPAD_DOWN = 3,
    BUTTON_A = 4, BUTTON_B = 5, BUTTON_X = 6, BUTTON_Y = 7, BUMPER_LEFT = 8, TRIGGER_LEFT = 9,
    STICK_LEFT = 10, BUMPER_RIGHT = 11, TRIGGER_RIGHT = 12, STICK_RIGHT = 13, BUTTON_BACK = 14, BUTTON_START = 15 })
ButtonAction = enum("ButtonAction", { ACTION_LEFT = 0, ACTION_RIGHT = 1, ACTION_UP = 2, ACTION_DOWN = 3,
    ACTION_SHOOTLEFT = 4, ACTION_SHOOTRIGHT = 5, ACTION_SHOOTUP = 6, ACTION_SHOOTDOWN = 7, ACTION_BOMB = 8,
    ACTION_ITEM = 9, ACTION_PILLCARD = 10, ACTION_DROP = 11, ACTION_PAUSE = 12, ACTION_MAP = 13,
    ACTION_MENUCONFIRM = 14, ACTION_MENUBACK = 15, ACTION_RESTART = 16, ACTION_FULLSCREEN = 17, ACTION_MUTE = 18 })
InputHook = enum("InputHook", { IS_ACTION_PRESSED = 0, IS_ACTION_TRIGGERED = 1, GET_ACTION_VALUE = 2 })
local callbackNames = { "MC_POST_RENDER", "MC_INPUT_ACTION", "MC_POST_GAME_STARTED", "MC_PRE_GAME_EXIT",
    "MC_ENTITY_TAKE_DMG", "MC_EVALUATE_CACHE", "MC_POST_PEFFECT_UPDATE", "MC_POST_UPDATE",
    "MC_POST_NEW_ROOM", "MC_NPC_UPDATE", "MC_POST_CURSE_EVAL" }
local cbEnum = {}
for i, n in ipairs(callbackNames) do cbEnum[n] = i end
ModCallbacks = enum("ModCallbacks", cbEnum)
EntityType = enum("EntityType", { ENTITY_PLAYER = 1, ENTITY_PICKUP = 5, ENTITY_EFFECT = 1000 })
EntityFlag = enum("EntityFlag", { FLAG_FREEZE = 1, FLAG_FRIENDLY = 2, FLAG_PERSISTENT = 4 })
EntityGridCollisionClass = enum("EntityGridCollisionClass", { GRIDCOLL_NONE = 0, GRIDCOLL_GROUND = 5 })
CacheFlag = enum("CacheFlag", { CACHE_DAMAGE = 1, CACHE_FIREDELAY = 2, CACHE_SHOTSPEED = 4, CACHE_RANGE = 8,
    CACHE_SPEED = 16, CACHE_TEARFLAG = 32, CACHE_TEARCOLOR = 64, CACHE_FLYING = 128, CACHE_LUCK = 1024,
    CACHE_SIZE = 2048, CACHE_ALL = 0xFFFF })
ActiveSlot = enum("ActiveSlot", { SLOT_PRIMARY = 0, SLOT_SECONDARY = 1, SLOT_POCKET = 2 })
PickupVariant = enum("PickupVariant", { PICKUP_COLLECTIBLE = 100, PICKUP_TRINKET = 350, PICKUP_TAROTCARD = 300 })
CollectibleType = enum("CollectibleType", { COLLECTIBLE_D6 = 105, COLLECTIBLE_D4 = 284, COLLECTIBLE_D20 = 166,
    COLLECTIBLE_SMELTER = 479, COLLECTIBLE_PAUSE = 478 })
UseFlag = enum("UseFlag", { USE_NOANIM = 1 })
ItemPoolType = enum("ItemPoolType", { POOL_TREASURE = 0 })
PillColor = enum("PillColor", { PILL_BLUE_BLUE = 1 })
RoomType = enum("RoomType", { ROOM_DEFAULT = 1, ROOM_SHOP = 2, ROOM_ERROR = 3, ROOM_TREASURE = 4,
    ROOM_BOSS = 5, ROOM_MINIBOSS = 6, ROOM_SECRET = 7, ROOM_SUPERSECRET = 8, ROOM_ARCADE = 9,
    ROOM_CURSE = 10, ROOM_CHALLENGE = 11, ROOM_LIBRARY = 12, ROOM_SACRIFICE = 13, ROOM_DEVIL = 14,
    ROOM_ANGEL = 15, ROOM_DUNGEON = 16, ROOM_BOSSRUSH = 17, ROOM_ISAACS = 18, ROOM_BARREN = 19,
    ROOM_CHEST = 20, ROOM_DICE = 21, ROOM_BLACK_MARKET = 22, ROOM_GREED_EXIT = 23, ROOM_PLANETARIUM = 24,
    ROOM_TELEPORTER = 25, ROOM_TELEPORTER_EXIT = 26, ROOM_SECRET_EXIT = 27, ROOM_BLUE = 28,
    ROOM_ULTRASECRET = 29 })
GridRooms = enum("GridRooms", { ROOM_DEVIL_IDX = -1, ROOM_ERROR_IDX = -2, ROOM_BLACK_MARKET_IDX = -6 })
Direction = enum("Direction", { NO_DIRECTION = -1 })
RoomTransitionAnim = enum("RoomTransitionAnim", { TELEPORT = 3 })
LevelCurse = enum("LevelCurse", { CURSE_OF_DARKNESS = 1, CURSE_OF_LABYRINTH = 2, CURSE_OF_THE_LOST = 4,
    CURSE_OF_THE_UNKNOWN = 8, CURSE_OF_THE_CURSED = 16, CURSE_OF_MAZE = 32, CURSE_OF_BLIND = 64,
    CURSE_OF_GIANT = 128 })
DoorSlot = enum("DoorSlot", { NUM_DOOR_SLOTS = 8 })
GridEntityType = enum("GridEntityType", { GRID_ROCK = 2, GRID_PIT = 7, GRID_SPIKES = 8, GRID_DOOR = 16,
    GRID_TRAPDOOR = 17, GRID_STAIRS = 18, GRID_WALL = 15 })
EffectVariant = enum("EffectVariant", { HEAVEN_LIGHT_DOOR = 39 })

-- Game objects
local playerData = {}
local player = obj({
    Position = vec(100, 100), ControllerIndex = 0, Damage = 3.5, MaxFireDelay = 10, MoveSpeed = 1,
    TearRange = 260, ShotSpeed = 1, Luck = 0, CanFly = false, SpriteScale = vec(1, 1),
    GetNumCoins = function() return 5 end, GetNumBombs = function() return 1 end,
    GetNumKeys = function() return 1 end, GetData = function() return playerData end,
    GetActiveItem = function() return 0 end, GetTrinket = function() return 0 end,
    HasCollectible = function(_, id) return id == 1 end, GetCollectibleNum = function(_, id) return id == 1 and 1 or 0 end,
    GetPlayerType = function() return 0 end, IsDead = function() return false end,
    ToPlayer = function(self) return self end,
})
local npcData = {}
local npc = obj({
    Position = vec(0, 0), Velocity = vec(0, 0), MaxHitPoints = 10, HitPoints = 10,
    GetData = function() return npcData end, ToNPC = function(self) return self end,
    ToProjectile = function() return nil end, ToPlayer = function() return nil end,
    IsVulnerableEnemy = function() return true end, IsDead = function() return false end,
    HasEntityFlags = function() return false end, IsBoss = function() return false end,
    IsChampion = function() return false end,
})
local proj = obj({ Velocity = vec(1, 1), FallingSpeed = 1, FallingAccel = 0.1, GetData = function() return {} end,
    ToNPC = function() return nil end, ToProjectile = function(self) return self end })
local roomDesc = obj({ SafeGridIndex = 45, Clear = false, Data = { Type = 4 } })
local rooms = obj({ Size = 2, Get = function() return roomDesc end })
local level = obj({ GetRooms = function() return rooms end, GetCurses = function() return 1 end,
    GetStartingRoomIndex = function() return 84 end, GetCurrentRoomIndex = function() return 84 end })
local room = obj({ GetGridSize = function() return 3 end, GetDoor = function() return nil end,
    GetGridEntity = function() return nil end, FindFreeTilePosition = function() return vec(0, 0) end,
    FindFreePickupSpawnPosition = function() return vec(0, 0) end })
local game = obj({ GetNumPlayers = function() return 1 end, GetLevel = function() return level end,
    GetRoom = function() return room end, GetSeeds = function() return obj({ GetStartSeedString = function() return "ABCD 1234" end }) end,
    TimeCounter = 0 })
Game = function() return game end
local function list(n) return obj({ Size = n }) end
local itemConfig = obj({
    GetCollectibles = function() return list(4) end, GetTrinkets = function() return list(3) end,
    GetCards = function() return list(3) end, GetPillEffects = function() return list(3) end,
    GetCollectible = function(_, id) return { Name = id == 2 and "The Sad Onion" or "#ITEM_" .. id .. "_NAME" } end,
    GetTrinket = function(_, id) return { Name = "#TRINKET_" .. id .. "_NAME" } end,
    GetCard = function(_, id) return { Name = "#CARD_" .. id .. "_NAME" } end,
    GetPillEffect = function(_, id) return { Name = "#PILL_" .. id .. "_NAME" } end,
})

-- Input simulation: set of pressed keys for this frame.
local pressed = {}
Input = {
    IsButtonPressed = function(k) return pressed[k] == true end,
    IsButtonTriggered = function(k) return pressed[k] == true end,
}

local debugLog = {}
local callbacks = {}
local saved
Isaac = {
    GetPlayer = function() return player end,
    GetItemConfig = function() return itemConfig end,
    DebugString = function(s) debugLog[#debugLog + 1] = s end,
    GetScreenWidth = function() return 480 end, GetScreenHeight = function() return 270 end,
    GetFrameCount = function() return 0 end,
    RenderText = function() end,
    Spawn = function() return npc end, GridSpawn = function() end,
    GetRoomEntities = function() return { npc, proj } end,
    FindByType = function() return { obj({ Variant = 10, Position = vec(0, 0) }) } end,
    GetFreeNearPosition = function(p) return p end,
    ExecuteCommand = function() return "" end,
}
Font = function() return obj({ IsLoaded = function() return true end, GetLineHeight = function() return 10 end,
    GetStringWidthUTF8 = function(_, s) return #s * 5 end }) end
Sprite = function() return obj() end

RegisterMod = function(name)
    return {
        Name = name,
        AddCallback = function(_, id, fn, param)
            callbacks[#callbacks + 1] = { id = id, fn = fn, param = param }
        end,
        HasData = function() return saved ~= nil end,
        LoadData = function() return saved end,
        SaveData = function(_, s) saved = s end,
    }
end

-- Minimal JSON for save round-trips.
package.preload.json = function()
    local function encode(v)
        local tv = type(v)
        if tv == "table" then
            if #v > 0 or next(v) == nil then
                local parts = {}
                for _, x in ipairs(v) do parts[#parts + 1] = encode(x) end
                return "[" .. table.concat(parts, ",") .. "]"
            end
            local parts = {}
            for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", tostring(k), encode(x)) end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif tv == "string" then return string.format("%q", v)
        else return tostring(v) end
    end
    local function decode(s)
        local lua = s:gsub("%[", "{"):gsub("%]", "}"):gsub('("[^"]-"):', "[%1]=")
        return load("return " .. lua)()
    end
    return { encode = encode, decode = decode }
end

include = function(path)
    return dofile(path:gsub("%.", "/") .. ".lua")
end

-- Load the mod.
dofile("main.lua")
local AC = TBOIAC
-- From here on, reading or creating unknown globals is a bug in the mod.
setmetatable(_G, {
    __index = function(_, k) fail("read of undefined global " .. tostring(k)) end,
    __newindex = function(t, k, v) fail("write to new global " .. tostring(k)) rawset(t, k, v) end,
})

local function fire(name, ...)
    for _, cb in ipairs(callbacks) do
        if cb.id == ModCallbacks[name] then
            local ok, err = pcall(cb.fn, AC.mod, ...)
            if not ok then fail(name .. ": " .. tostring(err)) end
        end
    end
end

local function frame(keys)
    pressed = {}
    for _, k in ipairs(keys or {}) do pressed[k] = true end
    fire("MC_POST_RENDER")
end

-- Error toasts from menu actions count as failures.
local toast = AC.render.toast
AC.render.toast = function(msg, ...)
    if tostring(msg):find("Error") or tostring(msg):find("Ошибка") then fail("toast: " .. msg) end
    return toast(msg, ...)
end

for _, lang in ipairs({ "ru", "en" }) do
    AC.save.data.ui.lang = lang
    -- Open the menu and press every widget on every page reachable from root.
    frame({ Keyboard.KEY_F2 })
    assert(AC.menu.open, "menu did not open")
    frame({ Keyboard.KEY_F2 })
    assert(AC.menu.open, "held key toggled the menu twice")
    frame()
    frame({ Keyboard.KEY_F2 })
    assert(not AC.menu.open, "menu did not close")
    frame()
    local visited = {}
    -- Re-open the menu along `path` (list of page ids) so every press starts from a known state.
    local function ensure(path)
        AC.menu.setOpen(true)
        for i = 2, #path do AC.menu.push(path[i]) end
        return AC.menu.stack[#AC.menu.stack]
    end
    local function visit(path)
        local id = path[#path]
        if visited[id] then return end
        visited[id] = true
        local f = ensure(path)
        for i, item in ipairs(f.items) do
            if type(item.label) ~= "string" then fail(id .. ": label is not a string at " .. i) end
        end
        for i = 1, #f.items do
            f = ensure(path)
            local item = f.items[i]
            if item and item.kind ~= "info" and not item.label:find("!!") then
                f.cursor = i
                if item.kind == "page" then
                    local target = type(item.page) == "function" and item.page() or item.page
                    local tid = type(target) == "table" and target.id or target
                    if not AC.menu.pages[tid] then fail(id .. ": link to unknown page " .. tostring(tid)) end
                    local sub = {}
                    for k, v in ipairs(path) do sub[k] = v end
                    sub[#sub + 1] = tid
                    visit(sub)
                elseif item.kind == "text" then
                    local before = item.get()
                    frame({ Keyboard.KEY_ENTER }); frame()
                    frame({ Keyboard.KEY_A }); frame(); frame({ Keyboard.KEY_ENTER }); frame()
                    if item.get() ~= before .. "a" then fail(id .. ": text entry did not work") end
                    item.set(before)
                else
                    frame({ Keyboard.KEY_RIGHT }); frame()
                    frame({ Keyboard.KEY_LEFT }); frame()
                    if item.kind == "action" then frame({ Keyboard.KEY_ENTER }); frame() end
                end
            end
        end
    end
    visit({ "root" })
    local n = 0
    for _ in pairs(visited) do n = n + 1 end
    print(lang .. ": visited " .. n .. " pages")
    AC.menu.setOpen(false)
end

-- Missing translations: every en key must exist in ru and vice versa.
for k in pairs(AC.i18n.langs.en) do
    if AC.i18n.langs.ru[k] == nil then fail("ru missing key " .. k) end
end
for k in pairs(AC.i18n.langs.ru) do
    if AC.i18n.langs.en[k] == nil then fail("en missing key " .. k) end
end
-- Untranslated keys rendered as raw keys.
local rawKey = AC.i18n.t
AC.i18n.t = function(key, ...)
    if AC.i18n.langs.en[key] == nil then fail("no translation for key " .. key) end
    return rawKey(key, ...)
end
AC.menu.setOpen(true)
for id in pairs(AC.menu.pages) do AC.menu.push(id) end
AC.menu.setOpen(false)

-- Enable every modifier and run gameplay callbacks.
local d = AC.save.data
d.player.god, d.player.oneHit, d.player.flight, d.player.noclip = true, true, true, true
d.player.infCoins, d.player.infBombs, d.player.infKeys, d.player.infCharge = true, true, true, true
d.player.size = 2
for k in pairs(d.player.stats) do d.player.stats[k] = 1 end
d.time.mode, d.time.freezeEnemies, d.time.freezeProjectiles = 1, true, true
d.enemies.hpMult, d.enemies.allChampions = 2, true
d.world.noCurses = true
fire("MC_POST_GAME_STARTED", false)
fire("MC_POST_NEW_ROOM")
fire("MC_POST_UPDATE")
fire("MC_POST_PEFFECT_UPDATE", player)
for _, flag in pairs({ 1, 2, 4, 8, 16, 128, 1024, 2048 }) do fire("MC_EVALUATE_CACHE", player, flag) end
fire("MC_ENTITY_TAKE_DMG", player, 1, 0, Any, 0)
fire("MC_NPC_UPDATE", npc)
fire("MC_POST_CURSE_EVAL", 1)
fire("MC_INPUT_ACTION", player, 0, 0)
AC.registry.resetAll()
fire("MC_POST_UPDATE")
fire("MC_PRE_GAME_EXIT", true)
assert(saved, "settings were not saved")
AC.save.load()

for _, line in ipairs(debugLog) do
    if line:find("error") then fail("log: " .. line) end
end

if #errors > 0 then
    for _, e in ipairs(errors) do print("FAIL: " .. e) end
    os.exit(1)
end
print("smoke ok")
