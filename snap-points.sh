#!/bin/bash
# Print the snap points that match a workspace's current window layout, as a
# `workspaces` entry for the snap-drag.lua options, e.g.
#
#   $ snap-points.sh 3
#   [3] = { widths = { "1/3", "2/3" }, heights = { "1/2" } },
#
# Usage: snap-points.sh [workspace id or name], default the active workspace.
# Each tiled window's width and height become a snap point, as the share of
# the usable screen that snap-drag.lua measures. A share within 16 px of a
# fraction with a denominator up to 12 is written as that fraction, any other
# as a number with three decimals. A size over 95% of the screen counts as the
# whole screen (that leaves room for a group bar). When every window spans the
# whole width, widths are left out, so they keep the default snap points; when
# every window spans the whole height, heights = {} turns height snapping off.
set -euo pipefail

ws=${1:-$(hyprctl activeworkspace -j | jq -r '.id')}
workspace=$(hyprctl workspaces -j | jq --arg w "$ws" '.[] | select((.id | tostring) == $w or .name == $w)')
[ -n "$workspace" ] || { echo "no such workspace: $ws" >&2; exit 1; }

mon=$(hyprctl monitors -j | jq --argjson id "$(jq '.monitorID' <<<"$workspace")" '.[] | select(.id == $id)')
border=$(hyprctl getoption general:border_size -j | jq '.int')
# css order: top right bottom left
read -r out_t out_r out_b out_l <<<"$(hyprctl getoption general:gaps_out -j | jq -r '.css')"
read -r in_t _ _ in_l <<<"$(hyprctl getoption general:gaps_in -j | jq -r '.css')"

hyprctl clients -j | jq -r --argjson ws "$workspace" --argjson m "$mon" --argjson b "$border" \
  --argjson ot "$out_t" --argjson or "$out_r" --argjson ob "$out_b" --argjson ol "$out_l" \
  --argjson it "$in_t" --argjson il "$in_l" '
  # reserved: left top right bottom
  ([$m.width, $m.height] | if $m.transform % 2 == 1 then reverse else . end | map(. / $m.scale)) as $size
  | [($size[0] - $m.reserved[0] - $m.reserved[2] - $ol - $or + 2 * $il),
     ($size[1] - $m.reserved[1] - $m.reserved[3] - $ot - $ob + 2 * $it)] as $span
  | [2 * $il, 2 * $it] as $sp
  # A share as "n/d" (the smallest d first) when a fraction up to twelfths is
  # within 16 px of it, else as a number.
  | def fraction($share; $len):
      [range(2; 13) as $d | ($share * $d | round) as $n
       | select($n > 0 and $n < $d and (($share - $n / $d) * $len | fabs) <= 16) | [$n, $d]]
      | if length > 0 then (.[0] | "\"\(.[0])/\(.[1])\"") else ($share * 1000 | round) / 1000 | tostring end;
    def points($k):
      [ .[] | (.size[$k] + 2 * $b + $sp[$k]) / $span[$k] ]
      # ponytail: a group bar takes some height off a grouped window, so a share
      # above 0.95 counts as the whole screen; read the bar height if a real
      # snap point up there is ever wanted.
      | map(select(. < 0.95)) | unique_by(. * 1000 | round)
      | map(fraction(.; $span[$k])) | unique;
  [ .[] | select(.workspace.id == $ws.id and (.floating | not) and (.hidden | not)) ]
  | unique_by(.at)
  | (if $ws.name == ($ws.id | tostring) then "[\($ws.id)]" else "[\($ws.name | tojson)]" end) as $key
  | [ (points(0) | select(length > 0) | "widths = { \(join(", ")) }"),
      (points(1) | if length > 0 then "heights = { \(join(", ")) }" else "heights = {}" end) ] as $parts
  | if $parts == ["heights = {}"] then "-- \($key): every window spans the whole screen; nothing to snap to"
    else "\($key) = { \($parts | join(", ")) }," end'
