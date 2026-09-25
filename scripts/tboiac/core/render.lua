-- Drawing primitives: text, filled boxes, toast notifications.
local AC = TBOIAC

local render = { toasts = {} }

-- Fonts that may contain Cyrillic glyphs are tried first; the last one is a safe fallback.
local FONT_CANDIDATES = {
    "font/cjk/lanapixel.fnt",
    "font/teammeatfontextended10.fnt",
    "font/terminus.fnt",
    "font/pftempestasevencondensed.fnt",
}

local font, box

local function getFont()
    if font then return font end
    for _, path in ipairs(FONT_CANDIDATES) do
        local f = Font()
        f:Load(path)
        if f:IsLoaded() then
            font = f
            AC.util.log("font: " .. path)
            return font
        end
    end
    return nil
end

local function getBox()
    if box then return box end
    box = Sprite()
    box:Load("gfx/tboiac/ui/box.anm2", true)
    box:Play("Idle", true)
    return box
end

function render.lineHeight()
    local f = getFont()
    return (f and f:GetLineHeight() or 10) * AC.save.data.ui.scale + 2
end

function render.textWidth(s, scale)
    local f = getFont()
    if not f then return #s * 6 end
    return f:GetStringWidthUTF8(s) * AC.save.data.ui.scale * (scale or 1)
end

-- color = { r, g, b, a } with components in 0..1; `scale` multiplies the UI text scale.
function render.text(s, x, y, color, scale)
    local f = getFont()
    color = color or { 1, 1, 1, 1 }
    if f then
        scale = AC.save.data.ui.scale * (scale or 1)
        f:DrawStringScaledUTF8(s, x, y, scale, scale, KColor(color[1], color[2], color[3], color[4]), 0, false)
    else
        Isaac.RenderText(s, x, y, color[1], color[2], color[3], color[4])
    end
end

function render.rect(x, y, w, h, color)
    local s = getBox()
    s.Scale = Vector(w, h)
    s.Color = Color(color[1], color[2], color[3], color[4])
    s:Render(Vector(x, y))
end

function render.toast(msg, frames)
    if AC.save.data.studio and AC.save.data.studio.clean then return end -- "clean frame" for recording
    table.insert(render.toasts, { msg = msg, t = frames or 90 })
    while #render.toasts > 5 do table.remove(render.toasts, 1) end
end

function render.drawToasts()
    local lh = render.lineHeight()
    local y = Isaac.GetScreenHeight() - 40 - lh * #render.toasts
    for i = #render.toasts, 1, -1 do
        local t = render.toasts[i]
        t.t = t.t - 1
        if t.t <= 0 then table.remove(render.toasts, i) end
    end
    for _, t in ipairs(render.toasts) do
        local a = math.min(1, t.t / 20)
        local w = render.textWidth(t.msg) + 8
        render.rect(8, y - 1, w, lh, { 0, 0, 0, 0.6 * a })
        render.text(t.msg, 12, y, { 1, 1, 0.6, a })
        y = y + lh
    end
end

return render
