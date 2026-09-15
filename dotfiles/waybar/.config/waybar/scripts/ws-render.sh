#!/usr/bin/env bash
# Print the Waybar custom/ws module from the workspace cache.
#
# Every one of the ten workspaces is a button carrying its number; an
# occupied one adds one glyph per window, an empty one shows the number
# alone. The active workspace is bold and underlined, an urgent one bold
# and italic, so the two never rely on colour alone. Nothing a window
# controls (class, title) reaches the markup: glyphs come from the catalogue
# and titles go to the tooltip HTML-escaped.
#
# Reads: WS_CACHE (default $XDG_RUNTIME_DIR/waybar-ws.json, written by
# ws-refresh.sh), WS_ICONS (default ~/.config/waybar/workspace-icons.json).
set -Eeuo pipefail

cache="${WS_CACHE:-${XDG_RUNTIME_DIR:-/tmp}/waybar-ws.json}"
icons="${WS_ICONS:-${XDG_CONFIG_HOME:-$HOME/.config}/waybar/workspace-icons.json}"

if [[ ! -r "$cache" ]]; then
	# Before the first event the strip is ten empty numbers, never blank.
	printf '{"text": "%s", "tooltip": "no workspace state yet", "class": "ws"}\n' "$(printf '%s  ' 1 2 3 4 5 6 7 8 9 10 | sed 's/  $//')"
	exit 0
fi

jq -c --slurpfile catalogue "$icons" '
	$catalogue[0] as $cat
	| def by_prefix($table; $name):
		[ $table | to_entries[] | .key as $k | select(($name | type) == "string" and ($name | startswith($k))) ]
		| sort_by(-(.key | length)) | .[0].value;
	def lookup($name):
		if ($name | type) != "string" or $name == "" then null
		else ($cat.classes[$name] // by_prefix($cat.prefixes; $name)) end;
	def by_title($title):
		if ($title | type) != "string" then null
		else ([ $cat.titles | to_entries[] | .key as $k | select($title | contains($k)) ] | .[0].value) end;
	def icon_for($w):
		lookup($w.initialClass) // lookup($w.class) // by_title($w.title) // $cat.default;
	. as $state
	| [ range(1; 11) as $n
		| ([ $state.workspaces[]? | select(.id == $n) ] | .[0]) as $w
		| ($w.windows // []) as $windows
		| (($n | tostring) + (if ($windows | length) > 0 then " " + ([ $windows[] | icon_for(.) ] | join(" ")) else "" end)) as $label
		| if $n == $state.active then "<span weight=\"bold\" underline=\"single\">" + $label + "</span>"
		  elif ($w.urgent // false) then "<span weight=\"bold\" style=\"italic\">" + $label + "</span>"
		  else $label end
	  ] as $buttons
	| {
		text: ($buttons | join("  ")),
		tooltip: ([ $state.workspaces[]? | select(.id >= 1 and .id <= 10) | select((.windows | length) > 0)
			| (.id | tostring) + ": " + ([ .windows[] | (.title // "") | @html ] | join(", ")) ] | join("\n")),
		class: (if ([ $state.workspaces[]? | select(.urgent // false) ] | length) > 0 then "ws urgent" else "ws" end)
	  }' "$cache"
