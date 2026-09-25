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

-- Offsets of `count` points arranged in a formation, `spacing` pixels apart.
local function formation(kind, count, spacing)
    local out = {}
    if kind == "circle" then
        local r = math.max(spacing, spacing * count / (2 * math.pi))
        for i = 1, count do out[i] = Vector.FromAngle(i * 360 / count) * r end
    elseif kind == "line_h" or kind == "line_v" then
        for i = 1, count do
            local d = (i - (count + 1) / 2) * spacing
            out[i] = kind == "line_h" and Vector(d, 0) or Vector(0, d)
        end
    elseif kind == "cross" or kind == "diag" then
        local start = kind == "cross" and 0 or 45
        for i = 1, count do
            local ring = math.floor((i - 1) / 4) + 1
            out[i] = Vector.FromAngle(start + ((i - 1) % 4) * 90) * (spacing * ring)
        end
    elseif kind == "grid" then
        local side = math.ceil(math.sqrt(count))
        for i = 1, count do
            local x, y = (i - 1) % side, (i - 1) // side
            out[i] = Vector((x - (side - 1) / 2) * spacing, (y - (side - 1) / 2) * spacing)
        end
    else
        for i = 1, count do out[i] = Vector(math.random(-spacing, spacing), math.random(-spacing, spacing)) end
    end
    return out
end

-- Spawn positions for `count` things around `base`, kept inside the room.
local function spawnPositions(base, p, count)
    local room = AC.game:GetRoom()
    local list = {}
    for i, off in ipairs(formation(p.formation or "random", count, p.spacing or 50)) do
        local pos = room:GetClampedPosition(base + off, 20)
        if (p.formation or "random") == "random" then pos = Isaac.GetFreeNearPosition(pos, 30) end
        list[i] = pos
    end
    return list
end

local function randomItem()
    return AC.game:GetItemPool():GetCollectible(ItemPoolType.POOL_TREASURE, true, Random())
end

