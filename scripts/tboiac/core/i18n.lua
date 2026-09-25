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

-- Like t(), but returns `s` unchanged when it is not a translation key (plain names).
function i18n.label(s)
    local lang = AC.save and AC.save.data.ui.lang or "en"
    return (i18n.langs[lang] or {})[s] or i18n.langs.en[s] or s
end

return i18n
