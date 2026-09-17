#!/usr/bin/env bash
set -Eeuo pipefail

# The asset manifest gate must reject all three ways the tree and the manifest
# can disagree. Each scenario runs against a disposable copy of the real assets,
# never against the checkout itself.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
gate="$repo_root/scripts/check-asset-manifest.sh"

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/vivac-assets.XXXXXX")"
trap 'rm -rf -- "$sandbox"' EXIT

# A minimal tree with one real asset is enough: the gate's three failure modes
# are independent of how many assets are listed.
mkdir -p -- "$sandbox/assets"
fixture="$repo_root/assets/screenshots/cosmos.png"
cp -- "$fixture" "$sandbox/assets/fixture.png"
manifest="$sandbox/manifest.tsv"

run_gate() {
	ASSET_ROOT="$sandbox" ASSET_MANIFEST="$manifest" bash "$gate" "$@"
}

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}

run_gate --update >/dev/null
run_gate >/dev/null || fail 'baseline: a freshly generated manifest must verify'

# Scenario 1 — an asset exists in the tree but is not listed.
cp -- "$repo_root/dotfiles/hypr/.local/share/wallpapers/bad-romance.png" "$sandbox/assets/stray.png"
if run_gate >/dev/null 2>&1; then
	fail 'scenario 1: gate accepted a stray unlisted binary'
fi
rm -- "$sandbox/assets/stray.png"
run_gate >/dev/null || fail 'scenario 1: gate must pass again once the stray file is gone'

# Scenario 2 — a listed asset's bytes changed.
printf 'tampered\n' >>"$sandbox/assets/fixture.png"
if run_gate >/dev/null 2>&1; then
	fail 'scenario 2: gate accepted a tampered asset'
fi
run_gate --update >/dev/null
run_gate >/dev/null || fail 'scenario 2: regenerating the manifest must restore the green state'

# Scenario 3 — a listed asset disappeared from the tree.
rm -- "$sandbox/assets/fixture.png"
if run_gate >/dev/null 2>&1; then
	fail 'scenario 3: gate accepted a manifest entry with no file behind it'
fi

printf 'asset manifest gate: 3 scenarios rejected as expected\n'
