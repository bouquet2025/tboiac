local AC = TBOIAC

local i18n = {
    langs = {
        en = include("scripts.tboiac.core.lang.en"),
        ru = include("scripts.tboiac.core.lang.ru"),
    },
    order = { "ru", "en" },
}

-- Translate `key`; extra arguments are passed to string.format.
function i18n.t(key, ...)
    local lang = AC.save and AC.save.data.ui.lang or "en"
    local s = (i18n.langs[lang] or {})[key] or i18n.langs.en[key] or key
    if select("#", ...) > 0 then
        return string.format(s, ...)
    end
    return s
end

-- Reverse lookup: translation key of a menu label (labels may carry "  ", "+ " or "> " prefixes).
local reverse = {}
function i18n.keyFor(label)
    local lang = AC.save and AC.save.data.ui.lang or "en"
    local map = reverse[lang]
    if not map then
        map = {}
        for k, v in pairs(i18n.langs.en) do map[v] = map[v] or k end
        for k, v in pairs(i18n.langs[lang] or {}) do map[v] = k end
        reverse[lang] = map
    end
    if type(label) ~= "string" then return nil end
    return map[label] or map[(label:gsub("^[%s%+>]+", ""))]
end

-- Description ("<key>_d") of a menu label, or nil.
function i18n.desc(label)
    local key = i18n.keyFor(label)
    if not key then return nil end
    local lang = AC.save and AC.save.data.ui.lang or "en"
    return (i18n.langs[lang] or {})[key .. "_d"] or i18n.langs.en[key .. "_d"]
end

-- Like t(), but returns `s` unchanged when it is not a translation key (plain names).
function i18n.label(s)
    local lang = AC.save and AC.save.data.ui.lang or "en"
    return (i18n.langs[lang] or {})[s] or i18n.langs.en[s] or s
end

return i18n
