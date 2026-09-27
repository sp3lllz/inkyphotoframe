#!/usr/bin/env python3
"""Sync photos from a Synology Photos album shared with the frame's own DSM account.

Downloads each photo's large preview (a 1280-pixel JPEG that Synology Photos makes) into a
local cache, and deletes photos taken out of the album. inkyframe.py shows the cached photos
while the last sync reached the NAS, and the local photo folder when it didn't.

Settings are in ~/.config/inkyframe/synology.conf, readable only by the frame's user:
    URL=https://192.168.1.20:5001
    USER=photoframe
    PASSWORD=...
    ALBUM=Frame
    VERIFY_CERT=no   (added by setup.sh when the NAS uses its own certificate)
    DEVICE_ID=...    (added after a 2-factor login, so no code is needed again)

Usage: synology.py [CODE]    CODE is a 2-factor code, only needed the first time.

Synology Photos' API isn't officially documented. The calls here follow aitjcize's
esp32-photoframe-server (https://github.com/aitjcize/esp32-photoframe-server, MIT licence;
backend/pkg/synology/client.go), including aashishvanand's fix in its pull request #63, and
N4S4's unofficial API notes (https://github.com/N4S4/synology-photos-api).
"""

import contextlib
import json
import re
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

SETTINGS = Path.home() / ".config/inkyframe/synology.conf"
CACHE = Path.home() / ".cache/inkyframe/synology"
STATUS = CACHE / ".status.json"  # what the last sync found; inkyframe.py reads this
NEEDS_CODE, UNTRUSTED_CERT = 2, 3  # exit codes that setup.sh asks the user about
LOGIN_ERRORS = {
    400: "wrong account name or password",
    401: "the account is disabled",
    402: "the account isn't allowed to log in",
    404: "wrong 2-factor code",
    406: "the account has to set up 2-factor login first: log in to DSM as it once",
    407: "DSM has blocked this Pi's address after failed logins",
}


class SyncError(Exception):
    def __init__(self, message, code=None):
        super().__init__(message)
        self.code = code


class DSM:
    """Just enough of the DSM web API."""

    def __init__(self, url, verify_cert):
        self.url = url.rstrip("/") + "/webapi/entry.cgi"
        self.context = None if verify_cert else ssl._create_unverified_context()
        self.sid = None

    def form(self, api, method, version, params):
        fields = {"api": api, "method": method, "version": version, **params, "_sid": self.sid or ""}
        return urllib.parse.urlencode(fields)

    def get(self, api, method, version, **params):
        """The raw reply, for downloads."""
        url = f"{self.url}?{self.form(api, method, version, params)}"
        with urllib.request.urlopen(url, timeout=30, context=self.context) as reply:
            return reply.read()

    def call(self, api, method, version, **params):
        """The reply's data. Sent as a POST, so the password isn't in a URL."""
        data = self.form(api, method, version, params).encode()
        with urllib.request.urlopen(self.url, data, timeout=30, context=self.context) as reply:
            answer = json.load(reply)
        if not answer.get("success"):
            code = answer.get("error", {}).get("code")
            raise SyncError(f"{api} {method} failed with DSM error {code}", code)
        return answer.get("data", {})


def load_settings():
    settings = {}
    for line in SETTINGS.read_text().splitlines():
        key, sep, value = line.partition("=")
        if sep and not key.startswith("#"):
            settings[key.strip()] = value.strip()
    return settings


def save_setting(key, value):
    lines = [line for line in SETTINGS.read_text().splitlines() if not line.startswith(f"{key}=")]
    SETTINGS.write_text("\n".join([*lines, f"{key}={value}"]) + "\n")


def log_in(dsm, settings, code):
    form = {"account": settings["USER"], "passwd": settings["PASSWORD"], "session": "InkyFrame", "format": "sid"}
    if settings.get("DEVICE_ID"):
        form["device_id"] = settings["DEVICE_ID"]
    if code:  # log in with the code and ask to become a trusted device, as esp32-photoframe-server does
        form.update(otp_code=code, enable_device_token="yes", device_name="Inky photo frame")
    try:
        answer = dsm.call("SYNO.API.Auth", "login", 6, **form)
    except SyncError as error:
        if error.code == 403:
            raise SyncError("the frame's account needs a 2-factor code", NEEDS_CODE) from None
        raise SyncError(f"couldn't log in: {LOGIN_ERRORS.get(error.code, error)}") from None
    dsm.sid = answer["sid"]
    if code and answer.get("did"):
        save_setting("DEVICE_ID", answer["did"])  # this Pi is now a trusted device


