-- Rule events and the game callbacks that emit them.
local AC = TBOIAC
local engine, P, util = AC.rules, AC.ruleParams, AC.util

local function roomMatches(p)
    local room = AC.game:GetRoom()
    if p.roomType ~= -1 and room:GetType() ~= p.roomType then return false end
    if p.visit == "first" then return room:IsFirstVisit() end
    if p.visit == "revisit" then return not room:IsFirstVisit() end
    return true
end

local VISIT = { { "any", "any" }, { "visit_first", "first" }, { "visit_revisit", "revisit" } }

local function idMatches(p, ctx) return p.id == 0 or p.id == ctx.value end

engine.defineEvent({ id = "run_start", label = "ev_run_start" })
engine.defineEvent({ id = "new_floor", label = "ev_new_floor" })
engine.defineEvent({
    id = "room_enter", label = "ev_room_enter",
    params = { P.choice("roomType", "room_type", -1, P.roomTypes(true)), P.choice("visit", "visit", "any", VISIT) },
    match = roomMatches,
})
engine.defineEvent({
    id = "room_clear", label = "ev_room_clear",
    params = { P.choice("roomType", "room_type", -1, P.roomTypes(true)) },
    match = function(p) return p.roomType == -1 or AC.game:GetRoom():GetType() == p.roomType end,
})
engine.defineEvent({
    id = "timer", label = "ev_timer",
    params = { P.number("seconds", "seconds", 10, 0.1, 3600, 0.5) },
    -- emitted per rule from the update loop below
})
engine.defineEvent({
    id = "key_press", label = "ev_key_press",
    params = { P.choice("key", "key", Keyboard.KEY_K, P.keys) },
    match = function(p, ctx) return p.key == ctx.value end,
})
engine.defineEvent({ id = "player_hurt", label = "ev_player_hurt" })
engine.defineEvent({ id = "player_death", label = "ev_player_death" })
engine.defineEvent({ id = "enemy_hurt", label = "ev_enemy_hurt", entity = true })
engine.defineEvent({ id = "entity_killed", label = "ev_entity_killed", entity = true })
engine.defineEvent({ id = "entity_spawned", label = "ev_entity_spawned", entity = true })
engine.defineEvent({ id = "pickup_spawned", label = "ev_pickup_spawned", entity = true })
engine.defineEvent({ id = "pickup_collected", label = "ev_pickup_collected", entity = true })
engine.defineEvent({
    id = "item_picked", label = "ev_item_picked",
    params = { P.catalog("id", "item", 0, "collectible", "any") }, match = idMatches,
})
engine.defineEvent({
    id = "active_used", label = "ev_active_used",
    params = { P.catalog("id", "item", 0, "collectible", "any") }, match = idMatches,
})
engine.defineEvent({
    id = "card_used", label = "ev_card_used",
    params = { P.catalog("id", "card", 0, "card", "any") }, match = idMatches,
})
engine.defineEvent({
    id = "pill_used", label = "ev_pill_used",
    params = { P.catalog("id", "pill", 0, "pill", "any") }, match = idMatches,
})
engine.defineEvent({ id = "tear_fired", label = "ev_tear_fired" })

-- Callback wiring -----------------------------------------------------------------------------

local events = {}
local roomWasClear = true

-- Entities spawned by rule actions are marked so "spawned" rules do not chain forever.
function events.markSpawned(e)
    if e then e:GetData().tboiacByRule = true end
    return e
end

local function fresh(e, flag)
    local data = e:GetData()
    if data[flag] then return false end
    data[flag] = true
    return not data.tboiacByRule
end

local function onUpdate()
    engine.update()
    local room = AC.game:GetRoom()
    local clear = room:IsClear()
    if clear and not roomWasClear then engine.emit("room_clear") end
    roomWasClear = clear

    local S = engine.S()
    if S.enabled then
        for _, rule in ipairs(S.list) do
            if rule.event.id == "timer" and rule.enabled then
                local frames = math.max(3, math.floor((rule.event.p.seconds or 10) * 30))
                if engine.frame % frames == 0 then
                    engine.try(rule, { player = util.firstTarget() })
                end
            end
        end
    end
