#!/usr/bin/env python3
"""Inky photo frame: show a photo on a Pimoroni Inky display.

Usage:
    inkyframe          show the next photo from PHOTO_DIR
    inkyframe PHOTO    show a specific image file

Photos are picked at random, and every photo is shown once before any repeat.
Settings are read from /etc/inkyframe.conf; environment variables of the same
name override them.
"""

import os
import random
import sys
from pathlib import Path

from inky.auto import auto
from PIL import Image, ImageOps

CONFIG_FILE = Path("/etc/inkyframe.conf")
DEFAULTS = {
    "PHOTO_DIR": "~/photos",
    "FIT": "crop",  # crop: fill the screen, trimming edges | pad: show the whole photo with borders
    "BACKGROUND": "white",  # border colour for FIT=pad
    "ROTATE": "0",  # clockwise degrees, to match how the frame is mounted
    "SATURATION": "0.5",
}
IMAGE_TYPES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
WELCOME = Path(__file__).with_name("welcome.jpg")
HISTORY = Path.home() / ".local/state/inkyframe/shown"


def load_config():
    config = dict(DEFAULTS)
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text().splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() in config:
                config[key.strip()] = value.strip().strip("'\"")
    config.update((key, os.environ[key]) for key in DEFAULTS if key in os.environ)
    return config


def find_photos(folder):
    """Every image under folder, including subfolders, skipping hidden files."""
    photos = []
    for path in folder.rglob("*"):
        relative = path.relative_to(folder)
        if path.suffix.lower() in IMAGE_TYPES and not any(part.startswith(".") for part in relative.parts):
            photos.append(str(relative))
    return photos


def pick_photo(photos):
    """A random photo that hasn't been shown yet this cycle."""
    shown = HISTORY.read_text().splitlines() if HISTORY.exists() else []
    seen = set(shown)
    unseen = [p for p in photos if p not in seen]
    if not unseen:  # everything has been shown: start a new cycle, avoiding the photo on screen now
        unseen = [p for p in photos if p != shown[-1]] or photos
        shown = []
    choice = random.choice(unseen)
    HISTORY.parent.mkdir(parents=True, exist_ok=True)
    HISTORY.write_text("\n".join([*shown, choice]) + "\n")
    return choice


def prepare(path, size, fit, rotate, background):
    """Load an image, apply its EXIF orientation and fit it to the display."""
    if rotate in (90, 270):
        size = size[::-1]
    with Image.open(path) as image:
        image.draft("RGB", (max(size), max(size)))  # decode large JPEGs at reduced scale: far faster on a Pi Zero
        image = ImageOps.exif_transpose(image).convert("RGB")
    image = ImageOps.pad(image, size, color=background) if fit == "pad" else ImageOps.fit(image, size)
    return image.rotate(-rotate, expand=True)


def main():
    args = sys.argv[1:]
    if len(args) > 1 or (args and args[0] in ("-h", "--help")):
        print(__doc__.strip())
        return

    config = load_config()
    rotate = int(config["ROTATE"]) % 360
    if rotate % 90:
        sys.exit("ROTATE must be 0, 90, 180 or 270")

    try:
        display = auto()
    except RuntimeError as error:
        sys.exit(f"{error}\nIs the display attached, and has the Pi been rebooted since installing?")

    if args:
        path = Path(args[0])
    else:
        folder = Path(config["PHOTO_DIR"]).expanduser()
        photos = find_photos(folder)
        if photos:
            path = folder / pick_photo(photos)
        else:
            print(f"No photos in {folder} yet, showing the welcome image")
            path = WELCOME

    print(f"Showing {path}")
    image = prepare(path, (display.width, display.height), config["FIT"], rotate, config["BACKGROUND"])
    try:
        display.set_image(image, saturation=float(config["SATURATION"]))
    except TypeError:  # black/white/red displays have no saturation setting
        display.set_image(image)
    display.show()


if __name__ == "__main__":
    main()
