-- Icons for the menu.
--   Items/trinkets: their 32x32 png from ItemConfig on our own centred icon.anm2 (vanilla game).
--   Entities/pickups: their anm2 file. REPENTOGON knows all of them (EntityConfig); without it the
--   mod learns the anm2 of every entity it sees in play (Sprite:GetFilename) and remembers it.
local AC = TBOIAC

local icons = { cache = {} }

local function cached(key, make)
    local s = icons.cache[key]
    if s == nil then
        local ok, sprite = pcall(make)
        s = ok and sprite or false
        icons.cache[key] = s
    end
    return s or nil
end

local function pngSprite(gfx)
    if not gfx or gfx == "" then return nil end
    local s = Sprite()
    s:Load("gfx/tboiac/ui/icon.anm2", false)
    s:ReplaceSpritesheet(0, gfx)
    s:LoadGraphics()
    s:Play("Idle", true)
    return s
end

-- Draw a 32x32 icon centred at `pos`.
function icons.collectible(id, pos, scale)
    local s = cached("c" .. id, function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        return cfg and pngSprite(cfg.GfxFileName)
    end)
    if not s then return false end
    s.Scale = Vector(scale or 1, scale or 1)
    s:Render(pos)
    return true
end

function icons.trinket(id, pos, scale)
    local s = cached("t" .. id, function()
        local cfg = Isaac.GetItemConfig():GetTrinket(id)
        return cfg and pngSprite(cfg.GfxFileName)
    end)
    if not s then return false end
    s.Scale = Vector(scale or 1, scale or 1)
    s:Render(pos)
    return true
end

-- anm2 path for "type.variant" (or "5.variant.subtype" for pickups).
local function entityPath(key, etype, variant)
    if AC.hasRepentogon and EntityConfig then
        local ok, cfg = pcall(EntityConfig.GetEntity, etype, variant)
        if ok and cfg then
            local path = cfg:GetAnm2Path()
            if path and path ~= "" then return path end
        end
    end
    return AC.save.data.iconCache[key]
end

function icons.known(key, etype, variant)
    return entityPath(key, etype, variant) ~= nil
end

-- Draw an entity standing at `pos` (its feet). Returns false when its sprite is unknown.
function icons.entityKey(key, etype, variant, pos, scale)
    local s = cached("e" .. key, function()
        local path = entityPath(key, etype, variant)
        if not path then return nil end
        local sprite = Sprite()
        sprite:Load(path, true)
        sprite:Play(sprite:GetDefaultAnimation(), true)
        return sprite
    end)
    if not s then
        icons.cache["e" .. key] = nil -- may be learned later
        return false
    end
    s.Scale = Vector(scale or 1, scale or 1)
    s:Render(pos)
    return true
end

function icons.entity(etype, variant, pos, scale)
    return icons.entityKey(etype .. "." .. variant, etype, variant, pos + Vector(20, 30), scale or 0.75)
end

-- Learning ------------------------------------------------------------------------------------

local function learn(key, entity)
    local cache = AC.save.data.iconCache
    if cache[key] then return end
    local ok, path = pcall(function() return entity:GetSprite():GetFilename() end)
    if ok and type(path) == "string" and path ~= "" then
        cache[key] = path
        AC.save.markDirty()
    end
end

icons.callbacks = {
    { ModCallbacks.MC_NPC_UPDATE, function(_, npc)
        local data = npc:GetData()
        if data.tboiacIcon then return end
        data.tboiacIcon = true
        learn(npc.Type .. "." .. npc.Variant, npc)
    end },
    { ModCallbacks.MC_POST_PICKUP_UPDATE, function(_, pickup)
        local data = pickup:GetData()
        if data.tboiacIcon then return end
        data.tboiacIcon = true
        if pickup.Variant ~= PickupVariant.PICKUP_COLLECTIBLE then
            learn("5." .. pickup.Variant .. "." .. pickup.SubType, pickup)
        end
    end },
}

return icons
