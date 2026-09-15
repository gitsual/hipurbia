#!/usr/bin/env bash
set -Eeuo pipefail

# The image builder is only trustworthy if it cannot drift from the gate and
# cannot ship the build's own credentials. Both are structural properties of
# the two scripts, so they are asserted here rather than left to a reviewer.

repo_root="${REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
build="$repo_root/scripts/build-vm-image.sh"
seal="$repo_root/scripts/seal-vm-image.sh"
gate="$repo_root/scripts/test-vm.sh"
acceptance="$repo_root/tests/guest-acceptance.sh"

fail() {
	printf '%s\n' "$1" >&2
	exit 1
}
for file in "$build" "$seal" "$gate" "$acceptance"; do
	[[ -x "$file" ]] || fail "missing or not executable: $file"
done

# One acceptance, two callers: neither may carry an inline copy.
for caller in "$build" "$gate"; do
	grep -Fq 'tests/guest-acceptance.sh' "$caller" || fail "$caller does not feed the shared acceptance"
	grep -q "<<'GUEST'" "$caller" && fail "$caller still embeds an inline acceptance"
done

# A backing file is meaningless off this machine; the artifact must be flat.
grep -Eq 'qemu-img convert -O qcow2' "$build" || fail 'the builder does not flatten the overlay'
grep -Fq 'discard=unmap' "$build" || fail 'the build drive cannot be trimmed, so the seal cannot shrink it'
grep -Fq 'IMAGE_SEAL: DONE' "$build" || fail 'the builder does not require the seal marker'
grep -Fq 'VM_ACCEPTANCE: PASS' "$build" || fail 'the builder seals without requiring the acceptance'

# Everything that would identify the build host or let a stranger in.
declare -A removals=(
	[authorized_keys]='the build SSH key'
	['/etc/ssh/ssh_host_']='the SSH host keys'
	['/etc/machine-id']='the machine id'
	['cloud-init.disabled']='the cloud-init datasource'
)
for needle in "${!removals[@]}"; do
	grep -Fq "$needle" "$seal" || fail "the seal does not deal with ${removals[$needle]}"
done
grep -Fq 'chage -d 0 portfolio' "$seal" || fail 'the seal does not force the first password change'

# Ordering is load-bearing: the seal drops passwordless sudo and its own key
# at the very end, so every privileged step above must already have run.
key_line="$(grep -n 'authorized_keys' "$seal" | tail -1 | cut -d: -f1)"
for earlier in 'fstrim' 'ssh_host_' 'machine-id' 'systemd-run'; do
	line="$(grep -n -- "$earlier" "$seal" | tail -1 | cut -d: -f1)"
	((line < key_line)) || fail "the seal removes its key before it finishes with $earlier"
done

grep -Fxq 'dist/' "$repo_root/.gitignore" || fail 'built artifacts are not ignored'

printf 'vm image build: one shared acceptance, a flat artifact, and a seal that outlives nothing\n'
