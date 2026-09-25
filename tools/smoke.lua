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

-- Object whose unknown methods are reported (names from the real API listed in `known`).
local function strictObj(members, known)
    local ok = {}
    for _, name in ipairs(known) do ok[name] = true end
    return setmetatable(members, { __index = function(_, k)
        if not ok[k] then fail("unknown API member " .. tostring(k)) end
        return function() return Any end
    end })
end

local PLAYER_API = { "AddCollectible", "RemoveCollectible", "HasCollectible", "GetCollectibleNum",
    "GetCollectibleCount", "AddTrinket", "TryRemoveTrinket", "GetTrinket", "HasTrinket", "UseActiveItem",
    "UseCard", "UsePill", "AddMaxHearts", "AddHearts", "AddSoulHearts", "AddBlackHearts", "AddBoneHearts",
    "AddGoldenHearts", "AddEternalHearts", "AddRottenHearts", "AddBrokenHearts", "SetFullHearts", "GetHearts",
    "GetSoulHearts", "GetBoneHearts", "AddCoins", "AddBombs", "AddKeys", "GetNumCoins", "GetNumBombs",
    "GetNumKeys", "AddGoldenBomb", "AddGoldenKey", "ChangePlayerType", "GetPlayerType", "Revive", "Kill",
    "Die", "IsDead", "TakeDamage", "AddCacheFlags", "EvaluateItems", "GetActiveItem", "NeedsCharge",
    "FullCharge", "GetData", "ToPlayer", "ToNPC", "ToPickup", "ToProjectile", "Exists", "Remove",
    "AddVelocity", "GetName", "AddEntityFlags", "HasEntityFlags", "ClearEntityFlags", "GetSprite", "SetColor",
    "GridCollisionClass", "AddCostume", "ClearCostumes" }

-- Strict enum: unknown names are reported.
local function enum(name, values)
    return setmetatable(values, {
        __index = function(_, k) fail("unknown enum " .. name .. "." .. tostring(k)) return -999 end,
    })
end

