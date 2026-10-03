#!/usr/bin/env python3
"""Build local test packages against the inspected stock Rodin EEA policy.

Never edits the supplied ROM tree or publishes anything. This is deliberately
target-specific: source templates are not a universal OEM policy replacement.
"""
import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from collections import Counter


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*command):
    return subprocess.run(command, check=True, capture_output=True, text=True).stdout


def write(path, contents):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8", newline="\n")


def archive(directory, destination):
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as output:
        for path in sorted(directory.rglob("*")):
            if path.is_file():
                item = zipfile.ZipInfo(path.relative_to(directory).as_posix())
                item.create_system = 3
                executable = path.suffix == ".sh" or path.parent.name == "bin"
                item.external_attr = ((0o100755 if executable else 0o100644) << 16)
                item.compress_type = zipfile.ZIP_DEFLATED
                output.writestr(item, path.read_bytes())


def scoped_exception(platform):
    # Exact observed stock rules. Do not broadly disable or remove neverallows.
    ptrace = "(typeattributeset base_typeattr_455 (and (domain ) (not (dumpstate system_server vold storaged ))))"
    dac = re.compile(r"\(typeattributeset base_typeattr_471 \(not \(([^()]*)\) \)\)")
    if platform.count(ptrace) != 1 or len(dac.findall(platform)) != 1:
        raise ValueError("Not the inspected stock platform policy layout")
    platform = platform.replace(ptrace, ptrace.replace("storaged ", "storaged rodin_daemon "))
    return dac.sub(lambda match: match[0].replace(match[1], match[1] + "rodin_daemon "), platform)


