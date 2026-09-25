-- Player: god mode, stats, health, resources, character, movement.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "player", label = "m_player" }

local function S() return AC.save.data.player end

local function isTarget(player)
    local target = S().target
    if target == 0 then return true end
    return GetPtrHash(Isaac.GetPlayer(target - 1)) == GetPtrHash(player)
end

local function recache()
    for _, p in ipairs(util.players()) do
        p:AddCacheFlags(CacheFlag.CACHE_ALL)
        p:EvaluateItems()
    end
end

local function each(fn)
    return function()
        for _, p in ipairs(util.targets()) do fn(p) end
    end
end

local CHARACTERS = AC.data.CHARACTERS

local HEARTS = {
    { "h_container", function(p, n) p:AddMaxHearts(2 * n) end },
    { "h_red", function(p, n) p:AddHearts(2 * n) end },
    { "h_soul", function(p, n) p:AddSoulHearts(2 * n) end },
    { "h_black", function(p, n) p:AddBlackHearts(2 * n) end },
    { "h_bone", function(p, n) p:AddBoneHearts(n) end },
    { "h_golden", function(p, n) p:AddGoldenHearts(n) end },
    { "h_eternal", function(p, n) p:AddEternalHearts(n) end },
    { "h_rotten", function(p, n) p:AddRottenHearts(2 * n) end },
    { "h_broken", function(p, n) p:AddBrokenHearts(n) end },
}

local STATS = {
    { "damage", "st_damage", 0.5 }, { "tears", "st_tears", 0.25 }, { "speed", "st_speed", 0.1 },
    { "range", "st_range", 0.5 }, { "shotspeed", "st_shotspeed", 0.1 }, { "luck", "st_luck", 1 },
}

