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

Two accounts, by convention rather than by secret: `user` with the password
`user`, and `root` with `toor`. They are printed here because a demo image
whose credentials have to be guessed is a worse demo, and nothing expires
them. Sudo asks for the password; the build's passwordless rule does not
survive the seal.

That is only defensible because **the image does not listen on the network**.
`sshd` ships installed and disabled, so a published root password is not a
door standing open; enabling it is a deliberate act by whoever owns the copy,
and whoever does it should change both passwords first.

Nothing about the build host survives either. The machine id is blank and
systemd writes a fresh one, cloud-init is disabled so the guest does not stall
waiting for a datasource it will never see, and the SSH host keys are absent —
`sshdgenkeys.service` will mint a new identity the first time anyone starts
sshd, so two downloads can never share one.

All of this is asserted rather than assumed. `scripts/test-vm-image.sh` boots
the artifact twice with no network device attached at all, logs in over the
serial console with the credentials above, and rejects the image if sshd is
enabled, if a host key from the build survived, or if the two instances report
the same machine id.

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
