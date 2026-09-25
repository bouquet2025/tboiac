local AC = TBOIAC
local util = {}

function util.log(msg)
    Isaac.DebugString("[TBOIAC] " .. tostring(msg))
end

function util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function util.round(v, step)
    step = step or 1
    return math.floor(v / step + 0.5) * step
end

-- Deep copy of plain data tables (no metatables, no cycles).
function util.copy(t)
    if type(t) ~= "table" then return t end
    local r = {}
    for k, v in pairs(t) do r[k] = util.copy(v) end
    return r
end

-- Fill missing keys of `t` from `defaults`, recursively.
function util.merge(t, defaults)
    for k, v in pairs(defaults) do
        if t[k] == nil then
            t[k] = util.copy(v)
        elseif type(v) == "table" and type(t[k]) == "table" then
            util.merge(t[k], v)
        end
    end
    return t
end

function util.players()
    local list = {}
    for i = 0, AC.game:GetNumPlayers() - 1 do
        list[#list + 1] = Isaac.GetPlayer(i)
    end
    return list
end

-- Players affected by player-targeted actions, per the "target" setting
-- (0 = everyone, N = player N).
function util.targets()
    local target = AC.save.data.player.target
    local all = util.players()
    if target == 0 then return all end
    return { all[target] or all[1] }
end

function util.firstTarget()
    return util.targets()[1] or Isaac.GetPlayer(0)
end

function util.enemies(includeFriendly)
    local list = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local npc = e:ToNPC()
        if npc and npc:IsVulnerableEnemy() and not npc:IsDead()
            and (includeFriendly or not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY)) then
            list[#list + 1] = npc
        end
    end
    return list
end

-- Free spot near the player for spawning things.
function util.spawnPos(offset)
    local room = AC.game:GetRoom()
    local base = util.firstTarget().Position
    return room:FindFreePickupSpawnPosition(base + (offset or Vector(0, 60)), 0, true)
end

-- Converts an ItemConfig name ("#SAD_ONION_NAME" or "The Sad Onion") to display text.
function util.prettyName(name)
    if not name or name == "" then return "?" end
    if name:sub(1, 1) ~= "#" then return name end
    name = name:sub(2):gsub("_NAME$", ""):gsub("_", " "):lower()
    return (name:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

function util.collectibleName(id)
    local cfg = Isaac.GetItemConfig():GetCollectible(id)
    return cfg and util.prettyName(cfg.Name) or nil
end

function util.trinketName(id)
    local cfg = Isaac.GetItemConfig():GetTrinket(id)
    return cfg and util.prettyName(cfg.Name) or nil
end

function util.cardName(id)
    local cfg = Isaac.GetItemConfig():GetCard(id)
    return cfg and util.prettyName(cfg.Name) or nil
end

function util.pillName(id)
    local cfg = Isaac.GetItemConfig():GetPillEffect(id)
    return cfg and util.prettyName(cfg.Name) or nil
end

-- Searchable catalogs shared by the item menus and rule editor.
util.catalogs = {
    collectible = { name = function(id) return util.collectibleName(id) end,
                    ids = function() return 1, util.maxCollectible() end,
                    icon = function(id, pos) AC.icons.collectible(id, pos) end },
    trinket = { name = function(id) return util.trinketName(id) end,
                ids = function() return 1, util.maxTrinket() end,
                icon = function(id, pos) AC.icons.trinket(id, pos) end },
    card = { name = function(id) return util.cardName(id) end,
             ids = function() return 1, Isaac.GetItemConfig():GetCards().Size - 1 end },
    pill = { name = function(id) return util.pillName(id) end,
             ids = function() return 0, Isaac.GetItemConfig():GetPillEffects().Size - 1 end },
}

function util.maxCollectible()
    return Isaac.GetItemConfig():GetCollectibles().Size - 1
end

function util.maxTrinket()
    return Isaac.GetItemConfig():GetTrinkets().Size - 1
end

function util.command(cmd)
    util.log("command: " .. cmd)
    return Isaac.ExecuteCommand(cmd)
end

function util.roomTypeName(rtype)
    for _, r in ipairs(AC.data.ROOM_TYPES) do
        if r[2] == rtype then return AC.i18n.t(r[1]) end
    end
    return AC.i18n.t("rt_other", rtype)
end

function util.teleport(index)
    AC.menu.setOpen(false)
    AC.game:StartRoomTransition(index, Direction.NO_DIRECTION, RoomTransitionAnim.TELEPORT)
end

-- Safe grid index of the first room of `rtype` on this floor, or nil.
function util.findRoom(rtype)
    local rooms = AC.game:GetLevel():GetRooms()
    for i = 0, rooms.Size - 1 do
        local desc = rooms:Get(i)
        if desc.Data and desc.Data.Type == rtype then return desc.SafeGridIndex end
    end
    return nil
end

return util
