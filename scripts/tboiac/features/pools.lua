-- Item pools: blacklist, whitelist, replacements and quality range for every newly
-- generated collectible (MC_POST_GET_COLLECTIBLE).
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "pools" } -- no root entry; opened from the Items page

local function S() return AC.save.data.pools end

local function set(list)
    local out = {}
    for _, id in ipairs(list) do out[id] = true end
    return out
end

local function quality(id)
    local cfg = Isaac.GetItemConfig():GetCollectible(id)
    return cfg and cfg.Quality or 0
end

local function allowed(id, black, white)
    if black[id] then return false end
    if next(white) and not white[id] then return false end
    local q = quality(id)
    return q >= S().qmin and q <= S().qmax
end

local busy = false -- our own GetCollectible calls re-enter the callback

local function onGetCollectible(_, selected, poolType, decrease, seed)
    local s = S()
    if not s.enabled or busy then return nil end
    for _, r in ipairs(s.replace) do
        if r[1] == selected then return r[2] end
    end
    local black, white = set(s.black), set(s.white)
    if allowed(selected, black, white) then return nil end

    local pool = AC.game:GetItemPool()
    local rng = RNG()
    rng:SetSeed(math.max(1, seed), 35)
    busy = true
    local pick
    for _ = 1, 30 do
        local id = pool:GetCollectible(poolType, false, rng:Next())
        if allowed(id, black, white) then pick = id break end
    end
    busy = false
    if not pick then
        -- Pool exhausted for these filters: take any allowed item from the whole config.
        local candidates = {}
        if next(white) then
            for id in pairs(white) do if allowed(id, black, white) then candidates[#candidates + 1] = id end end
        else
            for id = 1, util.maxCollectible() do
                if Isaac.GetItemConfig():GetCollectible(id) and allowed(id, black, white) then
                    candidates[#candidates + 1] = id
                end
            end
        end
        if #candidates == 0 then return nil end
        pick = candidates[rng:RandomInt(#candidates) + 1]
    end
    if decrease then pool:RemoveCollectible(pick) end
    return pick
end

local function itemLabel(id)
    return string.format("%s  #%d", util.collectibleName(id) or "?", id)
end

local function picker(title, onPick)
    return AC.catalog.page({
        title = function() return t(title) end,
        ids = function() return AC.catalog.range(1, util.maxCollectible()) end,
        name = util.collectibleName,
        pick = function(id)
            onPick(id)
            menu.pop()
        end,
    })
end

local function idListPage(key, title)
    return {
        title = function() return t(title) end,
        build = function()
            local list = S()[key]
            local items = {
                menu.link("+ " .. t("pool_add"), function()
                    return picker(title, function(id)
                        for _, x in ipairs(S()[key]) do if x == id then return end end
                        table.insert(S()[key], id)
                    end)
                end),
                menu.info(t("pool_remove_hint")),
            }
            for i, id in ipairs(list) do
                items[#items + 1] = menu.action(itemLabel(id), function() table.remove(list, i) end)
            end
            return items
        end,
    }
end

local draft = { from = 1, to = 118 }

local function catalogNumber(label, key)
    return { kind = "number", label = label, min = 1, max = util.maxCollectible(), step = 1,
             get = function() return draft[key] end, set = function(v) draft[key] = v end,
             fmt = function(v) return itemLabel(v) end }
end

feature.pages = {
    pools = {
        title = function() return t("m_pools") end,
        build = function()
            local s = S()
            return {
                menu.toggle(t("pools_enabled"), "pools", "enabled"),
                menu.info(t("pools_hint")),
                menu.link(t("pool_black", #s.black), "pools_black"),
                menu.link(t("pool_white", #s.white), "pools_white"),
                menu.link(t("pool_replace", #s.replace), "pools_replace"),
                menu.number(t("quality_min"), "pools", "qmin", 0, 4, 1),
                menu.number(t("quality_max"), "pools", "qmax", 0, 4, 1),
                menu.action(t("pools_reset"), function()
                    AC.save.data.pools = util.copy(AC.save.defaults.pools)
                end),
            }
        end,
    },
    pools_black = idListPage("black", "pool_black_title"),
    pools_white = idListPage("white", "pool_white_title"),
    pools_replace = {
        title = function() return t("pool_replace_title") end,
        build = function()
            local items = {
                catalogNumber(t("replace_from"), "from"),
                menu.link("  " .. t("pick_from_list"), function()
                    return picker("replace_from", function(id) draft.from = id end)
                end),
                catalogNumber(t("replace_to"), "to"),
                menu.link("  " .. t("pick_from_list"), function()
                    return picker("replace_to", function(id) draft.to = id end)
                end),
                menu.action("+ " .. t("replace_add"), function()
                    local list = S().replace
                    for i = #list, 1, -1 do if list[i][1] == draft.from then table.remove(list, i) end end
                    table.insert(list, { draft.from, draft.to })
                end),
                menu.info(t("pool_remove_hint")),
            }
            for i, r in ipairs(S().replace) do
                items[#items + 1] = menu.action(string.format("%s -> %s",
                    util.collectibleName(r[1]) or r[1], util.collectibleName(r[2]) or r[2]),
                    function() table.remove(S().replace, i) end)
            end
            return items
        end,
    },
}

feature.callbacks = {
    { ModCallbacks.MC_POST_GET_COLLECTIBLE, onGetCollectible },
}

function feature.reset()
    S().enabled = false
end

-- Exposed for tests.
feature.onGetCollectible = onGetCollectible

return feature
