#!/usr/bin/env bash
# User settings: the values a person chooses, as opposed to hardware facts,
# which are detected. Today these are the language axes: the system locale,
# the console keymap and the Hyprland keyboard layout. Each is written by
# exactly one place in this repository (tests/cases/test_axis_single_writer.sh
# holds that line), and each reads its value from here.
#
# The file lives in $XDG_CONFIG_HOME/archlinux-portfolio/settings, flat KV via
# lib/kv.sh, and is never committed. A missing file means the defaults, which
# reproduce the source workstation. An unknown key or a malformed value is an
# error: a typo in a keymap name would otherwise reach /etc/vconsole.conf.
#
# Sourced, not executed. Requires lib/kv.sh.

SETTINGS_ALLOWED_KEYS=(locale keymap xkb_layout ime theme weather_location)
declare -gA SETTINGS=()

# settings_defaults — reset SETTINGS to the values the source workstation uses.
settings_defaults() {
	SETTINGS=(
		[locale]=es_ES.UTF-8
		[keymap]=es
		[xkb_layout]=es
		[ime]=none
		[theme]=warm-night
		[weather_location]=auto
	)
}

# settings_valid KEY VALUE — 0 when VALUE is an acceptable KEY.
#   locale      a UTF-8 locale name (only those are generated), or C.UTF-8
#   keymap      a console keymap name as localectl lists them
#   xkb_layout  one or more XKB layouts, comma-separated (us,es)
#   theme       a name in the catalogue; the file has to exist, which only the
#               renderer can know, so here the shape is all that is checked
#   weather_location
#               what the bar asks wttr.in about: "auto" means by IP, which is
#               what the service does with an empty path. Anything else is a
#               place name or airport code, and is restricted to the characters
#               a place name needs so the value cannot smuggle a second URL or
#               a shell metacharacter into the module's command line.
settings_valid() {
	local key="$1" value="$2"
	case "$key" in
	locale) [[ "$value" == 'C.UTF-8' || "$value" =~ ^[a-z]{2,3}(_[A-Z]{2})?(@[a-z]+)?\.UTF-8$ ]] ;;
	keymap) [[ "$value" =~ ^[A-Za-z0-9_.-]+$ ]] ;;
	xkb_layout) [[ "$value" =~ ^[a-z]{2,8}(,[a-z]{2,8})*$ ]] ;;
	ime) [[ "$value" == none || "$value" == fcitx5 ]] ;;
	theme) [[ "$value" =~ ^[a-z][a-z0-9-]*$ ]] ;;
	weather_location) [[ "$value" =~ ^[A-Za-z0-9_.,+-]+$ ]] ;;
	*) return 1 ;;
	esac
}

# settings_load FILE — defaults, then FILE on top when it exists.
settings_load() {
	local file="$1" key allowed ok
	settings_defaults
	[[ -e "$file" ]] || return 0
	local -A __settings_read=()
	kv_load "$file" __settings_read || {
		printf 'settings: cannot read %s\n' "$file" >&2
		return 1
	}
	for key in "${!__settings_read[@]}"; do
		ok=1
		for allowed in "${SETTINGS_ALLOWED_KEYS[@]}"; do
			[[ "$key" == "$allowed" ]] && ok=0
		done
		((ok == 0)) || {
			printf 'settings: %s is not a setting this repository knows (%s)\n' "$key" "${SETTINGS_ALLOWED_KEYS[*]}" >&2
			return 1
		}
		settings_valid "$key" "${__settings_read["$key"]}" || {
			printf 'settings: %s has a malformed value: %q\n' "$key" "${__settings_read["$key"]}" >&2
			return 1
		}
		SETTINGS["$key"]="${__settings_read["$key"]}"
	done
}

# settings_get KEY — print one setting after settings_load.
settings_get() {
	[[ -v SETTINGS["$1"] ]] || {
		printf 'settings: no such setting %s\n' "$1" >&2
		return 1
	}
	printf '%s' "${SETTINGS["$1"]}"
}
