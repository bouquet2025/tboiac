-- Page-based menu. A page is { title = string|fn, build = fn() -> items, live = bool }.
-- Item kinds:
--   { kind = "action", label, fn }
--   { kind = "toggle", label, get, set }
--   { kind = "number", label, get, set, min, max, step, fmt }
--   { kind = "choice", label, options = { {label, value}, ... }, get, set }
--   { kind = "page",   label, page = id | pageTable }
--   { kind = "text",   label, get, set, live }  -- keyboard text entry
--   { kind = "info",   label }                  -- not selectable
-- Labels may be strings or functions returning strings.
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local menu = {
    open = false,
    pages = {},
    stack = {},
}

local COLORS = {
    title = { 1, 0.85, 0.3, 1 },
    normal = { 1, 1, 1, 1 },
    selected = { 0.4, 1, 0.5, 1 },
    info = { 0.65, 0.65, 0.7, 1 },
    on = { 0.4, 1, 0.5, 1 },
    off = { 1, 0.45, 0.45, 1 },
    hint = { 0.7, 0.7, 0.75, 1 },
}

local function resolve(v)
    if type(v) == "function" then return v() end
    return v
end

local function selectable(item)
    return item and item.kind ~= "info"
end

function menu.definePage(id, page)
    page.id = id
    menu.pages[id] = page
    return page
end

