#!/usr/bin/env python3
"""Inky photo frame: show photos on a Pimoroni Inky display.

Usage: inkyframe [COMMAND | PHOTO]

    next        show the next photo (the default)
    previous    go back to the previous photo
    pause       pause or resume the automatic photo changes
    info        show how to add photos, and what the buttons do
    shutdown    show a switched-off screen and shut the Pi down
    PHOTO       show a specific image file

Photos are picked at random, and every photo is shown once before any repeat.
Settings are read from /etc/inkyframe.conf; environment variables of the same
name override them.
"""

import contextlib
import fcntl
import getpass
import json
import os
import random
import socket
import subprocess
import sys
from pathlib import Path

from inky.auto import auto
from PIL import Image, ImageDraw, ImageFont, ImageOps

CONFIG_FILE = Path("/etc/inkyframe.conf")
DEFAULTS = {
    "PHOTO_DIR": "~/photos",
    "FIT": "crop",  # crop: fill the screen, trimming edges | pad: show the whole photo with borders
    "BACKGROUND": "white",  # border colour for FIT=pad
    "ROTATE": "0",  # clockwise degrees, to match how the frame is mounted
    "SATURATION": "0.5",
    "BUTTON_A": "next",
    "BUTTON_B": "previous",
    "BUTTON_C": "pause",
    "BUTTON_D": "info",
}
COMMANDS = {  # command: how the info screen describes it
    "next": "next photo",
    "previous": "previous photo",
    "pause": "pause / resume",
    "info": "this screen",
    "shutdown": "shut down",
    "none": "nothing",
}
IMAGE_TYPES = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff"}
WELCOME = Path(__file__).with_name("welcome.jpg")
STATE_DIR = Path.home() / ".local/state/inkyframe"
STATE_FILE = STATE_DIR / "state.json"


def load_config():
    config = dict(DEFAULTS)
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text().splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip() in config:
                config[key.strip()] = value.strip().strip("'\"")
    config.update((key, os.environ[key]) for key in DEFAULTS if key in os.environ)
    return config


def load_state():
    # history: photos shown, oldest first; cycle: where the current cycle starts in history;
    # showing: the photo on screen (None for the welcome, info and switched-off screens)
    state = {"history": [], "cycle": 0, "paused": False, "showing": None}
    with contextlib.suppress(OSError, ValueError):  # first run, or a damaged file: start afresh
        state.update(json.loads(STATE_FILE.read_text()))
    return state


def save_state(state):
    temp = STATE_FILE.with_suffix(".tmp")
    temp.write_text(json.dumps(state))
    temp.replace(STATE_FILE)  # atomic, so a power cut can't leave a half-written file


def find_photos(folder):
    """Every image under folder, including subfolders, skipping hidden files."""
    photos = []
    for path in folder.rglob("*"):
        relative = path.relative_to(folder)
        if path.suffix.lower() in IMAGE_TYPES and not any(part.startswith(".") for part in relative.parts):
            photos.append(str(relative))
    return photos


def next_photo(photos, state):
    """A random photo that hasn't been shown yet this cycle."""
    history = state["history"]
    seen = set(history[state["cycle"] :])
    unseen = [p for p in photos if p not in seen]
    if not unseen:  # everything has been shown: start a new cycle
        state["cycle"] = len(history)
        unseen = photos
    choice = random.choice([p for p in unseen if p != state["showing"]] or unseen)
    history.append(choice)
    trim = len(history) - len(photos) - 100  # keep the whole cycle, plus plenty to go back through
    if trim > 0:
        del history[:trim]
        state["cycle"] = max(0, state["cycle"] - trim)
    return choice


def previous_photo(photos, state):
    """Step back through the history. Photos stepped back past come round again later in the cycle."""
    history, available = state["history"], set(photos)
    if history and history[-1] != state["showing"] and history[-1] in available:
        return history[-1]  # e.g. from the info screen, go back to the photo that was up before it
    earlier = [i for i, p in enumerate(history[:-1]) if p in available]
    if not earlier:
        return None
    del history[earlier[-1] + 1 :]
    state["cycle"] = min(state["cycle"], len(history))
    return history[-1]


def fit_photo(path, size, config):
    """Load an image, apply its EXIF orientation and fit it to the screen."""
    with Image.open(path) as image:
        image.draft("RGB", (max(size), max(size)))  # decode large JPEGs at reduced scale: far faster on a Pi Zero
        image = ImageOps.exif_transpose(image).convert("RGB")
    if config["FIT"] == "pad":
        return ImageOps.pad(image, size, color=config["BACKGROUND"])
    return ImageOps.fit(image, size)


