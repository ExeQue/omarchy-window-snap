#!/bin/bash
# Link the skills in skills/ into the skill folders of the AI agents on
# this machine. Every skill is a plain SKILL.md (the Agent Skills format), so
# the same file works in each of them.
#
# ~/.agents/skills is the shared folder that Codex, OpenCode, pi and others
# read; it is always set up. An agent with its own folder gets a link there
# too, when that agent is installed (its config folder exists).
# Run it again after adding a skill; existing links are kept.
set -euo pipefail

here=$(cd "$(dirname "$0")/skills" && pwd)
targets=("$HOME/.agents/skills")
for agent in \
  "$HOME/.claude:skills" \
  "$HOME/.codex:skills" \
  "$HOME/.pi:agent/skills" \
  "$HOME/.copilot:skills" \
  "$HOME/.gemini:skills" \
  "${XDG_CONFIG_HOME:-$HOME/.config}/opencode:skills"; do
  root=${agent%%:*}
  [ -d "$root" ] && targets+=("$root/${agent#*:}")
done

for skill in "$here"/*/; do
  name=$(basename "$skill")
  [ -f "$skill/SKILL.md" ] || continue
  for dir in "${targets[@]}"; do
    mkdir -p "$dir"
    if [ -e "$dir/$name" ] && [ ! -L "$dir/$name" ]; then
      echo "skipped $dir/$name: something else is there" >&2
      continue
    fi
    ln -sfn "${skill%/}" "$dir/$name"
    echo "linked $dir/$name"
  done
done
