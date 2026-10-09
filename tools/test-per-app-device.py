"""Opt-in live test. Reverts its own profile and leaves global preferences intact."""
import argparse
import json
import shlex
import subprocess
import time

CTL = "/data/adb/modules/nees_rodin_essential_backend/bin/rodin_ctl"
PACKAGE = "com.android.settings"

def shell(command, root=False):
    if root:
        command = "su -c " + shlex.quote(command)
    result = subprocess.run(["adb", "shell", command], capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout.strip()

def ctl(command):
    result = shell(CTL + " " + shlex.quote(command), root=True)
    if not result.startswith("OK "):
        raise RuntimeError(result)
    body = result[3:]
    return json.loads(body) if body.startswith(("{", "[")) else body

def wait_owner(expected, timeout=12):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = ctl("GET app.controls")
        owner = (status.get("owner") or {}).get("package")
        if owner == expected and not status["error"]:
            return status
        time.sleep(0.15)
    raise RuntimeError("Profile transition did not acknowledge: " + json.dumps(status))

def preferences():
    raw = shell("cat /data/adb/rodin-essential/state.conf", root=True)
    return dict(line.split("=", 1) for line in raw.splitlines() if "=" in line)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true", help="Allow temporary profile writes and app launches")
    args = parser.parse_args()
    if not args.apply:
        parser.error("Live changes require --apply")
    initial = ctl("GET app.controls")
    if initial["config"]["enabled"] or initial["config"]["profiles"]:
        raise RuntimeError("This test requires a fresh, disabled profile store; existing profiles will not be overwritten")
    before = preferences()
    governor = shell("cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor", root=True)
    thermal_before = shell("cat /sys/devices/virtual/thermal/thermal_message/sconfig", root=True)
    caps = ctl("GET app.capabilities")
    table = caps["cpu"]["0"]["frequencies"]
    minimum, maximum = table[0], table[len(table) // 2]
    profile = {"enabled": True, "gpu": 2, "touch": 2, "refresh": 60,
               "cpu": {"0": {"range": [minimum, maximum]}}}
    print("Temporary Settings profile:", json.dumps(profile), flush=True)
    try:
        ctl("SET app.profile " + json.dumps({"user": 0, "package": PACKAGE, "profile": profile}, separators=(",", ":")))
        ctl("SET app.enabled 1")
        shell("am start -W -a android.settings.SETTINGS -f 0x10008000")
        active = wait_owner(PACKAGE)
        print("Foreground activation:", json.dumps(active), flush=True)
        snapshot = ctl("GET snapshot")
        print("Effective snapshot:", snapshot, flush=True)
        assert shell("cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor", root=True) == governor, "Range changed governor"
        assert int(shell("cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq", root=True)) == maximum * 1000, "CPU range did not apply"
        conflict = shell(CTL + " " + shlex.quote("SET perf 0"), root=True)
        assert conflict.startswith("ERR This control is owned"), conflict
        print("Conflicting global write rejected", flush=True)
        shell("am force-stop io.github.neeschal.rodinessential")
        wait_owner(PACKAGE)
        print("Profile remains active with Rodin Essential force-closed", flush=True)
        old_pid = shell("pidof rodin_daemon", root=True)
        shell("kill " + old_pid, root=True)
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            new_pid = shell("pidof rodin_daemon || true", root=True)
            if new_pid and new_pid != old_pid:
                try:
                    active = wait_owner(PACKAGE, timeout=2)
                    break
                except RuntimeError:
                    pass
            time.sleep(0.2)
        else:
            raise RuntimeError("Daemon restart did not restore the active saved profile")
        assert active["config"]["profiles"][0]["profile"] == profile
        print("Saved profile recovered after daemon restart", flush=True)
        shell("input keyevent KEYCODE_HOME", root=True)
        released = wait_owner(None)
        print("Launcher exit:", json.dumps(released), flush=True)
        after = preferences()
        for key in ("touch", "perf", "gpu_min_freq_mhz", "gpu_max_freq_mhz", "gpu_governor", "cpu_min_freq0", "cpu_max_freq0", "cpu0"):
            assert after[key] == before[key], f"Global preference changed: {key}: {before[key]} -> {after[key]}"
        assert shell("cat /sys/devices/system/cpu/cpufreq/policy0/scaling_governor", root=True) == governor
        assert shell("cat /sys/devices/virtual/thermal/thermal_message/sconfig", root=True) == thermal_before, "Original thermal mode was not restored"
        print("Saved global preferences and governor preserved", flush=True)
        shell("am start -W -a android.settings.SETTINGS -f 0x10008000")
        wait_owner(PACKAGE)
        ctl("ACTION app.reset 0 " + PACKAGE)
        wait_owner(None)
        print("Resetting the active app releases its controls", flush=True)
    finally:
        deadline = time.monotonic() + 30
        while True:
            try:
                ctl("SET app.enabled 0")
                break
            except RuntimeError:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.2)
        ctl("ACTION app.reset 0 " + PACKAGE)
        cleanup = ctl("GET app.controls")
        assert not cleanup["controls"] and cleanup["error"] is None, "Profile recovery is still pending: " + json.dumps(cleanup)
        shell("am start -n io.github.neeschal.rodinessential/.RodinActivity")
        print("Temporary test profile removed; Per-App Controls left disabled", flush=True)

if __name__ == "__main__":
    main()