def compile_policy(policy, validation, name, strict):
    inputs = [
        "system/plat_sepolicy.cil", "system/mapping/202404.cil",
        "system/mapping/202404.compat.cil", "system_ext/system_ext_sepolicy.cil",
        "system_ext/mapping/202404.cil", "system_ext/mapping/202404.compat.cil",
        "product/product_sepolicy.cil", "product/mapping/202404.cil",
        "vendor/plat_pub_versioned.cil", "vendor/vendor_sepolicy.cil", "odm/odm_sepolicy.cil",
    ]
    command = ["secilc", "-m", "-M", "true", "-G", "-c", "30"]
    if strict:
        command.append("-v")  # Report every matching allow, not only the first four.
    if not strict:
        command.append("-N")  # Android init's runtime mode, not a neverallow pass.
    command += [str(policy / item) for item in inputs]
    command += ["-o", str(validation / (name + ".policy")), "-f", str(validation / (name + ".contexts"))]
    result = subprocess.run(command, capture_output=True, text=True)
    write(validation / (name + ".log"), result.stdout + result.stderr)
    return result.returncode


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--policy", type=Path, required=True, help="Unmodified extracted stock policy directories")
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--binaries", type=Path, required=True)
    parser.add_argument("--build-tools", type=Path, required=True)
    parser.add_argument("--strip", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    project = Path(__file__).resolve().parents[1]
    policy = args.policy.resolve()
    destination = args.output.resolve()
    if destination.exists():
        parser.error("Output already exists; choose a new directory")
    if (policy / "vendor/plat_sepolicy_vers.txt").read_text().strip() != "202404":
        parser.error("Wrong vendor mapping version for the inspected stock base")
    platform = scoped_exception((policy / "system/plat_sepolicy.cil").read_text())
    fragment = (project / "android/unpacked/rodin-native.cil").read_text()
    if "(type rodin_daemon)" in (policy / "system/plat_sepolicy.cil").read_text():
        parser.error("Input is already modified; use original stock policies")
    for tool in ("secilc", "readelf"):
        if not shutil.which(tool):
            parser.error("Missing tool: " + tool)
    signer = args.build_tools / "apksigner"
    badging = run(str(args.build_tools / "aapt2"), "dump", "badging", str(args.apk)).splitlines()[0]
    metadata = re.search(r"name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", badging)
    if not metadata or metadata.groups() != ("io.github.neeschal.rodinessential", "11804", "1.18.4"):
        parser.error("Expected synchronized v1.18.4 APK")
    run(str(signer), "verify", str(args.apk))
    run(str(args.build_tools / "zipalign"), "-c", "-P", "16", "4", str(args.apk))
    with zipfile.ZipFile(args.apk) as apk:
        if any(re.search(r"(^|/)classes[0-9]*\.dex$", name) for name in apk.namelist()):
            parser.error("APK contains DEX")
    certificates = run(str(signer), "verify", "--print-certs-pem", str(args.apk))
    certs = re.findall(r"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----", certificates, re.S)
    if len(certs) != 1:
        parser.error("A single verified APK signer is required")
    der = base64.b64decode(re.sub(r"\s", "", certs[0]), validate=True)
    destination.mkdir(parents=True)
    staged_policy = destination / "validation/patched-policy-inputs"
    shutil.copytree(policy, staged_policy)
    write(staged_policy / "system/plat_sepolicy.cil", platform)
    write(staged_policy / "product/product_sepolicy.cil", (policy / "product/product_sepolicy.cil").read_text() + "\n" + fragment)
    validation = destination / "validation"
    statuses = {}
    # Keep strict stock failures visible; runtime-mode compilation is a separate result.
    for label, tree in (("stock", policy), ("rodin", staged_policy)):
        for strict in (False, True):
            name = label + ("-strict" if strict else "-runtime-mode")
            statuses[name] = compile_policy(tree, validation, name, strict)
            print(name + "=" + ("PASS" if statuses[name] == 0 else "FAIL"), flush=True)
    if statuses["stock-runtime-mode"] or statuses["rodin-runtime-mode"]:
        raise SystemExit("Complete split-policy compilation failed; no package created")
    def failed_rules(name):
        return Counter(line.strip() for line in (validation / name).read_text().splitlines()
                       if line.lstrip().startswith(("(neverallow ", "(allow ")))
    new_failures = failed_rules("rodin-strict.log") - failed_rules("stock-strict.log")
    if new_failures:
        write(validation / "new-strict-failures.txt", "\n".join(new_failures) + "\n")
        raise SystemExit("New strict policy failures were introduced; no package created")
    rom = destination / "rom-kit"
    files = rom / "copy-to-extracted-rom"
    product = files / "product"
    install_files = {
        "product/app/RodinEssential/RodinEssential.apk": args.apk,
        "product/bin/rodin_daemon": args.binaries / "rodin_daemon",
        "product/bin/rodin_ctl": args.binaries / "rodin_ctl",
    }
    for relative, source in install_files.items():
        target = files / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        if target.parent.name == "bin":
            run(str(args.strip), "--strip-unneeded", str(target))
            elf = run("readelf", "-h", str(target))
            if "AArch64" not in elf:
                raise ValueError("Non-ARM64 payload")
            loads = re.findall(r"^\s*LOAD.*?\s(0x[0-9a-fA-F]+)\s*$", run("readelf", "-lW", str(target)), re.M)
            if not loads or any(int(alignment, 16) < 16384 for alignment in loads):
                raise ValueError("Binary lacks 16KB alignment")
    write(product / "etc/init/rodin_daemon.rc", (project / "android/aosp/rodin_daemon.rc").read_text())
    for relative in ("system/plat_sepolicy.cil", "product/product_sepolicy.cil"):
        runtime_relative = "system/system/etc/selinux/plat_sepolicy.cil" if relative.startswith("system/") else "product/etc/selinux/product_sepolicy.cil"
        target = files / runtime_relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(staged_policy / relative, target)
    labels = (
        "/product/bin/rodin_daemon u:object_r:rodin_daemon_exec:s0\n"
        "/product/bin/rodin_ctl u:object_r:system_file:s0\n"
        "/product/app/RodinEssential(/.*)? u:object_r:system_file:s0\n"
        "/product/etc/init/rodin_daemon\\.rc u:object_r:system_file:s0\n"
        "/data/system/rodin-essential(/.*)? u:object_r:rodin_daemon_data_file:s0\n"
    )
    write(product / "etc/selinux/product_file_contexts", (policy / "product/product_file_contexts").read_text() + "\n" + labels)
    seapp = "user=_app seinfo=rodin_essential name=io.github.neeschal.rodinessential domain=rodin_app type=app_data_file levelFrom=all\n"
    write(product / "etc/selinux/product_seapp_contexts", (policy / "product/product_seapp_contexts").read_text() + "\n" + seapp)
    xml = ET.parse(policy / "product/product_mac_permissions.xml")
    signing = ET.SubElement(xml.getroot(), "signer", {"signature": der.hex()})
    package = ET.SubElement(signing, "package", {"name": "io.github.neeschal.rodinessential"})
    ET.SubElement(package, "seinfo", {"value": "rodin_essential"})
    write(product / "etc/selinux/product_mac_permissions.xml", '<?xml version="1.0" encoding="utf-8"?>\n' + ET.tostring(xml.getroot(), encoding="unicode") + "\n")
    write(rom / "metadata/file_contexts.additions", labels)
    entries = ["product/app/RodinEssential 0 0 0755", "product/bin 0 0 0755"]
    for path in sorted(files.rglob("*")):
        if path.is_file():
            relative = path.relative_to(files).as_posix()
            entries.append(f"{relative} 0 0 {'0755' if path.parent.name == 'bin' else '0644'}")
    write(rom / "metadata/fs_config.additions", "\n".join(entries) + "\n")
    remove = ["odm/etc/selinux/precompiled_sepolicy", "odm/etc/selinux/precompiled_sepolicy.plat_sepolicy_and_mapping.sha256", "odm/etc/selinux/precompiled_sepolicy.system_ext_sepolicy_and_mapping.sha256"]
    write(rom / "REMOVE-BEFORE-COPY.txt", "\n".join(remove) + "\n")
    write(rom / "RodinEssential.x509.pem", "-----BEGIN CERTIFICATE-----\n" + certs[0] + "\n-----END CERTIFICATE-----\n")
    shutil.copyfile(project / "docs/STOCK_ROM_PORTER_GUIDE.md", rom / "FULL-GUIDE.md")
    write(rom / "README.txt", (
        "Rodin Essential v1.18.4 — LOCAL STOCK ROM TEST KIT\n\n"
        "Target ONLY: Rodin EEA OS3.0.302.0.WOJEUXM Android 16. NOT FLASHABLE.\n"
        "Read FULL-GUIDE.md first: it explains copy destinations, vendor CIL and\n"
        "which metadata files are used by the kitchen, not copied to the phone.\n"
        "1. Extract matching ROM images with your ROM kitchen.\n"
        "2. Remove ONLY the three extracted-ODM cache files in REMOVE-BEFORE-COPY.txt.\n"
        "3. Merge copy-to-extracted-rom contents into the kitchen's extracted tree.\n"
        "   system/system/etc is the stock system-as-root extraction layout; if the\n"
        "   kitchen uses a flattened system directory, map it to system/etc instead.\n"
        "4. Merge metadata/file_contexts.additions and fs_config.additions into the\n"
        "   kitchen's ORIGINAL metadata. Keep all unrelated entries. Resolve duplicate\n"
        "   paths. Apply rodin_daemon_exec to the binary during image rebuild.\n"
        "5. Rebuild affected EROFS partitions with original ownership, modes, xattrs,\n"
        "   mount points, partition limits and the port's established AVB procedure.\n"
        "6. Boot-test with SELinux enforcing; verify every feature and restoration.\n\n"
        "No /data/adb dependency or app root grant is used by the baked service.\n"
        "The normal app uses a certificate-bound rodin_app domain. Both local test\n"
        "packages use the same current Windows test signing key, NOT the old public\n"
        "release key. Existing ROM APKs signed differently cannot be updated in place.\n"
        "Kernel-dependent controls, especially bypass, require compatible nodes.\n"
        "1000 Hz output is not a claim of 1000 physical panel scans per second.\n\n"
        "Validation: full split CIL compiles in Android runtime mode (-N); this is NOT\n"
        "a strict neverallow pass. Unmodified stock also fails strict checking.\n"
        "Only rodin_daemon is excluded from the two stock capability restrictions;\n"
        "remaining neverallows are retained. See validation report. No target boot or\n"
        "feature tests have been performed. Do not use this as a universal port patch.\n"
    ))
    module = destination / "module"
    module.mkdir()
    for name in ("customize.sh", "service.sh", "action.sh", "uninstall.sh", "module.prop", "skip_mount"):
        source = project / "android/kernelsu-next" / name
        write(module / name, source.read_text())
        if name.endswith(".sh"):
            run("bash", "-n", str(module / name))
    for relative, source in {
        "app/RodinEssential.apk": product / "app/RodinEssential/RodinEssential.apk",
        "bin/rodin_daemon": product / "bin/rodin_daemon",
        "bin/rodin_ctl": product / "bin/rodin_ctl",
    }.items():
        target = module / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    write(module / "LOCAL-TEST.txt", "Local v1.18.4 test package; not an official release. Uses the current Windows test certificate. Test before publishing.\n")
    # Byte-identical APK and native executables, even after strip.
    pairs = [(module / "app/RodinEssential.apk", product / "app/RodinEssential/RodinEssential.apk")]
    pairs += [(module / "bin" / name, product / "bin" / name) for name in ("rodin_daemon", "rodin_ctl")]
    assert all(digest(left) == digest(right) for left, right in pairs)
    report = {
        "target": "rodin_eea OS3.0.302.0.WOJEUXM Android 16", "version": "1.18.4",
        "versionCode": 11804, "protocol": "13.6", "apkSignerSha256": hashlib.sha256(der).hexdigest(),
        "policyCompileExitCodes": statuses, "strictNeverallowPass": statuses["rodin-strict"] == 0,
        "newStrictFailureRules": list(new_failures),
        "deviceBootTested": False, "deviceFeaturesTested": False,
        "payload": {left.relative_to(module).as_posix(): digest(left) for left, _ in pairs},
        "inputPolicySha256": {path.relative_to(policy).as_posix(): digest(path) for path in sorted(policy.rglob("*")) if path.is_file()},
    }
    write(destination / "VALIDATION.json", json.dumps(report, indent=2) + "\n")
    shutil.copyfile(destination / "VALIDATION.json", rom / "VALIDATION.json")
    for stage in (rom, module):
        write(stage / "SHA256SUMS", "".join(f"{digest(path)}  {path.relative_to(stage).as_posix()}\n" for path in sorted(stage.rglob("*")) if path.is_file()))
    rom_zip = destination / "Rodin-Essential-Stock-EEA-v1.18.4-local-test.zip"
    module_zip = destination / "Rodin-Essential-KernelSU-Next-Magisk-v1.18.4-local-test.zip"
    archive(rom, rom_zip)
    archive(module, module_zip)
    for path in (rom_zip, module_zip):
        with zipfile.ZipFile(path) as zipped:
            if zipped.testzip() is not None:
                raise ValueError("ZIP integrity failure")
        write(path.with_suffix(path.suffix + ".sha256"), digest(path) + "  " + path.name + "\n")
        print(str(path), flush=True)


if __name__ == "__main__":
    main()
