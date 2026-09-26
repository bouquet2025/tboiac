-- The in-game menu: centred panel with tabs, mouse and keyboard/controller control.
--
-- A page is { title = string|fn, build = fn() -> items, live = bool, layout = "list"|"tiles",
--             icon = icon spec for rows without their own icon, side = fn(x, y, w) -> height }
-- or a grid page from core/grid.lua (icons, type to filter, chips, place with the mouse).
-- Item kinds:
--   { kind = "action", label, fn }
--   { kind = "toggle", label, get, set }
--   { kind = "number", label, get, set, min, max, step, fmt }
--   { kind = "choice", label, options = { {label, value}, ... }, get, set }
--   { kind = "page",   label, page = id | pageTable | fn }
--   { kind = "text",   label, get, set, live }  -- keyboard text entry
--   { kind = "info",   label }                  -- not selectable
-- Optional on any item: icon (see icons.draw), desc (text under the menu), side = fn(x, y, w) -> h
-- (panel next to the menu while the item is selected). Labels may be strings or functions.
--
-- Actions and grid picks run on the next game update (MC_POST_UPDATE), never inside the render
-- callback: using pills/cards/items while rendering can crash the game.
local AC = TBOIAC
local t = function(...) return AC.i18n.t(...) end

local menu = {
    open = false,
    pages = {},
    stack = {},
    tabs = {},  -- { { label = i18n key, page = id }, ... } (set in main.lua)
    tab = 1,
    queue = {}, -- deferred actions
    hits = {},  -- clickable regions of the last drawn frame
    place = nil, -- active "place with the mouse" state
}

local COLORS = {
    title = { 1, 0.85, 0.3, 1 },
    normal = { 1, 1, 1, 1 },
    selected = { 0.45, 1, 0.55, 1 },
    info = { 0.62, 0.62, 0.68, 1 },
    on = { 0.45, 1, 0.55, 1 },
    off = { 1, 0.45, 0.45, 1 },
    hint = { 0.66, 0.66, 0.72, 1 },
    desc = { 0.9, 0.88, 0.62, 1 },
    panel = { 0.05, 0.05, 0.07, 1 },
    border = { 1, 1, 1, 0.22 },
    header = { 1, 1, 1, 0.06 },
    tile = { 1, 1, 1, 0.07 },
    tileSel = { 0.35, 0.9, 0.45, 0.28 },
}

local PANEL_W = 288
local MAX_ROWS = 9
local TILE_H = 30
local TILE_ROWS = 5
local GRID_COLS = 8
local GRID_ROWS = 3

