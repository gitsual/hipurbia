#!/usr/bin/env bash
# Software-rendered wallpaper, suitable for real hardware and virtual GPUs.
#
# The wallpaper belongs to the theme, so this reads the same setting every
# other themed file is rendered from. Only the default is committed as a PNG;
# the rest are drawn on demand from templates/wallpaper/ the first time their
# theme is chosen, which keeps eight 4K images out of the repository without
# leaving seven themes with somebody else's background.
set -Eeuo pipefail

repo="${PORTFOLIO_REPO:-$HOME/archlinux-portfolio}"
wallpapers="$HOME/.local/share/wallpapers"
settings="${XDG_CONFIG_HOME:-$HOME/.config}/archlinux-portfolio/settings"

theme=warm-night
[[ -f "$settings" ]] && theme="$(sed -nE 's/^theme=(.+)$/\1/p' "$settings" | tail -1)"
[[ -n "$theme" ]] || theme=warm-night

image="$wallpapers/$theme.png"
if [[ ! -f "$image" && -x "$repo/scripts/make-wallpaper.sh" ]]; then
	"$repo/scripts/make-wallpaper.sh" --theme "$theme" --out "$wallpapers" >/dev/null 2>&1 || true
fi
# A theme with no drawing of its own is still a usable desktop; a missing file
# handed to swaybg is not.
[[ -f "$image" ]] || image="$wallpapers/warm-night.png"

exec swaybg -i "$image" -m fill
