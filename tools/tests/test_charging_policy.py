"""Regression coverage for the porter's battery-manager traversal denial."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ChargingPolicyTests(unittest.TestCase):
    def test_aosp_parent_permission_is_search_only(self):
        source = (ROOT / 'android/aosp/sepolicy/vendor/rodin_daemon.te').read_text()
        rules = [line.strip() for line in source.splitlines()
                 if line.strip().startswith('allow ') and 'sysfs_batteryinfo' in line]
        self.assertEqual(rules, ['allow rodin_daemon sysfs_batteryinfo:dir search;'])
        for label in ('sysfs_battery_supply', 'sysfs_usb_supply'):
            self.assertIn(f'allow rodin_daemon {label}:dir search;', source)
            self.assertIn(f'allow rodin_daemon {label}:file rw_file_perms;', source)

    def test_unpacked_parent_permission_matches_aosp(self):
        source = (ROOT / 'android/unpacked/rodin-native.cil').read_text()
        rules = [line.strip() for line in source.splitlines()
                 if line.strip().startswith('(allow ') and 'sysfs_batteryinfo' in line]
        self.assertEqual(rules, ['(allow rodin_daemon sysfs_batteryinfo (dir (search)))'])

    def test_rom_packager_uses_production_adapter_check(self):
        source = (ROOT / 'tools/build-rom-integration-package.py').read_text()
        self.assertIn('tools/check-platform-dex.sh', source)
        self.assertNotIn("'Unexpected DEX'", source)

    def test_ram_parent_label_is_preserved(self):
        ram = '/devices/platform/soc/1c00f000.dvfsrc/mtk-dvfsrc-devfreq/devfreq/mtk-dvfsrc-devfreq'
        source = (ROOT / 'android/unpacked/rodin-native.cil').read_text()
        self.assertNotIn(f'(genfscon sysfs "{ram}" ', source)
        self.assertIn(f'(genfscon sysfs "{ram}/min_freq" ', source)
        self.assertIn(f'(genfscon sysfs "{ram}/max_freq" ', source)
        self.assertIn('(allow rodin_daemon sysfs_dvfsrc_devfreq (file (read getattr open)))', source)
        self.assertIn('(allow mtk_hal_power sysfs_rodin_subsystem_floor (file ', source)


if __name__ == '__main__':
    unittest.main()
