-- Param specs for rule events, conditions and actions, plus shared option lists.
-- Option labels are i18n keys or plain names (see i18n.label).
local AC = TBOIAC

local P = {}

function P.number(key, label, default, min, max, step)
    return { kind = "number", key = key, label = label, default = default, min = min, max = max, step = step or 1 }
end

function P.choice(key, label, default, options)
    return { kind = "choice", key = key, label = label, default = default, options = options }
end

function P.toggle(key, label, default)
    return { kind = "toggle", key = key, label = label, default = default or false }
end

function P.text(key, label, default)
    return { kind = "text", key = key, label = label, default = default or "" }
end

-- Id from a searchable catalog. catalog = "collectible"|"trinket"|"card"|"pill".
-- `zero` (i18n key) names the meaning of 0, e.g. "any" or "random"; nil forbids 0.
function P.catalog(key, label, default, catalog, zero)
    return { kind = "catalog", key = key, label = label, default = default, catalog = catalog, zero = zero }
end

-- Entity as a "type.variant.subtype" string, pickable from boss/enemy lists.
function P.entity(key, label, default)
    return { kind = "entity", key = key, label = label, default = default or "10.0.0" }
end

-- Parses "type.variant.subtype" (missing parts = 0).
function P.parseEntity(s)
    local a, b, c = tostring(s):match("^(%d+)%.?(%d*)%.?(%d*)$")
    if not a then return 10, 0, 0 end
    return tonumber(a), tonumber(b) or 0, tonumber(c) or 0
end

P.COMPARE = { { "op_gt", "gt" }, { "op_lt", "lt" }, { "op_ge", "ge" }, { "op_le", "le" }, { "op_eq", "eq" } }

P.POSITION = {
    { "pos_player", "player" }, { "pos_entity", "entity" }, { "pos_random", "random" }, { "pos_center", "center" },
}

P.STATS = {
    { "st_damage", "damage" }, { "st_tears", "tears" }, { "st_speed", "speed" },
    { "st_range", "range" }, { "st_shotspeed", "shotspeed" }, { "st_luck", "luck" },
}

P.RESOURCES = { { "coins", "coins" }, { "bombs", "bombs" }, { "keys", "keys" } }

P.HEARTS = {
    { "h_container", "container" }, { "h_red", "red" }, { "h_soul", "soul" }, { "h_black", "black" },
    { "h_bone", "bone" }, { "h_golden", "golden" }, { "h_eternal", "eternal" }, { "h_rotten", "rotten" },
    { "h_broken", "broken" },
}

P.COLORS = {
    { "col_red", "red" }, { "col_green", "green" }, { "col_blue", "blue" }, { "col_gold", "gold" },
    { "col_black", "black" }, { "col_white", "white" }, { "col_ghost", "ghost" }, { "col_reset", "reset" },
}

-- Who an entity action applies to. `name` names a label or list, `radius` is for "radius".
P.TARGETS = {
    { "tg_trigger", "trigger" }, { "tg_nearest", "nearest" }, { "tg_radius", "radius" },
    { "tg_enemies", "enemies" }, { "tg_pickups", "pickups" }, { "tg_items", "items" },
    { "tg_label", "label" }, { "tg_list", "list" },
}

function P.target()
    return {
        P.choice("target", "target", "trigger", P.TARGETS),
        P.text("name", "label_or_list", "a"),
        P.number("radius", "radius_px", 120, 10, 1000, 10),
    }
end

P.FORMATIONS = {
    { "fm_random", "random" }, { "fm_circle", "circle" }, { "fm_line_h", "line_h" }, { "fm_line_v", "line_v" },
    { "fm_cross", "cross" }, { "fm_diag", "diag" }, { "fm_grid", "grid" },
}

function P.formation()
    return {
        P.choice("formation", "formation", "random", P.FORMATIONS),
        P.number("spacing", "spacing_px", 50, 10, 300, 5),
    }
end

