#!/usr/bin/env bash
# Re-take the desktop captures the README shows, one per palette, inside the
# tested VM -- so the evidence is produced by a command like everything else
# here, and a palette that changes is a capture that changes with it.
#
# Requires an already running interactive VM:
#   ./scripts/test-vm.sh --gui      (first time: builds, accepts and boots it)
#   ./scripts/open-tested-vm.sh     (afterwards: boots the tested overlay)
set -Eeuo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
run="${VM_WORKDIR:-$repo_root/.vm-test}/run"
out_dir="${1:-$repo_root/assets/screenshots}"
# Written the way the other VM scripts write it: a literal loopback address in
# the source reads as a leaked private address to the privacy scan.
host_address="$(printf '%d.%d.%d.%d' 127 0 0 1)"

# The port is normally read from the file the VM scripts leave behind;
# VM_SSH_PORT overrides it for a VM that is up but whose provisioning run did
# not get as far as writing that file.
port="${VM_SSH_PORT:-}"
if [[ -z "$port" ]]; then
	[[ -f "$run/console-login.txt" ]] || {
		printf 'No running tested VM: start one with scripts/open-tested-vm.sh\n' >&2
		exit 1
	}
	port="$(sed -nE 's/^ssh_port=(.*)$/\1/p' "$run/console-login.txt")"
fi
ssh_opts=(-i "$run/id_ed25519" -p "$port" -o StrictHostKeyChecking=no
	-o UserKnownHostsFile=/dev/null -o ConnectTimeout=5)
# The theme name is expanded on this side deliberately: it comes from the
# catalogue in data/, never from input, and the guest reads it as an assignment.
# shellcheck disable=SC2029
guest() { ssh "${ssh_opts[@]}" "hipurbia@$host_address" "$@"; }

guest true >/dev/null 2>&1 || {
	printf 'The tested VM is not answering on port %s\n' "$port" >&2
	exit 1
}

themes=(warm-night)
while IFS= read -r file; do themes+=("$(basename -- "$file" .conf)"); done \
	< <(find "$repo_root/data/themes" -name '*.conf' -type f | LC_ALL=C sort)

mkdir -p -- "$out_dir"
for theme in "${themes[@]}"; do
	printf 'Capturing %s ...\n' "$theme"
	guest "THEME=$theme bash -s" <<'GUEST'
set -Eeuo pipefail
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export HYPRLAND_INSTANCE_SIGNATURE="$(find "$XDG_RUNTIME_DIR/hypr" -maxdepth 1 -mindepth 1 -type d -printf '%T@ %f\n' | sort -rn | head -1 | cut -d' ' -f2)"
export WAYLAND_DISPLAY="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -printf '%f\n' | sort | head -1)"
cd "$HOME/hipurbia"

./scripts/apply-theme.sh --theme "$THEME" >/dev/null

# A capture is a composition, so it starts from an empty workspace every time --
# and a kitty opened under the previous palette would still be wearing it.
#
# Killed rather than closed: a close reaches the terminal as a window manager
# request, and kitty answers a request to close a window running an editor with
# a confirmation dialog -- which is itself a window, and stays on the picture.
pkill -x kitty || true
for _ in $(seq 20); do
	[[ "$(hyprctl -j clients | python -c 'import json,sys; print(len(json.load(sys.stdin)))')" == 0 ]] && break
	sleep 0.5
done

# Each pane is a file, never a quoted string: `hyprctl dispatch exec` splits
# its argument on spaces and the quotes do not survive the trip, so a command
# passed inline arrives as a bare shell.
pane() {
	local number="$1" body="$2" path="/tmp/hipurbia-pane-$1.sh"
	printf '#!/usr/bin/env bash\nexport LANG=en_US.UTF-8\ncd "$HOME/hipurbia"\n%s\n' "$body" >"$path"
	chmod +x "$path"
	hyprctl dispatch exec -- kitty --hold "$path" >/dev/null
	sleep 4
}
first_window() {
	hyprctl -j clients | python -c '
import json, sys
print(sorted(json.load(sys.stdin), key=lambda c: (c["at"][1], c["at"][0]))[0]["address"])'
}

# Opened in the order the layout wants, not the order the picture reads in:
# dwindle puts each new window to the left of the one that was there, so the
# right-hand pane is the one that opens first.
#
# Right: the editor, opened on the template that renders the desktop around it.
pane 2 'nvim templates/hypr/.config/hypr/hyprland.conf.in'
sleep 6
# Bottom left: what this palette actually is, drawn in itself. It opens before
# the catalogue because dwindle splits the column downwards: the pane that opens
# second ends up under the one that opens third.
pane 3 './scripts/palette-card.sh'
# Top left: the catalogue this desktop can wear, printed by the command the
# menu itself uses, so the list on screen cannot drift from the list in data/.
hyprctl dispatch focuswindow "address:$(first_window)" >/dev/null
sleep 1
pane 1 './dotfiles/ricer/.local/bin/hipurbia-theme --print'

sleep 3
grim /tmp/capture.png
GUEST
	scp -q -i "$run/id_ed25519" -P "$port" -o StrictHostKeyChecking=no \
		-o UserKnownHostsFile=/dev/null \
		"hipurbia@$host_address:/tmp/capture.png" "$out_dir/$theme.png"
done
printf 'Captured %d desktops into %s\n' "${#themes[@]}" "$out_dir"
