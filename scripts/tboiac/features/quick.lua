-- "Quick" tab: the most used actions on one page.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "quick" } -- shown as the first tab, not in the root list

local function stopped()
    local time = AC.save.data.time
    return time.freezeEnemies and time.freezeProjectiles
end

feature.pages = {
    quick = {
        layout = "tiles",
        title = function() return t("tab_quick") end,
        build = function()
            return {
                menu.link(t("q_item"), "items_grid"),
                menu.link(t("q_boss"), "boss_grid"),
                menu.link(t("q_enemy"), "enemy_grid"),
                menu.link(t("q_pickup"), "pickups_grid"),
                menu.toggle(t("god"), "player", "god"),
                { kind = "toggle", label = t("q_stop"), get = stopped, set = function(v)
                    AC.save.data.time.freezeEnemies, AC.save.data.time.freezeProjectiles = v, v
                end },
                menu.choice(t("time_speed"), "time", "mode", function()
                    return { { t("time_normal"), 0 }, { t("time_slow"), 1 }, { t("time_fast"), 2 } }
                end),
                menu.action(t("kill_all"), function()
                    for _, npc in ipairs(util.enemies()) do npc:Kill() end
                end),
                menu.link(t("m_teleport"), "world_teleport"),
                { kind = "toggle", label = t("q_clean"), get = function() return AC.save.data.studio.clean end,
                  set = function(v) AC.studio.setClean(v) end },
                menu.action(t("panic"), AC.registry.resetAll),
            }
        end,
    },
}

return feature
