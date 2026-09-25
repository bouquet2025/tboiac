-- Studio: tools for recording videos.
--   Scenarios  - rules with the "manual" event, started from the menu, a hotkey or another rule
--   Hotkeys    - key_press rules, created and listed in one place
--   Overlay    - stopwatch, active rules list, counters, custom text lines
--   Clean frame- hides HUD, toasts and overlay (F3 by default)
--   Profiles   - save/load every setting and rule into named slots
local AC = TBOIAC
local menu, util, engine, P = AC.menu, AC.util, AC.rules, AC.ruleParams
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "studio", label = "m_studio" }

local function S() return AC.save.data.studio end

-- Stopwatch (counts game updates, so it pauses with the game) --------------------------------------

local stopwatch = { frames = 0, running = false }
feature.stopwatch = stopwatch

local function stopwatchText()
    local total = stopwatch.frames / 30
    return string.format("%02d:%05.2f", math.floor(total / 60), total % 60)
end

local function stopwatchControl(mode)
    if mode == "start" then stopwatch.running = true
    elseif mode == "pause" then stopwatch.running = false
    elseif mode == "toggle" then stopwatch.running = not stopwatch.running
    else stopwatch.frames, stopwatch.running = 0, false end
end

-- Options that rules/hotkeys can switch ------------------------------------------------------------

local function recache()
    for _, p in ipairs(util.players()) do
        p:AddCacheFlags(CacheFlag.CACHE_ALL)
        p:EvaluateItems()
    end
end

local function setClean(v)
    S().clean = v
    AC.game:GetHUD():SetVisible(not v)
    if v and AC.menu.open then AC.menu.setOpen(false) end
end

-- id -> { get, set }
local OPTIONS = {
    god = { function() return AC.save.data.player.god end, function(v) AC.save.data.player.god = v end },
    one_hit = { function() return AC.save.data.player.oneHit end, function(v) AC.save.data.player.oneHit = v end },
    flight = { function() return AC.save.data.player.flight end,
               function(v) AC.save.data.player.flight = v recache() end },
    noclip = { function() return AC.save.data.player.noclip end, function(v) AC.save.data.player.noclip = v end },
    inf_all = { function() return AC.save.data.player.infCoins end, function(v)
        local pl = AC.save.data.player
        pl.infCoins, pl.infBombs, pl.infKeys = v, v, v
    end },
    freeze_enemies = { function() return AC.save.data.time.freezeEnemies end,
                       function(v) AC.save.data.time.freezeEnemies = v end },
    freeze_projectiles = { function() return AC.save.data.time.freezeProjectiles end,
                           function(v) AC.save.data.time.freezeProjectiles = v end },
    slow_motion = { function() return AC.save.data.time.mode == 1 end,
                    function(v) AC.save.data.time.mode = v and 1 or 0 end },
    hide_hud = { function() return not AC.game:GetHUD():IsVisible() end,
                 function(v) AC.game:GetHUD():SetVisible(not v) end },
    clean_frame = { function() return S().clean end, setClean },
    pools_enabled = { function() return AC.save.data.pools.enabled end, function(v) AC.save.data.pools.enabled = v end },
    drops_enabled = { function() return AC.save.data.drops.enabled end, function(v) AC.save.data.drops.enabled = v end },
    rules_enabled = { function() return AC.save.data.rules.enabled end, function(v) AC.save.data.rules.enabled = v end },
}
local OPTION_ORDER = { "god", "one_hit", "flight", "noclip", "inf_all", "freeze_enemies", "freeze_projectiles",
    "slow_motion", "hide_hud", "clean_frame", "pools_enabled", "drops_enabled", "rules_enabled" }
local OPTION_LABELS = { god = "god", one_hit = "one_hit", flight = "flight", noclip = "noclip",
    inf_all = "opt_inf_all", freeze_enemies = "freeze_enemies", freeze_projectiles = "freeze_projectiles",
    slow_motion = "time_slow", hide_hud = "hide_hud", clean_frame = "clean_frame",
    pools_enabled = "pools_enabled", drops_enabled = "drops_enabled", rules_enabled = "rules_enabled" }

