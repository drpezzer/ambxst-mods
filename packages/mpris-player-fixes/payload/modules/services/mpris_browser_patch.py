#!/usr/bin/env python3
"""mpris-player-fixes: browser patch helper.

    mpris_browser_patch.py status   -> one JSON object describing every
                                       Firefox-family browser found, whether
                                       Violentmonkey and the userscript are
                                       installed, and an overall "patched" flag
    mpris_browser_patch.py patch    -> guided install in the browser the user
                                       actually uses (the desktop default if it
                                       is Firefox-family, else the most recently
                                       used profile): opens the Violentmonkey
                                       add-on page, then the userscript URL, and
                                       waits for each to land; one JSON line per
                                       step

Nothing here writes into a browser profile. Firefox does not allow an
extension or a userscript to be installed from outside the browser (add-ons
must come through the browser's own install prompt, and Violentmonkey keeps
its scripts in the extension's private storage), so the closest thing to
"patch it for me" is opening the two pages in the right browser and detecting
when the user has clicked through. Detection reads copies of profile files
only.

Stdlib only. Runs on any Linux with python3; browsers are found by their
profile directories (native, Flatpak, Snap).
"""
import configparser
import glob
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

VM_ID = "{aecec67f-0d10-4fa7-b7c7-609a2db280cf}"
VM_URL = "https://addons.mozilla.org/firefox/addon/violentmonkey/"
SCRIPT_URL = ("https://raw.githubusercontent.com/drpezzer/ambxst-mods/main/"
              "packages/mpris-player-fixes/extras/youtube-mpris-position.user.js")
# The userscript's @namespace; it appears in Violentmonkey's stored metadata
# and source for the script, whichever version is installed.
SCRIPT_MARK = "drpezzer.ambxst-mods"
WAIT_SECONDS = 300

HOME = os.path.expanduser("~")

# name, profile roots, launch commands (first that resolves wins)
BROWSERS = [
    ("Zen", [HOME + "/.zen", HOME + "/.config/zen"], [["zen-browser"], ["zen"]]),
    ("Zen (Flatpak)", [HOME + "/.var/app/app.zen_browser.zen/.zen"],
     [["flatpak", "run", "app.zen_browser.zen"]]),
    ("Firefox", [HOME + "/.mozilla/firefox", HOME + "/snap/firefox/common/.mozilla/firefox"],
     [["firefox"], ["firefox-esr"], ["firefox-developer-edition"], ["firefox-nightly"], ["firefox-beta"]]),
    ("Firefox (Flatpak)", [HOME + "/.var/app/org.mozilla.firefox/.mozilla/firefox"],
     [["flatpak", "run", "org.mozilla.firefox"]]),
    ("LibreWolf", [HOME + "/.librewolf"], [["librewolf"]]),
    ("LibreWolf (Flatpak)", [HOME + "/.var/app/io.gitlab.librewolf-community/.librewolf"],
     [["flatpak", "run", "io.gitlab.librewolf-community"]]),
    ("Floorp", [HOME + "/.floorp"], [["floorp"]]),
    ("Waterfox", [HOME + "/.waterfox"], [["waterfox"]]),
]


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


# ---------------------------------------------------------------- profiles --

def read_ini(path):
    cp = configparser.RawConfigParser()
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except Exception:
        return None
    return cp


def profile_dirs(root):
    """Profiles the browser actually uses under this root, most relevant
    first: installs.ini defaults (what a running install opens), then the
    profiles.ini Default=1 entry, then anything else that has been launched."""
    found = []

    def add(rel_or_abs, is_relative=True):
        p = os.path.join(root, rel_or_abs) if is_relative else rel_or_abs
        p = os.path.normpath(p)
        if os.path.isdir(p) and p not in found:
            found.append(p)

    inst = read_ini(os.path.join(root, "installs.ini"))
    if inst:
        for sec in inst.sections():
            if inst.has_option(sec, "Default"):
                add(inst.get(sec, "Default"))
    prof = read_ini(os.path.join(root, "profiles.ini"))
    if prof:
        entries = []
        for sec in prof.sections():
            if not sec.startswith("Profile") or not prof.has_option(sec, "Path"):
                continue
            rel = prof.get(sec, "IsRelative", fallback="1") == "1"
            default = prof.get(sec, "Default", fallback="0") == "1"
            entries.append((default, prof.get(sec, "Path"), rel))
        for default, path, rel in sorted(entries, key=lambda e: not e[0]):
            full = os.path.normpath(os.path.join(root, path) if rel else path)
            # a profile that was never launched has no extensions.json; keep
            # it only if it is the declared default and nothing else exists
            if os.path.exists(os.path.join(full, "extensions.json")) or (default and not found):
                add(path, rel)
    return found


