-- Enemies & bosses: spawn by ID or from the boss list, champions, friendly spawns,
-- mass actions, HP multiplier.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "enemies", label = "m_enemies" }

local function S() return AC.save.data.enemies end

local state = { type = 10, variant = 0, subtype = 0, count = 1, champion = false }

-- { name, type, variant }
local BOSSES = {
    { "Monstro", 20, 0 }, { "Monstro II", 43, 0 }, { "Larry Jr.", 19, 0 }, { "The Hollow", 19, 1 },
    { "Gurdy", 36, 0 }, { "Gurdy Jr.", 99, 0 }, { "Mama Gurdy", 266, 0 }, { "Duke of Flies", 67, 0 },
    { "The Husk", 67, 1 }, { "Peep", 68, 0 }, { "The Bloat", 68, 1 }, { "Chub", 28, 0 }, { "C.H.A.D.", 28, 1 },
    { "Carrion Queen", 28, 2 }, { "Gemini", 79, 0 }, { "Steven", 79, 1 }, { "Blighted Ovum", 79, 2 },
    { "Pin", 62, 0 }, { "Scolex", 62, 1 }, { "The Frail", 62, 2 }, { "Wormwood", 62, 3 },
    { "Famine", 63, 0 }, { "Pestilence", 64, 0 }, { "War", 65, 0 }, { "Conquest", 65, 1 }, { "Death", 66, 0 },
    { "Fistula", 71, 0 }, { "Teratoma", 71, 1 }, { "Blastocyst", 74, 0 }, { "Lokii", 69, 0 },
    { "Mask of Infamy", 97, 0 }, { "The Widow", 100, 0 }, { "The Wretched", 100, 1 },
    { "Daddy Long Legs", 101, 0 }, { "Triachnid", 101, 1 }, { "The Haunt", 260, 0 }, { "Dingle", 261, 0 },
    { "Dangle", 261, 1 }, { "Mega Maw", 262, 0 }, { "The Gate", 263, 0 }, { "Mega Fatty", 264, 0 },
    { "The Cage", 265, 0 }, { "Dark One", 267, 0 }, { "The Adversary", 268, 0 }, { "Polycephalus", 269, 0 },
    { "Mr. Fred", 270, 0 }, { "Uriel", 271, 0 }, { "Gabriel", 272, 0 }, { "The Fallen", 81, 0 },
    { "Krampus", 81, 1 }, { "The Stain", 401, 0 }, { "Brownie", 402, 0 }, { "The Forsaken", 403, 0 },
    { "Little Horn", 404, 0 }, { "Rag Man", 405, 0 }, { "Rag Mega", 409, 0 }, { "Sisters Vis", 410, 0 },
    { "Big Horn", 411, 0 }, { "The Matriarch", 413, 0 },
    { "Reap Creep", 900, 0 }, { "Lil Blub", 901, 0 }, { "The Rainmaker", 902, 0 }, { "The Visage", 903, 0 },
    { "The Siren", 904, 0 }, { "The Heretic", 905, 0 }, { "Hornfel", 906, 0 }, { "Great Gideon", 907, 0 },
    { "Baby Plum", 908, 0 }, { "The Scourge", 909, 0 }, { "Chimera", 910, 0 }, { "Rotgut", 911, 0 },
    { "Min-Min", 913, 0 }, { "Clog", 914, 0 }, { "Singe", 915, 0 }, { "Bumbino", 916, 0 },
    { "Colostomia", 917, 0 }, { "Turdlet", 918, 0 }, { "Raglich", 919, 0 }, { "Horny Boys", 920, 0 },
    { "Clutch", 921, 0 },
    { "Mom", 45, 0 }, { "Mom's Heart", 78, 0 }, { "It Lives", 78, 1 }, { "Satan", 84, 0 }, { "Isaac", 102, 0 },
    { "???", 102, 1 }, { "The Lamb", 273, 0 }, { "Mega Satan", 274, 0 }, { "Hush", 407, 0 },
    { "Ultra Greed", 406, 0 }, { "Ultra Greedier", 406, 1 }, { "Delirium", 412, 0 }, { "Mother", 912, 0 },
    { "Dogma", 950, 0 }, { "The Beast", 951, 0 },
}

