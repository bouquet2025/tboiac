-- Enemies & bosses: spawn by ID or from the boss list, champions, friendly spawns,
-- mass actions, HP multiplier.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "enemies", label = "m_enemies" }

local function S() return AC.save.data.enemies end
local BOSSES = AC.data.BOSSES

local state = { type = 10, variant = 0, subtype = 0, count = 1, champion = false }


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
                menu.link(t("m_enemies_common"), "enemies_common"),
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
                local it = menu.action(string.format("%s  %d.%d", b[1], b[2], b[3]), function()
                    spawn(b[2], b[3], 0, b[1])
                end)
                it.preview = function(pos) AC.icons.entity(b[2], b[3], pos) end
                items[#items + 1] = it
            end
            return items
        end,
    },
    enemies_common = {
        title = function() return t("m_enemies_common") end,
        build = function()
            local items = spawnOptions()
            for _, b in ipairs(AC.data.ENEMIES) do
                local it = menu.action(string.format("%s  %d.%d", b[1], b[2], b[3]), function()
                    spawn(b[2], b[3], 0, b[1])
                end)
                it.preview = function(pos) AC.icons.entity(b[2], b[3], pos) end
                items[#items + 1] = it
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
