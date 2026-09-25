-- Rule actions. run(p, ctx, rule). ctx.entity may be nil (event without entity).
local AC = TBOIAC
local engine, P, util = AC.rules, AC.ruleParams, AC.util

local def = engine.defineAction
local mark = function(e) return AC.ruleEvents.markSpawned(e) end

local function player(ctx) return ctx.player or util.firstTarget() end

local function position(mode, ctx)
    local room = AC.game:GetRoom()
    if mode == "entity" and ctx.entity then return ctx.entity.Position end
    if mode == "random" then return room:GetRandomPosition(40) end
    if mode == "center" then return room:GetCenterPos() end
    return player(ctx).Position
end

local function freePos(mode, ctx)
    return Isaac.GetFreeNearPosition(position(mode, ctx) + Vector(math.random(-20, 20), math.random(-20, 20)), 30)
end

local function randomItem()
    return AC.game:GetItemPool():GetCollectible(ItemPoolType.POOL_TREASURE, true, Random())
end

local function npcOf(ctx) return ctx.entity and ctx.entity:ToNPC() end

local COLORS = {
    red = { 1, 0.3, 0.3, 1, 0.4, 0, 0 }, green = { 0.3, 1, 0.3, 1, 0, 0.3, 0 },
    blue = { 0.3, 0.3, 1, 1, 0, 0, 0.4 }, gold = { 1, 0.85, 0.2, 1, 0.3, 0.2, 0 },
    black = { 0.1, 0.1, 0.1, 1, 0, 0, 0 }, white = { 1, 1, 1, 1, 0.6, 0.6, 0.6 },
    ghost = { 1, 1, 1, 0.35, 0, 0, 0 }, reset = { 1, 1, 1, 1, 0, 0, 0 },
}

-- Spawning -------------------------------------------------------------------------------------

def({ id = "spawn_entity", label = "a_spawn_entity",
    params = { P.entity("ent", "entity", "10.0.0"), P.number("count", "count", 1, 1, 30),
               P.choice("pos", "position", "random", P.POSITION), P.toggle("champion", "as_champion"),
               P.toggle("friendly", "friendly_spawn") },
    run = function(p, ctx)
        local et, ev, es = P.parseEntity(p.ent)
        for _ = 1, p.count do
            local e = mark(Isaac.Spawn(et, ev, es, freePos(p.pos, ctx), Vector.Zero, nil))
            local npc = e and e:ToNPC()
            if npc then
                if p.champion and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
                if p.friendly then
                    npc:AddCharmed(EntityRef(player(ctx)), -1)
                    npc:AddEntityFlags(EntityFlag.FLAG_PERSISTENT)
                end
            end
        end
    end })

