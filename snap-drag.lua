-- Snap the focused window to 1/4, 1/2 or 3/4 of the screen width after a
-- resize with the mouse (SUPER + right drag, or a drag on a border), when it
-- ends within 2% of one. Only the dragged edge moves, so only the neighbour
-- on that side changes. While the edge is within reach of a snap point, the
-- exe.snap shell plugin draws a line where it will land.
-- Loaded from ~/.config/hypr/bindings.lua; the file returns a setup function:
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/exe.snap/snap-drag.lua")({
--     widths = { "1/3", "1/2", "2/3", 0.4 }, -- default { "1/4", "1/2", "3/4" }
--     tolerance = 0.02, -- reach, as a share of the screen width
--   })
--
-- The binds watch the left and right mouse buttons without taking them from
-- apps (non_consuming, transparent). While a button is down a timer checks the
-- focused window's width every 30 ms; a plain click never changes it, so it
-- costs a few table lookups and starts no process.
local snap = os.getenv("HOME") .. "/.config/omarchy/plugins/exe.snap/snap.sh"
local fractions = {} -- { share, label }, from the widths given to setup
local tolerance = 0.02

local pressed = nil -- the focused window's box when the button went down
local shown = nil -- the snap the guide line shows: { fraction, edge, payload }

local function box()
  local window = hl.get_active_window()
  if not window or not window.monitor then
    return nil
  end
  return { window = window, address = window.address, x = window.at.x, width = window.size.x }
end

local function round(n)
  return math.floor(n + 0.5)
end

-- The snap the dragged edge is within reach of, or nil.
-- A window's box is its size plus its border on both sides, and boxes sit
-- 2 * gaps_in apart; snap.sh works out the same numbers.
local function reach(now)
  if not pressed or now.address ~= pressed.address or now.width == pressed.width then
    return nil
  end
  local window, m = now.window, now.window.monitor
  local r = m.reserved
  local b = hl.get_config("general.border_size")
  local gi, go = hl.get_config("general.gaps_in"), hl.get_config("general.gaps_out")
  local sp = 2 * gi.left
  local width = (m.transform % 2 == 1 and m.height or m.width) / m.scale
  local height = (m.transform % 2 == 1 and m.width or m.height) / m.scale
  local area = width - r.left - r.right - go.left - go.right
  local share = (now.width + 2 * b + sp) / (area + sp)

  for _, f in ipairs(fractions) do
    if math.abs(f[1] - share) <= tolerance then
      -- The left edge moved when the window's x did; otherwise the right one.
      local edge = now.x ~= pressed.x and "left" or "right"
      local mine = round((area + sp) * f[1]) - sp
      local x = edge == "right" and now.x - b + mine or now.x + now.width + b - mine
      local payload = string.format(
        '{"guide":{"monitor":"%s","x":%d,"top":%d,"bottom":%d,"label":"%s"}}',
        m.name, round(x - m.x), round(r.top + go.top), round(height - r.bottom - go.bottom), f[2])
      return { fraction = f[1], edge = edge, payload = payload }
    end
  end
  return nil
end

local function show(next)
  if next and shown and next.payload == shown.payload then
    return
  end
  if next then
    hl.exec_cmd("omarchy-shell shell summon exe.snap '" .. next.payload .. "'")
  elseif shown then
    hl.exec_cmd("omarchy-shell shell hide exe.snap")
  end
  shown = next
end

-- A width as "a/b" or a share such as 0.4: { share, label }.
local function fraction(w)
  local a, b = tostring(w):match("^%s*(%d+)%s*/%s*(%d+)%s*$")
  local share = a and tonumber(a) / tonumber(b) or tonumber(w)
  if not share or share <= 0 or share >= 1 then
    error("exe.snap: bad width " .. tostring(w) .. ", use \"1/3\" or a share between 0 and 1")
  end
  return { share, a and (a .. "/" .. b) or string.format("%g%%", share * 100) }
end

return function(opts)
  opts = opts or {}
  tolerance = opts.tolerance or tolerance
  for _, w in ipairs(opts.widths or { "1/4", "1/2", "3/4" }) do
    table.insert(fractions, fraction(w))
  end

  local timer = hl.timer(function()
    local now = box()
    show(now and reach(now) or nil)
  end, { timeout = 30, type = "repeat" })
  timer:set_enabled(false)

  local options = { ignore_mods = true, non_consuming = true, transparent = true }
  local release = { ignore_mods = true, non_consuming = true, transparent = true, release = true }

  for _, button in ipairs({ "mouse:272", "mouse:273" }) do
    hl.bind(button, function()
      pressed = box()
      timer:set_enabled(pressed ~= nil)
    end, options)
    hl.bind(button, function()
      timer:set_enabled(false)
      local now = box()
      local target = now and reach(now) or nil
      pressed = nil
      show(nil)
      if target then
        hl.exec_cmd(snap .. " " .. target.fraction .. " " .. target.edge)
      end
    end, release)
  end
end
