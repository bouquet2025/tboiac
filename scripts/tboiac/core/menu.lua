-- Page-based menu with tabs. A page is { title = string|fn, build = fn() -> items, live = bool },
-- or a grid page from core/grid.lua (icons, type to filter).
-- Item kinds:
--   { kind = "action", label, fn }
--   { kind = "toggle", label, get, set }
--   { kind = "number", label, get, set, min, max, step, fmt }
--   { kind = "choice", label, options = { {label, value}, ... }, get, set }
--   { kind = "page",   label, page = id | pageTable }
--   { kind = "text",   label, get, set, live }  -- keyboard text entry
--   { kind = "info",   label }                  -- not selectable
-- Any item may carry `preview = fn(screenPos)` to draw an icon while it is selected.
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
    desc = { 0.85, 0.85, 0.6, 1 },
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

-- Tabs shown across the top: { { label = i18n key, page = id }, ... } (set by the registry).
menu.tabs = {}
menu.tab = 1

local MAX_ROWS = 9
local CELL = 36

-- Decorative icons (vanilla collectible ids) for menu entries, by label translation key.
local ENTRY_ICONS = {
    q_item = 1, m_collectibles = 1, god = 313, flight = 20, q_stop = 478, stop_world = 478,
    time_speed = 232, m_time = 232, kill_all = 35, m_teleport = 44, full_heal = 45, m_health = 45,
    revive = 11, m_resources = 18, q_pickup = 18, m_pickups = 18, inf_charge = 63, m_stats = 12, size = 12,
    m_pills = 75, reroll_pedestals = 105, reroll_inventory = 284, reroll_pickups = 166, m_smelt = 479,
    reveal_map = 54, m_rooms = 21, m_curses = 260, no_curses = 260, m_stages = 84, freeze_enemies = 478,
    use_stopwatch = 478,
}

local function entryIcon(item)
    if item.icon then return item.icon end
    local key = AC.i18n.keyFor(resolve(item.label))
    return key and ENTRY_ICONS[key] or nil
end

local function drawDesc(text, x, y, width, lh)
    if not text or text == "" then return y end
    for i, line in ipairs(AC.render.wrap(text, width, 0.9)) do
        if i > 3 then break end
        AC.render.text(line, x, y, COLORS.desc, 0.9)
        y = y + lh * 0.9
    end
    return y
end