-- Decorative icons (vanilla collectible ids / trinkets) for entries, by label translation key.
local ENTRY_ICONS = {
    -- quick
    q_item = 515, q_boss = 86, q_enemy = 10, q_pickup = 94, god = 313, q_stop = 478, time_speed = 232,
    kill_all = 35, m_teleport = 44, q_clean = 76, panic = 127,
    -- player
    target = 8, one_hit = 237, flight = 20, noclip = 115, inf_charge = 63, size = 71, m_stats = 12,
    m_health = 45, m_resources = 18, m_character = 490, m_costumes = 216, full_heal = 92, revive = 11,
    kill_player = 126, st_damage = 7, st_tears = 1, st_speed = 27, st_range = 30, st_shotspeed = 69,
    st_luck = 46, reset_stats = 127, h_container = 15, h_red = 45, h_soul = 101, h_black = 34, h_bone = 549,
    h_golden = 202, h_eternal = 184, h_rotten = 26, h_broken = 126, coins = 18, bombs = 19, keys = 17,
    inf_coins = 18, inf_bombs = 19, inf_keys = 17, golden_bomb = 19, golden_key = 17,
    -- items
    m_collectibles = 515, m_trinkets = { trinket = 1 }, m_pickups = 94, m_cards = 85, m_pills = 102,
    m_recent = 66, m_inventory = 139, m_smelt = 479, m_pools = 297, reroll_pedestals = 105,
    reroll_inventory = 284, reroll_pickups = 166, random_item = 489, remove_all_items = 477,
    give_mode = 139, m_pickups_grid = 94, m_drops = 94, pk_clear = 477, pk_clear_items = 477,
    pk_collect_all = 53, pk_custom = 123,
    -- enemies
    m_bosses = 86, m_enemies_common = 10, m_waves = 208, m_spawn_custom = 123, hp_mult = 16,
    all_champions = 208, count = 94, as_champion = 208, friendly_spawn = 8, remove_all = 477,
    champion_all = 208, charm_all = 48, heal_all = 92,
    -- world & time
    m_time = 232, m_rooms = 21, m_stages = 84, m_room_tools = 175, m_curses = 260, m_run = 283,
    m_console = 481, m_seeds = 258, m_music = 192, hide_hud = 76, reveal_map = 54, no_curses = 260,
    freeze_enemies = 478, freeze_projectiles = 478, pause_world_menu = 66, stop_world = 478,
    use_stopwatch = 232, reset_timer = 66, clear_room = 35, open_doors = 175, spawn_trapdoor = 84,
    spawn_crawlspace = 60, restart_room = 283, restart_run = 283, tp_start = 44, tp_devil = 51,
    -- rules & studio & settings
    m_rules = 33, rules_enabled = 33, new_rule = 58, m_presets = 287, m_variables = 488,
    m_studio = 76, m_scenarios = 488, m_hotkeys = 482, m_overlay = 76, m_profiles = 534, clean_frame = 76,
    m_settings = 482, language = 192, open_key = 482, ui_scale = 12, ui_alpha = 76, imgui_menu = 481,
    game_names = 192, reset_settings = 127, ui_x = 21, ui_y = 21,
    -- tabs
    tab_quick = 12, tab_player = 8, tab_items = 515, tab_enemies = 86, tab_world = 21, tab_rules = 33,
    tab_studio = 76, tab_settings = 482,
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
menu.top = top

local function entryIcon(item, frame)
    if item.icon then return item.icon, 1 end
    local key = AC.i18n.keyFor(resolve(item.label))
    if key and ENTRY_ICONS[key] then return ENTRY_ICONS[key], 1 end
    if item.kind == "info" then return nil end
    return frame and (frame.page.icon or frame.icon), 0.45 -- inherited page icon, dimmed
end

-- Pages / navigation ------------------------------------------------------------------------------

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

-- `via` is the item that linked here (its icon becomes the page's default row icon).
function menu.push(page, via)
    if type(page) == "string" then page = menu.pages[page] end
    if not page then return end
    if page.grid then
        page.query = ""
        if page.gridDef.discover then pcall(page.gridDef.discover) end
    end
    local parent = top()
    local icon = via and entryIcon(via, parent) or (parent and (parent.page.icon or parent.icon))
    local frame = { page = page, cursor = 1, scroll = 0, sel = 1, icon = icon, focus = "grid", chip = 1 }
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
    local tab = menu.tabs[i]
    menu.push(tab and tab.page or "root")
    if tab then top().icon = ENTRY_ICONS[tab.label] end
end

-- Open or close the menu. Closing keeps the page stack, so reopening returns to the same place;
-- `pageId` opens a specific page instead.
function menu.setOpen(v, pageId)
    menu.open = v
    AC.input.blocking = v or menu.place ~= nil
    AC.input.textTarget = nil
    AC.input.held = {}
    if v then
        if pageId then
            menu.stack = {}
            menu.push(pageId)
        elseif #menu.stack > 0 then
            rebuild(top())
        else
            openTab(AC.util.clamp(menu.tab, 1, math.max(1, #menu.tabs)))
        end
    else
        -- the Esc that closed us must not also open the game's pause menu on the next update
        AC.input.pauseGrace = Isaac.GetFrameCount() + 20
        AC.save.write()
    end
end

-- HUD ---------------------------------------------------------------------------------------------
-- The vanilla HUD is drawn on top of MC_POST_RENDER, so it would cover the menu. While the menu is
-- open the HUD is hidden and the user's own "hide HUD" choice is kept in `hudWanted` instead.

local hudWanted = nil -- nil = menu is not hiding the HUD

function menu.hudVisible()
    if hudWanted ~= nil then return hudWanted end
    return AC.game:GetHUD():IsVisible()
end

function menu.setHudVisible(v)
    if hudWanted ~= nil then hudWanted = v else AC.game:GetHUD():SetVisible(v) end
end

local function syncHud()
    if menu.open and hudWanted == nil then
        local hud = AC.game:GetHUD()
        hudWanted = hud:IsVisible()
        hud:SetVisible(false)
    elseif not menu.open and hudWanted ~= nil then
        AC.game:GetHUD():SetVisible(hudWanted)
        hudWanted = nil
    end
end

-- Deferred execution ------------------------------------------------------------------------------

local function safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        AC.util.log("menu error: " .. tostring(err))
        AC.render.toast(t("error", tostring(err)), 180)
    end
    AC.save.markDirty()
end

function menu.defer(fn, ...)
    local args = table.pack(...)
    table.insert(menu.queue, function() fn(table.unpack(args, 1, args.n)) end)
end

-- Called from MC_POST_UPDATE.
function menu.runQueue()
    if #menu.queue == 0 then return end
    local q = menu.queue
    menu.queue = {}
    for _, fn in ipairs(q) do safe(fn) end
    if menu.open then menu.refresh() end
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

local function activate(item, alt)
    if item.kind == "action" then
        menu.defer(item.fn)
    elseif item.kind == "toggle" then
        safe(change, item, 1)
    elseif item.kind == "page" then
        menu.push(resolve(item.page), item)
    elseif item.kind == "text" then
        AC.input.beginText({
            text = item.get(),
            onChange = function(s) if item.live then item.set(s) menu.refresh() end end,
            onDone = function(s) item.set(s) menu.refresh() end,
        })
    elseif item.kind == "number" or item.kind == "choice" then
        safe(change, item, alt and -1 or 1)
    end
end

-- Grid helpers ----------------------------------------------------------------------------------

local function gridPick(frame, alt)
    local e = frame.entries[frame.sel]
    if e then menu.defer(e.pick, alt == true, AC.grid.amount(frame.page)) end
end

function menu.startPlace(frame)
    local e = frame.entries[frame.sel]
    if not e or not e.place then
        AC.render.toast(t("place_unsupported"))
        return
    end
    menu.place = { entry = e, amount = AC.grid.amount(frame.page) }
    menu.open = false
    AC.input.blocking = true
    AC.render.toast(t("place_hint"), 150)
end

local function endPlace()
    menu.place = nil
    menu.setOpen(true)
end

local function chipAt(frame, i)
    return AC.grid.chips(frame.page)[i]
end

-- Hit regions -----------------------------------------------------------------------------------

local function hit(x, y, w, h, handlers)
    handlers.x, handlers.y, handlers.w, handlers.h = x, y, w, h
    table.insert(menu.hits, handlers)
end

local function hitAt(pos)
    for i = #menu.hits, 1, -1 do
        local h = menu.hits[i]
        if pos.X >= h.x and pos.X <= h.x + h.w and pos.Y >= h.y and pos.Y <= h.y + h.h then return h end
    end
    return nil
end

-- Update ----------------------------------------------------------------------------------------

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

-- Tiles: move to the nearest tile in a direction, using the rectangles of the last draw.
local function moveSpatial(frame, dx, dy)
    local rects = frame.rects or {}
    local cur = rects[frame.cursor]
    if not cur then return moveCursor(frame, (dx + dy) >= 0 and 1 or -1) end
    local cx, cy = cur.x + cur.w / 2, cur.y + cur.h / 2
    local best, bestScore
    for i, r in pairs(rects) do
        if i ~= frame.cursor then
            local rx, ry = r.x + r.w / 2, r.y + r.h / 2
            local ddx, ddy = rx - cx, ry - cy
            local along = ddx * dx + ddy * dy
            if along > 1 then
                local score = along + math.abs(ddx * dy + ddy * dx) * 2
                if not bestScore or score < bestScore then best, bestScore = i, score end
            end
        end
    end
    if best then frame.cursor = best
    elseif dy ~= 0 then moveCursor(frame, dy) end
end

local function updateGrid(frame, ev)
    local page = frame.page
    local typed = AC.input.typed()
    if typed ~= "" then
        page.query = page.query .. typed
        frame.sel, frame.focus = 1, "grid"
        rebuild(frame)
        return
    end
    local n, cols = #frame.entries, frame.cols or GRID_COLS
    if frame.focus == "chips" then
        local chips = AC.grid.chips(page)
        if ev.back then menu.pop()
        elseif ev.left then frame.chip = math.max(1, frame.chip - 1)
        elseif ev.right then frame.chip = math.min(#chips, frame.chip + 1)
        elseif ev.down then frame.focus = "grid"
        elseif ev.confirm or ev.alt then
            local chip = chips[frame.chip]
            if chip then AC.grid.cycleChip(page, chip, ev.alt and -1 or 1) frame.sel = 1 rebuild(frame) end
        end
        return
    end
    if ev.back then
        if page.query ~= "" then
            page.query = page.query:sub(1, -2)
            frame.sel = 1
            rebuild(frame)
        else
            menu.pop()
        end
    elseif ev.up and frame.sel <= cols then
        if #AC.grid.chips(page) > 0 then frame.focus = "chips" end
    elseif n == 0 then
        return
    elseif ev.left then frame.sel = math.max(1, frame.sel - 1)
    elseif ev.right then frame.sel = math.min(n, frame.sel + 1)
    elseif ev.up then frame.sel = math.max(1, frame.sel - cols)
    elseif ev.down then frame.sel = math.min(n, frame.sel + cols)
    elseif ev.confirm and AC.input.ctrl() then menu.startPlace(frame)
    elseif ev.confirm or ev.alt then gridPick(frame, ev.alt)
    end
end

local function updatePlace()
    local m = AC.input.mouse()
    if AC.input.escape() or (m and m.right) or AC.input.poll().back then
        endPlace()
        return
    end
    if m and m.left then
        local p = menu.place
        local world = Input.GetMousePosition(true)
        menu.defer(p.entry.place, world, p.amount)
    end
end

function menu.update()
    if AC.game:IsPaused() then return end -- the game's own menu is open: do nothing
    if AC.input.toggleMenuPressed() then
        if menu.place then menu.place = nil end
        menu.setOpen(not menu.open)
        return
    end
    if menu.place then
        updatePlace()
        return
    end
    if not menu.open then return end
    if AC.input.textTarget then
        AC.input.updateText()
        return
    end
    if AC.input.escape() then
        menu.setOpen(false) -- first Esc closes the mod menu; the next one opens the game menu
        return
    end
    local frame = top()
    if not frame then return end

    local m = AC.input.mouse()
    if m then
        local h = hitAt(m.pos)
        if h and m.moved and h.hover then h.hover() end
        if h and m.left and h.click then h.click() return end
        if h and m.right and h.rclick then h.rclick() return end
    end

    local ev = AC.input.poll()
    local tabNext, tabPrev = ev.tabNext, ev.tabPrev
    if not frame.page.grid then
        local e, q = AC.input.tabKeys()
        tabNext, tabPrev = tabNext or e, tabPrev or q
    end
    if (tabNext or tabPrev) and #menu.tabs > 0 then
        openTab((menu.tab - 1 + (tabNext and 1 or -1)) % #menu.tabs + 1)
        return
    end
    if frame.page.grid then
        updateGrid(frame, ev)
        return
    end
    if frame.page.live then rebuild(frame) end
    local item = frame.items[frame.cursor]
    local tiles = frame.page.layout == "tiles"
    if ev.back then
        menu.pop()
    elseif tiles and (ev.up or ev.down or ev.left or ev.right) then
        moveSpatial(frame, ev.left and -1 or ev.right and 1 or 0, ev.up and -1 or ev.down and 1 or 0)
    elseif ev.up then
        moveCursor(frame, -1)
    elseif ev.down then
        moveCursor(frame, 1)
    elseif item and ev.left then
        safe(change, item, -1)
    elseif item and ev.right then
        safe(change, item, 1)
    elseif item and (ev.confirm or ev.alt) then
        safe(activate, item, ev.alt)
    end
end

-- Drawing ---------------------------------------------------------------------------------------

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
        local layout = editing and (" [" .. AC.input.layout:upper() .. "]") or ""
        return "[" .. s .. (editing and (Isaac.GetFrameCount() // 15 % 2 == 0 and "_" or " ") or "") .. "]" .. layout
    elseif item.kind == "page" then
        return ">"
    end
    return nil
end

-- Cut text to `width`, adding "..".
local function fit(s, width, scale)
    if AC.render.textWidth(s, scale) <= width then return s end
    local out = ""
    for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        if AC.render.textWidth(out .. ch .. "..", scale) > width then break end
        out = out .. ch
    end
    return out .. ".."
end
menu.fit = fit

local function border(x, y, w, h, color)
    AC.render.rect(x, y, w, 1, color)
    AC.render.rect(x, y + h - 1, w, 1, color)
    AC.render.rect(x, y, 1, h, color)
    AC.render.rect(x + w - 1, y, 1, h, color)
end
menu.border = border

-- Lines drawDesc uses for `text` (at most 3).
local function descLineCount(text, width)
    if type(text) ~= "string" or text == "" then return 0 end
    return math.min(3, #AC.render.wrap(text, width, 0.9))
end

local function itemDesc(item)
    return item.desc or AC.i18n.desc(resolve(item.label))
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

-- Tabs + close button. Returns the y below the header.
local function drawHeader(x, y, width, lh)
    AC.render.rect(x - 8, y - 6, width + 16, lh + 8, COLORS.header)
    -- close "X"
    local cx = x + width - 8
    AC.render.text("X", cx, y, COLORS.off)
    hit(cx - 4, y - 3, 16, lh + 4, { click = function() menu.setOpen(false) end })
    local avail = width - 22
    if #menu.tabs == 0 then return y + lh + 4 end
    local labels, widths = {}, {}
    for i, tab in ipairs(menu.tabs) do
        labels[i] = t(tab.label)
        widths[i] = AC.render.textWidth(labels[i]) + 10
    end
    local first, last = menu.tab, menu.tab
    local used = widths[menu.tab]
    while true do
        local grew = false
        if last < #labels and used + widths[last + 1] <= avail then
            last = last + 1; used = used + widths[last]; grew = true
        end
        if first > 1 and used + widths[first - 1] <= avail then
            first = first - 1; used = used + widths[first]; grew = true
        end
        if not grew then break end
    end
    local tx = x
    for i = first, last do
        local on = i == menu.tab
        if on then AC.render.rect(tx - 4, y - 2, widths[i] - 2, lh + 2, { 1, 0.85, 0.3, 0.18 }) end
        AC.render.text(labels[i], tx, y, on and COLORS.title or COLORS.info)
        local idx = i
        hit(tx - 4, y - 2, widths[i] - 2, lh + 2, { click = function() openTab(idx) end })
        tx = tx + widths[i]
    end
    return y + lh + 6
end

local function drawIcon(spec, pos, scale, alpha)
    if not spec then return false end
    if type(spec) == "number" or type(spec) == "table" then return AC.icons.draw(spec, pos, scale, alpha) end
    return AC.icons.draw(spec, pos, scale)
end

local function drawList(frame, x, y, width, lh)
    local rows = MAX_ROWS
    if frame.cursor <= frame.scroll then frame.scroll = frame.cursor - 1 end
    if frame.cursor > frame.scroll + rows then frame.scroll = frame.cursor - rows end
    if #frame.items == 0 then
        AC.render.text(t("empty"), x, y, COLORS.info)
        y = y + lh
    end
    local rowH = lh + 2
    for i = frame.scroll + 1, math.min(#frame.items, frame.scroll + rows) do
        local item = frame.items[i]
        local sel = i == frame.cursor
        local isInfo = item.kind == "info"
        local color = isInfo and COLORS.info or (sel and COLORS.selected or COLORS.normal)
        if sel then
            AC.render.rect(x - 4, y - 1, width + 8, rowH, COLORS.tileSel)
        end
        local icon, alpha = entryIcon(item, frame)
        if icon then drawIcon(icon, Vector(x + 7, y + rowH / 2 - 1), 0.5, alpha) end
        local label = resolve(item.label) or ""
        local v, vcolor = valueText(item, sel)
        local vw = v and AC.render.textWidth(v) or 0
        AC.render.text(fit(label, width - 22 - vw - 6), x + 18, y, color)
        if v then
            if item.kind == "toggle" then
                AC.render.rect(x + width - vw - 4, y, vw + 6, lh, { vcolor[1], vcolor[2], vcolor[3], 0.18 })
            end
            AC.render.text(v, x + width - vw - 1, y, vcolor or color)
        end
        if not isInfo then
            local idx = i
            hit(x - 4, y - 1, width + 8, rowH, {
                hover = function() frame.cursor = idx end,
                click = function() frame.cursor = idx safe(activate, item, false) end,
                rclick = function() frame.cursor = idx safe(activate, item, true) end,
            })
            if item.kind == "number" or item.kind == "choice" then
                -- clickable "<" and ">" on the value
                hit(x + width - vw - 2, y - 1, 10, rowH, { click = function() frame.cursor = idx safe(change, item, -1) end })
                hit(x + width - 10, y - 1, 12, rowH, { click = function() frame.cursor = idx safe(change, item, 1) end })
            end
        end
        y = y + rowH
    end
    if #frame.items > rows then
        local up, down = frame.scroll > 0, frame.scroll + rows < #frame.items
        local more = string.format("%d/%d", frame.cursor, #frame.items)
        AC.render.text(more, x + width - AC.render.textWidth(more), y, COLORS.hint)
        if up then
            AC.render.text("^", x + width / 2 - 10, y, COLORS.hint)
            hit(x + width / 2 - 16, y - 1, 14, lh, { click = function() moveCursor(frame, -rows) end })
        end
        if down then
            AC.render.text("v", x + width / 2 + 6, y, COLORS.hint)
            hit(x + width / 2 + 2, y - 1, 14, lh, { click = function()
                for _ = 1, rows do moveCursor(frame, 1) end
            end })
        end
        y = y + lh
    end
    return y
end

local function drawTiles(frame, x, y, width, lh)
    local colW = (width - 4) / 2
    -- layout in virtual coordinates
    local rects, vy, col = {}, 0, 0
    local headers = {}
    for i, item in ipairs(frame.items) do
        if item.kind == "info" then
            if col == 1 then vy = vy + TILE_H + 4 col = 0 end
            headers[#headers + 1] = { i = i, y = vy }
            vy = vy + lh + 2
        else
            rects[i] = { x = x + col * (colW + 4), y = vy, w = colW, h = TILE_H }
            col = col + 1
            if col == 2 then col = 0 vy = vy + TILE_H + 4 end
        end
    end
    local total = vy + (col == 1 and TILE_H + 4 or 0)
    local viewH = TILE_ROWS * (TILE_H + 4)
    frame.tscroll = frame.tscroll or 0
    local cur = rects[frame.cursor]
    if cur then
        if cur.y < frame.tscroll then frame.tscroll = cur.y end
        if cur.y + cur.h > frame.tscroll + viewH then frame.tscroll = cur.y + cur.h - viewH end
    end
    frame.rects = {}
    for _, hd in ipairs(headers) do
        local hy = y + hd.y - frame.tscroll
        if hd.y >= frame.tscroll and hd.y + lh <= frame.tscroll + viewH then
            AC.render.text(resolve(frame.items[hd.i].label) or "", x, hy, COLORS.info, 0.9)
        end
    end
    for i, r in pairs(rects) do
        if r.y >= frame.tscroll and r.y + r.h <= frame.tscroll + viewH then
            local item = frame.items[i]
            local ry = y + r.y - frame.tscroll
            local sel = i == frame.cursor
            AC.render.rect(r.x, ry, r.w, r.h, sel and COLORS.tileSel or COLORS.tile)
            if sel then border(r.x, ry, r.w, r.h, { 0.45, 1, 0.55, 0.7 }) end
            local icon, alpha = entryIcon(item, frame)
            if icon then drawIcon(icon, Vector(r.x + 14, ry + r.h / 2), 0.75, alpha) end
            local label = resolve(item.label) or ""
            local v, vcolor = valueText(item, sel)
            local tx = r.x + 29
            if v and item.kind ~= "page" then
                AC.render.text(fit(label, r.w - 33, 0.9), tx, ry + 2, sel and COLORS.selected or COLORS.normal, 0.9)
                AC.render.text(fit(v, r.w - 33, 0.9), tx, ry + 2 + lh * 0.9, vcolor or COLORS.hint, 0.9)
            else
                AC.render.text(fit(label, r.w - 33, 0.9), tx, ry + (r.h - lh) / 2,
                    sel and COLORS.selected or COLORS.normal, 0.9)
            end
            frame.rects[i] = { x = r.x, y = ry, w = r.w, h = r.h }
            local idx = i
            hit(r.x, ry, r.w, r.h, {
                hover = function() frame.cursor = idx end,
                click = function() frame.cursor = idx safe(activate, item, false) end,
                rclick = function() frame.cursor = idx safe(activate, item, true) end,
            })
        end
    end
    if total > viewH then
        local s = frame.tscroll > 0 and "^" or " "
        local e = frame.tscroll + viewH < total and "v" or " "
        AC.render.text(s .. " " .. e, x + width - 20, y + viewH - 2, COLORS.hint)
    end
    return y + math.min(total, viewH)
end

local function drawGrid(frame, x, y, width, lh)
    local page = frame.page
    local cell = math.floor(width / GRID_COLS)
    local cols = GRID_COLS
    frame.cols = cols
    local n = #frame.entries

    -- chips
    local chips = AC.grid.chips(page)
    if #chips > 0 then
        local cx = x
        for i, chip in ipairs(chips) do
            local value = ""
            local cur = AC.grid.chipValue(page, chip)
            for _, o in ipairs(AC.grid.chipOptions(chip)) do
                if o[2] == cur then value = AC.i18n.label(o[1]) end
            end
            local s = t(chip.label) .. ": " .. value
            local w = AC.render.textWidth(s, 0.9) + 8
            if cx + w > x + width + 2 then
                cx = x
                y = y + lh + 2
            end
            local focused = frame.focus == "chips" and frame.chip == i
            AC.render.rect(cx, y - 1, w - 2, lh, focused and COLORS.tileSel or COLORS.tile)
            if focused then border(cx, y - 1, w - 2, lh, { 0.45, 1, 0.55, 0.7 }) end
            AC.render.text(s, cx + 3, y, cur ~= chip.default and COLORS.title or COLORS.hint, 0.9)
            local idx = i
            hit(cx, y - 1, w - 2, lh, {
                click = function() frame.chip = idx AC.grid.cycleChip(page, chip, 1) frame.sel = 1 rebuild(frame) end,
                rclick = function() frame.chip = idx AC.grid.cycleChip(page, chip, -1) frame.sel = 1 rebuild(frame) end,
            })
            cx = cx + w
        end
        y = y + lh + 3
    end

    -- search line with layout badge
    local q = page.query ~= "" and (page.query .. (Isaac.GetFrameCount() // 15 % 2 == 0 and "_" or " "))
        or t("grid_type_hint")
    AC.render.text(t("search") .. ": " .. q, x, y, page.query ~= "" and COLORS.normal or COLORS.hint)
    local badge = "[" .. AC.input.layout:upper() .. "]"
    local bw = AC.render.textWidth(badge)
    local count = n > 0 and string.format("%d/%d", frame.sel, n) or ""
    local cw = AC.render.textWidth(count)
    AC.render.text(count, x + width - cw, y, COLORS.hint)
    AC.render.text(badge, x + width - cw - bw - 8, y, COLORS.title)
    hit(x + width - cw - bw - 10, y - 1, bw + 4, lh, { click = function() AC.input.toggleLayout() end })
    y = y + lh + 3

    -- cells
    local selRow = (frame.sel - 1) // cols
    frame.gscroll = frame.gscroll or 0
    if selRow < frame.gscroll then frame.gscroll = selRow end
    if selRow >= frame.gscroll + GRID_ROWS then frame.gscroll = selRow - GRID_ROWS + 1 end
    if n == 0 then
        AC.render.text(t("nothing_found"), x, y + cell, COLORS.info)
    end
    for r = 0, GRID_ROWS - 1 do
        for c = 0, cols - 1 do
            local i = (frame.gscroll + r) * cols + c + 1
            local e = frame.entries[i]
            if e then
                local cx, cy = x + c * cell, y + r * cell
                local sel = i == frame.sel and frame.focus == "grid"
                AC.render.rect(cx, cy, cell - 2, cell - 2, sel and COLORS.tileSel or COLORS.tile)
                if sel then border(cx, cy, cell - 2, cell - 2, { 0.45, 1, 0.55, 0.8 }) end
                local drawn = drawIcon(e.icon, Vector(cx + cell / 2 - 1, cy + cell / 2 - 1), 1, 1)
                if not drawn then
                    local s = AC.grid.initials(e.name or "?")
                    AC.render.text(s, cx + (cell - AC.render.textWidth(s)) / 2 - 1, cy + (cell - lh) / 2, COLORS.info)
                end
                local idx = i
                hit(cx, cy, cell - 2, cell - 2, {
                    hover = function() frame.sel = idx frame.focus = "grid" end,
                    click = function() frame.sel = idx gridPick(frame, false) end,
                    rclick = function() frame.sel = idx gridPick(frame, true) end,
                })
            end
        end
    end
    local rowsTotal = math.max(1, math.ceil(n / cols))
    if rowsTotal > GRID_ROWS then
        -- scroll arrows at the right edge
        if frame.gscroll > 0 then
            AC.render.text("^", x + width + 2, y, COLORS.hint)
            hit(x + width, y, 10, lh, { click = function() frame.sel = math.max(1, frame.sel - cols * GRID_ROWS) end })
        end
        if frame.gscroll + GRID_ROWS < rowsTotal then
            AC.render.text("v", x + width + 2, y + GRID_ROWS * cell - lh, COLORS.hint)
            hit(x + width, y + GRID_ROWS * cell - lh, 10, lh, { click = function()
                frame.sel = math.min(n, frame.sel + cols * GRID_ROWS)
            end })
        end
    end
    y = y + GRID_ROWS * cell + 3

    -- selected entry: name, description, buttons
    local e = frame.entries[frame.sel]
    if e then
        AC.render.text(fit(e.id and string.format("%s  #%s", e.name, tostring(e.id)) or e.name, width), x, y,
            COLORS.selected)
        y = y + lh
        local desc = e.desc
        if type(desc) == "function" then desc = desc() end
        drawDesc(desc, x, y, width, lh)
        frame.descLines = math.max(frame.descLines or 2, descLineCount(desc, width))
    end
    -- fixed-height description area, so the panel does not jump between entries
    y = y + (frame.descLines or 2) * lh * 0.9
    local buttons = { { t(page.gridDef.pickHint or "grid_pick"), function() gridPick(frame, false) end } }
    if page.gridDef.altHint then
        buttons[#buttons + 1] = { t(page.gridDef.altHint), function() gridPick(frame, true) end }
    end
    if e and e.place then
        buttons[#buttons + 1] = { t("grid_place"), function() menu.startPlace(frame) end }
    end
    local bx = x
    for _, b in ipairs(buttons) do
        local w = AC.render.textWidth(b[1], 0.9) + 12
        AC.render.rect(bx, y + 1, w, lh, { 0.35, 0.6, 1, 0.25 })
        border(bx, y + 1, w, lh, { 0.5, 0.7, 1, 0.6 })
        AC.render.text(b[1], bx + 6, y + 2, COLORS.normal, 0.9)
        hit(bx, y + 1, w, lh, { click = b[2] })
        bx = bx + w + 4
    end
    y = y + lh + 4
    return y
end

local function drawCursor(pos)
    for i = 0, 7 do
        AC.render.rect(pos.X - 1, pos.Y + i - 1, i + 3, 1, { 0, 0, 0, 0.8 })
        AC.render.rect(pos.X, pos.Y + i, i + 1, 1, { 1, 1, 1, 1 })
    end
end

local function drawPlace()
    local p = menu.place
    local m = AC.input.mouse()
    if not m then return end
    local drawn = drawIcon(p.entry.icon, m.pos, 1, 0.75)
    if not drawn then AC.render.text(AC.grid.initials(p.entry.name or "?"), m.pos.X - 6, m.pos.Y - 6, COLORS.title) end
    drawCursor(m.pos)
    local s = t("place_title", p.entry.name or "?", p.amount)
    AC.render.text(s, (Isaac.GetScreenWidth() - AC.render.textWidth(s)) / 2, 12, COLORS.title)
    local h = t("place_hint")
    AC.render.text(h, (Isaac.GetScreenWidth() - AC.render.textWidth(h, 0.9)) / 2, 12 + AC.render.lineHeight(),
        COLORS.hint, 0.9)
end

function menu.draw()
    menu.hits = {}
    syncHud()
    if AC.game:IsPaused() then return end
    if menu.place then
        drawPlace()
        return
    end
    if not menu.open then return end
    local frame = top()
    if not frame then return end
    local ui = AC.save.data.ui
    local lh = AC.render.lineHeight()
    local sw, sh = Isaac.GetScreenWidth(), Isaac.GetScreenHeight()
    local width = PANEL_W
    local item = frame.items[frame.cursor]
    local side = frame.page.side or (item and item.side)
    -- Reserve room for the longest description and for the side panel once per page, so the
    -- panel keeps its size and position while the cursor moves.
    if not frame.page.grid and not frame.descLines then
        local n = 0
        for _, it in ipairs(frame.items) do
            if it.side then frame.hasSide = true end
            n = math.max(n, descLineCount(itemDesc(it), width))
        end
        frame.descLines = n
    end
    local reserveSide = side or frame.hasSide
    local sideW = reserveSide and 150 or 0
    local height = frame.drawnHeight or (lh * 14)
    local x = math.floor((sw - width - (reserveSide and sideW + 14 or 0)) / 2 + (ui.offX or 0))
    local y = math.floor((sh - height) / 2 + (ui.offY or 0))
    x = AC.util.clamp(x, 10, math.max(10, sw - width - 10))
    y = AC.util.clamp(y, 8, math.max(8, sh - height - 4))

    -- panel
    AC.render.rect(x - 8, y - 6, width + 16, height + 10, { COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], ui.alpha })
    border(x - 8, y - 6, width + 16, height + 10, COLORS.border)

    local y0 = y
    y = drawHeader(x, y, width, lh)
    if #menu.stack > 1 then
        local back = "< " .. t("back")
        AC.render.text(back, x, y, COLORS.info, 0.9)
        local bw = AC.render.textWidth(back, 0.9) + 6
        hit(x - 2, y - 1, bw, lh, { click = function() menu.pop() end })
        local crumbs = {}
        for i = 2, #menu.stack do crumbs[#crumbs + 1] = resolve(menu.stack[i].page.title) end
        AC.render.text(fit(table.concat(crumbs, " / "), width - bw - 6, 0.9), x + bw + 4, y, COLORS.title, 0.9)
        y = y + lh + 2
    end
    if frame.page.grid then
        y = drawGrid(frame, x, y, width, lh)
        AC.render.text(t("hint_grid"), x, y, COLORS.hint, 0.85)
        y = y + lh
    else
        if frame.page.layout == "tiles" then
            y = drawTiles(frame, x, y, width, lh)
        else
            y = drawList(frame, x, y, width, lh)
        end
        local sel = frame.items[frame.cursor]
        local desc = sel and itemDesc(sel)
        frame.descLines = math.max(frame.descLines, descLineCount(desc, width))
        if frame.descLines > 0 then
            AC.render.rect(x - 4, y + 2, width + 8, 1, COLORS.border)
            drawDesc(desc, x, y + 5, width, lh)
            y = y + 5 + frame.descLines * lh * 0.9
        end
        local hint = AC.input.textTarget and t("hint_text") or t("hint_nav")
        AC.render.text(hint, x, y + 2, COLORS.hint, 0.85)
        y = y + lh + 2
    end
    frame.drawnHeight = y - y0

    -- side panel (rule diagram etc.)
    if side then
        local sx, sy = x + width + 22, y0
        AC.render.rect(sx - 8, sy - 6, sideW + 16, (frame.sideHeight or lh * 8) + 10,
            { COLORS.panel[1], COLORS.panel[2], COLORS.panel[3], ui.alpha })
        border(sx - 8, sy - 6, sideW + 16, (frame.sideHeight or lh * 8) + 10, COLORS.border)
        local ok, h = pcall(side, sx, sy, sideW)
        frame.sideHeight = ok and h or lh
        if not ok then AC.util.log("side panel error: " .. tostring(h)) end
    end

    local m = AC.input.mouse()
    if m and m.active then drawCursor(m.pos) end
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
