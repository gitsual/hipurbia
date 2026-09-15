#!/usr/bin/env bash
set -Eeuo pipefail

# Picking a theme has to change the room.
#
# The palette-dependent stylesheets are committed renders of the DEFAULT
# palette, symlinked into place by Stow. That makes choosing another theme a
# trap: the setting changes, the files on disk do not, and the desktop looks
# exactly as it did. So the overlay is asserted here in both directions — that
# a chosen palette really lands in every stylesheet, and that going back to the
# default restores the Stow symlink byte for byte rather than leaving a stale
# copy of somebody else's colours behind.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
apply="$repo_root/scripts/apply-theme.sh"
facts="$repo_root/tests/golden/vm-virtio/hardware-facts"

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}
[[ -x "$apply" ]] || fail 'scripts/apply-theme.sh is missing or not executable'
command -v stow >/dev/null || {
	printf 'apply-theme: skipped, stow is not installed\n'
	exit 0
}

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/archportfolio-theme.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT
mkdir -p -- "$sandbox/.config"

# Every package that carries a palette-dependent template, laid out the way a
# real session lays it out.
mapfile -t packages < <(find "$repo_root/templates" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' |
	grep -vx -e wallpaper -e system | LC_ALL=C sort)
stow --dir="$repo_root/dotfiles" --target="$sandbox" --no-folding "${packages[@]}"

run() {
	HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" XDG_STATE_HOME="$sandbox/.state" \
		FACTS_FILE="$facts" FACTS_OVERRIDE="$sandbox/absent" \
		SETTINGS_FILE="$sandbox/.config/archlinux-portfolio/settings" \
		"$apply" "$@"
}

# The paths the overlay owns, and what they pointed at before anyone touched
# them. Restoring has to reproduce this map exactly.
declare -A before=()
while IFS= read -r template; do
	rest="${template#"$repo_root/templates/"}"
	rest="${rest#*/}"
	[[ "$rest" == .* ]] || continue
	target="$sandbox/${rest%.in}"
	[[ -L "$target" ]] || fail "$rest is not stowed as a symlink; the test cannot tell restoration from luck"
	before["$target"]="$(readlink -- "$target")"
done < <(find "$repo_root/templates" -type f -name '*.in' | LC_ALL=C sort)
((${#before[@]} >= 5)) || fail 'almost nothing in this desktop depends on the palette; the test is not testing'

# A name that is not in the catalogue is refused by name, before anything on
# disk moves.
run --theme not-a-theme --no-reload >/dev/null 2>&1 && fail 'an unknown theme was accepted'
for target in "${!before[@]}"; do
	[[ -L "$target" ]] || fail "a refused theme still replaced $target"
done

# Applying a real one: every palette-dependent file becomes a real file, and
# holds a colour from the palette that was asked for rather than the default's.
run --theme ember-forge --no-reload >/dev/null
# Told apart by their BACKGROUND, not their accent: an accent is the canonical
# hex of an aesthetic in data/aesthetics.tsv, so two themes rooted in the same
# aesthetic share one on purpose and would make this assertion pass by accident.
background="$(sed -nE 's/^COLOR_BG=(.*)$/\1/p' "$repo_root/data/themes/ember-forge.conf")"
default_background="$(sed -nE 's/^COLOR_BG=(.*)$/\1/p' "$repo_root/data/theme.conf")"
[[ -n "$background" && "$background" != "$default_background" ]] || fail 'the fixture theme is indistinguishable from the default'
carried=0
for target in "${!before[@]}"; do
	[[ -L "$target" ]] && fail "$target is still a symlink: the chosen palette never reached it"
	grep -qiF "$background" "$target" && carried=$((carried + 1))
done
((carried >= 3)) || fail "the chosen background reached only $carried files"

# Switching again must not accumulate: the previous overlay is undone first, so
# no file is left holding the palette before last.
run --theme cold-slate --no-reload >/dev/null
for target in "${!before[@]}"; do
	grep -qiF "$background" "$target" && fail "$target still carries the previous theme's background"
done

# And back to the default: every symlink returns, pointing exactly where it
# pointed, and the overlay record is gone rather than merely emptied.
run --theme warm-night --no-reload >/dev/null
for target in "${!before[@]}"; do
	[[ -L "$target" ]] || fail "$target did not go back to being a Stow symlink"
	[[ "$(readlink -- "$target")" == "${before[$target]}" ]] ||
		fail "$target was restored to the wrong place"
done
[[ -e "$sandbox/.state/archlinux-portfolio/theme-overlay" ]] &&
	fail 'the default still records an overlay it does not have'

# Nothing outside the home directory is ever written: the greeter's stylesheet
# lives in /etc and belongs to apply-system.sh, which asks for root first.
grep -Fq 'etc/greetd' "$sandbox/.state/archlinux-portfolio/theme-overlay" 2>/dev/null &&
	fail 'the overlay reaches outside the home directory'

printf 'apply-theme: %d palette-dependent files overlaid and restored exactly\n' "${#before[@]}"
