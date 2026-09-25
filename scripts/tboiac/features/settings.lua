-- Menu settings: language, look, hotkey.
local AC = TBOIAC
local menu, util = AC.menu, AC.util
local t = function(...) return AC.i18n.t(...) end

local feature = { id = "settings", label = "m_settings" }

local function hotkeys()
    local list = {}
    for i = 1, 12 do
        local key = Keyboard["KEY_F" .. i]
        if key then list[#list + 1] = { "F" .. i, key } end
    end
    list[#list + 1] = { "Insert", Keyboard.KEY_INSERT }
    list[#list + 1] = { "Home", Keyboard.KEY_HOME }
    list[#list + 1] = { "`", Keyboard.KEY_GRAVE_ACCENT }
    return list
end

feature.pages = {
    settings = {
        title = function() return t("m_settings") end,
        build = function()
            return {
                menu.choice(t("language"), "ui", "lang", { { "Русский", "ru" }, { "English", "en" } }),
                menu.choice(t("open_key"), "keys", "open", hotkeys),
                menu.number(t("ui_scale"), "ui", "scale", 0.5, 2, 0.25),
                menu.number(t("ui_alpha"), "ui", "alpha", 0, 1, 0.1),
                menu.number(t("ui_x"), "ui", "x", 0, 400, 5),
                menu.number(t("ui_y"), "ui", "y", 0, 300, 5),
                menu.toggle(t("pause_world_menu"), "ui", "pauseWorld"),
                menu.info(t("pad_hint")),
                menu.action(t("reset_settings"), function()
                    AC.save.data.ui = util.copy(AC.save.defaults.ui)
                    AC.save.data.keys = util.copy(AC.save.defaults.keys)
                end),
            }
        end,
    },
}

return feature
