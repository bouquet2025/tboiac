-- Reward rules: room clear award (multiply, cancel, bonus), extra boss items, multiplying or
-- removing pickups that drop during play, and enemy drop chance.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "drops" } -- opened from the Pickups page

local function S() return AC.save.data.drops end

local BONUS = {
    { "rw_none", "none", nil }, { "rw_pickup", "pickup", { 0, 0 } }, { "pk_hearts", "heart", { 10, 0 } },
    { "pk_coins", "coin", { 20, 0 } }, { "pk_keys", "key", { 30, 0 } }, { "pk_bombs", "bomb", { 40, 0 } },
    { "pk_chest", "chest", { 50, 0 } }, { "pk_battery", "battery", { 90, 0 } },
    { "m_trinkets", "trinket", { 350, 0 } }, { "m_cards", "card", { 300, 0 } }, { "rw_item", "item", { 100, 0 } },
}

-- Pickup variants affected by the pickup multiplier / "no pickups" (cards, pills, trinkets and
-- items are left alone so swapping them never deletes the dropped one).
local BASIC = { [10] = true, [20] = true, [30] = true, [40] = true, [50] = true, [51] = true, [52] = true,
    [53] = true, [54] = true, [55] = true, [56] = true, [57] = true, [58] = true, [60] = true, [69] = true,
    [90] = true, [360] = true }

local function spawnAt(pos, v, st)
    local room = AC.game:GetRoom()
    local p = room:FindFreePickupSpawnPosition(pos, 0, true)
    local e = Isaac.Spawn(EntityType.ENTITY_PICKUP, v, st, p, Vector.Zero, nil)
    if e then e:GetData().tboiacDropCopy = true end
    return e
end

local busy = false

local function onClearAward(_, _, pos)
    local s = S()
    if not s.enabled or busy then return nil end
    local room = AC.game:GetRoom()
    busy = true
    if not s.noClearAward then
        for _ = 2, s.clearMult do room:SpawnClearAward() end
    end
    busy = false
    for _, b in ipairs(BONUS) do
        if b[2] == s.clearBonus and b[3] then spawnAt(room:GetCenterPos(), b[3][1], b[3][2]) end
    end
    if room:GetType() == RoomType.ROOM_BOSS then
        for _ = 1, s.bossItems do spawnAt(room:GetCenterPos(), PickupVariant.PICKUP_COLLECTIBLE, 0) end
    end
    if s.noClearAward then return true end
    return nil
end

local function onPickupInit(_, pickup)
    -- Only pickups appearing during play; the room's own layout spawns at room frame 0.
    if AC.game:GetRoom():GetFrameCount() > 1 then pickup:GetData().tboiacFresh = true end
end

local function onPickupUpdate(_, pickup)
    local data = pickup:GetData()
    if not data.tboiacFresh then return end
    data.tboiacFresh = nil
    local s = S()
    if not s.enabled or data.tboiacDropCopy or data.tboiacByRule then return end
    if not BASIC[pickup.Variant] or pickup.Price ~= 0 then return end
    if s.noPickups then
        pickup:Remove()
        return
    end
    for _ = 2, s.pickupMult do spawnAt(pickup.Position, pickup.Variant, pickup.SubType) end
end

local function onNpcDeath(_, npc)
    local s = S()
    if not s.enabled or s.enemyDrop <= 0 or not npc:IsEnemy() then return end
    if npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then return end
    if math.random(100) <= s.enemyDrop then spawnAt(npc.Position, 0, 0) end
end

feature.pages = {
    drops = {
        title = function() return t("m_drops") end,
        build = function()
            return {
                menu.toggle(t("drops_enabled"), "drops", "enabled"),
                menu.info(t("drops_clear")),
                menu.number("  " .. t("clear_mult"), "drops", "clearMult", 1, 10, 1),
                menu.toggle("  " .. t("no_clear_award"), "drops", "noClearAward"),
                menu.choice("  " .. t("clear_bonus"), "drops", "clearBonus", function()
                    local out = {}
                    for _, b in ipairs(BONUS) do out[#out + 1] = { t(b[1]), b[2] } end
                    return out
                end),
                menu.number("  " .. t("boss_items"), "drops", "bossItems", 0, 10, 1),
                menu.info(t("drops_play")),
                menu.number("  " .. t("pickup_mult"), "drops", "pickupMult", 1, 10, 1),
                menu.toggle("  " .. t("no_pickups"), "drops", "noPickups"),
                menu.number("  " .. t("enemy_drop"), "drops", "enemyDrop", 0, 100, 5),
                menu.action(t("drops_reset"), function() AC.save.data.drops = util.copy(AC.save.defaults.drops) end),
            }
        end,
    },
}

feature.callbacks = {
    { ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, onClearAward },
    { ModCallbacks.MC_POST_PICKUP_INIT, onPickupInit },
    { ModCallbacks.MC_POST_PICKUP_UPDATE, onPickupUpdate },
    { ModCallbacks.MC_POST_NPC_DEATH, onNpcDeath },
}

function feature.reset()
    S().enabled = false
end

feature.onClearAward = onClearAward -- exposed for tests

return feature
