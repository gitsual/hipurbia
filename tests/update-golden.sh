#!/usr/bin/env bash
set -Eeuo pipefail

# Regenerate the golden facts file for every archetype fixture.
#
# Run this deliberately, never from the test suite: a golden that regenerates
# itself on failure asserts nothing. Any change it produces belongs in the same
# PR as the detector change that caused it, where a reviewer can see both.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

for fixture in "$repo_root"/tests/fixtures/*/; do
	archetype="$(basename -- "$fixture")"
	golden_dir="$repo_root/tests/golden/$archetype"
	mkdir -p -- "$golden_dir"
	SYSROOT="$fixture/sysroot" FACTS_FILE="$golden_dir/hardware-facts" \
		"$repo_root/scripts/hardware-facts.sh" --emit >/dev/null
	printf 'regenerated: tests/golden/%s/hardware-facts\n' "$archetype"
done

# The workspace strip golden: replay the recorded trace against the fixture
# hyprctl and render once.
ws_cache="$(mktemp)"
WS_FIXTURE="$repo_root/tests/data/ws" PATH="$repo_root/tests/data/ws/bin:$PATH" WS_CACHE="$ws_cache" \
	WS_NOTIFY=true "$repo_root/dotfiles/waybar/.config/waybar/scripts/ws-refresh.sh" --replay "$repo_root/tests/data/ws/socket2.trace"
mkdir -p -- "$repo_root/tests/data/ws/golden"
WS_CACHE="$ws_cache" WS_ICONS="$repo_root/dotfiles/waybar/.config/waybar/workspace-icons.json" \
	"$repo_root/dotfiles/waybar/.config/waybar/scripts/ws-render.sh" >"$repo_root/tests/data/ws/golden/render.json"
rm -f -- "$ws_cache"
printf 'regenerated: tests/data/ws/golden/render.json\n'
