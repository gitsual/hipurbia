#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
packages=(hypr waybar kitty dunst rofi wofi nvim shell theme audio security automation ricer)
dry_run=false

usage() {
	cat <<'USAGE'
Usage: scripts/deploy.sh [--all] [--dry-run] [package ...]

Packages: hypr waybar kitty dunst rofi wofi nvim shell theme audio security automation
Existing files are moved to a timestamped backup; nothing is deleted.
USAGE
}

selected=()
while (($#)); do
	case "$1" in
	--all) selected=("${packages[@]}") ;;
	--dry-run) dry_run=true ;;
	-h | --help)
		usage
		exit 0
		;;
	--*)
		printf 'Unknown option: %s\n' "$1" >&2
		usage >&2
		exit 2
		;;
	*) selected+=("$1") ;;
	esac
	shift
done
((${#selected[@]})) || selected=("${packages[@]}")

command -v stow >/dev/null || {
	printf 'GNU Stow is required. Run scripts/bootstrap.sh first.\n' >&2
	exit 1
}

for package in "${selected[@]}"; do
	[[ " ${packages[*]} " == *" $package "* ]] || {
		printf 'Unknown package: %s\n' "$package" >&2
		exit 2
	}
done

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/archlinux-portfolio/backups/$stamp"

for package in "${selected[@]}"; do
	package_root="$repo_root/dotfiles/$package"
	while IFS= read -r -d '' source; do
		relative="${source#"$package_root"/}"
		target="$HOME/$relative"
		# Stow may link an entire parent directory. Compare canonical file
		# paths even when the final component is not itself a symlink; this
		# prevents a second run from moving files out of the repository.
		if [[ -e "$target" && "$(readlink -f -- "$target")" == "$(readlink -f -- "$source")" ]]; then
			continue
		fi
		if [[ -e "$target" || -L "$target" ]]; then
			destination="$backup_root/$relative"
			if $dry_run; then
				printf 'would back up %s -> %s\n' "$target" "$destination"
			else
				mkdir -p -- "$(dirname -- "$destination")"
				mv -- "$target" "$destination"
				printf 'backed up %s -> %s\n' "$target" "$destination"
			fi
		fi
	done < <(find "$package_root" -type f -print0)

done

if $dry_run; then
	printf 'would stow: %s\n' "${selected[*]}"
	exit 0
fi

stow --dir="$repo_root/dotfiles" --target="$HOME" --no-folding --restow "${selected[@]}"
printf 'deployed: %s\n' "${selected[*]}"
if [[ -d "$backup_root" ]]; then
	printf 'backup: %s\n' "$backup_root"
fi
