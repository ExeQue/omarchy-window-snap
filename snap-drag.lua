-- Snap the focused window to a fraction of the screen width or height after
-- a resize with the mouse (SUPER + right drag, or a drag on a border), when
-- the dragged edge ends within 40 px of one. By default that
-- is quarters of the height, and quarters of the width, or eighths on a wide
-- screen. Only the dragged edge moves, so only the neighbour on that side
-- changes. While an edge is within reach of a snap point, the exe.snap shell
-- plugin draws a line where it will land.
-- Loaded from ~/.config/hypr/bindings.lua; the file returns a setup function
-- (every option can be left out; a list may hold "a/b" or a share like 0.4):
--
--   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/exe.snap/snap-drag.lua")({
--     widths = { "1/3", "1/2", "2/3" }, -- default { "1/4", "1/2", "3/4" }
--     wide_widths = { "1/4", "1/2", "3/4" }, -- default eighths, "1/8" to "7/8"
--     wide = 2400, -- screens at least this wide (logical px) use wide_widths
--     heights = { "1/2" }, -- default { "1/4", "1/2", "3/4" }; {} snaps no heights
--     tolerance = 40, -- reach in logical px, on both axes
--   })
--
-- The binds watch the left and right mouse buttons without taking them from
-- apps (non_consuming, transparent). While a button is down a timer checks the
-- focused window's size every 30 ms; a plain click never changes it, so it
-- costs a few table lookups and starts no process.
local snap = os.getenv("HOME") .. "/.config/omarchy/plugins/exe.snap/snap.sh"
-- Snap points as { share, label }, from setup: x on a narrow screen, wide on
-- a wide one, y for heights.
local fractions = { x = {}, wide = {}, y = {} }
local tolerance = 40 -- logical px
local wide = 2400

local near = { x = "left", y = "top" }
local far = { x = "right", y = "bottom" }
local across = { x = "y", y = "x" }

local pressed = nil -- the focused window's box when the button went down
local shown = nil -- the snaps the guide lines show, from reach()

-- The window as it is now, as a box that keeps its numbers.
local function box(window)
  if not window or not window.monitor then
    return nil
  end
  return {
    window = window,
    address = window.address,
    at = { x = window.at.x, y = window.at.y },
    size = { x = window.size.x, y = window.size.y },
  }
end

-- The window the mouse grabs: the one under the cursor, or the nearest one
-- whose border (plus general.extend_border_grab_area) is under it. Not the
-- focused window: a drag on a border does not focus, and focus need not follow
-- the mouse. A floating window lies on top, so it wins.
local function grabbed()
  local c = hl.get_cursor_pos()
  local m = hl.get_monitor_at_cursor()
  local ws = m and hl.get_active_workspace(m)
  if not c or not ws then
    return nil
  end
  local reach = hl.get_config("general.border_size") + hl.get_config("general.extend_border_grab_area")
  local best, best_distance, best_floating = nil, math.huge, false
  for _, w in ipairs(hl.get_workspace_windows(ws.id)) do
    if not w.hidden then
      local dx = math.max(w.at.x - c.x, 0, c.x - (w.at.x + w.size.x))
      local dy = math.max(w.at.y - c.y, 0, c.y - (w.at.y + w.size.y))
      local distance = math.max(dx, dy)
      local floating = w.floating and distance <= reach
      if distance <= reach and (floating and not best_floating or floating == best_floating and distance < best_distance) then
        best, best_distance, best_floating = w, distance, floating
      end
    end
  end
  return box(best)
end

local function round(n)
  return math.floor(n + 0.5)
end

