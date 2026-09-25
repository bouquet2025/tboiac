-- Items: collectibles, trinkets, cards/runes, pills, rerolls.
local AC = TBOIAC
local menu, util, catalog = AC.menu, AC.util, AC.catalog
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "items", label = "m_items" }

-- "inventory" adds directly, "pedestal" spawns on the floor.
local mode = { give = "inventory" }

local function modeChoice()
    return {
        kind = "choice", label = t("give_mode"),
        options = { { t("mode_inventory"), "inventory" }, { t("mode_pedestal"), "pedestal" } },
        get = function() return mode.give end,
        set = function(v) mode.give = v end,
    }
end

local function spawnPickup(variant, subtype)
    Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, util.spawnPos(), Vector.Zero, nil)
end

-- `floor` true/false overrides the "give as" setting (grid: Enter = inventory, Shift+Enter = floor).
local function giveCollectible(id, name, floor, amount)
    if floor == nil then floor = mode.give == "pedestal" end
    amount = amount or 1
    for _ = 1, amount do
        if floor then
            spawnPickup(PickupVariant.PICKUP_COLLECTIBLE, id)
        else
            for _, p in ipairs(util.targets()) do p:AddCollectible(id, 0, true) end
        end
    end
    AC.save.pushRecent(AC.save.data.recent.items, id, 15)
    AC.render.toast(t("given_n", name or util.collectibleName(id) or id, amount))
end

local function giveTrinket(id, name, floor, amount)
    if floor == nil then floor = mode.give == "pedestal" end
    amount = amount or 1
    for _ = 1, amount do
        if floor then
            spawnPickup(PickupVariant.PICKUP_TRINKET, id)
        else
            for _, p in ipairs(util.targets()) do p:AddTrinket(id, true) end
        end
    end
    AC.render.toast(t("given_n", name, amount))
end

-- Put `amount` pickups of a kind at a world position (placing with the mouse).
local function placePickup(variant, subtype, pos, amount)
    local room = AC.game:GetRoom()
    for i = 1, amount or 1 do
        local p = room:FindFreePickupSpawnPosition(pos + Vector((i - 1) * 8, 0), 0, true)
        Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, p, Vector.Zero, nil)
    end
end
feature.placePickup = placePickup

-- Pool membership for the pool filter: exact with REPENTOGON, otherwise sampled from the live pool.
local poolCache = {}
local function poolSet(poolType)
    if poolCache[poolType] then return poolCache[poolType] end
    local set = {}
    local pool = AC.game:GetItemPool()
    if AC.hasRepentogon and pool.GetCollectiblesFromPool then
        local ok, list = pcall(pool.GetCollectiblesFromPool, pool, poolType)
        if ok and type(list) == "table" then
            for _, e in ipairs(list) do set[e.itemID] = true end
            poolCache[poolType] = set
            return set
        end
    end
    AC.poolSampling = true -- our pool filters must not interfere
    local rng = RNG()
    rng:SetSeed(7919 + poolType, 35)
    for _ = 1, 1500 do set[pool:GetCollectible(poolType, false, rng:Next())] = true end
    AC.poolSampling = false
    set[CollectibleType.COLLECTIBLE_BREAKFAST] = nil -- the "pool is empty" fallback
    poolCache[poolType] = set
    return set
end
feature.poolSet = poolSet

local POOLS = {
    { "pool_treasure", "POOL_TREASURE" }, { "pool_shop", "POOL_SHOP" }, { "pool_boss", "POOL_BOSS" },
    { "pool_devil", "POOL_DEVIL" }, { "pool_angel", "POOL_ANGEL" }, { "pool_secret", "POOL_SECRET" },
    { "pool_curse", "POOL_CURSE" }, { "pool_library", "POOL_LIBRARY" }, { "pool_golden_chest", "POOL_GOLDEN_CHEST" },
    { "pool_red_chest", "POOL_RED_CHEST" }, { "pool_beggar", "POOL_BEGGAR" }, { "pool_demon_beggar", "POOL_DEMON_BEGGAR" },
    { "pool_planetarium", "POOL_PLANETARIUM" }, { "pool_ultra_secret", "POOL_ULTRA_SECRET" },
}

