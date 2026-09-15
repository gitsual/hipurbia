# The downloadable image

A release carries the same workstation this repository builds, already
provisioned, as a disk you can boot: `hipurbia.qcow2` for
QEMU/libvirt and `hipurbia.ova` for VirtualBox and VMware.

## Reassembling

GitHub refuses a release asset over 2 GiB, so each artifact ships in parts.
Download every part of the one you want, put them in the same directory and
concatenate them in order:

```sh
cat hipurbia.qcow2.part* >hipurbia.qcow2
sha256sum -c SHA256SUMS
```

`SHA256SUMS` covers both the parts and the reassembled whole, so a bad
download is caught before it is ever booted.

## Running it

```
scripts/run-vm-image.sh            # a window, a greeter, changes discarded on shutdown
scripts/run-vm-image.sh --persist  # keep what you do
```

The flags matter, and the most modern-looking ones are the ones that break.
The launcher uses QEMU's GTK display **without** OpenGL on purpose: with
`gl=on`, QEMU hands the guest's cursor to the host through the GL path, which
uploads it with the framebuffer's Y convention and draws it upside down — a
second, inverted pointer riding on top of the real one. Nothing in the guest
causes it and nothing in the guest can fix it; the compositor already asks for
software cursors on virtual machines (`cursor { no_hardware_cursors = true }`,
rendered whenever the facts report virtualisation). `--gl` opts back in.

For VirtualBox or VMware, import the OVA and boot it; no flags to get wrong.

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

## What is installed

The image is provisioned by `scripts/bootstrap.sh` with every selector the
repository offers, including `--apps`: Obsidian from the official repositories
and Stremio from the AUR.

The Stremio package is `stremio-linux-shell`, not `stremio` — which is the one
with the votes and cannot be installed. Its 4.4 series is a Qt5 shell
depending on `qt5-webengine`, and Arch has dropped `qt5-webengine` from the
official repositories, so installing it now means compiling Chromium from
source: hours of build time and more RAM than the image is given, to ship a
client its own upstream has already replaced. `stremio-linux-shell` is that
replacement, from the Stremio organisation's own repository, and every
dependency it names is an official package — gtk4, libadwaita, webkitgtk-6.0,
mpv, nodejs. It builds against the system it is installed on rather than
carrying a browser engine of its own.

Stremio is the reason `scripts/aur-install.sh`
exists — the AUR is a collection of build recipes rather than a repository, so
using it means compiling here, and that decision is made in one place instead
of being assumed by every caller.

No helper is installed to do it. The first attempt did install one, and it
failed the way prebuilt binaries fail: `paru-bin` 2.1.0 is linked against
`libalpm.so.15`, the guest had just upgraded to a pacman shipping
`libalpm.so.16`, and the helper could not start. A tool that must be rebuilt
whenever pacman moves is a poor foundation for provisioning pacman. For an
explicit, flat list of packages, what a helper would do is clone each recipe
and run `makepkg` — so that is what happens, with no toolchain to install and
nothing prebuilt that can fall out of step with the local libalpm. A machine
that already has `paru` or `yay` keeps using it.

## Language

The image ships `en_US.UTF-8`, a `us` console keymap and a `us` compositor
layout, with fcitx5 installed. All three are settings, not builds: edit
`~/.config/hipurbia/settings` and run

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
