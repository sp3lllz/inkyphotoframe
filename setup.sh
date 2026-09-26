#!/usr/bin/env bash
# Inky Photo Frame installer for a Raspberry Pi with a Pimoroni Inky Impression display.
#
#   curl -sSL https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/setup.sh | bash
#
# Re-run it at any time to update; your photos and settings are kept.
# Photos change on the clock, every 30 minutes by default. To change that: ... | INTERVAL=60 bash
# Battery mode for a PiSugar (switches the Pi off between photos): ... | BATTERY=yes bash
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
    # Battery mode: BATTERY=yes or no, otherwise keep whatever was set up last time.
    local battery=${BATTERY:-}
    if [[ -z $battery ]]; then
        if [[ -f $UNIT_DIR/inkyframe-battery.service ]]; then battery=yes; else battery=no; fi
    fi
    [[ $battery == yes || $battery == no ]] || die "BATTERY must be yes or no."

    say "Installing system packages (this can take a few minutes on a Pi Zero)"
    # numpy, Pillow and spidev come from apt as prebuilt packages, so nothing has to be compiled.
    # The font is for the info screen.
    local pkg missing=()
    for pkg in python3-venv python3-pil python3-numpy python3-spidev fonts-dejavu-core; do
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
    fetch buttons.py "$APP_DIR/buttons.py"
    fetch battery.py "$APP_DIR/battery.py"
    fetch welcome.jpg "$APP_DIR/welcome.jpg"
    # --system-site-packages lets pip reuse the apt packages above; --clear rebuilds a venv broken by an OS upgrade.
    "$APP_DIR/venv/bin/python" -c '' 2>/dev/null || sudo python3 -m venv --clear --system-site-packages "$APP_DIR/venv"
    sudo "$APP_DIR/venv/bin/pip" install --quiet --upgrade --disable-pip-version-check \
        --extra-index-url https://www.piwheels.org/simple inky
    "$APP_DIR/venv/bin/python" -c 'import inky.auto, spidev, smbus2' || die "The Python libraries didn't install correctly (see above)."
    printf '#!/bin/sh\nexec %s/venv/bin/python %s/inkyframe.py "$@"\n' "$APP_DIR" "$APP_DIR" |
        sudo tee /usr/local/bin/inkyframe >/dev/null
    sudo chmod 755 /usr/local/bin/inkyframe
    if [[ $battery == yes ]]; then install_pisugar; fi

    if [[ -f $CONFIG ]]; then
        photos=$(sed -n 's/^PHOTO_DIR=//p' "$CONFIG")
        grep -q '^BUTTON_A=' "$CONFIG" || button_settings | sudo tee -a "$CONFIG" >/dev/null
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
$(button_settings)
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
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/inkyframe.py auto
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
$([[ $battery == yes ]] && echo "# (battery.py changes the photo at boot)" || echo "OnBootSec=30s")
AccuracySec=1s

[Install]
WantedBy=timers.target
EOF

    say "Setting up the buttons"
    sudo tee "$UNIT_DIR/inkyframe-buttons.service" >/dev/null <<EOF
[Unit]
Description=Inky photo frame: buttons

[Service]
User=$user
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/buttons.py
Environment=PYTHONUNBUFFERED=1
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    # Holding D shuts the Pi down, so allow exactly that command without a password.
    printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl poweroff\n' "$user" | sudo tee /etc/sudoers.d/inkyframe.new >/dev/null
    sudo chmod 440 /etc/sudoers.d/inkyframe.new
    if sudo visudo -cqf /etc/sudoers.d/inkyframe.new; then
        sudo mv /etc/sudoers.d/inkyframe.new /etc/sudoers.d/inkyframe
    else
        sudo rm -f /etc/sudoers.d/inkyframe.new
        warn "Couldn't allow the buttons to shut the Pi down; everything else will still work."
    fi


    # These timers catch up on every boot after the Pi has been off, which would eat into battery mode's short wake-ups.
    local catch_up_timers=(apt-daily.timer apt-daily-upgrade.timer man-db.timer)
    local services=(inkyframe.timer inkyframe-buttons.service)
    if [[ $battery == yes ]]; then
        say "Setting up battery mode"
        sudo tee "$UNIT_DIR/inkyframe-battery.service" >/dev/null <<EOF
[Unit]
Description=Inky photo frame: battery mode (switch off between photos)
After=pisugar-server.service
Wants=pisugar-server.service

