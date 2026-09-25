-- TBOIAC - Isaac Admin Console
-- Sandbox menu for The Binding of Isaac: Repentance+.

local mod = RegisterMod("TBOIAC", 1)

TBOIAC = {
    mod = mod,
    version = "0.8.0",
    game = Game(),
    hasRepentogon = REPENTOGON ~= nil,
}
local AC = TBOIAC

local function load(path)
    return include("scripts.tboiac." .. path)
end

AC.util = load("core.util")
AC.data = load("data.game")
AC.i18n = load("core.i18n")
AC.names = load("core.names")
AC.save = load("core.save")
AC.input = load("core.input")
AC.render = load("core.render")
AC.menu = load("core.menu")
AC.catalog = load("core.catalog")
AC.grid = load("core.grid")
AC.icons = load("core.icons")
AC.registry = load("core.registry")
AC.imgui = load("core.imgui")

AC.ruleParams = load("rules.params")
AC.rules = load("rules.engine")
AC.ruleEvents = load("rules.events")
load("rules.conditions")
AC.ruleActions = load("rules.actions")
AC.ruleEffects = load("rules.effects")
AC.rulePresets = load("rules.presets")
AC.ruleEditor = load("rules.editor")
AC.registry.register(AC.ruleEditor)

local features = {
    "quick",
    "player",
    "items",
    "pools",
    "pickups",
    "drops",
    "time",
    "enemies",
    "waves",
    "world",
    "studio",
    "settings",
}
for _, name in ipairs(features) do
    AC.registry.register(load("features." .. name))
end

AC.registry.register({ id = "icons", callbacks = AC.icons.callbacks })

-- Tabs across the top of the menu (the root list stays for the ImGui window).
AC.menu.tabs = {
    { label = "tab_quick", page = "quick" }, { label = "tab_player", page = "player" },
    { label = "tab_items", page = "items" }, { label = "tab_enemies", page = "enemies" },
    { label = "tab_world", page = "world" }, { label = "tab_rules", page = "rules" },
    { label = "tab_studio", page = "studio" }, { label = "tab_settings", page = "settings" },
}

AC.registry.start()
AC.util.log("loaded v" .. AC.version .. (AC.hasRepentogon and " (REPENTOGON)" or ""))
