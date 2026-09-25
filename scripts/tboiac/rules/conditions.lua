-- Rule conditions. check(p, ctx, rule) -> boolean. Every condition can be negated in the editor.
local AC = TBOIAC
local engine, P = AC.rules, AC.ruleParams

local function key(rule) return "r" .. rule.id end

local function player(ctx) return ctx.player or AC.util.firstTarget() end

local def = engine.defineCondition

def({ id = "chance", label = "c_chance", params = { P.number("value", "percent", 50, 1, 100, 5) },
    check = function(p) return math.random(100) <= p.value end })

def({ id = "every_nth", label = "c_every_nth", params = { P.number("n", "n", 3, 1, 1000) },
    check = function(p, _, rule) return (engine.run().matches[key(rule)] or 0) % p.n == 0 end })

def({ id = "once_run", label = "c_once_run",
    check = function(_, _, rule) return (engine.run().fired[key(rule)] or 0) == 0 end })

def({ id = "max_run", label = "c_max_run", params = { P.number("n", "n", 3, 1, 1000) },
    check = function(p, _, rule) return (engine.run().fired[key(rule)] or 0) < p.n end })

def({ id = "once_room", label = "c_once_room",
    check = function(_, _, rule) return (engine.room.fired[key(rule)] or 0) == 0 end })

def({ id = "once_entity", label = "c_once_entity",
    check = function(_, ctx, rule)
        if not ctx.entity then return true end
        local data = ctx.entity:GetData()
        data.tboiacRuleOnce = data.tboiacRuleOnce or {}
        if data.tboiacRuleOnce[rule.id] then return false end
        data.tboiacRuleOnce[rule.id] = true
        return true
    end })

def({ id = "cooldown", label = "c_cooldown", params = { P.number("seconds", "seconds", 5, 0.5, 3600, 0.5) },
    check = function(p, _, rule)
        local last = engine.last[key(rule)]
        return not last or engine.frame - last >= p.seconds * 30
    end })

def({ id = "stage", label = "c_stage",
    params = { P.number("min", "stage_min", 1, 1, 13), P.number("max", "stage_max", 13, 1, 13) },
    check = function(p)
        local s = AC.game:GetLevel():GetStage()
        return s >= p.min and s <= p.max
    end })

def({ id = "room_type", label = "c_room_type",
    params = { P.choice("roomType", "room_type", RoomType.ROOM_BOSS, P.roomTypes(false)) },
    check = function(p) return AC.game:GetRoom():GetType() == p.roomType end })

def({ id = "room_clear", label = "c_room_clear",
    check = function() return AC.game:GetRoom():IsClear() end })

def({ id = "hp", label = "c_hp",
    params = { P.choice("op", "compare", "lt", P.COMPARE), P.number("value", "hearts", 2, 0, 24, 0.5) },
    check = function(p, ctx)
        local pl = player(ctx)
        local hearts = (pl:GetHearts() + pl:GetSoulHearts() + pl:GetBoneHearts() * 2) / 2
        return engine.compare(hearts, p.op, p.value)
    end })

def({ id = "resource", label = "c_resource",
    params = { P.choice("res", "resource", "coins", P.RESOURCES), P.choice("op", "compare", "ge", P.COMPARE),
               P.number("value", "amount", 10, 0, 999) },
    check = function(p, ctx)
        local pl = player(ctx)
        local v = p.res == "bombs" and pl:GetNumBombs() or p.res == "keys" and pl:GetNumKeys() or pl:GetNumCoins()
        return engine.compare(v, p.op, p.value)
    end })

def({ id = "has_item", label = "c_has_item", params = { P.catalog("id", "item", 1, "collectible") },
    check = function(p, ctx) return player(ctx):HasCollectible(p.id) end })

def({ id = "has_trinket", label = "c_has_trinket", params = { P.catalog("id", "trinket", 1, "trinket") },
    check = function(p, ctx) return player(ctx):HasTrinket(p.id) end })

def({ id = "items_count", label = "c_items_count",
    params = { P.choice("op", "compare", "ge", P.COMPARE), P.number("value", "amount", 5, 0, 500) },
    check = function(p, ctx) return engine.compare(player(ctx):GetCollectibleCount(), p.op, p.value) end })

def({ id = "character", label = "c_character", params = { P.choice("type", "character", 0, P.characters) },
    check = function(p, ctx) return player(ctx):GetPlayerType() == p.type end })

def({ id = "flag", label = "c_flag", params = { P.text("name", "flag_name", "a") },
    check = function(p) return engine.flag(p.name) end })

def({ id = "counter", label = "c_counter",
    params = { P.text("name", "counter_name", "a"), P.choice("op", "compare", "ge", P.COMPARE),
               P.number("value", "amount", 5, -9999, 9999) },
    check = function(p) return engine.compare(engine.counter(p.name), p.op, p.value) end })

def({ id = "is_boss", label = "c_is_boss",
    check = function(_, ctx)
        local npc = ctx.entity and ctx.entity:ToNPC()
        return npc ~= nil and npc:IsBoss()
    end })

def({ id = "is_champion", label = "c_is_champion",
    check = function(_, ctx)
        local npc = ctx.entity and ctx.entity:ToNPC()
        return npc ~= nil and npc:IsChampion()
    end })

def({ id = "distance", label = "c_distance",
    params = { P.choice("op", "compare", "lt", P.COMPARE), P.number("value", "distance_px", 100, 0, 2000, 10) },
    check = function(p, ctx)
        if not ctx.entity then return false end
        return engine.compare(ctx.entity.Position:Distance(player(ctx).Position), p.op, p.value)
    end })

def({ id = "enemies_count", label = "c_enemies_count",
    params = { P.choice("op", "compare", "eq", P.COMPARE), P.number("value", "amount", 0, 0, 200) },
    check = function(p) return engine.compare(#AC.util.enemies(), p.op, p.value) end })

def({ id = "has_label", label = "c_has_label", params = { P.text("label", "label_name", "a") },
    check = function(p, ctx) return engine.hasLabel(ctx.entity, p.label) end })

def({ id = "in_list", label = "c_in_list", params = { P.text("list", "list_name", "a") },
    check = function(p, ctx) return engine.inList(p.list, ctx.entity) end })

def({ id = "list_size", label = "c_list_size",
    params = { P.text("list", "list_name", "a"), P.choice("op", "compare", "ge", P.COMPARE),
               P.number("value", "amount", 3, 0, 500) },
    check = function(p) return engine.compare(#engine.listEntities(p.list), p.op, p.value) end })

def({ id = "labeled_count", label = "c_labeled_count",
    params = { P.text("label", "label_name", "a"), P.choice("op", "compare", "eq", P.COMPARE),
               P.number("value", "amount", 0, 0, 500) },
    check = function(p)
        local n = 0
        for _, e in ipairs(Isaac.GetRoomEntities()) do
            if engine.hasLabel(e, p.label) and not e:IsDead() then n = n + 1 end
        end
        return engine.compare(n, p.op, p.value)
    end })

return true
