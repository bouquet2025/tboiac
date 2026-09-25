-- Rules engine: a rule is "event -> conditions -> actions".
--
-- Rule (stored in save.data.rules.list):
--   { id, name, enabled, scope = "always"|"run"|"chapter", chapter,
--     event  = { id, p = {params} },
--     filter = { mode = "any"|"enemy"|"boss"|"player"|"pickup"|"exact", t, v, s },
--     logic  = "and"|"or",
--     conds  = { { id, p, neg }, ... },
--     acts   = { { id, p, delay }, ... } }
--
-- Definitions register themselves through engine.defineEvent/Condition/Action. Each definition
-- has `id`, `label` (i18n key) and `params` (list of param specs, see rules/editor.lua).
-- ctx passed to conditions/actions: { entity = Entity?, player = EntityPlayer, value = any }
local AC = TBOIAC
local util = AC.util

local engine = {
    events = {}, eventOrder = {},
    conditions = {}, conditionOrder = {},
    actions = {}, actionOrder = {},
    queue = {},          -- delayed actions { at = frame, act, ctx, rule }
    room = { fired = {} },
    last = {},           -- rule key -> engine frame of last fire (not saved)
    frame = 0,
    firesThisFrame = 0,
    depth = 0,
}

engine.MAX_FIRES_PER_FRAME = 200
engine.MAX_DEPTH = 6

