#!/usr/bin/env python3
"""Run inkyframe commands from the four buttons on the side of an Inky Impression.

Tapping a button runs the command set for it in /etc/inkyframe.conf (BUTTON_A to
BUTTON_D), and holding D for 3 seconds shuts the Pi down. This runs as a service
and sleeps until a button is pressed; the display work happens in inkyframe.py.
"""

import subprocess
import sys
import time
from datetime import timedelta
from pathlib import Path

import gpiod
import gpiodevice
from gpiod.line import Bias, Direction, Edge, Value
from smbus2 import SMBus

INKYFRAME = [sys.executable, str(Path(__file__).with_name("inkyframe.py"))]
HOLD_SECONDS = 3


def display_width():
    """The display's width in pixels, read from its EEPROM (0 if it can't be read)."""
    try:
        with SMBus(1) as bus:
            bus.write_i2c_block_data(0x50, 0x00, [0x00])
            return int.from_bytes(bytes(bus.read_i2c_block_data(0x50, 0, 2)), "little")
    except OSError:
        return 0


def main():
    # BCM pin numbers for buttons A to D. The 13.3" display uses GPIO16 itself, so its C button is on GPIO25.
    pins = {"A": 5, "B": 6, "C": 25 if display_width() >= 1600 else 16, "D": 24}
    chip = gpiodevice.find_chip_by_platform()
    buttons = {chip.line_offset_from_id(pin): label for label, pin in pins.items()}
    pressed = gpiod.LineSettings(
        direction=Direction.INPUT,
        bias=Bias.PULL_UP,
        edge_detection=Edge.FALLING,
        debounce_period=timedelta(milliseconds=20),
    )
    request = chip.request_lines(consumer="inkyframe-buttons", config=dict.fromkeys(buttons, pressed))
    print("Waiting for button presses")

    running = None
    while True:
        for event in request.read_edge_events():
            line, label = event.line_offset, buttons[event.line_offset]
            # A tap or a hold? Wait for the button to come back up, for up to HOLD_SECONDS.
            give_up = time.monotonic() + HOLD_SECONDS
            while request.get_value(line) == Value.INACTIVE and time.monotonic() < give_up:
                time.sleep(0.05)
            if label == "D" and request.get_value(line) == Value.INACTIVE:
                print("D held: shutting down")
                subprocess.Popen([*INKYFRAME, "shutdown"])
            elif running and running.poll() is None:
                print(f"{label} pressed, but the screen is still updating, so it was ignored")
            else:
                print(f"{label} pressed")
                running = subprocess.Popen([*INKYFRAME, "button", label])


if __name__ == "__main__":
    main()