local function rebuild(frame)
    if frame.page.grid then
        frame.entries = AC.grid.filtered(frame.page)
        frame.sel = AC.util.clamp(frame.sel or 1, 1, math.max(1, #frame.entries))
        frame.items = {}
        return
    end
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
    if page.grid then page.query = "" end
    local frame = { page = page, cursor = 1, scroll = 0, sel = 1 }
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

local function openTab(i)
    menu.tab = i
    menu.stack = {}
    menu.push(menu.tabs[i] and menu.tabs[i].page or "root")
end

-- Open or close the menu; `pageId` opens a specific page instead of the current tab.
function menu.setOpen(v, pageId)
    menu.open = v
    AC.input.blocking = v
    AC.input.textTarget = nil
    AC.input.held = {}
    if v then
        if pageId then
            menu.stack = {}
            menu.push(pageId)
        else
            openTab(AC.util.clamp(menu.tab, 1, math.max(1, #menu.tabs)))
        end
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

local function updateGrid(frame, ev)
    local page = frame.page
    local typed = AC.input.typed()
    if typed ~= "" then
        page.query = page.query .. typed
        frame.sel = 1
        rebuild(frame)
        return
    end
    local n, cols = #frame.entries, frame.cols or 8
    if ev.back then
        if page.query ~= "" then
            page.query = page.query:sub(1, -2)
            frame.sel = 1
            rebuild(frame)
        else
            menu.pop()
        end
    elseif n == 0 then
        return
    elseif ev.left then frame.sel = math.max(1, frame.sel - 1)
    elseif ev.right then frame.sel = math.min(n, frame.sel + 1)
    elseif ev.up then frame.sel = math.max(1, frame.sel - cols)
    elseif ev.down then frame.sel = math.min(n, frame.sel + cols)
    elseif ev.confirm or ev.alt then
        local e = frame.entries[frame.sel]
        if e then safe(e.pick, ev.alt == true) end
    end
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
    local ev = AC.input.poll()
    if (ev.tabNext or ev.tabPrev) and #menu.tabs > 0 then
        local n = #menu.tabs
        openTab((menu.tab - 1 + (ev.tabNext and 1 or -1)) % n + 1)
        return
    end
    if frame.page.grid then
        updateGrid(frame, ev)
        return
    end
    if frame.page.live then rebuild(frame) end
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
    elseif item and (ev.confirm or ev.alt) then
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

-- Tab bar; when it does not fit, a window of tabs around the current one is shown.
local function drawTabs(x, y, width)
    if #menu.tabs == 0 then return y end
    local labels, widths = {}, {}
    for i, tab in ipairs(menu.tabs) do
        labels[i] = t(tab.label)
        widths[i] = AC.render.textWidth(labels[i]) + 10
    end
    local first, last = menu.tab, menu.tab
    local used = widths[menu.tab]
    while true do
        local grew = false
        if last < #labels and used + widths[last + 1] <= width then
            last = last + 1; used = used + widths[last]; grew = true
        end
        if first > 1 and used + widths[first - 1] <= width then
            first = first - 1; used = used + widths[first]; grew = true
        end
        if not grew then break end
    end
    local cx = x
    for i = first, last do
        local on = i == menu.tab
        if on then AC.render.rect(cx - 3, y - 1, widths[i] - 4, AC.render.lineHeight(), { 1, 1, 1, 0.15 }) end
        AC.render.text(labels[i], cx, y, on and COLORS.title or COLORS.info)
        cx = cx + widths[i]
    end
    return y + AC.render.lineHeight() + 2
end

local function drawGrid(frame, x, y, width, lh)
    local page = frame.page
    local cols = math.max(4, math.floor(width / CELL))
    frame.cols = cols
    local rows = 3
    local n = #frame.entries
    local selRow = (frame.sel - 1) // cols
    frame.gscroll = frame.gscroll or 0
    if selRow < frame.gscroll then frame.gscroll = selRow end
    if selRow >= frame.gscroll + rows then frame.gscroll = selRow - rows + 1 end

    local q = page.query ~= "" and (page.query .. (Isaac.GetFrameCount() // 15 % 2 == 0 and "_" or " "))
        or t("grid_type_hint")
    AC.render.text(t("search") .. ": " .. q, x, y, page.query ~= "" and COLORS.normal or COLORS.hint)
    if n > 0 then
        local count = string.format("%d/%d", frame.sel, n)
        AC.render.text(count, x + width - AC.render.textWidth(count), y, COLORS.hint)
    end
    y = y + lh + 2
    if n == 0 then
        AC.render.text(t("nothing_found"), x, y, COLORS.info)
    end
    for r = 0, rows - 1 do
        for c = 0, cols - 1 do
            local i = (frame.gscroll + r) * cols + c + 1
            local e = frame.entries[i]
            if e then
                local cx, cy = x + c * CELL, y + r * CELL
                local sel = i == frame.sel
                AC.render.rect(cx, cy, CELL - 2, CELL - 2, sel and { 0.4, 1, 0.5, 0.35 } or { 1, 1, 1, 0.07 })
                local drawn = false
                if e.icon then
                    local ok, res = pcall(e.icon, Vector(cx + CELL / 2 - 1, cy + CELL / 2 - 1))
                    drawn = ok and res ~= false
                end
                if not drawn then
                    local s = AC.grid.initials(e.name or "?")
                    AC.render.text(s, cx + (CELL - AC.render.textWidth(s)) / 2 - 1, cy + (CELL - lh) / 2, COLORS.normal)
                end
            end
        end
    end
    y = y + rows * CELL + 2
    local e = frame.entries[frame.sel]
    if e then
        AC.render.text(e.id and string.format("%s  #%s", e.name, tostring(e.id)) or e.name, x, y, COLORS.selected)
        y = y + lh
        local desc = e.desc
        if type(desc) == "function" then desc = desc() end
        if desc then y = drawDesc(desc, x, y, width, lh) end
    end
    local hint = "Enter: " .. t(page.gridDef.pickHint or "grid_pick")
    if page.gridDef.altHint then hint = hint .. "   Shift+Enter: " .. t(page.gridDef.altHint) end
    AC.render.text(hint, x, y, COLORS.hint)
    return y + lh
end

local function drawList(frame, x, y, width, lh)
    local rows = MAX_ROWS
    if frame.cursor <= frame.scroll then frame.scroll = frame.cursor - 1 end
    if frame.cursor > frame.scroll + rows then frame.scroll = frame.cursor - rows end
    if #frame.items == 0 then
        AC.render.text(t("empty"), x, y, COLORS.info)
        y = y + lh
    end
    local indent = 0
    for i = frame.scroll + 1, math.min(#frame.items, frame.scroll + rows) do
        if entryIcon(frame.items[i]) then indent = 18 break end
    end
    for i = frame.scroll + 1, math.min(#frame.items, frame.scroll + rows) do
        local item = frame.items[i]
        local sel = i == frame.cursor
        local color = item.kind == "info" and COLORS.info or (sel and COLORS.selected or COLORS.normal)
        if sel then AC.render.rect(x - 3, y - 1, width + 6, lh, { 1, 1, 1, 0.08 }) end
        local icon = entryIcon(item)
        if icon then
            local pos = Vector(x + 7, y + lh / 2)
            if type(icon) == "function" then pcall(icon, pos) else AC.icons.collectible(icon, pos, 0.5) end
        end
        AC.render.text(resolve(item.label), x + indent, y, color)
        local v, vcolor = valueText(item, sel)
        if v then
            AC.render.text(v, x + width - AC.render.textWidth(v), y, vcolor or color)
        end
        if sel and item.preview then
            -- Icon of the selected entry, drawn to the right of the menu box.
            local ok, err = pcall(item.preview, Vector(x + width + 30, y + lh / 2))
            if not ok then AC.util.log("preview error: " .. tostring(err)) item.preview = nil end
        end
        y = y + lh
    end
    if #frame.items > rows then
        local more = (frame.scroll > 0 and "^ " or "  ") .. string.format("%d/%d", frame.cursor, #frame.items)
            .. (frame.scroll + rows < #frame.items and " v" or "")
        AC.render.text(more, x + width - AC.render.textWidth(more), y, COLORS.hint)
        y = y + lh
    end
    -- what the selected entry does
    local item = frame.items[frame.cursor]
    if item then
        local desc = item.desc or AC.i18n.desc(resolve(item.label))
        if desc then
            AC.render.rect(x - 3, y + 1, width + 6, 1, { 1, 1, 1, 0.2 })
            y = drawDesc(desc, x, y + 4, width, lh)
        end
    end
    return y
end

function menu.draw()
    if not menu.open then return end
    local frame = top()
    if not frame then return end
    local ui = AC.save.data.ui
    local lh = AC.render.lineHeight()
    local x, y = ui.x, ui.y
    local sw = Isaac.GetScreenWidth()
    local width = frame.page.grid and math.min(sw - x - 20, 8 * CELL)
        or AC.util.clamp(sw * 0.5, 200, sw - x - 20)
    -- background sized from the previous frame's content height
    AC.render.rect(x - 8, y - 6, width + 16, (frame.drawnHeight or lh * 6) + 10, { 0, 0, 0, ui.alpha })

    local y0 = y
    y = drawTabs(x, y, width)
    if #menu.stack > 1 then
        local crumbs = {}
        for i = 2, #menu.stack do crumbs[#crumbs + 1] = resolve(menu.stack[i].page.title) end
        AC.render.text(table.concat(crumbs, " / "), x, y, COLORS.title)
        y = y + lh + 2
    end
    if frame.page.grid then
        y = drawGrid(frame, x, y, width, lh)
    else
        y = drawList(frame, x, y, width, lh)
        local hint = AC.input.textTarget and t("hint_text") or t("hint_nav")
        AC.render.text(hint, x, y + 2, COLORS.hint, 0.9)
        y = y + lh + 2
    end
    frame.drawnHeight = y - y0
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
