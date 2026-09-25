-- Time: slow/fast world, freeze enemies and projectiles, "stop world" while menu is open.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "time", label = "m_time" }

local function S() return AC.save.data.time end

local MODES = function()
    return { { t("time_normal"), 0 }, { t("time_slow"), 1 }, { t("time_fast"), 2 } }
end

local watchApplied = false

local function applyWatch()
    local mode = S().mode
    local room = AC.game:GetRoom()
    if mode ~= 0 then
        room:SetBrokenWatchState(mode)
        watchApplied = true
    elseif watchApplied then
        room:SetBrokenWatchState(0)
        watchApplied = false
    end
end

local function worldStopped()
    return AC.menu.open and AC.save.data.ui.pauseWorld
end

local function freezeNpc(npc)
    local data = npc:GetData()
    if not data.tboiacFreezePos then
        data.tboiacFreezePos = npc.Position
        npc:AddEntityFlags(EntityFlag.FLAG_FREEZE)
    end
    npc.Position = data.tboiacFreezePos
    npc.Velocity = Vector.Zero
end

local function unfreezeNpc(npc)
    local data = npc:GetData()
    if data.tboiacFreezePos then
        data.tboiacFreezePos = nil
        npc:ClearEntityFlags(EntityFlag.FLAG_FREEZE)
    end
end

local function freezeProjectile(proj)
    local data = proj:GetData()
    if not data.tboiacVel then
        data.tboiacVel = proj.Velocity
        data.tboiacFall = { proj.FallingSpeed, proj.FallingAccel }
    end
    proj.Velocity = Vector.Zero
    proj.FallingSpeed = 0
    proj.FallingAccel = 0
end

local function unfreezeProjectile(proj)
    local data = proj:GetData()
    if data.tboiacVel then
        proj.Velocity = data.tboiacVel
        proj.FallingSpeed, proj.FallingAccel = data.tboiacFall[1], data.tboiacFall[2]
        data.tboiacVel, data.tboiacFall = nil, nil
    end
end

local function onUpdate()
    applyWatch()
    local stop = worldStopped()
    local freezeEnemies = stop or S().freezeEnemies
    local freezeShots = stop or S().freezeProjectiles
    for _, e in ipairs(Isaac.GetRoomEntities()) do
        local npc = e:ToNPC()
        local proj = e:ToProjectile()
        if npc and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            if freezeEnemies then freezeNpc(npc) else unfreezeNpc(npc) end
        elseif proj then
            if freezeShots then freezeProjectile(proj) else unfreezeProjectile(proj) end
        end
    end
end

feature.pages = {
    time = {
        title = function() return t("m_time") end,
        build = function()
            return {
                menu.choice(t("time_speed"), "time", "mode", MODES),
                menu.toggle(t("freeze_enemies"), "time", "freezeEnemies"),
                menu.toggle(t("freeze_projectiles"), "time", "freezeProjectiles"),
                menu.toggle(t("pause_world_menu"), "ui", "pauseWorld"),
                menu.action(t("stop_world"), function()
                    local s = S()
                    local v = not (s.freezeEnemies and s.freezeProjectiles)
                    s.freezeEnemies, s.freezeProjectiles = v, v
                    AC.render.toast(v and t("world_stopped") or t("world_resumed"))
                end),
                menu.action(t("use_stopwatch"), function()
                    util.firstTarget():UseActiveItem(CollectibleType.COLLECTIBLE_PAUSE, UseFlag.USE_NOANIM)
                end),
                menu.action(t("reset_timer"), function()
                    if pcall(function() AC.game.TimeCounter = 0 end) then
                        AC.render.toast(t("timer_reset"))
                    end
                end),
            }
        end,
    },
}

feature.callbacks = {
    { ModCallbacks.MC_POST_UPDATE, onUpdate },
    { ModCallbacks.MC_POST_NEW_ROOM, function() watchApplied = false end },
}

function feature.reset()
    local s = S()
    s.mode, s.freezeEnemies, s.freezeProjectiles = 0, false, false
    AC.save.data.ui.pauseWorld = false
end

return feature
