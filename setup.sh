#!/usr/bin/env bash
# Inky Photo Frame installer for a Raspberry Pi with a Pimoroni Inky Impression display.
#
#   curl -sSL https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/setup.sh | bash
#
# Re-run it at any time to update; your photos and settings are kept.
# Photos change on the clock, every 30 minutes by default. To change that: ... | INTERVAL=60 bash
set -euo pipefail

REPO=https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main
APP_DIR=/opt/inkyframe
CONFIG=/etc/inkyframe.conf
UNIT_DIR=/etc/systemd/system
REBOOT_FLAG=/run/inkyframe-reboot-required # /run is emptied on boot, so this clears itself

say() { printf '\n\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33mWarning:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[1;31mError:\033[0m %s\n' "$*" >&2
    exit 1
}

# Install a file from this repo: from the local clone if we're running from one, otherwise from GitHub.
fetch() {
    local tmp
    tmp=$(mktemp)
    if [[ -n $SRC_DIR && -f $SRC_DIR/$1 ]]; then cp "$SRC_DIR/$1" "$tmp"; else curl -fsSL "$REPO/$1" -o "$tmp"; fi
    sudo install -m 644 "$tmp" "$2"
    rm -f "$tmp"
}

main() {
    command -v apt-get >/dev/null || die "This installer needs Raspberry Pi OS (Bookworm or newer)."
    grep -qs "Raspberry Pi" /proc/device-tree/model || warn "This doesn't look like a Raspberry Pi; carrying on anyway."

    local user home interval calendar photos
    user=${SUDO_USER:-$(id -un)}
    home=$(getent passwd "$user" | cut -d: -f6)
    interval=${INTERVAL:-$(sed -n 's/^# INTERVAL=\([0-9]*\).*/\1/p' "$UNIT_DIR/inkyframe.timer" 2>/dev/null || true)}
    interval=${interval:-30}
    # Photos change on the clock, so the interval has to divide evenly into an hour or a day.
    if [[ ! $interval =~ ^[1-9][0-9]*$ ]]; then
        calendar=
    elif ((interval < 60 && 60 % interval == 0)); then
        calendar="*:00/$interval" # e.g. 30: on the hour and at half past
    elif ((interval == 1440)); then
        calendar="00:00" # once a day at midnight
    elif ((interval % 60 == 0 && 24 % (interval / 60) == 0)); then
        calendar="00/$((interval / 60)):00" # e.g. 120: every other hour, on the hour
    fi
    [[ -n ${calendar:-} ]] || die "INTERVAL must fit evenly into the clock, e.g. 10, 15, 20, 30, 60, 120 or 1440 minutes."

    say "Installing system packages (this can take a few minutes on a Pi Zero)"
    # numpy, Pillow and spidev come from apt as prebuilt packages, so nothing has to be compiled.
    local pkg missing=()
    for pkg in python3-venv python3-pil python3-numpy python3-spidev; do
        dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
    done
    if ((${#missing[@]})); then
        sudo apt-get update -qq --allow-releaseinfo-change
        sudo apt-get install -y -qq --no-install-recommends "${missing[@]}" >/dev/null
    fi

    say "Enabling SPI and I2C"
    if command -v raspi-config >/dev/null; then
        [[ $(sudo raspi-config nonint get_spi) == 0 ]] || { sudo raspi-config nonint do_spi 0 && sudo touch "$REBOOT_FLAG"; }
        [[ $(sudo raspi-config nonint get_i2c) == 0 ]] || { sudo raspi-config nonint do_i2c 0 && sudo touch "$REBOOT_FLAG"; }
    else
        warn "raspi-config not found: make sure SPI and I2C are enabled."
    fi
    # The Inky drives the SPI chip-select pin itself, so stop the kernel from claiming it.
    local boot_config=/boot/firmware/config.txt
    [[ -f $boot_config ]] || boot_config=/boot/config.txt
    if [[ -f $boot_config ]] && ! grep -q '^dtoverlay=spi0-0cs' "$boot_config"; then
        printf '\n[all]\ndtoverlay=spi0-0cs\n' | sudo tee -a "$boot_config" >/dev/null
        sudo touch "$REBOOT_FLAG"
    fi
    local group
    for group in gpio spi i2c; do
        if getent group "$group" >/dev/null; then sudo usermod -aG "$group" "$user"; fi
    done

    say "Installing the photo frame software to $APP_DIR"
    sudo mkdir -p "$APP_DIR"
    fetch inkyframe.py "$APP_DIR/inkyframe.py"
    fetch welcome.jpg "$APP_DIR/welcome.jpg"
    # --system-site-packages lets pip reuse the apt packages above; --clear rebuilds a venv broken by an OS upgrade.
    "$APP_DIR/venv/bin/python" -c '' 2>/dev/null || sudo python3 -m venv --clear --system-site-packages "$APP_DIR/venv"
    sudo "$APP_DIR/venv/bin/pip" install --quiet --upgrade --disable-pip-version-check \
        --extra-index-url https://www.piwheels.org/simple inky
    "$APP_DIR/venv/bin/python" -c 'import inky.auto, spidev, smbus2' || die "The Python libraries didn't install correctly (see above)."
    printf '#!/bin/sh\nexec %s/venv/bin/python %s/inkyframe.py "$@"\n' "$APP_DIR" "$APP_DIR" |
        sudo tee /usr/local/bin/inkyframe >/dev/null
    sudo chmod 755 /usr/local/bin/inkyframe

    if [[ -f $CONFIG ]]; then
        photos=$(sed -n 's/^PHOTO_DIR=//p' "$CONFIG")
    else
        photos=$home/photos
        say "Creating your photo folder: $photos"
        sudo -u "$user" mkdir -p "$photos"
        sudo tee "$CONFIG" >/dev/null <<EOF
# Inky photo frame settings. Changes apply from the next photo change,
# or straight away if you run: inkyframe

# Folder your photos are in (subfolders are included)
PHOTO_DIR=$photos

# crop = fill the screen, trimming the edges if needed
# pad  = show the whole photo, adding borders if needed
FIT=crop

# Border colour for FIT=pad: a name like white or black, or #rrggbb
BACKGROUND=white

# Rotate photos clockwise to match how the frame hangs: 0, 90, 180 or 270
ROTATE=0

# Colour saturation, from 0.0 (muted) to 1.0 (vivid)
SATURATION=0.5
EOF
        migrate_v1 "$user" "$photos"
    fi

    say "Scheduling a new photo every $interval minutes, on the clock"
    sudo tee "$UNIT_DIR/inkyframe.service" >/dev/null <<EOF
[Unit]
Description=Inky photo frame: show the next photo

[Service]
Type=oneshot
User=$user
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/inkyframe.py
Nice=10
NoNewPrivileges=yes
ProtectSystem=full
EOF
    sudo tee "$UNIT_DIR/inkyframe.timer" >/dev/null <<EOF
# INTERVAL=$interval (written by setup.sh, which reads it back when re-run)
[Unit]
Description=Change the Inky photo frame picture every $interval minutes, on the clock

[Timer]
OnCalendar=$calendar
OnBootSec=30s
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable --quiet inkyframe.timer

    if [[ ! -f $REBOOT_FLAG ]]; then
        say "Showing a picture to test the display (the screen takes about 30 seconds to refresh)"
        # (Re)starting the timer triggers a run straight away; starting the service joins that run and waits for it.
        sudo systemctl restart inkyframe.timer
        if ! sudo systemctl start inkyframe.service; then
            warn "The display test failed. Recent log:"
            sudo journalctl -u inkyframe -n 15 --no-pager -o cat
        fi
    fi

    say "All done!"
    cat <<EOF
  Add photos to:        $photos   (subfolders are fine)
    from your computer: scp *.jpg $user@$(hostname).local:${photos#"$home"/}/
  Change settings:      sudo nano $CONFIG
  Show the next photo:  inkyframe
  See the log:          journalctl -u inkyframe
EOF

    if [[ -f $REBOOT_FLAG ]]; then
        say "A reboot is needed to switch on SPI and I2C. The frame shows its first picture about a minute after."
        if (: </dev/tty) 2>/dev/null; then
            local answer
            read -rp "Reboot now? [Y/n] " answer </dev/tty
            [[ $answer =~ ^[Nn] ]] || exec sudo reboot
        fi
        echo "Reboot when you're ready with: sudo reboot"
    fi
}

# Tidy up after the original cron-based version, which lived in /var/inkyframe.
migrate_v1() {
    local user=$1 photos=$2 cron old
    [[ -d /var/inkyframe ]] || return 0
    say "Moving your photos over from the old /var/inkyframe version"
    cron=$(sudo crontab -u "$user" -l 2>/dev/null || true)
    if [[ $cron == */var/inkyframe/* ]]; then
        grep -v /var/inkyframe/ <<<"$cron" | sudo crontab -u "$user" - || true
    fi
    old=(/var/inkyframe/images/main/*)
    if [[ -e ${old[0]} ]]; then
        sudo mv -n "${old[@]}" "$photos"/ || true
        sudo chown -R "$user:" "$photos"
    fi
    sudo rm -f /var/inkyframe/{ranphoto.py,ranphoto.sh,ranupdate.sh,image.py,testimage.jpg}
    sudo rmdir /var/inkyframe/images/main /var/inkyframe/images /var/inkyframe 2>/dev/null ||
        warn "Left /var/inkyframe in place because it still has files in it."
}

SRC_DIR=
if [[ -f ${BASH_SOURCE[0]:-} ]]; then SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); fi
main "$@"