-- Concatenate param lists.
function P.join(...)
    local out = {}
    for _, list in ipairs({ ... }) do
        for _, spec in ipairs(list) do out[#out + 1] = spec end
    end
    return out
end

P.TIME_MODES = { { "time_normal", 0 }, { "time_slow", 1 }, { "time_fast", 2 } }

function P.roomTypes(withAny)
    return function()
        local list = {}
        if withAny then list[1] = { "any", -1 } end
        for _, r in ipairs(AC.data.ROOM_TYPES) do list[#list + 1] = { r[1], r[2] } end
        return list
    end
end

function P.curses()
    local list = {}
    for _, c in ipairs(AC.data.CURSES) do list[#list + 1] = { c[1], c[2] } end
    return list
end

function P.characters()
    local list = {}
    for _, c in ipairs(AC.data.CHARACTERS) do list[#list + 1] = { c[2], c[1] } end
    return list
end

-- "SEED_BIG_HEAD" -> "Big Head"
local function prettyEnum(name, prefix)
    name = name:gsub("^" .. prefix, ""):gsub("_", " "):lower()
    return (name:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

-- Easter-egg seed effects useful for videos; names missing in this game version are skipped.
local SEED_NAMES = {
    "SEED_BIG_HEAD", "SEED_SMALL_HEAD", "SEED_NO_FACE", "SEED_BLACK_ISAAC", "SEED_INVISIBLE_ISAAC",
    "SEED_INVISIBLE_ENEMIES", "SEED_CAMO_ISAAC", "SEED_CAMO_ENEMIES", "SEED_CAMO_PICKUPS",
    "SEED_CAMO_EVERYTHING", "SEED_FART_SOUNDS", "SEED_OLD_TV", "SEED_DYSLEXIA", "SEED_NO_HUD",
    "SEED_PICKUPS_SLIDE", "SEED_CONTROLS_REVERSED", "SEED_ALL_CHAMPIONS", "SEED_ALWAYS_CHARMED",
    "SEED_ALWAYS_CONFUSED", "SEED_ALWAYS_AFRAID", "SEED_EXTRA_BLOOD", "SEED_POOP_TRAIL", "SEED_PACIFIST",
    "SEED_DAMAGE_WHEN_STOPPED", "SEED_ENEMIES_RESPAWN", "SEED_ITEMS_COST_MONEY", "SEED_GLOWING_TEARS",
    "SEED_SLOW_MUSIC", "SEED_FAST_MUSIC", "SEED_ICE_PHYSICS", "SEED_KAPPA", "SEED_CHRISTMAS", "SEED_KIDS_MODE",
    "SEED_SHOOT_IN_MOVEMENT_DIRECTION", "SEED_SHOOT_OPPOSITE_MOVEMENT_DIRECTION", "SEED_SUPER_HOT",
    "SEED_RETRO_VISION", "SEED_G_FUEL", "SEED_MOVEMENT_PITCH", "SEED_HEALTH_PITCH",
    "SEED_ISAAC_TAKES_HIGH_DAMAGE", "SEED_PERMANENT_CURSE_DARKNESS",
}

function P.seeds()
    local present = {}
    for name, v in pairs(SeedEffect) do present[name] = v end
    local list = {}
    for _, name in ipairs(SEED_NAMES) do
        if present[name] then list[#list + 1] = { prettyEnum(name, "SEED_"), present[name] } end
    end
    return list
end

-- All music tracks of this game version, sorted by id.
function P.music()
    local list = {}
    for name, v in pairs(Music) do
        if type(v) == "number" and name:match("^MUSIC_") and name ~= "MUSIC_NULL" then
            list[#list + 1] = { prettyEnum(name, "MUSIC_"), v }
        end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    return list
end

-- Keys a rule can be bound to (letters, digits, F-keys, numpad).
function P.keys()
    local list = {}
    for k = Keyboard.KEY_A, Keyboard.KEY_Z do list[#list + 1] = { string.char(k), k } end
    for k = Keyboard.KEY_0, Keyboard.KEY_9 do list[#list + 1] = { string.char(k), k } end
    for i = 1, 12 do
        local k = Keyboard["KEY_F" .. i]
        if k then list[#list + 1] = { "F" .. i, k } end
    end
    for k = Keyboard.KEY_KP_0, Keyboard.KEY_KP_9 do list[#list + 1] = { "Num" .. (k - Keyboard.KEY_KP_0), k } end
    return list
end

return P