def launch_command(cmds):
    for argv in cmds:
        if argv[0] == "flatpak":
            if shutil.which("flatpak") and subprocess.run(
                    ["flatpak", "info", argv[2]], stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL).returncode == 0:
                return argv
        elif shutil.which(argv[0]):
            return argv
    return None


# ------------------------------------------------------------- detection --

def violentmonkey_installed(profile):
    try:
        with open(os.path.join(profile, "extensions.json"), encoding="utf-8") as fh:
            data = json.load(fh)
    except Exception:
        return False
    for addon in data.get("addons", []):
        if addon.get("id") == VM_ID and addon.get("active", False) and not addon.get("appDisabled", False):
            return True
    return False


def extension_uuid(profile, addon_id):
    """Internal UUID Firefox gave the extension; its storage lives under it."""
    for name in ("prefs.js", "user.js"):
        try:
            with open(os.path.join(profile, name), encoding="utf-8", errors="ignore") as fh:
                for line in fh:
                    if "extensions.webextensions.uuids" not in line:
                        continue
                    m = re.search(r'"extensions\.webextensions\.uuids",\s*"(.*)"\);', line)
                    if not m:
                        continue
                    try:
                        mapping = json.loads(m.group(1).replace('\\"', '"').replace("\\\\", "\\"))
                    except Exception:
                        continue
                    if addon_id in mapping:
                        return mapping[addon_id]
        except Exception:
            continue
    return None


def snappy_decompress(buf):
    """Raw snappy block decoder (Firefox compresses IndexedDB values with it)."""
    i = 0
    n = 0
    shift = 0
    while True:
        c = buf[i]
        i += 1
        n |= (c & 0x7F) << shift
        if c < 0x80:
            break
        shift += 7
    out = bytearray()
    while i < len(buf):
        tag = buf[i] & 3
        if tag == 0:
            length = buf[i] >> 2
            i += 1
            if length >= 60:
                nbytes = length - 59
                length = int.from_bytes(buf[i:i + nbytes], "little")
                i += nbytes
            length += 1
            out += buf[i:i + length]
            i += length
        else:
            if tag == 1:
                length = ((buf[i] >> 2) & 7) + 4
                offset = ((buf[i] >> 5) << 8) | buf[i + 1]
                i += 2
            elif tag == 2:
                length = (buf[i] >> 2) + 1
                offset = int.from_bytes(buf[i + 1:i + 3], "little")
                i += 3
            else:
                length = (buf[i] >> 2) + 1
                offset = int.from_bytes(buf[i + 1:i + 5], "little")
                i += 5
            for _ in range(length):
                out.append(out[-offset])
    return bytes(out)


def userscript_installed(profile):
    """Look for the script in a COPY of Violentmonkey's storage.local
    IndexedDB (the live one is locked by the browser). Strings inside are
    UTF-16 or Latin-1 depending on content, so both spellings are checked."""
    uuid = extension_uuid(profile, VM_ID)
    if not uuid:
        return False
    marks = (SCRIPT_MARK.encode("latin-1"), SCRIPT_MARK.encode("utf-16-le"))
    pattern = os.path.join(profile, "storage", "default", "moz-extension+++" + uuid + "*", "idb", "*.sqlite")
    for db in glob.glob(pattern):
        tmp = tempfile.mkdtemp(prefix="ambxst-mpris-")
        try:
            base = os.path.join(tmp, "db.sqlite")
            shutil.copyfile(db, base)
            for suffix in ("-wal", "-shm"):
                if os.path.exists(db + suffix):
                    shutil.copyfile(db + suffix, base + suffix)
            con = sqlite3.connect(base)
            try:
                rows = con.execute("SELECT data FROM object_data").fetchall()
            except sqlite3.Error:
                rows = []
            con.close()
            for (data,) in rows:
                if not data:
                    continue
                try:
                    plain = snappy_decompress(bytes(data))
                except Exception:
                    continue
                if any(m in plain for m in marks):
                    return True
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    return False


