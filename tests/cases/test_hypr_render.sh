#!/usr/bin/env bash
set -Eeuo pipefail

# The Hyprland fragments carry only what the machine has: NVIDIA environment
# on a sole-NVIDIA desktop and nowhere else, a touchpad block on laptops, a
# software cursor on VMs and NVIDIA, the monitor scale from the facts.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
renderer="$repo_root/scripts/render-config.sh"

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/hipurbia-hypr.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

render() {
	local archetype="$1" home="$sandbox/$1"
	mkdir -p -- "$home"
	HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$home/.state" \
		FACTS_FILE="$repo_root/tests/golden/$archetype/hardware-facts" FACTS_OVERRIDE="$sandbox/none" \
		bash "$renderer" --deploy >/dev/null || fail "render failed for $archetype"
	printf '%s' "$home/.config/hypr/generated"
}

count() { grep -c -- "$2" "$1" || true; }

for archetype in desktop-nvidia laptop-amd-hybrid laptop-intel vm-virtio headless-unknown; do
	out="$(render "$archetype")"
	hardware="$out/hardware.conf"
	input="$out/input.conf"
	monitors="$out/monitors.conf"

	nvidia="$(grep -ci '^env = .*nvidia' "$hardware" || true)"
	cursor="$(count "$hardware" 'no_hardware_cursors')"
	touchpad="$(count "$input" 'touchpad {')"
	case "$archetype" in
	desktop-nvidia) want_nvidia=4 want_cursor=1 want_touchpad=0 ;;
	laptop-amd-hybrid) want_nvidia=0 want_cursor=0 want_touchpad=1 ;;
	laptop-intel) want_nvidia=0 want_cursor=0 want_touchpad=1 ;;
	vm-virtio) want_nvidia=0 want_cursor=1 want_touchpad=0 ;;
	headless-unknown) want_nvidia=0 want_cursor=0 want_touchpad=0 ;;
	esac
	[[ "$nvidia" -eq "$want_nvidia" ]] || fail "$archetype: $nvidia nvidia lines, expected $want_nvidia"
	[[ "$cursor" -eq "$want_cursor" ]] || fail "$archetype: $cursor cursor lines, expected $want_cursor"
	[[ "$touchpad" -eq "$want_touchpad" ]] || fail "$archetype: $touchpad touchpad blocks, expected $want_touchpad"

	# No other vendor's configuration exists to leak; assert it stays that way.
	grep -Eiq 'amd|radeon|intel|i915' "$hardware" && fail "$archetype: another vendor's lines in hardware.conf"

	scale="$(grep -Eo 'auto, [0-9.]+$' "$monitors" | cut -d' ' -f2)"
	[[ "$scale" == "$(grep '^max_scale=' "$repo_root/tests/golden/$archetype/hardware-facts" | cut -d= -f2)" ]] || fail "$archetype: monitor scale $scale does not match the facts"

	# Guards are consumed, never rendered.
	grep -q '@?' "$hardware" "$input" "$monitors" && fail "$archetype: a guard survived rendering"
done

# The committed hyprland.conf sources exactly the three generated fragments
# and defines nothing they own.
committed="$repo_root/dotfiles/hypr/.config/hypr/hyprland.conf"
for fragment in hardware monitors input; do
	grep -Fxq "source = ~/.config/hypr/generated/$fragment.conf" "$committed" || fail "hyprland.conf does not source $fragment.conf"
done
grep -Eq '^(monitor|input|env = (LIBVA|GBM|__GLX|NVIDIA))' "$committed" && fail 'hyprland.conf still carries machine-specific configuration'

printf 'hypr: generated fragments verified on 5 archetypes\n'