def({ id = "spawn_random", label = "a_spawn_random",
    params = { P.choice("kind", "kind", "boss", { { "kind_boss", "boss" }, { "kind_enemy", "enemy" } }),
               P.number("count", "count", 1, 1, 10), P.choice("pos", "position", "random", P.POSITION),
               P.toggle("champion", "as_champion") },
    run = function(p, ctx)
        local list = p.kind == "enemy" and AC.data.ENEMIES or AC.data.BOSSES
        for _ = 1, p.count do
            local pick = list[math.random(#list)]
            local e = mark(Isaac.Spawn(pick[2], pick[3], 0, freePos(p.pos, ctx), Vector.Zero, nil))
            local npc = e and e:ToNPC()
            if npc and p.champion and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
        end
    end })

def({ id = "entity_clone", label = "a_entity_clone", params = { P.number("count", "count", 1, 1, 20) },
    run = function(p, ctx)
        local e = ctx.entity
        if not e or e.Type == EntityType.ENTITY_PLAYER then return end
        for i = 1, p.count do
            local pos = Isaac.GetFreeNearPosition(e.Position + Vector.FromAngle(i * 360 / p.count) * 40, 20)
            mark(Isaac.Spawn(e.Type, e.Variant, e.SubType, pos, Vector.Zero, nil))
        end
    end })

def({ id = "replace_entity", label = "a_replace_entity", params = { P.entity("ent", "entity", "10.0.0") },
    run = function(p, ctx)
        local e = ctx.entity
        if not e then return end
        local et, ev, es = P.parseEntity(p.ent)
        local pickup = e:ToPickup()
        if pickup and et == EntityType.ENTITY_PICKUP then
            pickup:Morph(et, ev, es, true, true, false)
            return
        end
        mark(Isaac.Spawn(et, ev, es, e.Position, e.Velocity, nil))
        e:Remove()
    end })

def({ id = "set_item", label = "a_set_item", params = { P.catalog("id", "item", 0, "collectible", "random") },
    run = function(p, ctx)
        local pickup = ctx.entity and ctx.entity:ToPickup()
        if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE or pickup.SubType == 0 then return end
        local id = p.id ~= 0 and p.id or randomItem()
        if pickup.SubType ~= id then
            pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, true, true, false)
        end
    end })

def({ id = "spawn_pickup", label = "a_spawn_pickup",
    params = { P.number("variant", "variant", 0, 0, 1000), P.number("subtype", "subtype", 0, 0, 1000),
               P.number("count", "count", 1, 1, 30), P.choice("pos", "position", "player", P.POSITION) },
    run = function(p, ctx)
        for _ = 1, p.count do
            mark(Isaac.Spawn(EntityType.ENTITY_PICKUP, p.variant, p.subtype, freePos(p.pos, ctx), Vector.Zero, nil))
        end
    end })

def({ id = "spawn_item", label = "a_spawn_item",
    params = { P.catalog("id", "item", 0, "collectible", "random"), P.choice("pos", "position", "player", P.POSITION) },
    run = function(p, ctx)
        local pos = AC.game:GetRoom():FindFreePickupSpawnPosition(position(p.pos, ctx), 0, true)
        mark(Isaac.Spawn(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, p.id, pos, Vector.Zero, nil))
    end })

-- Player ---------------------------------------------------------------------------------------

def({ id = "give_item", label = "a_give_item", params = { P.catalog("id", "item", 0, "collectible", "random") },
    run = function(p, ctx) player(ctx):AddCollectible(p.id ~= 0 and p.id or randomItem(), 0, true) end })

def({ id = "remove_item", label = "a_remove_item", params = { P.catalog("id", "item", 0, "collectible", "random") },
    run = function(p, ctx)
        local pl = player(ctx)
        local id = p.id
        if id == 0 then
            local owned = {}
            for i = 1, util.maxCollectible() do
                if Isaac.GetItemConfig():GetCollectible(i) and pl:HasCollectible(i, true) then owned[#owned + 1] = i end
            end
            id = owned[math.random(math.max(1, #owned))]
        end
        if id and pl:HasCollectible(id, true) then pl:RemoveCollectible(id) end
    end })

def({ id = "give_trinket", label = "a_give_trinket", params = { P.catalog("id", "trinket", 1, "trinket") },
    run = function(p, ctx) player(ctx):AddTrinket(p.id, true) end })

def({ id = "use_active", label = "a_use_active", params = { P.catalog("id", "item", 105, "collectible") },
    run = function(p, ctx) player(ctx):UseActiveItem(p.id, UseFlag.USE_NOANIM) end })

def({ id = "use_card", label = "a_use_card", params = { P.catalog("id", "card", 1, "card") },
    run = function(p, ctx) player(ctx):UseCard(p.id, UseFlag.USE_NOANIM) end })

def({ id = "use_pill", label = "a_use_pill", params = { P.catalog("id", "pill", 0, "pill") },
    run = function(p, ctx) player(ctx):UsePill(p.id, PillColor.PILL_BLUE_BLUE, UseFlag.USE_NOANIM) end })

local HEART_FN = {
    container = function(pl, n) pl:AddMaxHearts(2 * n) end, red = function(pl, n) pl:AddHearts(2 * n) end,
    soul = function(pl, n) pl:AddSoulHearts(2 * n) end, black = function(pl, n) pl:AddBlackHearts(2 * n) end,
    bone = function(pl, n) pl:AddBoneHearts(n) end, golden = function(pl, n) pl:AddGoldenHearts(n) end,
    eternal = function(pl, n) pl:AddEternalHearts(n) end, rotten = function(pl, n) pl:AddRottenHearts(2 * n) end,
    broken = function(pl, n) pl:AddBrokenHearts(n) end,
}

def({ id = "hearts", label = "a_hearts",
    params = { P.choice("kind", "heart_kind", "red", P.HEARTS), P.number("amount", "amount", 1, -12, 12) },
    run = function(p, ctx) HEART_FN[p.kind](player(ctx), p.amount) end })

def({ id = "resources", label = "a_resources",
    params = { P.choice("res", "resource", "coins", P.RESOURCES), P.number("amount", "amount", 5, -99, 99) },
    run = function(p, ctx)
        local pl = player(ctx)
        if p.res == "bombs" then pl:AddBombs(p.amount)
        elseif p.res == "keys" then pl:AddKeys(p.amount)
        else pl:AddCoins(p.amount) end
    end })

def({ id = "stat", label = "a_stat",
    params = { P.choice("stat", "stat", "damage", P.STATS), P.number("amount", "amount", 0.5, -10, 10, 0.1) },
    run = function(p)
        local stats = engine.run().stats
        stats[p.stat] = (stats[p.stat] or 0) + p.amount
        for _, pl in ipairs(util.players()) do
            pl:AddCacheFlags(CacheFlag.CACHE_ALL)
            pl:EvaluateItems()
        end
    end })

def({ id = "damage_player", label = "a_damage_player", params = { P.number("amount", "half_hearts", 1, 1, 24) },
    run = function(p, ctx)
        player(ctx):TakeDamage(p.amount, 0, EntityRef(nil), 0)
    end })

def({ id = "heal_player", label = "a_heal_player", run = function(_, ctx) player(ctx):SetFullHearts() end })
def({ id = "kill_player", label = "a_kill_player", run = function(_, ctx) player(ctx):Kill() end })

def({ id = "change_character", label = "a_change_character", params = { P.choice("type", "character", 0, P.characters) },
    run = function(p, ctx) player(ctx):ChangePlayerType(p.type) end })

-- Trigger entity -------------------------------------------------------------------------------

def({ id = "entity_kill", label = "a_entity_kill", run = function(_, ctx) if ctx.entity then ctx.entity:Kill() end end })
def({ id = "entity_remove", label = "a_entity_remove", run = function(_, ctx) if ctx.entity then ctx.entity:Remove() end end })

def({ id = "entity_damage", label = "a_entity_damage", params = { P.number("amount", "amount", 10, 1, 1000, 5) },
    run = function(p, ctx)
        if ctx.entity then ctx.entity:TakeDamage(p.amount, 0, EntityRef(player(ctx)), 0) end
    end })

def({ id = "entity_heal", label = "a_entity_heal",
    run = function(_, ctx) if ctx.entity then ctx.entity.HitPoints = ctx.entity.MaxHitPoints end end })

def({ id = "entity_champion", label = "a_entity_champion",
    run = function(_, ctx)
        local npc = npcOf(ctx)
        if npc and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
    end })

def({ id = "entity_charm", label = "a_entity_charm",
    run = function(_, ctx)
        local npc = npcOf(ctx)
        if npc then npc:AddCharmed(EntityRef(player(ctx)), -1) end
    end })

def({ id = "entity_freeze", label = "a_entity_freeze", params = { P.number("seconds", "seconds", 3, 0.5, 60, 0.5) },
    run = function(p, ctx)
        local npc = npcOf(ctx)
        if npc then npc:AddFreeze(EntityRef(player(ctx)), math.floor(p.seconds * 30)) end
    end })

def({ id = "entity_scale", label = "a_entity_scale", params = { P.number("scale", "size", 2, 0.25, 5, 0.25) },
    run = function(p, ctx)
        local e = ctx.entity
        if not e then return end
        e.SpriteScale = Vector(p.scale, p.scale)
        e.SizeMulti = Vector(p.scale, p.scale)
    end })

def({ id = "entity_color", label = "a_entity_color", params = { P.choice("color", "color", "red", P.COLORS) },
    run = function(p, ctx)
        local c = COLORS[p.color]
        if ctx.entity then ctx.entity.Color = Color(c[1], c[2], c[3], c[4], c[5], c[6], c[7]) end
    end })

def({ id = "entity_push", label = "a_entity_push",
    params = { P.choice("dir", "direction", "away", { { "dir_away", "away" }, { "dir_toward", "toward" }, { "dir_random", "random" } }),
               P.number("speed", "speed", 15, 1, 100) },
    run = function(p, ctx)
        local e = ctx.entity
        if not e then return end
        local d
        if p.dir == "random" then d = Vector.FromAngle(math.random(360))
        else
            d = (e.Position - player(ctx).Position):Normalized()
            if p.dir == "toward" then d = d * -1 end
        end
        e:AddVelocity(d * p.speed)
    end })

def({ id = "explode", label = "a_explode",
    params = { P.choice("pos", "position", "entity", P.POSITION), P.number("damage", "amount", 40, 0, 1000, 5) },
    run = function(p, ctx) Isaac.Explode(position(p.pos, ctx), nil, p.damage) end })

-- Room & world ---------------------------------------------------------------------------------

def({ id = "kill_enemies", label = "kill_all", run = function()
    for _, npc in ipairs(util.enemies()) do npc:Kill() end
end })

def({ id = "charm_enemies", label = "charm_all", run = function(_, ctx)
    for _, npc in ipairs(util.enemies()) do npc:AddCharmed(EntityRef(player(ctx)), -1) end
end })

def({ id = "open_doors", label = "open_doors", run = function()
    local room = AC.game:GetRoom()
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then door:Open() end
    end
end })

def({ id = "close_doors", label = "a_close_doors", run = function()
    local room = AC.game:GetRoom()
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then door:Close(true) end
    end
end })

def({ id = "teleport", label = "a_teleport",
    params = { P.choice("to", "destination", "random", {
        { "dest_random", "random" }, { "tp_start", "start" }, { "tp_devil", "devil" }, { "tp_error", "error" },
        { "rt_treasure", "treasure" }, { "rt_shop", "shop" }, { "rt_boss", "boss" }, { "rt_secret", "secret" } }) },
    run = function(p)
        local level = AC.game:GetLevel()
        local idx
        if p.to == "random" then
            local rooms = level:GetRooms()
            idx = rooms:Get(math.random(0, rooms.Size - 1)).SafeGridIndex
        elseif p.to == "start" then idx = level:GetStartingRoomIndex()
        elseif p.to == "devil" then idx = GridRooms.ROOM_DEVIL_IDX
        elseif p.to == "error" then idx = GridRooms.ROOM_ERROR_IDX
        else
            local types = { treasure = RoomType.ROOM_TREASURE, shop = RoomType.ROOM_SHOP,
                            boss = RoomType.ROOM_BOSS, secret = RoomType.ROOM_SECRET }
            idx = util.findRoom(types[p.to])
        end
        if idx then util.teleport(idx) end
    end })

def({ id = "reroll_pedestals", label = "reroll_pedestals",
    run = function(_, ctx) player(ctx):UseActiveItem(CollectibleType.COLLECTIBLE_D6, UseFlag.USE_NOANIM) end })

def({ id = "reveal_map", label = "reveal_map", run = function()
    local level = AC.game:GetLevel()
    level:ApplyMapEffect()
    level:ApplyBlueMapEffect()
    level:ApplyCompassEffect(true)
end })

def({ id = "add_curse", label = "a_add_curse", params = { P.choice("curse", "curse", LevelCurse.CURSE_OF_DARKNESS, P.curses) },
    run = function(p) AC.game:GetLevel():AddCurse(p.curse, false) end })

def({ id = "clear_curses", label = "a_clear_curses", run = function()
    local level = AC.game:GetLevel()
    level:RemoveCurses(level:GetCurses())
end })

def({ id = "time_mode", label = "a_time_mode",
    params = { P.choice("mode", "time_speed", 1, P.TIME_MODES), P.number("seconds", "seconds_zero_forever", 5, 0, 600, 1) },
    run = function(p)
        local time = AC.save.data.time
        time.mode = p.mode
        if p.seconds > 0 then
            table.insert(engine.queue, { at = engine.frame + p.seconds * 30,
                act = { id = "time_mode", p = { mode = 0, seconds = 0 } }, ctx = {}, rule = nil })
        end
    end })

-- Feedback -------------------------------------------------------------------------------------

def({ id = "show_text", label = "a_show_text",
    params = { P.text("text", "text", "hello"),
               P.choice("style", "style", "toast", { { "style_toast", "toast" }, { "style_item", "item" } }) },
    run = function(p)
        if p.style == "item" then
            AC.game:GetHUD():ShowItemText(p.text, "", false)
        else
            AC.render.toast(p.text, 120)
        end
    end })

def({ id = "play_sound", label = "a_play_sound", params = { P.number("id", "sound_id", 1, 1, 1000) },
    run = function(p) SFXManager():Play(p.id, 1, 0, false, 1) end })

-- Variables & control --------------------------------------------------------------------------

def({ id = "flag_set", label = "a_flag_set",
    params = { P.text("name", "flag_name", "a"),
               P.choice("mode", "mode", "on", { { "on", "on" }, { "off", "off" }, { "toggle", "toggle" } }) },
    run = function(p)
        local v = p.mode == "on" or (p.mode == "toggle" and not engine.flag(p.name))
        engine.setFlag(p.name, v)
    end })

def({ id = "counter", label = "a_counter",
    params = { P.text("name", "counter_name", "a"),
               P.choice("op", "mode", "add", { { "op_add", "add" }, { "op_set", "set" } }),
               P.number("value", "amount", 1, -9999, 9999) },
    run = function(p)
        local v = p.op == "set" and p.value or engine.counter(p.name) + p.value
        engine.setCounter(p.name, v)
    end })

def({ id = "rule_toggle", label = "a_rule_toggle",
    params = { P.number("rule", "rule_id", 1, 1, 9999),
               P.choice("mode", "mode", "toggle", { { "on", "on" }, { "off", "off" }, { "toggle", "toggle" } }) },
    run = function(p)
        local r = engine.findRule(p.rule)
        if not r then return end
        if p.mode == "toggle" then r.enabled = not r.enabled else r.enabled = p.mode == "on" end
    end })

def({ id = "command", label = "a_command", params = { P.text("cmd", "command", "") },
    run = function(p) if p.cmd ~= "" then util.command(p.cmd) end end })

return true
