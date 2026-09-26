#!/usr/bin/env python3
"""Battery mode for a PiSugar: switch the Pi off completely between photo changes.

E-ink keeps its picture with no power at all, so on battery the Pi shows the next photo,
sets the PiSugar's clock to wake it for the change after, and powers off. Woken with the
PiSugar's power button instead, it stays on for a few minutes, and a few more after each
press of the frame's buttons, so you can use them or add photos. It never switches off
while charging, while the screen is updating, or while someone is logged in.

inkyframe.py imports this for the battery level, so it only uses the standard library.
"""

import fcntl
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta
from pathlib import Path

INTERVAL = timedelta(minutes=int(os.environ.get("INTERVAL", "360")))  # set by setup.sh
AWAKE_SECONDS = 5 * 60  # how long to stay on after a manual wake or a button press
EMPTY = 10  # battery %: below this, show a "please charge" screen and stay off
STATE_DIR = Path.home() / ".local/state/inkyframe"
WAKE_FILE = STATE_DIR / "wake-at"  # when we last asked the PiSugar to wake us
PRESSED = STATE_DIR / "pressed"  # touched by buttons.py on every press
INKYFRAME = [sys.executable, str(Path(__file__).with_name("inkyframe.py"))]


def pisugar(command):
    """Ask pisugar-server something, e.g. "get battery" -> "87.5"."""
    with socket.create_connection(("127.0.0.1", 8423), timeout=10) as sock, sock.makefile("rw") as stream:
        stream.write(command + "\n")
        stream.flush()
        for line in stream:
            _, sep, answer = line.strip().partition(": ")
            if sep:  # skip button events, which the server sends to every connection
                return answer
    raise OSError(f"pisugar-server didn't answer {command!r}")


def on_mains():
    plugged = pisugar("get battery_power_plugged")
    if plugged not in ("true", "false"):  # older PiSugar 2 models only report whether they're charging
        plugged = pisugar("get battery_charging")
    return plugged == "true"


def battery():
    """(percent, charging), or None when there's no PiSugar."""
    try:
        return float(pisugar("get battery")), on_mains()
    except (OSError, ValueError):
        return None


def clock_synced():
    command = ["timedatectl", "show", "--property=NTPSynchronized", "--value"]
    return subprocess.run(command, capture_output=True, text=True).stdout.strip() == "yes"


def next_change(after):
    """The first on-the-clock photo change after `after`."""
    midnight = after.replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight + ((after - midnight) // INTERVAL + 1) * INTERVAL


def idle(stay_on_until):
    """True when nothing needs the Pi on: no recent wake or button press, nobody logged in, not charging."""
    pressed = PRESSED.stat().st_mtime if PRESSED.exists() else 0
    if time.time() < max(stay_on_until, pressed + AWAKE_SECONDS):
        return False
    if subprocess.run(["who"], capture_output=True, text=True).stdout.strip():
        return False
    return not on_mains()


def uptime():
    return float(Path("/proc/uptime").read_text().split()[0])


def paused():
    state = STATE_DIR / "state.json"
    return state.exists() and json.loads(state.read_text()).get("paused", False)


def power_off(wake):
    """Power off, with the PiSugar set to wake the Pi at `wake`, or not at all if it's None."""
    if clock_synced():
        pisugar("rtc_pi2rtc")  # keep the PiSugar's clock right while we have internet time
    if wake is None:
        pisugar("rtc_alarm_disable")
    else:
        answer = pisugar(f"rtc_alarm_set {wake.isoformat()} 127")
        if answer != "done":
            raise OSError(f"couldn't set the wake-up alarm: {answer}")
        WAKE_FILE.write_text(str(wake.timestamp()))
    print(f"Switching off until {wake:%H:%M}" if wake else "Switching off until the PiSugar's power button is pressed")
    subprocess.run(["sudo", "-n", "/usr/bin/systemctl", "poweroff"], check=True)


def main():
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    for _ in range(30):  # pisugar-server may still be starting up
        try:
            if not clock_synced():
                pisugar("rtc_rtc2pi")  # no internet time (yet), so set the clock from the PiSugar's
            break
        except OSError:
            time.sleep(2)
    else:
        sys.exit("pisugar-server isn't answering, so staying on")  # never switch off without a way to wake up

    now = time.time()
    alarm = float(WAKE_FILE.read_text()) if WAKE_FILE.exists() else 0
    woken_by_alarm = abs(now - alarm) < 5 * 60
    stay_on_until = now if woken_by_alarm else now + AWAKE_SECONDS
    if uptime() < 5 * 60:  # just booted
        subprocess.run([*INKYFRAME, "auto"], check=False)  # the timer only covers the times the Pi is on

    while True:
        time.sleep(10)
        try:
            if not idle(stay_on_until):
                continue
            if float(pisugar("get battery")) < EMPTY:
                subprocess.run([*INKYFRAME, "lowbattery"], check=False)
                wake = None
            elif paused():
                wake = None  # no point waking up until someone resumes it
            else:
                wake = next_change(datetime.now().astimezone())
                if wake - datetime.now().astimezone() < timedelta(minutes=2):
                    continue  # the timer is about to change the photo; switch off after that
            with open(STATE_DIR / "lock", "w") as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    continue  # a photo is being drawn; try again in a moment
                power_off(wake)
                time.sleep(10 * 60)  # keep hold of the display until the shutdown stops us
        except (OSError, ValueError, subprocess.CalledProcessError) as error:
            print(f"Staying on: {error}")


if __name__ == "__main__":
    main()
