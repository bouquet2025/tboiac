-- Arena waves: spawn waves of enemies in the current room, next wave when cleared (or on a
-- timer), rewards between waves, endless generator, HUD overlay and rule events.
local AC = TBOIAC
local menu, util, engine, P = AC.menu, AC.util, AC.rules, AC.ruleParams
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "waves", label = "m_waves" }

local function S() return AC.save.data.waves end

-- Runtime state (not saved): state = "idle"|"fighting"|"pause"
local W = { state = "idle", wave = 0, timer = 0, room = nil, spawnedAt = 0 }
feature.state = W

local REWARDS = {
    { "rw_none", "none" }, { "rw_pickup", "pickup" }, { "rw_heart", "heart" }, { "rw_chest", "chest" },
    { "rw_item", "item" },
}
local REWARD_SPAWN = { pickup = { 0, 0 }, heart = { 10, 0 }, chest = { 50, 0 }, item = { 100, 0 } }

local KINDS = { { "kind_enemy", "enemy" }, { "kind_boss", "boss" }, { "wk_entity", "entity" } }

-- The entries of wave n: from the list, then generated when endless.
local function waveEntries(n)
    local s = S()
    if s.list[n] then return { s.list[n] } end
    if not s.endless and #s.list > 0 then return nil end
    local extra = n - #s.list
    local entries = { { kind = "enemy", count = math.min(30, 3 + s.growth * (extra - 1)) } }
    if s.bossEvery > 0 and n % s.bossEvery == 0 then
        entries[#entries + 1] = { kind = "boss", count = 1 }
    end
    return entries
end

local function lastWave()
    local s = S()
    if s.total > 0 then return s.total end
    if not s.endless then return #s.list end
    return nil
end

local function spawnEntry(entry)
    local room = AC.game:GetRoom()
    for _ = 1, entry.count or 1 do
        local et, ev, es
        if entry.kind == "entity" then
            et, ev, es = P.parseEntity(entry.ent)
        else
            local list = entry.kind == "boss" and AC.data.BOSSES or AC.data.ENEMIES
            local pick = list[math.random(#list)]
            et, ev, es = pick[2], pick[3], 0
        end
        local pos = Isaac.GetFreeNearPosition(room:GetRandomPosition(60), 40)
        local e = Isaac.Spawn(et, ev, es, pos, Vector.Zero, nil)
        local npc = e and e:ToNPC()
        if npc then
            engine.setLabel(npc, "wave", true)
            if entry.champion and not npc:IsBoss() then npc:MakeChampion(Random(), -1, true) end
        end
    end
end

local function banner(text, color)
    AC.ruleEffects.texts["__big"] = { text = text, center = true, scale = 3, fade = true,
        color = color or { 1, 0.9, 0.3, 1 }, untilFrame = Isaac.GetFrameCount() + 120 }
end

function feature.stop(victory)
    if W.state == "idle" then return end
    W.state = "idle"
    if S().lockDoors then AC.ruleEffects.doors("open") end
    if victory then
        banner(t("waves_victory"), { 0.4, 1, 0.5, 1 })
        engine.emit("waves_done", { value = W.wave })
    end
end

local function nextWave()
    local entries = waveEntries(W.wave + 1)
    if not entries then
        feature.stop(true)
        return
    end
    W.wave = W.wave + 1
    for _, entry in ipairs(entries) do spawnEntry(entry) end
    if S().lockDoors then AC.ruleEffects.doors("close") end
    W.state, W.spawnedAt, W.timer = "fighting", engine.frame, S().interval * 30
    banner(t("wave_n", W.wave))
    engine.emit("wave_start", { value = W.wave })
end

function feature.start()
    W.room = AC.game:GetLevel():GetCurrentRoomIndex()
    W.wave = 0
    AC.menu.setOpen(false)
    nextWave()
end

local function reward()
    local r = REWARD_SPAWN[S().reward]
    if not r then return end
    local pos = AC.game:GetRoom():FindFreePickupSpawnPosition(AC.game:GetRoom():GetCenterPos(), 0, true)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, r[1], r[2], pos, Vector.Zero, nil)
end

local function waveCleared()
    engine.emit("wave_clear", { value = W.wave })
    reward()
    local last = lastWave()
    if last and W.wave >= last then
        feature.stop(true)
    else
        W.state, W.timer = "pause", S().pause * 30
    end
end

local function onUpdate()
    if W.state == "idle" then return end
    if AC.game:GetLevel():GetCurrentRoomIndex() ~= W.room then
        feature.stop(false)
        return
    end
    W.timer = W.timer - 1
    if W.state == "fighting" then
        local cleared = engine.frame - W.spawnedAt > 30 and #util.enemies() == 0
        if cleared then
            waveCleared()
        elseif S().mode == "timer" and W.timer <= 0 then
            local last = lastWave()
            if last and W.wave >= last then W.timer = 30 else nextWave() end
        end
    elseif W.state == "pause" and W.timer <= 0 then
        nextWave()
    end
end

local function onRender()
    if W.state == "idle" then return end
    local last = lastWave()
    local s = last and t("wave_of", W.wave, last) or t("wave_n", W.wave)
    if W.state == "pause" then
        s = s .. "  " .. t("next_in", math.max(0, math.ceil(W.timer / 30)))
    else
        s = s .. "  " .. t("enemies_left", #util.enemies())
        if S().mode == "timer" then s = s .. "  " .. t("next_in", math.max(0, math.ceil(W.timer / 30))) end
    end
    local x = (Isaac.GetScreenWidth() - AC.render.textWidth(s)) / 2
    AC.render.text(s, x, 12, { 1, 0.9, 0.4, 1 })
end

-- Rule integration --------------------------------------------------------------------------------

engine.defineEvent({ id = "wave_start", label = "ev_wave_start" })
engine.defineEvent({ id = "wave_clear", label = "ev_wave_clear" })
engine.defineEvent({ id = "waves_done", label = "ev_waves_done" })
engine.defineCondition({ id = "wave_number", label = "c_wave_number",
    params = { P.choice("op", "compare", "ge", P.COMPARE), P.number("value", "amount", 5, 0, 999) },
    check = function(p) return engine.compare(W.wave, p.op, p.value) end })
engine.defineAction({ id = "waves_start", label = "a_waves_start", run = function() feature.start() end })
engine.defineAction({ id = "waves_stop", label = "a_waves_stop", run = function() feature.stop(false) end })

-- Menu ------------------------------------------------------------------------------------------

local function entryLabel(i, e)
    local what
    if e.kind == "entity" then what = e.ent else what = t(e.kind == "boss" and "kind_boss" or "kind_enemy") end
    return t("wave_entry", i, e.count, what) .. (e.champion and " *" or "")
end

local function wavePage(entry)
    return {
        title = function() return t("m_wave_edit") end,
        build = function()
            local items = {
                { kind = "choice", label = t("kind"), options = function()
                    local out = {}
                    for _, o in ipairs(KINDS) do out[#out + 1] = { t(o[1]), o[2] } end
                    return out
                end, get = function() return entry.kind end, set = function(v) entry.kind = v end },
            }
            if entry.kind == "entity" then
                items[#items + 1] = { kind = "text", label = t("entity") .. " (t.v.s)",
                    get = function() return entry.ent end, set = function(v) entry.ent = v end }
                items[#items + 1] = menu.link("  " .. t("pick_from_list"), function()
                    return AC.ruleEditor.entityPicker({ key = "ent", label = "entity" }, entry)
                end)
            end
            items[#items + 1] = { kind = "number", label = t("count"), min = 1, max = 30, step = 1,
                get = function() return entry.count end, set = function(v) entry.count = v end }
            items[#items + 1] = { kind = "toggle", label = t("as_champion"),
                get = function() return entry.champion end, set = function(v) entry.champion = v end }
            items[#items + 1] = menu.action(t("delete"), function()
                local list = S().list
                for i = #list, 1, -1 do if list[i] == entry then table.remove(list, i) end end
                menu.pop()
            end)
            return items
        end,
    }
end

feature.pages = {
    waves = {
        title = function() return t("m_waves") end,
        build = function()
            local s = S()
            local items = {}
            if W.state == "idle" then
                items[#items + 1] = menu.action(t("waves_start"), feature.start)
            else
                items[#items + 1] = menu.action(t("waves_stop"), function() feature.stop(false) end)
                items[#items + 1] = menu.info(t("wave_n", W.wave))
            end
            items[#items + 1] = menu.link(t("waves_list", #s.list), "waves_list")
            items[#items + 1] = menu.choice(t("waves_mode"), "waves", "mode", function()
                return { { t("wm_clear"), "clear" }, { t("wm_timer"), "timer" } }
            end)
            if s.mode == "timer" then
                items[#items + 1] = menu.number(t("waves_interval"), "waves", "interval", 3, 300, 1)
            end
            items[#items + 1] = menu.number(t("waves_pause"), "waves", "pause", 0, 60, 1)
            items[#items + 1] = {
                kind = "number", label = t("waves_total"), min = 0, max = 999, step = 1,
                get = function() return s.total end, set = function(v) s.total = v end,
                fmt = function(v) return v == 0 and t("waves_unlimited") or tostring(v) end,
            }
            items[#items + 1] = menu.toggle(t("waves_endless"), "waves", "endless")
            if s.endless then
                items[#items + 1] = menu.number("  " .. t("waves_growth"), "waves", "growth", 0, 10, 1)
                items[#items + 1] = {
                    kind = "number", label = "  " .. t("waves_boss_every"), min = 0, max = 50, step = 1,
                    get = function() return s.bossEvery end, set = function(v) s.bossEvery = v end,
                    fmt = function(v) return v == 0 and t("off") or tostring(v) end,
                }
            end
            items[#items + 1] = menu.choice(t("waves_reward"), "waves", "reward", function()
                local out = {}
                for _, o in ipairs(REWARDS) do out[#out + 1] = { t(o[1]), o[2] } end
                return out
            end)
            items[#items + 1] = menu.toggle(t("waves_lock"), "waves", "lockDoors")
            items[#items + 1] = menu.info(t("waves_hint"))
            return items
        end,
    },
    waves_list = {
        title = function() return t("waves_list", #S().list) end,
        build = function()
            local items = {}
            for i, e in ipairs(S().list) do
                items[#items + 1] = menu.link(entryLabel(i, e), function() return wavePage(e) end)
            end
            items[#items + 1] = menu.action("+ " .. t("waves_add"), function()
                local e = { kind = "enemy", ent = "10.0.0", count = 5, champion = false }
                table.insert(S().list, e)
                menu.push(wavePage(e))
            end)
            items[#items + 1] = menu.action(t("waves_reset_list"), function()
                S().list = AC.util.copy(AC.save.defaults.waves.list)
            end)
            return items
        end,
    },
}

feature.callbacks = {
    { ModCallbacks.MC_POST_UPDATE, onUpdate },
    { ModCallbacks.MC_POST_RENDER, onRender },
    { ModCallbacks.MC_POST_GAME_STARTED, function() W.state = "idle" end },
}

function feature.reset()
    feature.stop(false)
end

return feature
