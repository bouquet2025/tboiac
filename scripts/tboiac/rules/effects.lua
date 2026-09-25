-- Phase 2c actions: continuous movement behaviours, looks, doors, seeds, music and on-screen text.
local AC = TBOIAC
local engine, P, util = AC.rules, AC.ruleParams, AC.util
local A = AC.ruleActions
local def, entityAction = engine.defineAction, A.entityAction

local effects = { texts = {} }

-- Movement behaviours ---------------------------------------------------------------------------
-- Stored in entity:GetData().tboiacMove = { kind, speed, radius, shape, size, origin, angle, t, offset, untilFrame }

local BEHAVIOURS = {
    { "mv_attract", "attract" }, { "mv_repel", "repel" }, { "mv_orbit", "orbit" }, { "mv_patrol", "patrol" },
    { "mv_immobile", "immobile" }, { "mv_stick", "stick" }, { "mv_mimic", "mimic" }, { "mv_spin", "spin" },
}

local SHAPES = {
    { "sh_line_h", "line_h" }, { "sh_line_v", "line_v" }, { "sh_square", "square" },
    { "sh_circle", "circle" }, { "sh_eight", "eight" },
}

-- Offset along a closed patrol shape for phase u in [0, 1).
local function shapeOffset(shape, u, size)
    local a = u * 2 * math.pi
    if shape == "line_h" then return Vector(math.sin(a) * size, 0) end
    if shape == "line_v" then return Vector(0, math.sin(a) * size) end
    if shape == "circle" then return Vector(math.cos(a) * size, math.sin(a) * size) end
    if shape == "eight" then return Vector(math.sin(a) * size, math.sin(2 * a) * size / 2) end
    -- square: four edges
    local edge, f = math.floor(u * 4), (u * 4) % 1
    local c = {
        Vector(-size + 2 * size * f, -size), Vector(size, -size + 2 * size * f),
        Vector(size - 2 * size * f, size), Vector(-size, size - 2 * size * f),
    }
    return c[edge + 1]
end

local function stepBehaviour(e, b, pl)
    if b.untilFrame and engine.frame > b.untilFrame then
        e:GetData().tboiacMove = nil
        return
    end
    local kind = b.kind
    if kind == "attract" or kind == "repel" then
        local d = (pl.Position - e.Position):Normalized()
        if kind == "repel" then d = d * -1 end
        e.Velocity = e.Velocity * 0.7 + d * (b.speed * 0.3)
    elseif kind == "orbit" then
        b.angle = (b.angle + b.speed) % 360
        e.Position = pl.Position + Vector.FromAngle(b.angle) * b.radius
        e.Velocity = Vector.Zero
    elseif kind == "patrol" then
        b.t = b.t + 1
        local period = math.max(10, 600 / math.max(0.1, b.speed))
        e.Position = b.origin + shapeOffset(b.shape, (b.t % period) / period, b.radius)
        e.Velocity = Vector.Zero
    elseif kind == "immobile" then
        e.Position = b.origin
        e.Velocity = Vector.Zero
    elseif kind == "stick" then
        e.Position = pl.Position + b.offset
        e.Velocity = pl.Velocity
    elseif kind == "mimic" then
        e.Velocity = pl.Velocity * (b.speed / 5)
    elseif kind == "spin" then
        e.SpriteRotation = (e.SpriteRotation + b.speed) % 360
    end
end

local function updateBehaviours()
    local pl = util.firstTarget()
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local b = e:GetData().tboiacMove
        if b then stepBehaviour(e, b, pl) end
    end
end

entityAction("behaviour", "a_behaviour", {
    P.choice("kind", "behaviour", "orbit", BEHAVIOURS),
    P.number("speed", "speed", 4, 0.5, 40, 0.5),
    P.number("radius2", "radius_size_px", 80, 10, 400, 10),
    P.choice("shape", "patrol_shape", "line_h", SHAPES),
    P.number("seconds", "seconds_zero_forever", 0, 0, 600, 1),
}, function(e, p, ctx)
    local pl = A.player(ctx)
    local selfRelative = p.kind == "attract" or p.kind == "repel" or p.kind == "orbit"
        or p.kind == "stick" or p.kind == "mimic"
    if selfRelative and GetPtrHash(e) == GetPtrHash(pl) then return end
    local pos = Vector(e.Position.X, e.Position.Y)
    e:GetData().tboiacMove = {
        kind = p.kind, speed = p.speed, radius = p.radius2, shape = p.shape,
        origin = pos, t = 0, angle = (pos - pl.Position):GetAngleDegrees(), offset = pos - pl.Position,
        untilFrame = p.seconds > 0 and engine.frame + p.seconds * 30 or nil,
    }
end)

