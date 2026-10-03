import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("stock_kit", Path(__file__).parents[1] / "prepare-stock-rom-test-kit.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ScopedStockPolicyTests(unittest.TestCase):
    def test_only_daemon_is_excluded(self):
        source = (
            "(typeattributeset base_typeattr_455 (and (domain ) (not (dumpstate system_server vold storaged ))))\n"
            "(typeattributeset base_typeattr_471 (not (init vold ) ))\n"
            "(neverallow base_typeattr_455 self (capability (sys_ptrace)))\n"
        )
        changed = module.scoped_exception(source)
        self.assertIn("storaged rodin_daemon", changed)
        self.assertIn("init vold rodin_daemon", changed)
        self.assertEqual(changed.count("rodin_daemon"), 2)
        self.assertIn("(neverallow base_typeattr_455 self (capability (sys_ptrace)))", changed)

    def test_unknown_base_rejected(self):
        with self.assertRaises(ValueError):
            module.scoped_exception("(typeattributeset base_typeattr_455 (domain))")

    def test_reapplying_rejected(self):
        original = (
            "(typeattributeset base_typeattr_455 (and (domain ) (not (dumpstate system_server vold storaged ))))\n"
            "(typeattributeset base_typeattr_471 (not (init vold ) ))\n"
        )
        with self.assertRaises(ValueError):
            module.scoped_exception(module.scoped_exception(original))


if __name__ == "__main__":
    unittest.main()
