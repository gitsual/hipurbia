#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

# Stage labels are numbered at run time so that adding a stage touches one line
# instead of renumbering every label. The total is the number of `stage` calls
# in this file, counted once at startup.
stage_total="$(grep -c '^stage ' "${BASH_SOURCE[0]}")"
stage_index=0
stage() {
	stage_index=$((stage_index + 1))
	printf '[%d/%d] %s\n' "$stage_index" "$stage_total" "$1"
}

stage 'shell syntax'
while IFS= read -r -d '' file; do bash -n "$file"; done < <(find scripts dotfiles lib tests -type f \( -name '*.sh' -o -name 'workstation-security-audit' \) -print0)

stage 'shellcheck'
if command -v shellcheck >/dev/null; then
	mapfile -d '' shell_files < <(find scripts dotfiles lib tests -type f \( -name '*.sh' -o -name 'workstation-security-audit' \) -print0)
	shellcheck "${shell_files[@]}"
else
	printf '%s\n' 'shellcheck not installed; syntax checks still ran'
fi

stage 'structured configuration'
python -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/privacy-scan.py").read_text())'
python -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/configure-audio.py").read_text())'
python -c 'import ast, pathlib; ast.parse(pathlib.Path("dotfiles/automation/.local/bin/workstation-task-runner").read_text())'
python -m json.tool dotfiles/waybar/.config/waybar/config >/dev/null
python -m json.tool profiles/automation/example.json >/dev/null
while IFS= read -r -d '' file; do
	nvim --headless --clean -u NONE -c "lua assert(loadfile([[${file}]]))" -c qa
done < <(find dotfiles/nvim -type f -name '*.lua' -print0)
systemd-analyze verify \
	dotfiles/security/.config/systemd/user/*.service \
	dotfiles/security/.config/systemd/user/*.timer \
	dotfiles/automation/.config/systemd/user/*.service \
	dotfiles/automation/.config/systemd/user/*.timer

stage 'package manifests'
for manifest in packages/*.txt; do
	[[ "$manifest" == *.local.txt ]] && continue
	[[ -f "$manifest" ]]
	diff -u "$manifest" <(LC_ALL=C sort -u "$manifest")
done

stage 'symlinks and unexpected binaries'
if find . \( -path ./.git -o -path ./.vm-test -o -path ./.audit \) -prune -o -type l ! -exec test -e {} \; -print -quit | grep -q .; then
	printf '%s\n' 'broken symlink found' >&2
	exit 1
fi
if find . \( -path ./.git -o -path ./.vm-test -o -path ./.audit \) -prune -o -type f ! -path './dotfiles/hypr/.local/share/wallpapers/warm-night.png' -print0 | xargs -0 file | grep -Ev 'text|empty|SVG|JSON|Python script|shell script' >/dev/null; then
	printf '%s\n' 'unexpected binary file found' >&2
	exit 1
fi

# NOTE: this stage must run after the committed-render stage introduced in the
# rendering phase, so hashes are taken over post-render bytes rather than stale
# ones. The ordering assertion itself lands with that stage.
stage 'asset manifest'
"$repo_root/scripts/check-asset-manifest.sh"
stage 'privacy and secret scan'
python scripts/privacy-scan.py .
if command -v gitleaks >/dev/null; then
	gitleaks detect --no-banner --no-git --source .
else
	printf '%s\n' 'gitleaks not installed; explicit privacy scanner completed'
fi

stage 'default profile baseline'
"$repo_root/scripts/freeze-baseline.sh"

stage 'selector registry'
"$repo_root/scripts/check-selectors.sh"

stage 'unit and fixture tests'
"$repo_root/tests/run.sh"

stage 'deployment script dry run'
dry_home="$(mktemp -d "${TMPDIR:-/tmp}/archportfolio-dry-run.XXXXXX")"
trap 'rm -rf -- "$dry_home"' EXIT
HOME="$dry_home" XDG_STATE_HOME="$dry_home/.local/state" "$repo_root/scripts/deploy.sh" --all --dry-run
rm -rf -- "$dry_home"
trap - EXIT

stage 'isolated deployment regression'
"$repo_root/scripts/test-deploy.sh"

printf '%s\n' 'all repository checks passed'
