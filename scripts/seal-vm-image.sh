#!/usr/bin/env bash
set -Eeuo pipefail

# Runs INSIDE the build guest, fed over `bash -s` by scripts/build-vm-image.sh,
# after the guest has passed tests/guest-acceptance.sh. It turns a provisioned
# test guest into something a stranger can safely boot.
#
# IMAGE_LOCALE, IMAGE_KEYMAP and IMAGE_LAYOUT are exported by the caller.

cd "$HOME/archlinux-portfolio"

# The acceptance seeds three deliberately different axis values (es/es/fr) so
# each writer can be told apart. A published image carries defaults instead.
printf 'locale=%s\nkeymap=%s\nxkb_layout=%s\nime=fcitx5\n' \
	"$IMAGE_LOCALE" "$IMAGE_KEYMAP" "$IMAGE_LAYOUT" \
	>"$HOME/.config/archlinux-portfolio/settings"
./scripts/apply-system.sh --locale --keymap
./scripts/render-config.sh --deploy >/dev/null
grep -Fxq "LANG=$IMAGE_LOCALE" /etc/locale.conf
grep -Fxq "KEYMAP=$IMAGE_KEYMAP" /etc/vconsole.conf
grep -Fxq "    kb_layout = $IMAGE_LAYOUT" "$HOME/.config/hypr/generated/input.conf"

# Nothing that identifies the build host or the build run may survive.
sudo pacman -Scc --noconfirm >/dev/null
sudo journalctl --rotate >/dev/null 2>&1 || true
sudo journalctl --vacuum-time=1s >/dev/null 2>&1 || true
sudo rm -rf -- /var/log/journal/* /var/tmp/* /tmp/portfolio-runtime
rm -f -- "$HOME/.bash_history"
# systemd writes a fresh id at boot when the file exists and is empty.
sudo truncate -s 0 /etc/machine-id
# Host keys regenerate at first boot: Arch's sshd.service wants
# sshdgenkeys.service, which is conditioned on exactly these paths missing.
# Without this every downloaded copy of the image would share one identity.
sudo rm -f -- /etc/ssh/ssh_host_*

# cloud-init provisioned this guest from a seed ISO the artifact will not have;
# left enabled it stalls every boot waiting for a datasource that never comes.
sudo touch /etc/cloud/cloud-init.disabled
sudo rm -rf -- /var/lib/cloud/*

sudo fstrim -av >/dev/null 2>&1 || true

# Deferred so this SSH session can close cleanly and the caller can read the
# marker below; powering off inline would drop the connection mid-stream.
sudo systemd-run --on-active=8 --unit=seal-poweroff systemctl poweroff >/dev/null

# Credentials last: after this the build key is gone and sudo asks for a
# password, so nothing above could still be done.
printf 'portfolio:portfolio\n' | sudo chpasswd
sudo chage -d 0 portfolio
sudo rm -f -- /etc/sudoers.d/90-cloud-init-users
printf '%%wheel ALL=(ALL:ALL) ALL\n' | sudo tee /etc/sudoers.d/10-wheel >/dev/null
sudo chmod 0440 /etc/sudoers.d/10-wheel
sudo visudo -c -q
shred -u -- "$HOME/.ssh/authorized_keys" 2>/dev/null || rm -f -- "$HOME/.ssh/authorized_keys"

printf '%s\n' 'IMAGE_SEAL: DONE'