-- Entities an entity action applies to (see P.TARGETS).
local function targets(p, ctx)
    local mode = p.target or "trigger"
    if mode == "trigger" then return { ctx.entity } end
    if mode == "label" then
        local out = {}
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if engine.hasLabel(e, p.name) then out[#out + 1] = e end
        end
        return out
    end
    if mode == "list" then return engine.listEntities(p.name) end
    if mode == "pickups" or mode == "items" then
        local out = {}
        for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
            local isItem = e.Variant == PickupVariant.PICKUP_COLLECTIBLE
            if (mode == "items") == isItem then out[#out + 1] = e end
        end
        return out
    end
    local enemies = util.enemies()
    if mode == "enemies" then return enemies end
    local origin = (ctx.entity or player(ctx)).Position
    if mode == "nearest" then
        local best, bestDist
        for _, npc in ipairs(enemies) do
            local d = npc.Position:Distance(origin)
            if (not ctx.entity or GetPtrHash(npc) ~= GetPtrHash(ctx.entity)) and (not best or d < bestDist) then
                best, bestDist = npc, d
            end
        end
        return { best }
    end
    local out = {}
    for _, npc in ipairs(enemies) do
        if npc.Position:Distance(origin) <= p.radius then out[#out + 1] = npc end
    end
    return out
end

-- Define an action applied to every target entity: fn(entity, p, ctx).
local function entityAction(id, label, params, fn)
    def({ id = id, label = label, params = P.join(P.target(), params or {}),
        run = function(p, ctx)
            for _, e in ipairs(targets(p, ctx)) do
                if e and e:Exists() then fn(e, p, ctx) end
            end
        end })
end

local COLORS = {
    red = { 1, 0.3, 0.3, 1, 0.4, 0, 0 }, green = { 0.3, 1, 0.3, 1, 0, 0.3, 0 },
    blue = { 0.3, 0.3, 1, 1, 0, 0, 0.4 }, gold = { 1, 0.85, 0.2, 1, 0.3, 0.2, 0 },
    black = { 0.1, 0.1, 0.1, 1, 0, 0, 0 }, white = { 1, 1, 1, 1, 0.6, 0.6, 0.6 },
    ghost = { 1, 1, 1, 0.35, 0, 0, 0 }, reset = { 1, 1, 1, 1, 0, 0, 0 },
}

local function setupNpc(e, p, ctx)
    local npc = e and e:ToNPC()
    if not npc then return end
    if p.champion and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
    if p.friendly then
        npc:AddCharmed(EntityRef(player(ctx)), -1)
        npc:AddEntityFlags(EntityFlag.FLAG_PERSISTENT)
    end
    if p.label and p.label ~= "" then engine.setLabel(npc, p.label, true) end
end

-- Spawning -------------------------------------------------------------------------------------

local SPAWN_OPTS = {
    P.toggle("champion", "as_champion"), P.toggle("friendly", "friendly_spawn"), P.text("label", "give_label", ""),
}

def({ id = "spawn_entity", label = "a_spawn_entity",
    params = P.join({ P.entity("ent", "entity", "10.0.0"), P.number("count", "count", 1, 1, 30),
                      P.choice("pos", "position", "random", P.POSITION) }, P.formation(), SPAWN_OPTS),
    run = function(p, ctx)
        local et, ev, es = P.parseEntity(p.ent)
        for _, pos in ipairs(spawnPositions(position(p.pos, ctx), p, p.count)) do
            setupNpc(mark(Isaac.Spawn(et, ev, es, pos, Vector.Zero, nil)), p, ctx)
        end
    end })

def({ id = "spawn_random", label = "a_spawn_random",
    params = P.join({ P.choice("kind", "kind", "boss", { { "kind_boss", "boss" }, { "kind_enemy", "enemy" } }),
                      P.number("count", "count", 1, 1, 10), P.choice("pos", "position", "random", P.POSITION) },
                    P.formation(), SPAWN_OPTS),
    run = function(p, ctx)
        local list = p.kind == "enemy" and AC.data.ENEMIES or AC.data.BOSSES
        for _, pos in ipairs(spawnPositions(position(p.pos, ctx), p, p.count)) do
            local pick = list[math.random(#list)]
            setupNpc(mark(Isaac.Spawn(pick[2], pick[3], 0, pos, Vector.Zero, nil)), p, ctx)
        end
    end })

entityAction("entity_clone", "a_entity_clone", P.join({ P.number("count", "count", 1, 1, 20) },
    { P.choice("formation", "formation", "circle", P.FORMATIONS), P.number("spacing", "spacing_px", 40, 10, 300, 5) }),
    function(e, p)
        if e.Type == EntityType.ENTITY_PLAYER then return end
        for _, pos in ipairs(spawnPositions(e.Position, p, p.count)) do
            local copy = mark(Isaac.Spawn(e.Type, e.Variant, e.SubType, pos, Vector.Zero, nil))
            local labels = e:GetData().tboiacLabels
            if copy and labels then copy:GetData().tboiacLabels = AC.util.copy(labels) end
        end
    end)

entityAction("replace_entity", "a_replace_entity", { P.entity("ent", "entity", "10.0.0") },
    function(e, p)
        if e.Type == EntityType.ENTITY_PLAYER then return end
        local et, ev, es = P.parseEntity(p.ent)
        local pickup = e:ToPickup()
        if pickup and et == EntityType.ENTITY_PICKUP then
            pickup:Morph(et, ev, es, true, true, false)
            return
        end
        mark(Isaac.Spawn(et, ev, es, e.Position, e.Velocity, nil))
        e:Remove()
    end)

entityAction("set_item", "a_set_item", { P.catalog("id", "item", 0, "collectible", "random") },
    function(e, p)
        local pickup = e:ToPickup()
        if not pickup or pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE or pickup.SubType == 0 then return end
        local id = p.id ~= 0 and p.id or randomItem()
        if pickup.SubType ~= id then
            pickup:Morph(EntityType.ENTITY_PICKUP, PickupVariant.PICKUP_COLLECTIBLE, id, true, true, false)
        end
    end)

def({ id = "spawn_pickup", label = "a_spawn_pickup",
    params = P.join({ P.number("variant", "variant", 0, 0, 1000), P.number("subtype", "subtype", 0, 0, 1000),
                      P.number("count", "count", 1, 1, 30), P.choice("pos", "position", "player", P.POSITION) },
                    P.formation()),
    run = function(p, ctx)
        for _, pos in ipairs(spawnPositions(position(p.pos, ctx), p, p.count)) do
            mark(Isaac.Spawn(EntityType.ENTITY_PICKUP, p.variant, p.subtype, pos, Vector.Zero, nil))
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

-- Entities (target: trigger, nearest enemy, radius, all enemies, pickups, items, label, list) -----

entityAction("entity_kill", "a_entity_kill", nil, function(e) e:Kill() end)
entityAction("entity_remove", "a_entity_remove", nil, function(e) e:Remove() end)

entityAction("entity_damage", "a_entity_damage", { P.number("amount", "amount", 10, 1, 1000, 5) },
    function(e, p, ctx) e:TakeDamage(p.amount, 0, EntityRef(player(ctx)), 0) end)

entityAction("entity_heal", "a_entity_heal", nil, function(e) e.HitPoints = e.MaxHitPoints end)

entityAction("entity_champion", "a_entity_champion", nil, function(e)
    local npc = e:ToNPC()
    if npc and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
end)

entityAction("entity_charm", "a_entity_charm", nil, function(e, _, ctx)
    local npc = e:ToNPC()
    if npc then npc:AddCharmed(EntityRef(player(ctx)), -1) end
end)

entityAction("entity_freeze", "a_entity_freeze", { P.number("seconds", "seconds", 3, 0.5, 60, 0.5) },
    function(e, p, ctx)
        local npc = e:ToNPC()
        if npc then npc:AddFreeze(EntityRef(player(ctx)), math.floor(p.seconds * 30)) end
    end)

entityAction("entity_scale", "a_entity_scale", { P.number("scale", "size", 2, 0.25, 5, 0.25) },
    function(e, p)
        e.SpriteScale = Vector(p.scale, p.scale)
        e.SizeMulti = Vector(p.scale, p.scale)
    end)

entityAction("entity_color", "a_entity_color", { P.choice("color", "color", "red", P.COLORS) },
    function(e, p)
        local c = COLORS[p.color]
        e.Color = Color(c[1], c[2], c[3], c[4], c[5], c[6], c[7])
    end)

entityAction("entity_push", "a_entity_push",
    { P.choice("dir", "direction", "away", { { "dir_away", "away" }, { "dir_toward", "toward" }, { "dir_random", "random" } }),
      P.number("speed", "speed", 15, 1, 100) },
    function(e, p, ctx)
        local d
        if p.dir == "random" then d = Vector.FromAngle(math.random(360))
        else
            d = (e.Position - player(ctx).Position):Normalized()
            if p.dir == "toward" then d = d * -1 end
        end
        e:AddVelocity(d * p.speed)
    end)

entityAction("label_add", "a_label_add", { P.text("label", "label_name", "a") },
    function(e, p) engine.setLabel(e, p.label, true) end)

entityAction("label_remove", "a_label_remove", { P.text("label", "label_name", "a") },
    function(e, p) engine.setLabel(e, p.label, false) end)

entityAction("list_add", "a_list_add", { P.text("list", "list_name", "a") },
    function(e, p) engine.addToList(p.list, e) end)

entityAction("list_remove", "a_list_remove", { P.text("list", "list_name", "a") },
    function(e, p) engine.removeFromList(p.list, e) end)

def({ id = "list_clear", label = "a_list_clear", params = { P.text("list", "list_name", "a") },
    run = function(p) engine.lists[p.list] = nil end })

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

-- Stops the remaining actions of this firing (with a chance, for "maybe the rest happens").
def({ id = "stop", label = "a_stop", params = { P.number("chance", "percent", 100, 1, 100, 5) },
    run = function(p, ctx) if math.random(100) <= p.chance then ctx.stop = true end end })

def({ id = "pool_remove", label = "a_pool_remove", params = { P.catalog("id", "item", 1, "collectible") },
    run = function(p) AC.game:GetItemPool():RemoveCollectible(p.id) end })

def({ id = "command", label = "a_command", params = { P.text("cmd", "command", "") },
    run = function(p) if p.cmd ~= "" then util.command(p.cmd) end end })

-- Helpers shared with rules/effects.lua.
return { entityAction = entityAction, targets = targets, position = position, player = player }
