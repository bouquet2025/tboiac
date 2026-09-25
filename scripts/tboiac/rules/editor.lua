-- Rules menu: rule list, rule editor, conditions/actions editors, presets, variables.
local AC = TBOIAC
local menu, util, engine, P = AC.menu, AC.util, AC.rules, AC.ruleParams
local t = function(...) return AC.i18n.t(...) end
local L = function(s) return AC.i18n.label(s) end

local feature = { id = "rules", label = "m_rules" }

-- Param widgets --------------------------------------------------------------------------------

local function options(spec)
    local list = type(spec.options) == "function" and spec.options() or spec.options
    local out = {}
    for _, o in ipairs(list) do out[#out + 1] = { L(o[1]), o[2] } end
    return out
end

local function catalogPicker(spec, p)
    local cat = util.catalogs[spec.catalog]
    return AC.catalog.page({
        title = function() return t(spec.label) end,
        ids = function() return AC.catalog.range(cat.ids()) end,
        name = cat.name,
        alias = cat.alias,
        icon = cat.icon,
        pick = function(id)
            p[spec.key] = id
            menu.pop()
        end,
    })
end

local function entityPicker(spec, p)
    local function list(title, entries)
        return {
            title = function() return t(title) end,
            build = function()
                local items = {}
                for _, e in ipairs(entries) do
                    local it = menu.action(string.format("%s  %d.%d", util.entityName(e[2], e[3], e[1]), e[2], e[3]), function()
                        p[spec.key] = e[2] .. "." .. e[3] .. ".0"
                        menu.pop()
                        menu.pop()
                    end)
                    it.preview = function(pos) AC.icons.entity(e[2], e[3], pos) end
                    items[#items + 1] = it
                end
                return items
            end,
        }
    end
    return {
        title = function() return t(spec.label) end,
        build = function()
            return {
                menu.link(t("m_bosses"), list("m_bosses", AC.data.BOSSES)),
                menu.link(t("m_enemies_common"), list("m_enemies_common", AC.data.ENEMIES)),
            }
        end,
    }
end

-- Widgets editing table `p` according to param specs.
local function paramWidgets(specs, p, items)
    for _, spec in ipairs(specs) do
        local label = t(spec.label)
        local get = function() return p[spec.key] end
        local set = function(v) p[spec.key] = v end
        if spec.kind == "number" then
            items[#items + 1] = { kind = "number", label = label, min = spec.min, max = spec.max, step = spec.step,
                                  get = get, set = set }
        elseif spec.kind == "choice" then
            items[#items + 1] = { kind = "choice", label = label, options = function() return options(spec) end,
                                  get = get, set = set }
        elseif spec.kind == "toggle" then
            items[#items + 1] = { kind = "toggle", label = label, get = get, set = set }
        elseif spec.kind == "text" then
            items[#items + 1] = { kind = "text", label = label, get = get, set = set }
        elseif spec.kind == "catalog" then
            local cat = util.catalogs[spec.catalog]
            local lo, hi = cat.ids()
            items[#items + 1] = {
                kind = "number", label = label, min = spec.zero and 0 or lo, max = hi, step = 1, get = get, set = set,
                fmt = function(v)
                    if v == 0 and spec.zero then return t(spec.zero) end
                    return (cat.name(v) or "?") .. " #" .. v
                end,
            }
            items[#items + 1] = menu.link("  " .. t("pick_from_list"), function() return catalogPicker(spec, p) end)
        elseif spec.kind == "entity" then
            items[#items + 1] = { kind = "text", label = label .. " (t.v.s)", get = get, set = set }
            items[#items + 1] = menu.link("  " .. t("pick_from_list"), function() return entityPicker(spec, p) end)
        end
    end
end

-- Labels ---------------------------------------------------------------------------------------

local function defLabel(store, id)
    local def = store[id]
    return def and t(def.label) or ("? " .. tostring(id))
end

local function ruleLabel(rule)
    return string.format("%s #%d %s - %s", rule.enabled and "[+]" or "[-]", rule.id, rule.name,
        defLabel(engine.events, rule.event.id))
end

local FILTER_MODES = {
    { "f_any", "any" }, { "f_enemy", "enemy" }, { "f_boss", "boss" }, { "f_player", "player" },
    { "f_pickup", "pickup" }, { "f_exact", "exact" }, { "f_label", "label" }, { "f_list", "list" },
}

local SCOPES = { { "scope_always", "always" }, { "scope_run", "run" }, { "scope_chapter", "chapter" } }

-- Rule diagram (side panel) ------------------------------------------------------------------------

local function paramSummary(def, p)
    local parts = {}
    for _, spec in ipairs(def.params or {}) do
        local v = p and p[spec.key]
        if v ~= nil and spec.kind ~= "toggle" then
            if spec.kind == "choice" then
                for _, o in ipairs(options(spec)) do if o[2] == v then v = o[1] end end
            elseif spec.kind == "catalog" then
                v = (v == 0 and spec.zero) and t(spec.zero) or (util.catalogs[spec.catalog].name(v) or v)
            end
            parts[#parts + 1] = tostring(v)
        end
        if #parts >= 3 then break end
    end
    return table.concat(parts, ", ")
end

local BLOCKS = {
    when = { 0.35, 0.6, 1 }, ["if"] = { 1, 0.8, 0.3 }, ["then"] = { 0.4, 1, 0.5 },
}

-- Draws WHEN -> IF -> THEN boxes for a rule at (x, y), `w` wide. Returns the height used.
local function drawRuleDiagram(rule, x, y, w)
    local lh = AC.render.lineHeight() * 0.85
    local y0 = y
    local function block(kind, title, lines)
        local c = BLOCKS[kind]
        local h = lh + 4 + math.max(1, #lines) * lh + 4
        AC.render.rect(x, y, w, h, { c[1], c[2], c[3], 0.12 })
        AC.menu.border(x, y, w, h, { c[1], c[2], c[3], 0.7 })
        AC.render.rect(x, y, w, lh + 3, { c[1], c[2], c[3], 0.3 })
        AC.render.text(title, x + 4, y + 1, { c[1], c[2], c[3], 1 }, 0.85)
        local ly = y + lh + 5
        if #lines == 0 then
            AC.render.text(t("diagram_none"), x + 4, ly, { 0.6, 0.6, 0.65, 1 }, 0.85)
        end
        for _, line in ipairs(lines) do
            AC.render.text(AC.menu.fit(line, w - 8, 0.85), x + 4, ly, { 1, 1, 1, 1 }, 0.85)
            ly = ly + lh
        end
        y = y + h
    end
    local function arrow()
        AC.render.text("v", x + w / 2 - 3, y, { 0.8, 0.8, 0.85, 1 }, 0.85)
        y = y + lh
    end
    local ev = engine.events[rule.event.id]
    local whenLines = {}
    if ev then
        whenLines[1] = t(ev.label)
        local sum = paramSummary(ev, rule.event.p)
        if sum ~= "" then whenLines[#whenLines + 1] = sum end
        if ev.entity and rule.filter and rule.filter.mode ~= "any" then
            whenLines[#whenLines + 1] = t("filter") .. ": " .. t("f_" .. rule.filter.mode)
        end
    end
    if rule.scope ~= "always" then whenLines[#whenLines + 1] = t("scope_" .. rule.scope) end
    block("when", t("when"), whenLines)
    arrow()
    local ifLines = {}
    for i, c in ipairs(rule.conds or {}) do
        if i > 5 then ifLines[#ifLines + 1] = "+" .. (#rule.conds - 5) break end
        local def = engine.conditions[c.id]
        local line = (c.neg and (t("not") .. " ") or "") .. (def and t(def.label) or c.id)
        local sum = def and paramSummary(def, c.p) or ""
        if sum ~= "" then line = line .. ": " .. sum end
        ifLines[#ifLines + 1] = line
    end
    local logic = #ifLines > 1 and (" (" .. t(rule.logic == "or" and "logic_or" or "logic_and") .. ")") or ""
    block("if", t("if") .. logic, ifLines)
    arrow()
    local thenLines = {}
    for i, a in ipairs(rule.acts or {}) do
        if i > 6 then thenLines[#thenLines + 1] = "+" .. (#rule.acts - 6) break end
        local def = engine.actions[a.id]
        local line = i .. ". " .. (def and t(def.label) or a.id)
        if (a.delay or 0) > 0 then line = line .. string.format(" (+%gs)", a.delay) end
        thenLines[#thenLines + 1] = line
    end
    block("then", t("then"), thenLines)
    if not rule.enabled then
        AC.render.text(t("rule_disabled"), x, y + 2, { 1, 0.45, 0.45, 1 }, 0.85)
        y = y + lh + 2
    end
    return y - y0
end
feature.drawRuleDiagram = drawRuleDiagram

-- Pages ----------------------------------------------------------------------------------------

local rulePage, conditionPage, actionPage

local function swap(list, i, j)
    if list[i] and list[j] then list[i], list[j] = list[j], list[i] end
end

local function indexOf(list, item)
    for i, v in ipairs(list) do if v == item then return i end end
    return nil
end

local function typePicker(title, order, store, onPick)
    return {
        title = function() return t(title) end,
        build = function()
            local items = {}
            for _, id in ipairs(order) do
                items[#items + 1] = menu.action(t(store[id].label), function() onPick(id) end)
            end
            return items
        end,
    }
end

conditionPage = function(rule, cond)
    return {
        title = function() return defLabel(engine.conditions, cond.id) end,
        build = function()
            local def = engine.conditions[cond.id]
            cond.p = cond.p or {}
            for k, v in pairs(engine.defaults(def)) do if cond.p[k] == nil then cond.p[k] = v end end
            local items = { { kind = "toggle", label = t("negate"),
                              get = function() return cond.neg == true end, set = function(v) cond.neg = v end } }
            paramWidgets(def.params, cond.p, items)
            items[#items + 1] = menu.action(t("delete"), function()
                local i = indexOf(rule.conds, cond)
                if i then table.remove(rule.conds, i) end
                menu.pop()
            end)
            return items
        end,
    }
end

actionPage = function(rule, act)
    return {
        title = function() return defLabel(engine.actions, act.id) end,
        build = function()
            local def = engine.actions[act.id]
            act.p = act.p or {}
            for k, v in pairs(engine.defaults(def)) do if act.p[k] == nil then act.p[k] = v end end
            local items = {}
            paramWidgets(def.params, act.p, items)
            items[#items + 1] = { kind = "number", label = t("delay_before"), min = 0, max = 600, step = 0.5,
                                  get = function() return act.delay or 0 end, set = function(v) act.delay = v end }
            items[#items + 1] = menu.action(t("run_now"), function()
                engine.runAction(act, { player = util.firstTarget() }, rule)
            end)
            items[#items + 1] = menu.action(t("move_up"), function()
                local i = indexOf(rule.acts, act)
                if i then swap(rule.acts, i, i - 1) end
            end)
            items[#items + 1] = menu.action(t("move_down"), function()
                local i = indexOf(rule.acts, act)
                if i then swap(rule.acts, i, i + 1) end
            end)
            items[#items + 1] = menu.action(t("delete"), function()
                local i = indexOf(rule.acts, act)
                if i then table.remove(rule.acts, i) end
                menu.pop()
            end)
            return items
        end,
    }
end

rulePage = function(rule)
    local confirmDelete = false
    return {
        title = function() return "#" .. rule.id .. " " .. rule.name end,
        side = function(x, y, w) return drawRuleDiagram(rule, x, y, w) end,
        build = function()
            local ev = engine.events[rule.event.id]
            local items = {
                { kind = "text", label = t("rule_name"), get = function() return rule.name end,
                  set = function(s) rule.name = s end },
                { kind = "toggle", label = t("enabled"), get = function() return rule.enabled end,
                  set = function(v) rule.enabled = v end },
                menu.info("- " .. t("when") .. " -"),
                { kind = "choice", label = t("event"),
                  options = function()
                      local list = {}
                      for _, id in ipairs(engine.eventOrder) do list[#list + 1] = { t(engine.events[id].label), id } end
                      return list
                  end,
                  get = function() return rule.event.id end,
                  set = function(id) rule.event = { id = id, p = engine.defaults(engine.events[id]) } end },
            }
            if ev then
                rule.event.p = rule.event.p or {}
                for k, v in pairs(engine.defaults(ev)) do if rule.event.p[k] == nil then rule.event.p[k] = v end end
                paramWidgets(ev.params, rule.event.p, items)
                if ev.entity then
                    local f = rule.filter
                    items[#items + 1] = { kind = "choice", label = t("filter"),
                        options = function()
                            local out = {}
                            for _, o in ipairs(FILTER_MODES) do out[#out + 1] = { t(o[1]), o[2] } end
                            return out
                        end,
                        get = function() return f.mode end, set = function(v) f.mode = v end }
                    if f.mode == "label" or f.mode == "list" then
                        items[#items + 1] = { kind = "text", label = "  " .. t(f.mode == "label" and "label_name" or "list_name"),
                            get = function() return f.name or "a" end, set = function(v) f.name = v end }
                    end
                    if f.mode == "exact" then
                        for _, k in ipairs({ { "t", "type" }, { "v", "variant" }, { "s", "subtype" } }) do
                            items[#items + 1] = { kind = "number", label = "  " .. t(k[2]), min = -1, max = 5000, step = 1,
                                fmt = function(v) return v < 0 and t("any") or tostring(v) end,
                                get = function() return f[k[1]] end, set = function(v) f[k[1]] = v end }
                        end
                    end
                end
            end
            items[#items + 1] = { kind = "choice", label = t("scope"),
                options = function()
                    local out = {}
                    for _, o in ipairs(SCOPES) do out[#out + 1] = { t(o[1]), o[2] } end
                    return out
                end,
                get = function() return rule.scope end, set = function(v) rule.scope = v end }
            if rule.scope == "chapter" then
                items[#items + 1] = { kind = "number", label = "  " .. t("chapter"), min = 1, max = 7, step = 1,
                    get = function() return rule.chapter or 1 end, set = function(v) rule.chapter = v end }
            end

            items[#items + 1] = menu.info("- " .. t("if") .. " -")
            items[#items + 1] = { kind = "choice", label = t("logic"),
                options = function() return { { t("logic_and"), "and" }, { t("logic_or"), "or" } } end,
                get = function() return rule.logic end, set = function(v) rule.logic = v end }
            for _, c in ipairs(rule.conds) do
                items[#items + 1] = menu.link((c.neg and (t("not") .. " ") or "") .. defLabel(engine.conditions, c.id),
                    function() return conditionPage(rule, c) end)
            end
            items[#items + 1] = menu.link("+ " .. t("add_condition"), function()
                return typePicker("add_condition", engine.conditionOrder, engine.conditions, function(id)
                    local c = { id = id, p = engine.defaults(engine.conditions[id]), neg = false }
                    table.insert(rule.conds, c)
                    menu.pop()
                    menu.push(conditionPage(rule, c))
                end)
            end)

            items[#items + 1] = menu.info("- " .. t("then") .. " -")
            for i, a in ipairs(rule.acts) do
                local delay = (a.delay or 0) > 0 and string.format(" (+%gs)", a.delay) or ""
                items[#items + 1] = menu.link(i .. ". " .. defLabel(engine.actions, a.id) .. delay,
                    function() return actionPage(rule, a) end)
            end
            items[#items + 1] = menu.link("+ " .. t("add_action"), function()
                return typePicker("add_action", engine.actionOrder, engine.actions, function(id)
                    local a = { id = id, p = engine.defaults(engine.actions[id]), delay = 0 }
                    table.insert(rule.acts, a)
                    menu.pop()
                    menu.push(actionPage(rule, a))
                end)
            end)

            items[#items + 1] = menu.info("")
            items[#items + 1] = menu.action(t("test_rule"), function() engine.test(rule) end)
            items[#items + 1] = menu.action(t("duplicate_rule"), function()
                local copy = engine.addRule(rule)
                copy.name = rule.name .. " (2)"
                AC.render.toast(t("rule_copied", copy.id))
            end)
            items[#items + 1] = menu.action(confirmDelete and t("confirm_delete") or t("delete_rule"), function()
                if confirmDelete then
                    engine.removeRule(rule)
                    menu.pop()
                else
                    confirmDelete = true
                end
            end)
            return items
        end,
    }
end

local confirmClear = false

feature.pages = {
    rules = {
        title = function() return t("m_rules") end,
        build = function()
            local S = engine.S()
            local items = {
                menu.toggle(t("rules_enabled"), "rules", "enabled"),
                menu.action("+ " .. t("new_rule"), function()
                    local rule = engine.newRule()
                    menu.push(rulePage(rule))
                end),
                menu.link(t("m_presets"), "rules_presets"),
                menu.link(t("m_variables"), "rules_variables"),
                menu.info(t("my_rules", #S.list)),
            }
            for _, rule in ipairs(S.list) do
                local link = menu.link(ruleLabel(rule), function() return rulePage(rule) end)
                link.side = function(x, y, w) return drawRuleDiagram(rule, x, y, w) end
                link.icon = rule.enabled and 33 or nil
                items[#items + 1] = link
            end
            if #S.list > 0 then
                items[#items + 1] = menu.action(confirmClear and t("confirm_delete") or t("delete_all_rules"), function()
                    if confirmClear then
                        S.list = {}
                        confirmClear = false
                    else
                        confirmClear = true
                    end
                end)
            end
            return items
        end,
    },
    rules_presets = {
        title = function() return t("m_presets") end,
        build = function()
            local items = { menu.info(t("presets_hint")) }
            for _, preset in ipairs(AC.rulePresets.list) do
                items[#items + 1] = menu.action(t(preset.name), function()
                    AC.rulePresets.apply(preset)
                    AC.render.toast(t("preset_loaded", t(preset.name)))
                end)
            end
            return items
        end,
    },
    rules_variables = {
        title = function() return t("m_variables") end,
        build = function()
            local run = engine.run()
            local items = { menu.info(t("variables_hint")) }
            for name, v in pairs(run.flags) do
                items[#items + 1] = { kind = "toggle", label = t("flag") .. " " .. name,
                    get = function() return run.flags[name] == true end,
                    set = function(val) engine.setFlag(name, val) end }
            end
            for name in pairs(run.counters) do
                items[#items + 1] = { kind = "number", label = t("counter") .. " " .. name, min = -9999, max = 9999,
                    get = function() return engine.counter(name) end,
                    set = function(val) engine.setCounter(name, val) end }
            end
            items[#items + 1] = menu.action(t("reset_variables"), function()
                run.flags, run.counters = {}, {}
            end)
            return items
        end,
    },
}

local function onCache(_, player, flag)
    local st = engine.run().stats
    if flag == CacheFlag.CACHE_DAMAGE then
        player.Damage = math.max(0.1, player.Damage + st.damage)
    elseif flag == CacheFlag.CACHE_FIREDELAY and st.tears ~= 0 then
        local tears = 30 / (player.MaxFireDelay + 1) + st.tears
        player.MaxFireDelay = 30 / math.max(0.1, tears) - 1
    elseif flag == CacheFlag.CACHE_SPEED then
        player.MoveSpeed = util.clamp(player.MoveSpeed + st.speed, 0.1, 5)
    elseif flag == CacheFlag.CACHE_RANGE then
        player.TearRange = math.max(40, player.TearRange + st.range * 40)
    elseif flag == CacheFlag.CACHE_SHOTSPEED then
        player.ShotSpeed = math.max(0.1, player.ShotSpeed + st.shotspeed)
    elseif flag == CacheFlag.CACHE_LUCK then
        player.Luck = player.Luck + st.luck
    end
end

feature.callbacks = { { ModCallbacks.MC_EVALUATE_CACHE, onCache } }

-- Shared with other menus: page picking a boss/enemy into p[spec.key] as "type.variant.0".
feature.entityPicker = entityPicker
-- Rule editor page for a rule (used by the Studio's scenarios and hotkeys pages).
feature.rulePage = function(rule) return rulePage(rule) end
for _, cb in ipairs(AC.ruleEvents.callbacks) do table.insert(feature.callbacks, cb) end
for _, cb in ipairs(AC.ruleEffects.callbacks) do table.insert(feature.callbacks, cb) end

-- Panic button: stop all rules (they stay saved and can be re-enabled).
function feature.reset()
    engine.S().enabled = false
    engine.queue = {}
    AC.ruleEffects.reset()
end

return feature
