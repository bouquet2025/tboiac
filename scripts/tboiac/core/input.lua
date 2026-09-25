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
    select = C.BUTTON_BACK or 14, fast = C.BUMPER_RIGHT or 11,
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
    if input.textTarget then return false end
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
function input.poll()
    return {
        up = repeating("up"),
        down = repeating("down"),
        left = repeating("left"),
        right = repeating("right"),
        confirm = repeating("confirm") and input.held.confirm == 1,
        back = repeating("back") and input.held.back == 1,
    }
end

local TEXT_KEYS = {}
for k = Keyboard.KEY_A, Keyboard.KEY_Z do TEXT_KEYS[k] = string.char(k):lower() end
for k = Keyboard.KEY_0, Keyboard.KEY_9 do TEXT_KEYS[k] = string.char(k) end
for k = Keyboard.KEY_KP_0, Keyboard.KEY_KP_9 do TEXT_KEYS[k] = tostring(k - Keyboard.KEY_KP_0) end
TEXT_KEYS[Keyboard.KEY_SPACE] = " "
TEXT_KEYS[Keyboard.KEY_PERIOD] = "."
TEXT_KEYS[Keyboard.KEY_MINUS] = "-"
TEXT_KEYS[Keyboard.KEY_APOSTROPHE] = "'"

-- Start text entry. `target` = { text = "...", onChange = fn(text), onDone = fn(text) }.
local END_KEYS = { Keyboard.KEY_ENTER, Keyboard.KEY_KP_ENTER, Keyboard.KEY_ESCAPE, Keyboard.KEY_BACKSPACE }

function input.beginText(target)
    input.textTarget = target
    input.held = {}
    -- Keys already down (e.g. the Enter that started entry) must not count as new presses.
    for key in pairs(TEXT_KEYS) do prev["k" .. key] = keyPressed(key) end
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
    for key, ch in pairs(TEXT_KEYS) do
        if keyTriggered(key) then
            t.text = t.text .. ch
            changed = true
        end
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
}) do
    if ButtonAction[name] then BLOCKED[ButtonAction[name]] = true end
end

function input.onInputAction(_, entity, hook, action)
    if not input.blocking or not BLOCKED[action] then return nil end
    if entity and not entity:ToPlayer() then return nil end
    if hook == InputHook.GET_ACTION_VALUE then return 0 end
    return false
end

return input
