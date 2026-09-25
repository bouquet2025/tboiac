-- Grid pages: icons in a grid, filter by typing, Enter = pick, Shift+Enter / X = second action.
--
-- grid.page{
--   title   = string|fn,
--   entries = fn() -> { { name, alias?, id?, icon = fn(pos) -> bool, pick = fn(alt) }, ... },
--   pickHint = i18n key describing Enter, altHint = i18n key describing Shift+Enter (optional),
--   dynamic = true when entries change while the game runs (not cached),
--   extra   = fn() -> menu items shown above the results in list mode (ImGui) }
-- The page also has a normal `build` (search field + one action per entry) used by the ImGui
-- mirror and tests.
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local grid = {}

local LIST_LIMIT = 200

local function entries(page)
    local lang = AC.save.data.ui.lang
    if page.gridDef.dynamic or not page.cache or page.cacheLang ~= lang then
        local list = page.gridDef.entries()
        for _, e in ipairs(list) do
            e.lower = AC.names.lower(e.name or "?")
            if e.alias and e.alias ~= e.name then e.lower = e.lower .. "\n" .. AC.names.lower(e.alias) end
            if e.id then e.lower = e.lower .. "\n#" .. tostring(e.id) end
        end
        page.cache, page.cacheLang = list, lang
    end
    return page.cache
end

-- Entries matching the page's current query.
function grid.filtered(page)
    local q = AC.names.lower(page.query or "")
    local all = entries(page)
    if q == "" then return all end
    local out = {}
    local qid = tonumber(q)
    for _, e in ipairs(all) do
        if e.lower:find(q, 1, true) or (qid and e.id == qid) then out[#out + 1] = e end
    end
    return out
end

function grid.page(def)
    local page = { title = def.title, gridDef = def, grid = true, query = "" }
    page.build = function()
        local items = {
            { kind = "text", label = t("search"), live = true,
              get = function() return page.query end, set = function(s) page.query = s end },
        }
        for _, it in ipairs(def.extra and def.extra() or {}) do items[#items + 1] = it end
        for i, e in ipairs(grid.filtered(page)) do
            if i > LIST_LIMIT then
                items[#items + 1] = AC.menu.info(t("too_many"))
                break
            end
            local label = e.id and string.format("%s  #%s", e.name, tostring(e.id)) or e.name
            items[#items + 1] = { kind = "action", label = label, fn = function() e.pick(false) end,
                                  preview = e.icon }
            if def.altHint then
                items[#items + 1] = { kind = "action", label = "    " .. t(def.altHint), fn = function() e.pick(true) end }
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
