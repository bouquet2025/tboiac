-- Keyboard / controller handling: menu hotkey, navigation with key repeat,
-- text entry, and blocking gameplay input while the menu is open.
local AC = TBOIAC

local input = {
    blocking = false, -- true while the menu is open
    held = {},        -- action -> frames held
    textTarget = nil, -- active text-entry callback table
}

local C = Controller or {}
local PAD = {
    up = C.DPAD_UP or 2, down = C.DPAD_DOWN or 3, left = C.DPAD_LEFT or 0, right = C.DPAD_RIGHT or 1,
    confirm = C.BUTTON_A or 4, back = C.BUTTON_B or 5, y = C.BUTTON_Y or 7,
    select = C.BUTTON_BACK or 14, x = C.BUTTON_X or 6,
    lb = C.BUMPER_LEFT or 8, rb = C.BUMPER_RIGHT or 11, fast = C.TRIGGER_RIGHT or 12,
}

local KEYS = {
    up = { Keyboard.KEY_UP }, down = { Keyboard.KEY_DOWN },
    left = { Keyboard.KEY_LEFT }, right = { Keyboard.KEY_RIGHT },
    confirm = { Keyboard.KEY_ENTER, Keyboard.KEY_KP_ENTER },
    back = { Keyboard.KEY_BACKSPACE },
}

local REPEAT_DELAY, REPEAT_RATE = 15, 3

