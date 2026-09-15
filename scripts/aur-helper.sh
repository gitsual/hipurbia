#!/usr/bin/env bash
set -Eeuo pipefail

# Make sure an AUR helper exists, and print its name.
#
# The AUR is not a repository: it is a collection of build recipes, and using
# it means compiling on the machine. That is a real decision, so it is made in
# one place rather than assumed by every caller. If paru or yay is already
# installed nothing is built at all; otherwise paru-bin is fetched from the
# AUR and built with makepkg, which is the only bootstrap that does not need an
# AUR helper to install an AUR helper. paru-bin ships a compiled binary, so
# this costs a download rather than a Rust toolchain.
#
#   --ensure    build a helper when none is present (default: only report)
#
# Prints the helper's name on stdout, or exits 1 with the reason.

ensure=false
[[ "${1:-}" == --ensure ]] && ensure=true

for helper in paru yay; do
	if command -v "$helper" >/dev/null; then
		printf '%s\n' "$helper"
		exit 0
	fi
done

$ensure || {
	printf 'No AUR helper (paru or yay) is installed.\n' >&2
	exit 1
}

for required in git makepkg; do
	command -v "$required" >/dev/null || {
		printf 'Cannot build an AUR helper without %s; install base-devel and git.\n' "$required" >&2
		exit 1
	}
done
# makepkg refuses to run as root, and installing the result needs root, so it
# asks for it itself — this must therefore run as the user who will own the
# packages, never under sudo.
[[ "$(id -u)" -ne 0 ]] || {
	printf 'Run this as the unprivileged user; makepkg refuses to build as root.\n' >&2
	exit 1
}

work="$(mktemp -d "${TMPDIR:-/tmp}/archportfolio-aur.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT
git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$work/paru-bin" >&2
(cd "$work/paru-bin" && makepkg -si --noconfirm) >&2
command -v paru >/dev/null || {
	printf 'paru-bin built but paru is not on PATH.\n' >&2
	exit 1
}
printf 'paru\n'
