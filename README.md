# inkyphotoframe

A digital photo frame that's virtually indistinguishable from a real one. A Raspberry Pi shows your photos on a Pimoroni colour e-ink display and changes to a new random one every 30 minutes (or whatever interval you like). E-ink holds its picture with the power off, so it looks like a print, not a screen.

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

## Settings

Edit the settings with `sudo nano /etc/inkyframe.conf`. Changes apply from the next photo change, or straight away if you run `inkyframe`.

| Setting | Default | What it does |
| --- | --- | --- |
| `PHOTO_DIR` | `~/photos` | Folder to show photos from |
| `FIT` | `crop` | `crop` fills the screen and trims the edges. `pad` shows the whole photo and adds borders |
| `BACKGROUND` | `white` | Border colour for `FIT=pad` (a name like `black`, or `#rrggbb`) |
| `ROTATE` | `0` | Turns photos clockwise by `90`, `180` or `270` degrees, for a frame hung in portrait or upside down |
| `SATURATION` | `0.5` | Colour intensity, from `0.0` (muted) to `1.0` (vivid) |

To change **how often the photo changes**, run the install command again with `INTERVAL` set in minutes:

```bash
curl -sSL https://raw.githubusercontent.com/sp3lllz/inkyphotoframe/main/setup.sh | INTERVAL=60 bash
```

## Handy commands

| Command | What it does |
| --- | --- |
| `inkyframe` | Show the next photo now |
| `inkyframe path/to/photo.jpg` | Show a specific photo |
| `journalctl -u inkyframe` | See which photos were shown, and any errors |
| `systemctl list-timers inkyframe.timer` | See when the next change is due |

## Updating

Run the install command again. Your photos and settings are kept.

## Troubleshooting

- **`No EEPROM detected`**: check the display is pushed firmly onto the GPIO header, and that you've rebooted since installing.
- **`Woah there, some pins we need are in use!`**: reboot. The installer changes a boot setting (`dtoverlay=spi0-0cs`) that only takes effect after a restart.
- **Anything else**: run `journalctl -u inkyframe -n 50` and look at the last few lines.

## Uninstalling

```bash
sudo systemctl disable --now inkyframe.timer
sudo rm -rf /opt/inkyframe /etc/inkyframe.conf /etc/systemd/system/inkyframe.* /usr/local/bin/inkyframe
sudo systemctl daemon-reload
```

Your `photos` folder is left alone.

## How it works

- `setup.sh` installs the Python libraries (prebuilt from apt where possible, so nothing is compiled on the Pi), turns on SPI and I2C, installs Pimoroni's [inky](https://github.com/pimoroni/inky) library into a virtual environment in `/opt/inkyframe`, and sets up a systemd timer that runs the frame 30 seconds after boot and then every `INTERVAL` minutes. It's safe to run as many times as you like.
- `inkyframe.py` picks a photo, fits it to the display and shows it. It runs once each time the timer fires and then exits, so nothing sits in memory between changes.

## The frame

There are a few options for the frame. You can make something from scratch, or use something like [this mount](https://makerworld.com/en/models/1221196-ikea-rodlam-inky-impression-7-mount#profileId-1238116) to fit it in an off-the-shelf IKEA frame and make it even more inconspicuous!