local function controllers()
    local seen, list = {}, {}
    for _, p in ipairs(AC.util.players()) do
        local idx = p.ControllerIndex
        if idx ~= 0 and not seen[idx] then
            seen[idx] = true
            list[#list + 1] = idx
        end
    end
    return list
end

local function padPressed(button)
    for _, idx in ipairs(controllers()) do
        if Input.IsButtonPressed(button, idx) then return true end
    end
    return false
end

local function keyPressed(key) return Input.IsButtonPressed(key, 0) end

-- Edge detection done by hand: IsButtonTriggered is tied to the 30 Hz game tick and can
-- report the same press on two 60 Hz render frames.
local prev = {}

local function edge(id, down)
    local was = prev[id]
    prev[id] = down
    return down and not was
end

local function keyTriggered(key)
    return edge("k" .. key, keyPressed(key))
end

-- Public edge check for a keyboard key (used by rule hotkeys).
function input.keyEdge(key)
    return keyTriggered(key)
end

local function padTriggered(button)
    local hit = false
    for _, idx in ipairs(controllers()) do
        if edge("p" .. idx .. ":" .. button, Input.IsButtonPressed(button, idx)) then hit = true end
    end
    return hit
end

function input.shift()
    return keyPressed(Keyboard.KEY_LEFT_SHIFT) or keyPressed(Keyboard.KEY_RIGHT_SHIFT)
        or padPressed(PAD.fast)
end

function input.toggleMenuPressed()
    local key = keyTriggered(AC.save.data.keys.open)
    local pad = padTriggered(PAD.y) and padPressed(PAD.select)
    if input.textTarget or AC.imgui.active() then return false end
    return key or pad
end

-- Returns true on the first frame and then repeatedly while held.
local function repeating(action)
    local down = false
    for _, key in ipairs(KEYS[action] or {}) do
        if keyPressed(key) then down = true break end
    end
    if not down and PAD[action] and padPressed(PAD[action]) then down = true end
    if not down then
        input.held[action] = nil
        return false
    end
    local n = (input.held[action] or 0) + 1
    input.held[action] = n
    return n == 1 or (n > REPEAT_DELAY and (n - REPEAT_DELAY) % REPEAT_RATE == 0)
end

-- Navigation events for this render frame.
--   alt    = Shift+Enter or controller X (second action, e.g. "put on the floor")
--   tabNext/tabPrev = Tab / Shift+Tab or controller RB / LB
function input.poll()
    local confirm = repeating("confirm") and input.held.confirm == 1
    local tab = keyTriggered(Keyboard.KEY_TAB)
    local padX, padLB, padRB = padTriggered(PAD.x), padTriggered(PAD.lb), padTriggered(PAD.rb)
    local shift = input.shift()
    return {
        up = repeating("up"),
        down = repeating("down"),
        left = repeating("left"),
        right = repeating("right"),
        confirm = confirm and not shift,
        alt = (confirm and shift) or padX,
        back = repeating("back") and input.held.back == 1,
        tabNext = (tab and not shift) or padRB,
        tabPrev = (tab and shift) or padLB,
    }
end

-- Text keys for the English layout and the Russian ЙЦУКЕН layout on the same physical keys.
-- The game only reports physical keys, so the layout is our own: toggled with Alt+Shift,
-- Ctrl+Shift or by clicking the [EN]/[RU] badge.
input.layout = "en"

local TEXT_EN, TEXT_RU = {}, {}
for k = Keyboard.KEY_A, Keyboard.KEY_Z do TEXT_EN[k] = string.char(k):lower() end
for k = Keyboard.KEY_0, Keyboard.KEY_9 do TEXT_EN[k] = string.char(k); TEXT_RU[k] = string.char(k) end
for k = Keyboard.KEY_KP_0, Keyboard.KEY_KP_9 do
    TEXT_EN[k] = tostring(k - Keyboard.KEY_KP_0); TEXT_RU[k] = TEXT_EN[k]
end
TEXT_EN[Keyboard.KEY_SPACE], TEXT_RU[Keyboard.KEY_SPACE] = " ", " "
TEXT_EN[Keyboard.KEY_PERIOD] = "."
TEXT_EN[Keyboard.KEY_MINUS], TEXT_RU[Keyboard.KEY_MINUS] = "-", "-"
TEXT_EN[Keyboard.KEY_APOSTROPHE] = "'"
local RU = {
    Q = "й", W = "ц", E = "у", R = "к", T = "е", Y = "н", U = "г", I = "ш", O = "щ", P = "з",
    A = "ф", S = "ы", D = "в", F = "а", G = "п", H = "р", J = "о", K = "л", L = "д",
    Z = "я", X = "ч", C = "с", V = "м", B = "и", N = "т", M = "ь",
    LEFT_BRACKET = "х", RIGHT_BRACKET = "ъ", SEMICOLON = "ж", APOSTROPHE = "э", COMMA = "б",
    PERIOD = "ю", GRAVE_ACCENT = "ё",
}
for name, ch in pairs(RU) do
    local key = Keyboard["KEY_" .. name]
    if key then TEXT_RU[key] = ch end
end
local TEXT_KEYS = {} -- every physical key used by either layout
for k in pairs(TEXT_EN) do TEXT_KEYS[k] = true end
for k in pairs(TEXT_RU) do TEXT_KEYS[k] = true end

function input.toggleLayout()
    input.layout = input.layout == "en" and "ru" or "en"
end

local function modifiers()
    return keyPressed(Keyboard.KEY_LEFT_ALT) or keyPressed(Keyboard.KEY_RIGHT_ALT)
        or keyPressed(Keyboard.KEY_LEFT_CONTROL) or keyPressed(Keyboard.KEY_RIGHT_CONTROL)
end

local comboHeld = false
local function checkLayoutCombo()
    local held = input.shift() and modifiers()
    if held and not comboHeld then input.toggleLayout() end
    comboHeld = held
end

function input.ctrl()
    return keyPressed(Keyboard.KEY_LEFT_CONTROL) or keyPressed(Keyboard.KEY_RIGHT_CONTROL)
end

-- Characters typed this frame (grid pages filter as you type, no text field needed).
function input.typed()
    checkLayoutCombo()
    if modifiers() then
        for key in pairs(TEXT_KEYS) do keyTriggered(key) end -- keep edge state fresh, type nothing
        return ""
    end
    local map = input.layout == "ru" and TEXT_RU or TEXT_EN
    local s = ""
    for key in pairs(TEXT_KEYS) do
        if keyTriggered(key) and map[key] then s = s .. map[key] end
    end
    return s
end

-- Esc (never while typing into a text field) and the Q/E tab keys (only on pages without search).
function input.escape() return keyTriggered(Keyboard.KEY_ESCAPE) end
function input.tabKeys()
    return keyTriggered(Keyboard.KEY_E), keyTriggered(Keyboard.KEY_Q)
end

-- Mouse in screen (render) coordinates, with click edges.
local mouseLast, mouseMovedAt = nil, -1000
local mouseDown = {}
function input.mouse()
    local ok, world = pcall(Input.GetMousePosition, true)
    if not ok or not world then return nil end
    local pos = Isaac.WorldToScreen(world)
    local moved = mouseLast ~= nil and (math.abs(pos.X - mouseLast.X) + math.abs(pos.Y - mouseLast.Y)) > 0.5
    mouseLast = pos
    if moved then mouseMovedAt = Isaac.GetFrameCount() end
    local function edge(btn)
        local down = Input.IsMouseBtnPressed(btn)
        local was = mouseDown[btn]
        mouseDown[btn] = down
        return down and not was
    end
    return {
        pos = pos, moved = moved,
        active = Isaac.GetFrameCount() - mouseMovedAt < 300, -- used recently: show the cursor
        left = edge(0), right = edge(1),
    }
end

local END_KEYS = { Keyboard.KEY_ENTER, Keyboard.KEY_KP_ENTER, Keyboard.KEY_ESCAPE, Keyboard.KEY_BACKSPACE }

function input.beginText(target)
    input.textTarget = target
    input.held = {}
    -- Keys already down (e.g. the Enter that started entry) must not count as new presses.
    for key in pairs(TEXT_KEYS) do prev["k" .. key] = keyPressed(key) end
    prev["k" .. Keyboard.KEY_ESCAPE] = keyPressed(Keyboard.KEY_ESCAPE)
    for _, key in ipairs(END_KEYS) do prev["k" .. key] = keyPressed(key) end
    for _, idx in ipairs(controllers()) do
        prev["p" .. idx .. ":" .. PAD.confirm] = Input.IsButtonPressed(PAD.confirm, idx)
        prev["p" .. idx .. ":" .. PAD.back] = Input.IsButtonPressed(PAD.back, idx)
    end
end

function input.updateText()
    local t = input.textTarget
    if not t then return end
    local changed = false
    local typed = input.typed()
    if typed ~= "" then
        t.text = t.text .. typed
        changed = true
    end
    if keyTriggered(Keyboard.KEY_BACKSPACE) and #t.text > 0 then
        t.text = t.text:sub(1, -2)
        changed = true
    end
    if changed and t.onChange then t.onChange(t.text) end
    local finished = false
    for _, key in ipairs({ Keyboard.KEY_ENTER, Keyboard.KEY_KP_ENTER, Keyboard.KEY_ESCAPE }) do
        if keyTriggered(key) then finished = true end
    end
    if padTriggered(PAD.confirm) then finished = true end
    if padTriggered(PAD.back) then finished = true end
    if finished then
        input.textTarget = nil
        input.held = { confirm = 1, back = 1 } -- swallow the key that ended entry
        prev["k" .. Keyboard.KEY_ESCAPE] = true -- an Esc that ends typing must not also close the menu
        if t.onDone then t.onDone(t.text) end
    end
end

-- Gameplay actions blocked while the menu is open.
local BLOCKED = {}
for _, name in ipairs({
    "ACTION_LEFT", "ACTION_RIGHT", "ACTION_UP", "ACTION_DOWN",
    "ACTION_SHOOTLEFT", "ACTION_SHOOTRIGHT", "ACTION_SHOOTUP", "ACTION_SHOOTDOWN",
    "ACTION_BOMB", "ACTION_ITEM", "ACTION_PILLCARD", "ACTION_DROP", "ACTION_MAP",
    "ACTION_RESTART", "ACTION_FULLSCREEN", "ACTION_MUTE",
    -- Esc / Start: the first press closes our menu instead of opening the game's pause menu
    "ACTION_PAUSE", "ACTION_MENUBACK",
}) do
    if ButtonAction[name] then BLOCKED[ButtonAction[name]] = true end
end

local PAUSE_ACTIONS = { [ButtonAction.ACTION_PAUSE or -1] = true, [ButtonAction.ACTION_MENUBACK or -1] = true }

function input.onInputAction(_, entity, hook, action)
    local grace = PAUSE_ACTIONS[action] and Isaac.GetFrameCount() < (input.pauseGrace or 0)
    if not ((input.blocking and BLOCKED[action]) or grace) then return nil end
    if AC.game:IsPaused() then return nil end -- the game's own menu is open: leave it alone
    if entity and not entity:ToPlayer() then return nil end
    if hook == InputHook.GET_ACTION_VALUE then return 0 end
    return false
end

return input
