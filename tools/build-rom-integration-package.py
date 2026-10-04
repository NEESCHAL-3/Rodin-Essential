#!/usr/bin/env python3
"""Package only Rodin integration inputs from an already verified module ZIP."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import zipfile


def write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8', newline='\n')


def build(module, output, apksigner):
    project = Path(__file__).resolve().parents[1]
    stage = output / 'rom-integration'
    if stage.exists():
        raise ValueError('Output stage already exists; choose a new directory')
    stage.mkdir(parents=True)
    payload = {}
    with zipfile.ZipFile(module) as archive:
        assert archive.testzip() is None
        prop = archive.read('module.prop').decode()
        version = re.search(r'^version=v(\d+\.\d+\.\d+)$', prop, re.M)[1]
        code = int(re.search(r'^versionCode=(\d+)$', prop, re.M)[1])
        for source, relative in {
            'app/RodinEssential.apk': 'product/app/RodinEssential/RodinEssential.apk',
            'bin/rodin_daemon': 'product/bin/rodin_daemon',
            'bin/rodin_ctl': 'product/bin/rodin_ctl',
        }.items():
            data = archive.read(source)
            target = stage / 'copy-to-extracted-rom' / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            payload[source] = hashlib.sha256(data).hexdigest()
    apk = stage / 'copy-to-extracted-rom/product/app/RodinEssential/RodinEssential.apk'
    with zipfile.ZipFile(io.BytesIO(apk.read_bytes())) as archive:
        assert not any(name.endswith('.dex') for name in archive.namelist()), 'Unexpected DEX'
    result = subprocess.run([str(apksigner), 'verify', '--print-certs-pem', str(apk)], check=True, capture_output=True, text=True)
    certificates = re.findall(r'-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----', result.stdout, re.S)
    assert len(certificates) == 1, 'Expected one signing certificate'
    der = base64.b64decode(certificates[0])
    signer_hash = hashlib.sha256(der).hexdigest()
    assert signer_hash == (project / 'android/package/release-cert.sha256').read_text().strip(), 'Unexpected signer'
    write(stage / 'policy/certificate.der.hex', der.hex() + '\n')
    write(stage / 'policy/product_mac_permissions.additions.xml',
          '<policy><signer signature="' + der.hex() + '"><package name="io.github.neeschal.rodinessential"><seinfo value="rodin_essential"/></package></signer></policy>\n')
    for source, destination in {
        'android/unpacked/rodin-native.cil': 'policy/rodin-essential.cil',
        'android/aosp/rodin_daemon.rc': 'copy-to-extracted-rom/product/etc/init/rodin_daemon.rc',
        'tools/merge-unpacked-rom-policy.py': 'tools/merge-unpacked-rom-policy.py',
        'docs/UNPACKED_ROM_PORTER_GUIDE.md': 'FULL-GUIDE.md',
    }.items():
        write(stage / destination, (project / source).read_text())
    contexts = (
        '/product/bin/rodin_daemon u:object_r:rodin_daemon_exec:s0\n'
        '/data/system/rodin-essential(/.*)? u:object_r:rodin_daemon_data_file:s0\n')
    write(stage / 'policy/product_file_contexts.additions', contexts)
    write(stage / 'policy/product_seapp_contexts.additions',
          'user=_app seinfo=rodin_essential name=io.github.neeschal.rodinessential domain=rodin_app type=app_data_file levelFrom=all\n')
    write(stage / 'metadata/file_contexts.additions', contexts +
          '/product/bin/rodin_ctl u:object_r:system_file:s0\n'
          '/product/app/RodinEssential(/.*)? u:object_r:system_file:s0\n'
          '/product/etc/init/rodin_daemon\\.rc u:object_r:system_file:s0\n')
    entries = ['product/app/RodinEssential 0 0 0755']
    for path in sorted((stage / 'copy-to-extracted-rom').rglob('*')):
        if path.is_file():
            relative = path.relative_to(stage / 'copy-to-extracted-rom').as_posix()
            entries.append(f"{relative} 0 0 {'0755' if path.parent.name == 'bin' else '0644'}")
    write(stage / 'metadata/fs_config.additions', '\n'.join(entries) + '\n')
    write(stage / 'README.txt',
          f'Rodin Essential v{version} — ROM Integration\n\n'
          'Not flashable. For extracted ROM images on Rodin devices.\n'
          'Read FULL-GUIDE.md. Only Rodin payloads and policy additions are included.\n'
          'Run the included merger against YOUR ROM policy before copying generated changes.\n'
          'Never replace a whole ROM policy with policy from another build.\n'
          'Root-manager-free operation uses Android init and dedicated SELinux domains.\n')
    write(stage / 'PACKAGE.json', json.dumps({
        'version': version, 'versionCode': code, 'protocol': '13.6',
        'apkSignerSha256': signer_hash, 'payload': payload,
        'policyScope': 'Rodin-only additions; target policies are not included',
        'sourceModuleSha256': hashlib.sha256(module.read_bytes()).hexdigest(),
    }, indent=2) + '\n')
    write(stage / 'SHA256SUMS', ''.join(
        f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(stage).as_posix()}\n'
        for path in sorted(stage.rglob('*')) if path.is_file()))
    package = output / f'Rodin-Essential-ROM-Integration-v{version}.zip'
    with zipfile.ZipFile(package, 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(stage.rglob('*')):
            if not path.is_file():
                continue
            item = zipfile.ZipInfo(path.relative_to(stage).as_posix())
            item.create_system = 3
            item.external_attr = (0o100755 if path.parent.name == 'bin' else 0o100644) << 16
            item.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(item, path.read_bytes())
    write(package.with_suffix('.zip.sha256'), hashlib.sha256(package.read_bytes()).hexdigest() + '  ' + package.name + '\n')
    print(package)
    return package


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--module', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apksigner', type=Path, required=True)
    args = parser.parse_args()
    build(args.module, args.output, args.apksigner)
