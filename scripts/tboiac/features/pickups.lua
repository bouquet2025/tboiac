-- Pickups: spawn any heart/coin/key/bomb/chest/battery/sack, room cleanup.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "pickups", label = "m_pickups" }

local state = { count = 1, variant = 10, subtype = 1 }

-- { i18n key, variant, subtype }
local GROUPS = {
    { "pk_hearts", {
        { "pk_heart_full", 10, 1 }, { "pk_heart_half", 10, 2 }, { "pk_heart_double", 10, 5 },
        { "pk_heart_soul", 10, 3 }, { "pk_heart_halfsoul", 10, 8 }, { "pk_heart_black", 10, 6 },
        { "pk_heart_eternal", 10, 4 }, { "pk_heart_gold", 10, 7 }, { "pk_heart_bone", 10, 11 },
        { "pk_heart_rotten", 10, 12 }, { "pk_heart_blended", 10, 10 }, { "pk_heart_scared", 10, 9 },
    } },
    { "pk_coins", {
        { "pk_penny", 20, 1 }, { "pk_nickel", 20, 2 }, { "pk_dime", 20, 3 }, { "pk_double_penny", 20, 4 },
        { "pk_lucky_penny", 20, 5 }, { "pk_sticky_nickel", 20, 6 }, { "pk_golden_penny", 20, 7 },
    } },
    { "pk_keys", {
        { "pk_key", 30, 1 }, { "pk_golden_key", 30, 2 }, { "pk_key_ring", 30, 3 }, { "pk_charged_key", 30, 4 },
    } },
    { "pk_bombs", {
        { "pk_bomb", 40, 1 }, { "pk_double_bomb", 40, 2 }, { "pk_golden_bomb", 40, 4 }, { "pk_giga_bomb", 40, 7 },
    } },
    { "pk_chests", {
        { "pk_chest", 50, 0 }, { "pk_bomb_chest", 51, 0 }, { "pk_spiked_chest", 52, 0 },
        { "pk_eternal_chest", 53, 0 }, { "pk_mimic_chest", 54, 0 }, { "pk_old_chest", 55, 0 },
        { "pk_wooden_chest", 56, 0 }, { "pk_mega_chest", 57, 0 }, { "pk_haunted_chest", 58, 0 },
        { "pk_golden_chest", 60, 0 }, { "pk_red_chest", 360, 0 },
    } },
    { "pk_other", {
        { "pk_battery", 90, 1 }, { "pk_micro_battery", 90, 2 }, { "pk_mega_battery", 90, 3 },
        { "pk_golden_battery", 90, 4 }, { "pk_grab_bag", 69, 1 }, { "pk_black_sack", 69, 2 },
        { "pk_random_pickup", 0, 0 },
    } },
}

local function spawn(variant, subtype, label)
    for _ = 1, state.count do
        Isaac.Spawn(EntityType.ENTITY_PICKUP, variant, subtype, util.spawnPos(), Vector.Zero, nil)
    end
    AC.render.toast(t("spawned", label, state.count))
end

local function countItem()
    return {
        kind = "number", label = t("count"), min = 1, max = 50, step = 1,
        get = function() return state.count end,
        set = function(v) state.count = v end,
    }
end

local function removePickups(filter)
    for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
        if filter(e) then e:Remove() end
    end
end

feature.pages = {
    pickups_grid = AC.grid.page({
        title = function() return t("m_pickups") end,
        pickHint = "grid_spawn", amount = true,
        discover = function()
            local jobs = {}
            for _, g in ipairs(GROUPS) do
                for _, p in ipairs(g[2]) do
                    if p[2] ~= 0 then
                        jobs[#jobs + 1] = { key = "5." .. p[2] .. "." .. p[3], t = 5, v = p[2], s = p[3] }
                    end
                end
            end
            AC.icons.discover(jobs)
        end,
        entries = function()
            local out = {}
            for _, g in ipairs(GROUPS) do
                for _, p in ipairs(g[2]) do
                    local key = "5." .. p[2] .. "." .. p[3]
                    local name = t(p[1])
                    out[#out + 1] = { name = name,
                        icon = function(pos) return AC.icons.entityKey(key, 5, p[2], pos + Vector(0, 8), 1) end,
                        pick = function(_, amount)
                            local n = state.count
                            state.count = amount or 1
                            spawn(p[2], p[3], name)
                            state.count = n
                        end,
                        place = function(pos, amount)
                            local room = AC.game:GetRoom()
                            for k = 1, amount or 1 do
                                local at = room:FindFreePickupSpawnPosition(pos + Vector((k - 1) * 6, 0), 0, true)
                                Isaac.Spawn(EntityType.ENTITY_PICKUP, p[2], p[3], at, Vector.Zero, nil)
                            end
                        end }
                end
            end
            return out
        end,
    }),
    pickups = {
        title = function() return t("m_pickups") end,
        build = function()
            local items = { menu.link(t("m_pickups_grid"), "pickups_grid"), countItem() }
            for _, g in ipairs(GROUPS) do
                items[#items + 1] = menu.link(t(g[1]), "pickups_" .. g[1])
            end
            items[#items + 1] = menu.link(t("pk_custom"), "pickups_custom")
            items[#items + 1] = menu.link(t("m_drops"), "drops")
            items[#items + 1] = menu.action(t("pk_clear"), function()
                removePickups(function(e) return e.Variant ~= PickupVariant.PICKUP_COLLECTIBLE end)
            end)
            items[#items + 1] = menu.action(t("pk_clear_items"), function()
                removePickups(function(e) return e.Variant == PickupVariant.PICKUP_COLLECTIBLE end)
            end)
            items[#items + 1] = menu.action(t("pk_collect_all"), function()
                local pos = util.firstTarget().Position
                for _, e in ipairs(Isaac.FindByType(EntityType.ENTITY_PICKUP)) do
                    if e.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then e.Position = pos end
                end
            end)
            return items
        end,
    },
    pickups_custom = {
        title = function() return t("pk_custom") end,
        build = function()
            return {
                countItem(),
                { kind = "number", label = t("variant"), min = 0, max = 1000, step = 1,
                  get = function() return state.variant end, set = function(v) state.variant = v end },
                { kind = "number", label = t("subtype"), min = 0, max = 1000, step = 1,
                  get = function() return state.subtype end, set = function(v) state.subtype = v end },
                menu.action(t("spawn"), function()
                    spawn(state.variant, state.subtype, "5." .. state.variant .. "." .. state.subtype)
                end),
            }
        end,
    },
}

for _, g in ipairs(GROUPS) do
    feature.pages["pickups_" .. g[1]] = {
        title = function() return t(g[1]) end,
        build = function()
            local items = { countItem() }
            for _, p in ipairs(g[2]) do
                items[#items + 1] = menu.action(t(p[1]), function() spawn(p[2], p[3], t(p[1])) end)
            end
            return items
        end,
    }
end

return feature
