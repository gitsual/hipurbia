#!/usr/bin/env bash
set -Eeuo pipefail

# Accept the PUBLISHED artifact, not the tree that produced it.
#
# The sealed image does not listen on the network — sshd ships installed and
# disabled — so it is accepted the way its owner will meet it: through the
# console, logging in with the published credentials.
#
# Three properties matter, and each is asserted rather than inferred. The
# credentials in the README actually work. sshd is really off, so the known
# root password is not a door left open. And two instances of the same file
# report DIFFERENT machine ids, which is the whole point of truncating it in
# the seal; if it fails, every download shares one identity.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
image="$repo_root/dist/archlinux-portfolio.qcow2"
# The published credentials, as the README states them.
image_user="${VM_IMAGE_USER:-user}"
boot_timeout="${VM_IMAGE_BOOT_TIMEOUT:-180}"

usage() {
	cat <<'USAGE'
Usage: scripts/test-vm-image.sh [--image PATH]

Boot the published image twice and accept it from its own console.
Works on any format QEMU reads, so the OVA's VMDK can be accepted too.
Overrides: VM_IMAGE_BOOT_TIMEOUT (seconds, default 180), VM_IMAGE_USER.
USAGE
}

while (($#)); do
	case "$1" in
	--image)
		[[ $# -ge 2 ]] || {
			printf '%s\n' '--image needs a path' >&2
			exit 2
		}
		image="$2"
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		printf 'Unknown option: %s\n' "$1" >&2
		exit 2
		;;
	esac
	shift
done

for command_name in qemu-system-x86_64 qemu-img python; do
	command -v "$command_name" >/dev/null || {
		printf 'Missing host dependency: %s\n' "$command_name" >&2
		exit 1
	}
done
[[ -f "$image" ]] || {
	printf 'No image at %s; run scripts/build-vm-image.sh first\n' "$image" >&2
	exit 1
}
qemu-img check -q "$image"
# The OVA ships the same disk in another format; accepting only the qcow2
# would leave half the release untested.
image_format="$(qemu-img info --output=json "$image" | python -c 'import json,sys; print(json.load(sys.stdin)["format"])')"

work="$(mktemp -d)"
pids=()
cleanup() {
	status=$?
	for pid in "${pids[@]:-}"; do
		[[ -n "$pid" ]] && kill "$pid" 2>/dev/null
	done
	rm -rf -- "$work"
	((status == 0)) || printf 'Published image rejected\n' >&2
}
trap cleanup EXIT

# -snapshot keeps every write in a throwaway overlay, so the artifact under
# test is the file that ships, bit for bit, and two instances cannot share
# state through it. No network device is attached at all: an image that needed
# one to be accepted would not be the image that ships.
consoles=()
for instance in 1 2; do
	console="$work/console-$instance.sock"
	consoles+=("$console")
	qemu-system-x86_64 \
		-enable-kvm -machine q35,accel=kvm -cpu host \
		-smp 2 -m 2048 -snapshot \
		-drive "if=virtio,format=$image_format,file=$image" \
		-nic none \
		-device virtio-vga -display none \
		-daemonize -pidfile "$work/qemu-$instance.pid" \
		-serial "unix:$console,server=on,wait=off"
	pids+=("$(<"$work/qemu-$instance.pid")")
done

# Talking to a getty is a conversation, not a command: the driver waits for
# each prompt instead of sleeping and hoping, and every answer comes back
# tagged so a line of boot noise cannot be mistaken for one.
report() {
	python - "$1" "$2" "$3" <<'DRIVER'
import socket, sys, time

path, user, deadline = sys.argv[1], sys.argv[2], float(sys.argv[3])
end = time.time() + deadline
buffer = ""

connection = None
while time.time() < end and connection is None:
    try:
        connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        connection.connect(path)
    except OSError:
        connection = None
        time.sleep(1)
if connection is None:
    sys.exit("console socket never accepted a connection")
connection.settimeout(2)


def expect(needle, what):
    global buffer
    while needle not in buffer:
        if time.time() > end:
            sys.exit("timed out waiting for %s\n--- console tail ---\n%s" % (what, buffer[-2000:]))
        try:
            chunk = connection.recv(4096)
        except socket.timeout:
            # A getty already sitting at its prompt sends nothing more; a
            # newline makes it reprint rather than leaving us blocked.
            connection.sendall(b"\n")
            continue
        if not chunk:
            sys.exit("console closed")
        buffer += chunk.decode("utf-8", "replace")


def send(line):
    connection.sendall((line + "\n").encode())


expect("login:", "the login prompt")
send(user)
expect("assword:", "the password prompt")
send(user)
expect("$", "a shell prompt")

# One tagged line per fact, so an answer cannot be confused with the motd, the
# prompt, or another answer.
send("""printf 'MACHINE_ID=%s\\n' "$(cat /etc/machine-id)" """)
expect("MACHINE_ID=", "the machine id")
send("""printf 'SSHD=%s\\n' "$(systemctl is-enabled sshd.service 2>&1)" """)
expect("SSHD=", "the sshd state")
send("""printf 'HOSTKEYS=%s\\n' "$(ls /etc/ssh/ssh_host_* 2>/dev/null | wc -l)" """)
expect("HOSTKEYS=", "the host key count")

for line in buffer.splitlines():
    line = line.strip()
    # The echo of the command that produced a tag also contains it, and that
    # echo is the one carrying a quote.
    if '"' in line or "=" not in line:
        continue
    if line.split("=")[0] in ("MACHINE_ID", "SSHD", "HOSTKEYS"):
        print(line)
DRIVER
}

declare -A seen=()
for index in 0 1; do
	instance=$((index + 1))
	answers="$(report "${consoles[$index]}" "$image_user" "$boot_timeout")" || {
		printf 'Instance %d never reached a usable console:\n%s\n' "$instance" "$answers" >&2
		exit 1
	}
	machine_id="$(sed -nE 's/^MACHINE_ID=(.+)$/\1/p' <<<"$answers" | tail -1)"
	sshd="$(sed -nE 's/^SSHD=(.+)$/\1/p' <<<"$answers" | tail -1)"
	host_keys="$(sed -nE 's/^HOSTKEYS=(.+)$/\1/p' <<<"$answers" | tail -1)"

	[[ -n "$machine_id" ]] || {
		printf 'Instance %d reported no machine id\n' "$instance" >&2
		exit 1
	}
	[[ "$sshd" == disabled ]] || {
		printf 'Instance %d ships sshd as %q; a published root password needs a closed door\n' \
			"$instance" "$sshd" >&2
		exit 1
	}
	((host_keys == 0)) || {
		printf 'Instance %d carries %s host key files from the build\n' "$instance" "$host_keys" >&2
		exit 1
	}
	[[ -v "seen[$machine_id]" ]] && {
		printf 'Both instances report machine id %s: the seal did not clear it\n' "$machine_id" >&2
		exit 1
	}
	seen["$machine_id"]="$instance"
done

printf 'Published image accepted: %s logs in, sshd is disabled, no host keys shipped,\n' "$image_user"
printf 'and the two instances report different machine ids.\n'
