#!/usr/bin/env bash
set -Eeuo pipefail

# The first-run wizard is the one program in the repository that a stranger
# meets before they know anything, so the parts of it that can be checked
# without a compositor are checked here: that it runs once and then stops, that
# every choice it offers is a choice the settings file will accept, and that
# the answers it writes are readable by the loader that has to read them.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
wizard="$repo_root/dotfiles/welcome/.local/bin/portfolio-welcome"
hypr="$repo_root/templates/hypr/.config/hypr/hyprland.conf.in"
# shellcheck source=lib/kv.sh
source "$repo_root/lib/kv.sh"
# shellcheck source=lib/settings.sh
source "$repo_root/lib/settings.sh"

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}
[[ -x "$wizard" ]] || fail 'the wizard is missing or not executable'

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/archportfolio-welcome.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

# Once, and then never again without being asked. A wizard that reappears every
# login is not a welcome, it is an obstacle.
state="$sandbox/state/archlinux-portfolio"
mkdir -p -- "$state"
printf 'welcome completed\n' >"$state/welcome-done"
output="$(HOME="$sandbox" XDG_STATE_HOME="$sandbox/state" PORTFOLIO_REPO="$repo_root" \
	"$wizard" --first-run 2>&1)" || fail "--first-run failed with a marker present: $output"
[[ -z "$output" ]] || fail "--first-run spoke when it should have stayed silent: $output"

# Every keyboard it offers has to survive the settings validator, on both axes
# it writes. An entry that cannot be saved is a dead end dressed as a choice.
mapfile -t offered < <(sed -nE 's/^layouts=\((.*)\)$/\1/p' "$wizard" | tr ' ' '\n' | grep .)
((${#offered[@]} >= 4)) || fail 'the wizard offers almost no keyboards'
for layout in "${offered[@]}"; do
	settings_valid xkb_layout "$layout" || fail "the wizard offers xkb_layout=$layout, which settings refuse"
	settings_valid keymap "$layout" || fail "the wizard offers keymap=$layout, which settings refuse"
	grep -q "^	\[$layout\]=" "$wizard" || fail "the keyboard $layout is offered with no label to read"
done

# The theme list is read from the catalogue, never copied into the wizard: a
# second list is a second thing to forget to update.
grep -qE '^themes=\(warm-night\)$' "$wizard" ||
	fail 'the wizard seeds its theme list with something other than the default alone'
grep -Fq 'data/themes' "$wizard" || fail 'the wizard does not read the catalogue'

# What it writes has to be what the loader reads, including when the key was
# already there: the second answer replaces the first rather than joining it.
settings_file="$sandbox/.config/archlinux-portfolio/settings"
mkdir -p -- "$(dirname -- "$settings_file")"
printf 'theme=warm-night\nxkb_layout=us\n' >"$settings_file"
HOME="$sandbox" XDG_CONFIG_HOME="$sandbox/.config" PORTFOLIO_REPO="$repo_root" \
	bash -c 'source "$0"; settings_file="$1"; setting_write xkb_layout fr; setting_write theme cold-slate' \
	<(sed -n '/^setting_write()/,/^}/p' "$wizard") "$settings_file" ||
	fail 'setting_write failed on an existing file'
(($(grep -c '^xkb_layout=' "$settings_file") == 1)) || fail 'setting_write duplicated a key'
settings_load "$settings_file" || fail 'the loader cannot read what the wizard wrote'
[[ "${SETTINGS[xkb_layout]}" == fr ]] || fail "the loader read xkb_layout=${SETTINGS[xkb_layout]}, not fr"
[[ "${SETTINGS[theme]}" == cold-slate ]] || fail "the loader read theme=${SETTINGS[theme]}, not cold-slate"

# Started exactly once by the session, with the flag that makes it a no-op the
# second time, and floated so it is not tiled behind the bar on first sight.
(($(grep -c 'portfolio-welcome --first-run' "$hypr") == 1)) ||
	fail 'the session does not start the wizard exactly once'
grep -Fq 'windowrule = float on, match:class ^(portfolio-welcome)$' "$hypr" ||
	fail 'the wizard would be tiled like an ordinary window'
grep -Fq 'welcome' "$repo_root/scripts/deploy.sh" || fail 'the wizard is never deployed'

# The background is part of the theme, not a constant: the session's wallpaper
# script reads the same setting, and draws the image when the chosen theme has
# none yet. Only the default ships as a committed PNG.
paper="$repo_root/dotfiles/hypr/.config/hypr/scripts/wallpaper.sh"
grep -Fq 'archlinux-portfolio/settings' "$paper" || fail 'the wallpaper ignores the chosen theme'
grep -Fq 'make-wallpaper.sh' "$paper" || fail 'a theme without a committed image would have no wallpaper'
grep -Fq 'warm-night.png' "$paper" || fail 'the wallpaper has no fallback when nothing can be drawn'
grep -Fq 'pkill -x swaybg' "$wizard" || fail 'the theme preview cannot replace the running wallpaper'

printf 'welcome: silent once taken, %d keyboards the settings accept, answers the loader reads\n' \
	"${#offered[@]}"
