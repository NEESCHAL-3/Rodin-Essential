import importlib.util
from pathlib import Path
import unittest
import tempfile

path = Path(__file__).resolve().parents[1] / 'merge-unpacked-rom-policy.py'
spec = importlib.util.spec_from_file_location('merge_policy', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PolicyMergeTest(unittest.TestCase):
    def test_roundtrip_comments_and_quoted_paths(self):
        original = '; ignored\n(type x)\n(genfscon sysfs "/hello world" (u object_r x ((s0) (s0))))'
        parsed = module.parse(original)
        self.assertEqual(parsed, module.parse('\n'.join(module.render(node) for node in parsed)))

    def test_only_new_domain_excluded_from_selected_rights(self):
        output, count = module.exception('(neverallow forbidden self (capability (sys_ptrace sys_admin dac_override)))')
        self.assertEqual(count, 1)
        self.assertIn('(neverallow forbidden self (capability (sys_admin)))', output)
        self.assertIn('(and (forbidden) (not (rodin_daemon)))', output)
        self.assertIn('(capability (sys_ptrace dac_override))', output)

    def test_other_neverallows_unchanged(self):
        original = '(neverallow domain sysfs (file (write)))'
        output, count = module.exception(original)
        self.assertEqual(count, 0)
        self.assertEqual(output.strip(), original)

    def test_no_numbered_attribute_assumptions(self):
        output, count = module.exception('(neverallow base_typeattr_987 self (capability (sys_ptrace)))')
        self.assertEqual(count, 1)
        self.assertIn('(and (base_typeattr_987) (not (rodin_daemon)))', output)

    def test_malformed_input_rejected(self):
        for text in ('(type x', ')', 'unexpected'):
            with self.assertRaises(ValueError):
                module.parse(text)

    def test_remap_preserves_quoted_paths(self):
        original = '(genfscon sysfs "/devices/sysfs_old" (u object_r sysfs_old ((s0) (s0))))'
        result = module.render(module.remap(module.parse(original)[0], {'sysfs_old': 'sysfs_new'}))
        self.assertIn('"/devices/sysfs_old"', result)
        self.assertIn('object_r sysfs_new', result)

    def test_explicit_inputs_bypass_auto_mapping_detection(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for partition in ('system', 'vendor', 'product'):
                (root / partition / 'etc/selinux').mkdir(parents=True)
            directories, inputs = module.split_inputs(root, explicit=True)
            self.assertEqual(set(directories), {'system', 'vendor', 'product'})
            self.assertEqual(inputs, [])


if __name__ == '__main__':
    unittest.main()
