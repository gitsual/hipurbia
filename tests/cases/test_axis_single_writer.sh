#!/usr/bin/env bash
set -Eeuo pipefail

# Each language axis is written by exactly one place. The markers are the
# strings that only a writer would carry; verification scripts read the
# results and are scanned separately for writes they must not make.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
cd "$repo_root"

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

writers() {
	find scripts lib render templates dotfiles system -type f \
		! -name 'test-*.sh' ! -name 'open-tested-vm.sh' ! -name 'vm-*.sh' -print0 |
		xargs -0 grep -lE -- "$1" | LC_ALL=C sort || true
}

expect_one() {
	local marker="$1" writer="$2" found
	found="$(writers "$marker")"
	[[ "$found" == "$writer" ]] || fail "axis marker '$marker' is written by [$(tr '\n' ' ' <<<"$found")], expected exactly $writer"
}

expect_one '(^|[^A-Z_])LANG=' scripts/apply-system.sh
expect_one 'locale-gen' scripts/apply-system.sh
expect_one '(^|[^A-Z_])KEYMAP=' scripts/apply-system.sh
expect_one '(^|[^x])kb_layout' render/hypr/generated/input.conf.in

# The greeter's own layout axis arrives with the GUI greeter unit; until then
# nothing may write it.
found="$(writers 'XKB_DEFAULT_LAYOUT')"
[[ -z "$found" ]] || fail "XKB_DEFAULT_LAYOUT has a writer before the greeter unit: $found"

# Verification and interactive scripts may read an axis, never set one.
if grep -lE 'localectl set-|locale-gen|tee .*(locale|vconsole)' scripts/test-*.sh scripts/open-tested-vm.sh scripts/vm-*.sh 2>/dev/null | grep .; then
	fail 'a verification script writes a language axis'
fi

printf 'axis single writer: LANG, locale-gen, KEYMAP -> apply-system.sh; kb_layout -> input.conf.in\n'