def add_pause_badge(image):
    """A pause symbol in the bottom-right corner, so it's clear the photo won't change."""
    draw = ImageDraw.Draw(image)
    radius = min(image.size) // 14
    x, y = image.width - 2 * radius, image.height - 2 * radius
    circle = (x - radius, y - radius, x + radius, y + radius)
    draw.ellipse(circle, fill="black", outline="white", width=max(radius // 8, 1))  # the ring shows up on dark photos
    bar = radius // 3
    for left in (x - 3 * bar // 2, x + bar // 2):
        draw.rectangle((left, y - radius // 2, left + bar, y + radius // 2), fill="white")


def font(size, bold=False):
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf", size)
    except OSError:  # font not installed
        return ImageFont.load_default()


def text_screen(size, title, lines):
    """Black text on white, as large as will fit, but never too small to read."""
    image = Image.new("RGB", size, "white")
    draw = ImageDraw.Draw(image)
    width, height = size
    smallest = max(min(size) // 32, 8)
    for body in range(max(height // 16, smallest), smallest - 1, -1):
        title_font, body_font = font(body * 2, bold=True), font(body)
        widths = [draw.textlength(title, font=title_font), *(draw.textlength(line, font=body_font) for line in lines)]
        block = body * (3 + 1.5 * len(lines))
        if max(widths) <= width * 0.9 and block <= height * 0.9:
            break
    x, y = width * 0.05, (height - block) / 2
    draw.text((x, y), title, font=title_font, fill="black")
    y += body * 3
    for line in lines:
        while len(line) > 3 and draw.textlength(line, font=body_font) > width * 0.9:  # still too wide: shorten it
            line = line[:-4] + "..."
        draw.text((x, y), line, font=body_font, fill="black")
        y += body * 1.5
    return image


def local_ip():
    """The Pi's address on the local network. (Connecting a UDP socket doesn't send anything.)"""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("192.0.2.1", 1))
            return sock.getsockname()[0]
    except OSError:
        return "not connected"


def info_lines(config, state, folder, count):
    with contextlib.suppress(ValueError):
        folder = folder.relative_to(Path.home())
    buttons = [f"{b}   {COMMANDS.get(config[f'BUTTON_{b}'], config[f'BUTTON_{b}'])}" for b in "ABCD"]
    buttons[-1] += "   (hold: shut down)"
    return [
        "Add photos with an SFTP app:",
        f"server {socket.gethostname()}.local or {local_ip()}",
        f"user {getpass.getuser()}, folder {folder}",
        f"{count} photo{'' if count == 1 else 's'}" + (", paused" if state["paused"] else ""),
        "",
        *buttons,
    ]


def choose_photo(command, folder, photos, state):
    """The photo to show for next, previous, pause or auto, or None to leave the screen alone."""
    if not photos:
        print(f"No photos in {folder} yet, showing the welcome image")
        state["showing"] = None
        return WELCOME
    if command == "previous":
        name = previous_photo(photos, state)
        if name is None:
            print("There's no earlier photo to go back to")
            return None
    elif command == "pause" and state["paused"] and state["history"] and state["history"][-1] in photos:
        name = state["history"][-1]  # redraw the current photo with the pause badge
    else:
        name = next_photo(photos, state)
    state["showing"] = name
    return folder / name


def update(command, photo, config, state, rotate):
    """Draw whatever command asks for, and save the new state once it's on screen."""
    try:
        display = auto()
    except RuntimeError as error:
        sys.exit(f"{error}\nIs the display attached, and has the Pi been rebooted since installing?")
    size = (display.height, display.width) if rotate in (90, 270) else (display.width, display.height)
    folder = Path(config["PHOTO_DIR"]).expanduser()

    if command == "info":
        image = text_screen(size, "Inky Photo Frame", info_lines(config, state, folder, len(find_photos(folder))))
        state["showing"] = None
    elif command == "shutdown":
        lines = ["Wait 30 seconds, then it's safe to unplug.", "To start it again, unplug it and plug it back in."]
        image = text_screen(size, "Switched off", lines)
        state["showing"] = None
    else:
        if command == "pause":
            state["paused"] = not state["paused"]
            print("Paused" if state["paused"] else "Resumed")
        if photo:
            path, state["showing"] = photo, None
        else:
            path = choose_photo(command, folder, find_photos(folder), state)
            if path is None:
                return
        print(f"Showing {path}")
        image = fit_photo(path, size, config)
        if state["paused"]:
            add_pause_badge(image)

    image = image.rotate(-rotate, expand=True)
    try:
        display.set_image(image, saturation=float(config["SATURATION"]))
    except TypeError:  # black/white/red displays have no saturation setting
        display.set_image(image)
    display.show()
    save_state(state)


def main():
    command, *args = sys.argv[1:] or ["next"]
    if command in ("-h", "--help"):
        print(__doc__.strip())
        return
    config = load_config()
    if command == "button":  # sent by buttons.py, e.g. "button A"
        command = config.get(f"BUTTON_{''.join(args)}", "none")
    photo = None
    if command not in COMMANDS and command != "auto":  # "auto" is the timer's scheduled change
        photo = Path(command)
        if not photo.is_file():
            sys.exit(f"No such command or photo: {command}\n\n{__doc__.strip()}")
    if command == "none":
        return
    rotate = int(config["ROTATE"]) % 360
    if rotate % 90:
        sys.exit("ROTATE must be 0, 90, 180 or 270")

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with open(STATE_DIR / "lock", "w") as lock:
        try:  # one display update at a time; a scheduled change is skipped rather than queued
            fcntl.flock(lock, fcntl.LOCK_EX | (fcntl.LOCK_NB if command == "auto" else 0))
        except BlockingIOError:
            print("The display is busy, skipping this change")
            return
        state = load_state()
        if command == "auto" and state["paused"]:
            print("Paused, keeping the current photo")
            return
        try:
            update(command, photo, config, state, rotate)
        finally:
            if command == "shutdown":
                subprocess.run(["sudo", "-n", "/usr/bin/systemctl", "poweroff"], check=False)


if __name__ == "__main__":
    main()
