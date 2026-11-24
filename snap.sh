#!/bin/bash
# Move the edge of the focused window that was dragged with the mouse, so the
# window takes a fraction of its monitor's usable width or height, e.g.
# `snap.sh 0.25 right [address]`, for the focused window when no address is
# given. Called by snap-drag.lua after a resize. Only that edge
# moves, so only the neighbour on that side changes.
#
# Dwindle has no way to set a split directly. A relative resize of a window
# moves one split in its tree by the given number of pixels, but which split
# (the window's near or far edge) depends on the tree. So each boundary
# between two windows in the row (or column) is moved towards its target
# through the window before it, or, when that moves the wrong split, the one
# after it; moving an outer split rescales the inner ones, so this repeats
# until every boundary sits where it should.
set -euo pipefail

usage="usage: snap.sh <fraction 0-1> <left|right|top|bottom> [address]"
frac=${1:?$usage}
edge=${2:?$usage}
[[ $frac =~ ^0?\.[0-9]+$|^1(\.0+)?$ ]] || { echo "bad fraction: $frac" >&2; exit 1; }
case $edge in
  left | right) ax=0 ;;
  top | bottom) ax=1 ;;
  *) echo "bad edge: $edge" >&2; exit 1 ;;
esac

target=${3:-}
[[ $target =~ ^(0x[0-9a-f]+)?$ ]] || { echo "bad address: $target" >&2; exit 1; }
if [ -n "$target" ]; then
  win=$(hyprctl clients -j | jq --arg a "$target" '.[] | select(.address == $a)')
else
  win=$(hyprctl activewindow -j)
fi
[ -n "$win" ] || exit 0
addr=$(jq -r '.address // empty' <<<"$win")
[ -n "$addr" ] || exit 0
layout=$(hyprctl workspaces -j | jq -r --argjson id "$(jq '.workspace.id' <<<"$win")" '.[] | select(.id == $id) | .tiledLayout')

# The scrolling layout sizes columns as a share of the monitor itself.
if [ "$layout" = scrolling ] && [ $ax = 0 ] && [ "$(jq '.floating' <<<"$win")" = false ]; then
  # colresize works on the focused column.
  hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
  hyprctl dispatch "hl.dsp.layout(\"colresize $frac\")" >/dev/null
  exit 0
fi

mon=$(hyprctl monitors -j | jq --argjson id "$(jq '.monitor' <<<"$win")" '.[] | select(.id == $id)')
border=$(hyprctl getoption general:border_size -j | jq '.int')
# css order: top right bottom left
read -r out_t out_r out_b out_l <<<"$(hyprctl getoption general:gaps_out -j | jq -r '.css')"
read -r in_t _ _ in_l <<<"$(hyprctl getoption general:gaps_in -j | jq -r '.css')"

# A window's box is its size plus its border on both sides (.at is inside the
# border), and boxes sit 2 * gaps_in apart.
# One line per window in the row (or column), in order: "address target",
# where target is where its near edge (.at[ax]) should end up. Or, for a
# floating window, "single w h x y": its new size, and where to put it so the
# edge that was not dragged stays put (a resize alone keeps its centre).
plan=$(hyprctl clients -j | jq -r --argjson win "$win" --argjson m "$mon" --argjson frac "$frac" \
  --arg edge "$edge" --argjson ax "$ax" --argjson b "$border" \
  --argjson ot "$out_t" --argjson or "$out_r" --argjson ob "$out_b" --argjson ol "$out_l" \
  --argjson it "$in_t" --argjson il "$in_l" '
  # reserved: left top right bottom
  ([$m.width, $m.height] | if $m.transform % 2 == 1 then reverse else . end | map(. / $m.scale)) as $size
  | (if $ax == 0 then $size[0] - $m.reserved[0] - $m.reserved[2] - $ol - $or
     else $size[1] - $m.reserved[1] - $m.reserved[3] - $ot - $ob end) as $area
  | (2 * (if $ax == 0 then $il else $it end)) as $sp
  | (1 - $ax) as $o
  | (($area + $sp) * $frac | round - $sp) as $mine
  | ($edge == "right" or $edge == "bottom") as $far
  | if $win.floating then
      ($mine - 2 * $b) as $len
      | ($win.size | .[$ax] = $len) as $new
      | ($win.at | if $far then . else .[$ax] += $win.size[$ax] - $len end) as $at
      | "single \($new[0]) \($new[1]) \($at[0]) \($at[1])"
    else
      # Tiled windows on the workspace beside the focused one along the axis:
      # those that overlap it across the axis, one per near edge. That keeps
      # one window of a stack or a group, the focused window first.
      # ponytail: a nested split, such as A | (B / (C | D)) seen from A, puts
      # C and D in the row too; their boundary is then held where it is.
      [ .[] | select(.workspace.id == $win.workspace.id and (.floating | not)
                     and .at[$o] < $win.at[$o] + $win.size[$o] and $win.at[$o] < .at[$o] + .size[$o]) ]
      | sort_by(.address != $win.address) | unique_by(.at[$ax])
      | sort_by(.at[$ax])
      | (map(.address) | index($win.address)) as $i
      | (if $far then $i + 1 else $i end) as $k
      # Only the dragged edge moves, to where the window is $mine long. Moving
      # an outer split rescales the windows under it, so every other boundary
      # is held where it is.
      | (if $far then $win.at[$ax] + $mine + $sp
         else $win.at[$ax] + $win.size[$ax] + 2 * $b - $mine end) as $moved
      | if $k < 1 or $k >= length then empty else
          to_entries[]
          | "\(.value.address) \(if .key == $k then $moved else .value.at[$ax] end)"
        end
    end')
[ -n "$plan" ] || exit 0
if [[ $plan == single\ * ]]; then
  read -r _ w h x y <<<"$plan"
  hyprctl dispatch "hl.dsp.window.resize({ window = \"address:$addr\", x = $w, y = $h })" >/dev/null
  hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", x = $x, y = $y })" >/dev/null
  exit 0
fi
mapfile -t addrs < <(cut -d' ' -f1 <<<"$plan")
mapfile -t targets < <(cut -d' ' -f2 <<<"$plan")

near_edge() { hyprctl clients -j | jq --arg a "$1" --argjson ax "$ax" '.[] | select(.address == $a) | .at[$ax]'; }
nudge() {
  local x=$2 y=0
  (( ax == 0 )) || { x=0 y=$2; }
  hyprctl dispatch "hl.dsp.window.resize({ window = \"address:$1\", x = $x, y = $y, relative = true })" >/dev/null
}

for _ in $(seq 8); do
  settled=true
  for ((k = 1; k < ${#addrs[@]}; k++)); do
    after=${addrs[k]} target=${targets[k]}
    off=$(( target - $(near_edge "$after") ))
    (( off > 1 || off < -1 )) || continue
    settled=false
    for mover in "${addrs[k - 1]}" "$after"; do
      nudge "$mover" "$off"
      now=$(( target - $(near_edge "$after") ))
      (( ${now#-} < ${off#-} )) && break
      nudge "$mover" $(( -off ))
    done
  done
  $settled && break
done
