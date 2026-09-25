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

local function giveCollectible(id, name)
    if mode.give == "pedestal" then
        spawnPickup(PickupVariant.PICKUP_COLLECTIBLE, id)
    else
        for _, p in ipairs(util.targets()) do p:AddCollectible(id, 0, true) end
    end
    AC.save.pushRecent(AC.save.data.recent.items, id, 15)
    AC.render.toast(t("given", name or util.collectibleName(id) or id))
end

local function giveTrinket(id, name)
    if mode.give == "pedestal" then
        spawnPickup(PickupVariant.PICKUP_TRINKET, id)
    else
        for _, p in ipairs(util.targets()) do p:AddTrinket(id, true) end
    end
    AC.render.toast(t("given", name))
end

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

feature.pages = {
    items = {
        title = function() return t("m_items") end,
        build = function()
            return {
                modeChoice(),
                menu.link(t("m_collectibles"), "items_collectibles"),
                menu.link(t("m_recent"), "items_recent"),
                menu.link(t("m_inventory"), "items_inventory"),
                menu.link(t("m_trinkets"), "items_trinkets"),
                menu.link(t("m_smelt"), "items_smelt"),
                menu.link(t("m_cards"), "items_cards"),
                menu.link(t("m_pills"), "items_pills"),
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
    items_collectibles = catalog.page({
        title = function() return t("m_collectibles") end,
        ids = function() return catalog.range(1, util.maxCollectible()) end,
        name = util.collectibleName,
        alias = util.collectibleAlias,
        icon = AC.icons.collectible,
        pick = giveCollectible,
        extra = function() return { modeChoice() } end,
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
    items_trinkets = catalog.page({
        title = function() return t("m_trinkets") end,
        ids = function() return catalog.range(1, util.maxTrinket()) end,
        name = util.trinketName,
        alias = util.trinketAlias,
        icon = AC.icons.trinket,
        pick = giveTrinket,
        extra = function() return { modeChoice() } end,
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
