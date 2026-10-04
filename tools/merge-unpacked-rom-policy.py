#!/usr/bin/env python3
"""Merge Rodin-only inputs into a copy of the porter's own Android split policy.

No input image/tree is modified. No policy from another ROM is distributed.
Unknown labels, incomplete inputs and new neverallow failures block output.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET


def parse(text):
    tokens = re.findall(r';[^\n]*|"(?:\\.|[^"\\])*"|[()]|[^\s();]+', text)
    roots, stack = [], []
    for token in tokens:
        if token.startswith(';'):
            continue
        if token == '(':
            node = []
            (stack[-1] if stack else roots).append(node)
            stack.append(node)
        elif token == ')':
            if not stack:
                raise ValueError('Unbalanced CIL')
            stack.pop()
        elif stack:
            stack[-1].append(token)
        else:
            raise ValueError('Atom outside CIL expression')
    if stack:
        raise ValueError('Unbalanced CIL')
    return roots


def render(node):
    return '(' + ' '.join(render(item) if isinstance(item, list) else item for item in node) + ')'


def exception(platform):
    """Exclude only the new domain from ptrace/DAC neverallows, not other rights.

    Explicit porter opt-in required. Original attributes and every other domain
    retain their restrictions, including unrelated rights in combined rules.
    """
    roots = parse(platform)
    output, number = [], 0
    for node in roots:
        if len(node) != 4 or node[0] != 'neverallow':
            output.append(node)
            continue
        permissions = node[3]
        if not isinstance(permissions, list) or len(permissions) != 2 or permissions[0] != 'capability' or not isinstance(permissions[1], list):
            output.append(node)
            continue
        selected = [right for right in permissions[1] if right in ('sys_ptrace', 'dac_override')]
        if not selected:
            output.append(node)
            continue
        remaining = [right for right in permissions[1] if right not in selected]
        if remaining:
            output.append(['neverallow', node[1], node[2], ['capability', remaining]])
        name = f'rodin_touch_capability_restriction_{number}'
        number += 1
        original = node[1] if isinstance(node[1], list) else [node[1]]
        output.extend([
            ['typeattribute', name],
            ['typeattributeset', name, ['and', original, ['not', ['rodin_daemon']]]],
            ['neverallow', name, node[2], ['capability', selected]],
        ])
    return '\n'.join(render(node) for node in output) + '\n', number


def write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data, encoding='utf-8', newline='\n')


def remap(node, labels):
    """Remap identifiers, never quoted paths or strings."""
    return [remap(item, labels) if isinstance(item, list) else labels.get(item, item) for item in node]


def split_inputs(rom, explicit=False):
    directories = {}
    for partition in ('system', 'system_ext', 'product', 'vendor', 'odm'):
        choices = [rom / partition / 'etc/selinux']
        if partition == 'system':
            choices.append(rom / 'system/system/etc/selinux')
        found = [path for path in choices if path.is_dir()]
        if len(found) > 1:
            raise ValueError('Ambiguous system extraction layout')
        if found:
            directories[partition] = found[0]
    if not {'system', 'vendor', 'product'} <= directories.keys():
        raise ValueError('Extracted system, vendor and product SELinux directories are required')
    if explicit:
        return directories, []
    version = (directories['vendor'] / 'plat_sepolicy_vers.txt').read_text().strip()
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+)?', version):
        raise ValueError('Invalid vendor policy mapping version')
    inputs = [directories['system'] / 'plat_sepolicy.cil']
    mapping = directories['system'] / f'mapping/{version}.cil'
    if not mapping.is_file():
        raise ValueError('Missing target vendor-version platform mapping: ' + str(mapping))
    inputs.append(mapping)
    compat = mapping.with_name(version + '.compat.cil')
    if compat.is_file():
        inputs.append(compat)
    for partition in ('system_ext', 'product', 'vendor', 'odm'):
        if partition not in directories:
            continue
        directory = directories[partition]
        canonical = directory / f'{partition}_sepolicy.cil'
        if canonical.is_file():
            inputs.append(canonical)
        if partition in ('system_ext', 'product'):
            for suffix in (('.cil', '.compat.cil') if partition == 'system_ext' else ('.cil',)):
                candidate = directory / ('mapping/' + version + suffix)
                if candidate.is_file():
                    inputs.append(candidate)
        if partition == 'vendor':
            candidate = directory / 'plat_pub_versioned.cil'
            if not candidate.is_file():
                raise ValueError('Missing vendor/plat_pub_versioned.cil')
            inputs.append(candidate)
    # Genfs compatibility is independently versioned on newer Android releases.
    genfs_version = directories['vendor'] / 'genfs_labels_version.txt'
    if genfs_version.is_file():
        value = genfs_version.read_text().strip()
        if not re.fullmatch(r'[0-9]+', value):
            raise ValueError('Invalid genfs labels version')
        candidate = directories['system'] / f'plat_sepolicy_genfs_{value}.cil'
        if not candidate.is_file():
            raise ValueError('Missing version-specific genfs policy; provide explicit --inputs')
        inputs.append(candidate)
    return directories, inputs


def failed_rules(text):
    return Counter(line.strip() for line in text.splitlines()
                   if line.lstrip().startswith(('(neverallow ', '(allow ')))


def compile_set(inputs, output, strict, policy_version):
    command = ['secilc', '-m', '-M', 'true', '-G', '-c', str(policy_version), '-v']
    if not strict:
        command.append('-N')
    result = subprocess.run(command + [str(path) for path in inputs] +
                            ['-o', str(output.with_suffix('.policy')), '-f', str(output.with_suffix('.contexts'))],
                            capture_output=True, text=True)
    write(output.with_suffix('.log'), result.stdout + result.stderr)
    return result.returncode, result.stdout + result.stderr


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, required=True, help='Extracted ROM tree with system/product/vendor/...')
    parser.add_argument('--output', type=Path, required=True, help='New directory outside the input ROM')
    parser.add_argument('--kit', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--labels', type=Path, help='Explicit JSON mapping of vendor type names to target ROM names')
    parser.add_argument('--inputs', type=Path, help='JSON list of exact compiler input paths relative to --rom; replaces auto list')
    parser.add_argument('--policy-version', type=int, default=30)
    parser.add_argument('--touch-capability-exception', action='store_true', help='Opt in to a daemon-only native touch capability exception')
    parser.add_argument('--permit-baseline-neverallows', action='store_true', help='Permit pre-existing strict baseline conflicts, never new ones')
    args = parser.parse_args()
    if not shutil.which('secilc'):
        parser.error('Install the target-compatible secilc compiler first')
    rom, output = args.rom.resolve(), args.output.resolve()
    if output == rom or rom in output.parents or output in rom.parents:
        parser.error('Output must be outside and disjoint from the input ROM tree')
    if output.exists():
        parser.error('Output already exists; choose a new directory')
    directories, inputs = split_inputs(rom, explicit=bool(args.inputs))
    if args.inputs:
        supplied = json.loads(args.inputs.read_text())
        if not isinstance(supplied, list) or any(not isinstance(name, str) for name in supplied):
            parser.error('Explicit inputs must be a JSON list of relative paths')
        inputs = [(rom / name).resolve() for name in supplied]
        if not supplied or any(rom not in path.parents or not path.is_file() for path in inputs):
            parser.error('Explicit inputs must be existing files inside the target ROM')
    product_policy = directories['product'] / 'product_sepolicy.cil'
    platform_policy = directories['system'] / 'plat_sepolicy.cil'
    if product_policy not in inputs or platform_policy not in inputs:
        parser.error('Compiler inputs must include canonical platform and product policies')
    baseline_text = '\n'.join(path.read_text() for path in inputs)
    if re.search(r'\(type\s+rodin_(?:daemon|app)\)', baseline_text):
        parser.error('Existing Rodin integration detected: remove its old managed policy block before replacement')
    if args.kit.joinpath('policy/rodin-essential.cil').is_file():
        fragment = (args.kit / 'policy/rodin-essential.cil').read_text()
    else:
        fragment = (args.kit / 'android/unpacked/rodin-native.cil').read_text()
    if args.labels:
        labels = json.loads(args.labels.read_text())
        if not isinstance(labels, dict) or any(not re.fullmatch(r'[A-Za-z0-9_]+', key) or not re.fullmatch(r'[A-Za-z0-9_]+', value) or key.startswith('rodin_') for key, value in labels.items()):
            parser.error('Labels must explicitly map vendor identifiers; Rodin-owned identifiers cannot be remapped')
        fragment = '\n'.join(render(remap(node, labels)) for node in parse(fragment)) + '\n'
    # Diagnose missing labels before emitting any replacement files.
    declared = set(re.findall(r'\((?:type|typeattribute)\s+([A-Za-z0-9_]+)', baseline_text + '\n' + fragment))
    referenced = set()
    for node in parse(fragment):
        if node and node[0] in ('allow', 'allowx', 'typetransition'):
            referenced.update(item for item in node[1:3] if isinstance(item, str) and item != 'self')
    missing = sorted(referenced - declared)
    if missing:
        parser.error('Target labels differ or inputs are incomplete: ' + ', '.join(missing) + '. Supply a reviewed --labels JSON map, not guessed grants.')
    output.mkdir(parents=True)
    validation = output / 'validation'
    validation.mkdir()
    baseline_code, baseline_log = compile_set(inputs, validation / 'baseline-strict', True, args.policy_version)
    if baseline_code and (not args.permit_baseline_neverallows or not failed_rules(baseline_log)):
        raise SystemExit('Baseline strict policy failed. See validation/baseline-strict.log; no deployable files emitted.')
    platform = platform_policy.read_text()
    exception_count = 0
    if args.touch_capability_exception:
        platform, exception_count = exception(platform)
    work = output / 'validation/target-policy'
    edited_inputs = []
    for path in inputs:
        target = work / path.relative_to(rom)
        content = path.read_text()
        if path == platform_policy:
            content = platform
        if path == product_policy:
            content += '\n; BEGIN RODIN ESSENTIAL POLICY\n' + fragment + '\n; END RODIN ESSENTIAL POLICY\n'
        write(target, content)
        edited_inputs.append(target)
    edited_code, edited_log = compile_set(edited_inputs, validation / 'edited-strict', True, args.policy_version)
    new_failures = failed_rules(edited_log) - failed_rules(baseline_log)
    if edited_code and (not args.permit_baseline_neverallows or not failed_rules(edited_log) or new_failures):
        raise SystemExit('Edited policy failed or introduced strict conflicts. See validation/edited-strict.log; no deployable files emitted.')
    if edited_code:
        base_runtime, _ = compile_set(inputs, validation / 'baseline-runtime', False, args.policy_version)
        edited_runtime, _ = compile_set(edited_inputs, validation / 'edited-runtime', False, args.policy_version)
        if base_runtime or edited_runtime:
            raise SystemExit('Runtime policy compile failed; no deployable files emitted.')
    # Validate contexts and certificate mapping before emitting deployable files.
    files = output / 'copy-to-extracted-rom'
    product = directories['product']
    contexts = product / 'product_file_contexts'
    addition_root = args.kit / 'policy'
    file_additions = '/product/bin/rodin_daemon u:object_r:rodin_daemon_exec:s0\n/data/system/rodin-essential(/.*)? u:object_r:rodin_daemon_data_file:s0\n'
    contexts_text = (contexts.read_text() if contexts.exists() else '')
    if 'rodin_daemon_exec' in contexts_text or 'rodin_daemon_data_file' in contexts_text:
        raise SystemExit('Existing Rodin file contexts need review; no deployable files emitted')
    merged_contexts = contexts_text + '\n' + file_additions
    seapp = product / 'product_seapp_contexts'
    seapp_text = seapp.read_text() if seapp.exists() else ''
    if 'io.github.neeschal.rodinessential' in seapp_text:
        raise SystemExit('Existing seapp entry needs review; output is incomplete and must not be copied')
    mac = product / 'product_mac_permissions.xml'
    root = ET.fromstring(mac.read_text()) if mac.exists() else ET.Element('policy')
    for package in root.iter('package'):
        if package.get('name') == 'io.github.neeschal.rodinessential':
            raise SystemExit('Existing MAC package entry needs review; output is incomplete and must not be copied')
    certificate_hex = (addition_root / 'certificate.der.hex').read_text().strip()
    bytes.fromhex(certificate_hex)
    signer = next((item for item in root.findall('signer') if item.get('signature', '').lower() == certificate_hex.lower()), None)
    if signer is None:
        signer = ET.SubElement(root, 'signer', {'signature': certificate_hex})
    package = ET.SubElement(signer, 'package', {'name': 'io.github.neeschal.rodinessential'})
    ET.SubElement(package, 'seinfo', {'value': 'rodin_essential'})
    write(validation / 'product_file_contexts', merged_contexts)
    if not shutil.which('sefcontext_compile'):
        raise SystemExit('Install sefcontext_compile to validate target file contexts; no deployable files emitted')
    compiled_policy = validation / ('edited-strict.policy' if edited_code == 0 else 'edited-runtime.policy')
    result = subprocess.run(['sefcontext_compile', '-p', str(compiled_policy), '-o', str(validation / 'product_file_contexts.bin'), str(validation / 'product_file_contexts')], capture_output=True, text=True)
    write(validation / 'file-contexts.log', result.stdout + result.stderr)
    if result.returncode:
        raise SystemExit('File-context validation failed; no deployable files emitted')
    for path in (platform_policy, product_policy):
        relative = path.relative_to(rom)
        if path == platform_policy and not args.touch_capability_exception:
            continue
        write(files / relative, (work / relative).read_text())
    write(files / contexts.relative_to(rom), merged_contexts)
    write(files / seapp.relative_to(rom), seapp_text + '\nuser=_app seinfo=rodin_essential name=io.github.neeschal.rodinessential domain=rodin_app type=app_data_file levelFrom=all\n')
    write(files / mac.relative_to(rom), ET.tostring(root, encoding='unicode') + '\n')
    caches = []
    for partition in ('odm', 'vendor'):
        if partition in directories:
            for path in sorted(directories[partition].glob('precompiled_sepolicy*')):
                if path.name == 'precompiled_sepolicy' or path.name.startswith('precompiled_sepolicy.') and path.name.endswith('.sha256'):
                    caches.append(path.relative_to(rom).as_posix())
    write(output / 'REMOVE-AFTER-VALIDATION.txt', '\n'.join(caches) + '\n')
    report = {'strictPass': edited_code == 0, 'baselineStrictPass': baseline_code == 0,
              'newStrictFailureRules': list(new_failures), 'touchCapabilityExceptions': exception_count,
              'inputSha256': {path.relative_to(rom).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs},
              'deviceBootTested': False}
    write(output / 'VALIDATION.json', json.dumps(report, indent=2) + '\n')
    write(output / 'SHA256SUMS', ''.join(f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(output).as_posix()}\n' for path in sorted(files.rglob('*')) if path.is_file()))
    write(output / 'READY.txt', 'Policy generated from this target ROM. Merge payload, metadata and listed policy files; rebuild and boot-test.\n')
    print('TARGET_ROM_POLICY_MERGE=PASS; see READY.txt and VALIDATION.json')


if __name__ == '__main__':
    main()
