import importlib.util
from pathlib import Path
import unittest
import subprocess
import sys
import tempfile

spec = importlib.util.spec_from_file_location("touch_policy", Path(__file__).parents[1] / "prepare-aosp-touch-policy.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

DOMAIN = """neverallow {
  domain
  -vold
} self:global_capability_class_set sys_ptrace;
define(`dac_override_allowed', `{
  init
  vold
}')
neverallow ~dac_override_allowed self:global_capability_class_set dac_override;
"""


class PolicyPreparationTests(unittest.TestCase):
    def test_scoped_and_idempotent(self):
        updated = module.prepare("attribute domain;\n", DOMAIN)
        self.assertIn("  -rodin_native_touch_access\n", updated[1])
        self.assertIn("  rodin_native_touch_access\n", updated[1])
        self.assertEqual(module.prepare(*updated), updated)
        self.assertIn("neverallow ~dac_override_allowed", updated[1])

    def test_unknown_rules_rejected(self):
        with self.assertRaises(ValueError):
            module.prepare("", "neverallow domain self:capability sys_ptrace;")

    def test_partial_patch_rejected(self):
        with self.assertRaises(ValueError):
            module.prepare("attribute rodin_native_touch_access;", DOMAIN)

    def test_ambiguous_rules_rejected(self):
        with self.assertRaises(ValueError):
            module.prepare("", DOMAIN + DOMAIN)

    def test_cli_preview_does_not_write(self):
        with tempfile.TemporaryDirectory() as directory:
            policy = Path(directory) / "system/sepolicy"
            (policy / "public").mkdir(parents=True)
            (policy / "private").mkdir()
            attributes = policy / "public/attributes"
            domain = policy / "private/domain.te"
            attributes.write_text("attribute domain;\n")
            domain.write_text(DOMAIN)
            result = subprocess.run([sys.executable, module.__file__, directory], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("Preview only", result.stdout)
            self.assertEqual(attributes.read_text(), "attribute domain;\n")
            self.assertEqual(domain.read_text(), DOMAIN)

    def test_cli_apply_is_idempotent(self):
        with tempfile.TemporaryDirectory() as directory:
            policy = Path(directory) / "system/sepolicy"
            (policy / "public").mkdir(parents=True)
            (policy / "private").mkdir()
            attributes = policy / "public/attributes"
            domain = policy / "private/domain.te"
            attributes.write_text("attribute domain;\n")
            domain.write_text(DOMAIN)
            for _ in range(2):
                result = subprocess.run([sys.executable, module.__file__, directory, "--apply"], capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(attributes.read_text().count("attribute rodin_native_touch_access;"), 1)
            self.assertIn("expandattribute rodin_native_touch_access false;", attributes.read_text())


if __name__ == "__main__":
    unittest.main()