local function spawn(etype, variant, subtype, label)
    local player = util.firstTarget()
    for i = 1, state.count do
        local angle = (i / state.count) * 360
        local pos = Isaac.GetFreeNearPosition(player.Position + Vector.FromAngle(angle) * 120, 40)
        local e = Isaac.Spawn(etype, variant, subtype, pos, Vector.Zero, nil)
        local npc = e and e:ToNPC()
        if npc then
            if state.champion and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
            if S().friendlySpawn then
                npc:AddCharmed(EntityRef(player), -1)
                npc:AddEntityFlags(EntityFlag.FLAG_PERSISTENT)
            end
        end
    end
    AC.save.pushRecent(AC.save.data.recent.entities, etype .. "." .. variant .. "." .. subtype, 15)
    AC.render.toast(t("spawned", label, state.count))
end

local function forEnemies(fn)
    return function()
        local list = util.enemies()
        for _, npc in ipairs(list) do fn(npc) end
        AC.render.toast(t("affected", #list))
    end
end

local function spawnOptions()
    return {
        { kind = "number", label = t("count"), min = 1, max = 30, step = 1,
          get = function() return state.count end, set = function(v) state.count = v end },
        { kind = "toggle", label = t("as_champion"),
          get = function() return state.champion end, set = function(v) state.champion = v end },
        menu.toggle(t("friendly_spawn"), "enemies", "friendlySpawn"),
    }
end

local function withOptions(list)
    local items = spawnOptions()
    for _, it in ipairs(list) do items[#items + 1] = it end
    return items
end

feature.pages = {
    enemies = {
        title = function() return t("m_enemies") end,
        build = function()
            return withOptions({
                menu.link(t("m_bosses"), "enemies_bosses"),
                menu.link(t("m_spawn_custom"), "enemies_custom"),
                menu.link(t("m_recent"), "enemies_recent"),
                menu.number(t("hp_mult"), "enemies", "hpMult", 0.1, 20, 0.1),
                menu.toggle(t("all_champions"), "enemies", "allChampions"),
                menu.action(t("kill_all"), forEnemies(function(npc) npc:Kill() end)),
                menu.action(t("remove_all"), forEnemies(function(npc) npc:Remove() end)),
                menu.action(t("champion_all"), forEnemies(function(npc)
                    if not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
                end)),
                menu.action(t("charm_all"), forEnemies(function(npc)
                    npc:AddCharmed(EntityRef(util.firstTarget()), -1)
                end)),
                menu.action(t("heal_all"), forEnemies(function(npc) npc.HitPoints = npc.MaxHitPoints end)),
            })
        end,
    },
    enemies_bosses = {
        title = function() return t("m_bosses") end,
        build = function()
            local items = spawnOptions()
            for _, b in ipairs(BOSSES) do
                items[#items + 1] = menu.action(string.format("%s  %d.%d", b[1], b[2], b[3]), function()
                    spawn(b[2], b[3], 0, b[1])
                end)
            end
            return items
        end,
    },
    enemies_custom = {
        title = function() return t("m_spawn_custom") end,
        build = function()
            local function num(label, key, max)
                return { kind = "number", label = label, min = 0, max = max, step = 1,
                         get = function() return state[key] end, set = function(v) state[key] = v end }
            end
            return withOptions({
                menu.info(t("custom_hint")),
                num(t("type"), "type", 1000), num(t("variant"), "variant", 4000), num(t("subtype"), "subtype", 4000),
                menu.action(t("spawn"), function()
                    spawn(state.type, state.variant, state.subtype,
                        state.type .. "." .. state.variant .. "." .. state.subtype)
                end),
            })
        end,
    },
    enemies_recent = {
        title = function() return t("m_recent") end,
        build = function()
            local items = spawnOptions()
            for _, key in ipairs(AC.save.data.recent.entities) do
                local a, b, c = key:match("^(%d+)%.(%d+)%.(%d+)$")
                if a then
                    items[#items + 1] = menu.action(key, function()
                        spawn(tonumber(a), tonumber(b), tonumber(c), key)
                    end)
                end
            end
            return items
        end,
    },
}

local function onNpcUpdate(_, npc)
    local data = npc:GetData()
    if data.tboiacSeen then return end
    data.tboiacSeen = true
    if not npc:IsVulnerableEnemy() or npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
    local s = S()
    if s.hpMult ~= 1 then
        npc.MaxHitPoints = npc.MaxHitPoints * s.hpMult
        npc.HitPoints = npc.MaxHitPoints
    end
    if s.allChampions and not npc:IsBoss() and not npc:IsChampion() then
        npc:MakeChampion(Random(), -1, true)
    end
end

feature.callbacks = {
    { ModCallbacks.MC_NPC_UPDATE, onNpcUpdate },
}

function feature.reset()
    local s = S()
    s.hpMult, s.allChampions, s.friendlySpawn = 1, false, false
end

return feature
