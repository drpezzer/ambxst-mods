#!/usr/bin/env python3
"""Point the EasyEffects output pipeline at a specific sink.

EasyEffects reads its database only at startup: it links no KConfigWatcher and
exposes no D-Bus interface, so an external edit to easyeffectsrc is invisible to
a running instance. Changing the target device therefore means rewriting the
config and restarting the service, which briefly interrupts audio.

Usage:
    easyeffects_output.py <sink-name>      set target and restart EasyEffects
    easyeffects_output.py --get            print the configured target
    easyeffects_output.py --get-capture    print whether "Process all output
                                           streams" is on (true/false)
    easyeffects_output.py --release-streams
                                           turn off "Process all output
                                           streams" so per-app routing sticks
    easyeffects_output.py <sink> --no-restart

The restart only relaunches EasyEffects if it was running; a stopped service
just picks the change up whenever it next starts.
"""

import os
import subprocess
import sys

CONFIG = os.path.expanduser("~/.config/easyeffects/db/easyeffectsrc")
SECTION = "StreamOutputs"


def read_config():
    if not os.path.exists(CONFIG):
        return []
    with open(CONFIG) as fh:
        return fh.read().splitlines()


def get_keys(section_name):
    """Return {key: value} for one section."""
    found, section = {}, None
    for line in read_config():
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            section = stripped[1:-1]
        elif section == section_name and "=" in stripped:
            key, _, value = stripped.partition("=")
            found[key.strip()] = value.strip()
    return found


def get_target():
    """Return (outputDevice, useDefaultOutputDevice)."""
    keys = get_keys(SECTION)
    return keys.get("outputDevice", ""), keys.get("useDefaultOutputDevice", "").lower() == "true"


def get_capture():
    """Whether EasyEffects pulls every output stream into its own sink.
    Defaults to true in EasyEffects' own schema, so a missing key is on."""
    return get_keys("EffectsPipelines").get("processAllOutputs", "true").lower() != "false"


def set_keys(section_name, updates):
    """Write key=value pairs into one section, preserving everything else."""
    lines = read_config()
    out, section, in_section = [], None, False
    wrote = {key: False for key in updates}

    def flush_missing():
        # Append any keys the section did not already contain.
        for key, value in updates.items():
            if not wrote[key]:
                out.append(f"{key}={value}")
                wrote[key] = True

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_section:
                # Leaving the section: make sure both keys were emitted.
                while out and not out[-1].strip():
                    out.pop()
                flush_missing()
                out.append("")
            section = stripped[1:-1]
            in_section = section == section_name
            out.append(line)
            continue

        if in_section and "=" in stripped:
            key = stripped.partition("=")[0].strip()
            if key in updates:
                out.append(f"{key}={updates[key]}")
                wrote[key] = True
                continue

        out.append(line)

    if in_section:
        while out and not out[-1].strip():
            out.pop()
        flush_missing()
    elif not any(l.strip() == f"[{section_name}]" for l in out):
        if out and out[-1].strip():
            out.append("")
        out.append(f"[{section_name}]")
        flush_missing()

    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    with open(CONFIG, "w") as fh:
        fh.write("\n".join(out).rstrip("\n") + "\n")


def set_target(sink):
    """Point the output pipeline at <sink>, pinning it explicitly. Without the
    pin EasyEffects keeps chasing the system default and the choice made here
    is ignored."""
    set_keys(SECTION, {"outputDevice": sink, "useDefaultOutputDevice": "false"})


def release_streams():
    """Stop EasyEffects from capturing every output stream, so per-app routes
    made elsewhere stick. Note the group: this key lives in [EffectsPipelines],
    not [StreamOutputs] — the wrong group is silently ignored."""
    set_keys("EffectsPipelines", {"processAllOutputs": "false"})


def restart():
    # Nothing to restart if it is not running: `easyeffects --quit` with no
    # instance would spin one up just to stop it, and relaunching afterwards
    # would start a service the user had not asked for.
    if subprocess.run(["pgrep", "-x", "easyeffects"], capture_output=True).returncode != 0:
        return
    subprocess.run(["easyeffects", "--quit"], capture_output=True)
    # setsid so the service outlives whichever process invoked this script.
    subprocess.Popen(
        ["setsid", "easyeffects", "--gapplication-service"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
    )


def main():
    args = [a for a in sys.argv[1:]]
    if not args:
        print(__doc__)
        return 1

    if args[0] == "--get":
        device, use_default = get_target()
        print(f"{device}\t{'true' if use_default else 'false'}")
        return 0

    if args[0] == "--get-capture":
        print("true" if get_capture() else "false")
        return 0

    if args[0] == "--release-streams":
        release_streams()
    else:
        set_target(args[0])
    if "--no-restart" not in args:
        restart()
    return 0


if __name__ == "__main__":
    sys.exit(main())