local function optionList()
    local out = {}
    for _, id in ipairs(OPTION_ORDER) do out[#out + 1] = { OPTION_LABELS[id], id } end
    return out
end

-- Rule pieces -----------------------------------------------------------------------------------

engine.defineEvent({ id = "manual", label = "ev_manual" }) -- never emitted: scenarios run on demand

engine.defineAction({ id = "run_rule", label = "a_run_rule", params = { P.number("rule", "rule_id", 1, 1, 9999) },
    run = function(p, _, rule)
        local target = engine.findRule(p.rule)
        if target and target ~= rule then engine.test(target) end
    end })

engine.defineAction({ id = "toggle_option", label = "a_toggle_option",
    params = { P.choice("option", "option", "god", optionList),
               P.choice("mode", "mode", "toggle", { { "on", "on" }, { "off", "off" }, { "toggle", "toggle" } }) },
    run = function(p)
        local opt = OPTIONS[p.option]
        if not opt then return end
        local v = p.mode == "on" or (p.mode == "toggle" and not opt[1]())
        opt[2](v)
        AC.render.toast(t(OPTION_LABELS[p.option]) .. ": " .. (v and t("on") or t("off")))
    end })

engine.defineAction({ id = "stopwatch", label = "a_stopwatch",
    params = { P.choice("mode", "mode", "toggle", { { "sw_start", "start" }, { "sw_pause", "pause" },
                                                  { "toggle", "toggle" }, { "sw_reset", "reset" } }) },
    run = function(p) stopwatchControl(p.mode) end })

engine.defineAction({ id = "stop_scenarios", label = "a_stop_scenarios", run = function() engine.queue = {} end })

-- Profiles --------------------------------------------------------------------------------------

local PROFILE_KEYS = { "player", "time", "enemies", "world", "rules", "pools", "waves", "drops", "studio" }

local function snapshot()
    local data = {}
    for _, k in ipairs(PROFILE_KEYS) do data[k] = util.copy(AC.save.data[k]) end
    return data
end

function feature.loadProfile(profile)
    for _, k in ipairs(PROFILE_KEYS) do
        if profile.data[k] then
            AC.save.data[k] = util.merge(util.copy(profile.data[k]), AC.save.defaults[k])
        end
    end
    engine.queue = {}
    recache()
    AC.game:GetHUD():SetVisible(not S().clean)
    AC.save.write()
    AC.render.toast(t("profile_loaded", profile.name))
end

-- Slots are stored under string keys ("s1".."s8") so the JSON never holds a sparse array.
local function slotKey(slot) return "s" .. slot end

function feature.getProfile(slot) return AC.save.data.profiles[slotKey(slot)] end

function feature.saveProfile(slot, name)
    local list = AC.save.data.profiles
    list[slotKey(slot)] = { name = name or t("profile_n", slot), data = snapshot() }
    AC.save.write()
    AC.render.toast(t("profile_saved", list[slotKey(slot)].name))
end

local function profilePage(slot)
    local confirm = false
    return {
        title = function()
            local p = feature.getProfile(slot)
            return p and p.name or t("profile_empty", slot)
        end,
        build = function()
            local list = AC.save.data.profiles
            local p = list[slotKey(slot)]
            local items = {}
            if p then
                items[#items + 1] = { kind = "text", label = t("rule_name"), get = function() return p.name end,
                                      set = function(v) p.name = v end }
                items[#items + 1] = menu.action(t("profile_load"), function() feature.loadProfile(p) end)
            end
            items[#items + 1] = menu.action(p and t("profile_overwrite") or t("profile_save"), function()
                feature.saveProfile(slot, p and p.name)
            end)
            if p then
                items[#items + 1] = menu.action(confirm and t("confirm_delete") or t("delete"), function()
                    if confirm then
                        list[slotKey(slot)] = nil
                        menu.pop()
                    else
                        confirm = true
                    end
                end)
            end
            return items
        end,
    }
end

local PROFILE_SLOTS = 8

-- Overlay rendering -----------------------------------------------------------------------------

local function drawOverlay()
    local s = S()
    if s.clean then return end
    local white, yellow = { 1, 1, 1, 1 }, { 1, 0.9, 0.4, 1 }
    if s.timer.show then
        AC.render.text(stopwatchText(), s.timer.x, s.timer.y, stopwatch.running and white or yellow, 1.5)
    end
    if s.showRules then
        local y = s.rulesY
        AC.render.text(t("overlay_rules_title"), s.rulesX, y, yellow)
        for _, r in ipairs(AC.save.data.rules.list) do
            if r.enabled and r.event.id ~= "manual" then
                y = y + AC.render.lineHeight()
                AC.render.text("- " .. r.name, s.rulesX, y, white)
            end
        end
    end
    if s.showCounters then
        local y = s.countersY
        local run = engine.run()
        local names = {}
        for name in pairs(run.counters) do names[#names + 1] = name end
        table.sort(names)
        for _, name in ipairs(names) do
            AC.render.text(name .. ": " .. tostring(run.counters[name]), s.countersX, y, white)
            y = y + AC.render.lineHeight()
        end
    end
    for _, line in ipairs(s.lines) do
        if line.show and line.text ~= "" then
            AC.render.text(AC.ruleEffects.format(line.text), line.x, line.y, white)
        end
    end
end

local function onRender()
    if AC.input.keyEdge(S().cleanKey) and not AC.input.textTarget and not AC.imgui.active() then
        setClean(not S().clean)
    end
    drawOverlay()
end

local function onUpdate()
    if stopwatch.running then stopwatch.frames = stopwatch.frames + 1 end
end

-- Menu ------------------------------------------------------------------------------------------

local function rulesWithEvent(id)
    local out = {}
    for _, r in ipairs(AC.save.data.rules.list) do
        if r.event.id == id then out[#out + 1] = r end
    end
    return out
end

local function keyName(k)
    for _, o in ipairs(P.keys()) do if o[2] == k then return o[1] end end
    return tostring(k)
end

local function position(label, tbl, kx, ky)
    return {
        { kind = "number", label = "  " .. label .. " X", min = 0, max = 1000, step = 5,
          get = function() return tbl[kx] end, set = function(v) tbl[kx] = v end },
        { kind = "number", label = "  " .. label .. " Y", min = 0, max = 600, step = 5,
          get = function() return tbl[ky] end, set = function(v) tbl[ky] = v end },
    }
end

local function append(items, list)
    for _, it in ipairs(list) do items[#items + 1] = it end
end

feature.pages = {
    studio = {
        title = function() return t("m_studio") end,
        build = function()
            return {
                menu.link(t("m_scenarios"), "studio_scenarios"),
                menu.link(t("m_hotkeys"), "studio_hotkeys"),
                menu.link(t("m_overlay"), "studio_overlay"),
                menu.link(t("m_profiles"), "studio_profiles"),
                { kind = "toggle", label = t("clean_frame"), get = function() return S().clean end, set = setClean },
                menu.info(t("clean_hint", keyName(S().cleanKey))),
            }
        end,
    },
    studio_scenarios = {
        title = function() return t("m_scenarios") end,
        build = function()
            local items = { menu.info(t("scenarios_hint")) }
            for _, r in ipairs(rulesWithEvent("manual")) do
                items[#items + 1] = menu.action("> " .. r.name .. "  #" .. r.id, function()
                    AC.menu.setOpen(false)
                    engine.test(r)
                end)
                items[#items + 1] = menu.link("    " .. t("edit"), function() return AC.ruleEditor.rulePage(r) end)
            end
            items[#items + 1] = menu.action("+ " .. t("new_scenario"), function()
                local r = engine.newRule("manual")
                r.name = t("scenario_n", r.id)
                menu.push(AC.ruleEditor.rulePage(r))
            end)
            items[#items + 1] = menu.action(t("a_stop_scenarios"), function() engine.queue = {} end)
            return items
        end,
    },
    studio_hotkeys = {
        title = function() return t("m_hotkeys") end,
        build = function()
            local items = { menu.info(t("hotkeys_hint")) }
            for _, r in ipairs(rulesWithEvent("key_press")) do
                local first = r.acts[1]
                local what = first and t(engine.actions[first.id] and engine.actions[first.id].label or "?") or t("empty")
                items[#items + 1] = menu.link(string.format("[%s] %s - %s%s", keyName(r.event.p.key), r.name, what,
                    r.enabled and "" or " (" .. t("off") .. ")"), function() return AC.ruleEditor.rulePage(r) end)
            end
            items[#items + 1] = menu.action("+ " .. t("new_hotkey"), function()
                local r = engine.newRule("key_press")
                r.name = t("hotkey_n", r.id)
                menu.push(AC.ruleEditor.rulePage(r))
            end)
            items[#items + 1] = menu.choice(t("clean_key"), "studio", "cleanKey", P.keys)
            return items
        end,
    },
    studio_overlay = {
        title = function() return t("m_overlay") end,
        build = function()
            local s = S()
            local items = {
                { kind = "toggle", label = t("clean_frame"), get = function() return s.clean end, set = setClean },
                menu.info(t("stopwatch_title", stopwatchText())),
                { kind = "toggle", label = "  " .. t("show"), get = function() return s.timer.show end,
                  set = function(v) s.timer.show = v end },
                menu.action("  " .. (stopwatch.running and t("sw_pause") or t("sw_start")),
                    function() stopwatchControl("toggle") end),
                menu.action("  " .. t("sw_reset"), function() stopwatchControl("reset") end),
            }
            append(items, position(t("stopwatch"), s.timer, "x", "y"))
            items[#items + 1] = menu.toggle(t("overlay_rules"), "studio", "showRules")
            append(items, position(t("overlay_rules"), s, "rulesX", "rulesY"))
            items[#items + 1] = menu.toggle(t("overlay_counters"), "studio", "showCounters")
            append(items, position(t("overlay_counters"), s, "countersX", "countersY"))
            for i, line in ipairs(s.lines) do
                items[#items + 1] = menu.info(t("overlay_line", i))
                items[#items + 1] = { kind = "text", label = "  " .. t("text"), get = function() return line.text end,
                                      set = function(v) line.text = v end }
                items[#items + 1] = { kind = "toggle", label = "  " .. t("show"), get = function() return line.show end,
                                      set = function(v) line.show = v end }
                append(items, position(t("overlay_line", i), line, "x", "y"))
            end
            items[#items + 1] = menu.info(t("overlay_hint"))
            return items
        end,
    },
    studio_profiles = {
        title = function() return t("m_profiles") end,
        build = function()
            local items = { menu.info(t("profiles_hint")) }
            for slot = 1, PROFILE_SLOTS do
                local p = feature.getProfile(slot)
                items[#items + 1] = menu.link(string.format("%d. %s", slot, p and p.name or t("profile_free")),
                    function() return profilePage(slot) end)
            end
            items[#items + 1] = menu.action(t("factory_reset"), function()
                for _, k in ipairs(PROFILE_KEYS) do
                    if k ~= "rules" then AC.save.data[k] = util.copy(AC.save.defaults[k]) end
                end
                recache()
                AC.game:GetHUD():SetVisible(true)
                AC.render.toast(t("factory_done"))
            end)
            return items
        end,
    },
}

feature.callbacks = {
    { ModCallbacks.MC_POST_RENDER, onRender },
    { ModCallbacks.MC_POST_UPDATE, onUpdate },
}

function feature.reset()
    if S().clean then setClean(false) end
end

return feature