end

local function onRender()
    if AC.menu.open or AC.input.textTarget then return end
    local S = engine.S()
    if not S.enabled then return end
    local seen = {}
    for _, rule in ipairs(S.list) do
        local k = rule.event.id == "key_press" and rule.event.p.key
        if k and not seen[k] then
            seen[k] = true
            if AC.input.keyEdge(k) then engine.emit("key_press", { value = k }) end
        end
    end
end

local function onPlayerUpdate(_, player)
    local data = player:GetData()
    -- Item pickups: the item sits in QueuedItem while being held up.
    local queued = player.QueuedItem.Item
    if queued and queued:IsCollectible() then
        if data.tboiacQueued ~= queued.ID then
            data.tboiacQueued = queued.ID
            engine.emit("item_picked", { player = player, entity = player, value = queued.ID })
        end
    else
        data.tboiacQueued = nil
    end
    local dead = player:IsDead()
    if dead and not data.tboiacDead then engine.emit("player_death", { player = player, entity = player }) end
    data.tboiacDead = dead
end

local function onDamage(_, entity, amount)
    local player = entity:ToPlayer()
    if player then
        engine.emit("player_hurt", { player = player, entity = player, value = amount })
    elseif entity:IsVulnerableEnemy() then
        engine.emit("enemy_hurt", { entity = entity, value = amount })
    end
    return nil
end

local function onNpcUpdate(_, npc)
    if fresh(npc, "tboiacRuleSeen") then engine.emit("entity_spawned", { entity = npc }) end
end

local function onPickupUpdate(_, pickup)
    if fresh(pickup, "tboiacRuleSeen") then engine.emit("pickup_spawned", { entity = pickup }) end
    local sprite = pickup:GetSprite()
    if sprite:IsPlaying("Collect") and not pickup:GetData().tboiacCollected then
        pickup:GetData().tboiacCollected = true
        engine.emit("pickup_collected", { entity = pickup })
    end
end

events.callbacks = {
    { ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
        if not continued then
            engine.onNewRun()
            engine.emit("run_start")
        end
    end },
    { ModCallbacks.MC_POST_NEW_LEVEL, function() engine.emit("new_floor") end },
    { ModCallbacks.MC_POST_NEW_ROOM, function()
        engine.onNewRoom()
        roomWasClear = AC.game:GetRoom():IsClear()
        engine.emit("room_enter")
    end },
    { ModCallbacks.MC_POST_UPDATE, onUpdate },
    { ModCallbacks.MC_POST_RENDER, onRender },
    { ModCallbacks.MC_POST_PEFFECT_UPDATE, onPlayerUpdate },
    { ModCallbacks.MC_ENTITY_TAKE_DMG, onDamage },
    { ModCallbacks.MC_POST_NPC_DEATH, function(_, npc) engine.emit("entity_killed", { entity = npc }) end },
    { ModCallbacks.MC_NPC_UPDATE, onNpcUpdate },
    { ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate },
    { ModCallbacks.MC_USE_ITEM, function(_, item, _, player)
        engine.emit("active_used", { player = player, entity = player, value = item })
    end },
    { ModCallbacks.MC_USE_CARD, function(_, card, player)
        engine.emit("card_used", { player = player, entity = player, value = card })
    end },
    { ModCallbacks.MC_USE_PILL, function(_, effect, player)
        engine.emit("pill_used", { player = player, entity = player, value = effect })
    end },
    { ModCallbacks.MC_POST_FIRE_TEAR, function(_, tear)
        local spawner = tear.SpawnerEntity
        engine.emit("tear_fired", { entity = tear, player = spawner and spawner:ToPlayer() or nil })
    end },
}

return events
