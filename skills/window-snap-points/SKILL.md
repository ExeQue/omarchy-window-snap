---
name: window-snap-points
description: Turn a Hyprland workspace's current window layout into snap points for the Omarchy Window Snap plugin (exeque.omarchy-window-snap), so a mouse resize on that workspace snaps back to the same widths and heights. Use when asked to save, capture or copy a workspace layout as snap points, to set per-workspace snap points, or to make a workspace snap to the sizes its windows have now.
---

# Window snap points from a workspace layout

The Omarchy Window Snap plugin (`~/.config/omarchy/plugins/exeque.omarchy-window-snap`) snaps a window's width and height to snap points after a mouse resize. It has a default set of snap points, and each workspace can override them with its own. This skill writes such an override from the windows a workspace has now.

## Steps

1. **Pick the workspace.** Use the id or name the user gave. Otherwise use the active one (`hyprctl activeworkspace -j | jq '{id, name}'`), and say which it is.

2. **Read the layout.** Run:

   ```bash
   ~/.config/omarchy/plugins/exeque.omarchy-window-snap/snap-points.sh <workspace>
   ```

   It prints one Lua line, a `workspaces` entry such as:

   ```lua
   [3] = { widths = { "1/3", "2/3" }, heights = { "1/2" } },
   ```

   Each tiled window's width and height is a snap point, written as a fraction up to twelfths when one is within 16 px, else as a number between 0 and 1. An axis where every window spans the whole screen is left out, so that axis keeps the default snap points. If it prints a comment instead (every window spans the whole screen), tell the user there is nothing to snap to and stop.

3. **Show the user the snap points** in plain words (e.g. "widths 1/3 and 2/3, heights 1/2") and ask before changing their config. Offer to add the defaults' points too when the layout gives only one or two per axis, since a workspace's own list replaces the default list for that axis.

4. **Find the setup call.** It is the line that loads `snap-drag.lua`, usually in `~/.config/hypr/bindings.lua`:

   ```bash
   grep -rn "exeque.omarchy-window-snap/snap-drag.lua" ~/.config/hypr/
   ```

5. **Add the entry to the options table** of that call, inside `workspaces`, keeping every other option as it is:
   - `...snap-drag.lua")()` becomes `...snap-drag.lua")({ workspaces = { <entry> } })`.
   - With options but no `workspaces`, add `workspaces = { <entry> },` to the table.
   - With `workspaces` already there, add the entry, or replace the one with the same key (`[3]` or `["name"]`).

   Write it over several lines when the table grows past one line:

   ```lua
   dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/exeque.omarchy-window-snap/snap-drag.lua")({
     workspaces = {
       [3] = { widths = { "1/3", "2/3" }, heights = { "1/2" } },
     },
   })
   ```

6. **Check it.** Run `hyprctl reload`, then `hyprctl configerrors`; it must print nothing. A bad snap point shows up there as `exeque.omarchy-window-snap: bad size ...`.

## Notes

- Workspace keys: `[3]` for a numbered workspace, `["name"]` for a named one, e.g. `["special:scratch"]`. The script picks the right form.
- A workspace entry takes `widths`, `wide_widths` and `heights`. Its `widths` count on wide screens too unless it also sets `wide_widths`. What it leaves out comes from the defaults.
- `heights = {}` turns height snapping off for that workspace.
- Only edit the user's own config. Never edit files under `/usr/share/omarchy/`, and never edit the plugin's files to store a layout.
