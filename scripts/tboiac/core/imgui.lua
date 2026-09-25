-- REPENTOGON ImGui window mirroring the mod's menu pages (mouse, real text input incl. Cyrillic).
-- Opened from the "TBOIAC" entry in the debug console's top bar (~). Pages are rendered from the
-- same page definitions as the in-game menu; changes are applied through the same get/set/fn.
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local imgui = {
    ready = false,
    stack = {},     -- page tables
    ids = {},       -- element ids in creation order
    itemStart = {}, -- item index -> first element index
    dirty = nil,    -- nil | "full" | item index to rebuild after (live text input)
    counter = 0,
}

local MENU, OPEN, WIN = "tboiacMenu", "tboiacMenuOpen", "tboiacWindow"

local function resolve(v)
    if type(v) == "function" then return v() end
    return v
end

function imgui.enabled()
    return AC.hasRepentogon and ImGui ~= nil and AC.save.data.ui.imgui
end

local function newId()
    imgui.counter = imgui.counter + 1
    local id = "tboiacE" .. imgui.counter
    imgui.ids[#imgui.ids + 1] = id
    return id
end

local function clearFrom(index)
    for i = #imgui.ids, index, -1 do
        pcall(ImGui.RemoveElement, imgui.ids[i])
        imgui.ids[i] = nil
    end
end

-- Menu code calls menu.push/pop (e.g. "new rule" opens the rule page); inside ImGui callbacks those
-- must move the ImGui page stack instead of the in-game menu.
local function run(fn, ...)
    local menu = AC.menu
    local push, pop = menu.push, menu.pop
    menu.push = function(page)
        if type(page) == "string" then page = menu.pages[page] end
        if page then table.insert(imgui.stack, page) end
    end
    menu.pop = function()
        if #imgui.stack > 1 then table.remove(imgui.stack) end
    end
    local ok, err = pcall(fn, ...)
    menu.push, menu.pop = push, pop
    if not ok then
        AC.util.log("imgui error: " .. tostring(err))
        pcall(ImGui.PushNotification, t("error", tostring(err)), ImGuiNotificationType.ERROR, 5000)
    end
    AC.save.markDirty()
    imgui.dirty = imgui.dirty or "full"
end

local function optionLabels(item)
    local opts = resolve(item.options) or {}
    local labels, selected = {}, 0
    local cur = item.get()
    for i, o in ipairs(opts) do
        labels[i] = resolve(o[1])
        if o[2] == cur then selected = i - 1 end
    end
    return opts, labels, selected
end

local function addItem(item, index)
    local label = resolve(item.label) or ""
    local kind = item.kind
    if kind == "info" then
        if label == "" then
            ImGui.AddElement(WIN, newId(), ImGuiElement.Separator, "")
        else
            ImGui.AddText(WIN, label, true, newId())
        end
    elseif kind == "action" then
        ImGui.AddButton(WIN, newId(), label, function() run(item.fn) end, false)
    elseif kind == "page" then
        ImGui.AddButton(WIN, newId(), label .. "  >", function()
            run(function() AC.menu.push(resolve(item.page)) end)
        end, false)
    elseif kind == "toggle" then
        ImGui.AddCheckbox(WIN, newId(), label, function(v) run(item.set, v) end, item.get() == true)
    elseif kind == "number" then
        local id = newId()
        local min = item.min or -1000000
        local max = item.max or 1000000
        local step = item.step or 1
        local fmtId
        local function changed(v)
            v = AC.util.clamp(v, min, max)
            run(item.set, v)
            if fmtId then pcall(ImGui.UpdateText, fmtId, item.fmt(v)) end
            imgui.dirty = nil -- keep the drag widget alive while it is being dragged
        end
        if step < 1 then
            ImGui.AddDragFloat(WIN, id, label, changed, item.get(), step, min, max, "%.2f")
        else
            ImGui.AddDragInteger(WIN, id, label, changed, math.floor(item.get()), step, min, max, "%d")
        end
        if item.fmt then
            ImGui.AddElement(WIN, newId(), ImGuiElement.SameLine, "")
            fmtId = newId()
            ImGui.AddText(WIN, item.fmt(item.get()), false, fmtId)
        end
    elseif kind == "choice" then
        local opts, labels, selected = optionLabels(item)
        ImGui.AddCombobox(WIN, newId(), label, function(i, val)
            local pick
            for n, l in ipairs(labels) do if l == val then pick = opts[n] end end
            pick = pick or opts[(i or 0) + 1]
            if pick then run(item.set, pick[2]) end
        end, labels, selected, false)
    elseif kind == "text" then
        ImGui.AddInputText(WIN, newId(), label, function(s)
            run(item.set, s)
            -- live inputs (search) refresh the rest of the page but keep the input itself focused
            imgui.dirty = item.live and index or nil
        end, item.get() or "", "")
    end
end

local function build()
    local page = imgui.stack[#imgui.stack]
    local ok, items = pcall(function() return page.build and page.build() or page.items or {} end)
    if not ok then return { { kind = "info", label = "Error: " .. tostring(items) } } end
    return items
end

local function rebuild(after)
    local items = build()
    if after and imgui.itemStart[after + 1] then
        clearFrom(imgui.itemStart[after + 1])
    else
        clearFrom(1)
        after = 0
        local crumbs = {}
        for _, p in ipairs(imgui.stack) do crumbs[#crumbs + 1] = resolve(p.title) or "?" end
        ImGui.AddText(WIN, table.concat(crumbs, " / "), true, newId())
        if #imgui.stack > 1 then
            ImGui.AddButton(WIN, newId(), "< " .. t("back"), function()
                run(function() AC.menu.pop() end) -- resolved inside run(), where pop is redirected
            end, true)
            ImGui.AddElement(WIN, newId(), ImGuiElement.SameLine, "")
            ImGui.AddButton(WIN, newId(), t("home"), function()
                run(function() imgui.stack = { imgui.stack[1] } end)
            end, true)
            ImGui.AddElement(WIN, newId(), ImGuiElement.SameLine, "")
        end
        ImGui.AddButton(WIN, newId(), t("refresh"), function() run(function() end) end, true)
        ImGui.AddElement(WIN, newId(), ImGuiElement.Separator, "")
    end
    for i = after + 1, #items do
        imgui.itemStart[i] = #imgui.ids + 1
        local ok, err = pcall(addItem, items[i], i)
        if not ok then AC.util.log("imgui item error: " .. tostring(err)) end
    end
    for i = #items + 1, #imgui.itemStart do imgui.itemStart[i] = nil end
end

function imgui.init()
    if not (AC.hasRepentogon and ImGui ~= nil) then return end
    if ImGui.ElementExists(MENU) then ImGui.RemoveMenu(MENU) end -- luamod reload
    if ImGui.ElementExists(WIN) then ImGui.RemoveWindow(WIN) end
    ImGui.CreateMenu(MENU, "TBOIAC")
    ImGui.AddElement(MENU, OPEN, ImGuiElement.MenuItem, t("imgui_open"))
    ImGui.CreateWindow(WIN, "TBOIAC v" .. AC.version)
    ImGui.LinkWindowToElement(WIN, OPEN)
    ImGui.SetWindowSize(WIN, 560, 640)
    imgui.stack = { AC.menu.pages.root }
    imgui.ids, imgui.itemStart = {}, {}
    imgui.ready, imgui.dirty = true, "full"
end

function imgui.shutdown()
    if not imgui.ready then return end
    pcall(ImGui.RemoveWindow, WIN)
    pcall(ImGui.RemoveMenu, MENU)
    imgui.ready = false
end

-- True while the ImGui overlay has focus: game-side hotkeys must not fire while typing there.
function imgui.active()
    if not (AC.hasRepentogon and ImGui ~= nil) then return false end
    local ok, v = pcall(ImGui.IsVisible)
    return ok and v == true
end

-- Called every render frame.
function imgui.update()
    local on = AC.save.data.ui.imgui
    if on and not imgui.ready then imgui.init() end
    if not on and imgui.ready then imgui.shutdown() end
    if not imgui.ready then return end
    if imgui.dirty then
        local d = imgui.dirty
        imgui.dirty = nil
        rebuild(type(d) == "number" and d or nil)
    end
end

return imgui
