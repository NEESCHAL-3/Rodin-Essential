"""Opt-in per-control live regression; preserves pre-existing app profiles."""
import importlib.util
import json
import re
from pathlib import Path
import sys
import time

spec = importlib.util.spec_from_file_location('live', Path(__file__).with_name('test-per-app-device.py'))
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)

if '--apply' not in sys.argv:
    raise SystemExit('Pass --apply to authorize temporary foreground profiles.')

initial = live.ctl('GET app.controls')['config']
package = sys.argv[sys.argv.index('--package') + 1] if '--package' in sys.argv else 'com.android.settings'
component = live.shell('cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.LAUNCHER ' + package).splitlines()[-1]
assert component.startswith(package + '/'), 'No launchable test activity'
launch = 'am start -W -n ' + component + ' -f 0x10008000'
original = next((p for p in initial['profiles'] if p['user'] == 0 and p['package'] == package), None)
before = live.preferences()
refresh_before = live.shell('settings get system min_refresh_rate; settings get system peak_refresh_rate; settings get secure user_refresh_rate; settings get secure miui_refresh_rate; cmd display get-user-preferred-display-mode 0', root=True)
smart_before = live.shell('settings get system is_smart_fps', root=True)
checkpoint = Path(__file__).resolve().parents[1] / 'out/per-app-development/per-app-retest-baseline.json'
checkpoint.parent.mkdir(parents=True, exist_ok=True)
checkpoint.write_text(json.dumps({'config': initial, 'preferences': before,
                                 'refresh': refresh_before, 'smart_fps': smart_before},
                                indent=2), encoding='utf-8')
print('Saved recovery baseline: ' + str(checkpoint), flush=True)
adaptive = '--adaptive-baseline' in sys.argv
if adaptive:
    assert smart_before in ['0', '1'], 'Adaptive baseline test requires existing OEM setting'
gpu_profile = int(sys.argv[sys.argv.index('--gpu-profile') + 1]) if '--gpu-profile' in sys.argv else 2
assert gpu_profile in [0, 1, 2, 3], 'Invalid GPU test profile'
cases = [
    {'touch': 2}, {'gpu': gpu_profile}, {'refresh': 60}, {'refresh': 90}, {'refresh': 120},
    {'cpu': {'0': {'range': [300, 1200]}}},
    {'cores': 253},
    {'touch': 2, 'gpu': gpu_profile, 'refresh': 60, 'cpu': {'0': {'range': [300, 1200]}}, 'cores': 253},
]
gpu_all = '--gpu-all' in sys.argv
if gpu_all:
    cases = [{'gpu': mode} for mode in [0, 1, 2, 3]]
    gpu_start = float(live.shell('cat /proc/uptime', root=True).split()[0])

def check_gpu_health():
    raw = live.shell('dmesg', root=True)
    errors = []
    for line in raw.splitlines():
        stamp = re.match(r'\[\s*([0-9.]+)\]', line)
        if stamp and float(stamp.group(1)) >= gpu_start and 'mali' in line.lower():
            if re.search(r'fence.*timeout|STATUS_UPDATE.*timed out|Resetting GPU|Reset complete', line, re.I):
                errors.append(line)
    assert not errors, 'New GPU driver fault: ' + '\n'.join(errors)
    temperature = float(live.shell('cat /sys/class/power_supply/battery/temp', root=True)) / 10
    assert temperature < 43, 'Stopping GPU test at battery temperature ' + str(temperature)

failures = []
def normalized_refresh(value):
    # Android reports an unset preferred mode as either null or -1 -1 0.0.
    # Keep all actual settings and explicit modes exact; only normalize unset.
    return value.replace('User preferred display mode: -1 -1 0.0',
                         'User preferred display mode: null')