def last_used(profile):
    """When the profile was last active: the session backup is rewritten every
    few seconds while the browser runs; places/prefs cover older builds."""
    latest = 0.0
    for rel in ("sessionstore-backups/recovery.jsonlz4", "sessionstore-backups/recovery.baklz4",
                "sessionstore.jsonlz4", "places.sqlite", "prefs.js"):
        try:
            latest = max(latest, os.path.getmtime(os.path.join(profile, rel)))
        except OSError:
            pass
    return latest


def default_browser_family():
    """Family name of the desktop's default browser, if it is one of ours."""
    try:
        out = subprocess.run(["xdg-settings", "get", "default-web-browser"],
                             capture_output=True, text=True, timeout=5).stdout.strip().lower()
    except Exception:
        return None
    for key, family in (("librewolf", "LibreWolf"), ("floorp", "Floorp"), ("waterfox", "Waterfox"),
                        ("zen", "Zen"), ("firefox", "Firefox")):
        if key in out:
            return family
    return None


def scan():
    browsers = []
    for name, roots, cmds in BROWSERS:
        for root in roots:
            profiles = profile_dirs(root) if os.path.isdir(root) else []
            if not profiles:
                continue
            argv = launch_command(cmds)
            for profile in profiles:
                vm = violentmonkey_installed(profile)
                browsers.append({
                    "name": name,
                    "family": name.split(" (")[0],
                    "profile": profile,
                    "launch": argv,
                    "lastUsed": last_used(profile),
                    "violentmonkey": vm,
                    "script": vm and userscript_installed(profile),
                })
    return browsers


def choose_primary(browsers):
    """The browser the user actually uses: the desktop default if it is a
    Firefox-family browser we found, otherwise the most recently used
    profile. Only launchable browsers qualify."""
    launchable = [b for b in browsers if b["launch"]]
    if not launchable:
        return None
    family = default_browser_family()
    pool = [b for b in launchable if b["family"] == family] or launchable
    return max(pool, key=lambda b: b["lastUsed"])


def status(browsers=None):
    browsers = scan() if browsers is None else browsers
    primary = choose_primary(browsers)
    for b in browsers:
        b["primary"] = b is primary
    return {
        "browsers": browsers,
        "browserFound": primary is not None,
        "primary": primary["name"] if primary else "",
        "profile": primary["profile"] if primary else "",
        "patched": bool(primary and primary["script"]),
    }


# ---------------------------------------------------------------- patching --

def open_url(browser, url):
    argv = list(browser["launch"]) + ["--new-tab", url]
    subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True)


def wait_for(check, profile, seconds):
    deadline = time.time() + seconds
    while time.time() < deadline:
        if check(profile):
            return True
        time.sleep(2)
    return False


def patch():
    browsers = scan()
    primary = choose_primary(browsers)
    if primary is None:
        emit({"step": "no-browser"})
        return 3
    targets = [primary] if not primary["script"] else []
    if not targets:
        emit({"step": "done", **status(browsers)})
        return 0
    for b in targets:
        if not b["violentmonkey"]:
            emit({"step": "violentmonkey", "browser": b["name"]})
            open_url(b, VM_URL)
            if not wait_for(violentmonkey_installed, b["profile"], WAIT_SECONDS):
                emit({"step": "timeout", "browser": b["name"], "waiting": "violentmonkey"})
                return 2
            b["violentmonkey"] = True
            # Violentmonkey opens its own welcome tab; give it a moment to
            # settle before the install page lands on top of it.
            time.sleep(3)
        emit({"step": "userscript", "browser": b["name"]})
        open_url(b, SCRIPT_URL)
        if not wait_for(userscript_installed, b["profile"], WAIT_SECONDS):
            emit({"step": "timeout", "browser": b["name"], "waiting": "userscript"})
            return 2
        b["script"] = True
    emit({"step": "done", **status(browsers)})
    return 0


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    if cmd == "status":
        emit(status())
        return 0
    if cmd == "patch":
        return patch()
    sys.stderr.write(__doc__)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
