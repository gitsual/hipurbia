# The downloadable image

A release carries the same workstation this repository builds, already
provisioned, as a disk you can boot: `archlinux-portfolio.qcow2` for
QEMU/libvirt and `archlinux-portfolio.ova` for VirtualBox and VMware.

## Reassembling

GitHub refuses a release asset over 2 GiB, so each artifact ships in parts.
Download every part of the one you want, put them in the same directory and
concatenate them in order:

```sh
cat archlinux-portfolio.qcow2.part* >archlinux-portfolio.qcow2
sha256sum -c SHA256SUMS
```

`SHA256SUMS` covers both the parts and the reassembled whole, so a bad
download is caught before it is ever booted.

## First boot

The image logs in as `portfolio` with the password `portfolio`, and the
account is expired: the first login demands a new password before it gives you
a shell. Sudo asks for that password; the build's passwordless rule does not
survive the seal.

Nothing about the build host survives either. The machine id is blank and
systemd writes a fresh one, cloud-init is disabled so the guest does not stall
waiting for a datasource it will never see, and the SSH host keys are absent
so `sshdgenkeys.service` generates a new identity on first boot. Two copies of
the same file therefore have different host keys, which is asserted rather
than assumed: `scripts/test-vm-image.sh` boots the artifact twice and rejects
it if the fingerprints match.

## Language

The image ships `en_US.UTF-8`, a `us` console keymap and a `us` compositor
layout, with fcitx5 installed. All three are settings, not builds: edit
`~/.config/archlinux-portfolio/settings` and run

```sh
./scripts/apply-system.sh --locale --keymap
./scripts/render-config.sh --deploy
```

## Building it yourself

`scripts/build-vm-image.sh` produces the artifact from a clean checkout. It
provisions a guest, runs the same `tests/guest-acceptance.sh` the VM gate runs,
and seals the result only if that acceptance passed; `scripts/package-vm-image.sh`
then writes the OVA, the parts and the checksums. The published checksum is
what you can compare against.
