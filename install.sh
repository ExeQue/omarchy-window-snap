#!/bin/bash
# Turn on the mouse snapping in Hyprland: add the line that loads
# snap-drag.lua to ~/.config/hypr/bindings.lua, unless the Hyprland config
# already loads it, then reload Hyprland and check for config errors.
# The guide lines come from the shell plugin, which `omarchy plugin add
# --enable` sets up; Omarchy loads no Hyprland files from plugins by itself.
set -euo pipefail

hypr=${XDG_CONFIG_HOME:-$HOME/.config}/hypr
file=$hypr/bindings.lua

if grep -rqs --include='*.lua' "exe.snap/snap-drag.lua" "$hypr"; then
  echo "Hyprland already loads snap-drag.lua ($(grep -rls --include='*.lua' "exe.snap/snap-drag.lua" "$hypr" | head -1))"
else
  cat >>"$file" <<'EOF'

-- Snap window width and height to fractions of the screen after a mouse resize (exe.snap plugin).
-- Options (widths, wide_widths, wide, heights, tolerance, workspaces): see ~/.config/omarchy/plugins/exe.snap/README.md
dofile(os.getenv("HOME") .. "/.config/omarchy/plugins/exe.snap/snap-drag.lua")()
EOF
  echo "Added snap-drag.lua to $file"
fi

hyprctl reload >/dev/null
errors=$(hyprctl configerrors)
if [ -n "$errors" ]; then
  echo "Hyprland reports config errors:" >&2
  echo "$errors" >&2
  exit 1
fi
echo "Mouse snapping is on."
