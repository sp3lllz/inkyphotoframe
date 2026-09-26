# inkyphotoframe

A digital photo frame that's virtually indistinguishable from a real one. A Raspberry Pi shows your photos on a Pimoroni colour e-ink display and changes to a new random one on the hour and at half past (or whatever interval you like). E-ink holds its picture with the power off, so it looks like a print, not a screen.

![Inky Photo Frame welcome image](welcome.jpg)

## What you need

1. **A Raspberry Pi** with a 40-pin header. A Pi Zero 2 W or Pi 3 or newer is best because it has Wi-Fi built in. A Pi Zero W works too, just more slowly.
2. **A microSD card.** The bigger the card, the more photos it can hold.
3. **A Pimoroni Inky Impression display**: the [5.7"](https://shop.pimoroni.com/products/inky-impression-5-7), [4"](https://shop.pimoroni.com/products/inky-impression-4) or [7.3"](https://shop.pimoroni.com/products/inky-impression-7-3), or the newer Spectra 6 versions. Photos are resized to fit whichever one you have.
4. **A frame** to put it all in (see [The frame](#the-frame) below).

## Setup

1. Use [Raspberry Pi Imager](https://www.raspberrypi.com/software/) to flash **Raspberry Pi OS Lite** (Bookworm or newer) onto the microSD card. In the customisation settings, set a hostname (e.g. `inkyframe`), a username and password, and your Wi-Fi, and turn on SSH.
2. Plug the display onto the Pi's GPIO header. A Pi Zero fits straight onto the back of the board. For a full-size Pi, use the standoffs and the GPIO extension header that come with the display.
3. Power up the Pi, connect over SSH (`ssh <username>@inkyframe.local`) and run:

   ```bash
   curl -sSL https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/setup.sh | bash
   ```

4. At the end it asks to reboot, which it needs to do to switch on the display's SPI and I2C interfaces. About a minute after the Pi restarts, the frame shows the welcome image above.

That's it. Now add some photos.

## Adding photos

Put your photos in the `photos` folder in your home directory on the Pi. From a Mac or Linux computer:

```bash
scp *.jpg <username>@inkyframe.local:photos/
```

Or use any SFTP app (Cyberduck, WinSCP, FileZilla) to connect to `inkyframe.local` with your Pi's username and password, then drag photos into `photos`.

- Files can have any name, and subfolders are fine.
- JPEG, PNG, WebP, GIF, BMP and TIFF all work. For iPhone HEIC photos, export them as JPEG first.
- There's no need to resize or rotate anything. Photos are scaled and cropped to fit the screen, and phone photos are turned the right way up automatically.
- Photos are shown in random order, and every photo is shown once before any of them repeat.

## Buttons

The four buttons on the side of the display work without needing to SSH in:

| Button | What it does |
| --- | --- |
| **A** | Next photo |
| **B** | Previous photo. Press it again to keep going back |
| **C** | Pause or resume the automatic changes. A pause symbol shows in the corner while it's paused |
| **D** | Info screen: the frame's address and username for adding photos, and what each button does |
| **Hold D** for 3 seconds | Shut down safely. The screen tells you when it's safe to unplug |

The screen takes about 30 seconds to redraw, and presses during a redraw are ignored. You can change what A to D do in the settings below.

## Battery mode (PiSugar)

The frame can run from a [PiSugar](https://github.com/PiSugar/PiSugar) battery: a PiSugar 3 for a Pi Zero, or a PiSugar 3 Plus for a Pi 3 or 4. An always-on Pi would flatten it in less than a day. Battery mode instead **switches the Pi off completely between photos**. E-ink keeps its picture with no power at all, and the PiSugar's clock wakes the Pi up for the next change. To turn it on, run the install command with `BATTERY=yes` (it's remembered from then on):

```bash
curl -sSL https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/setup.sh | BATTERY=yes bash
```

How it behaves on battery:

- **Each photo change** takes about a minute: the Pi wakes, shows the next photo, sets the PiSugar to wake it for the change after, and switches off.
- **To use the buttons or add photos**, wake it with the PiSugar's power button. It shows the next photo and stays on for 5 minutes after waking, or after the last button press. It never switches off while you're logged in over SSH.
- **While charging**, it stays on and works just like the plugged-in version.
- **When paused** (button C), it switches off and doesn't wake again until you press the PiSugar's power button.
- **Below 20% battery**, a small battery symbol appears in the corner of each photo, and the info screen (button D) shows the level. Below 10%, the screen says "Battery empty" and the frame stays off until you charge it and press the PiSugar's power button.

Battery life depends mostly on how often the photo changes. These are very rough estimates for a Pi Zero 2 W:

| Photo changes | PiSugar 3 (1200 mAh) | PiSugar 3 Plus (5000 mAh) |
| --- | --- | --- |
| Every 30 minutes | about 5 days | about 3 weeks |
| Every hour | about 10 days | about 6 weeks |
| Every 2 hours | about 2 weeks | about 2 months |
| **Every 6 hours** (the battery mode default) | about 3 to 4 weeks | about 4 months |
| Once a day | about a month | about 5 months |

In battery mode the photo changes every 6 hours (at midnight, 6am, noon and 6pm) unless you choose a different `INTERVAL` on the same install command, e.g. `BATTERY=yes INTERVAL=120 bash`. Turn battery mode off again with `BATTERY=no`, which puts the interval back to the plugged-in default of 30 minutes unless you set one.

The installer finds a PiSugar 3 automatically. For a PiSugar 2, name the model: `PISUGAR_MODEL="PiSugar 2 (4-LEDs)"`, `"PiSugar 2 (2-LEDs)"` or `"PiSugar 2 Pro"`. The PiSugar S has no clock, so it can't wake the Pi and won't work with battery mode.

## Settings

Edit the settings with `sudo nano /etc/inkyframe.conf`. Changes apply from the next photo change, or straight away if you run `inkyframe`.

| Setting | Default | What it does |
| --- | --- | --- |
| `PHOTO_DIR` | `~/photos` | Folder to show photos from |
| `FIT` | `crop` | `crop` fills the screen and trims the edges. `pad` shows the whole photo and adds borders |
| `BACKGROUND` | `white` | Border colour for `FIT=pad` (a name like `black`, or `#rrggbb`) |
| `ROTATE` | `0` | Turns photos clockwise by `90`, `180` or `270` degrees, for a frame hung in portrait or upside down |
| `SATURATION` | `0.5` | Colour intensity, from `0.0` (muted) to `1.0` (vivid) |
| `BUTTON_A` to `BUTTON_D` | `next`, `previous`, `pause`, `info` | What each button does: `next`, `previous`, `pause`, `info`, `shutdown` or `none` |

To change **how often the photo changes**, run the install command again with `INTERVAL` set in minutes:

```bash
curl -sSL https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/setup.sh | INTERVAL=60 bash
```

Changes happen on the clock, so the interval has to fit evenly into an hour or a day: for example `15` (:00, :15, :30, :45), `30` (the default), `60` (on the hour), `120` (every other hour), `360` (the default in [battery mode](#battery-mode-pisugar)) or `1440` (midnight). A photo is also shown 30 seconds after the Pi starts. Your interval is remembered when you re-run the installer, until you switch battery mode on or off.

## Handy commands

| Command | What it does |
| --- | --- |
| `inkyframe` | Show the next photo now |
| `inkyframe previous` / `pause` / `info` / `shutdown` | The same as the buttons |
| `inkyframe path/to/photo.jpg` | Show a specific photo |
| `journalctl -u 'inkyframe*'` | See which photos were shown, button presses, when it switched off on battery, and any errors |
| `systemctl list-timers inkyframe.timer` | See when the next change is due |

## Updating

Run the install command again. Your photos and settings are kept.

## Troubleshooting

- **`No EEPROM detected`**: check the display is pushed firmly onto the GPIO header, and that you've rebooted since installing.
- **`Woah there, some pins we need are in use!`**: reboot. The installer changes a boot setting (`dtoverlay=spi0-0cs`) that only takes effect after a restart.
- **Buttons do nothing**: run `journalctl -u inkyframe-buttons -n 20` to see whether presses are being picked up.
- **Anything else**: run `journalctl -u 'inkyframe*' -n 50` and look at the last few lines.

## Uninstalling

```bash
sudo systemctl disable --now inkyframe.timer inkyframe-buttons.service inkyframe-battery.service
sudo rm -rf /opt/inkyframe /etc/inkyframe.conf /etc/systemd/system/inkyframe* /usr/local/bin/inkyframe /etc/sudoers.d/inkyframe
sudo systemctl daemon-reload
```

Your `photos` folder is left alone. If you used battery mode, also run `sudo apt purge pisugar-server pisugar-poweroff` and `sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer man-db.timer`.

## How it works

- `setup.sh` installs the Python libraries (prebuilt from apt where possible, so nothing is compiled on the Pi), turns on SPI and I2C, installs Pimoroni's [inky](https://github.com/pimoroni/inky) library into a virtual environment in `/opt/inkyframe`, and sets up a systemd timer that runs the frame 30 seconds after boot and then on the clock every `INTERVAL` minutes. It's safe to run as many times as you like.
- `inkyframe.py` picks a photo, fits it to the display and shows it. It runs once each time the timer fires or a button is pressed, then exits.
- `buttons.py` is a small service that keeps running while the Pi is on. It sleeps until a button is pressed and then runs `inkyframe.py`. It also lets the buttons shut the Pi down, via a sudoers rule that allows only `systemctl poweroff`.
- `battery.py` runs only in battery mode. It talks to PiSugar's `pisugar-server` (installed from PiSugar's GitHub releases, and only reachable from the Pi itself) to read the battery, sync the clock and set the wake-up alarm, then powers off. `pisugar-poweroff` then cuts the battery output, so the switched-off Pi draws almost nothing. Battery mode also turns off the `apt-daily` and `man-db` timers, which would otherwise run on every wake-up.

## The frame

There are a few options for the frame. You can make something from scratch, or use something like [this mount](https://makerworld.com/en/models/1221196-ikea-rodlam-inky-impression-7-mount#profileId-1238116) to fit it in an off-the-shelf IKEA frame and make it even more inconspicuous!