def album_items(dsm, passphrase):
    offset = 0
    while True:
        page = dsm.call(
            "SYNO.Foto.Browse.Item",
            "list",
            1,
            passphrase=passphrase,
            offset=offset,
            limit=500,
            additional='["thumbnail"]',
        )["list"]
        yield from page
        if len(page) < 500:
            return
        offset += len(page)


def sync(settings, code):
    """Bring the cache in line with the album. Returns (album name, number of photos)."""
    dsm = DSM(settings["URL"], settings.get("VERIFY_CERT") != "no")
    log_in(dsm, settings, code)
    try:
        # The method name, and reading by passphrase below, are from esp32-photoframe-server's pull request #63.
        shared = dsm.call("SYNO.Foto.Sharing.Misc", "list_shared_with_me_album", 1, offset=0, limit=1000)["list"]
        album = next((a for a in shared if a.get("name", "").casefold() == settings["ALBUM"].casefold()), None)
        if album is None:
            raise SyncError(f"no album called {settings['ALBUM']!r} is shared with {settings['USER']}")
        # A shared album is read through its share passphrase (instead of its id; DSM refuses both).
        wanted = {}
        for item in album_items(dsm, album["passphrase"]):
            key = item.get("additional", {}).get("thumbnail", {}).get("cache_key")
            if key and item.get("type") != "video":  # the key changes when a photo is edited, so it names the file
                safe_key = re.sub(r"[^\w-]", "_", key)
                wanted[f"synology-{safe_key}.jpg"] = (item["id"], key)
        for name, (item_id, key) in wanted.items():
            path = CACHE / name
            if path.exists():
                continue
            data = dsm.get(  # parameters as Synology Photos' web page sends them, per esp32-photoframe-server
                "SYNO.Foto.Thumbnail",
                "get",
                2,
                id=item_id,
                cache_key=json.dumps(key),
                type='"item"',
                size='"xl"',
                passphrase=json.dumps(album["passphrase"]),
            )
            if data.startswith(b"\xff\xd8"):  # a JPEG, rather than an error
                path.with_suffix(".part").write_bytes(data)
                path.with_suffix(".part").replace(path)
            else:
                print(f"No preview yet for photo {item_id}; will try again next time")
        for path in CACHE.iterdir():
            if path.name not in wanted and not path.name.startswith("."):
                path.unlink()  # taken out of the album (or a download that was cut off)
        return album["name"], sum((CACHE / name).exists() for name in wanted)
    finally:
        with contextlib.suppress(OSError, SyncError):
            dsm.call("SYNO.API.Auth", "logout", 6, session="InkyFrame")


def sync_when_reachable(settings, code):
    """sync(), retrying for a while if the NAS can't be reached: just after boot, Wi-Fi may still be connecting."""
    for attempt in range(10):
        try:
            return sync(settings, code)
        except urllib.error.HTTPError as error:
            raise SyncError(f"the NAS answered with HTTP error {error.code}; is the address right?") from None
        except urllib.error.URLError as error:
            if isinstance(error.reason, ssl.SSLCertVerificationError):
                raise SyncError("the NAS's certificate isn't trusted", UNTRUSTED_CERT) from None
            problem = error.reason
        except OSError as error:  # e.g. a timeout part-way through
            problem = error
        except (ValueError, KeyError) as error:
            raise SyncError(f"unexpected reply from the NAS: {error!r}") from None
        if attempt < 9:
            time.sleep(3)
    raise SyncError(f"couldn't reach the NAS: {problem}")


def main():
    code = sys.argv[1] if len(sys.argv) > 1 else None
    CACHE.mkdir(parents=True, exist_ok=True)
    settings = load_settings()
    try:
        album, count = sync_when_reachable(settings, code)
    except SyncError as error:
        status = {"ok": False, "album": settings.get("ALBUM"), "error": str(error), "time": time.time()}
        STATUS.write_text(json.dumps(status))
        print(f"Couldn't sync from Synology, so showing local photos: {error}", file=sys.stderr)
        sys.exit(error.code if error.code in (NEEDS_CODE, UNTRUSTED_CERT) else 1)
    STATUS.write_text(json.dumps({"ok": True, "album": album, "photos": count, "time": time.time()}))
    print(f"Synced {count} photos from Synology album {album!r}")


if __name__ == "__main__":
    main()