local function vec(x, y)
    return setmetatable({ X = x, Y = y,
        Distance = function(a, b) return math.sqrt((a.X - b.X) ^ 2 + (a.Y - b.Y) ^ 2) end,
        Normalized = function(a) return vec(1, 0) end,
        GetAngleDegrees = function() return 0 end }, {
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
for c = 65, 90 do keyboard["KEY_" .. string.char(c)] = c end
keyboard.KEY_TAB = 258
for d = 0, 9 do keyboard["KEY_" .. d] = 48 + d; keyboard["KEY_KP_" .. d] = 320 + d end
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
    "MC_POST_NEW_ROOM", "MC_NPC_UPDATE", "MC_POST_CURSE_EVAL", "MC_POST_NEW_LEVEL", "MC_POST_NPC_DEATH",
    "MC_POST_PICKUP_UPDATE", "MC_USE_ITEM", "MC_USE_CARD", "MC_USE_PILL", "MC_POST_FIRE_TEAR",
    "MC_POST_GET_COLLECTIBLE", "MC_PRE_SPAWN_CLEAN_AWARD", "MC_POST_PICKUP_INIT", "MC_PRE_NPC_UPDATE" }
local cbEnum = {}
for i, n in ipairs(callbackNames) do cbEnum[n] = i end
ModCallbacks = enum("ModCallbacks", cbEnum)
EntityType = enum("EntityType", { ENTITY_PLAYER = 1, ENTITY_PICKUP = 5, ENTITY_EFFECT = 1000 })
vec(0, 0) -- ensure metatable-created vectors exist before use
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
SeedEffect = enum("SeedEffect", { SEED_BIG_HEAD = 32, SEED_KAPPA = 44, SEED_NO_HUD = 10 })
Music = enum("Music", { MUSIC_NULL = 0, MUSIC_BASEMENT = 1, MUSIC_CAVES = 2, MUSIC_BOSS = 11 })
MusicManager = function() return obj() end

-- Game objects
local playerData = {}
local player = strictObj({
    Position = vec(100, 100), ControllerIndex = 0, Damage = 3.5, MaxFireDelay = 10, MoveSpeed = 1,
    TearRange = 260, ShotSpeed = 1, Luck = 0, CanFly = false, SpriteScale = vec(1, 1),
    GetNumCoins = function() return 5 end, GetNumBombs = function() return 1 end,
    GetNumKeys = function() return 1 end, GetData = function() return playerData end,
    GetActiveItem = function() return 0 end, GetTrinket = function() return 0 end,
    HasCollectible = function(_, id) return id == 1 end, GetCollectibleNum = function(_, id) return id == 1 and 1 or 0 end,
    GetPlayerType = function() return 0 end, IsDead = function() return false end,
    ToPlayer = function(self) return self end, ToNPC = function() return nil end, Exists = function() return true end,
    GetHearts = function() return 6 end, GetSoulHearts = function() return 2 end, GetBoneHearts = function() return 0 end,
    GetCollectibleCount = function() return 3 end, HasTrinket = function() return false end,
    QueuedItem = { Item = obj({ ID = 7, IsCollectible = function() return true end }) }, Type = 1,
    Color = { R = 1, G = 1, B = 1, A = 1, RO = 0, GO = 0, BO = 0 }, SpriteRotation = 0, Velocity = vec(0, 0),
}, PLAYER_API)
local npcData = {}
local npc = obj({
    Position = vec(0, 0), Velocity = vec(0, 0), MaxHitPoints = 10, HitPoints = 10,
    GetData = function() return npcData end, ToNPC = function(self) return self end,
    ToProjectile = function() return nil end, ToPlayer = function() return nil end,
    IsVulnerableEnemy = function() return true end, IsDead = function() return false end,
    HasEntityFlags = function() return false end, IsBoss = function() return false end,
    IsChampion = function() return false end, Exists = function() return true end,
    Color = { R = 1, G = 1, B = 1, A = 1, RO = 0, GO = 0, BO = 0 }, SpriteRotation = 0,
    GetSprite = function() return obj({ IsPlaying = function() return true end }) end,
    ToPickup = function() return nil end, Type = 10, Variant = 0, SubType = 0,
})
local pickup = obj({ Type = 5, Variant = 100, SubType = 3, Position = vec(0, 0), Velocity = vec(0, 0),
    Color = { R = 1, G = 1, B = 1, A = 1, RO = 0, GO = 0, BO = 0 }, SpriteRotation = 0,
    GetData = function() return {} end, ToNPC = function() return nil end, Exists = function() return true end,
    ToPickup = function(self) return self end, ToPlayer = function() return nil end,
    GetSprite = function() return obj({ IsPlaying = function() return true end }) end })
local proj = obj({ Velocity = vec(1, 1), FallingSpeed = 1, FallingAccel = 0.1, GetData = function() return {} end,
    ToNPC = function() return nil end, ToProjectile = function(self) return self end })
local roomDesc = obj({ SafeGridIndex = 45, Clear = false, Data = { Type = 4 } })
local rooms = obj({ Size = 2, Get = function() return roomDesc end })
local level = obj({ GetRooms = function() return rooms end, GetCurses = function() return 1 end,
    GetStage = function() return 3 end,
    GetStartingRoomIndex = function() return 84 end, GetCurrentRoomIndex = function() return 84 end })
local door = strictObj({}, { "Open", "Close", "Bar", "SetLocked", "TryBlowOpen" })
local room = obj({ GetGridSize = function() return 3 end, GetDoor = function(_, slot) return slot == 0 and door or nil end,
    GetClampedPosition = function(_, p) return p end,
    GetFrameCount = function() return 10 end,
    SpawnClearAward = function() clearAwards = (clearAwards or 0) + 1 end,
    GetType = function() return 5 end, IsFirstVisit = function() return true end, IsClear = function() return false end,
    GetRandomPosition = function() return vec(10, 10) end, GetCenterPos = function() return vec(20, 20) end,
    GetGridEntity = function() return nil end, FindFreeTilePosition = function() return vec(0, 0) end,
    FindFreePickupSpawnPosition = function() return vec(0, 0) end })
-- Item pool that hands out ids 1, 2, 3 in turn.
local poolNext = 0
local itemPool = obj({ GetCollectible = function() poolNext = poolNext % 3 + 1 return poolNext end })
RNG = function() return obj({ Next = function() return 7 end, RandomInt = function(_, n) return 0 end }) end
local game = obj({ GetItemPool = function() return itemPool end, GetNumPlayers = function() return 1 end, GetLevel = function() return level end,
    GetRoom = function() return room end, GetSeeds = function() return obj({ GetStartSeedString = function() return "ABCD 1234" end }) end,
    TimeCounter = 0 })
Game = function() return game end
local function list(n) return obj({ Size = n }) end
local itemConfig = obj({
    GetCollectibles = function() return list(4) end, GetTrinkets = function() return list(3) end,
    GetCards = function() return list(3) end, GetPillEffects = function() return list(3) end,
    GetCollectible = function(_, id)
        if type(id) ~= "number" or id < 1 or id > 3 then return nil end
        return { Name = id == 2 and "The Sad Onion" or "#ITEM_" .. id .. "_NAME", Quality = id - 1 }
    end,
    GetTrinket = function(_, id) return { Name = "#TRINKET_" .. id .. "_NAME" } end,
    GetCard = function(_, id) return { Name = "#CARD_" .. id .. "_NAME" } end,
    GetPillEffect = function(_, id) return { Name = "#PILL_" .. id .. "_NAME" } end,
})

-- Input simulation: set of pressed keys for this frame.
local pressed = {}
clearAwards = 0
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
    FindByType = function() return { obj({ Variant = 10, Position = vec(0, 0),
        Color = { R = 1, G = 1, B = 1, A = 1, RO = 0, GO = 0, BO = 0 } }) } end,
    GetFreeNearPosition = function(p) return p end,
    ExecuteCommand = function() return "" end,
    Explode = function() end,
    WorldToScreen = function(p) return p end,
}
Font = function() return obj({ IsLoaded = function() return true end, GetLineHeight = function() return 10 end,
    GetStringWidthUTF8 = function(_, s) return #s * 5 end }) end
Sprite = function() return obj() end
SFXManager = function() return obj() end

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

-- A rule using every condition and action, so the editor traversal reaches all their pages.
do
    local E = AC.rules
    local r = E.newRule("entity_killed")
    r.filter.mode = "exact"
    r.scope = "chapter"
    for _, id in ipairs(E.conditionOrder) do r.conds[#r.conds + 1] = { id = id, p = E.defaults(E.conditions[id]) } end
    for _, id in ipairs(E.actionOrder) do r.acts[#r.acts + 1] = { id = id, p = E.defaults(E.actions[id]), delay = 1 } end
    AC.save.data.rules.enabled = false -- keep the traversal from firing rules
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
    local visited, pages = {}, 0
    -- Re-open the menu along `path` (page ids or page tables) so every press starts from a known state.
    local function ensure(path)
        AC.menu.setOpen(true, path[1])
        for i = 2, #path do AC.menu.push(path[i]) end
        return AC.menu.stack[#AC.menu.stack]
    end
    local function titleOf(page)
        local title = page.title
        if type(title) == "function" then title = title() end
        return tostring(title)
    end
    local function visit(path, trail)
        local f = ensure(path)
        local id = trail .. "/" .. titleOf(f.page)
        if visited[id] or #path > 8 then return end
        visited[id] = true
        pages = pages + 1
        if os.getenv("SMOKE_PAGES") then print("page", lang, id) end
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
                    if type(target) == "string" and not AC.menu.pages[target] then
                        fail(id .. ": link to unknown page " .. target)
                    elseif target then
                        local sub = {}
                        for k, v in ipairs(path) do sub[k] = v end
                        sub[#sub + 1] = target
                        visit(sub, id)
                    end
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
    visit({ "root" }, lang)
    print(lang .. ": visited " .. pages .. " pages, rules now: " .. #AC.save.data.rules.list)
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
-- Rules engine: every event through the real callbacks, then every condition and action directly.
AC.save.data.rules.enabled = true
for _, preset in ipairs(AC.rulePresets.list) do AC.rulePresets.apply(preset) end
local E = AC.rules
for _, id in ipairs(E.eventOrder) do
    local r = E.newRule(id)
    r.acts = { { id = "counter", p = { name = "hits_" .. id, op = "add", value = 1 }, delay = 0 } }
end
AC.save.write() -- MC_POST_GAME_STARTED reloads settings from the save
fire("MC_POST_GAME_STARTED", false)
fire("MC_POST_NEW_LEVEL")
fire("MC_POST_NEW_ROOM")
for _ = 1, 400 do fire("MC_POST_UPDATE") end
fire("MC_POST_PEFFECT_UPDATE", player)
fire("MC_ENTITY_TAKE_DMG", npc, 1, 0, Any, 0)
d.player.god = false
fire("MC_ENTITY_TAKE_DMG", player, 1, 0, Any, 0)
fire("MC_POST_NPC_DEATH", npc)
npcData.tboiacRuleSeen, npcData.tboiacByRule = nil, nil
playerData.tboiacQueued = nil
fire("MC_POST_PEFFECT_UPDATE", player)
fire("MC_NPC_UPDATE", npc)
fire("MC_POST_PICKUP_UPDATE", pickup)
fire("MC_USE_ITEM", 105, Any, player)
fire("MC_USE_CARD", 1, player)
fire("MC_USE_PILL", 1, player)
fire("MC_POST_FIRE_TEAR", obj({ SpawnerEntity = player, GetData = function() return {} end }))
pressed = { [Keyboard.KEY_K] = true }
fire("MC_POST_RENDER")
pressed = {}
for _, id in ipairs({ "run_start", "new_floor", "room_enter", "timer", "player_hurt", "enemy_hurt",
    "entity_killed", "entity_spawned", "pickup_spawned", "pickup_collected", "item_picked", "active_used",
    "card_used", "pill_used", "tear_fired", "key_press" }) do
    if E.counter("hits_" .. id) < 1 then fail("rule event never fired: " .. id) end
end
-- Param sets: defaults, plus one variant per option of every choice param.
local function variants(def)
    local list = { E.defaults(def) }
    for _, spec in ipairs(def.params) do
        if spec.kind == "choice" then
            local opts = type(spec.options) == "function" and spec.options() or spec.options
            for _, o in ipairs(opts) do
                local p = E.defaults(def)
                p[spec.key] = o[2]
                list[#list + 1] = p
            end
        elseif spec.kind == "toggle" then
            local p = E.defaults(def)
            p[spec.key] = not spec.default
            list[#list + 1] = p
        end
    end
    return list
end
for _, id in ipairs(E.conditionOrder) do
    for _, p in ipairs(variants(E.conditions[id])) do
        local ok, err = pcall(E.checkCondition, { id = id, p = p }, { entity = npc, player = player }, { id = 1 })
        if not ok then fail("condition " .. id .. ": " .. tostring(err)) end
    end
end
for _, id in ipairs(E.actionOrder) do
    for _, p in ipairs(variants(E.actions[id])) do
        for _, ent in ipairs({ npc, pickup }) do
            E.runAction({ id = id, p = p }, { entity = ent, player = player }, { id = 1 })
        end
        E.runAction({ id = id, p = p }, { player = player }, { id = 1 })
    end
end
for _, def in pairs(E.actions) do
    for _, spec in ipairs(def.params) do
        if spec.default == nil then fail("action " .. def.id .. " param " .. spec.key .. " has no default") end
    end
end
-- Loop guard: a rule that re-triggers itself must be capped.
local loop = E.newRule("entity_killed")
loop.acts = { { id = "counter", p = { name = "loop", op = "add", value = 1 } } }
for _ = 1, 500 do E.emit("entity_killed", { entity = npc }) end
if E.counter("loop") > E.MAX_FIRES_PER_FRAME then fail("loop guard did not cap fires") end

-- Item pools.
do
    local pools = AC.save.data.pools
    local get = function(selected)
        for _, f in ipairs(AC.registry.features) do
            if f.id == "pools" then return f.onGetCollectible(AC.mod, selected, 0, true, 123) end
        end
    end
    pools.enabled = true
    if get(2) ~= nil then fail("pools: allowed item was changed") end
    pools.black = { 2 }
    local r = get(2)
    if r == nil or r == 2 then fail("pools: blacklisted item not replaced, got " .. tostring(r)) end
    pools.black, pools.white = {}, { 3 }
    if get(1) ~= 3 then fail("pools: whitelist not applied") end
    pools.white, pools.replace = {}, { { 1, 3 } }
    if get(1) ~= 3 then fail("pools: replacement not applied") end
    pools.replace, pools.qmin = {}, 2
    if get(1) ~= 3 then fail("pools: quality filter not applied") end
    pools.qmin, pools.qmax = 3, 4
    if get(1) ~= nil then fail("pools: impossible filter should keep the item") end
    pools.qmin, pools.qmax = 0, 4
end

-- Freeze: flag restored after a hit clears it, AI skipped while frozen.
do
    local flags, flagsAdded = false, 0
    local frozenData = {}
    local victim = obj({ Position = vec(5, 5), Velocity = vec(1, 1), GetData = function() return frozenData end,
        ToNPC = function(self) return self end, ToProjectile = function() return nil end,
        HasEntityFlags = function(_, f) return f == EntityFlag.FLAG_FREEZE and flags end,
        AddEntityFlags = function() flags = true flagsAdded = flagsAdded + 1 end,
        ClearEntityFlags = function() flags = false end,
        GetSprite = function() return obj({ GetAnimation = function() return "Walk" end, GetFrame = function() return 3 end }) end })
    local real = Isaac.GetRoomEntities
    Isaac.GetRoomEntities = function() return { victim } end
    AC.save.data.time.freezeEnemies = true
    fire("MC_POST_UPDATE")
    flags = false -- a tear hit clears the game's freeze flag
    fire("MC_POST_UPDATE")
    if flagsAdded < 2 then fail("freeze: flag not re-applied after it was cleared") end
    local skipped
    for _, cb in ipairs(callbacks) do
        if cb.id == ModCallbacks.MC_PRE_NPC_UPDATE then skipped = cb.fn(AC.mod, victim) end
    end
    if skipped ~= true then fail("freeze: AI of a frozen enemy is not skipped") end
    AC.save.data.time.freezeEnemies = false
    fire("MC_POST_UPDATE")
    if flags or frozenData.tboiacFreezePos then fail("freeze: not released") end
    Isaac.GetRoomEntities = real
end

-- v0.8: tabs and icon grids.
do
    local M = AC.menu
    AC.menu.setOpen(false)
    frame({ Keyboard.KEY_F2 }); frame()
    if M.stack[1].page.id ~= "quick" then fail("menu should open on the Quick tab") end
    frame({ Keyboard.KEY_TAB }); frame()
    if M.tab ~= 2 or M.stack[1].page.id ~= M.tabs[2].page then fail("Tab did not switch tabs") end
    frame({ Keyboard.KEY_LEFT_SHIFT, Keyboard.KEY_TAB }); frame()
    if M.tab ~= 1 then fail("Shift+Tab did not go back") end
    for _, tab in ipairs(M.tabs) do
        if not M.pages[tab.page] then fail("tab page missing: " .. tab.page) end
    end
    AC.menu.setOpen(false)
    for _, id in ipairs({ "items_grid", "trinkets_grid", "boss_grid", "enemy_grid", "pickups_grid" }) do
        local page = M.pages[id]
        if not page or not page.grid then fail("grid page missing: " .. id) else
            AC.menu.setOpen(true, id)
            local f = M.stack[#M.stack]
            if #f.entries == 0 then fail(id .. ": no entries") end
            local picked = 0
            for _, e in ipairs(f.entries) do
                local orig = e.pick
                e.pick = function(alt) picked = picked + 1 orig(alt) end
            end
            frame({ Keyboard.KEY_RIGHT }); frame()
            frame({ Keyboard.KEY_DOWN }); frame()
            frame({ Keyboard.KEY_ENTER }); frame()
            frame({ Keyboard.KEY_LEFT_SHIFT, Keyboard.KEY_ENTER }); frame()
            if picked ~= 2 then fail(id .. ": Enter/Shift+Enter picked " .. picked .. " times") end
            frame({ Keyboard.KEY_Z }); frame()
            if page.query ~= "z" then fail(id .. ": typing did not filter (" .. page.query .. ")") end
            frame({ Keyboard.KEY_BACKSPACE }); frame()
            if page.query ~= "" then fail(id .. ": backspace did not erase") end
            frame({ Keyboard.KEY_BACKSPACE }); frame()
            if AC.menu.open then fail(id .. ": backspace on empty search should go back/close") end
            if #page.build() < 2 then fail(id .. ": list fallback empty") end
            for _, e in ipairs(f.entries) do e.pick = nil end
        end
    end
    -- descriptions resolve from labels
    if not AC.i18n.desc(AC.i18n.t("god")) then fail("description lookup failed") end
    if not AC.i18n.desc("  " .. AC.i18n.t("m_stats")) then fail("description lookup with indent failed") end
    AC.menu.setOpen(false)
end

-- Phase 5: REPENTOGON - localized names and the ImGui mirror, against a simulated REPENTOGON.
do
    local elements, order = {}, {}
    local function reg(id, e)
        if id ~= "" then
            if elements[id] then fail("imgui: duplicate element id " .. id) end
            elements[id] = e
            order[#order + 1] = id
        end
    end
    local stub = {
        CreateMenu = function(id, label) reg(id, { kind = "menu", label = label }) end,
        CreateWindow = function(id, label) reg(id, { kind = "window", label = label }) end,
        AddElement = function(parent, id, etype, label) reg(id, { kind = "element", label = label, parent = parent }) end,
        LinkWindowToElement = function() end, SetWindowSize = function() end, SetVisible = function() end,
        IsVisible = function() return false end, PushNotification = function(text) fail("imgui notification: " .. text) end,
        ElementExists = function(id) return elements[id] ~= nil end,
        RemoveElement = function(id)
            if not elements[id] then fail("imgui: removing missing element " .. tostring(id)) end
            elements[id] = nil
        end,
        UpdateText = function(id, text) if elements[id] then elements[id].label = text end end,
        AddText = function(parent, text, wrap, id) reg(id or "", { kind = "text", label = text, parent = parent }) end,
        AddButton = function(parent, id, label, cb) reg(id, { kind = "button", label = label, cb = cb, parent = parent }) end,
        AddCheckbox = function(parent, id, label, cb, v) reg(id, { kind = "checkbox", label = label, cb = cb, value = v }) end,
        AddDragFloat = function(parent, id, label, cb, v) reg(id, { kind = "drag", label = label, cb = cb, value = v }) end,
        AddDragInteger = function(parent, id, label, cb, v) reg(id, { kind = "drag", label = label, cb = cb, value = v }) end,
        AddCombobox = function(parent, id, label, cb, opts, sel)
            reg(id, { kind = "combo", label = label, cb = cb, options = opts, value = sel })
        end,
        AddInputText = function(parent, id, label, cb, v) reg(id, { kind = "input", label = label, cb = cb, value = v }) end,
    }
    stub.RemoveMenu, stub.RemoveWindow = stub.RemoveElement, stub.RemoveElement
    rawset(_G, "ImGui", stub)
    rawset(_G, "ImGuiElement", { MenuItem = 2, Separator = 6, SameLine = 11 })
    rawset(_G, "ImGuiNotificationType", { INFO = 0, SUCCESS = 1, WARNING = 2, ERROR = 3 })
    rawset(_G, "EntityConfig", {
        GetEntity = function(t, v) return obj({ GetName = function() return t == 20 and "#MONSTRO" or "" end }) end,
        GetPlayer = function() return obj({ GetName = function() return "#ISAAC_NAME" end }) end,
    })
    local STR = { ["Items:ITEM_1_NAME"] = "Грустный лук", ["Entities:MONSTRO"] = "Монстро",
                  ["Players:ISAAC_NAME"] = "Айзек" }
    Isaac.GetString = function(cat, key) return STR[cat .. ":" .. key] or key end
    AC.hasRepentogon = true
    AC.save.data.ui.imgui, AC.save.data.ui.gameNames = true, true

    if AC.util.collectibleName(1) ~= "Грустный лук" then fail("names: item " .. tostring(AC.util.collectibleName(1))) end
    if AC.util.entityName(20, 0, "x") ~= "Монстро" then fail("names: entity") end
    if AC.util.entityName(99, 0, "Fallback") ~= "Fallback" then fail("names: entity fallback") end
    if AC.util.characterName(0, "x") ~= "Айзек" then fail("names: character") end
    if AC.names.lower("ГРУСТНЫЙ Ёж Abc") ~= "грустный ёж abc" then fail("names: utf8 lower " .. AC.names.lower("ГРУСТНЫЙ Ёж Abc")) end

    AC.imgui.shutdown()
    AC.imgui.init()
    fire("MC_POST_RENDER")
    local function current()
        local list = {}
        for _, id in ipairs(order) do
            local e = elements[id]
            if e and e.parent == "tboiacWindow" then list[#list + 1] = e end
        end
        return list
    end
    if #current() < 5 then fail("imgui: root page not built") end
    local back = "< " .. AC.i18n.t("back")
    local visited, clicks = 0, 0
    local function explore(depth)
        visited = visited + 1
        if depth > 3 or visited > 250 then return end
        -- exercise value widgets on this page
        for _, e in ipairs(current()) do
            if e.kind == "checkbox" then e.cb(not e.value); fire("MC_POST_RENDER"); break end
        end
        for _, e in ipairs(current()) do
            if e.kind == "input" then e.cb("тест"); fire("MC_POST_RENDER"); e.cb(""); fire("MC_POST_RENDER"); break end
        end
        for _, e in ipairs(current()) do
            if e.kind == "combo" and e.options[1] then e.cb(0, e.options[1]); fire("MC_POST_RENDER"); break end
        end
        for _, e in ipairs(current()) do
            if e.kind == "drag" then e.cb(e.value); fire("MC_POST_RENDER"); break end
        end
        -- navigate into sub pages (buttons ending with ">")
        local links = {}
        for _, e in ipairs(current()) do
            if e.kind == "button" and e.label:sub(-1) == ">" and not e.label:find("!!") then links[#links + 1] = e.label end
        end
        for _, label in ipairs(links) do
            for _, e in ipairs(current()) do
                if e.kind == "button" and e.label == label then
                    clicks = clicks + 1
                    e.cb()
                    fire("MC_POST_RENDER")
                    explore(depth + 1)
                    for _, b in ipairs(current()) do
                        if b.kind == "button" and b.label == back then b.cb() fire("MC_POST_RENDER") break end
                    end
                    break
                end
            end
        end
    end
    if os.getenv("SMOKE_IMGUI") then
        for _, e in ipairs(current()) do print("root", e.kind, e.label) end
    end
    explore(0)
    print("imgui: visited " .. visited .. " pages via " .. clicks .. " clicks")
    if clicks < 20 then fail("imgui: navigation did not work") end
    AC.imgui.shutdown()
    if elements.tboiacWindow or elements.tboiacMenu then fail("imgui: shutdown left the window") end
    AC.hasRepentogon = false
    Isaac.GetString = nil
end

-- Phase 4: studio.
do
    local studio
    for _, f in ipairs(AC.registry.features) do if f.id == "studio" then studio = f end end
    local E = AC.rules
    -- profile round trip, including a save/load through JSON
    AC.save.data.player.god = true
    studio.saveProfile(3, "test")
    AC.save.write()
    AC.save.load()
    AC.save.data.player.god = false
    local prof = studio.getProfile(3)
    if not prof or prof.name ~= "test" then fail("profiles: slot 3 lost after save/load") end
    studio.loadProfile(prof)
    if AC.save.data.player.god ~= true then fail("profiles: load did not restore settings") end
    AC.save.data.player.god = false
    -- stopwatch counts updates only while running
    studio.stopwatch.frames, studio.stopwatch.running = 0, true
    for _ = 1, 30 do fire("MC_POST_UPDATE") end
    studio.stopwatch.running = false
    fire("MC_POST_UPDATE")
    if studio.stopwatch.frames ~= 30 then fail("stopwatch: " .. studio.stopwatch.frames) end
    -- clean frame suppresses toasts
    AC.render.toasts = {}
    AC.save.data.studio.clean = true
    AC.render.toast("x")
    if #AC.render.toasts ~= 0 then fail("clean frame did not hide toasts") end
    AC.save.data.studio.clean = false
    -- toggle_option and run_rule
    E.runAction({ id = "toggle_option", p = { option = "god", mode = "on" } }, { player = player }, { id = 1 })
    if AC.save.data.player.god ~= true then fail("toggle_option did not switch god mode") end
    AC.save.data.player.god = false
    AC.save.data.rules.enabled = true
    local scen = E.newRule("manual")
    scen.acts = { { id = "counter", p = { name = "scen", op = "add", value = 1 } } }
    E.setCounter("scen", 0)
    E.runAction({ id = "run_rule", p = { rule = scen.id } }, { player = player }, { id = 0 })
    if E.counter("scen") ~= 1 then fail("run_rule did not run the scenario") end
end

-- Phase 3: arena waves.
do
    local waves
    for _, f in ipairs(AC.registry.features) do if f.id == "waves" then waves = f end end
    local E = AC.rules
    E.setCounter("ws", 0)
    E.setCounter("wc", 0)
    local r1 = E.newRule("wave_start"); r1.acts = { { id = "counter", p = { name = "ws", op = "add", value = 1 } } }
    local r2 = E.newRule("wave_clear"); r2.acts = { { id = "counter", p = { name = "wc", op = "add", value = 1 } } }
    local r3 = E.newRule("waves_done"); r3.acts = { { id = "counter", p = { name = "wd", op = "add", value = 1 } } }
    local ws = AC.save.data.waves
    ws.total, ws.pause, ws.mode, ws.endless = 4, 1, "clear", true
    AC.save.data.rules.enabled = true -- the toggle_option variants above may have switched rules off
    fire("MC_POST_UPDATE") -- new frame: earlier checks may have used up this frame's fire budget
    waves.start()
    if waves.state.wave ~= 1 or waves.state.state ~= "fighting" then fail("waves: did not start") end
    local realEntities = Isaac.GetRoomEntities
    Isaac.GetRoomEntities = function() return {} end -- every wave is instantly cleared
    for _ = 1, 400 do fire("MC_POST_UPDATE") end
    fire("MC_POST_RENDER")
    Isaac.GetRoomEntities = realEntities
    if waves.state.state ~= "idle" then fail("waves: did not finish, state " .. waves.state.state) end
    if waves.state.wave ~= 4 then fail("waves: expected 4 waves, got " .. waves.state.wave) end
    if E.counter("ws") ~= 4 or E.counter("wc") ~= 4 or E.counter("wd") ~= 1 then
        fail(string.format("waves: rule events %d/%d/%d", E.counter("ws"), E.counter("wc"), E.counter("wd")))
    end
    ws.mode, ws.interval = "timer", 5
    waves.start()
    for _ = 1, 400 do fire("MC_POST_UPDATE") end -- timer spawns next waves while enemies live
    if waves.state.wave < 2 then fail("waves: timer mode did not advance") end
    waves.stop(false)
end

-- Phase 3: reward rules.
do
    local drops
    for _, f in ipairs(AC.registry.features) do if f.id == "drops" then drops = f end end
    local ds = AC.save.data.drops
    ds.enabled, ds.clearMult, ds.clearBonus, ds.bossItems = true, 3, "chest", 2
    clearAwards = 0
    if drops.onClearAward(AC.mod, Any, vec(0, 0)) ~= nil then fail("drops: award cancelled unexpectedly") end
    if clearAwards ~= 2 then fail("drops: expected 2 extra awards, got " .. tostring(clearAwards)) end
    ds.noClearAward = true
    if drops.onClearAward(AC.mod, Any, vec(0, 0)) ~= true then fail("drops: award not cancelled") end
    local removed = false
    local coinData = {}
    local coin = obj({ Variant = 20, SubType = 1, Price = 0, Position = vec(0, 0),
        GetData = function() return coinData end, Remove = function() removed = true end })
    ds.noPickups = true
    fire("MC_POST_PICKUP_INIT", coin)
    fire("MC_POST_PICKUP_UPDATE", coin)
    if not removed then fail("drops: pickup not removed") end
    AC.save.data.drops = AC.util.copy(AC.save.defaults.drops)
end

-- Phase 2c: movement behaviours move entities; screen text formats counters.
do
    local E = AC.rules
    for _, kind in ipairs({ "orbit", "patrol", "attract", "immobile", "spin" }) do
        npc.Position = vec(300, 300)
        E.runAction({ id = "behaviour", p = { target = "trigger", kind = kind, speed = 5, radius2 = 50,
            shape = "square", seconds = 0 } }, { entity = npc, player = player }, { id = 1 })
        if not npcData.tboiacMove then fail("behaviour " .. kind .. " not applied") end
        for _ = 1, 5 do fire("MC_POST_UPDATE") end
        if kind == "orbit" and npc.Position.X == 300 and npc.Position.Y == 300 then fail("orbit did not move") end
    end
    E.runAction({ id = "behaviour_clear", p = { target = "trigger" } }, { entity = npc, player = player }, { id = 1 })
    if npcData.tboiacMove then fail("behaviour not cleared") end
    E.setCounter("kills", 7)
    if AC.ruleEffects.format("k={kills} f={flag:x}") ~= "k=7 f=" .. AC.i18n.t("off") then
        fail("screen text formatting: " .. AC.ruleEffects.format("k={kills} f={flag:x}"))
    end
    E.runAction({ id = "screen_text", p = E.defaults(E.actions.screen_text) }, { player = player }, { id = 1 })
    E.runAction({ id = "big_text", p = E.defaults(E.actions.big_text) }, { player = player }, { id = 1 })
    fire("MC_POST_RENDER")
    if not AC.ruleEffects.texts.a then fail("screen text slot missing") end
    E.runAction({ id = "clear_text", p = { slot = "" } }, { player = player }, { id = 1 })
    if next(AC.ruleEffects.texts) then fail("clear_text did not clear") end
end

-- Formations and targets: a clone in circle formation, labels and lists round-trip.
do
    local E = AC.rules
    E.setLabel(npc, "boss", true)
    if not E.hasLabel(npc, "boss") then fail("labels: set/has") end
    E.addToList("group", npc)
    E.addToList("group", npc)
    if #E.listEntities("group") ~= 1 then fail("lists: duplicate add") end
    if not E.matchFilter({ mode = "label", name = "boss" }, npc) then fail("filter: label") end
    if not E.matchFilter({ mode = "list", name = "group" }, npc) then fail("filter: list") end
    E.removeFromList("group", npc)
    if E.inList("group", npc) then fail("lists: remove") end
    local ctx = { player = player, entity = npc }
    E.runAction({ id = "stop", p = { chance = 100 } }, ctx, { id = 1 })
    if not ctx.stop then fail("stop action did not stop the chain") end
end

AC.registry.resetAll()
fire("MC_POST_UPDATE")
fire("MC_PRE_GAME_EXIT", true)
assert(saved, "settings were not saved")
AC.save.load()

for _, line in ipairs(debugLog) do
    if line:find("error") or line:find("failed") then fail("log: " .. line) end
end

if #errors > 0 then
    for _, e in ipairs(errors) do print("FAIL: " .. e) end
    os.exit(1)
end
print("smoke ok")
