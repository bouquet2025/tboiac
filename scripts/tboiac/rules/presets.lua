-- Built-in rule presets. Loading a preset appends copies of its rules.
-- Rule templates omit ids; missing params are filled from definitions when the rule runs.
local presets = {}

local function rule(name, event, eventP, acts, extra)
    local r = {
        name = name, enabled = true, scope = "always", chapter = 1,
        event = { id = event, p = eventP or {} },
        filter = { mode = "any", t = 10, v = -1, s = -1 },
        logic = "and", conds = {}, acts = acts,
    }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

local function act(id, p, delay) return { id = id, p = p or {}, delay = delay or 0 } end
local function cond(id, p, neg) return { id = id, p = p or {}, neg = neg or false } end

presets.list = {
    { name = "pr_every_item", rules = {
        rule("prr_every_item_is_brimstone", "pickup_spawned", nil, { act("set_item", { id = 118 }) },
            { filter = { mode = "exact", t = 5, v = 100, s = -1 } }),
    } },
    { name = "pr_boss_rooms", rules = {
        rule("prr_boss_in_every_room", "room_enter", { roomType = 1, visit = "first" },
            { act("spawn_random", { kind = "boss", count = 1 }) }),
    } },
    { name = "pr_kill_damage", rules = {
        rule("prr_kills_give_damage", "entity_killed", nil, { act("stat", { stat = "damage", amount = 0.05 }) },
            { filter = { mode = "enemy", t = 10, v = -1, s = -1 } }),
    } },
    { name = "pr_timed_items", rules = {
        rule("prr_item_every_30s", "timer", { seconds = 30 },
            { act("give_item", { id = 0 }), act("show_text", { text = "free item!", style = "toast" }) }),
    } },
    { name = "pr_hurt_teleport", rules = {
        rule("prr_hurt_teleport", "player_hurt", nil, { act("teleport", { to = "random" }, 0.5) }),
    } },
    { name = "pr_explosive_enemies", rules = {
        rule("prr_enemies_explode", "entity_killed", nil, { act("explode", { pos = "entity", damage = 10 }) },
            { filter = { mode = "enemy", t = 10, v = -1, s = -1 } }),
    } },
    { name = "pr_clones", rules = {
        rule("prr_enemies_may_clone", "entity_spawned", nil, { act("entity_clone", { count = 1 }) },
            { filter = { mode = "enemy", t = 10, v = -1, s = -1 }, conds = { cond("chance", { value = 50 }) } }),
    } },
    { name = "pr_giants", rules = {
        rule("prr_giant_enemies", "entity_spawned", nil,
            { act("entity_scale", { scale = 2 }), act("entity_color", { color = "red" }) },
            { filter = { mode = "enemy", t = 10, v = -1, s = -1 } }),
    } },
    { name = "pr_one_hit", rules = {
        rule("prr_one_hit_death", "player_hurt", nil, { act("kill_player") }),
    } },
    { name = "pr_coin_rain", rules = {
        rule("prr_coins_for_clearing", "room_clear", { roomType = -1 },
            { act("spawn_pickup", { variant = 20, subtype = 1, count = 5, pos = "center" }) }),
    } },
    { name = "pr_hotkeys", rules = {
        rule("prr_k_random_boss", "key_press", { key = Keyboard.KEY_K }, { act("spawn_random", { kind = "boss" }) }),
        rule("prr_l_random_item", "key_press", { key = Keyboard.KEY_L }, { act("spawn_item", { id = 0 }) }),
        rule("prr_o_kill_enemies", "key_press", { key = Keyboard.KEY_O }, { act("kill_enemies") }),
    } },
    { name = "pr_slow_bosses", rules = {
        rule("prr_slow_in_boss_room", "room_enter", { roomType = RoomType.ROOM_BOSS, visit = "any" },
            { act("time_mode", { mode = 1, seconds = 0 }) }),
        rule("prr_normal_after_boss", "room_clear", { roomType = RoomType.ROOM_BOSS },
            { act("time_mode", { mode = 0, seconds = 0 }) }),
        rule("prr_normal_elsewhere", "room_enter", { roomType = -1, visit = "any" },
            { act("time_mode", { mode = 0, seconds = 0 }) },
            { conds = { cond("room_type", { roomType = RoomType.ROOM_BOSS }, true) } }),
    } },
    { name = "pr_counter_demo", rules = {
        rule("prr_count_kills", "entity_killed", nil, { act("counter", { name = "kills", op = "add", value = 1 }) },
            { filter = { mode = "enemy", t = 10, v = -1, s = -1 } }),
        rule("prr_every_25_kills_item", "entity_killed", nil,
            { act("counter", { name = "kills", op = "set", value = 0 }), act("spawn_item", { id = 0 }) },
            { filter = { mode = "enemy", t = 10, v = -1, s = -1 },
              conds = { cond("counter", { name = "kills", op = "ge", value = 25 }) } }),
    } },
}

-- Append a preset's rules to the rule list (names are translated at load time).
function presets.apply(preset)
    local AC = TBOIAC
    for _, r in ipairs(preset.rules) do
        local copy = AC.rules.addRule(r)
        copy.name = AC.i18n.label(r.name)
    end
end

return presets
