#!/usr/bin/env bash
# Software-rendered wallpaper, suitable for real hardware and virtual GPUs.
#
# The wallpaper belongs to the theme, so this reads the same setting every
# other themed file is rendered from. Only the default is committed as a PNG;
# the rest are drawn on demand from templates/wallpaper/ the first time their
# theme is chosen, which keeps eight 4K images out of the repository without
# leaving seven themes with somebody else's background.
set -Eeuo pipefail

repo="${HIPURBIA_REPO:-$HOME/hipurbia}"
wallpapers="$HOME/.local/share/wallpapers"
settings="${XDG_CONFIG_HOME:-$HOME/.config}/hipurbia/settings"

# Previewing the catalogue fires one of these per keypress. They used to run
# unserialised -- each read the setting, rendered, and started swaybg on its
# own -- so the desktop ended up wearing whichever instance FINISHED last
# rather than the theme the user actually stopped on.
#
# Take a lock, then read the setting: an instance that queued here was started
# for a theme that has since been moved past, and re-reading makes every
# waiter converge on the theme that is current now instead of fighting.
lock="${XDG_RUNTIME_DIR:-/tmp}/hipurbia-wallpaper.lock"
exec 9>"$lock"
flock 9

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

pkill -x swaybg >/dev/null 2>&1 || true
# swaybg outlives this script, so it must not inherit the lock: a waiting
# instance would block on it for the rest of the session.
exec 9>&-
exec swaybg -i "$image" -m fill
