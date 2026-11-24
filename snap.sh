#!/bin/bash
# Move the edge of the focused window that was dragged with the mouse, so the
# window takes a fraction of its monitor's usable width, e.g.
# `snap.sh 0.25 right`. Called by snap-drag.lua after a resize. Only that edge
# moves, so only the neighbour on that side changes.
#
# Dwindle has no way to set a split directly. A relative resize of a window
# moves one split in its tree by the given number of pixels, but which split
# (the window's left or right edge) depends on the tree. So each boundary
# between two windows in the row is moved towards its target through the
# window on its left, or, when that moves the wrong split, the one on its
# right; moving an outer split rescales the inner ones, so this repeats until
# every boundary sits where it should.
set -euo pipefail

usage="usage: snap.sh <fraction 0-1> <left|right>"
frac=${1:?$usage}
edge=${2:?$usage}
[[ $frac =~ ^0?\.[0-9]+$|^1(\.0+)?$ ]] || { echo "bad fraction: $frac" >&2; exit 1; }
[[ $edge =~ ^(left|right)$ ]] || { echo "bad edge: $edge" >&2; exit 1; }

win=$(hyprctl activewindow -j)
addr=$(jq -r '.address // empty' <<<"$win")
[ -n "$addr" ] || exit 0
layout=$(hyprctl workspaces -j | jq -r --argjson id "$(jq '.workspace.id' <<<"$win")" '.[] | select(.id == $id) | .tiledLayout')

# The scrolling layout sizes columns as a share of the monitor itself.
if [ "$layout" = scrolling ] && [ "$(jq '.floating' <<<"$win")" = false ]; then
  hyprctl dispatch "hl.dsp.layout(\"colresize $frac\")" >/dev/null
  exit 0
fi

mon=$(hyprctl monitors -j | jq --argjson id "$(jq '.monitor' <<<"$win")" '.[] | select(.id == $id)')
border=$(hyprctl getoption general:border_size -j | jq '.int')
# css order: top right bottom left
read -r _ out_r _ out_l <<<"$(hyprctl getoption general:gaps_out -j | jq -r '.css')"
read -r _ _ _ in_l <<<"$(hyprctl getoption general:gaps_in -j | jq -r '.css')"

# A window's box is its size plus its border on both sides (.at is inside the
# border), and boxes sit 2 * gaps_in apart.
# One line per window in the row, left to right: "address target-x", where
# target-x is where its left edge (.at[0]) should end up. Or, for a floating
# window, "single width x y": its new width, and where to put it so the edge
# that was not dragged stays put (a resize alone keeps its centre).
plan=$(hyprctl clients -j | jq -r --argjson win "$win" --argjson m "$mon" --argjson frac "$frac" \
  --arg edge "$edge" --argjson b "$border" --argjson gl "$out_l" --argjson gr "$out_r" --argjson gi "$in_l" '
  ($m.transform % 2 == 1) as $rot
  | ((if $rot then $m.height else $m.width end) / $m.scale
     - $m.reserved[0] - $m.reserved[2] - $gl - $gr) as $area
  | (2 * $gi) as $sp
  | (($area + $sp) * $frac | round - $sp) as $mine
  | if $win.floating then
      ($mine - 2 * $b) as $width
      | "single \($width) \($win.at[0] + (if $edge == "left" then $win.size[0] - $width else 0 end)) \($win.at[1])"
    else
      # Tiled windows on the workspace beside the focused one: those that
      # overlap it vertically, one per left edge. That keeps one window of a
      # stack or a group, the focused window first.
      # ponytail: a nested split, such as A | (B / (C | D)) seen from A, puts
      # C and D in the row too; their boundary is then held where it is.
      [ .[] | select(.workspace.id == $win.workspace.id and (.floating | not)
                     and .at[1] < $win.at[1] + $win.size[1] and $win.at[1] < .at[1] + .size[1]) ]
      | sort_by(.address != $win.address) | unique_by(.at[0])
      | sort_by(.at[0])
      | (map(.address) | index($win.address)) as $i
      | (if $edge == "right" then $i + 1 else $i end) as $k
      # Only the dragged edge moves, to where the window is $mine wide. Moving
      # an outer split rescales the windows under it, so every other boundary
      # is held where it is.
      | (if $edge == "right" then $win.at[0] + $mine + $sp
         else $win.at[0] + $win.size[0] + 2 * $b - $mine end) as $moved
      | if $k < 1 or $k >= length then empty else
          to_entries[]
          | "\(.value.address) \(if .key == $k then $moved else .value.at[0] end)"
        end
    end')
[ -n "$plan" ] || exit 0
if [[ $plan == single\ * ]]; then
  read -r _ width x y <<<"$plan"
  height=$(jq '.size[1]' <<<"$win")
  hyprctl dispatch "hl.dsp.window.resize({ window = \"address:$addr\", x = $width, y = $height })" >/dev/null
  hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", x = $x, y = $y })" >/dev/null
  exit 0
fi
mapfile -t addrs < <(cut -d' ' -f1 <<<"$plan")
mapfile -t targets < <(cut -d' ' -f2 <<<"$plan")

left_edge() { hyprctl clients -j | jq --arg a "$1" '.[] | select(.address == $a) | .at[0]'; }
nudge() { hyprctl dispatch "hl.dsp.window.resize({ window = \"address:$1\", x = $2, y = 0, relative = true })" >/dev/null; }

for _ in $(seq 8); do
  settled=true
  for ((k = 1; k < ${#addrs[@]}; k++)); do
    right=${addrs[k]} target=${targets[k]}
    off=$(( target - $(left_edge "$right") ))
    (( off > 1 || off < -1 )) || continue
    settled=false
    for mover in "${addrs[k - 1]}" "$right"; do
      nudge "$mover" "$off"
      now=$(( target - $(left_edge "$right") ))
      (( ${now#-} < ${off#-} )) && break
      nudge "$mover" $(( -off ))
    done
  done
  $settled && break
done
