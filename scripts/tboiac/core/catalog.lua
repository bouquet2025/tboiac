-- Searchable list pages: collectibles, trinkets, cards, pills, entities.
-- catalog.page{ title, ids = fn() -> {id...}, name = fn(id) -> string?, pick = fn(id), extra = fn() -> items }
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local catalog = {}

local LIMIT = 200

function catalog.page(def)
    local state = { query = "" }
    local cache
    local function entries()
        if not cache then
            cache = {}
            for _, id in ipairs(def.ids()) do
                local name = def.name(id)
                if name then cache[#cache + 1] = { id = id, name = name, lower = name:lower() } end
            end
        end
        return cache
    end
    return {
        title = def.title,
        build = function()
            local items = {
                {
                    kind = "text", label = t("search"), live = true,
                    get = function() return state.query end,
                    set = function(s) state.query = s end,
                },
            }
            for _, it in ipairs(def.extra and def.extra() or {}) do items[#items + 1] = it end
            local q = state.query:lower()
            local qid = tonumber(q)
            local found = 0
            for _, e in ipairs(entries()) do
                if q == "" or e.lower:find(q, 1, true) or e.id == qid then
                    found = found + 1
                    if found > LIMIT then
                        items[#items + 1] = AC.menu.info(t("too_many"))
                        break
                    end
                    items[#items + 1] = {
                        kind = "action",
                        label = string.format("%s  #%s", e.name, tostring(e.id)),
                        fn = function() def.pick(e.id, e.name) end,
                    }
                end
            end
            return items
        end,
    }
end

function catalog.range(from, to)
    local ids = {}
    for i = from, to do ids[#ids + 1] = i end
    return ids
end

return catalog