local function top() return menu.stack[#menu.stack] end

local function rebuild(frame)
    local ok, items = pcall(function()
        return frame.page.build and frame.page.build() or frame.page.items or {}
    end)
    if not ok then
        AC.util.log("page error: " .. tostring(items))
        items = { { kind = "info", label = "Error: " .. tostring(items) } }
    end
    frame.items = items
    if #frame.items == 0 then
        frame.cursor = 1
        return
    end
    frame.cursor = AC.util.clamp(frame.cursor, 1, #frame.items)
    if not selectable(frame.items[frame.cursor]) then
        for i = 1, #frame.items do
            if selectable(frame.items[i]) then frame.cursor = i break end
        end
    end
end

function menu.refresh()
    local frame = top()
    if frame then rebuild(frame) end
end

function menu.push(page)
    if type(page) == "string" then page = menu.pages[page] end
    if not page then return end
    local frame = { page = page, cursor = 1, scroll = 0 }
    table.insert(menu.stack, frame)
    rebuild(frame)
end

function menu.pop()
    table.remove(menu.stack)
    if #menu.stack == 0 then
        menu.setOpen(false)
    else
        rebuild(top())
    end
end

function menu.setOpen(v)
    menu.open = v
    AC.input.blocking = v
    AC.input.textTarget = nil
    AC.input.held = {}
    if v then
        menu.stack = {}
        menu.push("root")
    else
        AC.save.write()
    end
end

local function numberStep(item)
    local step = item.step or 1
    if AC.input.shift() then step = step * 10 end
    return step
end

local function change(item, dir)
    if item.kind == "number" then
        local v = item.get() + numberStep(item) * dir
        v = AC.util.round(v, (item.step or 1) < 1 and 0.01 or 1)
        item.set(AC.util.clamp(v, item.min or -math.huge, item.max or math.huge))
    elseif item.kind == "choice" then
        local cur, opts = item.get(), resolve(item.options)
        local idx = 1
        for i, o in ipairs(opts) do if o[2] == cur then idx = i break end end
        idx = (idx - 1 + dir) % #opts + 1
        item.set(opts[idx][2])
    elseif item.kind == "toggle" then
        item.set(not item.get())
    else
        return
    end
    AC.save.markDirty()
    menu.refresh()
end

-- Menu callbacks touch the game API; an error must not kill the render callback.
local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        AC.util.log("menu error: " .. tostring(err))
        AC.render.toast(t("error", tostring(err)), 180)
    end
    AC.save.markDirty()
end

local function activate(item)
    if item.kind == "action" then
        safe(item.fn)
        menu.refresh()
    elseif item.kind == "toggle" then
        change(item, 1)
    elseif item.kind == "page" then
        menu.push(resolve(item.page))
    elseif item.kind == "text" then
        AC.input.beginText({
            text = item.get(),
            onChange = function(s) if item.live then item.set(s) menu.refresh() end end,
            onDone = function(s) item.set(s) menu.refresh() end,
        })
    elseif item.kind == "number" or item.kind == "choice" then
        change(item, 1)
    end
end

local function moveCursor(frame, dir)
    local n = #frame.items
    if n == 0 then return end
    local i = frame.cursor
    for _ = 1, n do
        i = (i - 1 + dir) % n + 1
        if selectable(frame.items[i]) then break end
    end
    frame.cursor = i
end

function menu.update()
    if AC.input.toggleMenuPressed() then
        menu.setOpen(not menu.open)
        return
    end
    if not menu.open then return end
    if AC.input.textTarget then
        AC.input.updateText()
        return
    end
    local frame = top()
    if frame.page.live then rebuild(frame) end
    local ev = AC.input.poll()
    local item = frame.items[frame.cursor]
    if ev.back then
        menu.pop()
    elseif ev.up then
        moveCursor(frame, -1)
    elseif ev.down then
        moveCursor(frame, 1)
    elseif item and ev.left then
        safe(change, item, -1)
    elseif item and ev.right then
        safe(change, item, 1)
    elseif item and ev.confirm then
        safe(activate, item)
    end
end

local function valueText(item, selected)
    if item.kind == "toggle" then
        local on = item.get()
        return on and t("on") or t("off"), on and COLORS.on or COLORS.off
    elseif item.kind == "number" then
        local v = item.get()
        local s = item.fmt and item.fmt(v) or (math.type and math.type(v) == "integer" and tostring(v))
            or string.format("%.2f", v):gsub("%.?0+$", "")
        return "< " .. s .. " >"
    elseif item.kind == "choice" then
        local cur = item.get()
        for _, o in ipairs(resolve(item.options)) do
            if o[2] == cur then return "< " .. resolve(o[1]) .. " >" end
        end
        return "< ? >"
    elseif item.kind == "text" then
        local editing = selected and AC.input.textTarget ~= nil
        local s = editing and AC.input.textTarget.text or item.get()
        return "[" .. s .. (editing and (Isaac.GetFrameCount() // 15 % 2 == 0 and "_" or " ") or "") .. "]"
    elseif item.kind == "page" then
        return ">"
    end
    return nil
end

function menu.draw()
    if not menu.open then return end
    local frame = top()
    if not frame then return end
    local ui = AC.save.data.ui
    local lh = AC.render.lineHeight()
    local x, y = ui.x, ui.y
    local width = math.max(260, Isaac.GetScreenWidth() * 0.45)
    local rows = math.max(3, math.floor((Isaac.GetScreenHeight() - y - lh * 4) / lh))

    if frame.cursor <= frame.scroll then frame.scroll = frame.cursor - 1 end
    if frame.cursor > frame.scroll + rows then frame.scroll = frame.cursor - rows end
    local shown = math.min(rows, #frame.items)

    AC.render.rect(x - 6, y - 4, width, lh * (shown + 3) + 8, { 0, 0, 0, ui.alpha })

    local crumbs = {}
    for _, f in ipairs(menu.stack) do crumbs[#crumbs + 1] = resolve(f.page.title) end
    AC.render.text(table.concat(crumbs, " / "), x, y, COLORS.title)
    y = y + lh * 1.3

    if #frame.items == 0 then
        AC.render.text(t("empty"), x, y, COLORS.info)
    end
    for i = frame.scroll + 1, math.min(#frame.items, frame.scroll + rows) do
        local item = frame.items[i]
        local sel = i == frame.cursor
        local color = item.kind == "info" and COLORS.info or (sel and COLORS.selected or COLORS.normal)
        AC.render.text((sel and "> " or "  ") .. resolve(item.label), x, y, color)
        local v, vcolor = valueText(item, sel)
        if v then
            AC.render.text(v, x + width - 12 - AC.render.textWidth(v), y, vcolor or color)
        end
        y = y + lh
    end
    if #frame.items > rows then
        AC.render.text(string.format("%d/%d", frame.cursor, #frame.items), x + width - 50, ui.y, COLORS.hint)
    end
    y = y + lh * 0.5
    AC.render.text(AC.input.textTarget and t("hint_text") or t("hint_nav"), x, y, COLORS.hint)
end

-- Widget shorthands bound to a save-data setting. `path` is like "player.stats".
local function section(path)
    local node = AC.save.data
    for part in path:gmatch("[^.]+") do node = node[part] end
    return node
end

function menu.toggle(label, path, key, after)
    return {
        kind = "toggle", label = label,
        get = function() return section(path)[key] end,
        set = function(v) section(path)[key] = v if after then after(v) end end,
    }
end

function menu.number(label, path, key, min, max, step, after)
    return {
        kind = "number", label = label, min = min, max = max, step = step,
        get = function() return section(path)[key] end,
        set = function(v) section(path)[key] = v if after then after(v) end end,
    }
end

function menu.choice(label, path, key, options, after)
    return {
        kind = "choice", label = label, options = options,
        get = function() return section(path)[key] end,
        set = function(v) section(path)[key] = v if after then after(v) end end,
    }
end

function menu.action(label, fn) return { kind = "action", label = label, fn = fn } end
function menu.link(label, page) return { kind = "page", label = label, page = page } end
function menu.info(label) return { kind = "info", label = label } end

return menu
