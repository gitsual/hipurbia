#!/usr/bin/env bash
set -Eeuo pipefail

# The ricing tools are one selector with one manifest, all from the official
# repositories: packages/aur.txt stays empty, wlogout is never installed or
# referenced, nwg-bar sits beside the rofi power menu rather than replacing
# it, its stylesheet is rendered from the palette, and hypridle's config
# carries the three stages.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
template="$repo_root/templates/hypr/.config/hypr/hyprland.conf.in"

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}
grep -Eq '^[^#[:space:]]' "$repo_root/packages/aur.txt" && fail 'packages/aur.txt is not empty'
grep -rIl --exclude-dir=.git --exclude-dir=.vm-test --exclude-dir=tests --exclude=README.md 'wlogout' "$repo_root" && fail 'wlogout is referenced'
LC_ALL=C sort -cu "$repo_root/packages/ricer.txt" || fail 'packages/ricer.txt is not sorted unique'
for package in cliphist nwg-bar nwg-look qt6ct kvantum swappy wf-recorder; do
	grep -Fxq -- "$package" "$repo_root/packages/ricer.txt" || fail "$package missing from the ricer manifest"
done
grep -Fxq hypridle "$repo_root/packages/pacman.txt" || fail 'hypridle is not in the base manifest'

# --- beside, not instead: both power menus are bound, the rofi one to its own script -------------------
# shellcheck disable=SC2016  # the literal $HOME is what the template says
grep -Fxq 'bind = SUPER SHIFT, E, exec, $HOME/.config/rofi/power/powermenu.sh' "$template" || fail 'the rofi power menu bind changed'
grep -Fxq 'bind = SUPER SHIFT, Q, exec, nwg-bar' "$template" || fail 'nwg-bar is not bound'
grep -q 'Power off' "$repo_root/dotfiles/rofi/.config/rofi/power/powermenu.sh" || fail 'the rofi power menu lost an entry'
python3 -c '
import json, sys
bar = json.load(open(sys.argv[1]))
labels = [b["label"] for b in bar]
assert labels == ["Lock", "Suspend", "Log out", "Reboot", "Power off"], labels
assert all(b["exec"] for b in bar)' "$repo_root/dotfiles/ricer/.config/nwg-bar/bar.json" || fail 'nwg-bar entries differ from the rofi menu'
[[ -f "$repo_root/templates/ricer/.config/nwg-bar/style.css.in" ]] || fail 'the nwg-bar stylesheet is not a palette template'
grep -Eq '#[0-9A-F]{6}' "$repo_root/dotfiles/ricer/.config/nwg-bar/style.css" || fail 'the rendered nwg-bar stylesheet carries no colour'

# --- hypridle: started with the session, three stages in order ----------------------------------------------
grep -Fxq 'exec-once = hypridle' "$template" || fail 'hypridle is not started with the session'
mapfile -t timeouts < <(awk '/^[[:space:]]*timeout =/ { print $3 }' "$repo_root/dotfiles/hypr/.config/hypr/hypridle.conf")
[[ "${timeouts[*]}" == '300 600 1800' ]] || fail "hypridle stages are not lock, screen off, suspend in order: ${timeouts[*]}"
grep -q 'lock_cmd' "$repo_root/dotfiles/hypr/.config/hypr/hypridle.conf" || fail 'hypridle has no lock command'

# --- the selector adds exactly its manifest ---------------------------------------------------------------------
listing() {
	SYSROOT="$repo_root/tests/fixtures/laptop-intel/sysroot" LSPCI_CMD=false PACMAN_CMD=false \
		bash "$repo_root/scripts/bootstrap.sh" --dry-run "$@" 2>/dev/null | grep '^would install official packages' || true
}
base="$(listing)"
with="$(listing --ricer)"
extra="$(comm -13 <(tr ' ' '\n' <<<"${base#*: }" | LC_ALL=C sort) <(tr ' ' '\n' <<<"${with#*: }" | LC_ALL=C sort))"
[[ "$extra" == "$(<"$repo_root/packages/ricer.txt")" ]] || fail "--ricer added something outside its manifest: $extra"
grep -Eq 'nwg-bar|cliphist' <<<"$base" && fail 'the default bootstrap installs ricing tools'

printf 'ricer: official repos only, no wlogout, nwg-bar beside rofi, hypridle staged, selector adds its manifest\n'
