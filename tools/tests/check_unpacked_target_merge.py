#!/usr/bin/env python3
"""Optional full-policy regression using a local, unmodified target fixture.

Fixture is not shipped in the ROM integration archive. Inputs are never edited.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys


def hashes(root):
    return {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in root.rglob('*') if path.is_file()}


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--fixture', type=Path, required=True, help='Local policy/<partition> fixture')
parser.add_argument('--kit', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=False)
original = hashes(args.fixture)
rom = args.output / 'rom'
for partition in args.fixture.iterdir():
    if partition.is_dir():
        shutil.copytree(partition, rom / partition.name / 'etc/selinux')
before = hashes(rom)
tool = args.kit / 'tools/merge-unpacked-rom-policy.py'
command = [sys.executable, str(tool), '--rom', str(rom), '--kit', str(args.kit),
           '--output', str(args.output / 'merged'), '--touch-capability-exception',
           '--permit-baseline-neverallows']
result = subprocess.run(command, capture_output=True, text=True)
print(result.stdout + result.stderr)
assert result.returncode == 0, 'Full-target merge failed'
merged = args.output / 'merged'
assert (merged / 'READY.txt').is_file()
report = json.loads((merged / 'VALIDATION.json').read_text())
assert not report['newStrictFailureRules']
assert report['touchCapabilityExceptions'] > 0
assert hashes(rom) == before and hashes(args.fixture) == original, 'Input policy mutated'
product_relative = 'product/etc/selinux/product_sepolicy.cil'
text = (merged / 'copy-to-extracted-rom' / product_relative).read_text()
assert text.startswith((rom / product_relative).read_text()), 'Unrelated product policy changed'
assert len((merged / 'REMOVE-AFTER-VALIDATION.txt').read_text().splitlines()) == 3
assert (merged / 'validation/file-contexts.log').is_file()
# Missing target types are diagnosed, never replaced by generic/broad grants.
labels = args.output / 'missing-labels.json'
labels.write_text(json.dumps({'sysfs_ged': 'nonexistent_target_label'}))
bad_command = command[:]
bad_command[bad_command.index('--output') + 1] = str(args.output / 'rejected')
result = subprocess.run(bad_command + ['--labels', str(labels)], capture_output=True, text=True)
assert result.returncode != 0 and 'nonexistent_target_label' in result.stderr
assert not (args.output / 'rejected/READY.txt').exists()
assert not (args.output / 'rejected/copy-to-extracted-rom').exists()
assert hashes(rom) == before
print('FULL_TARGET_MERGE_INPUT_PRESERVATION_AND_REJECTION=PASS')
