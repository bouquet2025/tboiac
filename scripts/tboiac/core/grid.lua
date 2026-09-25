-- Grid pages: icons in a grid, filter by typing, chips (tier/type/pool/sort/amount), Enter = pick,
-- Shift+Enter / right click = second action, Ctrl+Enter / "place" button = put it with the mouse.
--
-- grid.page{
--   title    = string|fn,
--   entries  = fn() -> { entry... },
--   pickHint = i18n key for Enter, altHint = i18n key for Shift+Enter (optional),
--   chips    = { { id, label = i18n key, options = { {label, value}, ... } | fn, default }, ... },
--   filter   = fn(entry, chips) -> bool   (chips = { [id] = value })
--   sorts    = { { label, value, fn(a, b) }, ... }   optional extra sort orders (ID order is default)
--   amount   = true to show the amount chip (entry.pick/place get it)
--   discover = fn(entries) optional: called when opened (sprite discovery)
--   dynamic  = true when entries change while the game runs (not cached),
--   extra    = fn() -> menu items shown above the results in list mode (ImGui) }
-- entry = { name, alias?, id?, desc = string|fn, icon = icon spec (see icons.draw),
--           pick = fn(alt, amount), place = fn(worldPos, amount) optional }
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local grid = {}

local LIST_LIMIT = 200
grid.AMOUNTS = { 1, 2, 3, 5, 10, 20 }

local function entries(page)
    local lang = AC.save.data.ui.lang
    if page.gridDef.dynamic or not page.cache or page.cacheLang ~= lang then
        local list = page.gridDef.entries()
        for i, e in ipairs(list) do
            e.order = i
            e.lower = AC.names.lower(e.name or "?")
            if e.alias and e.alias ~= e.name then e.lower = e.lower .. "\n" .. AC.names.lower(e.alias) end
            if e.id then e.lower = e.lower .. "\n#" .. tostring(e.id) end
        end
        page.cache, page.cacheLang = list, lang
    end
    return page.cache
end

-- Chip definitions of a page, including the built-in sort and amount chips.
function grid.chips(page)
    local def = page.gridDef
    local list = {}
    for _, c in ipairs(def.chips or {}) do list[#list + 1] = c end
    if def.sorts then
        local opts = { { "sort_id", "id" } }
        for _, s in ipairs(def.sorts) do opts[#opts + 1] = { s[1], s[2] } end
        list[#list + 1] = { id = "sort", label = "chip_sort", options = opts, default = "id" }
    end
    if def.amount then
        local opts = {}
        for _, n in ipairs(grid.AMOUNTS) do opts[#opts + 1] = { tostring(n), n } end
        list[#list + 1] = { id = "amount", label = "chip_amount", options = opts, default = 1 }
    end
    return list
end

function grid.chipOptions(chip)
    return type(chip.options) == "function" and chip.options() or chip.options
end

function grid.chipValue(page, chip)
    page.chipState = page.chipState or {}
    local v = page.chipState[chip.id]
    if v == nil then v = chip.default end
    return v
end

function grid.cycleChip(page, chip, dir)
    local opts = grid.chipOptions(chip)
    local cur = grid.chipValue(page, chip)
    local idx = 1
    for i, o in ipairs(opts) do if o[2] == cur then idx = i break end end
    idx = (idx - 1 + dir) % #opts + 1
    page.chipState[chip.id] = opts[idx][2]
end

function grid.amount(page)
    return page.chipState and page.chipState.amount or 1
end

-- Entries matching the query and chips, in the chosen order.
function grid.filtered(page)
    local def = page.gridDef
    local q = AC.names.lower(page.query or "")
    local qid = tonumber(q)
    local state = {}
    for _, c in ipairs(grid.chips(page)) do state[c.id] = grid.chipValue(page, c) end
    local out = {}
    for _, e in ipairs(entries(page)) do
        local ok = q == "" or e.lower:find(q, 1, true) or (qid and e.id == qid)
        if ok and def.filter then
            local fine, res = pcall(def.filter, e, state)
            ok = fine and res
        end
        if ok then out[#out + 1] = e end
    end
    local sort = state.sort
    if sort and sort ~= "id" then
        for _, s in ipairs(def.sorts or {}) do
            if s[2] == sort then
                table.sort(out, function(a, b)
                    local r = s[3](a, b)
                    if r == nil then return a.order < b.order end
                    return r
                end)
            end
        end
    end
    return out
end

-- Standard sorts.
function grid.byName(a, b)
    if a.lower == b.lower then return nil end
    return a.lower < b.lower
end

function grid.page(def)
    local page = { title = def.title, gridDef = def, grid = true, query = "", chipState = {} }
    page.build = function()
        local items = {
            { kind = "text", label = t("search"), live = true,
              get = function() return page.query end, set = function(s) page.query = s end },
        }
        for _, c in ipairs(grid.chips(page)) do
            items[#items + 1] = { kind = "choice", label = t(c.label),
                options = function()
                    local out = {}
                    for _, o in ipairs(grid.chipOptions(c)) do out[#out + 1] = { AC.i18n.label(o[1]), o[2] } end
                    return out
                end,
                get = function() return grid.chipValue(page, c) end,
                set = function(v) page.chipState[c.id] = v end }
        end
        for _, it in ipairs(def.extra and def.extra() or {}) do items[#items + 1] = it end
        for i, e in ipairs(grid.filtered(page)) do
            if i > LIST_LIMIT then
                items[#items + 1] = AC.menu.info(t("too_many"))
                break
            end
            local label = e.id and string.format("%s  #%s", e.name, tostring(e.id)) or e.name
            items[#items + 1] = { kind = "action", label = label, icon = e.icon,
                fn = function() e.pick(false, grid.amount(page)) end }
            if def.altHint then
                items[#items + 1] = { kind = "action", label = "    " .. t(def.altHint),
                    fn = function() e.pick(true, grid.amount(page)) end }
            end
        end
        return items
    end
    return page
end

-- Short placeholder for entries without a known sprite ("Monstro" -> "Mo").
function grid.initials(name)
    local first = name:match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
    local second = name:sub(#first + 1):match("^[%z\1-\127\194-\244][\128-\191]*") or ""
    return first .. second
end

return grid
