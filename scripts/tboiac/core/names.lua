-- Display names in the game's current language. Needs REPENTOGON (Isaac.GetString, EntityConfig);
-- without it every function returns nil and callers fall back to their own names.
local AC = TBOIAC

local names = {}

local function enabled()
    return AC.hasRepentogon and AC.save.data.ui.gameNames
end

local function valid(s, key)
    return type(s) == "string" and s ~= "" and s ~= key and s:sub(1, 1) ~= "#"
end

-- String-table lookup; keys may come with or without the leading "#".
function names.localize(category, key)
    if not enabled() or type(key) ~= "string" or key == "" then return nil end
    local ok, s = pcall(Isaac.GetString, category, key)
    if ok and valid(s, key) then return s end
    if key:sub(1, 1) == "#" then
        local bare = key:sub(2)
        ok, s = pcall(Isaac.GetString, category, bare)
        if ok and valid(s, bare) then return s end
    end
    return nil
end

function names.entity(etype, variant)
    if not enabled() or not EntityConfig then return nil end
    local ok, cfg = pcall(EntityConfig.GetEntity, etype, variant)
    if not ok or not cfg then return nil end
    local name = cfg:GetName()
    return names.localize("Entities", name) or (valid(name, "") and name or nil)
end

function names.character(ptype)
    if not enabled() or not EntityConfig then return nil end
    local ok, cfg = pcall(EntityConfig.GetPlayer, ptype)
    if not ok or not cfg then return nil end
    local name = cfg:GetName()
    return names.localize("Players", name) or (valid(name, "") and name or nil)
end

-- UTF-8 aware lower case for Latin and Cyrillic (for search).
function names.lower(s)
    s = s:lower()
    s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end) -- А-П
    s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end) -- Р-Я
    return (s:gsub("\208\129", "\209\145")) -- Ё
end

return names
