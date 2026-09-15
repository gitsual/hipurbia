#!/usr/bin/env bash
set -Eeuo pipefail

# Workspaces are numbered 1 to 10, bound to the digit keys with 0 as 10, in
# numeric order, with a wraparound pair and no special workspace in the
# sequence. Waybar shows every one of the ten by its number on every output,
# and the stylesheet tells active, urgent and empty apart.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
template="$repo_root/templates/hypr/.config/hypr/hyprland.conf.in"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/archportfolio-ws.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

# --- binds: 1..9 then 0 -> 10, in that order, for both switch and move ------------------------
for dispatcher in workspace movetoworkspace; do
	mapfile -t targets < <(grep -E "^bind = SUPER( SHIFT)?, [0-9], $dispatcher, [0-9]+$" "$template" | awk -F', ' '{print $4}')
	[[ "${targets[*]}" == '1 2 3 4 5 6 7 8 9 10' ]] || fail "$dispatcher binds are not 1..10 in order: ${targets[*]}"
	[[ "$(grep -E "^bind = SUPER( SHIFT)?, 0, $dispatcher, " "$template" | awk -F', ' '{print $4}')" == 10 ]] || fail "$dispatcher: 0 does not map to 10"
done
grep -Eq '^bind = SUPER, bracketright, workspace, e\+1$' "$template" || fail 'no wraparound forward bind'
grep -Eq '^bind = SUPER, bracketleft, workspace, e-1$' "$template" || fail 'no wraparound backward bind'
grep -E '^bind = SUPER( SHIFT)?, [0-9], (move)?(to)?workspace, special' "$template" && fail 'a digit key targets a special workspace'

# --- Waybar: ten numbered, persistent buttons on every output, on 1 and 2 monitors alike ------
for archetype in vm-virtio laptop-amd-hybrid; do
	home="$sandbox/$archetype"
	mkdir -p -- "$home"
	HOME="$home" XDG_CONFIG_HOME="$home/.config" XDG_STATE_HOME="$sandbox/state-$archetype" \
		FACTS_FILE="$repo_root/tests/golden/$archetype/hardware-facts" FACTS_OVERRIDE="$sandbox/none" \
		bash "$repo_root/scripts/render-config.sh" --deploy >/dev/null || fail "$archetype: render failed"
	python3 - "$home/.config/waybar/config" "$archetype" <<'PY' || exit 1
import json, sys
config = json.load(open(sys.argv[1]))
ws = config["hyprland/workspaces"]
problems = []
if ws.get("format") != "{id}": problems.append("format is not the workspace number")
if ws.get("persistent-workspaces") != {"*": 10}: problems.append("not ten persistent workspaces on every output")
if ws.get("sort-by") != "number": problems.append("not sorted by number")
if ws.get("all-outputs") is not True: problems.append("a second monitor would hide workspaces of the first")
if "format-icons" in ws: problems.append("icons would replace the numbers")
if problems:
    print(sys.argv[2] + ": " + "; ".join(problems), file=sys.stderr); sys.exit(1)
PY
done

# --- the stylesheet distinguishes the three states ---------------------------------------------------
css="$repo_root/dotfiles/waybar/.config/waybar/style.css"
for state in active urgent empty; do
	grep -q "^#workspaces button\.$state " "$css" || fail "no style for a $state workspace"
done
active="$(grep '^#workspaces button\.active ' "$css")"
urgent="$(grep '^#workspaces button\.urgent ' "$css")"
[[ "$active" != "$urgent" ]] || fail 'active and urgent look the same'

printf 'workspace numbering: 1..10 with 0 as 10, wraparound, ten numbered buttons on 1 and 2 monitors\n'