local function poolOptions()
    local out = { { "all", -1 } }
    for _, p in ipairs(POOLS) do
        local present = false
        for name in pairs(ItemPoolType) do if name == p[2] then present = true end end
        if present then out[#out + 1] = { p[1], ItemPoolType[p[2]] } end
    end
    return out
end

local ITEM_TYPES = { passive = 1, active = 3, familiar = 4 }

local function smeltTrinket(id, name)
    for _, p in ipairs(util.targets()) do
        -- Smelter absorbs held trinkets; move current ones aside first.
        local held = { p:GetTrinket(0), p:GetTrinket(1) }
        for _, h in ipairs(held) do if h ~= 0 then p:TryRemoveTrinket(h) end end
        p:AddTrinket(id, false)
        p:UseActiveItem(CollectibleType.COLLECTIBLE_SMELTER, UseFlag.USE_NOANIM)
        for _, h in ipairs(held) do if h ~= 0 then p:AddTrinket(h, false) end end
    end
    AC.render.toast(t("smelted", name))
end

local function ownedCollectibles()
    local p, ids = util.firstTarget(), {}
    for id = 1, util.maxCollectible() do
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        if cfg and p:HasCollectible(id, true) then ids[#ids + 1] = id end
    end
    return ids
end

local function useItem(id)
    for _, p in ipairs(util.targets()) do p:UseActiveItem(id, UseFlag.USE_NOANIM) end
end

local cardNames, pillNames = util.cardName, util.pillName

feature.callbacks = {
    { ModCallbacks.MC_POST_GAME_STARTED, function() poolCache = {} end },
}

feature.pages = {
    items = {
        layout = "tiles",
        title = function() return t("m_items") end,
        build = function()
            return {
                menu.link(t("m_collectibles"), "items_grid"),
                menu.link(t("m_trinkets"), "trinkets_grid"),
                menu.link(t("m_pickups"), "pickups"),
                menu.link(t("m_cards"), "items_cards"),
                menu.link(t("m_pills"), "items_pills"),
                menu.link(t("m_recent"), "items_recent"),
                menu.link(t("m_inventory"), "items_inventory"),
                menu.link(t("m_smelt"), "items_smelt"),
                menu.link(t("m_pools"), "pools"),
                menu.action(t("reroll_pedestals"), function() useItem(CollectibleType.COLLECTIBLE_D6) end),
                menu.action(t("reroll_inventory"), function() useItem(CollectibleType.COLLECTIBLE_D4) end),
                menu.action(t("reroll_pickups"), function() useItem(CollectibleType.COLLECTIBLE_D20) end),
                menu.action(t("random_item"), function()
                    local pool = AC.game:GetItemPool()
                    local id = pool:GetCollectible(ItemPoolType.POOL_TREASURE, true, Random())
                    giveCollectible(id)
                end),
                menu.action(t("remove_all_items"), function()
                    for _, p in ipairs(util.targets()) do
                        for id = 1, util.maxCollectible() do
                            if Isaac.GetItemConfig():GetCollectible(id) then
                                for _ = 1, p:GetCollectibleNum(id, true) do p:RemoveCollectible(id) end
                            end
                        end
                    end
                    AC.render.toast(t("removed_all"))
                end),
            }
        end,
    },
    items_grid = AC.grid.page({
        title = function() return t("m_collectibles") end,
        pickHint = "grid_give", altHint = "grid_floor", amount = true,
        chips = {
            { id = "tier", label = "chip_tier", default = -1,
              options = { { "all", -1 }, { "0", 0 }, { "1", 1 }, { "2", 2 }, { "3", 3 }, { "4", 4 } } },
            { id = "type", label = "chip_type", default = "all",
              options = { { "all", "all" }, { "type_passive", "passive" }, { "type_active", "active" },
                          { "type_familiar", "familiar" } } },
            { id = "pool", label = "chip_pool", default = -1, options = poolOptions },
        },
        filter = function(e, c)
            if c.tier ~= -1 and e.quality ~= c.tier then return false end
            if c.type ~= "all" and e.itype ~= ITEM_TYPES[c.type] then return false end
            if c.pool ~= -1 and not poolSet(c.pool)[e.id] then return false end
            return true
        end,
        sorts = {
            { "sort_name", "name", AC.grid.byName },
            { "sort_tier", "tier", function(a, b)
                if a.quality == b.quality then return nil end
                return a.quality > b.quality
            end },
        },
        entries = function()
            local list = {}
            local config = Isaac.GetItemConfig()
            for id = 1, util.maxCollectible() do
                local cfg = config:GetCollectible(id)
                local name = cfg and util.collectibleName(id)
                if name then
                    list[#list + 1] = { id = id, name = name, alias = util.collectibleAlias(id),
                        quality = cfg.Quality or 0, itype = cfg.Type,
                        desc = function()
                            local d = util.collectibleDesc(id)
                            local q = t("tier_n", cfg.Quality or 0)
                            return d and (q .. "  " .. d) or q
                        end,
                        icon = id,
                        pick = function(floor, amount) giveCollectible(id, name, floor, amount) end,
                        place = function(pos, amount) placePickup(PickupVariant.PICKUP_COLLECTIBLE, id, pos, amount) end }
                end
            end
            return list
        end,
    }),
    items_recent = {
        title = function() return t("m_recent") end,
        build = function()
            local items = { modeChoice() }
            for _, id in ipairs(AC.save.data.recent.items) do
                local name = util.collectibleName(id)
                if name then
                    local it = menu.action(name .. "  #" .. id, function() giveCollectible(id, name) end)
                    it.preview = function(pos) AC.icons.collectible(id, pos) end
                    items[#items + 1] = it
                end
            end
            return items
        end,
    },
    items_inventory = {
        title = function() return t("m_inventory") end,
        build = function()
            local items = { menu.info(t("inventory_hint")) }
            local p = util.firstTarget()
            for _, id in ipairs(ownedCollectibles()) do
                local name = util.collectibleName(id)
                local n = p:GetCollectibleNum(id, true)
                items[#items + 1] = menu.action(string.format("%s x%d", name, n), function()
                    p:RemoveCollectible(id)
                    AC.render.toast(t("removed", name))
                end)
            end
            return items
        end,
    },
    trinkets_grid = AC.grid.page({
        title = function() return t("m_trinkets") end,
        pickHint = "grid_give", altHint = "grid_floor", amount = true,
        sorts = { { "sort_name", "name", AC.grid.byName } },
        entries = function()
            local list = {}
            for id = 1, util.maxTrinket() do
                local name = util.trinketName(id)
                if name then
                    list[#list + 1] = { id = id, name = name, alias = util.trinketAlias(id),
                        desc = function() return util.trinketDesc(id) end,
                        icon = { trinket = id },
                        pick = function(floor, amount) giveTrinket(id, name, floor, amount) end,
                        place = function(pos, amount) placePickup(PickupVariant.PICKUP_TRINKET, id, pos, amount) end }
                end
            end
            return list
        end,
    }),
    items_smelt = catalog.page({
        title = function() return t("m_smelt") end,
        ids = function() return catalog.range(1, util.maxTrinket()) end,
        name = util.trinketName,
        icon = AC.icons.trinket,
        pick = smeltTrinket,
    }),
    items_cards = catalog.page({
        title = function() return t("m_cards") end,
        ids = function() return catalog.range(1, Isaac.GetItemConfig():GetCards().Size - 1) end,
        name = cardNames,
        pick = function(id, name)
            if mode.give == "pedestal" then
                spawnPickup(PickupVariant.PICKUP_TAROTCARD, id)
            else
                for _, p in ipairs(util.targets()) do p:UseCard(id, UseFlag.USE_NOANIM) end
            end
            AC.render.toast(t("used", name))
        end,
        extra = function() return { modeChoice(), menu.info(t("cards_hint")) } end,
    }),
    items_pills = catalog.page({
        title = function() return t("m_pills") end,
        ids = function() return catalog.range(0, Isaac.GetItemConfig():GetPillEffects().Size - 1) end,
        name = pillNames,
        pick = function(id, name)
            for _, p in ipairs(util.targets()) do p:UsePill(id, PillColor.PILL_BLUE_BLUE, UseFlag.USE_NOANIM) end
            AC.render.toast(t("used", name))
        end,
    }),
}

return feature
