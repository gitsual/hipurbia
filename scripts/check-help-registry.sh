#!/usr/bin/env bash
# Bind and registry parity for the help panes.
#
# Every bind in the Hyprland template carries a "# @help: <pane> <label_key>"
# line right above it, that key exists in the English table, and the registry
# has the row (pane, bind id) with the same key. Every hypr row in the
# registry is such a bind. Every doc row points at a file under docs/. A key
# added to the desktop without its help line, or a help line that describes
# a key that is gone, fails here rather than in a user's F1.
set -Eeuo pipefail

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)}"
# shellcheck source=lib/kv.sh
source "$repo_root/lib/kv.sh"
# shellcheck source=lib/i18n.sh
source "$repo_root/lib/i18n.sh"
# shellcheck source=lib/help.sh
source "$repo_root/lib/help.sh"

template="${HELP_TEMPLATE:-$repo_root/templates/hypr/.config/hypr/hyprland.conf.in}"
registry="${HELP_REGISTRY:-$repo_root/data/help-registry.tsv}"
status=0
problem() {
	printf 'help registry: %s\n' "$1" >&2
	status=1
}

i18n_load en "$repo_root/i18n"
help_load_registry "$registry"

declare -A seen=()
previous=''
lineno=0
while IFS= read -r line || [[ -n "$line" ]]; do
	lineno=$((lineno + 1))
	if [[ "$line" =~ ^bind[lmer]*\ =\ ([^,]*),\ ([^,]+), ]]; then
		mods="${BASH_REMATCH[1]}"
		key="${BASH_REMATCH[2]}"
		id="$(help_bind_id "$mods" "${key// /}")"
		if [[ "$previous" =~ ^#\ @help:\ ([a-z]+)\ ([a-z0-9_.]+)$ ]]; then
			pane="${BASH_REMATCH[1]}"
			label="${BASH_REMATCH[2]}"
			[[ -v I18N_TEXT["$label"] ]] || problem "line $lineno: label $label is not in i18n/en.conf"
			if [[ -v HELP_LABEL["$pane/$id"] ]]; then
				[[ "${HELP_LABEL["$pane/$id"]}" == "$label" ]] || problem "line $lineno: registry says $pane/$id is ${HELP_LABEL["$pane/$id"]}, the annotation says $label"
			else
				problem "line $lineno: bind $id has no registry row in pane $pane"
			fi
			seen["$pane/$id"]=1
		else
			problem "line $lineno: bind $id has no '# @help: <pane> <label_key>' line above it"
		fi
	fi
	previous="$line"
done <"$template"

for row in "${HELP_ROWS[@]}"; do
	[[ -v I18N_TEXT["${HELP_LABEL["$row"]}"] ]] || problem "$row: label ${HELP_LABEL["$row"]} is not in i18n/en.conf"
	case "${HELP_TYPE["$row"]}" in
	doc)
		path="${HELP_VALUE["$row"]%%#*}"
		[[ "$path" == docs/* && -f "$repo_root/$path" ]] || problem "$row: doc value $path is not a file under docs/"
		;;
	exec | dispatch)
		[[ "${HELP_PANE["$row"]}" == hypr ]] || problem "$row: ${HELP_TYPE["$row"]} actions belong to the hypr pane"
		[[ -v seen["$row"] ]] || problem "$row: the registry describes a Hyprland key the template does not bind"
		;;
	esac
done

((status == 0)) && printf 'help registry: %d rows, every Hyprland bind annotated and registered\n' "${#HELP_ROWS[@]}"
exit "$status"
