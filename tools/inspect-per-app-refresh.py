"""Temporary refresh diagnostic, with original configuration restored."""
import importlib.util
import json
import sys
from pathlib import Path
import time

if '--apply' not in sys.argv:
    raise SystemExit('Pass --apply to authorize temporary refresh diagnostics.')

spec = importlib.util.spec_from_file_location('live', Path(__file__).with_name('test-per-app-device.py'))
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)
initial = live.ctl('GET app.controls')['config']
vendor = {key: live.shell('settings get secure ' + key, root=True) for key in ['user_refresh_rate', 'miui_refresh_rate']}
package = 'com.android.settings'
original = next((p for p in initial['profiles'] if p['package'] == package and p['user'] == 0), None)
try:
    live.shell('am start -W -a android.settings.SETTINGS -f 0x10008000')
    live.ctl('SET app.enabled 1')
    print(live.ctl('SET app.profile ' + json.dumps({'user': 0, 'package': package, 'profile': {'enabled': True, 'refresh': 60}}, separators=(',', ':'))))
    for key, value in vendor.items():
        if value != 'null':
            live.shell('settings put secure ' + key + ' 60', root=True)
    live.shell('input swipe 650 1900 650 500 450')
    for delay in [0, .3, 1, 2]:
        time.sleep(delay)
        print('Delay', delay, flush=True)
        print(live.shell('cmd display get-user-preferred-display-mode 0; settings get system min_refresh_rate; settings get system peak_refresh_rate', root=True), flush=True)
        display = live.shell('dumpsys display', root=True)
        for line in display.splitlines():
            if 'DisplayDeviceInfo{"Built-in' in line:
                print(line[:220], flush=True)
        if delay == 2:
            start = display.find('DisplayModeDirector')
            print(display[start:start + 10000], flush=True)
            print(live.shell('settings list system | grep -Ei "refresh|fps"; settings list secure | grep -Ei "refresh|fps"', root=True), flush=True)
        print(live.ctl('GET app.controls')['error'], flush=True)
finally:
    for key, value in vendor.items():
        live.shell('settings ' + ('delete secure ' + key if value == 'null' else 'put secure ' + key + ' ' + value), root=True)
    live.ctl('SET app.enabled 0')
    if original:
        live.ctl('SET app.profile ' + json.dumps(original, separators=(',', ':')))
    else:
        live.ctl('ACTION app.reset 0 ' + package)
    live.ctl('SET app.enabled ' + ('1' if initial['enabled'] else '0'))
    live.shell('am start -n io.github.neeschal.rodinessential/.RodinActivity')
    assert live.ctl('GET app.controls')['config'] == initial