-- The snaps the dragged edges are within reach of: { hits, payload } with a
-- hit { fraction, edge } per axis, or nil. A corner drag can snap both axes;
-- an axis whose size has not changed since the button went down never snaps.
-- A window's box is its size plus its border on both sides, and boxes sit
-- 2 * gaps_in apart; snap.sh works out the same numbers.
local function reach(now)
  if not pressed or now.address ~= pressed.address then
    return nil
  end
  local m = now.window.monitor
  local r = m.reserved
  local b = hl.get_config("general.border_size")
  local gi, go = hl.get_config("general.gaps_in"), hl.get_config("general.gaps_out")
  local rot = m.transform % 2 == 1
  local size = { x = (rot and m.height or m.width) / m.scale, y = (rot and m.width or m.height) / m.scale }
  -- The usable stretch of the monitor along an axis, from its own origin.
  local function span(axis)
    return r[near[axis]] + go[near[axis]], size[axis] - r[far[axis]] - go[far[axis]]
  end

  local hits, guides = {}, {}
  for _, a in ipairs({ "x", "y" }) do
    if now.size[a] ~= pressed.size[a] then
      local from, to = span(a)
      local sp = 2 * gi[near[a]]
      local length = now.size[a] + 2 * b + sp
      local list = a == "y" and "y" or size.x >= wide and "wide" or "x"
      for _, f in ipairs(fractions[list]) do
        if math.abs((to - from + sp) * f[1] - length) <= tolerance then
          -- The near edge moved when the window's position did; otherwise the far one.
          local edge = now.at[a] ~= pressed.at[a] and near[a] or far[a]
          local mine = round((to - from + sp) * f[1]) - sp
          local pos = edge == far[a] and now.at[a] - b + mine or now.at[a] + now.size[a] + b - mine
          local lo, hi = span(across[a])
          table.insert(hits, { fraction = f[1], edge = edge })
          table.insert(guides, string.format('{"axis":"%s","pos":%d,"from":%d,"to":%d,"label":"%s"}',
            a, round(pos - m[a]), round(lo), round(hi), f[2]))
          break
        end
      end
    end
  end
  if #hits == 0 then
    return nil
  end
  local payload = string.format('{"monitor":"%s","guides":[%s]}', m.name, table.concat(guides, ","))
  return { hits = hits, payload = payload }
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
    error("exe.snap: bad size " .. tostring(w) .. ", use \"1/3\" or a share between 0 and 1")
  end
  return { share, a and (a .. "/" .. b) or string.format("%g%%", share * 100) }
end

return function(opts)
  opts = opts or {}
  tolerance = opts.tolerance or tolerance
  wide = opts.wide or wide
  local quarters = { "1/4", "1/2", "3/4" }
  local eighths = { "1/8", "1/4", "3/8", "1/2", "5/8", "3/4", "7/8" }
  for list, given in pairs({
    x = opts.widths or quarters,
    wide = opts.wide_widths or eighths,
    y = opts.heights or quarters,
  }) do
    for _, w in ipairs(given) do
      table.insert(fractions[list], fraction(w))
    end
  end

  local timer = hl.timer(function()
    local now = pressed and box(hl.get_window("address:" .. pressed.address))
    show(now and reach(now) or nil)
  end, { timeout = 30, type = "repeat" })
  timer:set_enabled(false)

  local options = { ignore_mods = true, non_consuming = true, transparent = true }
  local release = { ignore_mods = true, non_consuming = true, transparent = true, release = true }

  for _, button in ipairs({ "mouse:272", "mouse:273" }) do
    hl.bind(button, function()
      pressed = grabbed()
      timer:set_enabled(pressed ~= nil)
    end, options)
    hl.bind(button, function()
      timer:set_enabled(false)
      local now = pressed and box(hl.get_window("address:" .. pressed.address))
      local target = now and reach(now) or nil
      pressed = nil
      show(nil)
      if target then
        local commands = {}
        for _, hit in ipairs(target.hits) do
          table.insert(commands, snap .. " " .. hit.fraction .. " " .. hit.edge .. " " .. now.address)
        end
        hl.exec_cmd(table.concat(commands, "; "))
      end
    end, release)
  end
end
