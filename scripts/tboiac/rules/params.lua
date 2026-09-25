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
