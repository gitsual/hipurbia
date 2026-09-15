#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/hipurbia-nvim.XXXXXX")"
keep=false
[[ "${KEEP_TEST_SANDBOX:-0}" == 1 ]] && keep=true
cleanup() {
	if $keep; then
		printf 'Neovim test sandbox kept at %s\n' "$sandbox"
	else
		rm -rf -- "$sandbox"
	fi
}
trap cleanup EXIT

config_home="$sandbox/config"
data_home="$sandbox/data"
state_home="$sandbox/state"
cache_home="$sandbox/cache"
mkdir -p -- "$config_home" "$data_home" "$state_home" "$cache_home"
cp -a -- "$repo_root/dotfiles/nvim/.config/nvim" "$config_home/nvim"
source_lock="$repo_root/dotfiles/nvim/.config/nvim/lazy-lock.json"
source_lock_hash="$(sha256sum "$source_lock" | cut -d' ' -f1)"

run_nvim() {
	HOME="$sandbox/home" \
	XDG_CONFIG_HOME="$config_home" \
	XDG_DATA_HOME="$data_home" \
	XDG_STATE_HOME="$state_home" \
	XDG_CACHE_HOME="$cache_home" \
	AVANTE_PROVIDER=codexcli \
	nvim --headless "$@"
}

sync_log="$sandbox/lazy-sync.log"
startup_log="$sandbox/startup.log"
error_pattern='(^|[^[:alpha:]])(error|failed|fatal|E[0-9]{3}:)|HTTP 504|codeberg\.org'
sync_ok=false
sync_attempt=0
for sync_attempt in 1 2 3; do
	if run_nvim '+Lazy! sync' +qa! >"$sync_log" 2>&1 && ! grep -Eiq "$error_pattern" "$sync_log"; then
		sync_ok=true
		break
	fi
	mv -- "$sync_log" "$sandbox/lazy-sync.attempt-$sync_attempt.log"
	sleep "$((sync_attempt * 5))"
done
if ! $sync_ok; then
	printf '%s\n' 'Neovim sync failed after 3 bounded attempts:' >&2
	grep -Ein "$error_pattern" "$sandbox"/lazy-sync.attempt-*.log >&2 || true
	exit 1
fi

run_nvim \
	-c 'lua local function loaded(name) local ok, value = pcall(require, name); assert(ok, value) end; loaded("nvchad"); loaded("nvim-treesitter.configs"); loaded("avante"); loaded("cmp"); local plugin = require("lazy.core.config").plugins["cmp-async-path"]; assert(plugin and vim.uv.fs_stat(plugin.dir), "cmp-async-path is not installed")' \
	-c 'qa!' >"$startup_log" 2>&1

if grep -Eiq "$error_pattern" "$sync_log" "$startup_log"; then
	printf '%s\n' 'Neovim logs contain an error marker:' >&2
	grep -Ein "$error_pattern" "$sync_log" "$startup_log" >&2
	exit 1
fi

origin="$(git -C "$data_home/nvim/lazy/cmp-async-path" remote get-url origin)"
[[ "$origin" == 'https://github.com/FelipeLema/cmp-async-path.git' ]]
python - "$config_home/nvim/lazy-lock.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    lock = json.load(stream)
assert "cmp-async-path" in lock, "cmp-async-path missing from lockfile"
assert "cmp-path" not in lock, "obsolete cmp-path still present in lockfile"
PY
[[ "$(sha256sum "$source_lock" | cut -d' ' -f1)" == "$source_lock_hash" ]]

printf 'Neovim clean install: passed in %d sync attempt(s); cmp-async-path origin=%s\n' "$sync_attempt" "$origin"
