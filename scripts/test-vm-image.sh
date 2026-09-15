#!/usr/bin/env bash
set -Eeuo pipefail

# Accept the PUBLISHED artifact, not the tree that produced it.
#
# The interesting properties of a sealed image are observable from outside it,
# with no root on the host and no login to the guest: it must boot, it must
# bring sshd up, and two instances of the same file must present DIFFERENT
# host keys. That last one is the whole point of removing the keys in the
# seal; if it fails, every download shares one identity.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
image="$repo_root/dist/archlinux-portfolio.qcow2"
boot_timeout="${VM_IMAGE_BOOT_TIMEOUT:-180}"

usage() {
	cat <<'USAGE'
Usage: scripts/test-vm-image.sh [--image PATH]

Boot the published image twice and accept it from outside the guest.
Overrides: VM_IMAGE_BOOT_TIMEOUT (seconds, default 180).
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

for command_name in qemu-system-x86_64 qemu-img ssh-keyscan; do
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

host_address="$(printf '%d.%d.%d.%d' 127 0 0 1)"
ports=()
# -snapshot keeps every write in a throwaway overlay, so the artifact under
# test is the file that ships, bit for bit, and two instances cannot share
# state through it.
for instance in 1 2; do
	port="$(python -c 'import socket; s=socket.socket(); s.bind(("localhost", 0)); print(s.getsockname()[1]); s.close()')"
	ports+=("$port")
	qemu-system-x86_64 \
		-enable-kvm -machine q35,accel=kvm -cpu host \
		-smp 2 -m 2048 -snapshot \
		-drive "if=virtio,format=qcow2,file=$image" \
		-netdev "user,id=net0,hostfwd=tcp:$host_address:$port-:22" \
		-device virtio-net-pci,netdev=net0 \
		-device virtio-vga -display none \
		-daemonize -pidfile "$work/qemu-$instance.pid" \
		-serial "file:$work/serial-$instance.log"
	pids+=("$(<"$work/qemu-$instance.pid")")
done

fingerprints=()
for index in 0 1; do
	port="${ports[$index]}"
	key=''
	for _ in $(seq 1 "$((boot_timeout / 3))"); do
		key="$(ssh-keyscan -t ed25519 -p "$port" "$host_address" 2>/dev/null || true)"
		[[ -n "$key" ]] && break
		sleep 3
	done
	[[ -n "$key" ]] || {
		printf 'Instance %d never answered on ssh within %ss\n' "$((index + 1))" "$boot_timeout" >&2
		tail -n 40 "$work/serial-$((index + 1)).log" >&2 || true
		exit 1
	}
	fingerprints+=("$(ssh-keygen -lf - <<<"$key" | awk '{print $2}')")
done

[[ "${fingerprints[0]}" != "${fingerprints[1]}" ]] || {
	printf 'Both instances present the same host key (%s): the seal did not remove it\n' "${fingerprints[0]}" >&2
	exit 1
}

# A booted guest that reached sshd also reached multi-user; say so from the
# console rather than inferring it.
for instance in 1 2; do
	grep -q 'archportfolio' "$work/serial-$instance.log" || {
		printf 'Instance %d never announced its hostname on the console\n' "$instance" >&2
		exit 1
	}
done

printf 'Published image accepted: boots, serves ssh, and regenerates its identity\n'
printf '  instance 1: %s\n  instance 2: %s\n' "${fingerprints[0]}" "${fingerprints[1]}"