feature.pages = {
    player = {
        title = function() return t("m_player") end,
        build = function()
            local targets = { { t("target_all"), 0 } }
            for i = 1, AC.game:GetNumPlayers() do targets[#targets + 1] = { "P" .. i, i } end
            return {
                menu.choice(t("target"), "player", "target", targets),
                menu.toggle(t("god"), "player", "god"),
                menu.toggle(t("one_hit"), "player", "oneHit"),
                menu.toggle(t("flight"), "player", "flight", recache),
                menu.toggle(t("noclip"), "player", "noclip"),
                menu.toggle(t("inf_charge"), "player", "infCharge"),
                menu.number(t("size"), "player", "size", 0.25, 5, 0.25, recache),
                menu.link(t("m_stats"), "player_stats"),
                menu.link(t("m_health"), "player_health"),
                menu.link(t("m_resources"), "player_resources"),
                menu.link(t("m_character"), "player_character"),
                menu.link(t("m_costumes"), "player_costumes"),
                menu.action(t("full_heal"), each(function(p) p:SetFullHearts() end)),
                menu.action(t("revive"), each(function(p) if p:IsDead() then p:Revive() end end)),
                menu.action(t("kill_player"), each(function(p) p:Kill() end)),
            }
        end,
    },
    player_stats = {
        title = function() return t("m_stats") end,
        build = function()
            local items = { menu.info(t("stats_hint")) }
            for _, s in ipairs(STATS) do
                items[#items + 1] = menu.number(t(s[2]), "player.stats", s[1], -100, 100, s[3], recache)
            end
            items[#items + 1] = menu.action(t("reset_stats"), function()
                for _, s in ipairs(STATS) do S().stats[s[1]] = 0 end
                recache()
            end)
            return items
        end,
    },
    player_health = {
        title = function() return t("m_health") end,
        build = function()
            local items = { menu.info(t("health_hint")) }
            for _, h in ipairs(HEARTS) do
                items[#items + 1] = {
                    kind = "number", label = t(h[1]), min = -1, max = 1, step = 1,
                    get = function() return 0 end,
                    set = function(v) for _, p in ipairs(util.targets()) do h[2](p, v) end end,
                }
            end
            items[#items + 1] = menu.action(t("full_heal"), each(function(p) p:SetFullHearts() end))
            return items
        end,
    },
    player_resources = {
        title = function() return t("m_resources") end,
        build = function()
            local function resource(label, get, add)
                return {
                    kind = "number", label = label, min = 0, max = 99, step = 1,
                    get = function() return get(util.firstTarget()) end,
                    set = function(v)
                        for _, p in ipairs(util.targets()) do add(p, v - get(p)) end
                    end,
                }
            end
            return {
                resource(t("coins"), function(p) return p:GetNumCoins() end, function(p, n) p:AddCoins(n) end),
                resource(t("bombs"), function(p) return p:GetNumBombs() end, function(p, n) p:AddBombs(n) end),
                resource(t("keys"), function(p) return p:GetNumKeys() end, function(p, n) p:AddKeys(n) end),
                menu.toggle(t("inf_coins"), "player", "infCoins"),
                menu.toggle(t("inf_bombs"), "player", "infBombs"),
                menu.toggle(t("inf_keys"), "player", "infKeys"),
                menu.action(t("golden_bomb"), each(function(p) p:AddGoldenBomb() end)),
                menu.action(t("golden_key"), each(function(p) p:AddGoldenKey() end)),
            }
        end,
    },
    player_costumes = AC.catalog.page({
        title = function() return t("m_costumes") end,
        ids = function() return AC.catalog.range(1, util.maxCollectible()) end,
        name = util.collectibleName,
        pick = function(id)
            local cfg = Isaac.GetItemConfig():GetCollectible(id)
            if cfg then for _, p in ipairs(util.targets()) do p:AddCostume(cfg, false) end end
        end,
        extra = function()
            return {
                menu.info(t("costumes_hint")),
                menu.action(t("a_clear_costumes"), each(function(p) p:ClearCostumes() end)),
            }
        end,
    }),
    player_character = {
        title = function() return t("m_character") end,
        build = function()
            local items = {}
            for _, c in ipairs(CHARACTERS) do
                items[#items + 1] = menu.action(c[2], each(function(p)
                    p:ChangePlayerType(c[1])
                    AC.render.toast(t("changed_to", c[2]))
                end))
            end
            return items
        end,
    },
}

local function onTakeDamage(_, entity)
    local player = entity:ToPlayer()
    if not player or not isTarget(player) then return nil end
    if S().god then return false end
    if S().oneHit then
        player:Kill()
    end
    return nil
end

local function onCache(_, player, flag)
    if not isTarget(player) then return end
    local st = S().stats
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
    elseif flag == CacheFlag.CACHE_FLYING and S().flight then
        player.CanFly = true
    elseif flag == CacheFlag.CACHE_SIZE and S().size ~= 1 then
        player.SpriteScale = player.SpriteScale * S().size
    end
end

local function onPlayerUpdate(_, player)
    if not isTarget(player) then return end
    local s = S()
    if s.infCoins and player:GetNumCoins() < 99 then player:AddCoins(99) end
    if s.infBombs and player:GetNumBombs() < 99 then player:AddBombs(99) end
    if s.infKeys and player:GetNumKeys() < 99 then player:AddKeys(99) end
    if s.infCharge then
        for slot = ActiveSlot.SLOT_PRIMARY, ActiveSlot.SLOT_POCKET do
            if player:GetActiveItem(slot) ~= 0 and player:NeedsCharge(slot) then
                player:FullCharge(slot, true)
            end
        end
    end
    local data = player:GetData()
    if s.noclip then
        player.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_NONE
        data.tboiacNoclip = true
    elseif data.tboiacNoclip then
        player.GridCollisionClass = EntityGridCollisionClass.GRIDCOLL_GROUND
        data.tboiacNoclip = nil
    end
end

feature.callbacks = {
    { ModCallbacks.MC_ENTITY_TAKE_DMG, onTakeDamage, EntityType.ENTITY_PLAYER },
    { ModCallbacks.MC_EVALUATE_CACHE, onCache },
    { ModCallbacks.MC_POST_PEFFECT_UPDATE, onPlayerUpdate },
    { ModCallbacks.MC_POST_GAME_STARTED, function() recache() end },
}

function feature.reset()
    local s = S()
    s.god, s.oneHit, s.flight, s.noclip = false, false, false, false
    s.infCoins, s.infBombs, s.infKeys, s.infCharge = false, false, false, false
    s.size = 1
    for k in pairs(s.stats) do s.stats[k] = 0 end
    recache()
end

return feature
