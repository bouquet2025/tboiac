-- TBOIAC - Isaac Admin Console
-- Sandbox menu for The Binding of Isaac: Repentance+.

local mod = RegisterMod("TBOIAC", 1)

TBOIAC = {
    mod = mod,
    version = "0.6.0",
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
AC.save = load("core.save")
AC.input = load("core.input")
AC.render = load("core.render")
AC.menu = load("core.menu")
AC.catalog = load("core.catalog")
AC.icons = load("core.icons")
AC.registry = load("core.registry")

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

AC.registry.start()
AC.util.log("loaded v" .. AC.version .. (AC.hasRepentogon and " (REPENTOGON)" or ""))