entityAction("behaviour_clear", "a_behaviour_clear", nil, function(e)
    e:GetData().tboiacMove = nil
    e.SpriteRotation = 0
end)

-- Looks -----------------------------------------------------------------------------------------

entityAction("entity_rotate", "a_entity_rotate", { P.number("angle", "angle", 90, -360, 360, 15) },
    function(e, p) e.SpriteRotation = p.angle end)

entityAction("entity_alpha", "a_entity_alpha", { P.number("alpha", "opacity", 0.5, 0, 1, 0.1) },
    function(e, p)
        local c = e.Color
        e.Color = Color(c.R, c.G, c.B, p.alpha, c.RO, c.GO, c.BO)
    end)

entityAction("entity_anim", "a_entity_anim", { P.text("anim", "anim_name", "Idle") },
    function(e, p) e:GetSprite():Play(p.anim, true) end)

entityAction("entity_sprite", "a_entity_sprite", { P.text("path", "anm2_path", "gfx/001.000_player.anm2") },
    function(e, p)
        local sprite = e:GetSprite()
        sprite:Load(p.path, true)
        sprite:Play(sprite:GetDefaultAnimation(), true)
    end)

def({ id = "player_costume", label = "a_player_costume", params = { P.catalog("id", "item", 1, "collectible") },
    run = function(p, ctx)
        local cfg = Isaac.GetItemConfig():GetCollectible(p.id)
        if cfg then A.player(ctx):AddCostume(cfg, false) end
    end })

def({ id = "clear_costumes", label = "a_clear_costumes",
    run = function(_, ctx) A.player(ctx):ClearCostumes() end })

def({ id = "hud", label = "a_hud",
    params = { P.choice("mode", "mode", "hide", { { "hud_hide", "hide" }, { "hud_show", "show" }, { "toggle", "toggle" } }) },
    run = function(p)
        local hud = AC.game:GetHUD()
        local v = p.mode == "show" or (p.mode == "toggle" and not hud:IsVisible())
        hud:SetVisible(v)
    end })

-- Doors -----------------------------------------------------------------------------------------

local DOOR_MODES = {
    { "door_open", "open" }, { "door_close", "close" }, { "door_bar", "bar" }, { "door_lock", "lock" },
    { "door_unlock", "unlock" }, { "door_blow", "blow" },
}

function effects.doors(mode)
    local room = AC.game:GetRoom()
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then
            if mode == "open" then door:Open()
            elseif mode == "close" then door:Close(true)
            elseif mode == "bar" then door:Bar()
            elseif mode == "lock" then door:SetLocked(true)
            elseif mode == "unlock" then door:SetLocked(false)
            elseif mode == "blow" then door:TryBlowOpen(true, nil)
            end
        end
    end
end

def({ id = "doors", label = "a_doors", params = { P.choice("mode", "mode", "bar", DOOR_MODES) },
    run = function(p) effects.doors(p.mode) end })

-- Seeds & music ---------------------------------------------------------------------------------

local function firstSeed()
    local list = P.seeds()
    return list[1] and list[1][2] or 0
end

def({ id = "seed_effect", label = "a_seed_effect",
    params = { P.choice("seed", "seed_effect", firstSeed(), P.seeds),
               P.choice("mode", "mode", "on", { { "on", "on" }, { "off", "off" }, { "toggle", "toggle" } }) },
    run = function(p)
        local seeds = AC.game:GetSeeds()
        local on = p.mode == "on" or (p.mode == "toggle" and not seeds:HasSeedEffect(p.seed))
        if on then seeds:AddSeedEffect(p.seed) else seeds:RemoveSeedEffect(p.seed) end
    end })

def({ id = "clear_seeds", label = "a_clear_seeds", run = function() AC.game:GetSeeds():ClearSeedEffects() end })

local function firstTrack()
    local list = P.music()
    return list[1] and list[1][2] or 1
end

def({ id = "music", label = "a_music",
    params = { P.choice("mode", "mode", "play", { { "music_play", "play" }, { "music_fade", "fade" },
                                                  { "music_off", "off" }, { "music_on", "on" } }),
               P.choice("track", "track", firstTrack(), P.music) },
    run = function(p)
        local mm = MusicManager()
        if p.mode == "play" then mm:Enable() mm:Play(p.track, 1)
        elseif p.mode == "fade" then mm:Fadeout()
        elseif p.mode == "off" then mm:Disable()
        else mm:Enable() end
    end })

