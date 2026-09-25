-- World: teleports, floor warps, map, curses, room tools, run control, console.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "world", label = "m_world" }
local ROOM_TYPES, STAGES, CURSES = AC.data.ROOM_TYPES, AC.data.STAGES, AC.data.CURSES
local teleport, findRoom, roomTypeName = util.teleport, util.findRoom, util.roomTypeName

local state = { command = "", layout = "" }

local function openDoors()
    local room = AC.game:GetRoom()
    for slot = 0, DoorSlot.NUM_DOOR_SLOTS - 1 do
        local door = room:GetDoor(slot)
        if door then door:Open() end
    end
end

local function gridAtPlayer(gtype)
    local room = AC.game:GetRoom()
    local pos = room:FindFreeTilePosition(util.firstTarget().Position + Vector(0, 80), 200)
    Isaac.GridSpawn(gtype, 0, pos, true)
end

feature.pages = {
    world = {
        title = function() return t("m_world") end,
        build = function()
            return {
                menu.link(t("m_teleport"), "world_teleport"),
                menu.link(t("m_rooms"), "world_rooms"),
                menu.link(t("m_stages"), "world_stages"),
                menu.link(t("m_room_tools"), "world_room"),
                menu.link(t("m_curses"), "world_curses"),
                menu.link(t("m_run"), "world_run"),
                menu.link(t("m_console"), "world_console"),
                menu.action(t("reveal_map"), function()
                    local level = AC.game:GetLevel()
                    level:ApplyMapEffect()
                    level:ApplyBlueMapEffect()
                    level:ApplyCompassEffect(true)
                    AC.render.toast(t("map_revealed"))
                end),
            }
        end,
    },
    world_teleport = {
        title = function() return t("m_teleport") end,
        build = function()
            local level = AC.game:GetLevel()
            local items = {
                menu.action(t("tp_start"), function() teleport(level:GetStartingRoomIndex()) end),
                menu.action(t("tp_devil"), function() teleport(GridRooms.ROOM_DEVIL_IDX) end),
                menu.action(t("tp_error"), function() teleport(GridRooms.ROOM_ERROR_IDX) end),
                menu.action(t("tp_black_market"), function() teleport(GridRooms.ROOM_BLACK_MARKET_IDX) end),
            }
            for _, r in ipairs(ROOM_TYPES) do
                if r[2] ~= RoomType.ROOM_DEFAULT then
                    items[#items + 1] = menu.action(t("tp_to", t(r[1])), function()
                        local idx = findRoom(r[2])
                        if idx then teleport(idx) else AC.render.toast(t("no_such_room")) end
                    end)
                end
            end
            return items
        end,
    },
    world_rooms = {
        title = function() return t("m_rooms") end,
        build = function()
            local items = {}
            local level = AC.game:GetLevel()
            local current = level:GetCurrentRoomIndex()
            local rooms = level:GetRooms()
            for i = 0, rooms.Size - 1 do
                local desc = rooms:Get(i)
                if desc.Data then
                    local idx = desc.SafeGridIndex
                    local label = string.format("%s  [%d]%s%s", roomTypeName(desc.Data.Type), idx,
                        desc.Clear and "" or " *", idx == current and " <" or "")
                    items[#items + 1] = menu.action(label, function() teleport(idx) end)
                end
            end
            return items
        end,
    },
    world_stages = {
        title = function() return t("m_stages") end,
        build = function()
            local items = { menu.info(t("console_warning")) }
            for _, s in ipairs(STAGES) do
                items[#items + 1] = menu.action(s[1], function()
                    AC.menu.setOpen(false)
                    util.command("stage " .. s[2] .. s[3])
                end)
            end
            return items
        end,
    },
    world_room = {
        title = function() return t("m_room_tools") end,
        build = function()
            return {
                menu.action(t("clear_room"), function()
                    for _, npc in ipairs(util.enemies()) do npc:Kill() end
                    AC.game:GetRoom():SetClear(true)
                    openDoors()
                end),
                menu.action(t("open_doors"), openDoors),
                menu.action(t("spawn_trapdoor"), function() gridAtPlayer(GridEntityType.GRID_TRAPDOOR) end),
                menu.action(t("spawn_crawlspace"), function() gridAtPlayer(GridEntityType.GRID_STAIRS) end),
                menu.action(t("spawn_light"), function()
                    Isaac.Spawn(EntityType.ENTITY_EFFECT, EffectVariant.HEAVEN_LIGHT_DOOR, 0,
                        util.spawnPos(), Vector.Zero, nil)
                end),
                menu.action(t("spawn_rock"), function() gridAtPlayer(GridEntityType.GRID_ROCK) end),
                menu.action(t("spawn_pit"), function() gridAtPlayer(GridEntityType.GRID_PIT) end),
                menu.action(t("spawn_spikes"), function() gridAtPlayer(GridEntityType.GRID_SPIKES) end),
                menu.action(t("remove_grid"), function()
                    local room = AC.game:GetRoom()
                    for i = 0, room:GetGridSize() - 1 do
                        local g = room:GetGridEntity(i)
                        local gt = g and g:GetType()
                        if g and gt ~= GridEntityType.GRID_WALL and gt ~= GridEntityType.GRID_DOOR then
                            room:RemoveGridEntity(i, 0, false)
                        end
                    end
                    room:Update()
                end),
                menu.action(t("restart_room"), function()
                    teleport(AC.game:GetLevel():GetCurrentRoomIndex())
                end),
            }
        end,
    },
    world_curses = {
        title = function() return t("m_curses") end,
        build = function()
            local items = { menu.toggle(t("no_curses"), "world", "noCurses", function(v)
                if v then AC.game:GetLevel():RemoveCurses(AC.game:GetLevel():GetCurses()) end
            end) }
            for _, c in ipairs(CURSES) do
                items[#items + 1] = {
                    kind = "toggle", label = t(c[1]),
                    get = function() return AC.game:GetLevel():GetCurses() & c[2] ~= 0 end,
                    set = function(v)
                        local level = AC.game:GetLevel()
                        if v then level:AddCurse(c[2], false) else level:RemoveCurses(c[2]) end
                    end,
                }
            end
            return items
        end,
    },
    world_run = {
        title = function() return t("m_run") end,
        build = function()
            local seeds = AC.game:GetSeeds()
            return {
                menu.info(t("seed_is", seeds:GetStartSeedString())),
                menu.action(t("restart_run"), function() util.command("restart") end),
                menu.action(t("restart_same_char"), function()
                    util.command("restart " .. Isaac.GetPlayer(0):GetPlayerType())
                end),
                menu.action(t("reseed_floor"), function() util.command("reseed") end),
            }
        end,
    },
    world_console = {
        title = function() return t("m_console") end,
        build = function()
            return {
                menu.info(t("console_warning")),
                { kind = "text", label = t("goto_layout"),
                  get = function() return state.layout end, set = function(s) state.layout = s end },
                menu.action(t("goto_run"), function()
                    if state.layout ~= "" then AC.menu.setOpen(false) util.command("goto " .. state.layout) end
                end),
                { kind = "text", label = t("command"),
                  get = function() return state.command end, set = function(s) state.command = s end },
                menu.action(t("command_run"), function()
                    if state.command ~= "" then
                        local out = util.command(state.command)
                        AC.render.toast(out ~= nil and out ~= "" and tostring(out) or t("done"))
                    end
                end),
            }
        end,
    },
}

feature.callbacks = {
    { ModCallbacks.MC_POST_CURSE_EVAL, function(_, curses)
        if AC.save.data.world.noCurses then return 0 end
        return nil
    end },
}

function feature.reset()
    AC.save.data.world.noCurses = false
end

return feature
