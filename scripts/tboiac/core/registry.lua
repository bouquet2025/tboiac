-- Feature registry. A feature is a table:
--   id        unique string
--   label     i18n key for the root menu entry
--   pages     { [pageId] = page }  (see menu.lua); the page named `id` is the entry page
--   callbacks { { ModCallbacks.X, fn, optionalParam }, ... }
--   init()    optional, called once after all features are registered
--   reset()   optional, called by the panic button to drop every active modifier
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local registry = { features = {} }

function registry.register(feature)
    table.insert(registry.features, feature)
    for id, page in pairs(feature.pages or {}) do
        AC.menu.definePage(id, page)
    end
end

function registry.resetAll()
    for _, f in ipairs(registry.features) do
        if f.reset then f.reset() end
    end
    AC.save.write()
    AC.render.toast(t("panic_done"))
end

local function buildRoot()
    local items = {}
    for _, f in ipairs(registry.features) do
        if f.label and AC.menu.pages[f.id] then
            items[#items + 1] = { kind = "page", label = t(f.label), page = f.id }
        end
    end
    items[#items + 1] = { kind = "info", label = "" }
    items[#items + 1] = { kind = "action", label = t("panic"), fn = registry.resetAll }
    return items
end

function registry.start()
    local mod = AC.mod
    AC.save.load()

    AC.menu.definePage("root", {
        title = function() return "TBOIAC v" .. AC.version end,
        build = buildRoot,
    })

    mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
        AC.menu.update()
        AC.menu.draw()
        AC.render.drawToasts()
        AC.save.flush()
        AC.imgui.update()
    end)
    mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, AC.input.onInputAction)
    mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function() AC.save.load() end)
    mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function()
        if AC.menu.open then AC.menu.setOpen(false) end
        AC.save.write()
    end)

    for _, f in ipairs(registry.features) do
        for _, cb in ipairs(f.callbacks or {}) do
            local fn = cb[2]
            local safe = function(...)
                local ok, a, b = pcall(fn, ...)
                if not ok then
                    AC.util.log("error in " .. f.id .. ": " .. tostring(a))
                    return nil
                end
                return a, b
            end
            if cb[3] ~= nil then
                mod:AddCallback(cb[1], safe, cb[3])
            else
                mod:AddCallback(cb[1], safe)
            end
        end
    end
    for _, f in ipairs(registry.features) do
        if f.init then f.init() end
    end
    AC.imgui.init()
end

return registry