-- On-screen text --------------------------------------------------------------------------------
-- effects.texts[slot] = { text, x, y, scale, color, untilFrame, entity, fade }
-- "{name}" inside a text shows the counter `name`, "{flag:name}" shows ON/OFF.

local TEXT_COLORS = {
    white = { 1, 1, 1, 1 }, yellow = { 1, 0.9, 0.3, 1 }, red = { 1, 0.35, 0.35, 1 },
    green = { 0.4, 1, 0.5, 1 }, blue = { 0.5, 0.7, 1, 1 },
}
local TEXT_COLOR_OPTS = {
    { "col_white", "white" }, { "col_yellow", "yellow" }, { "col_red", "red" }, { "col_green", "green" },
    { "col_blue", "blue" },
}

function effects.format(text)
    text = text:gsub("{flag:([%w_]+)}", function(n) return engine.flag(n) and AC.i18n.t("on") or AC.i18n.t("off") end)
    return (text:gsub("{([%w_]+)}", function(n) return tostring(engine.counter(n)) end))
end

local function until_(seconds)
    return seconds > 0 and Isaac.GetFrameCount() + seconds * 60 or nil -- render frames
end

def({ id = "screen_text", label = "a_screen_text",
    params = { P.text("text", "text", "kills: {kills}"), P.text("slot", "text_slot", "a"),
               P.number("x", "screen_x", 60, 0, 1000, 5), P.number("y", "screen_y", 40, 0, 600, 5),
               P.number("scale", "text_scale", 1, 0.5, 4, 0.25), P.choice("color", "color", "white", TEXT_COLOR_OPTS),
               P.number("seconds", "seconds_zero_forever", 0, 0, 600, 1) },
    run = function(p)
        effects.texts[p.slot] = { text = p.text, x = p.x, y = p.y, scale = p.scale,
                                  color = TEXT_COLORS[p.color], untilFrame = until_(p.seconds) }
    end })

def({ id = "big_text", label = "a_big_text",
    params = { P.text("text", "text", "round 2"), P.number("seconds", "seconds", 3, 0.5, 30, 0.5),
               P.choice("color", "color", "yellow", TEXT_COLOR_OPTS) },
    run = function(p)
        effects.texts["__big"] = { text = p.text, center = true, scale = 3, fade = true,
                                   color = TEXT_COLORS[p.color], untilFrame = until_(p.seconds), total = p.seconds * 60 }
    end })

entityAction("entity_text", "a_entity_text", { P.text("text", "text", "!"), P.number("seconds", "seconds", 3, 0.5, 60, 0.5) },
    function(e, p)
        effects.texts["__e" .. GetPtrHash(e)] = { text = p.text, entity = e, scale = 1,
                                                  color = TEXT_COLORS.white, untilFrame = until_(p.seconds) }
    end)

def({ id = "clear_text", label = "a_clear_text", params = { P.text("slot", "text_slot_all", "") },
    run = function(p)
        if p.slot == "" then effects.texts = {} else effects.texts[p.slot] = nil end
    end })

local function drawTexts()
    local now = Isaac.GetFrameCount()
    for slot, tx in pairs(effects.texts) do
        local gone = (tx.untilFrame and now > tx.untilFrame) or (tx.entity and not tx.entity:Exists())
        if gone then
            effects.texts[slot] = nil
        else
            local s = effects.format(tx.text)
            local c = tx.color or TEXT_COLORS.white
            local alpha = c[4]
            if tx.fade and tx.untilFrame then alpha = alpha * math.min(1, (tx.untilFrame - now) / 30) end
            local x, y = tx.x or 0, tx.y or 0
            if tx.center then
                x = (Isaac.GetScreenWidth() - AC.render.textWidth(s, tx.scale)) / 2
                y = Isaac.GetScreenHeight() * 0.3
            elseif tx.entity then
                local pos = Isaac.WorldToScreen(tx.entity.Position)
                x, y = pos.X - AC.render.textWidth(s) / 2, pos.Y - 45
            end
            AC.render.text(s, x, y, { c[1], c[2], c[3], alpha }, tx.scale)
        end
    end
end

function effects.reset()
    effects.texts = {}
    for _, e in ipairs(Isaac.GetRoomEntities()) do e:GetData().tboiacMove = nil end
end

effects.callbacks = {
    { ModCallbacks.MC_POST_UPDATE, updateBehaviours },
    { ModCallbacks.MC_POST_RENDER, drawTexts },
    { ModCallbacks.MC_POST_NEW_ROOM, function()
        for slot, tx in pairs(effects.texts) do if tx.entity then effects.texts[slot] = nil end end
    end },
}

return effects