[Service]
User=$user
ExecStart=$APP_DIR/venv/bin/python $APP_DIR/battery.py
Environment=PYTHONUNBUFFERED=1 INTERVAL=$interval
Restart=on-failure
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
        services+=(inkyframe-battery.service)
        sudo systemctl disable --quiet --now "${catch_up_timers[@]}" 2>/dev/null || true
    elif [[ -f $UNIT_DIR/inkyframe-battery.service ]]; then
        say "Turning battery mode off"
        sudo systemctl disable --quiet --now inkyframe-battery.service
        sudo rm -f "$UNIT_DIR/inkyframe-battery.service"
        sudo systemctl enable --quiet --now "${catch_up_timers[@]}" 2>/dev/null || true
    fi

    sudo systemctl daemon-reload
    sudo systemctl enable --quiet "${services[@]}"

    if [[ ! -f $REBOOT_FLAG ]]; then
        sudo systemctl restart "${services[@]:1}"
        say "Showing a picture to test the display (the screen takes about 30 seconds to refresh)"
        # (Re)starting the timer triggers a run straight away (except in battery mode, which has no boot trigger);
        # starting the service joins that run, or starts one, and waits for it.
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
  Buttons:              A next, B previous, C pause, D info (hold D to shut down)
  Show the next photo:  inkyframe   (or: inkyframe previous / pause / info)
  See the log:          journalctl -u 'inkyframe*'
EOF
    if [[ $battery == yes ]]; then
        cat <<EOF
  Battery mode:         on battery, the Pi switches off between photos (never while you're
                        logged in or charging). To use the buttons or add photos, wake it
                        with the PiSugar's power button; it stays on for 5 minutes.
EOF
    fi

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

# PiSugar's power manager, which battery.py uses to read the battery and set the wake-up alarm.
install_pisugar() {
    local model=${PISUGAR_MODEL:-}
    if [[ -z $model ]]; then
        if sudo "$APP_DIR/venv/bin/python" -c 'from smbus2 import SMBus; SMBus(1).read_byte(0x57)' 2>/dev/null; then
            model="PiSugar 3"
        elif [[ -f $REBOOT_FLAG ]]; then
            model="PiSugar 3"
            warn "Can't look for the PiSugar until after the reboot, so assuming it's a PiSugar 3."
        else
            die "No PiSugar 3 found: check it's attached and switched on. For a PiSugar 2, add e.g. PISUGAR_MODEL=\"PiSugar 2 (4-LEDs)\""
        fi
    fi
    if ! dpkg -s pisugar-server pisugar-poweroff &>/dev/null; then
        say "Installing the PiSugar software ($model)"
        local version arch tmp pkg
        version=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/PiSugar/pisugar-power-manager-rs/releases/latest)
        version=${version##*/v}
        arch=$(dpkg --print-architecture)
        tmp=$(mktemp -d)
        chmod 755 "$tmp" # so apt's download user can read the packages
        for pkg in pisugar-server pisugar-poweroff; do
            curl -fsSL -o "$tmp/$pkg.deb" \
                "https://github.com/PiSugar/pisugar-power-manager-rs/releases/download/v$version/${pkg}_$version-1_$arch.deb"
        done
        # Answer the packages' questions up front: the model, and keep the server private to this Pi (no web page).
        sudo debconf-set-selections <<EOF
pisugar-server pisugar-server/model select $model
pisugar-server pisugar-server/address select 127.0.0.1
pisugar-server pisugar-server/web boolean false
pisugar-poweroff pisugar-poweroff/model select $model
EOF
        sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$tmp"/*.deb >/dev/null
        rm -rf "$tmp"
    fi
    # pisugar-poweroff cuts the battery output once the Pi has shut down. Only enable it: starting it shuts the Pi down!
    sudo systemctl enable --quiet pisugar-poweroff.service
    sudo systemctl enable --quiet --now pisugar-server.service
}

# Button settings for the config file; also appended to configs from before the buttons existed.
button_settings() {
    cat <<'EOF'

# What the buttons on the side of the display do, A to D.
# Choose from: next, previous, pause, info, shutdown, none
# (Holding D for 3 seconds always shuts the Pi down safely.)
BUTTON_A=next
BUTTON_B=previous
BUTTON_C=pause
BUTTON_D=info
EOF
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