local function define(store, order, def)
    def.params = def.params or {}
    store[def.id] = def
    order[#order + 1] = def.id
    return def
end

function engine.defineEvent(def) return define(engine.events, engine.eventOrder, def) end
function engine.defineCondition(def) return define(engine.conditions, engine.conditionOrder, def) end
function engine.defineAction(def) return define(engine.actions, engine.actionOrder, def) end

function engine.S() return AC.save.data.rules end
function engine.run() return AC.save.data.run end

function engine.defaults(def)
    local p = {}
    for _, spec in ipairs(def.params) do p[spec.key] = util.copy(spec.default) end
    return p
end

-- Fill params missing in saved data (definitions may gain params in newer versions).
local function withDefaults(def, p)
    p = p or {}
    for _, spec in ipairs(def.params) do
        if p[spec.key] == nil then p[spec.key] = util.copy(spec.default) end
    end
    return p
end

local function key(rule) return "r" .. rule.id end

-- Rules -------------------------------------------------------------------------------------

function engine.newRule(eventId)
    local S = engine.S()
    local id = S.nextId
    S.nextId = id + 1
    local ev = engine.events[eventId or "room_enter"]
    local rule = {
        id = id, name = AC.i18n.t("rule_default_name", id), enabled = true,
        scope = "always", chapter = 1,
        event = { id = ev.id, p = engine.defaults(ev) },
        filter = { mode = "any", t = 10, v = -1, s = -1 },
        logic = "and", conds = {}, acts = {},
    }
    table.insert(S.list, rule)
    return rule
end

function engine.addRule(rule)
    local S = engine.S()
    rule = util.copy(rule)
    rule.id = S.nextId
    S.nextId = S.nextId + 1
    table.insert(S.list, rule)
    return rule
end

function engine.removeRule(rule)
    local list = engine.S().list
    for i = #list, 1, -1 do
        if list[i] == rule then table.remove(list, i) end
    end
end

function engine.findRule(id)
    for _, r in ipairs(engine.S().list) do
        if r.id == id then return r end
    end
    return nil
end

local function inScope(rule)
    if rule.scope == "chapter" then
        local stage = AC.game:GetLevel():GetStage()
        return math.ceil(stage / 2) == rule.chapter
    end
    return true
end

-- Entity filter ------------------------------------------------------------------------------

function engine.matchFilter(filter, entity)
    local mode = filter and filter.mode or "any"
    if mode == "any" then return true end
    if not entity then return false end
    if mode == "player" then return entity.Type == EntityType.ENTITY_PLAYER end
    if mode == "pickup" then return entity.Type == EntityType.ENTITY_PICKUP end
    local npc = entity:ToNPC()
    if mode == "enemy" then return npc ~= nil and npc:IsVulnerableEnemy() and not npc:IsBoss() end
    if mode == "boss" then return npc ~= nil and npc:IsBoss() end
    if mode == "exact" then
        return entity.Type == filter.t
            and (filter.v < 0 or entity.Variant == filter.v)
            and (filter.s < 0 or entity.SubType == filter.s)
    end
    return false
end

-- Conditions ---------------------------------------------------------------------------------

function engine.checkCondition(cond, ctx, rule)
    local def = engine.conditions[cond.id]
    if not def then return false end
    local ok = def.check(withDefaults(def, cond.p), ctx, rule) and true or false
    if cond.neg then ok = not ok end
    return ok
end

local function conditionsPass(rule, ctx)
    local conds = rule.conds or {}
    if #conds == 0 then return true end
    local any = rule.logic == "or"
    for _, c in ipairs(conds) do
        local ok = engine.checkCondition(c, ctx, rule)
        if any and ok then return true end
        if not any and not ok then return false end
    end
    return not any
end

-- Actions ------------------------------------------------------------------------------------

function engine.runAction(act, ctx, rule)
    local def = engine.actions[act.id]
    if not def then return end
    if ctx.entity and not ctx.entity:Exists() then ctx.entity = nil end
    local ok, err = pcall(def.run, withDefaults(def, act.p), ctx, rule)
    if not ok then
        util.log("rule " .. tostring(rule and rule.id) .. " action " .. act.id .. " failed: " .. tostring(err))
    end
end

local function fire(rule, ctx)
    local run = engine.run()
    local k = key(rule)
    run.fired[k] = (run.fired[k] or 0) + 1
    engine.room.fired[k] = (engine.room.fired[k] or 0) + 1
    engine.last[k] = engine.frame
    local delay = 0
    for _, act in ipairs(rule.acts or {}) do
        delay = delay + math.max(0, act.delay or 0)
        if delay > 0 then
            table.insert(engine.queue, { at = engine.frame + math.floor(delay * 30), act = act, ctx = ctx, rule = rule })
        else
            engine.runAction(act, ctx, rule)
        end
    end
end

-- Evaluate one rule against an event context. `force` skips event matching (test button).
function engine.try(rule, ctx, force)
    if not force then
        if not rule.enabled or not inScope(rule) then return false end
        local ev = engine.events[rule.event.id]
        if not ev then return false end
        if ev.match and not ev.match(withDefaults(ev, rule.event.p), ctx, rule) then return false end
        if ev.entity and not engine.matchFilter(rule.filter, ctx.entity) then return false end
    end
    if engine.firesThisFrame >= engine.MAX_FIRES_PER_FRAME then
        if not engine.warned then
            engine.warned = true
            AC.render.toast(AC.i18n.t("rules_loop_warning"), 180)
        end
        return false
    end
    local run = engine.run()
    local k = key(rule)
    run.matches[k] = (run.matches[k] or 0) + 1
    if not conditionsPass(rule, ctx) then return false end
    engine.firesThisFrame = engine.firesThisFrame + 1
    fire(rule, ctx)
    return true
end

-- Run a rule's actions right now, ignoring event and conditions (editor "test" button).
function engine.test(rule)
    fire(rule, { player = util.firstTarget() })
end

-- Emit an event to every rule listening to it.
function engine.emit(eventId, ctx)
    local S = engine.S()
    if not S.enabled or #S.list == 0 then return end
    if engine.depth >= engine.MAX_DEPTH then return end
    ctx = ctx or {}
    ctx.player = ctx.player or util.firstTarget()
    engine.depth = engine.depth + 1
    for _, rule in ipairs(S.list) do
        if rule.event.id == eventId then
            -- each rule gets its own ctx copy so delayed actions keep their entity
            engine.try(rule, { entity = ctx.entity, player = ctx.player, value = ctx.value })
        end
    end
    engine.depth = engine.depth - 1
end

-- Per-frame bookkeeping, called from MC_POST_UPDATE.
function engine.update()
    engine.frame = engine.frame + 1
    engine.firesThisFrame = 0
    engine.warned = false
    local due = {}
    for i = #engine.queue, 1, -1 do
        local q = engine.queue[i]
        if q.at <= engine.frame then
            table.remove(engine.queue, i)
            table.insert(due, 1, q)
        end
    end
    for _, q in ipairs(due) do engine.runAction(q.act, q.ctx, q.rule) end
end

function engine.onNewRoom()
    engine.room = { fired = {} }
end

-- New run (not continued): reset run state and drop "this run only" rules.
function engine.onNewRun()
    AC.save.data.run = util.copy(AC.save.defaults.run)
    engine.queue = {}
    local list = engine.S().list
    for i = #list, 1, -1 do
        if list[i].scope == "run" then table.remove(list, i) end
    end
end

-- Named variables (flags and counters) shared by all rules.
function engine.flag(name) return engine.run().flags[name] == true end
function engine.setFlag(name, v) engine.run().flags[name] = v or nil end
function engine.counter(name) return engine.run().counters[name] or 0 end
function engine.setCounter(name, v) engine.run().counters[name] = v end

function engine.compare(a, op, b)
    if op == "gt" then return a > b end
    if op == "lt" then return a < b end
    if op == "ge" then return a >= b end
    if op == "le" then return a <= b end
    return a == b
end

return engine
