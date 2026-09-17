#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/vivac-deploy.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

test_home="$sandbox/home"
state_home="$sandbox/state"
# The conflict fixture is a stowed file. The Waybar config is not one any more
# (it is rendered per machine), so kitty.conf stands in for "a file the user
# already had".
mkdir -p -- "$test_home/.config/kitty" "$state_home"
printf '%s\n' 'pre-existing user configuration' >"$test_home/.config/kitty/kitty.conf"

hash_sources() {
	(
		cd "$repo_root"
		find dotfiles -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum
	)
}

hash_sources >"$sandbox/sources.before"
HOME="$test_home" XDG_STATE_HOME="$state_home" "$repo_root/scripts/deploy.sh" --all
hash_sources >"$sandbox/sources.after-first"
cmp "$sandbox/sources.before" "$sandbox/sources.after-first"

mapfile -t backups < <(compgen -G "$state_home/vivac/backups/*/.config/kitty/kitty.conf" || true)
[[ ${#backups[@]} -eq 1 ]]
grep -Fxq 'pre-existing user configuration' "${backups[0]}"
[[ "$(readlink -f -- "$test_home/.config/kitty/kitty.conf")" == "$repo_root/dotfiles/kitty/.config/kitty/kitty.conf" ]]

HOME="$test_home" XDG_STATE_HOME="$state_home" "$repo_root/scripts/deploy.sh" --all
hash_sources >"$sandbox/sources.after-second"
cmp "$sandbox/sources.before" "$sandbox/sources.after-second"
mapfile -t backups_after < <(compgen -G "$state_home/vivac/backups/*/.config/kitty/kitty.conf" || true)
[[ ${#backups_after[@]} -eq 1 ]]

printf 'deployment regression: passed (%d source files preserved, 1 conflict backed up)\n' "$(wc -l <"$sandbox/sources.before")"
