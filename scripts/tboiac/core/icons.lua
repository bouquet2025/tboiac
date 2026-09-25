-- Icons for menu previews. Items and trinkets use vanilla pickup sprites; entities need
-- REPENTOGON's EntityConfig to know their anm2 file.
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

local function pickupSprite(anm2, layer, gfx)
    local s = Sprite()
    s:Load(anm2, false)
    s:ReplaceSpritesheet(layer, gfx)
    s:LoadGraphics()
    s:Play("Idle", true)
    return s
end

function icons.collectible(id, pos)
    local s = cached("c" .. id, function()
        local cfg = Isaac.GetItemConfig():GetCollectible(id)
        return cfg and pickupSprite("gfx/005.100_collectible.anm2", 1, cfg.GfxFileName)
    end)
    if s then s:RenderLayer(1, pos) end
end

function icons.trinket(id, pos)
    local s = cached("t" .. id, function()
        local cfg = Isaac.GetItemConfig():GetTrinket(id)
        return cfg and pickupSprite("gfx/005.350_trinket.anm2", 0, cfg.GfxFileName)
    end)
    if s then s:RenderLayer(0, pos) end
end

-- Entity preview (REPENTOGON only). Returns false when unavailable.
function icons.entity(etype, variant, pos)
    if not AC.hasRepentogon or not EntityConfig then return false end
    local s = cached("e" .. etype .. "." .. variant, function()
        local cfg = EntityConfig.GetEntity(etype, variant)
        if not cfg then return nil end
        local sprite = Sprite()
        sprite:Load(cfg:GetAnm2Path(), true)
        sprite:Play(sprite:GetDefaultAnimation(), true)
        sprite.Scale = Vector(0.75, 0.75)
        return sprite
    end)
    if s then
        s:Render(pos + Vector(20, 30))
        return true
    end
    return false
end

return icons
