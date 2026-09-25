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
    s.Color = Color(1, 1, 1, 1)
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
    s.Color = Color(1, 1, 1, 1)
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

-- Generic icon drawing. `spec` is a collectible id (number), { trinket = id },
-- { entity = "type.variant", t = type, v = variant } or a function(pos, scale) -> bool.
function icons.draw(spec, pos, scale, alpha)
    if spec == nil then return false end
    if type(spec) == "function" then
        local ok, res = pcall(spec, pos, scale)
        return ok and res ~= false
    end
    local s
    if type(spec) == "number" then
        s = cached("c" .. spec, function()
            local cfg = Isaac.GetItemConfig():GetCollectible(spec)
            return cfg and pngSprite(cfg.GfxFileName)
        end)
    elseif spec.trinket then
        s = cached("t" .. spec.trinket, function()
            local cfg = Isaac.GetItemConfig():GetTrinket(spec.trinket)
            return cfg and pngSprite(cfg.GfxFileName)
        end)
    elseif spec.entity then
        return icons.entityKey(spec.entity, spec.t, spec.v, pos, scale)
    end
    if not s then return false end
    s.Scale = Vector(scale or 1, scale or 1)
    s.Color = Color(1, 1, 1, alpha or 1)
    s:Render(pos)
    return true
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

-- Active sprite discovery (vanilla game): spawn each unknown entity far outside the room for a
-- single frame, read its anm2 and remove it together with anything it created. One per update.
-- Entities that need their own room/scripted fight are never spawned this way.
local UNSAFE = { [274] = true, [275] = true, [406] = true, [407] = true, [412] = true, [912] = true,
    [950] = true, [951] = true }
icons.queue, icons.tried = {}, {}

function icons.discover(list)
    if AC.hasRepentogon then return end
    for _, job in ipairs(list) do
        if not AC.save.data.iconCache[job.key] and not icons.tried[job.key] and not UNSAFE[job.t] then
            icons.tried[job.key] = true
            icons.queue[#icons.queue + 1] = job
        end
    end
end

function icons.pending() return #icons.queue end

local function discoverOne(job)
    local before = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do before[GetPtrHash(e)] = true end
    local e = Isaac.Spawn(job.t, job.v, job.s or 0, Vector(-3000, -3000), Vector.Zero, nil)
    if e then learn(job.key, e) end
    for _, x in ipairs(Isaac.GetRoomEntities()) do
        if not before[GetPtrHash(x)] then x:Remove() end
    end
end

icons.callbacks = {
    { ModCallbacks.MC_POST_UPDATE, function()
        local job = table.remove(icons.queue, 1)
        if job then
            local ok, err = pcall(discoverOne, job)
            if not ok then AC.util.log("sprite discovery failed for " .. job.key .. ": " .. tostring(err)) end
        end
    end },

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