try:
    if adaptive:
        live.shell('settings put system is_smart_fps 1', root=True)
    live.shell(launch)
    live.ctl('SET app.enabled 1')
    for controls in cases:
        if gpu_all:
            check_gpu_health()
        payload = {'user': 0, 'package': package, 'profile': {'enabled': True, **controls}}
        state = live.ctl('SET app.profile ' + json.dumps(payload, separators=(',', ':')))
        time.sleep(.3)
        state = live.ctl('GET app.controls')
        snapshot = live.ctl('GET snapshot') if not state['error'] else {}
        if isinstance(snapshot, str):
            snapshot = dict(field.split('=', 1) for field in snapshot.split(';') if '=' in field)
        if 'refresh' in controls:
            live.shell('input swipe 650 1900 650 500 450')
            time.sleep(3)
            display = next(line for line in live.shell('dumpsys display', root=True).splitlines() if 'DisplayDeviceInfo{"Built-in' in line)
            actual = float(re.search(r'renderFrameRate ([0-9.]+)', display).group(1))
            assert abs(actual - controls['refresh']) < .1, 'Actual display missed requested Hz: ' + display[:230]
            print('DISPLAY: ' + display[:190], flush=True)
            if adaptive:
                assert live.shell('settings get system is_smart_fps', root=True) == '0', 'Adaptive mode was not borrowed'
        fields = ['touch', 'touch_ack', 'perf', 'perf_verified', 'cpu_online_mask', 'cpu_min_freq0', 'cpu_max_freq0', 'display_hz_x10', 'display_max_hz_x10']
        print(json.dumps({'case': controls, 'status': state, 'snapshot': {k: snapshot.get(k) for k in fields}}), flush=True)
        if state['error'] or (state.get('owner') or {}).get('package') != package:
            failures.append(controls)
        else:
            if 'touch' in controls:
                assert snapshot.get('touch') == str(controls['touch']) and snapshot.get('touch_ack') == '1', 'Touch driver did not acknowledge'
            if 'gpu' in controls:
                assert snapshot.get('perf') == str(controls['gpu']) and snapshot.get('perf_verified') == '1', 'GPU profile did not verify'
                if gpu_all:
                    for _ in range(3):
                        live.shell('input swipe 650 1900 650 500 450')
                        time.sleep(1)
                        check_gpu_health()
                    print('GPU READBACK: ' + live.shell('cat /sys/class/misc/mali0/device/devfreq/13000000.mali/min_freq; cat /sys/class/misc/mali0/device/devfreq/13000000.mali/max_freq; cat /sys/class/misc/mali0/device/devfreq/13000000.mali/governor; cat /sys/class/misc/mali0/device/power_policy', root=True), flush=True)
            if 'cores' in controls:
                assert live.shell('cat /sys/devices/system/cpu/online', root=True) == '0,2-7'
            if 'cpu' in controls:
                assert live.shell('cat /sys/devices/system/cpu/cpufreq/policy0/scaling_max_freq', root=True) == '1200000'
            live.shell('am force-stop io.github.neeschal.rodinessential')
            assert (live.ctl('GET app.controls').get('owner') or {}).get('package') == package, 'UI closure lost profile'
            if len(controls) > 1:
                pid = live.shell('pidof rodin_daemon', root=True)
                live.shell('kill ' + pid, root=True)
                deadline = time.monotonic() + 30
                while time.monotonic() < deadline:
                    try:
                        state = live.ctl('GET app.controls')
                        if (state.get('owner') or {}).get('package') == package and not state['error']:
                            break
                    except RuntimeError:
                        pass
                    time.sleep(.3)
                else:
                    raise RuntimeError('Daemon restart failed to recover active profile')
                print('PASS: combined profile recovered after daemon restart', flush=True)
        live.shell('input keyevent KEYCODE_HOME')
        live.wait_owner(None)
        if gpu_all:
            check_gpu_health()
            restored = live.ctl('GET snapshot')
            fields = dict(field.split('=', 1) for field in restored.split(';') if '=' in field)
            assert fields.get('perf') == before.get('perf'), 'Global GPU profile was not restored'
        if failures:
            raise RuntimeError('Stopping at rejected profile: ' + json.dumps(controls))
        if adaptive:
            assert live.shell('settings get system is_smart_fps', root=True) == '1', 'OEM adaptive mode was not restored on exit'
        live.shell(launch)
finally:
    live.ctl('SET app.enabled 0')
    if adaptive:
        live.shell('settings put system is_smart_fps ' + smart_before, root=True)
    if original:
        live.ctl('SET app.profile ' + json.dumps(original, separators=(',', ':')))
    else:
        live.ctl('ACTION app.reset 0 ' + package)
    live.ctl('SET app.enabled ' + ('1' if initial['enabled'] else '0'))
    live.shell('am start -n io.github.neeschal.rodinessential/.RodinActivity')
    after = live.preferences()
    for key in ['touch', 'perf', 'cpu_online_mask', 'cpu_manual', 'cpu_min_freq0', 'cpu_max_freq0']:
        assert before.get(key) == after.get(key), 'Saved global preference changed: ' + key
    assert live.ctl('GET app.controls')['config'] == initial, 'Profile configuration was not restored'
    refresh_after = live.shell('settings get system min_refresh_rate; settings get system peak_refresh_rate; settings get secure user_refresh_rate; settings get secure miui_refresh_rate; cmd display get-user-preferred-display-mode 0', root=True)
    assert normalized_refresh(refresh_after) == normalized_refresh(refresh_before), 'Refresh baseline was not restored'
    assert live.shell('settings get system is_smart_fps', root=True) == smart_before, 'OEM adaptive setting was not restored'
if failures:
    raise SystemExit('Failed control groups: ' + json.dumps(failures))
print('PASS: per-control activation, app exits, and original configuration restoration', flush=True)
